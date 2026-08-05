function [selection, audit] = et_fcs_production_trip_decision( ...
    t,x,y,Y,u,ec,dae,sched,case_data,resources,selector_table,mode,opt)
%ET_FCS_PRODUCTION_TRIP_DECISION  Predictive SG-trip mode/owner decision.
%   Every nonlinear candidate trial starts from the same accepted event-left
%   state.  The SG-trip transaction, device-owned transfer maps, frozen
%   post-trip dispatch, full-KCL right limit, and production composite
%   trapezoidal kernel are applied on private value copies only.  This
%   function returns a selection request; it never mutates production state.
%
%   MODE is `et_fcsps` (exhaustive ranking) or `bo_replay` (the frozen
%   finite-set BO reveal policy over the same immutable trial table).

arguments
    t (1,1) double {mustBeFinite}
    x (:,1) double
    y (:,1) double
    Y double
    u (:,1) double
    ec struct
    dae struct
    sched struct
    case_data struct
    resources struct
    selector_table struct
    mode {mustBeTextScalar}
    opt struct = struct()
end

mode = lower(char(mode));
if ~any(strcmp(mode,{'et_fcsps','bo_replay'}))
    error('stability:et_fcs_production_trip_decision:badMode', ...
        'mode must be et_fcsps or bo_replay.');
end
policy = stability.et_fcs_policy_ieee14();
state = accepted_state(t,x,y,Y,ec,dae,case_data,resources);
event = struct('event_id',sprintf('sg_trip@%.12g',t),'type','sg_trip', ...
    'authenticated',true,'local_request',false);
base_snapshot = stability.et_fcs_snapshot(state,event);

reused = false;
if isfield(opt,'trial_evidence') && isstruct(opt.trial_evidence) && ...
        isfield(opt.trial_evidence,'base_snapshot_fingerprint') && ...
        strcmp(opt.trial_evidence.base_snapshot_fingerprint,base_snapshot.fingerprint)
    trial_table = opt.trial_evidence.trial_table;
    reused = true;
else
    candidates = stability.et_fcs_enumerate(base_snapshot);
    runtime = struct('t',t,'x',x,'y',y,'Y',Y,'u',u,'ec',ec,'dae',dae, ...
        'sched',sched,'case_data',case_data,'resources',resources, ...
        'selector_table',selector_table,'dt',resolve_dt(opt));
    trial_table = build_trials(base_snapshot,candidates,runtime,policy);
end

state.trial_table = trial_table;
providers = struct('screen','stability.et_fcs_table_screen', ...
    'predict','stability.et_fcs_table_predict');
decision = stability.et_fcs_supervisor(state,event,providers,policy);
if ~strcmp(decision.status,'COMMIT_REQUEST')
    detail=decision.reason;
    if isfield(decision,'candidates') && ~isempty(decision.candidates)
        sp=sum([decision.candidates.screen_pass]);
        pp=sum([decision.candidates.prediction_pass]);
        sf=unique(arrayfun(@(q) string(q.screen.failure_id), ...
            decision.candidates,'UniformOutput',true));
        pf=unique(arrayfun(@(q) string(q.prediction.failure_id), ...
            decision.candidates,'UniformOutput',true));
        detail=sprintf('%s screen=%d/%d prediction=%d/%d; screen IDs=%s; prediction IDs=%s', ...
            detail,sp,numel(decision.candidates),pp,numel(decision.candidates), ...
            strjoin(sf,','),strjoin(pf,','));
    end
    error('stability:et_fcs_production_trip_decision:noEtCandidate', ...
        '%s: %s',decision.failure_id,detail);
end

if strcmp(mode,'et_fcsps')
    winner = decision.candidates(strcmp({decision.candidates.candidate_id}, ...
        decision.winner_candidate_id));
    bo = struct();
else
    bo = stability.et_fcs_bo_replay(decision.candidates,policy.bo);
    if ~strcmp(bo.status,'COMPLETE')
        error('stability:et_fcs_production_trip_decision:noBoCandidate', ...
            'Finite-set BO did not return a feasible sampled candidate: %s.',bo.status);
    end
    winner = decision.candidates(bo.winner_index);
end
if ~isscalar(winner)
    error('stability:et_fcs_production_trip_decision:identityMismatch', ...
        'The winning candidate ID did not map uniquely.');
end

selection = struct('selected_gfm_indices',winner.selected_gfm_indices, ...
    'n_gfm_required',winner.n_gfm, ...
    'reference_resource_index',winner.owner_index);
audit = struct('schema','et_fcs_production_trip_audit/1.0','mode',mode, ...
    'policy',policy,'base_snapshot_fingerprint',base_snapshot.fingerprint, ...
    'trial_table',trial_table,'trial_evidence_reused',reused, ...
    'decision',decision,'bo',bo,'selection',selection, ...
    'classification',controller_classification(mode));
end

function state = accepted_state(t,x,y,Y,ec,dae,case_data,resources)
nd = numel(dae.devices);
ids = {dae.devices.device_id};
types = cell(1,nd); modes = cell(1,nd); online = false(1,nd);
eligible = false(1,nd); refcap = false(1,nd);
hs = ec.hybrid_state;
for k = 1:nd
    dev = dae.devices(k);
    key = matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
    types{k} = resource_type(dev);
    modes{k} = char(hs.device_modes.(key));
    online(k) = logical(hs.device_online.(key));
    eligible(k) = strcmp(types{k},'ibr') && capability(dev,'can_switch_mode') && ...
        supports(dev,'gfl') && supports(dev,'gfm');
    refcap(k) = strcmp(types{k},'sg') || supports(dev,'gfm');
end
decision_online = online;
decision_online(strcmp(types,'sg')) = false;
owners = [];
if isfield(hs,'reference_owner_indices'), owners = hs.reference_owner_indices; end
rc = stability.runtime_rerank_candidates_context_for_et_fcs(hs,dae,t);
[limits,reserve] = contracts(case_data,resources,dae);
state = struct('accepted',true,'t',t,'x',x,'y',y, ...
    'topology_payload',Y,'resource_ids',{ids},'resource_types',{types}, ...
    'device_modes',{modes},'device_online',online,'eligible_mask',eligible, ...
    'reference_capable',refcap,'resource_island_ids',ones(1,nd), ...
    'energized_island_ids',1,'reference_owner_indices',owners, ...
    'hold_timers',rc.hold_timers,'lockout_until',rc.lockout_timers, ...
    'limits',limits,'reserve',reserve,'agsi',zeros(1,nd), ...
    'decision_device_online',decision_online, ...
    'decision_reference_owner_indices',[]);
end

function table = build_trials(snapshot,candidates,r,policy)
empty_screen = struct('converged',false,'kcl_norm',Inf,'voltage_abs',[], ...
    'current_abs',[],'reserve_known',false,'delta_p_available',NaN, ...
    'delta_q_available',NaN,'mapped_x',[],'mapped_y',[]);
empty_prediction = struct('converged',false,'t',[],'voltage_abs',[], ...
    'frequency_hz',[],'rocof_hz_s',[],'current_abs',[], ...
    'reserve_known',false,'delta_p_available',[],'delta_q_available',[], ...
    'handback',struct());
table = repmat(struct('candidate_id','','screen',empty_screen, ...
    'prediction',empty_prediction,'producer_stage','not_authenticated'),numel(candidates),1);
for k = 1:numel(candidates)
    c = candidates(k); table(k).candidate_id = c.candidate_id;
    if ~authenticated_candidate(c,r.selector_table), continue; end
    fprintf('ET_FCS_TRIAL_START %d/%d %s\n',k,numel(candidates),c.candidate_id);
    trial_clock=tic;
    [screen,prediction,stage] = one_trial(snapshot,c,r,policy.prediction_horizon);
    table(k).screen = screen;
    table(k).prediction = prediction;
    table(k).producer_stage = stage;
    fprintf('ET_FCS_TRIAL_DONE %d/%d %s stage=%s elapsed=%.3f s\n', ...
        k,numel(candidates),c.candidate_id,stage,toc(trial_clock));
end
if ~any(arrayfun(@(q) q.screen.converged,table))
    error('stability:et_fcs_production_trip_decision:noRightLimitTrial', ...
        'No candidate reached a converged right limit; producer stages: %s.', ...
        strjoin(unique(string({table.producer_stage})),','));
end
end

function [screen,pred,stage] = one_trial(snapshot,c,r,Tp)
screen = struct('converged',false,'kcl_norm',Inf,'voltage_abs',[], ...
    'current_abs',[],'reserve_known',false,'delta_p_available',NaN, ...
    'delta_q_available',NaN,'mapped_x',[],'mapped_y',[]);
pred = struct('converged',false,'t',[],'voltage_abs',[], ...
    'frequency_hz',[],'rocof_hz_s',[],'current_abs',[], ...
    'reserve_known',false,'delta_p_available',[],'delta_q_available',[], ...
    'handback',struct());
stage='event_transaction';
event = struct('type','sg_trip_request','t',r.t,'sg_ids',{{r.sched.sg_id}}, ...
    'committed_selection',struct('selected_gfm_indices',c.selected_gfm_indices, ...
    'n_gfm_required',c.n_gfm,'reference_resource_index',c.owner_index, ...
    'reference_owner_indices',c.owner_index, ...
    'gfm_reference_resource_indices',c.owner_index,'reference_island_ids',1));
[hs,log] = stability.sg_event_handler(r.ec.hybrid_state,event,r.dae.devices,struct());
if ~log.applied, return; end
ec1 = r.ec; ec1.hybrid_state = stability.ts_hybrid_state_snapshot(hs);
stage='mode_transfer_or_dispatch';
try
    x1 = transfer_states(r.x,r.y,r.u,r.ec,ec1,r.dae);
    u1 = post_trip_input(r.u,r.dae,r.case_data);
    [y1,ok,kcl] = solve_right(x1,r.y,r.Y,r.dae,u1,ec1,r.t, ...
        snapshot.limits.kcl_tol);
catch me
    stage=sprintf('mode_transfer_or_dispatch:%s:%s',me.identifier,me.message);
    return;
end
stage='right_limit';
if ~ok, return; end
    [v0,i0,p0,q0] = electrical(r.t,x1,y1,u1,ec1,r.dae);
[rp0,rq0] = reserve_available(p0,q0,r.resources,r.case_data.mpc.baseMVA);
screen = struct('converged',true,'kcl_norm',kcl,'voltage_abs',v0, ...
    'current_abs',i0,'reserve_known',true,'delta_p_available',rp0, ...
    'delta_q_available',rq0,'mapped_x',x1,'mapped_y',y1);

stage='prediction';
dt = r.dt; nstep = round(Tp/dt);
if abs(nstep*dt-Tp) > 32*eps(max(1,Tp)), return; end
tvec = r.t + (0:nstep)*dt;
V = zeros(r.dae.nb,nstep+1); Vc=complex(V); I = zeros(sum(snapshot.eligible_mask),nstep+1);
P = I; Q = I; X = x1; yy = y1;
[V(:,1),I(:,1),P(:,1),Q(:,1),Vc(:,1)] = electrical(r.t,X,yy,u1,ec1,r.dae);
active = stability.ts_dynamic_state_indices(r.dae,ec1);
for j = 1:nstep
    step_opt = struct('newton_tol',snapshot.limits.kcl_tol,'max_iter',50, ...
        'fd_eps',3e-6,'verbose',false,'full_kcl',true, ...
        't_now',tvec(j),'domain_preserving_trials',true);
    try
        s = stability.ts_step_composite(X,yy,dt,r.dae,r.Y,u1,ec1,active,step_opt);
    catch
        return;
    end
    if ~s.converged || ~s.finite, return; end
    X=s.x_full; yy=s.y_full;
    [V(:,j+1),I(:,j+1),P(:,j+1),Q(:,j+1),Vc(:,j+1)] = ...
        electrical(tvec(j+1),X,yy,u1,ec1,r.dae);
end
freq = bus_frequency(tvec,Vc,r.dae,c.owner_index);
rocof = gradient(freq,dt);
[rp,rq] = reserve_series(P,Q,r.resources,r.case_data.mpc.baseMVA);
pred = struct('converged',true,'t',tvec,'voltage_abs',V, ...
    'frequency_hz',freq,'rocof_hz_s',rocof,'current_abs',I, ...
    'reserve_known',true,'delta_p_available',rp,'delta_q_available',rq, ...
    'handback',struct('delta_p',abs(sum(P(:,end))-sum(P(:,1))), ...
    'delta_q',abs(sum(Q(:,end))-sum(Q(:,1))), ...
    'delta_i',max(abs(I(:,end)-I(:,1))), ...
    'delta_theta',abs(wrap_deg(owner_angle(Vc(:,end),r.dae,c.owner_index)- ...
    owner_angle(Vc(:,1),r.dae,c.owner_index)))));
stage='complete';
end

function [Vmag,Iabs,P,Q,Vphasor] = electrical(t,x,y,u,ec,dae)
Vphasor = complex(y(1:2:end),y(2:2:end)); Vmag = abs(Vphasor);
ibr = find(arrayfun(@(d) strcmp(resource_type(d),'ibr'),dae.devices));
Iabs=zeros(numel(ibr),1); P=Iabs; Q=Iabs;
for j=1:numel(ibr)
    k=ibr(j); d=dae.devices(k); xi=dae.device_offsets(k)+(1:d.nx); ui=dae.u_offsets(k)+(1:d.nu);
    ii=d.current_injection(t,x(xi),y,u(ui),ec);
    ss=Vphasor(d.bus_position)*conj(ii);
    Iabs(j)=abs(ii); P(j)=real(ss); Q(j)=imag(ss);
end
end

function f = bus_frequency(t,V,dae,owner)
bp=dae.devices(owner).bus_position;
a=unwrap(angle(V(bp,:)));
f=60+gradient(a,t)/(2*pi);
end

function a = owner_angle(V,dae,owner)
a=angle(V(dae.devices(owner).bus_position))*180/pi;
end

function w = wrap_deg(a), w=mod(a+180,360)-180; end

function [rp,rq] = reserve_series(P,Q,resources,Sbase)
nt=size(P,2); rp=zeros(1,nt); rq=rp;
for j=1:nt, [rp(j),rq(j)]=reserve_available(P(:,j),Q(:,j),resources,Sbase); end
end

function [rp,rq] = reserve_available(P,Q,resources,Sbase)
idx=find(strcmpi({resources.resource_type},'ibr')); pmax=zeros(numel(idx),1); qmax=pmax;
for j=1:numel(idx)
    pmax(j)=resources(idx(j)).limits.Pmax_MW/Sbase;
    qmax(j)=resources(idx(j)).limits.Qmax_MVAr/Sbase;
end
rp=sum(max(0,pmax-max(P(:),0))); rq=sum(max(0,qmax-abs(Q(:))));
end

function [limits,reserve] = contracts(case_data,resources,dae)
idx=find(strcmpi({resources.resource_type},'ibr')); imax=zeros(numel(idx),1);
for j=1:numel(idx)
    imax(j)=resources(idx(j)).limits.ImaxF*resources(idx(j)).ratings.Mbase/case_data.mpc.baseMVA;
end
limits=struct('kcl_tol',1e-8,'v_min',0.80,'v_max',1.20,'i_max',imax, ...
    'f_min',57,'f_max',63,'rocof_max',5);
reserve=struct('known',true,'provenance', ...
    'CASE_DEFINED_NAMEPLATE_PROXY: resource limits Pmax_MW/Qmax_MVAr');
if numel(dae.devices)~=numel(resources)
    error('stability:et_fcs_production_trip_decision:resourceAlignment', ...
        'Device/resource counts differ.');
end
end

function tf = authenticated_candidate(c,table)
tf=false;
if ~isfield(table,'sg_off') || ~isfield(table.sg_off,'configurations'), return; end
cfg=table.sg_off.configurations;
for k=1:numel(cfg)
    if isfield(cfg(k),'ready_to_commit') && cfg(k).ready_to_commit && ...
            isequal(sort(reshape(cfg(k).selected_gfm_indices,1,[])), ...
            sort(reshape(c.selected_gfm_indices,1,[]))) && ...
            isequal(cfg(k).reference_resource_index,c.owner_index)
        tf=true; return;
    end
end
end

function xr=transfer_states(x,y,u,ec0,ec1,dae)
xr=x;
for k=1:numel(dae.devices)
    d=dae.devices(k); key=matlab.lang.makeValidName(char(d.device_id),'ReplacementStyle','underscore');
    before=char(ec0.hybrid_state.device_modes.(key)); after=char(ec1.hybrid_state.device_modes.(key));
    if strcmpi(before,after), continue; end
    if ~any(strcmpi(after,{'gfl','gfm','tripped'})), continue; end
    if ~isfield(d,'mode_transfer_state') || ~isa(d.mode_transfer_state,'function_handle')
        error('stability:et_fcs_production_trip_decision:missingTransfer', ...
            'Device %s lacks a mode-transfer callback.',d.device_id);
    end
    xi=dae.device_offsets(k)+(1:d.nx); ui=dae.u_offsets(k)+(1:d.nu);
    [xd,~]=d.mode_transfer_state(x(xi),y,u(ui),ec0,after,ec1,struct('AbsTol',1e-10));
    xr(xi)=xd(:);
end
end

function unew=post_trip_input(u,dae,case_data)
contract=case_data.dispatch_contract.post_trip.post_trip_Pg_MW;
unew=u; Sbase=case_data.mpc.baseMVA;
for k=1:numel(dae.devices)
    d=dae.devices(k); if ~strcmp(resource_type(d),'ibr'), continue; end
    slot=find(strcmpi(string(d.input_names),'P_ref'));
    unew(dae.u_offsets(k)+slot)=contract.(char(d.device_id))/Sbase;
end
end

function [ys,ok,normg]=solve_right(x,y,Y,dae,u,ec,t,tol)
g=@(xx,yy,YY) dae.dae_g(t,xx,yy,YY,u,ec);
try
    [ys,info]=stability.ts_algebraic_solve(x,y,Y,g,@stability.ts_jac_y_fd,tol);
    normg=norm(g(x,ys,Y),inf); ok=info.converged && isfinite(normg) && normg<=tol;
catch
    ys=y; ok=false; normg=Inf;
end
end

function rc = resolve_dt(opt)
rc=0.0125; if isfield(opt,'dt') && ~isempty(opt.dt), rc=opt.dt; end
end
function s=resource_type(d)
s=''; if isfield(d,'capabilities') && isfield(d.capabilities,'resource_type'), s=lower(char(d.capabilities.resource_type)); end
end
function tf=capability(d,name)
tf=isfield(d,'capabilities') && isfield(d.capabilities,name) && logical(d.capabilities.(name));
end
function tf=supports(d,mode)
tf=isfield(d,'capabilities') && isfield(d.capabilities,'supported_modes') && ...
    any(strcmpi(string(d.capabilities.supported_modes),mode));
end
function s=controller_classification(mode)
if strcmp(mode,'et_fcsps'), s='PROJECT_DERIVED_PROTOTYPE'; else, s='ASSUMED_DIAGNOSTIC_OFFLINE_REPLAY'; end
end
