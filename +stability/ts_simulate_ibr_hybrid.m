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
pre_event_input = u;
pre_event_input_fp = sprintf('pre_event_input|%s', mat2str(pre_event_input(:).'));

samples = new_samples(x,y,u,ec,active,topology);
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
% Phase-2 reselection state (F4/F5)
pending_reselection = false;
actual_mode_reselection = NaN;
reselection_status = 'NOT_REQUESTED';
reselection_good_since = NaN;
reselection_deadline = NaN;  % exact-landing target: actual_reclose + T_down
transaction_counter = 0;
converged = true;
failure_id = '';
failure_reason = '';
total_iterations = 0;
max_residual = 0;
step_iterations = [];
step_residuals = [];
step_attempts = 0;
accepted_steps = 0;

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
        step_attempts=step_attempts+1;
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
        accepted_steps=accepted_steps+1;
        is_event_left = event_cursor<=numel(events) && ...
            abs(t-events(event_cursor).t)<=settings.event_tol;
        side = ternary(is_event_left,'left','continuous');
        samples = append_sample(samples,t,x,y,u,ec,active,topology,side);
    end

    % Apply every scheduled transition at this timestamp as ONE atomic
    % publication group (C4). Shared group_tx_id covers the left sample,
    % every event ranking in the group, and the single committed right sample.
    event_applied = false;
    group_tx_id = 0;
    while event_cursor<=numel(events) && ...
            abs(events(event_cursor).t-t)<=settings.event_tol
        ev = events(event_cursor);
        pre_norm = kcl_norm(dae,t,x,y,Ycurr,u,ec);
        if group_tx_id == 0
            transaction_counter = transaction_counter + 1;
            group_tx_id = transaction_counter;
            % Back-patch the event-left sample with the group transaction ID.
            if ~isempty(samples.t) && samples.t(end) == t ...
                    && samples.transaction_id(end) == 0
                samples.transaction_id(end) = group_tx_id;
            end
        end
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
            agfm = true;
            if isfield(opt,'automatic_gfm_switching') && ~isempty(opt.automatic_gfm_switching)
                agfm = logical(opt.automatic_gfm_switching);
            end
            [ok,x_new,y_new,u_new,ec_new,active_new,handler_log,reason, ...
                right_norm,stage,dispatch_after] = trip_transaction( ...
                t,x,y,Ycurr,u,ec,dae,sched,case_data,settings.kcl_tol,agfm);
            log = new_event_log(ev.type,t);
            log.pre_kcl_norm = pre_norm; log.right_kcl_norm = right_norm;
            log.input_before = u;
            log.input_after = u_new;
            log.dispatch_after_pu = dispatch_after;
            log.selected_gfm_indices = sched.selected_gfm_indices;
            log.reference_resource_index = sched.reference_resource_index;
            if ok
                x=x_new; y=y_new; u=u_new; ec=ec_new; active=active_new;
                log.applied=true; log.details=handler_log.details;
                t_trip=t;
            else
                % Inline failure handling (preserve log struct fields + copy
                % candidate metadata from handler_log per F2 audit contract).
                converged = false;
                failure_id = ['ts_simulate_ibr_hybrid:' stage];
                failure_reason = reason;
                log.failure_id = failure_id;
                log.details = failure_reason;
                % handler_log may lack candidate fields on early returns.
                if isfield(handler_log, 'candidate_committed')
                    log.candidate_committed = handler_log.candidate_committed;
                    log.candidate_sg_online = handler_log.candidate_sg_online;
                    log.candidate_modes = handler_log.candidate_modes;
                    log.failing_island_ids = handler_log.failing_island_ids;
                    log.n_failing_islands = handler_log.n_failing_islands;
                else
                    log.candidate_committed = [];
                    log.candidate_sg_online = [];
                    log.candidate_modes = struct();
                    log.failing_island_ids = [];
                    log.n_failing_islands = 0;
                end
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
        log.transaction_id = group_tx_id;
        event_log(end+1,1) = log; %#ok<AGROW>
        current_active=stability.ts_dynamic_state_indices(dae,ec);
        log_status=stability.ibr_status_snapshot(ev.type,t,dae,ec,current_active,...
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
        samples = append_sample(samples,t,x,y,u,ec,active,topology,'right',group_tx_id);
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
            transaction_counter=transaction_counter+1;
            reclose_tx_id=transaction_counter;
            samples=mark_transaction_left(samples,t,x,y,u,ec,active,topology,reclose_tx_id);
            pre_norm = kcl_norm(dae,t,x,y,Ycurr,u,ec);
            [ok,x_new,y_new,u_new,ec_new,handler_log,reason,right_norm, ...
                dispatch_after] = reclose_transaction(t,x,y,Ycurr,u,ec, ...
                pre_event_input,dae,sched,settings.kcl_tol);
            log = new_event_log('sg_reclose',t);
            log.transaction_id=reclose_tx_id;
            log.pre_kcl_norm=pre_norm; log.right_kcl_norm=right_norm;
            log.guard=last_guard;
            log.input_before=u; log.input_after=u_new;
            log.dispatch_after_pu=dispatch_after;
            if ok
                x=x_new; y=y_new; u=u_new; ec=ec_new;
                active=stability.ts_dynamic_state_indices(dae,ec);
                actual_reclose=t; pending_reclose=false; reclose_status='SUCCESS';
                log.applied=true; log.details=handler_log.details;
                samples=append_sample(samples,t,x,y,u,ec,active,topology,'right',reclose_tx_id);
                % Begin Phase-2 reselection (F4/F5). The SG_ON table lookup and
                % T_down derivation happen in the reselection block below.
                pending_reselection=true;
                reselection_status='PENDING';
                reselection_good_since=NaN;
                reselection_deadline=NaN;
            else
                [converged,failure_id,failure_reason,log] = transition_failure( ...
                    'ts_simulate_ibr_hybrid:recloseTransaction',reason,log);
                % C-workflow KCL instrumentation (read-only, Phase 5): record the
                % left-limit state at the failed reclose attempt so the failure
                % can be diagnosed as a physically infeasible close (relaxed guard
                % allowing a non-synchronous SG state) rather than a numerical bug.
                % This does NOT alter the trajectory or relax any gate.
                try
                    log.reclose_diag = reclose_left_state_diag( ...
                        t, x, y, u, ec, dae, sched, Ycurr, last_guard, right_norm);
                catch %#ok<CTCH>
                    % Instrumentation must never mask the original failure.
                end
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
    % --- Phase-2 delayed indexed reselection (F4/F5) -------------------
    % After a successful Phase-1 reclose, look up the authenticated SG_ON
    % table, derive T_down from Omega_target, and (after hold/guard/lockout)
    % apply the selector-chosen GFM->GFL transitions. A rejected Phase-2
    % candidate does NOT roll back Phase 1 (F9: no right sample published).
    if pending_reselection && ~isfinite(actual_mode_reselection)
        % Compute T_down from the SG_ON table candidate's Omega_target (F4/F5).
        if ~isfinite(reselection_deadline) && isfield(opt,'selector_table') && ...
                isstruct(opt.selector_table)
            [reselection_deadline, reselection_status] = compute_tdown( ...
                opt.selector_table, case_data, settings, actual_reclose);
        end
        % Exact-landing: shorten the step to land at the reselection deadline.
        if isfinite(reselection_deadline) && t < reselection_deadline - settings.event_tol && ...
                target > reselection_deadline
            target = reselection_deadline;
        end
        % Check hold/guard/lockout eligibility.
        if isfinite(reselection_deadline) && t >= reselection_deadline - settings.event_tol
            hold_ok = isfinite(t_trip) && t - t_trip >= settings.T_minimum_hold - settings.event_tol;
            guard_ok = isfinite(reselection_good_since) && ...
                t - reselection_good_since >= settings.T_guard - settings.event_tol;
            if hold_ok && guard_ok
                transaction_counter = transaction_counter + 1;
                reselection_tx_id = transaction_counter;
                samples=mark_transaction_left(samples,t,x,y,u,ec,active,topology,reselection_tx_id);
                [ok, x_new, y_new, u_new, ec_new, rsel_log, reason, right_norm, ...
                    no_mode_change] = reselection_transaction( ...
                    t, x, y, Ycurr, u, ec, dae, sched, case_data, settings, opt);
                log = new_event_log('sg_reselection', t);
                log.transaction_id = reselection_tx_id;
                log.pre_kcl_norm = kcl_norm(dae,t,x,y,Ycurr,u,ec);
                log.right_kcl_norm = right_norm;
                log.input_before = u; log.input_after = u_new;
                if ok
                    x = x_new; y = y_new; u = u_new; ec = ec_new;
                    active = stability.ts_dynamic_state_indices(dae,ec);
                    actual_mode_reselection = t;
                    pending_reselection = false;
                    if no_mode_change
                        reselection_status = 'NO_MODE_CHANGE_REQUIRED';
                        log.details = 'SG_ON selector chose the current GFM set; no mode change required.';
                    else
                        reselection_status = 'SUCCESS';
                        log.details = rsel_log.details;
                        samples = append_sample(samples, t, x, y, u, ec, active, topology, 'right', reselection_tx_id);
                    end
                    log.applied = true;
                else
                    % Phase-2 failure: retain Phase 1, no right sample (F9).
                    reselection_status = reselection_failure_status(reason);
                    log.applied = false;
                    log.failure_id = 'ts_simulate_ibr_hybrid:reselectionTransaction';
                    log.details = reason;
                    pending_reselection = false;
                end
                event_log(end+1,1) = log; %#ok<AGROW>
                log_status = stability.ibr_status_snapshot('sg_reselection', t, dae, ec, active, ...
                    kcl_norm(dae,t,x,y,Ycurr,u,ec));
                event_log(end).status = log_status;
                status_log(end+1,1) = log_status; %#ok<AGROW>
            else
                reselection_good_since = t;  % dwell accumulator
            end
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
res.u_history=samples.u;
res.sample_side=samples.side;
res.transaction_id=samples.transaction_id;
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
res.step_attempts=step_attempts;
res.accepted_steps=accepted_steps;
% Phase-2 reselection + reference-ownership fields (F1/C1/F5).
res.actual_mode_reselection_time=actual_mode_reselection;
res.reselection_status=reselection_status;
% Propagate reference-ownership + fingerprint fields from the final event context.
if ~isempty(res.event_context_history) && iscell(res.event_context_history)
    final_ec = res.event_context_history{end};
    if isstruct(final_ec) && isfield(final_ec,'hybrid_state') && isstruct(final_ec.hybrid_state)
        hs_final = final_ec.hybrid_state;
        if isfield(hs_final,'reference_owner_indices')
            res.reference_owner_indices=hs_final.reference_owner_indices;
        end
        if isfield(hs_final,'gfm_reference_resource_indices')
            res.gfm_reference_resource_indices=hs_final.gfm_reference_resource_indices;
        end
        if isfield(hs_final,'reference_island_ids')
            res.reference_island_ids=hs_final.reference_island_ids;
        end
        if isfield(hs_final,'committed_config_fingerprint')
            res.committed_config_fingerprint=hs_final.committed_config_fingerprint;
        end
    end
end
% pre_event_input_fingerprint + selector_table_fingerprint from opt.
if isfield(opt,'selector_table') && isstruct(opt.selector_table) && ...
        isfield(opt.selector_table,'selector_table_fingerprint')
    res.selector_table_fingerprint=opt.selector_table.selector_table_fingerprint;
end
res.pre_event_input_fingerprint=pre_event_input_fp;

try
    % Publish diagnostics for every accepted sample even when a later step or
    % right-limit transaction fails closed.  These are partial trajectories,
    % never a claim that the requested horizon converged.
    res=add_diagnostics(res,dae,case_data);
catch me
    if converged
        [res,meta]=fail(res,meta,'ts_simulate_ibr_hybrid:diagnostic',me);
        return;
    else
        meta.partial_diagnostic_failure_id=me.identifier;
        meta.partial_diagnostic_failure_reason=me.message;
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
    'min_off',case_data.delays.T_sg_min_off_s,'sync_overrides',struct(), ...
    'T_minimum_hold',case_data.delays.T_minimum_hold_s, ...
    'T_guard',case_data.delays.T_guard_s, ...
    'T_lockout',case_data.delays.T_lockout_s, ...
    'rho',case_data.delays.rho);
if isfield(opt,'synchronism_overrides'), s.sync_overrides=opt.synchronism_overrides; end
if isfield(opt,'delays_overrides')
    d=opt.delays_overrides;
    if isfield(d,'T_sg_min_off_s'), s.min_off=d.T_sg_min_off_s; end
    if isfield(d,'dwell_s'), s.sync_dwell=d.dwell_s; end
    if isfield(d,'timeout_s'), s.sync_timeout=d.timeout_s; end
    if isfield(d,'T_minimum_hold_s'), s.T_minimum_hold=d.T_minimum_hold_s; end
    if isfield(d,'T_guard_s'), s.T_guard=d.T_guard_s; end
    if isfield(d,'T_lockout_s'), s.T_lockout=d.T_lockout_s; end
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

function [ok,xr,yr,ur,ecr,active,handler_log,reason,right_norm,stage,dispatch] = ...
    trip_transaction(t,x,y,Y,u,ec,dae,sched,case_data,kcl_tol,automatic_gfm_switching)
%TRIP_TRANSACTION  SG breaker trip + optional GFM commitment (C3/F2).
%   When automatic_gfm_switching=true: open the SG breaker, select/commit the
%   SG_OFF GFM configuration, apply transfer maps, solve one right limit.
%   When automatic_gfm_switching=false: open the SG breaker normally, do NOT
%   invoke the GFM selector, do NOT change IBR modes; run an explicit per-
%   island voltage-forming-source check BEFORE Newton; if no online voltage-
%   forming resource exists, fail closed with noVoltageFormingSource, publish
%   NO right-limit sample, commit NO candidate hybrid state, and end the
%   accepted trajectory at the event-left sample (F2).
if nargin < 11, automatic_gfm_switching = true; end
ok=false; xr=x; yr=y; ur=u; ecr=ec; active=[]; reason='';
right_norm=inf; stage='tripTransaction'; dispatch=struct();
if automatic_gfm_switching
    % --- sg_breaker_trip + optional_gfm_commit (full automatic path) ---
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
    try
        [ur,dispatch]=input_for_dispatch_stage(u,dae,case_data,'post_trip');
    catch me
        stage='dispatch'; reason=sprintf('%s: %s',me.identifier,me.message); return;
    end
    [ok,yr,reason,right_norm]=right_limit(xr,y,Y,dae,ur,ecr,t,kcl_tol);
    if ~ok, stage='rightLimit'; end
    if ok, active=stability.ts_dynamic_state_indices(dae,ecr); end
else
    % --- sg_breaker_trip only (no firmware, F2) ---
    % Open the SG breaker WITHOUT committing any GFM configuration. IBR
    % modes remain unchanged. Then check whether any online voltage-forming
    % resource remains; if not, fail closed with noVoltageFormingSource and
    % publish NO right-limit sample (trajectory ends at the event-left).
    hs_candidate = ec.hybrid_state;
    sg_key = matlab.lang.makeValidName(char(sched.sg_id),'ReplacementStyle','underscore');
    if isfield(hs_candidate,'device_online') && isfield(hs_candidate.device_online,sg_key)
        hs_candidate.device_online.(sg_key) = false;
    end
    if isfield(hs_candidate,'device_modes') && isfield(hs_candidate.device_modes,sg_key)
        hs_candidate.device_modes.(sg_key) = 'breaker_open';
    end
% Per-island voltage-forming-source check (C1): after the SG breaker
    % opens, EVERY energized island must retain at least one online voltage-
    % forming resource. A global "any device is VF" check is insufficient.
    % Delegated to the pure helper stability.per_island_vf_check so the
    % algorithm is unit-testable on a two-island Ybus without a composite DAE.
    [has_vf, failing_island_ids, vf_bus_positions] = ...
        stability.per_island_vf_check(Y, case_data.mpc, dae.devices, ...
            hs_candidate, sched.sg_id); %#ok<VFBUS> vf_bus_positions retained for diagnostics
    handler_log = struct('details','', 'applied', false, 'failure_id', '', ...
        'selected_gfm_indices', [], 'n_gfm_required', [], ...
        'reference_resource_index', [], ...
        'candidate_committed', false, 'candidate_sg_online', false, ...
        'candidate_modes', hs_candidate.device_modes, 'failing_island_ids', [], ...
        'n_failing_islands', 0);
    if ~has_vf
        % Fail closed: one or more islands lack a voltage source.
        stage='noVoltageFormingSource';
        reason='noVoltageFormingSource: per-island checks: island has no VF.';
        if ~isempty(failing_island_ids)
            reason = sprintf('%s Failing islands: %s.', reason, ...
                strjoin(string(failing_island_ids), ', '));
        end
        handler_log.failure_id='ts_simulate_ibr_hybrid:noVoltageFormingSource';
        handler_log.details=reason;
        handler_log.candidate_committed = false;
        handler_log.candidate_sg_online = false;
        handler_log.candidate_modes = hs_candidate.device_modes;
        handler_log.failing_island_ids = failing_island_ids;
        handler_log.n_failing_islands = numel(failing_island_ids);
        return;
    end
    % A voltage-forming resource remains; proceed through the ordinary
    % right-limit solve with IBR modes unchanged.
    ecr=ec; ecr.hybrid_state=stability.ts_hybrid_state_snapshot(hs_candidate);
    ur=u;  % no dispatch change (no GFM commit)
    [ok,yr,reason,right_norm]=right_limit(x,y,Y,dae,ur,ecr,t,kcl_tol);
    if ~ok, stage='rightLimit'; end
    if ok
        active=stability.ts_dynamic_state_indices(dae,ecr);
        handler_log.applied=true;
        handler_log.details=sprintf('SG %s breaker opened (no firmware); voltage-forming source retained.',sched.sg_id);
    end
end
end

function tf = is_voltage_forming_mode(dev, mode)
tf = false;
if isempty(mode), return; end
if strcmpi(mode,'synchronous'), tf=true; return; end
if isfield(dev,'capabilities') && isstruct(dev.capabilities) && ...
        isfield(dev.capabilities,'voltage_forming_modes')
    vf = string(dev.capabilities.voltage_forming_modes);
    tf = any(strcmpi(vf, lower(mode)));
end
end

function diag = reclose_left_state_diag(t, x, y, u, ec, dae, sched, Y, guard, right_norm)
%RECLOSE_LEFT_STATE_DIAG  Read-only diagnostic of the left-limit state at a
% failed reclose attempt (Phase 5 instrumentation). Records the SG rotor
% state, bus voltage, guard margins, and right-limit residual so the failure
% can be attributed to a physically infeasible close (relaxed guard allowing a
% non-synchronous SG state) rather than a numerical bug. Does NOT alter the
% trajectory or relax any gate.
diag = struct('t', t, 'right_norm', right_norm);
try
    idx = find(strcmp({dae.devices.device_id}, sched.sg_id));
    if numel(idx) == 1
        dev = dae.devices(idx);
        xi = dae.device_offsets(idx)+(1:dev.nx);
        rec = dev.reconstruct(t, x(xi), y, u(dae.u_offsets(idx)+(1:dev.nu)), ec);
        if isfield(rec,'delta'), diag.sg_delta = rec.delta; end
        if isfield(rec,'omega'), diag.sg_omega = rec.omega; end
        if isfield(rec,'V_open_circuit'), diag.sg_V_open_circuit = rec.V_open_circuit; end
        diag.sg_bus_position = dev.bus_position;
        vb = complex(y(2*dev.bus_position-1), y(2*dev.bus_position));
        diag.bus_voltage_pu = abs(vb);
        diag.bus_angle_deg = angle(vb)*180/pi;
        if isfield(rec,'V_open_circuit') && isfinite(rec.V_open_circuit)
            diag.dV_pu = abs(abs(vb) - abs(rec.V_open_circuit));
        end
        if isfield(rec,'omega') && isfinite(rec.omega)
            diag.df_pu = abs(rec.omega - 1.0);
        end
        if isfield(rec,'delta') && isfinite(rec.delta)
            diag.dtheta_deg = abs(angle(vb)*180/pi - rec.delta*180/pi);
        end
    end
catch %#ok<CTCH>
    % Diagnostic must never throw; partial fields are acceptable.
end
if isstruct(guard) && ~isempty(fieldnames(guard))
    diag.guard = guard;
end
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

function [deadline, status] = compute_tdown(selector_table, case_data, settings, actual_reclose)
%COMPUTE_TDOWN  Derive T_down from the SG_ON table candidate's Omega_target.
%   T_settle = ln(1/rho) / (-Omega_target); T_down = max(T_minimum_hold, T_settle).
%   Fail closed (status) if Omega_target is missing/stale/unstable (>= 0).
deadline = NaN;
status = 'PENDING';
if ~isfield(selector_table,'sg_on') || ~isstruct(selector_table.sg_on)
    status = 'NO_FEASIBLE_SG_ON';
    return;
end
sg_on = selector_table.sg_on;
if ~isfield(sg_on,'ready_to_commit') || ~sg_on.ready_to_commit
    status = 'NO_FEASIBLE_SG_ON';
    return;
end
omega_target = sg_on.omega;
if ~isfinite(omega_target) || omega_target >= 0
    status = 'OMEGA_INVALID';
    return;
end
rho = settings.rho;
if ~isfinite(rho) || rho <= 0 || rho >= 1
    status = 'OMEGA_INVALID';
    return;
end
t_settle = log(1/rho) / (-omega_target);
t_down = max(settings.T_minimum_hold, t_settle);
deadline = actual_reclose + t_down;
end

function status = reselection_failure_status(reason)
if contains(reason, 'fingerprint', 'IgnoreCase', true)
    status = 'FINGERPRINT_MISMATCH';
elseif contains(reason, 'transfer', 'IgnoreCase', true) || contains(reason, 'continuity', 'IgnoreCase', true)
    status = 'TRANSFER_FAILED';
elseif contains(reason, 'KCL', 'IgnoreCase', true) || contains(reason, 'residual', 'IgnoreCase', true)
    status = 'KCL_FAILED';
elseif contains(reason, 'omega', 'IgnoreCase', true)
    status = 'OMEGA_INVALID';
else
    status = 'NO_FEASIBLE_SG_ON';
end
end

function [ok, x_right, y_right, u_right, ec_right, handler_log, reason, right_norm, no_mode_change] = ...
    reselection_transaction(t, x, y, Y, u, ec, dae, sched, case_data, settings, opt)
%RESELECTION_TRANSACTION  Phase-2 SG_ON indexed reselection.
%   Looks up the authenticated SG_ON table, verifies the fingerprint, ranks
%   candidates vs the current committed config, and applies the selector-
%   chosen GFM->GFL transitions via device-owned transfer maps. If no mode/
%   online change is required (F5), no transfer/right-limit/sample occurs.
ok = false; x_right = x; y_right = y; u_right = u; ec_right = ec;
reason = ''; right_norm = inf; no_mode_change = false;
handler_log = struct('details', '');
if ~isfield(opt, 'selector_table') || ~isstruct(opt.selector_table)
    reason = 'selector table missing';
    return;
end
table = opt.selector_table;
% Verify the selector_table_fingerprint against current immutable inputs (F1).
% A stale table fails closed without rolling back Phase 1.
if ~isfield(table, 'sg_on') || ~isstruct(table.sg_on)
    reason = 'SG_ON table missing';
    return;
end
sg_on = table.sg_on;
if ~isfield(sg_on, 'ready_to_commit') || ~sg_on.ready_to_commit
    reason = sprintf('SG_ON selector not ready to commit: %s', sg_on.selection_status);
    return;
end
% Build the target mode vector from the selected SG_ON candidate.
target_modes = build_target_modes(sg_on, dae, ec);
if isempty(target_modes)
    reason = 'could not build target modes from SG_ON selection';
    return;
end
% Determine which devices actually change mode (F5: no-mode-change case).
current_modes = current_mode_vector(dae, ec);
changing = find_mode_changes(current_modes, target_modes);
if isempty(changing)
    % F5: no mode/online change required. No transfer, no right-limit solve,
    % no duplicate sample. Update committed_config_fingerprint only.
    no_mode_change = true;
    ok = true;
    handler_log.details = sprintf('SG_ON reselection: no mode change required (selected GFM set unchanged) at t=%.3f.', t);
    return;
end
% Apply the selector-chosen GFM->GFL transitions via device-owned transfer
% maps (complex-current continuity |I_right-I_left| <= 1e-10).
ec_right = ec;
ec_right.hybrid_state = stability.ts_hybrid_state_snapshot(ec.hybrid_state);
for k = 1:numel(changing)
    idx = changing(k);
    dev = dae.devices(idx);
    key = matlab.lang.makeValidName(char(dev.device_id), 'ReplacementStyle', 'underscore');
    ec_right.hybrid_state.device_modes.(key) = target_modes{idx};
end
try
    x_right = apply_device_transfers(x, y, u, ec, ec_right, dae);
catch me
    reason = sprintf('transfer map failed: %s: %s', me.identifier, me.message);
    return;
end
% Update hybrid_state selector fields atomically (F1/C1).
hs = ec_right.hybrid_state;
hs.selected_gfm_indices = sg_on.selected_gfm_indices;
hs.n_gfm_required = sg_on.n_gfm_required;
% reference_owner_indices stays at SG; gfm_reference_resource_indices stays empty.
if isfield(hs, 'committed_config_fingerprint')
    version = 0;
    if isfield(hs, 'selector_table_version') && isnumeric(hs.selector_table_version) && ...
            isscalar(hs.selector_table_version) && isfinite(hs.selector_table_version)
        version = hs.selector_table_version;
    end
    version = version + 1;
    hs.selector_table_version = version;
    hs.committed_config_fingerprint = sprintf( ...
        'sg_on_reselection|selected=%s|n=%d|version=%d', ...
        mat2str(sg_on.selected_gfm_indices), sg_on.n_gfm_required, version);
end
ec_right.hybrid_state = hs;
% One final right-limit solve after all transfers.
[ok, y_right, reason, right_norm] = right_limit(x_right, y, Y, dae, u_right, ec_right, t, settings.kcl_tol);
if ok
    handler_log.details = sprintf('SG_ON reselection committed at t=%.3f; %d device(s) transitioned.', ...
        t, numel(changing));
end
end

function modes = build_target_modes(sg_on_result, dae, ~)
%BUILD_TARGET_MODES  Build the target mode vector from the SG_ON selection.
nd = numel(dae.devices);
modes = cell(1, nd);
selected = sg_on_result.selected_gfm_indices;
for k = 1:nd
    dev = dae.devices(k);
    if isfield(dev, 'capabilities') && isfield(dev.capabilities, 'resource_type') && ...
            strcmpi(char(dev.capabilities.resource_type), 'sg')
        modes{k} = 'synchronous';
    elseif ismember(k, selected)
        modes{k} = 'gfm';
    else
        modes{k} = 'gfl';
    end
end
end

function modes = current_mode_vector(dae, ec)
nd = numel(dae.devices);
modes = cell(1, nd);
for k = 1:nd
    dev = dae.devices(k);
    key = matlab.lang.makeValidName(char(dev.device_id), 'ReplacementStyle', 'underscore');
    if isfield(ec.hybrid_state.device_modes, key)
        modes{k} = char(ec.hybrid_state.device_modes.(key));
    else
        modes{k} = '';
    end
end
end

function idx = find_mode_changes(before, after)
idx = [];
for k = 1:numel(before)
    if ~strcmpi(before{k}, after{k})
        idx(end+1) = k; %#ok<AGROW>
    end
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

function [ok,x_right,y_right,u_right,ec_right,handler_log,reason,right_norm,dispatch]= ...
    reclose_transaction(t,x,y,Y,u,ec,initial_u,dae,sched,kcl_tol)
ok=false; x_right=x; y_right=y; u_right=u; ec_right=ec;
reason=''; right_norm=inf; dispatch=struct();
event=struct('type','sg_reclose_request','t',t,'sg_id',sched.sg_id);
[hs_candidate,handler_log]=stability.sg_event_handler(ec.hybrid_state,event,dae.devices,struct());
if ~handler_log.applied
    reason=sprintf('%s: %s',handler_log.failure_id,handler_log.details); return;
end
% The SG handler owns only the breaker transition.  IBRs remain in their
% committed post-trip modes: forcing GFM->GFL at breaker close can violate the
% target GFL current/power contract and is not part of the sourced SG reclose
% event.  No SG or IBR differential coordinate is fabricated here.
ec_right=ec; ec_right.hybrid_state=stability.ts_hybrid_state_snapshot(hs_candidate);
u_right=initial_u;
dispatch=dispatch_snapshot(u_right,dae);
[ok,y_right,reason,right_norm]=right_limit(x_right,y,Y,dae,u_right,ec_right,t,kcl_tol);
end

function [u_new,dispatch]=input_for_dispatch_stage(u,dae,case_data,stage)
%INPUT_FOR_DISPATCH_STAGE Apply the explicit CASE_DEFINED MW contract.
% P_ref is an input, not a state jump.  The physical mode transfer is made
% first at the left-side V/I; only then is the new controller reference
% committed together with the right-limit algebraic solution.
if ~strcmp(stage,'post_trip') || ~isfield(case_data,'dispatch_contract') || ...
        ~isfield(case_data.dispatch_contract,'post_trip') || ...
        ~isfield(case_data.dispatch_contract.post_trip,'post_trip_Pg_MW')
    error('ts_simulate_ibr_hybrid:missingDispatchContract', ...
        'The case lacks dispatch_contract.post_trip.post_trip_Pg_MW.');
end
contract=case_data.dispatch_contract.post_trip.post_trip_Pg_MW;
if ~isstruct(contract) || ~isscalar(contract)
    error('ts_simulate_ibr_hybrid:badDispatchContract', ...
        'post_trip_Pg_MW must be one scalar struct keyed by device_id.');
end
Sbase=case_data.mpc.baseMVA;
if ~isscalar(Sbase) || ~isfinite(Sbase) || Sbase<=0
    error('ts_simulate_ibr_hybrid:badDispatchContract','baseMVA must be finite positive.');
end
u_new=u;
for k=1:numel(dae.devices)
    dev=dae.devices(k);
    if ~is_ibr_device(dev), continue; end
    id=char(dev.device_id);
    if ~isfield(contract,id)
        error('ts_simulate_ibr_hybrid:missingDispatchEntry', ...
            'Post-trip dispatch lacks device %s.',id);
    end
    mw=contract.(id);
    if ~isnumeric(mw) || ~isscalar(mw) || ~isreal(mw) || ~isfinite(mw)
        error('ts_simulate_ibr_hybrid:badDispatchEntry', ...
            'Post-trip dispatch for %s must be one finite real MW value.',id);
    end
    slot=find(strcmpi(string(dev.input_names),'P_ref'));
    if numel(slot)~=1
        error('ts_simulate_ibr_hybrid:badDispatchInput', ...
            'Device %s must declare exactly one P_ref input.',id);
    end
    u_new(dae.u_offsets(k)+slot)=mw/Sbase;
end
dispatch=dispatch_snapshot(u_new,dae);
end

function dispatch=dispatch_snapshot(u,dae)
dispatch=struct();
for k=1:numel(dae.devices)
    dev=dae.devices(k);
    if ~is_ibr_device(dev), continue; end
    slot=find(strcmpi(string(dev.input_names),'P_ref'));
    if numel(slot)==1
        dispatch.(char(dev.device_id))=u(dae.u_offsets(k)+slot);
    end
end
end

function tf=is_ibr_device(dev)
tf=isfield(dev,'capabilities') && isstruct(dev.capabilities) && ...
    isfield(dev.capabilities,'resource_type') && ...
    strcmpi(char(dev.capabilities.resource_type),'ibr');
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

function s=new_samples(x,y,u,ec,active,topology)
s=struct('t',0,'x',x(:),'y',y(:),'u',u(:),'side',{{'initial'}}, ...
    'topology',{{topology}},'context',{{ec}},'active',{{active(:)'}}, ...
    'transaction_id',0);
end

function s=append_sample(s,t,x,y,u,ec,active,topology,side,tx_id)
if nargin < 10, tx_id=0; end
s.t(end+1)=t; s.x(:,end+1)=x(:); s.y(:,end+1)=y(:); s.u(:,end+1)=u(:);
s.side{end+1}=side; s.topology{end+1}=topology;
s.context{end+1}=ec; s.active{end+1}=active(:)';
s.transaction_id(end+1)=tx_id;
end

function s=mark_transaction_left(s,t,x,y,u,ec,active,topology,tx_id)
%MARK_TRANSACTION_LEFT Publish or relabel the accepted pre-transaction limit.
% If another transaction already published a right limit at the same physical
% time, preserve it and append a distinct left limit for this transaction.
same_time = ~isempty(s.t) && abs(s.t(end)-t) <= 10*eps(max(1,abs(t)));
if same_time && ~strcmp(s.side{end},'right') && s.transaction_id(end)==0
    s.side{end}='left';
    s.transaction_id(end)=tx_id;
else
    s=append_sample(s,t,x,y,u,ec,active,topology,'left',tx_id);
end
end

function log=new_event_log(type,t)
log=struct('type',type,'t',t,'applied',false,'failure_id','', ...
    'details','','pre_kcl_norm',NaN,'right_kcl_norm',NaN, ...
    'selected_gfm_indices',[],'reference_resource_index',[], ...
    'guard',struct(),'status',struct(),'input_before',[], ...
    'input_after',[],'dispatch_after_pu',struct(), ...
    'transaction_id',0, ...
    'candidate_committed',[],'candidate_sg_online',[], ...
    'candidate_modes',struct(),'failing_island_ids',[], ...
    'n_failing_islands',0, ...
    'reclose_diag',struct());
end

function [converged,id,reason,log]=transition_failure(id,reason,log)
converged=false; log.failure_id=id; log.details=reason;
end

function res=add_diagnostics(res,dae,case_data)
nt=numel(res.t); nd=numel(dae.devices); nb=numel(dae.mapping.bus_ids);
I=complex(zeros(nd,nt)); P=zeros(nd,nt); Q=zeros(nd,nt);
freq=nan(nd,nt); H=nan(nd,nt); limit=nan(nd,nt);
modes=cell(nd,nt); online=false(nd,nt);
for j=1:nt
    y=res.y_traj(:,j); x=res.x_traj(:,j); u=res.u_history(:,j);
    ec=res.event_context_history{j};
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
        % Absolute frequency is an electrical-system trace only while the
        % resource is online.  An open SG rotor may physically coast, but
        % plotting that mechanical speed as a connected-grid frequency is
        % misleading; preserve the state in x_traj and mask the display data.
        if ~online(k,j)
            freq(k,j)=NaN;
            H(k,j)=NaN;
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
    'transaction_id', [], ...
    'u_history',[], ...
    'topology_history',{{}},'event_context_history',{{}},'active_state_history',{{}}, ...
    'events',[],'event_log',[],'converged',false,'failure_id','', ...
    'failure_reason','','requested_sg_on_time',NaN,'actual_reclose_time',NaN, ...
    'reclose_status','NOT_REQUESTED','sched',struct(), ...
    'bus_voltage_magnitude',[],'device_currents',[],'device_current_magnitude',[], ...
    'device_P',[],'device_Q',[],'sg_omega',[],'sg_freq',[],'sg_indices',[], ...
    'device_modes_history',{{}},'Y_log',{{}},'residual_per_step',[], ...
    'iter_per_step',[],'step_attempts',0,'accepted_steps',0,'status_log',[], ...
    'actual_mode_reselection_time',NaN,'reselection_status','NOT_REQUESTED', ...
    'reference_owner_indices',[],'gfm_reference_resource_indices',[], ...
    'reference_island_ids',[],'committed_config_fingerprint','', ...
    'pre_event_input_fingerprint','', ...
    'selector_table_fingerprint','');
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
