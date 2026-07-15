function [res,meta] = ts_simulate_ibr_hybrid(case_data,devices,x0,y0,opt)
%TS_SIMULATE_IBR_HYBRID Event supervisor for the shared SG+IBR composite TS.
%   This function owns event-grid orchestration only. Every differential step
%   is delegated to stability.ts_step_composite, the same coupled all-KCL
%   trapezoidal step used by ts_simulate_composite. SG and all IBR devices stay
%   in one composite DAE throughout fault, trip, mode transfer, and reclose.
%
%   Scheduled API (opt.ibr_event_schedule): fault_on, fault_clear, sg_trip,
%   and sg_on (earliest reclose-request time). State/mode transitions are
%   transactional: device-owned transfer callbacks and the right-limit KCL
%   solve must both succeed before the candidate context is committed.
%
%   Classification: event ordering and rollback are PROJECT_DERIVED;
%   Yfault=Ypre+e_f*e_f'/Zf is SOURCE_DEFINED; synchronism thresholds and
%   delays are CASE_DEFINED in case_data. No external solver is used.

arguments
    case_data struct
    devices struct
    x0 (:,1) double
    y0 (:,1) double
    opt struct
end

[res,meta] = empty_result(opt);
try
    [dae,u,ec,sched,settings] = initialize(case_data,devices,x0,y0,opt);
catch me
    [res,meta] = fail(res,meta,'ts_simulate_ibr_hybrid:badInput',me);
    return;
end

Ypre = dae.Ynet;
Yfault = Ypre;
if sched.enabled
    fp = sched.fault_bus_position;
    Yfault(fp,fp) = Yfault(fp,fp)+1/sched.Zf;
end
Ypost = Ypre;
Ycurr = Ypre;
topology = 'pre';
x = x0(:);
y = y0(:);
t = 0.0;
active = stability.ts_dynamic_state_indices(dae,ec);

samples = new_samples(x,y,ec,active,topology);
event_log = repmat(new_event_log('',NaN),0,1);
status_log = stability.ibr_status_snapshot('initial_configuration',0,dae,ec,active, ...
    kcl_norm(dae,0,x,y,Ycurr,u,ec));
events = schedule_events(sched);
event_cursor = 1;
pending_reclose = false;
good_since = NaN;
last_guard = struct();
actual_reclose = NaN;
reclose_status = 'NOT_REQUESTED';
t_trip = NaN;
converged = true;
failure_id = '';
failure_reason = '';
total_iterations = 0;
max_residual = 0;
step_iterations = [];
step_residuals = [];

while t < settings.t_end-settings.event_tol
    target = min(t+settings.dt,settings.t_end);
    if event_cursor <= numel(events)
        target = min(target,events(event_cursor).t);
    end
    if pending_reclose
        target = min(target,sched.sg_on+settings.sync_timeout);
        if isfinite(good_since)
            target = min(target,good_since+settings.sync_dwell);
        end
    end
    h = target-t;
    if h <= settings.event_tol
        t = target;
    else
        active = stability.ts_dynamic_state_indices(dae,ec);
        step_opt = struct('newton_tol',settings.newton_tol, ...
            'max_iter',settings.max_iter,'fd_eps',settings.fd_eps, ...
            'verbose',settings.verbose,'full_kcl',true,'t_now',t);
        step = stability.ts_step_composite(x,y,h,dae,Ycurr,u,ec,active,step_opt);
        total_iterations = total_iterations+step.iterations;
        max_residual = max(max_residual,step.residual_norm);
        step_iterations(end+1)=step.iterations; %#ok<AGROW>
        step_residuals(end+1)=step.residual_norm; %#ok<AGROW>
        if ~step.converged || ~step.finite
            converged = false;
            failure_id = 'ts_simulate_ibr_hybrid:stepNewton';
            failure_reason = sprintf('Composite step failed at t=%.15g (residual %.3e).', ...
                target,step.residual_norm);
            break;
        end
        x = step.x_full;
        y = step.y_full;
        t = target;
        is_event_left = event_cursor<=numel(events) && ...
            abs(t-events(event_cursor).t)<=settings.event_tol;
        side = ternary(is_event_left,'left','continuous');
        samples = append_sample(samples,t,x,y,ec,active,topology,side);
    end

    % Apply every scheduled transition at this timestamp in deterministic order.
    event_applied = false;
    while event_cursor<=numel(events) && ...
            abs(events(event_cursor).t-t)<=settings.event_tol
        ev = events(event_cursor);
        pre_norm = kcl_norm(dae,t,x,y,Ycurr,u,ec);
        switch ev.type
        case 'fault_on'
            [ok,y_new,reason,right_norm] = right_limit(x,y,Yfault,dae,u,ec,t,settings.kcl_tol);
            log = new_event_log(ev.type,t);
            log.pre_kcl_norm = pre_norm; log.right_kcl_norm = right_norm;
            if ok
                y = y_new; Ycurr = Yfault; topology = 'fault';
                log.applied = true; log.details = 'Fault admittance committed.';
            else
                [converged,failure_id,failure_reason,log] = transition_failure( ...
                    'ts_simulate_ibr_hybrid:rightLimit',reason,log);
            end
        case 'fault_clear'
            [ok,y_new,reason,right_norm] = right_limit(x,y,Ypost,dae,u,ec,t,settings.kcl_tol);
            log = new_event_log(ev.type,t);
            log.pre_kcl_norm = pre_norm; log.right_kcl_norm = right_norm;
            if ok
                y = y_new; Ycurr = Ypost; topology = 'post';
                log.applied = true; log.details = 'Pre-fault network restored after fault clear.';
            else
                [converged,failure_id,failure_reason,log] = transition_failure( ...
                    'ts_simulate_ibr_hybrid:rightLimit',reason,log);
            end
        case 'sg_trip'
            [ok,x_new,y_new,ec_new,active_new,handler_log,reason,right_norm,stage] = ...
                trip_transaction(t,x,y,Ycurr,u,ec,dae,sched,settings.kcl_tol);
            log = new_event_log(ev.type,t);
            log.pre_kcl_norm = pre_norm; log.right_kcl_norm = right_norm;
            log.selected_gfm_indices = sched.selected_gfm_indices;
            log.reference_resource_index = sched.reference_resource_index;
            if ok
                x=x_new; y=y_new; ec=ec_new; active=active_new;
                log.applied=true; log.details=handler_log.details;
                t_trip=t;
            else
                [converged,failure_id,failure_reason,log] = transition_failure( ...
                    ['ts_simulate_ibr_hybrid:' stage],reason,log);
            end
        case 'sg_on'
            pending_reclose = true;
            good_since = NaN;
            reclose_status = 'PENDING';
            log = new_event_log(ev.type,t);
            log.applied = true;
            log.details = 'Earliest SG reclose request accepted; synchronism dwell is now monitored.';
            log.pre_kcl_norm = pre_norm; log.right_kcl_norm = pre_norm;
        otherwise
            log = new_event_log(ev.type,t);
            [converged,failure_id,failure_reason,log] = transition_failure( ...
                'ts_simulate_ibr_hybrid:badEvent',sprintf('Unknown event %s.',ev.type),log);
        end
        event_log(end+1,1) = log; %#ok<AGROW>
        current_active=stability.ts_dynamic_state_indices(dae,ec);
        log_status=stability.ibr_status_snapshot(ev.type,t,dae,ec,current_active, ...
            kcl_norm(dae,t,x,y,Ycurr,u,ec));
        event_log(end).status=log_status;
        status_log(end+1,1)=log_status; %#ok<AGROW>
        event_cursor = event_cursor+1;
        event_applied = true;
        if ~converged, break; end
    end
    if ~converged, break; end
    if event_applied
        active = stability.ts_dynamic_state_indices(dae,ec);
        samples = append_sample(samples,t,x,y,ec,active,topology,'right');
    end

    % sg_on is an earliest request. Check after every accepted sample, enforce
    % minimum-off time and sustained dwell, and close at the first eligible
    % landing. Failure of the close transaction rolls back and fails closed.
    if pending_reclose && ~isfinite(actual_reclose)
        [eligible,last_guard] = reclose_guard(t,x,y,u,ec,dae,sched,case_data,settings);
        if eligible
            if ~isfinite(good_since), good_since=t; end
        else
            good_since=NaN;
        end
        dwell_ok = isfinite(good_since) && t-good_since>=settings.sync_dwell-settings.event_tol;
        off_ok = isfinite(t_trip) && t-t_trip>=settings.min_off-settings.event_tol;
        if eligible && dwell_ok && off_ok
            pre_norm = kcl_norm(dae,t,x,y,Ycurr,u,ec);
            [ok,y_new,ec_new,handler_log,reason,right_norm] = ...
                reclose_transaction(t,x,y,Ycurr,u,ec,dae,sched,settings.kcl_tol);
            log = new_event_log('sg_reclose',t);
            log.pre_kcl_norm=pre_norm; log.right_kcl_norm=right_norm;
            log.guard=last_guard;
            if ok
                y=y_new; ec=ec_new; active=stability.ts_dynamic_state_indices(dae,ec);
                actual_reclose=t; pending_reclose=false; reclose_status='SUCCESS';
                log.applied=true; log.details=handler_log.details;
                samples=append_sample(samples,t,x,y,ec,active,topology,'right');
            else
                [converged,failure_id,failure_reason,log] = transition_failure( ...
                    'ts_simulate_ibr_hybrid:recloseTransaction',reason,log);
            end
            event_log(end+1,1)=log; %#ok<AGROW>
            log_status=stability.ibr_status_snapshot('sg_reclose',t,dae,ec,active, ...
                kcl_norm(dae,t,x,y,Ycurr,u,ec));
            event_log(end).status=log_status;
            status_log(end+1,1)=log_status; %#ok<AGROW>
        elseif t>=sched.sg_on+settings.sync_timeout-settings.event_tol
            pending_reclose=false; reclose_status='SYNC_TIMEOUT';
            log=new_event_log('sg_reclose_timeout',t);
            log.applied=false; log.guard=last_guard;
            log.details='Synchronism was not sustained through the CASE_DEFINED timeout.';
            log.pre_kcl_norm=kcl_norm(dae,t,x,y,Ycurr,u,ec);
            log.right_kcl_norm=log.pre_kcl_norm;
            event_log(end+1,1)=log; %#ok<AGROW>
            log_status=stability.ibr_status_snapshot('sg_reclose_timeout',t,dae,ec, ...
                stability.ts_dynamic_state_indices(dae,ec),log.right_kcl_norm);
            event_log(end).status=log_status;
            status_log(end+1,1)=log_status; %#ok<AGROW>
        end
    end
    if ~converged, break; end
end

if pending_reclose && strcmp(reclose_status,'PENDING') && ...
        ~isempty(fieldnames(last_guard)) && ~last_guard.passes
    reclose_status='PENDING_SYNC_FAIL';
end

res.t=samples.t;
res.x_traj=samples.x;
res.y_traj=samples.y;
res.sample_side=samples.side;
res.topology_history=samples.topology;
res.Y_log=samples.topology;
res.active_state_history=samples.active;
res.event_context_history=samples.context;
res.event_log=event_log;
res.status_log=status_log;
res.events=events;
res.converged=converged;
res.failure_id=failure_id;
res.failure_reason=failure_reason;
if sched.enabled
    res.requested_sg_on_time=sched.sg_on;
else
    res.requested_sg_on_time=NaN;
end
res.actual_reclose_time=actual_reclose;
res.reclose_status=reclose_status;
res.sched=sched;
res.t_sg_trip=t_trip;
res.last_synchronism_guard=last_guard;
res.iter_per_step=step_iterations;
res.residual_per_step=step_residuals;

if converged
    try
        res=add_diagnostics(res,dae,u,case_data);
    catch me
        [res,meta]=fail(res,meta,'ts_simulate_ibr_hybrid:diagnostic',me);
        return;
    end
end
meta.method='trapezoidal_coupled_newton_shared';
meta.full_kcl=true;
meta.event_aware=true;
meta.iterations=total_iterations;
meta.max_step_residual=max_residual;
meta.sample_count=numel(res.t);
meta.event_count=numel(event_log);
meta.failure_id=failure_id;
meta.failure_reason=failure_reason;
end

function [dae,u,ec,sched,s] = initialize(case_data,devices,x0,y0,opt)
required={'u_eq','event_context','ibr_event_schedule'};
for k=1:numel(required)
    if ~isfield(opt,required{k})
        error('ts_simulate_ibr_hybrid:missingInput','opt.%s is required.',required{k});
    end
end
dae=stability.composite_dae(case_data,devices,struct('load_model',option(opt,'load_model','cz_p_cz_q')));
if numel(x0)~=numel(dae.x0) || numel(y0)~=numel(dae.y0)
    error('ts_simulate_ibr_hybrid:badStateSize','x0/y0 dimensions do not match the composite DAE.');
end
u=opt.u_eq(:);
if numel(u)~=numel(dae.u0) || any(~isfinite(u))
    error('ts_simulate_ibr_hybrid:badInputVector','u_eq must be finite and match the composite input dimension.');
end
ec=opt.event_context;
if ~isstruct(ec) || ~isscalar(ec) || ~isfield(ec,'hybrid_state')
    error('ts_simulate_ibr_hybrid:badEventContext','event_context.hybrid_state is required.');
end
sched=opt.ibr_event_schedule;
if ~isfield(sched,'enabled'), error('ts_simulate_ibr_hybrid:badSchedule','Schedule lacks enabled.'); end
s=struct('t_end',option(opt,'t_end',5.0),'dt',option(opt,'dt',0.01), ...
    'verbose',logical(option(opt,'verbose',false)),'newton_tol',1e-8, ...
    'max_iter',50,'fd_eps',3e-6,'kcl_tol',1e-6,'event_tol',1e-12, ...
    'sync_dwell',case_data.synchronism.dwell_s, ...
    'sync_timeout',case_data.synchronism.timeout_s, ...
    'min_off',case_data.delays.T_sg_min_off_s,'sync_overrides',struct());
if isfield(opt,'synchronism_overrides'), s.sync_overrides=opt.synchronism_overrides; end
if isfield(opt,'delays_overrides')
    d=opt.delays_overrides;
    if isfield(d,'T_sg_min_off_s'), s.min_off=d.T_sg_min_off_s; end
    if isfield(d,'dwell_s'), s.sync_dwell=d.dwell_s; end
    if isfield(d,'timeout_s'), s.sync_timeout=d.timeout_s; end
end
vals=[s.t_end,s.dt,s.sync_dwell,s.sync_timeout,s.min_off];
if any(~isfinite(vals)) || s.t_end<=0 || s.dt<=0 || any(vals(3:5)<0)
    error('ts_simulate_ibr_hybrid:badOptions','Time-step and delay settings are invalid.');
end
end

function events=schedule_events(sched)
if ~sched.enabled
    events=repmat(struct('type','','t',0),0,1); return;
end
events=repmat(struct('type','','t',0),numel(sched.events),1);
for k=1:numel(sched.events)
    events(k).type=char(sched.events(k).type);
    events(k).t=sched.events(k).t;
end
end

function [ok,xr,yr,ecr,active,handler_log,reason,right_norm,stage] = ...
    trip_transaction(t,x,y,Y,u,ec,dae,sched,kcl_tol)
ok=false; xr=x; yr=y; ecr=ec; active=[]; reason=''; right_norm=inf; stage='tripTransaction';
event=struct('type','sg_trip_request','t',t,'sg_ids',{{sched.sg_id}}, ...
    'committed_selection',struct('selected_gfm_indices',sched.selected_gfm_indices, ...
    'n_gfm_required',sched.n_gfm_required, ...
    'reference_resource_index',sched.reference_resource_index));
[hs_candidate,handler_log]=stability.sg_event_handler(ec.hybrid_state,event,dae.devices,struct());
if ~handler_log.applied
    reason=sprintf('%s: %s',handler_log.failure_id,handler_log.details); return;
end
ecr=ec; ecr.hybrid_state=stability.ts_hybrid_state_snapshot(hs_candidate);
try
    xr=apply_device_transfers(x,y,u,ec,ecr,dae);
catch me
    stage='modeTransfer'; reason=sprintf('%s: %s',me.identifier,me.message); return;
end
[ok,yr,reason,right_norm]=right_limit(xr,y,Y,dae,u,ecr,t,kcl_tol);
if ~ok, stage='rightLimit'; end
if ok, active=stability.ts_dynamic_state_indices(dae,ecr); end
end

function xr=apply_device_transfers(x,y,u,ec_left,ec_right,dae)
xr=x;
for k=1:numel(dae.devices)
    dev=dae.devices(k); key=matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
    if ~isfield(ec_left.hybrid_state.device_modes,key) || ...
            ~isfield(ec_right.hybrid_state.device_modes,key)
        error('ts_simulate_ibr_hybrid:modeMap','Hybrid mode map is missing device %s.',dev.device_id);
    end
    before=char(ec_left.hybrid_state.device_modes.(key));
    after=char(ec_right.hybrid_state.device_modes.(key));
    if strcmpi(before,after), continue; end
    if ~any(strcmpi(after,{'gfl','gfm','tripped'})), continue; end
    if ~isfield(dev,'mode_transfer_state') || ~isa(dev.mode_transfer_state,'function_handle')
        error('ts_simulate_ibr_hybrid:missingTransfer','Device %s lacks a physical transfer callback.',dev.device_id);
    end
    xi=dae.device_offsets(k)+(1:dev.nx);
    ui=dae.u_offsets(k)+(1:dev.nu);
    [xdev,~]=dev.mode_transfer_state(x(xi),y,u(ui),ec_left,after,ec_right,struct('AbsTol',1e-10));
    if numel(xdev)~=dev.nx || any(~isfinite(xdev))
        error('ts_simulate_ibr_hybrid:badTransferState','Device %s returned an invalid transfer state.',dev.device_id);
    end
    xr(xi)=xdev(:);
end
end

function [ok,y_right,reason,norm_right]=right_limit(x,y0,Y,dae,u,ec,t,kcl_tol)
ok=false; y_right=y0; reason=''; norm_right=inf;
g=@(xx,yy,YY) dae.dae_g(t,xx,yy,YY,u,ec);
try
    [y_candidate,info]=stability.ts_algebraic_solve(x,y0,Y,g,@stability.ts_jac_y_fd,kcl_tol);
catch me
    reason=sprintf('%s: %s',me.identifier,me.message); return;
end
norm_right=norm(g(x,y_candidate,Y),inf);
if ~info.converged || ~isfinite(norm_right) || norm_right>kcl_tol
    reason=sprintf('Right-limit KCL residual %.3e exceeds %.3e.',norm_right,kcl_tol); return;
end
y_right=y_candidate; ok=true;
end

function [ok,y_right,ec_right,handler_log,reason,right_norm]= ...
    reclose_transaction(t,x,y,Y,u,ec,dae,sched,kcl_tol)
ok=false; y_right=y; ec_right=ec; reason=''; right_norm=inf;
event=struct('type','sg_reclose_request','t',t,'sg_id',sched.sg_id);
[hs_candidate,handler_log]=stability.sg_event_handler(ec.hybrid_state,event,dae.devices,struct());
if ~handler_log.applied
    reason=sprintf('%s: %s',handler_log.failure_id,handler_log.details); return;
end
ec_right=ec; ec_right.hybrid_state=stability.ts_hybrid_state_snapshot(hs_candidate);
[ok,y_right,reason,right_norm]=right_limit(x,y,Y,dae,u,ec_right,t,kcl_tol);
end

function [eligible,guard]=reclose_guard(t,x,y,u,ec,dae,sched,case_data,settings)
idx=find(strcmp({dae.devices.device_id},sched.sg_id));
if numel(idx)~=1, error('ts_simulate_ibr_hybrid:badSgId','SG ID does not map uniquely.'); end
dev=dae.devices(idx); xi=dae.device_offsets(idx)+(1:dev.nx); ui=dae.u_offsets(idx)+(1:dev.nu);
rec=dev.reconstruct(t,x(xi),y,u(ui),ec);
if ~isfield(rec,'V_open_circuit') || ~isfield(rec,'omega') || ~isfield(rec,'delta')
    error('ts_simulate_ibr_hybrid:missingSynchronismOutput','SG reconstruct lacks synchronism outputs.');
end
Vbus=complex(y(2*dev.bus_position-1),y(2*dev.bus_position));
gopt=struct('dV_max',case_data.synchronism.dV_max_pu, ...
    'df_max',case_data.synchronism.df_max_pu, ...
    'dtheta_max',case_data.synchronism.dtheta_max_deg, ...
    'dwell_min',settings.sync_dwell);
names=fieldnames(settings.sync_overrides);
for k=1:numel(names), gopt.(names{k})=settings.sync_overrides.(names{k}); end
guard=stability.synchronism_guard(Vbus,rec.V_open_circuit,rec.delta,rec.omega,0.0,gopt);
eligible=guard.passes;
end

function n=kcl_norm(dae,t,x,y,Y,u,ec)
g=dae.dae_g(t,x,y,Y,u,ec); n=norm(g,inf);
end

function s=new_samples(x,y,ec,active,topology)
s=struct('t',0,'x',x(:),'y',y(:),'side',{{'initial'}}, ...
    'topology',{{topology}},'context',{{ec}},'active',{{active(:)'}});
end

function s=append_sample(s,t,x,y,ec,active,topology,side)
s.t(end+1)=t; s.x(:,end+1)=x(:); s.y(:,end+1)=y(:);
s.side{end+1}=side; s.topology{end+1}=topology;
s.context{end+1}=ec; s.active{end+1}=active(:)';
end

function log=new_event_log(type,t)
log=struct('type',type,'t',t,'applied',false,'failure_id','', ...
    'details','','pre_kcl_norm',NaN,'right_kcl_norm',NaN, ...
    'selected_gfm_indices',[],'reference_resource_index',[], ...
    'guard',struct(),'status',struct());
end

function [converged,id,reason,log]=transition_failure(id,reason,log)
converged=false; log.failure_id=id; log.details=reason;
end

function res=add_diagnostics(res,dae,u,case_data)
nt=numel(res.t); nd=numel(dae.devices); nb=numel(dae.mapping.bus_ids);
I=complex(zeros(nd,nt)); P=zeros(nd,nt); Q=zeros(nd,nt);
freq=nan(nd,nt); H=nan(nd,nt); limit=nan(nd,nt);
modes=cell(nd,nt); online=false(nd,nt);
for j=1:nt
    y=res.y_traj(:,j); x=res.x_traj(:,j); ec=res.event_context_history{j};
    for k=1:nd
        dev=dae.devices(k); xi=dae.device_offsets(k)+(1:dev.nx); ui=dae.u_offsets(k)+(1:dev.nu);
        I(k,j)=dev.current_injection(res.t(j),x(xi),y,u(ui),ec);
        if ~isfinite(I(k,j)), error('ts_simulate_ibr_hybrid:nonFiniteCurrent','Non-finite current for %s.',dev.device_id); end
        V=complex(y(2*dev.bus_position-1),y(2*dev.bus_position)); S=V*conj(I(k,j));
        P(k,j)=real(S); Q(k,j)=imag(S);
        out=dev.reconstruct(res.t(j),x(xi),y,u(ui),ec);
        modes{k,j}=char(out.mode); online(k,j)=logical(out.online);
        if strcmpi(out.mode,'sg')
            freq(k,j)=case_data.base_values.frequency_Hz*(1+out.omega);
            H(k,j)=out.H_system;
        elseif isfield(out,'gfm')
            freq(k,j)=case_data.base_values.frequency_Hz*(1+out.gfm.omega_m);
            H(k,j)=out.gfm.H_system; limit(k,j)=out.gfm.ImaxF_sys;
        elseif isfield(out,'gfl')
            limit(k,j)=out.gfl.Imax/out.gfl.kappa;
        end
    end
end
coi=nan(1,nt);
for j=1:nt
    use=isfinite(freq(:,j)) & isfinite(H(:,j)) & H(:,j)>0 & online(:,j);
    if any(use), coi(j)=sum(H(use,j).*freq(use,j))/sum(H(use,j)); end
end
Vmat=complex(res.y_traj(1:2:end,:),res.y_traj(2:2:end,:));
res.bus_ids=dae.mapping.bus_ids;
res.device_ids={dae.devices.device_id};
res.device_bus_ids=[dae.devices.bus_id];
res.bus_voltage_magnitude=abs(Vmat(1:nb,:));
res.device_currents=I; res.device_current_magnitude=abs(I);
res.device_P=P; res.device_Q=Q;
res.device_P_pu=P; res.device_Q_pu=Q;
res.device_P_MW=P*case_data.mpc.baseMVA; res.device_Q_MVAr=Q*case_data.mpc.baseMVA;
res.device_frequency_Hz=freq; res.coi_frequency_Hz=coi;
res.device_inertia_system=H; res.device_current_limit_sys=limit;
res.device_modes_history=modes; res.device_online_history=online;
sg=find(strcmpi({dae.devices.device_type},'sg_emf6_composite'));
res.sg_indices=sg; res.sg_freq=freq(sg,:);
if isempty(sg), res.sg_omega=[]; else, res.sg_omega=res.sg_freq/case_data.base_values.frequency_Hz-1; end
end

function [res,meta]=empty_result(opt)
res=struct('t',[],'x_traj',[],'y_traj',[],'sample_side',{{}}, ...
    'topology_history',{{}},'event_context_history',{{}},'active_state_history',{{}}, ...
    'events',[],'event_log',[],'converged',false,'failure_id','', ...
    'failure_reason','','requested_sg_on_time',NaN,'actual_reclose_time',NaN, ...
    'reclose_status','NOT_REQUESTED','sched',struct(), ...
    'bus_voltage_magnitude',[],'device_currents',[],'device_current_magnitude',[], ...
    'device_P',[],'device_Q',[],'sg_omega',[],'sg_freq',[],'sg_indices',[], ...
    'device_modes_history',{{}},'Y_log',{{}},'residual_per_step',[], ...
    'iter_per_step',[],'status_log',[]);
meta=struct('method','trapezoidal_coupled_newton_shared','full_kcl',true, ...
    'event_aware',true,'failure_id','','failure_reason','');
if isfield(opt,'ibr_event_schedule'), res.sched=opt.ibr_event_schedule; end
end

function [res,meta]=fail(res,meta,id,me)
res.converged=false; res.failure_id=id;
if isa(me,'MException'), res.failure_reason=sprintf('%s: %s',me.identifier,me.message); else, res.failure_reason=char(me); end
meta.failure_id=id; meta.failure_reason=res.failure_reason;
end

function value=option(s,name,default)
value=default; if isfield(s,name) && ~isempty(s.(name)), value=s.(name); end
end

function value=ternary(condition,a,b)
if condition, value=a; else, value=b; end
end
