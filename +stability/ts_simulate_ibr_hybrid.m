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
    % The public TS contract is structured fail-closed (no uncaught exception),
    % but the governing validation identifier must remain observable.  Collapsing
    % every initialization rejection to badInput hid whether an atomic healthy-PF
    % pair was incomplete, duplicated, or otherwise malformed.
    failure_id = me.identifier;
    if isempty(failure_id)
        failure_id = 'ts_simulate_ibr_hybrid:badInput';
    end
    [res,meta] = fail(res,meta,failure_id,me);
    return;
end

Ypre = dae.Ynet;
Yfault = Ypre;
if sched.enabled && sched.has_fault
    fp = sched.fault_bus_position;
    Yfault(fp,fp) = Yfault(fp,fp)+1/sched.Zf;
end
Ypost = Ypre;
Ycurr = Ypre;
Ybase_current = Ypre;
Yload_delta = zeros(size(Ypre));
Yline_stamp = zeros(size(Ypre));
if sched.enabled && isfield(sched,'has_chronology') && sched.has_chronology
    Vpf=dae.pf.bus_voltage(:);
    Sload=(case_data.mpc.bus(:,3)+1i*case_data.mpc.bus(:,4))/case_data.mpc.baseMVA;
    Yload_delta=sched.load_step_factor*diag(conj(Sload)./(abs(Vpf).^2+eps));
    Yline_stamp=chronology_branch_stamp(case_data.mpc,sched.line_from_bus, ...
        sched.line_to_bus,dae.bus_ids);
end
topology = 'pre';
x = x0(:);
y = y0(:);
t = 0.0;
active = stability.ts_dynamic_state_indices(dae,ec);
pre_event_input = u;
pre_event_input_fp = sprintf('pre_event_input|%s', mat2str(pre_event_input(:).'));
sync_ctl=initialize_sync_controller(dae,u,sched,case_data);

samples = new_samples(x,y,u,ec,active,topology);
% Admittance log for the opt-in reference-AGSI overlay only. It records the
% (time, label, Y) of every topology in force so the post-processor can compute
% a topology-correct Thevenin/SCR. Empty and untouched when the overlay is off.
Ylog = struct('t',{},'topology',{},'Y',{});
if settings.agsi_reference_enabled
    Ylog(1)=struct('t',0,'topology',topology,'Y',Ycurr);
end
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
sg_on_cand = [];  % authenticated SG_ON candidate (Step 5); [] until authenticated
sg_on_auth_ok = false;
% Per-device down-line timers for the opt-in severity handback.  A timer is
    % finite only while that online GFM's complete V/f evidence stays below
    % Gamma_off; each device therefore earns its own T_d_off dwell.
    severity_release_since = nan(1,numel(dae.devices));
    % SG-off AGSI supervisor timers.  A single system up/down timer is used
    % because J_f is a system signal and every online switchable IBR is checked
    % before a configuration transaction.  Hysteresis makes the timers
    % mutually exclusive. Rejected transactions are lockout-limited.
    support_up_since = NaN;
    support_down_since = NaN;
    support_retry_after = -Inf;
    support_status = 'DISABLED';
    support_predictor_active = false;
    predictor_prev_x = [];
    predictor_prev_t = NaN;
transaction_counter = 0;
controller_audit = struct();
converged = true;
failure_id = '';
failure_reason = '';
total_iterations = 0;
max_residual = 0;
step_iterations = [];
step_residuals = [];
accepted_step_residuals = [];
step_attempts = 0;
accepted_steps = 0;
internal_substeps = 0;
domain_rejected_total = 0;
subdivision_depth = 0;
subdivision_hint = 0;
rannacher_steps_remaining=0;
% --- Adaptive-step controller state (opt-in; unused on the fixed path) -------
% dt_adaptive carries the proposed nominal step between accepted steps and is
% reinitialized to dt_min at each event (discontinuity restart). The rejection
% record mirrors ts_adaptive_driver's rejection_history schema.
dt_adaptive = settings.dt;
rejected_steps = 0;
floor_accepted_steps = 0;
dt_history = [];
lte_history = [];
rejection_history = repmat(struct('t',NaN,'attempted_dt',NaN,'error_norm',NaN, ...
    'alg_residual',NaN,'converged',false,'reject_count',0,'reason','', ...
    'retry_dt',NaN),0,1);
% --- Phase-1 read-only resynchronization diagnostics (Mission C) -------------
% Per-sample record of the synchronism state during the breaker-open interval. These
% accumulators are written but never read by the integration logic, so they do
% not alter the trajectory. They expose the actual grid-relative voltage,
% frequency, and phase margins used by the reclose transaction.
% Start as a completely empty struct (1×1, zero fields). The first appended
% record DEFINES the field template, and every subsequent record must match it.
% This avoids MATLAB struct-array field-type mismatch between a pre-declared
% empty template (e.g. char '' vs char 'none') and the real records.
resync_diag = struct();

while t < settings.t_end-settings.event_tol
    if settings.stepper=="adaptive"
        % Error-controlled proposal. dt_max_armed keeps event-crossing
        % detection on a cadence comparable to the fixed grid while a
        % supervisor decision is pending (decision-parity safeguard, not a
        % reclose fix). The post-event Rannacher restart is handled by the
        % dt_adaptive=dt_min reinitialization at the event, not a proposal cap.
        dt_prop = dt_adaptive;
        if pending_reclose || pending_reselection || ...
                (settings.severity_support_enabled && ~sg_online_state(dae,ec))
            dt_prop = min(dt_prop,settings.dt_max_armed);
        end
        target = min(t+dt_prop,settings.t_end);
    else
        target = min(t+settings.dt,settings.t_end);
    end
    if event_cursor <= numel(events)
        target = min(target,events(event_cursor).t);
    end
    if pending_reclose
        target = min(target,sched.sg_on+settings.sync_timeout);
        if isfinite(good_since)
            target = min(target,good_since+settings.sync_dwell);
        end
    end
    if pending_reselection
        if settings.severity_handback_enabled
            due = severity_release_since(isfinite(severity_release_since)) + ...
                settings.severity_T_d_off;
            due = due(due > t+settings.event_tol);
            if ~isempty(due), target=min(target,min(due)); end
        elseif isfinite(reselection_deadline) && ...
                reselection_deadline>t+settings.event_tol
            target=min(target,reselection_deadline);
        end
    end
    if sync_ctl.active && sync_ctl.online && sync_ctl.handback_active
        target=min(target,sync_ctl.handback_t0+sync_ctl.handback_T);
    end
    if settings.severity_support_enabled && ~sg_online_state(dae,ec)
        due=[];
        if isfinite(support_up_since)
            due(end+1)=support_up_since+settings.severity_T_d_on; %#ok<AGROW>
        end
        if isfinite(support_down_since)
            due(end+1)=support_down_since+settings.severity_T_d_off; %#ok<AGROW>
        end
        due=due(due>t+settings.event_tol);
        if ~isempty(due), target=min(target,min(due)); end
    end
    h = target-t;
    if h <= settings.event_tol
        t = target;
    elseif settings.stepper=="adaptive"
        % --- Error-controlled adaptive step (step-doubling trapezoidal) -------
        % Operates on local temporaries; nothing outside {rejected_steps,
        % rejection_history, counters} is written until the single atomic
        % commit below, so a rejected trial advances no supervisor state.
        x_step_left=x;
        t_step_left=t;
        active = stability.ts_dynamic_state_indices(dae,ec);
        predictor='hold';
        if support_predictor_active, predictor=settings.state_predictor; end
        step_opt = struct('newton_tol',settings.newton_tol, ...
            'max_iter',settings.max_iter,'fd_eps',settings.fd_eps, ...
            'verbose',settings.verbose,'full_kcl',true,'t_now',t, ...
            'domain_preserving_trials',true, ...
            'fd_grouping',settings.fd_grouping, ...
            'fd_structure_check',settings.fd_structure_check, ...
            'state_predictor',predictor);
        % NOTE: the linear predictor is rebuilt per ATTEMPT below, because it
        % scales with the trial step. Building it once from the nominal h and
        % reusing it across halved retries hands Newton an initial guess a
        % factor h/h_try too far along the trajectory, which is what makes a
        % small-step retry fail where the full step converged.
        predictor_usable = support_predictor_active && ...
            strcmpi(predictor,'linear_kcl') && ~isempty(predictor_prev_x) && ...
            isfinite(predictor_prev_t) && t>predictor_prev_t+settings.event_tol;
        % Post-event restart mirrors the FIXED path exactly (its
        % rannacher_steps_remaining=1 is consumed by ONE backward-Euler step):
        % the next step and only the next is a single damped-BE solve of the
        % full target h, convergence-controlled (no LTE gate), after which
        % trapezoidal stepping resumes. A small BE window followed by
        % LTE-controlled trapezoidal steps cannot reproduce this: the
        % trapezoidal controller then tries to meet the tolerance across the
        % event-induced kink by halving all the way to dt_min, where Newton
        % itself loses convergence on the low-voltage state. The fixed path
        % never does that; neither does this.
        use_be = rannacher_steps_remaining>0;
        reject_count=0; h_try=h; target_try=target;
        attempt_iterations=0; floor_accepted=false;
        be_floor=false;   % order-reduction rescue at the dt_min floor (set below)
        while true
            attempt_opt=step_opt;
            if predictor_usable
                ratio=h_try/(t-predictor_prev_t);
                attempt_opt.x_predictor=x+ratio*(x-predictor_prev_x);
            end
            step_is_be = use_be || be_floor;
            [cand,est,astats]=advance_adaptive_step( ...
                x,y,t,h_try,dae,Ycurr,u,ec,active,attempt_opt,settings, ...
                sync_ctl,step_is_be,case_data);
            step_attempts=step_attempts+1;
            total_iterations=total_iterations+astats.iterations;
            attempt_iterations=attempt_iterations+astats.iterations;
            domain_rejected_total=domain_rejected_total+astats.domain_rejected;
            at_floor = h_try <= settings.dt_min*(1+1e-12);
            if step_is_be
                % Backward-Euler step (post-event window OR floor rescue). The
                % coupled Newton solves the FULL KCL rows to newton_tol
                % (1e-8 < kcl_tol), so convergence already certifies the
                % algebraic residual; there is no Richardson estimate to gate.
                accept_this=cand.converged;
                lte_ok=true;
                % A mid-coast BE step (be_floor, not an event restart) is a
                % floor acceptance: it took the dt_min step the trapezoidal
                % controller could not.
                floor_accepted = accept_this && be_floor && ~use_be;
            else
                lte_ok = cand.converged && est.usable && ...
                    est.err<=1 && est.alg_res<=settings.kcl_tol;
                % Floor acceptance for the non-smooth current-limiter kink:
                % at dt_min a fully solved trapezoidal step (Newton converged
                % AND KCL residual within kcl_tol) is ACCEPTED even when the
                % Richardson LTE cannot be met, because the LTE is measuring a
                % C0 switching kink, not a resolvable smooth error, and further
                % halving cannot reduce it. Every such step still satisfies the
                % same newton_tol/kcl_tol contract as a fixed step (which also
                % descends to ~dt/2^max_step_subdivisions at hard points via
                % failure-driven subdivision). This is a NUMERICAL_METHOD
                % step-control policy for a switched system; it relaxes no
                % physical gate and is fully recorded (floor_accepted +
                % lte_history). It is NOT a silent fixed-step fallback: the
                % step taken is dt_min, not the nominal dt.
                floor_ok = at_floor && cand.converged && est.usable && ...
                    est.alg_res<=settings.kcl_tol;
                accept_this = lte_ok || floor_ok;
                floor_accepted = accept_this && ~lte_ok;
            end
            if accept_this, break; end
            rejected_steps=rejected_steps+1; reject_count=reject_count+1;
            rejection_history(end+1)=struct('t',t,'attempted_dt',h_try, ...
                'error_norm',est.err,'alg_residual',est.alg_res, ...
                'converged',cand.converged,'reject_count',reject_count, ...
                'reason',adaptive_reject_reason(cand,est,settings), ...
                'retry_dt',max(settings.dt_min,h_try/2)); %#ok<AGROW>
            if at_floor
                if ~step_is_be
                    % Order-reduction rescue. At a C0 current-limiter switching
                    % kink the trapezoidal fixed-point iteration averages f at
                    % the two endpoints straddling the switch, which are
                    % inconsistent, so Newton cannot converge and halving only
                    % sharpens the corner. Retry the SAME dt_min step with
                    % L-stable backward-Euler (single-endpoint evaluation),
                    % exactly the order reduction the post-event Rannacher
                    % restart and TR-BDF2 use at a discontinuity. This is NOT a
                    % fixed-step fallback: the step is dt_min (not the nominal
                    % dt), it is recorded, and if BE at dt_min ALSO fails the
                    % run fails closed below. The trajectory is still validated
                    % against the fixed reference by decision-parity + COI.
                    be_floor=true;
                    continue;   % retry at the same h_try under backward-Euler
                end
                % At the floor and STILL not acceptable under BE: the DAE itself
                % could not be solved here. Genuine fail-closed; no fallback.
                converged=false;
                failure_id='ts_simulate_ibr_hybrid:adaptiveDtMin';
                failure_reason=sprintf(['Adaptive step could not satisfy the ' ...
                    'DAE at dt_min=%.3e, t=%.6f (err=%.3e alg_res=%.3e ' ...
                    'converged=%d, backward-Euler rescue attempted). ' ...
                    'No silent fixed-step fallback.'], ...
                    settings.dt_min,t,est.err,est.alg_res,cand.converged);
                break;
            elseif reject_count>=settings.reject_limit
                converged=false;
                failure_id='ts_simulate_ibr_hybrid:adaptiveRejectLimit';
                failure_reason=sprintf(['Adaptive step exceeded reject_limit=%d ' ...
                    'at t=%.6f (last err=%.3e). No silent fixed-step fallback.'], ...
                    settings.reject_limit,t,est.err);
                break;
            end
            h_try=max(settings.dt_min,h_try/2); target_try=t+h_try;
        end
        if ~converged
            step_iterations(end+1)=attempt_iterations; %#ok<AGROW>
            step_residuals(end+1)=cand.residual_norm; %#ok<AGROW>
            accepted_step_residuals(end+1)=cand.residual_norm; %#ok<AGROW>
            max_residual=max(max_residual,cand.residual_norm);
            break;
        end
        % --- atomic commit (mirrors the fixed accept block) ------------------
        x=cand.x; y=cand.y;
        if sync_ctl.active
            sync_ctl=cand.sync;
            u=sync_ctl.u_end;
        end
        t=target_try;
        accepted_steps=accepted_steps+1;
        internal_substeps=internal_substeps+1;
        if use_be
            % The Rannacher restart step has been taken; consume the flag so
            % the next step returns to trapezoidal (mirrors the fixed path).
            rannacher_steps_remaining=rannacher_steps_remaining-1;
        end
        if floor_accepted, floor_accepted_steps=floor_accepted_steps+1; end
        max_residual=max(max_residual,cand.residual_norm);
        step_iterations(end+1)=attempt_iterations; %#ok<AGROW>
        step_residuals(end+1)=cand.residual_norm; %#ok<AGROW>
        accepted_step_residuals(end+1)=cand.residual_norm; %#ok<AGROW>
        dt_history(end+1)=h_try; %#ok<AGROW>
        if step_is_be
            % A backward-Euler step (event-restart window OR floor rescue)
            % carries no Richardson estimate; record NaN rather than the
            % unusable sentinel so the diagnostic never reads as "an accepted
            % step had infinite error".
            lte_history(end+1)=NaN; %#ok<AGROW>
        else
            lte_history(end+1)=est.err; %#ok<AGROW>
        end
        if ~step_is_be
            % Controller update on the step ACTUALLY taken (h_try), not on the
            % stale proposal: the clamps at the top of the loop routinely cut
            % the step to land on an event or a supervisor deadline, and
            % scaling a nominal the integrator never used lets dt_adaptive
            % drift away from the achieved step. err==0 is the exact-step case
            % (an equilibrium window, where trapezoidal is exact); the
            % reference controller accelerates by fac_max there rather than
            % leaving dt frozen (ts_adaptive_driver.m:240-244).
            if isfinite(est.err) && est.err>0
                factor=min(settings.controller_fac_max, ...
                    max(settings.controller_fac_min, ...
                    settings.controller_fac*(1/est.err)^(1/3)));
            else
                factor=settings.controller_fac_max;
            end
            dt_adaptive=min(settings.dt_max,max(settings.dt_min,h_try*factor));
        else
            % Resume cautiously after any BE step (Rannacher window or a floor
            % rescue through a limiter kink): re-enter trapezoidal at the small
            % Rannacher window size, not at fac_max*dt_min, so the controller
            % re-earns a larger step from a fresh LTE measurement.
            dt_adaptive=max(settings.dt_min,settings.rannacher_window_dt);
        end
        if support_predictor_active
            predictor_prev_x=x_step_left;
            predictor_prev_t=t_step_left;
        else
            predictor_prev_x=[];
            predictor_prev_t=NaN;
        end
        if settings.progress_every > 0 && ~isempty(settings.progress_file)
            lastp = settings.progress_last;
            if t-lastp >= settings.progress_every
                pfd = fopen(settings.progress_file,'a');
                if pfd>0
                    fprintf(pfd,[ ...
                        'PROGRESS t=%.4f iter=%d residual=%.3e dt=%.3e ' ...
                        'rejects=%d be=%d\n'],t,attempt_iterations, ...
                        cand.residual_norm,h_try,reject_count,use_be);
                    fclose(pfd);
                end
                settings.progress_last = t;
            end
        end
        is_event_left = event_cursor<=numel(events) && ...
            abs(t-events(event_cursor).t)<=settings.event_tol;
        side = ternary(is_event_left,'left','continuous');
        samples = append_sample(samples,t,x,y,u,ec,active,topology,side);
    else
        x_step_left=x;
        t_step_left=t;
        u_step=u; sync_candidate=sync_ctl;
        if sync_ctl.active
            [u_step,sync_candidate]=advance_sync_controller( ...
                sync_ctl,x,y,t,h,dae,ec,u,case_data);
        end
        active = stability.ts_dynamic_state_indices(dae,ec);
        predictor='hold';
        if support_predictor_active, predictor=settings.state_predictor; end
        step_opt = struct('newton_tol',settings.newton_tol, ...
            'max_iter',settings.max_iter,'fd_eps',settings.fd_eps, ...
            'verbose',settings.verbose,'full_kcl',true,'t_now',t, ...
            'domain_preserving_trials',true, ...
            'fd_grouping',settings.fd_grouping, ...
            'fd_structure_check',settings.fd_structure_check, ...
            'state_predictor',predictor);
        if support_predictor_active && strcmpi(predictor,'linear_kcl') && ...
                ~isempty(predictor_prev_x) && isfinite(predictor_prev_t) && ...
                t>predictor_prev_t+settings.event_tol
            ratio=h/(t-predictor_prev_t);
            step_opt.x_predictor=x+ratio*(x-predictor_prev_x);
        end
        if rannacher_steps_remaining>0
            [step,retry_stats]=advance_rannacher_restart( ...
                x,y,t,h,dae,Ycurr,u_step,ec,active,step_opt,settings);
        else
            [step,retry_stats] = advance_with_subdivision_hint( ...
                x,y,t,h,dae,Ycurr,u_step,ec,active,step_opt,settings, ...
                subdivision_hint);
        end
        step_attempts=step_attempts+retry_stats.attempts;
        internal_substeps=internal_substeps+retry_stats.accepted_leaf_steps;
        domain_rejected_total = domain_rejected_total + retry_stats.domain_rejected_trials;
        subdivision_depth = max(subdivision_depth, retry_stats.subdivision_depth);
        total_iterations = total_iterations+step.iterations;
        max_residual = max(max_residual,step.residual_norm);
        step_iterations(end+1)=step.iterations; %#ok<AGROW>
        step_residuals(end+1)=step.residual_norm; %#ok<AGROW>
        accepted_step_residuals(end+1)=retry_stats.accepted_residual_norm; %#ok<AGROW>
        if ~step.converged || ~step.finite
            converged = false;
            failure_id = 'ts_simulate_ibr_hybrid:stepNewton';
            failure_reason = format_step_failure(target, h, step, retry_stats);
            break;
        end
        x = step.x_full;
        y = step.y_full;
        if sync_ctl.active
            sync_ctl=sync_candidate;
            u=sync_ctl.u_end;
        end
        t = target;
        accepted_steps=accepted_steps+1;
        subdivision_hint=next_subdivision_hint( ...
            subdivision_hint,retry_stats,settings.max_step_subdivisions);
        if support_predictor_active
            predictor_prev_x=x_step_left;
            predictor_prev_t=t_step_left;
        else
            predictor_prev_x=[];
            predictor_prev_t=NaN;
        end
        if rannacher_steps_remaining>0
            rannacher_steps_remaining=rannacher_steps_remaining-1;
        end
        % Progress log (presentation-only, opt-in, default off): every
        % settings.progress_every seconds of SIM time, append the current time
        % to settings.progress_file so a long-running batch can be tailed live
        % (MATLAB -batch does not flush stdout until exit). No numerical path
        % reads this file; it exists only to explain where the run stands.
        if settings.progress_every > 0 && ~isempty(settings.progress_file)
            lastp = settings.progress_last;   % initialized to -Inf in initialize()
            if t-lastp >= settings.progress_every
                pfd = fopen(settings.progress_file,'a');
                if pfd>0
                    fprintf(pfd,[ ...
                        'PROGRESS t=%.4f iter=%d residual=%.3e attempts=%d ' ...
                        'leaves=%d depth=%d\n'],t,step.iterations, ...
                        retry_stats.accepted_residual_norm,retry_stats.attempts, ...
                        retry_stats.accepted_leaf_steps,retry_stats.subdivision_depth);
                    fclose(pfd);
                end
                settings.progress_last = t;
            end
        end
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
            Yfault=Ybase_current;
            fp=sched.fault_bus_position;
            Yfault(fp,fp)=Yfault(fp,fp)+1/sched.Zf;
            [ok,y_new,reason,right_norm] = fault_right_limit_homotopy( ...
                x,y,Ybase_current,sched,dae,u,ec,t,settings.kcl_tol);
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
            Ypost=Ybase_current;
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
        case 'load_step'
            Ycandidate=Ybase_current+Yload_delta;
            [ok,y_new,reason,right_norm]=right_limit(x,y,Ycandidate,dae,u,ec,t,settings.kcl_tol);
            log=new_event_log(ev.type,t); log.pre_kcl_norm=pre_norm; log.right_kcl_norm=right_norm;
            if ok
                y=y_new; Ybase_current=Ycandidate; Ycurr=Ycandidate; topology='load_step';
                log.applied=true; log.details='All base constant-impedance loads increased by the frozen factor.';
            else
                [converged,failure_id,failure_reason,log]=transition_failure( ...
                    'ts_simulate_ibr_hybrid:rightLimit',reason,log);
            end
        case 'line_trip'
            Ycandidate=Ybase_current-Yline_stamp;
            [ok,y_new,reason,right_norm]=right_limit(x,y,Ycandidate,dae,u,ec,t,settings.kcl_tol);
            log=new_event_log(ev.type,t); log.pre_kcl_norm=pre_norm; log.right_kcl_norm=right_norm;
            if ok
                y=y_new; Ybase_current=Ycandidate; Ycurr=Ycandidate; topology='line_trip';
                log.applied=true; log.details='Scheduled branch stamp removed.';
            else
                [converged,failure_id,failure_reason,log]=transition_failure( ...
                    'ts_simulate_ibr_hybrid:rightLimit',reason,log);
            end
        case 'topology_restore'
            Ycandidate=Ypre;
            [ok,y_new,reason,right_norm]=right_limit(x,y,Ycandidate,dae,u,ec,t,settings.kcl_tol);
            log=new_event_log(ev.type,t); log.pre_kcl_norm=pre_norm; log.right_kcl_norm=right_norm;
            if ok
                y=y_new; Ybase_current=Ycandidate; Ycurr=Ycandidate; topology='restored';
                log.applied=true; log.details='Base loads and scheduled branch restored before SG reclose request.';
            else
                [converged,failure_id,failure_reason,log]=transition_failure( ...
                    'ts_simulate_ibr_hybrid:rightLimit',reason,log);
            end
        case 'sg_trip'
            agfm = true;
            if isfield(opt,'automatic_gfm_switching') && ~isempty(opt.automatic_gfm_switching)
                agfm = logical(opt.automatic_gfm_switching);
            end
            [ok,x_new,y_new,u_new,ec_new,active_new,handler_log,reason, ...
                right_norm,stage,dispatch_after,trip_controller_audit] = trip_transaction( ...
                t,x,y,Ycurr,u,ec,dae,sched,case_data,settings.kcl_tol,agfm,opt);
            if ~isempty(fieldnames(trip_controller_audit))
                controller_audit = trip_controller_audit;
            end
            log = new_event_log(ev.type,t);
            log.pre_kcl_norm = pre_norm; log.right_kcl_norm = right_norm;
            log.input_before = u;
            log.input_after = u_new;
            log.dispatch_after_pu = dispatch_after;
            % Log the ACTUAL committed candidate (from the authenticated table
            % via handler_log), not the schedule literals — so the audit trail
            % reflects what was published, not what was requested (F2/advisor).
            if isfield(handler_log, 'selected_gfm_indices')
                log.selected_gfm_indices = handler_log.selected_gfm_indices;
            else
                log.selected_gfm_indices = [];
            end
            if isfield(handler_log, 'reference_resource_index')
                log.reference_resource_index = handler_log.reference_resource_index;
            else
                log.reference_resource_index = [];
            end
            if ok
                x=x_new; y=y_new; u=u_new; ec=ec_new; active=active_new;
                sync_ctl=activate_sync_controller(sync_ctl,u,t);
                log.applied=true; log.details=handler_log.details;
                t_trip=t;
            else
                % Inline failure handling (preserve log struct fields + copy
                % candidate metadata from handler_log per F2 audit contract).
                converged = false;
                % Preserve the structured failure_id from the handler when one
                % is present (e.g. missingAuthenticatedSelectorTable,
                % manualCandidateNotInTable, candidateNotReady) instead of
                % collapsing to a generic stage ID (advisor #6).
                if isfield(handler_log, 'failure_id') && ~isempty(handler_log.failure_id)
                    failure_id = handler_log.failure_id;
                else
                    failure_id = ['ts_simulate_ibr_hybrid:' stage];
                end
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
        append_progress_event(settings,t,ev.type,log.applied,log.details);
        event_cursor = event_cursor+1;
        event_applied = true;
        if ~converged, break; end
    end
    if ~converged, break; end
    if event_applied
        active = stability.ts_dynamic_state_indices(dae,ec);
        samples = append_sample(samples,t,x,y,u,ec,active,topology,'right',group_tx_id);
        if settings.agsi_reference_enabled
            Ylog(end+1)=struct('t',t,'topology',topology,'Y',Ycurr); %#ok<AGROW>
        end
        rannacher_steps_remaining=1;
        subdivision_hint=0;
        predictor_prev_x=[];
        predictor_prev_t=NaN;
        % Adaptive discontinuity restart: an event is a C0 (or worse) break in
        % the trajectory, so the pre-event step size is meaningless afterward.
        % Every production adaptive DAE integrator reinitializes the step at a
        % discontinuity (CVODE, ode15s, ...); carrying the coarse pre-event dt
        % into the post-event Rannacher step made the order-1 BE restart span
        % the sharpest part of the transient and injected an O(0.1) state error
        % that the controller then chased down to the dt_min Newton wall. Reset
        % to the floor and let the LTE controller ramp the step back up (fac_max
        % per accepted step) from a measured error. This reinitializes STEP SIZE
        % only; it changes no error tolerance, equation, or gate, so it is not a
        % post-hoc tolerance retune. Guarded on the adaptive stepper: settings
        % has no dt_min field on the fixed path (initialize only sets the
        % adaptive schema under stepper=='adaptive').
        if settings.stepper=="adaptive"
            dt_adaptive = settings.dt_min;
        end
    end
    % --- Real-time SG-off AGSI support supervisor --------------------------
    % Event names are not switching commands. Every accepted sample is
    % measured using only J_V and J_f. The hysteresis/dwell lines decide WHEN
    % support changes; the authenticated SG_OFF table decides WHICH smallest
    % admissible superset/subset may be attempted. The live-topology
    % right-limit KCL solve remains the final atomic commit gate.
    if settings.severity_support_enabled && ~sg_online_state(dae,ec)
        [sev_ok, online_ibr, sev_values] = online_ibr_severity( ...
            t,x,y,u,ec,dae,settings);
        current_modes=current_mode_vector(dae,ec);
        current_gfm=online_ibr(strcmpi(current_modes(online_ibr),'gfm'));
        current_gfl=online_ibr(strcmpi(current_modes(online_ibr),'gfl'));
        up_stress=false;
        down_healthy=false;
        if sev_ok
            gfl_mask=ismember(online_ibr,current_gfl);
            up_stress=~isempty(current_gfl) && ...
                any(sev_values(gfl_mask)>=settings.severity_gamma_on);
            down_healthy=~isempty(current_gfm) && ...
                all(sev_values<settings.severity_gamma_off);
        end
        hold_ok=isfinite(t_trip) && ...
            t-t_trip>=settings.T_minimum_hold-settings.event_tol;
        if ~hold_ok
            support_up_since=NaN; support_down_since=NaN;
            support_status='MINIMUM_HOLD';
        elseif ~sev_ok
            support_up_since=NaN; support_down_since=NaN;
            support_status='EVIDENCE_UNAVAILABLE';
        elseif up_stress
            if ~isfinite(support_up_since), support_up_since=t; end
            support_down_since=NaN;
            support_status='PENDING_UP_DWELL';
        elseif down_healthy
            support_up_since=NaN;
            if ~isfinite(support_down_since), support_down_since=t; end
            support_status='PENDING_DOWN_DWELL';
        else
            support_up_since=NaN; support_down_since=NaN;
            support_status='HYSTERESIS_HOLD';
        end

        direction=''; candidate=struct(); found=false; selection_audit=struct();
        up_due=isfinite(support_up_since) && ...
            t-support_up_since>=settings.severity_T_d_on-settings.event_tol;
        down_due=isfinite(support_down_since) && ...
            t-support_down_since>=settings.severity_T_d_off-settings.event_tol;
        if t>=support_retry_after-settings.event_tol && up_due
            direction='augment';
            [candidate,found,selection_audit]= ...
                stability.select_support_augmentation_candidate( ...
                opt.selector_table,current_gfm);
        elseif t>=support_retry_after-settings.event_tol && down_due
            direction='release';
            [candidate,found,selection_audit]= ...
                stability.select_support_release_candidate( ...
                opt.selector_table,current_gfm);
        end

        if ~isempty(direction) && found
            transaction_counter=transaction_counter+1;
            support_tx_id=transaction_counter;
            samples=mark_transaction_left(samples,t,x,y,u,ec,active,topology,support_tx_id);
            [ok,x_new,y_new,u_new,ec_new,support_log,reason,right_norm]= ...
                sg_off_support_transaction(t,x,y,Ycurr,u,ec,dae,settings, ...
                candidate,direction);
            log=new_event_log(['gfm_support_' direction],t);
            log.transaction_id=support_tx_id;
            log.pre_kcl_norm=kcl_norm(dae,t,x,y,Ycurr,u,ec);
            log.right_kcl_norm=right_norm;
            log.input_before=u; log.input_after=u_new;
            log.selected_gfm_indices=candidate.selected_gfm_indices;
            log.reference_resource_index=candidate.reference_resource_index;
            if ok
                x=x_new; y=y_new; u=u_new; ec=ec_new;
                active=stability.ts_dynamic_state_indices(dae,ec);
                log.applied=true; log.details=support_log.details;
                samples=append_sample(samples,t,x,y,u,ec,active,topology,'right',support_tx_id);
                % The device-owned transfer already enforces terminal-current
                % continuity and the atomic transaction enforces live KCL.
                % A BE/Rannacher restart here was counterproductive: it moved
                % the accepted controller state off the continuous
                % trapezoidal branch and raised the next-step Newton count
                % from 5 to 20--33. Keep canonical trapezoidal stepping for
                % this bumpless mode-only transaction. Scheduled load/fault/
                % topology discontinuities still retain their restart.
                rannacher_steps_remaining=0;
                subdivision_hint=0;
                support_status=upper(['COMMITTED_' direction]);
                support_retry_after=t+settings.T_lockout;
                support_predictor_active=true;
                predictor_prev_x=[];
                predictor_prev_t=NaN;
            else
                log.applied=false;
                log.failure_id='ts_simulate_ibr_hybrid:sgOffSupportTransaction';
                log.details=reason;
                support_status=upper(['REJECTED_' direction]);
                support_retry_after=t+settings.T_lockout;
            end
            support_up_since=NaN; support_down_since=NaN;
            event_log(end+1,1)=log; %#ok<AGROW>
            log_status=stability.ibr_status_snapshot(log.type,t,dae,ec,active, ...
                kcl_norm(dae,t,x,y,Ycurr,u,ec));
            event_log(end).status=log_status;
            status_log(end+1,1)=log_status; %#ok<AGROW>
            append_progress_event(settings,t,log.type,log.applied,log.details);
        elseif ~isempty(direction) && ~found
            support_status=upper(selection_audit.reason);
            support_retry_after=t+settings.T_lockout;
            support_up_since=NaN; support_down_since=NaN;
        end
    elseif settings.severity_support_enabled
        support_up_since=NaN; support_down_since=NaN;
        support_status='SG_ON';
    end

    if sync_ctl.active && ~pending_reclose && isfield(sched,'sg_on') && ...
            isfinite(sched.sg_on) && t>=sched.sg_on-settings.sync_dwell
        [prequalified,last_guard]=reclose_guard(t,x,y,u,ec,dae,sched,case_data,settings);
        if prequalified
            if ~isfinite(good_since), good_since=t; end
        else
            good_since=NaN;
        end
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
        % --- Phase-1 read-only: record the synchronism state this step --------
        % Pure measurement hook; writes to resync_diag but never alters the
        % trajectory. Limiting gate = the margin that governs eligibility.
        lim_gate = 'none';
        if isstruct(last_guard) && isfield(last_guard,'signed_margin')
            mg = [last_guard.margin_V, last_guard.margin_f, last_guard.margin_theta];
            gates = {'V','f','theta'};
            [~,klim] = min(mg);
            if numel(klim) == 1 && ~eligible
                lim_gate = gates{klim};
            end
        end
        % SG state via device reconstruct (authoritative for delta/omega/V_open).
        % Note: sg_reconstruct does NOT expose Te; for the offline (breaker-open)
        % SG, Te=0 by physics (Pe=0 in sg_composite_device offlineline branch).
        sg_Tm = NaN; sg_Te = NaN; sg_Efd = NaN; sg_delta = NaN; sg_omega = NaN; sgVo = NaN;
        idx_sg = find(strcmp({dae.devices.device_id},sched.sg_id));
        if numel(idx_sg) == 1
            dev_sg = dae.devices(idx_sg);
            ui_sg = dae.u_offsets(idx_sg)+(1:dev_sg.nu);
            xi_sg = dae.device_offsets(idx_sg)+(1:dev_sg.nx);
            if numel(ui_sg) == 2 && numel(xi_sg) == 6
                sg_Tm = u(ui_sg(1)); sg_Efd = u(ui_sg(2));
                rec_sg = dev_sg.reconstruct(t,x(xi_sg),y,u(ui_sg),ec);
                if isfield(rec_sg,'delta'),       sg_delta = rec_sg.delta;       end
                if isfield(rec_sg,'omega'),       sg_omega = rec_sg.omega;       end
                if isfield(rec_sg,'V_open_circuit'), sgVo = rec_sg.V_open_circuit; end
                % Offline SG: Te=0 (breaker open, Pe=0). The reconstruct does not
                % carry Te, so we flag it explicitly when the device is offline.
                if isfield(rec_sg,'online') && ~logical(rec_sg.online)
                    sg_Te = 0;
                end
            end
        end
        % bus voltage magnitude/angle from the network algebraic state.
        busVm = NaN; busAg = NaN;
        if numel(idx_sg) == 1
            bp_sg = dae.devices(idx_sg).bus_position;
            vb = complex(y(2*bp_sg-1), y(2*bp_sg));
            busVm = abs(vb); busAg = angle(vb)*180/pi;
        end
        % Build a UNIFORM record: every field present every time (numeric NaN /
        % char 'none' defaults) so the struct-array append never hits a
        % field-name mismatch between records.
        g = last_guard;  % alias; may be struct() on the very first pass
        rec = struct('t',t, ...
            'eligible',eligible, ...
            'dwell_ok',dwell_ok, ...
            'off_ok',off_ok, ...
            'good_since',good_since, ...
            'dV',NaN, 'df',NaN, 'dtheta',NaN, ...
            'margin_V',NaN, 'margin_f',NaN, 'margin_theta',NaN, ...
            'signed_margin',NaN, ...
            'limiting_gate',lim_gate, ...
            'sg_omega',sg_omega, 'sg_delta',sg_delta, ...
            'sg_V_open',sgVo, ...
            'bus_V_mag',busVm, 'bus_angle_deg',busAg, ...
            'Tm',sg_Tm, 'Te',sg_Te, 'Efd',sg_Efd);
        if isstruct(g) && ~isempty(fieldnames(g))
            if isfield(g,'dV'),           rec.dV           = g.dV;           end
            if isfield(g,'df'),           rec.df           = g.df;           end
            if isfield(g,'dtheta'),       rec.dtheta       = g.dtheta;       end
            if isfield(g,'margin_V'),     rec.margin_V     = g.margin_V;     end
            if isfield(g,'margin_f'),     rec.margin_f     = g.margin_f;     end
            if isfield(g,'margin_theta'), rec.margin_theta = g.margin_theta; end
            if isfield(g,'signed_margin'),rec.signed_margin= g.signed_margin;end
        end
        if isempty(fieldnames(resync_diag))
            resync_diag = rec;            % first record defines the template
        else
            resync_diag(end+1) = rec; %#ok<AGROW> % subsequent records append
        end
        if eligible && dwell_ok && off_ok
            [handback_T,handback_status]=derive_handback_duration( ...
                opt.selector_table,dae,ec,settings,sync_ctl);
            if ~isfinite(handback_T)
                good_since=NaN;
                reclose_status=handback_status;
                continue;
            end
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
                % The breaker close ends the offline phase planner but does
                % not remove the prime-mover dynamics.  Re-enter the sourced
                % Sauer-Pai non-reheat turbine/governor at the restored
                % equilibrium input so Tm is bumpless and frequency remains
                % regulated after the SG resumes network power balance.
                sync_ctl=enter_online_governor(sync_ctl,u_new,t,handback_T);
                active=stability.ts_dynamic_state_indices(dae,ec);
                actual_reclose=t; pending_reclose=false; reclose_status='SUCCESS';
                subdivision_hint=0;
                support_predictor_active=false;
                predictor_prev_x=[];
                predictor_prev_t=NaN;
                log.applied=true; log.details=handler_log.details;
                log.handback_duration_s=handback_T;
                log.handback_status='C1_ACTIVE';
                samples=append_sample(samples,t,x,y,u,ec,active,topology,'right',reclose_tx_id);
                if isfield(sched,'coordinated_handback') && sched.coordinated_handback
                    [hb_ok,hb_x,hb_y,hb_ec,hb_reason,hb_norm]= ...
                        coordinated_sg_handback(t,x,y,Ycurr,u,ec,dae,settings.kcl_tol);
                    if hb_ok
                        x=hb_x; y=hb_y; ec=hb_ec;
                        active=stability.ts_dynamic_state_indices(dae,ec);
                        actual_mode_reselection=t;
                        reselection_status='COORDINATED_SG_REFERENCE_HANDBACK';
                        pending_reselection=false;
                        log.details=[log.details ' Coordinated SG-reference handback committed all IBRs to GFL.'];
                        log.right_kcl_norm=max(log.right_kcl_norm,hb_norm);
                        samples=append_sample(samples,t,x,y,u,ec,active,topology,'right',reclose_tx_id);
                    else
                        [converged,failure_id,failure_reason,log]=transition_failure( ...
                            'ts_simulate_ibr_hybrid:coordinatedHandback',hb_reason,log);
                    end
                else
                    % Begin Phase-2 handback.  With an explicit healthy-PF
                    % profile this is the per-IBR 2-term severity supervisor;
                    % without that profile the authenticated SG_ON selector
                    % remains the legacy authority.
                    pending_reselection=true;
                    reselection_status='PENDING';
                    reselection_good_since=NaN;
                    reselection_deadline=NaN;
                    severity_release_since(:)=NaN;
                    sg_on_cand=[];
                end
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
            append_progress_event(settings,t,'sg_reclose',log.applied,log.details);
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
            append_progress_event(settings,t,'sg_reclose_timeout',false,log.details);
        end
    end
    % --- Phase-2 delayed indexed reselection (F4/F5) -------------------
    % Two authorities are deliberately disjoint:
    %   (1) explicit healthy-PF V references -> scalar AGSI dwell only;
    %   (2) the authenticated SG_ON table -> every physical release guard.
    % The scalar never substitutes for equilibrium/SSSA/reserve/current gates.
    % A severity release is therefore authenticated as an exact one-IBR step
    % against the SG-online table before a mode transaction is attempted.
    if pending_reselection
        severity_enabled = settings.severity_handback_enabled;
        target_modes = {};
        target_selected = [];
        authority = '';
        attempt_transaction = false;

        if severity_enabled
            [sev_ok, current_gfm, sev_values] = post_reclose_severity( ...
                t, x, y, u, ec, dae, settings);
            severity_release_since(setdiff(1:numel(dae.devices),current_gfm)) = NaN;
            if ~sev_ok
                severity_release_since(:) = NaN;
                reselection_status = 'SEVERITY_EVIDENCE_UNAVAILABLE';
            elseif isempty(current_gfm)
                pending_reselection = false;
                reselection_status = 'SUCCESS';
            else
                for q = 1:numel(current_gfm)
                    kdev = current_gfm(q);
                    if sev_values(q) < settings.severity_gamma_off
                        if ~isfinite(severity_release_since(kdev))
                            severity_release_since(kdev) = t;
                        end
                    else
                        severity_release_since(kdev) = NaN;
                    end
                end
                release = current_gfm(isfinite(severity_release_since(current_gfm)) & ...
                    t-severity_release_since(current_gfm) >= ...
                    settings.severity_T_d_off-settings.event_tol);
                hold_ok = isfinite(actual_reclose) && ...
                    t-actual_reclose >= settings.T_minimum_hold-settings.event_tol && ...
                    sync_ctl.handback_complete;
                if hold_ok && ~isempty(release)
                    % The scalar AGSI is only a timing predicate.  Authenticate
                    % each one-device target against the immutable SG_ON table
                    % and choose the deterministic best admissible candidate.
                    selector_table_live = struct();
                    if isfield(opt,'selector_table') && isstruct(opt.selector_table)
                        selector_table_live = opt.selector_table;
                    end
                    [target_selected, release_audit, release_ok] = ...
                        choose_sg_online_one_step( ...
                        selector_table_live, dae, sched, ec, Ycurr, t, case_data, ...
                        current_gfm, release);
                    if release_ok
                        target_modes = modes_from_selected(dae,target_selected);
                        authority = 'severity_sg_online_authenticated';
                        attempt_transaction = true;
                        reselection_status = 'AUTHENTICATED_ONE_STEP_READY';
                    else
                        % Keep the scalar dwell evidence, but fail closed when
                        % the independent SG-online hard guards are absent or
                        % stale.  No mode is changed and no physical state is
                        % fabricated while waiting for a fresh authenticated
                        % candidate.
                        target_selected = [];
                        target_modes = {};
                        authority = '';
                        attempt_transaction = false;
                        reselection_status = release_audit.reason;
                    end
                else
                    reselection_status = 'PENDING_SEVERITY';
                end
            end
        else
            % Legacy compatibility path: authenticate the SG_ON candidate once,
            % derive T_down from its stable mode, and retain all previous gates.
            if ~isstruct(sg_on_cand) && isfield(opt,'selector_table') && ...
                    isstruct(opt.selector_table)
                [sg_on_cand, sg_on_auth_ok, ~, ~] = ...
                    authenticate_sg_on_candidate(opt.selector_table, dae, sched, ...
                    ec, Ycurr, t, case_data);
                if ~sg_on_auth_ok
                    reselection_status = 'NO_FEASIBLE_SG_ON';
                    sg_on_cand = struct();
                end
            end
            if ~isfinite(reselection_deadline) && isstruct(sg_on_cand) && ~isempty(sg_on_cand)
                [reselection_deadline, reselection_status] = compute_tdown( ...
                    sg_on_cand, settings, actual_reclose);
            elseif ~isstruct(sg_on_cand) || isempty(sg_on_cand)
                reselection_status = 'NO_FEASIBLE_SG_ON';
            end
            if isfinite(reselection_deadline) && t >= reselection_deadline-settings.event_tol
                hold_ok = isfinite(t_trip) && ...
                    t-t_trip >= settings.T_minimum_hold-settings.event_tol;
                guard_ok = isfinite(reselection_good_since) && ...
                    t-reselection_good_since >= settings.T_guard-settings.event_tol;
                if hold_ok && guard_ok
                    target_selected = sg_on_cand.selected_gfm_indices;
                    target_modes = build_target_modes_frozen(sg_on_cand,dae);
                    authority = 'selector';
                    attempt_transaction = true;
                else
                    reselection_good_since = t;
                end
            end
        end

        if attempt_transaction
            transaction_counter = transaction_counter + 1;
            reselection_tx_id = transaction_counter;
            samples=mark_transaction_left(samples,t,x,y,u,ec,active,topology,reselection_tx_id);
            [ok, x_new, y_new, u_new, ec_new, rsel_log, reason, right_norm, ...
                no_mode_change] = reselection_transaction( ...
                t, x, y, Ycurr, u, ec, dae, settings, target_modes, ...
                target_selected, authority);
            log = new_event_log('sg_reselection',t);
            log.transaction_id = reselection_tx_id;
            log.pre_kcl_norm = kcl_norm(dae,t,x,y,Ycurr,u,ec);
            log.right_kcl_norm = right_norm;
            log.input_before = u; log.input_after = u_new;
            log.selected_gfm_indices = target_selected;
            if ok
                x=x_new; y=y_new; u=u_new; ec=ec_new;
                active=stability.ts_dynamic_state_indices(dae,ec);
                if ~isfinite(actual_mode_reselection) && ~no_mode_change
                    actual_mode_reselection=t;
                end
                if no_mode_change
                    pending_reselection=false;
                    reselection_status='NO_MODE_CHANGE_REQUIRED';
                    log.details='SG_ON selector chose the current GFM set; no mode change required.';
                else
                    samples=append_sample(samples,t,x,y,u,ec,active,topology,'right',reselection_tx_id);
                    log.details=rsel_log.details;
                    if severity_enabled && ~isempty(target_selected)
                        % The transfer is a discontinuity for the remaining
                        % devices' V/f environment.  Reset all down-line timers;
                        % each residual GFM must earn a fresh full dwell.
                        severity_release_since(:)=NaN;
                        reselection_status='PARTIAL_SEVERITY_RELEASE';
                        pending_reselection=true;
                    else
                        reselection_status='SUCCESS';
                        pending_reselection=false;
                    end
                end
                log.applied=true;
            else
                % A rejected transfer/KCL transaction never publishes a right
                % sample and never rolls back the already committed Phase 1.
                reselection_status=reselection_failure_status(reason);
                log.applied=false;
                log.failure_id='ts_simulate_ibr_hybrid:reselectionTransaction';
                log.details=reason;
                pending_reselection=false;
            end
            event_log(end+1,1)=log; %#ok<AGROW>
            log_status=stability.ibr_status_snapshot('sg_reselection',t,dae,ec,active, ...
                kcl_norm(dae,t,x,y,Ycurr,u,ec));
            event_log(end).status=log_status;
            status_log(end+1,1)=log_status; %#ok<AGROW>
            append_progress_event(settings,t,'sg_reselection',log.applied,log.details);
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
% Phase-1 read-only resynchronization diagnostics (Mission C): per-sample
% synchronism state during the offline coast. struct([]) (0×0) when pending_reclose
% was never entered; otherwise a struct array with the fields defined by rec.
if isempty(fieldnames(resync_diag))
    res.resync_diagnostics = struct([]);
else
    res.resync_diagnostics = resync_diag;
end
res.iter_per_step=step_iterations;
res.residual_per_step=step_residuals;
res.accepted_residual_per_step=accepted_step_residuals;
res.step_attempts=step_attempts;
res.accepted_steps=accepted_steps;
res.internal_substeps=internal_substeps;
res.domain_rejected_trials=domain_rejected_total;
res.subdivision_depth=subdivision_depth;
% Stepper provenance + adaptive diagnostics (fixed path publishes only the
% label so its trajectory arrays stay byte-identical).
res.stepper=char(settings.stepper);
if settings.stepper=="adaptive"
    res.dt_history=dt_history;
    res.lte_history=lte_history;
    res.rejected_steps=rejected_steps;
    res.floor_accepted_steps=floor_accepted_steps;
    res.rejection_history=rejection_history;
end
% Phase-2 reselection + reference-ownership fields (F1/C1/F5).
res.actual_mode_reselection_time=actual_mode_reselection;
res.reselection_status=reselection_status;
res.support_supervision_status=support_status;
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
res.sg_sync_controller=sync_ctl;
res.handback_status=sync_ctl.handback_status;
res.handback_start_time=sync_ctl.handback_t0;
res.handback_duration_s=sync_ctl.handback_T;
res.handback_complete_time=sync_ctl.handback_complete_time;
res.controller_audit=controller_audit;

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
% --- Reference-AGSI in-band overlay (opt-in, DIAGNOSTIC ONLY) --------------
% Strictly post-processing: it reads the completed sample record and cannot
% affect a single accepted step, the severity scalar, the hysteresis/dwell
% logic, or any acceptance gate. Failure to build it is never a run failure.
if settings.agsi_reference_enabled
    try
        res.agsi_reference=stability.agsi_reference_terms(res,dae,settings,Ylog);
    catch me
        res.agsi_reference=struct('status','OVERLAY_FAILED', ...
            'failure_id',me.identifier,'failure_reason',me.message, ...
            'classification','ASSUMED_DIAGNOSTIC');
    end
end
meta.method='trapezoidal_coupled_newton_shared';
meta.full_kcl=true;
meta.event_aware=true;
meta.iterations=total_iterations;
meta.max_step_residual=max_residual;
meta.sample_count=numel(res.t);
meta.event_count=numel(event_log);
meta.internal_substeps=internal_substeps;
meta.failure_id=failure_id;
meta.failure_reason=failure_reason;
meta.domain_rejected_trials=domain_rejected_total;
meta.subdivision_depth=subdivision_depth;
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
    'max_step_subdivisions',option(opt,'max_step_subdivisions',4), ...
    'sync_dwell',case_data.synchronism.dwell_s, ...
    'sync_timeout',case_data.synchronism.timeout_s, ...
    'min_off',case_data.delays.T_sg_min_off_s,'sync_overrides',struct(), ...
    'T_minimum_hold',case_data.delays.T_minimum_hold_s, ...
    'T_guard',case_data.delays.T_guard_s, ...
    'T_lockout',case_data.delays.T_lockout_s, ...
    'rho',case_data.delays.rho);
s.progress_every = option(opt,'progress_every',0);
s.progress_file  = char(option(opt,'progress_file',''));
s.progress_last  = -Inf;
s.state_predictor = char(option(opt,'state_predictor','hold'));
% Falsified alternative (2026-08-11, do not reintroduce without new
% evidence): using an extrapolating predictor for ORDINARY steps instead of
% 'hold'. At one recorded stiff state it looked decisive -- 'hold' spends 21
% coupled Newton iterations, 17 of them line-search backtracks, while
% 'explicit_euler_kcl' converges in 4 with alpha==1 throughout and moves the
% accepted point by only 3.3e-12 (scripts/diagnostics/probe_fd_step_sensitivity.m).
% Over a whole switching arm it is worse and NOT equivalent: 4083 vs 2725
% Newton iterations, subdivision depth 7 vs 5, max|dx|=280.7. A changed
% iteration count flips whether individual steps exhaust max_iter, which
% changes the accepted dyadic structure and therefore the discretization.
% FD Jacobian construction, forwarded to stability.ts_step_composite. The
% kernel defaults are 'auto' grouping (same dense Jacobian as the historical
% per-column build) and no structure check; a verification run can force
% 'off' to rebuild per column, or true to build both and require exact
% equality.
s.fd_grouping = char(option(opt,'fd_grouping','auto'));
s.fd_structure_check = logical(option(opt,'fd_structure_check',false));
s.healthy_pf_V = option(opt,'healthy_pf_V',[]);
s.healthy_pf_bus_ids = option(opt,'healthy_pf_bus_ids',[]);
has_healthy_v = isfield(opt,'healthy_pf_V') && ~isempty(opt.healthy_pf_V);
has_healthy_bus = isfield(opt,'healthy_pf_bus_ids') && ~isempty(opt.healthy_pf_bus_ids);
if xor(has_healthy_v,has_healthy_bus)
    error('ts_simulate_ibr_hybrid:incompleteHealthyPfReference', ...
        'healthy_pf_V and healthy_pf_bus_ids must be supplied together.');
end
s.severity_handback_enabled = has_healthy_v && has_healthy_bus;
s.severity_support_enabled = logical(option(opt,'automatic_support_supervision',false)) && ...
    logical(option(opt,'automatic_gfm_switching',true)) && ...
    has_healthy_v && has_healthy_bus;
s.severity_gamma_on = option(opt,'severity_gamma_on',0.65);
s.severity_gamma_off = option(opt,'severity_gamma_off',0.35);
s.severity_T_d_on = option(opt,'severity_T_d_on',0.10);
s.severity_T_d_off = option(opt,'severity_T_d_off',1.00);
s.severity_dV_base = 0.10;
s.severity_df_base_Hz = 0.50;
s.severity_f0_Hz = case_data.base_values.frequency_Hz;
% --- Reference-AGSI in-band overlay (opt-in, DIAGNOSTIC ONLY) --------------
% The switching supervisor consumes J_V and J_f ONLY; that contract is
% unchanged. When this flag is set the driver additionally publishes the
% remaining standard AGSI sub-indices as a POST-PROCESSED reference so the run
% can be checked against the published bands, and never feeds them into the
% severity scalar, the hysteresis, the dwell timers, or any gate. It is
% computed after the trajectory is complete, from the recorded samples, so it
% cannot influence a single accepted step. Default false, so an omitted option
% leaves the result schema and the runtime byte-identical.
s.agsi_reference_enabled = logical(option(opt,'agsi_reference',false));
% Normalization bases. ASSUMED_DIAGNOSTIC: the reference AGSI formulation the
% owner supplied fixes the J_V/J_f bases (0.10 pu, 0.50 Hz -- already used by
% the production trigger above) and gives 1.0 Hz/s and 0.20 pu for the ROCOF and
% power-tracking terms; the PLL-lock base is the project's own 0.10 pu q-axis
% residual. These are diagnostic band references, never acceptance gates, and
% every one of them is overridable by the caller.
s.agsi_rocof_base_Hz_s = option(opt,'agsi_rocof_base_Hz_s',1.0);
s.agsi_dP_base_pu = option(opt,'agsi_dP_base_pu',0.20);
s.agsi_scr_floor = option(opt,'agsi_scr_floor',3.0);
s.agsi_vq_base_pu = option(opt,'agsi_vq_base_pu',0.10);
if s.agsi_reference_enabled
    b=[s.agsi_rocof_base_Hz_s s.agsi_dP_base_pu s.agsi_scr_floor s.agsi_vq_base_pu];
    if any(~isfinite(b)) || any(b<=0)
        error('ts_simulate_ibr_hybrid:invalidAgsiReferenceBases', ...
            'Reference-AGSI normalization bases must be finite and positive.');
    end
end
if s.severity_handback_enabled
    hV=s.healthy_pf_V(:).'; hB=s.healthy_pf_bus_ids(:).';
    if numel(hV)~=numel(hB) || isempty(hV) || ...
            any(~isfinite(hV)) || any(hV<=0) || ...
            any(~isfinite(hB)) || numel(unique(hB))~=numel(hB)
        error('ts_simulate_ibr_hybrid:invalidHealthyPfReference', ...
            ['healthy_pf_V and healthy_pf_bus_ids must be equal-length finite ' ...
             'vectors with positive voltages and unique bus IDs.']);
    end
    s.healthy_pf_V=hV; s.healthy_pf_bus_ids=hB;
end
sev_contract=[s.severity_gamma_on,s.severity_gamma_off, ...
    s.severity_T_d_on,s.severity_T_d_off];
if any(~isfinite(sev_contract)) || s.severity_gamma_off<0 || ...
        s.severity_gamma_on<=s.severity_gamma_off || ...
        s.severity_T_d_on<0 || s.severity_T_d_off<0
    error('ts_simulate_ibr_hybrid:invalidSeverityContract', ...
        ['Severity thresholds/dwells must be finite, Gamma_on>Gamma_off>=0, ' ...
         'and T_d_on/T_d_off nonnegative.']);
end
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
if ~isscalar(s.max_step_subdivisions) || ~isfinite(s.max_step_subdivisions) || ...
        s.max_step_subdivisions<0 || s.max_step_subdivisions~=fix(s.max_step_subdivisions) || ...
        s.max_step_subdivisions>12
    error('ts_simulate_ibr_hybrid:badOptions', ...
        'max_step_subdivisions must be an integer in [0,12].');
end
% --- Adaptive-step options (opt-in). All NUMERICAL_METHOD ------------------
% Default 'fixed' leaves the fixed path byte-identical: none of these fields
% is read on the fixed branch. Mirrors the step-doubling trapezoidal +
% Richardson LTE algorithm of stability.ts_adaptive_driver (a separate
% implementation driving ts_step_composite; ts_adaptive_driver itself is
% never edited), including controller_fac/fac_min/fac_max = 0.9/0.2/5.0 and
% the weight norm sc = atol + rtol*max(|x_n|,|x_cand|).
s.stepper = lower(string(option(opt,'stepper','fixed')));
if ~isscalar(s.stepper) || ~ismember(s.stepper,["fixed","adaptive"])
    error('ts_simulate_ibr_hybrid:badStepper', ...
        'stepper must be fixed or adaptive.');
end
if s.stepper=="adaptive"
    % Tolerances mirror ts_adaptive_driver's defaults. Classification
    % PROPOSED: tolerance selection for the SG adaptive track is documented
    % as NOT_READY (TRACK_A_ADAPTIVE_TS); these values are declared in the
    % plan and the tests before any metric is viewed, and are overridden
    % per-caller, never retuned after seeing results.
    s.atol_x = option(opt,'atol_x',1e-6);
    s.rtol_x = option(opt,'rtol_x',1e-4);
    s.atol_y = option(opt,'atol_y',1e-5);
    s.rtol_y = option(opt,'rtol_y',1e-4);
    % dt_min is tied to the subdivision floor the fixed path already has:
    % with max_step_subdivisions the fixed kernel resolves stiffness down to
    % dt/2^max_step_subdivisions, so the adaptive path keeps the same reach
    % with headroom rather than a coarser floor.
    s.dt_min = option(opt,'dt_min',s.dt/(2^(s.max_step_subdivisions+1)));
    s.dt_max = option(opt,'dt_max',s.dt*10);
    % Armed-window ceiling: keeps event-crossing detection (good_since,
    % support timers, severity releases) on a cadence comparable to the
    % fixed grid while supervisor decisions are pending. This is a
    % decision-parity safeguard, NOT a reclose fix (dt=0.01 also times out
    % under this config; see PERF-2026-08-11-01).
    s.dt_max_armed = option(opt,'dt_max_armed',s.sync_dwell/10);
    s.controller_fac = option(opt,'controller_fac',0.9);
    s.controller_fac_min = option(opt,'controller_fac_min',0.2);
    s.controller_fac_max = option(opt,'controller_fac_max',5.0);
    s.reject_limit = option(opt,'reject_limit',10);
    s.rannacher_n = option(opt,'rannacher_n',2);
    s.rannacher_window_dt = option(opt,'rannacher_window_dt',s.dt_max_armed);
    advals=[s.atol_x,s.rtol_x,s.atol_y,s.rtol_y,s.dt_min,s.dt_max, ...
        s.dt_max_armed,s.controller_fac,s.controller_fac_min, ...
        s.controller_fac_max,s.reject_limit,s.rannacher_n, ...
        s.rannacher_window_dt];
    if any(~isfinite(advals)) || any(advals(1:12)<=0)
        error('ts_simulate_ibr_hybrid:badAdaptiveOptions', ...
            'All adaptive controller parameters must be finite and positive.');
    end
    if s.dt_min>=s.dt_max || s.dt_max_armed<s.dt_min || ...
            s.dt_max_armed>s.dt_max || s.rannacher_window_dt<s.dt_min
        error('ts_simulate_ibr_hybrid:badAdaptiveOptions', ...
            ['Adaptive dt bounds must satisfy dt_min < dt_max and ' ...
             'dt_min <= dt_max_armed <= dt_max, dt_min <= rannacher_window_dt.']);
    end
    if s.reject_limit<1 || s.reject_limit~=fix(s.reject_limit) || ...
            s.rannacher_n<0 || s.rannacher_n~=fix(s.rannacher_n)
        error('ts_simulate_ibr_hybrid:badAdaptiveOptions', ...
            'reject_limit and rannacher_n must be positive/nonnegative integers.');
    end
end
end

function [step,stats] = advance_with_subdivision(x0,y0,t0,h,dae,Ynet,u,ec,active,step_opt,s,depth)
%ADVANCE_WITH_SUBDIVISION Retry a failed logical output step with two
% coupled-trapezoidal half steps. The public/output grid remains s.dt; only
% the internal numerical landing points are refined. This is a
% NUMERICAL_METHOD safeguard for millisecond converter loops, not a change
% to device equations, event times, or the published sample contract.
%
% Subdivision operates strictly within the caller-supplied interval
% [t0,t0+h]; the main loop bounds h by the next scheduled event before
% calling here, so internal half-step landings cannot cross an event
% boundary and are never published as samples.
step_opt.t_now=t0;
trial=stability.ts_step_composite(x0,y0,h,dae,Ynet,u,ec,active,step_opt);
stats=struct('attempts',1, ...
    'accepted_leaf_steps',double(trial.converged&&trial.finite), ...
    'accepted_residual_norm',NaN, ...
    'domain_rejected_trials',step_domain_rejects(trial), ...
    'subdivision_depth',depth, ...
    'terminal_domain_failure',step_terminal_failure(trial));
if trial.converged && trial.finite
    stats.accepted_residual_norm=trial.residual_norm;
    step=trial;
    return;
end

if depth>=s.max_step_subdivisions
    step=trial;
    return;
end

h2=h/2;
[left_opt,right_opt]=subdivision_predictor_options(step_opt,x0);
[left,left_stats]=advance_with_subdivision( ...
    x0,y0,t0,h2,dae,Ynet,u,ec,active,left_opt,s,depth+1);
stats.attempts=stats.attempts+left_stats.attempts;
stats.accepted_leaf_steps=left_stats.accepted_leaf_steps;
stats.domain_rejected_trials=stats.domain_rejected_trials+left_stats.domain_rejected_trials;
stats.subdivision_depth=max(stats.subdivision_depth,left_stats.subdivision_depth);
stats.terminal_domain_failure=pick_terminal_failure(stats.terminal_domain_failure, ...
    left_stats.terminal_domain_failure,left,trial);
if ~left.converged || ~left.finite
    step=left;
    step.iterations=trial.iterations+left.iterations;
    step.residual_norm=max(trial.residual_norm,left.residual_norm);
    return;
end
[right,right_stats]=advance_with_subdivision( ...
    left.x_full,left.y_full,t0+h2,h2,dae,Ynet,u,ec,active,right_opt,s,depth+1);
stats.attempts=stats.attempts+right_stats.attempts;
stats.accepted_leaf_steps=left_stats.accepted_leaf_steps+right_stats.accepted_leaf_steps;
if right.converged && right.finite
    stats.accepted_residual_norm=max( ...
        left_stats.accepted_residual_norm,right_stats.accepted_residual_norm);
end
stats.domain_rejected_trials=stats.domain_rejected_trials+right_stats.domain_rejected_trials;
stats.subdivision_depth=max(stats.subdivision_depth,right_stats.subdivision_depth);
% The terminal failed leaf governs the failure report. A successful left
% child that triggered subdivision retains its rejected-trial count in the
% aggregate, but the right child's terminal evidence (when it fails) takes
% precedence over the parent's.
stats.terminal_domain_failure=pick_terminal_failure(stats.terminal_domain_failure, ...
    right_stats.terminal_domain_failure,right,trial);
step=right;
step.iterations=trial.iterations+left.iterations+right.iterations;
step.residual_norm=max([trial.residual_norm,left.residual_norm,right.residual_norm]);
end

function [step,stats]=advance_with_subdivision_hint( ...
    x0,y0,t0,h,dae,Ynet,u,ec,active,step_opt,s,hint)
% Use the previous accepted logical step only as a work hint. Forced leaves
% still solve the identical implicit residual and can subdivide further.
% No previous numerical state or correction is reused.
hint=max(0,min(s.max_step_subdivisions,fix(hint)));
[step,stats]=advance_forced_subdivision( ...
    x0,y0,t0,h,dae,Ynet,u,ec,active,step_opt,s,0,hint);
end

function [step,stats]=advance_forced_subdivision( ...
    x0,y0,t0,h,dae,Ynet,u,ec,active,step_opt,s,depth,remaining)
if remaining<=0
    [step,stats]=advance_with_subdivision( ...
        x0,y0,t0,h,dae,Ynet,u,ec,active,step_opt,s,depth);
    return;
end
h2=h/2;
[left_opt,right_opt]=subdivision_predictor_options(step_opt,x0);
[left,ls]=advance_forced_subdivision( ...
    x0,y0,t0,h2,dae,Ynet,u,ec,active,left_opt,s,depth+1,remaining-1);
stats=ls;
if ~left.converged || ~left.finite
    step=left;
    return;
end
[right,rs]=advance_forced_subdivision( ...
    left.x_full,left.y_full,t0+h2,h2,dae,Ynet,u,ec,active,right_opt, ...
    s,depth+1,remaining-1);
stats.attempts=ls.attempts+rs.attempts;
stats.accepted_leaf_steps=ls.accepted_leaf_steps+rs.accepted_leaf_steps;
stats.domain_rejected_trials=ls.domain_rejected_trials+rs.domain_rejected_trials;
stats.subdivision_depth=max(ls.subdivision_depth,rs.subdivision_depth);
stats.terminal_domain_failure=pick_terminal_failure( ...
    ls.terminal_domain_failure,rs.terminal_domain_failure,right,left);
if right.converged && right.finite
    stats.accepted_residual_norm=max( ...
        ls.accepted_residual_norm,rs.accepted_residual_norm);
end
step=right;
step.iterations=left.iterations+right.iterations;
step.residual_norm=max(left.residual_norm,right.residual_norm);
end

function hint=next_subdivision_hint(previous,stats,max_depth)
% If every forced/adaptive leaf passed on its first solve, cautiously coarsen
% one dyadic level. Otherwise start the next step near the accepted leaf
% count, avoiding repeated failed coarse ancestors.
%
% Falsified alternative (2026-08-11, do not reintroduce without new
% evidence): requiring K consecutive clean steps before coarsening was
% expected to remove the doomed full-length parent trial that a hint
% oscillation pays on every other step, with the accepted leaves unchanged.
% Measured on the compressed switching arm it is both slower and NOT
% equivalent: 3829 vs 2725 Newton iterations and max|dx|=126. Reason:
% retaining a hint of 2 or more does not merely skip a doomed trial, it
% forces a FINER dyadic structure than the coarsening path would have
% accepted, so the published trajectory is a different discretization.
if stats.accepted_leaf_steps<=0 || ~isfinite(stats.accepted_leaf_steps)
    hint=0;
elseif stats.attempts==stats.accepted_leaf_steps
    hint=max(previous-1,0);
else
    hint=ceil(log2(max(1,stats.accepted_leaf_steps)));
end
hint=max(0,min(max_depth,hint));
end

function [left_opt,right_opt]=subdivision_predictor_options(step_opt,x0)
% A linear predictor supplied to this routine targets the END of the
% caller's interval.  Reusing that endpoint for the left half over-predicts
% by a factor of two at every recursion level and can dominate the work in a
% stiff post-event transient.  Interpolate only the left-child endpoint;
% the right child retains the original parent endpoint.  This changes the
% Newton initial guess only, never the BE/trapezoidal residual or gate.
left_opt=step_opt;
right_opt=step_opt;
if isfield(step_opt,'x_predictor') && isnumeric(step_opt.x_predictor) && ...
        numel(step_opt.x_predictor)==numel(x0) && ...
        all(isfinite(step_opt.x_predictor(:)))
    xp=step_opt.x_predictor(:);
    left_opt.x_predictor=x0+0.5*(xp-x0);
end
end

% =========================================================================
function n = step_domain_rejects(step)
n = 0;
if isstruct(step) && isfield(step,'domain_rejected_trials') && ...
        isscalar(step.domain_rejected_trials) && ...
        isfinite(step.domain_rejected_trials)
    n = step.domain_rejected_trials;
end
end

function f = step_terminal_failure(step)
f = struct([]);
if isstruct(step) && isfield(step,'newton_info') && isstruct(step.newton_info) && ...
        isfield(step.newton_info,'line_search_exhausted') && ...
        step.newton_info.line_search_exhausted
    f = step.newton_info;
end
end

function f = pick_terminal_failure(current, candidate, ~, parent_step)
%PICK_TERMINAL_FAILURE  Preserve the terminal failed-leaf evidence.
%   A child that actually exhausted its line search (non-empty scalar struct
%   with line_search_exhausted=true) overrides the parent's evidence because
%   the child is the actual terminal attempt. An empty struct([]) candidate
%   (child succeeded) must NOT override a non-empty parent evidence.
has_evidence = @(x) isstruct(x) && isscalar(x) && ~isempty(fieldnames(x)) && ...
    isfield(x,'line_search_exhausted') && x.line_search_exhausted;
if has_evidence(candidate)
    f = candidate;
    return;
end
if has_evidence(current)
    f = current;
    return;
end
% Fall back to the parent step's newton_info if it exhausted and no child
% has reported yet (e.g., depth limit reached at the parent).
f = step_terminal_failure(parent_step);
end

function reason = format_step_failure(target, h, step, retry_stats)
%FORMAT_STEP_FAILURE  Compose the public failure_reason with terminal-leaf
%   domain evidence when present, otherwise the ordinary Newton message.
base = sprintf('Composite step failed at t=%.15g (residual %.3e).', ...
    target, step.residual_norm);
info = retry_stats.terminal_domain_failure;
if isempty(fieldnames(info)) || ~isfield(info,'line_search_exhausted') || ...
        ~info.line_search_exhausted || ...
        ~isfield(info,'domain_rejected_trials') || ...
        info.domain_rejected_trials <= 0
    reason = base;
    return;
end
parts = {base};
if isfield(info,'residual_before_line_search') && isscalar(info.residual_before_line_search) && ...
        isfinite(info.residual_before_line_search)
    parts{end+1} = sprintf('residual_before=%.3e', info.residual_before_line_search); %#ok<AGROW>
end
if isfield(info,'final_tested_alpha') && isscalar(info.final_tested_alpha) && ...
        isfinite(info.final_tested_alpha)
    parts{end+1} = sprintf('final_tested_alpha=%.3e', info.final_tested_alpha); %#ok<AGROW>
end
if isfield(info,'minimum_trial_voltage') && isscalar(info.minimum_trial_voltage) && ...
        isfinite(info.minimum_trial_voltage)
    parts{end+1} = sprintf('minimum_trial_voltage=%.4g', info.minimum_trial_voltage); %#ok<AGROW>
end
parts{end+1} = sprintf('h=%.3e domain_rejected_trials=%d', h, info.domain_rejected_trials); %#ok<AGROW>
% Violating devices: list every attributed device, never just the first.
viol_str = '';
if isfield(info,'final_domain_violation') && isstruct(info.final_domain_violation) && ...
        isfield(info.final_domain_violation,'violating_devices')
    vd = info.final_domain_violation.violating_devices;
    for k = 1:numel(vd)
        if isfield(vd(k),'device_id') && isfield(vd(k),'bus_id') && ...
                isfield(vd(k),'trial_voltage')
            viol_str = [viol_str, sprintf(' %s@bus%d(%.4g)', ...
                char(vd(k).device_id), vd(k).bus_id, vd(k).trial_voltage)]; %#ok<AGROW>
        end
    end
end
if ~isempty(viol_str)
    parts{end+1} = sprintf('violating_devices:%s', viol_str); %#ok<AGROW>
end
reason = strjoin(parts, ' ');
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

function [ok,xr,yr,ur,ecr,active,handler_log,reason,right_norm,stage,dispatch,controller_audit] = ...
    trip_transaction(t,x,y,Y,u,ec,dae,sched,case_data,kcl_tol,automatic_gfm_switching,opt)
%TRIP_TRANSACTION  SG breaker trip + optional GFM commitment (C3/F2).
%   When automatic_gfm_switching=true: open the SG breaker, then commit the
%   SG_OFF GFM configuration read from the AUTHENTICATED precomputed selector
%   table (opt.selector_table.sg_off.selected_config) — NOT from schedule
%   literals. Verifies table presence + ready_to_commit before any candidate
%   state is published (mirrors reselection_transaction). Apply transfer
%   maps, solve one right limit.
%   When automatic_gfm_switching=false: open the SG breaker normally, do NOT
%   invoke the GFM selector, do NOT change IBR modes; run an explicit per-
%   island voltage-forming-source check BEFORE Newton; if no online voltage-
%   forming resource exists, fail closed with noVoltageFormingSource, publish
%   NO right-limit sample, commit NO candidate hybrid state, and end the
%   accepted trajectory at the event-left sample (F2).
if nargin < 11, automatic_gfm_switching = true; end
if nargin < 12, opt = struct(); end
ok=false; xr=x; yr=y; ur=u; ecr=ec; active=[]; reason='';
right_norm=inf; stage='tripTransaction'; dispatch=struct();
controller_audit=struct();
if automatic_gfm_switching
    % --- sg_breaker_trip + optional_gfm_commit (full automatic path) ---
    % Authenticate the SG_OFF candidate from the precomputed selector table.
    % The committed_selection is built from the TABLE, never from sched.*
    % (closes the fixed-IEEE14-index defect). Fail closed before any
    % candidate publication. Branches on selection_request.mode:
    %   automatic       -> table.sg_off.selected_config (ranked winner)
    %   manual_override -> EXACT unique match against table.sg_off.configurations
    % Missing table / no match / not ready -> structured failure_id, no right
    % sample, no candidate publication (advisor #3, #6).
    req = struct('mode','automatic');
    if isfield(sched,'selection_request') && isstruct(sched.selection_request) && ...
            isfield(sched.selection_request,'mode')
        req = sched.selection_request;
    end
    if ~isfield(opt,'selector_table') || ~isstruct(opt.selector_table)
        handler_log = auth_fail_log('stability:gfm_selection:missingTable', ...
            'automatic SG_OFF requires opt.selector_table (no table injected).');
        reason = handler_log.details; return;
    end
    controller_mode='legacy';
    if isfield(opt,'controller_mode') && ~isempty(opt.controller_mode)
        controller_mode=lower(char(opt.controller_mode));
    end
    if ~strcmp(controller_mode,'legacy')
        if ~isfield(opt,'resources') || ~isstruct(opt.resources)
            handler_log=auth_fail_log( ...
                'stability:et_fcs_production_trip_decision:missingResources', ...
                'Predictive trip decision requires the authenticated resource table.');
            reason=handler_log.details; return;
        end
        ctrl_opt=struct('dt',option(opt,'dt',0.0125));
        if isfield(opt,'controller_trial_evidence') && ...
                ~isempty(opt.controller_trial_evidence)
            ctrl_opt.trial_evidence=opt.controller_trial_evidence;
        end
        try
            [ctrl_selection,controller_audit]= ...
                stability.et_fcs_production_trip_decision(t,x,y,Y,u,ec,dae, ...
                sched,case_data,opt.resources,opt.selector_table,controller_mode,ctrl_opt);
        catch me
            handler_log=auth_fail_log(me.identifier,me.message);
            reason=handler_log.details; return;
        end
        req=struct('mode','manual_override','manual_candidate',ctrl_selection);
    end
    % Assemble the identity-aligned runtime context (Step F): event-left modes,
    % online/hold/lockout materialized in dae.devices order + eligible mask.
    runtime_context = assemble_runtime_context(ec.hybrid_state, dae);
    runtime_context.event_time = t;
    % Authenticate against LIVE Y (topology drift detection, Step 8). Pass the
    % runtime topology derived from case_data.mpc so the input fingerprint
    % matches the build-time hash when the network has not drifted.
    Ytopo = [];
    if isfield(case_data,'mpc') && isstruct(case_data.mpc)
        Ytopo = canonical_ybus_from_mpc(case_data.mpc);
    end
    [auth_ok, auth_fid, auth_msg, ~, cand] = ...
        stability.validate_runtime_candidate_compatibility( ...
        opt.selector_table, req, dae, sched, 'sg_off', Ytopo, runtime_context);
    if ~auth_ok
        % Preserve the structured ID from the validator VERBATIM (advisor #6,
        % Revision 4): do NOT prepend any namespace.
        handler_log = auth_fail_log(auth_fid, auth_msg);
        reason = auth_msg; return;
    end
    % Canonical owner arrays + actual energized-island ID (Step F + Step 10):
    % compute the live island ID from the actual topology (NOT literal 1).
    actual_island_id = [];
    if ~isempty(Ytopo) && isfield(case_data,'mpc') && isstruct(case_data.mpc)
        islands = stability.island_components(Ytopo, case_data.mpc);
        energized = islands([islands.energized]);
        if ~isempty(energized)
            actual_island_id = energized(1).island_id;
        end
    end
    % Read the committed selection from the validator output; fall back to the
    % schedule literals only if a field is missing (defensive — the validator
    % output carries the authoritative authenticated tuple in scope).
    cand_sel = [];
    cand_n = [];
    cand_ref = [];
    if isfield(cand,'selected_gfm_indices'), cand_sel = cand.selected_gfm_indices; end
    if isfield(cand,'n_gfm_required'), cand_n = cand.n_gfm_required; end
    if isfield(cand,'reference_resource_index'), cand_ref = cand.reference_resource_index; end
    if isempty(cand_sel) && isfield(sched,'selection_request') && isstruct(sched.selection_request) && ...
            isfield(sched.selection_request,'manual_candidate') && ~isempty(sched.selection_request.manual_candidate)
        mc = sched.selection_request.manual_candidate;
        if isempty(cand_sel) && isfield(mc,'selected_gfm_indices'), cand_sel = mc.selected_gfm_indices; end
        if isempty(cand_n) && isfield(mc,'n_gfm_required'), cand_n = mc.n_gfm_required; end
        if isempty(cand_ref) && isfield(mc,'reference_resource_index'), cand_ref = mc.reference_resource_index; end
    end
    event=struct('type','sg_trip_request','t',t,'sg_ids',{{sched.sg_id}}, ...
        'committed_selection',struct('selected_gfm_indices',cand_sel, ...
        'n_gfm_required',cand_n, ...
        'reference_resource_index',cand_ref, ...
        'reference_owner_indices',cand_ref, ...
        'gfm_reference_resource_indices',cand_ref, ...
        'reference_island_ids',actual_island_id));
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
        if isfield(cand,'eq_u_eq') && ~isempty(cand.eq_u_eq)
            ur=apply_authenticated_candidate_inputs(ur,cand.eq_u_eq,dae);
            dispatch=dispatch_snapshot(ur,dae);
        end
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
            omega_grid=reference_grid_omega(dae,x,y,u,ec);
            diag.df_pu = abs(rec.omega-omega_grid);
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

function [cand, ok, err_id, err_msg] = authenticate_sg_on_candidate(table, dae, sched, ec, Y, t, case_data)
%AUTHENTICATE_SG_ON_CANDIDATE  Route the SG_ON selection through the validator.
%   Returns the authenticated SG_ON candidate (sole commit authority, Step 5)
%   or an empty struct with a failure ID. No raw table.sg_on aggregate is read
%   as commit authority. Builds the runtime context from the event-left
%   hybrid_state and the live Y (post-fault-clear topology).
cand = struct();
ok = false; err_id = ''; err_msg = '';
if ~isstruct(table) || ~isfield(table,'sg_on') || ~isstruct(table.sg_on)
    err_id = 'stability:gfm_selection:missingTable';
    err_msg = 'SG_ON reselection requires an authenticated selector_table.';
    return;
end
req = struct('mode','automatic');
if isfield(sched,'selection_request') && isstruct(sched.selection_request) && ...
        isfield(sched.selection_request,'mode')
    req = sched.selection_request;
    req.mode = 'automatic';   % SG_ON reselection is always automatic (table-ranked)
end
runtime_context = assemble_runtime_context(ec.hybrid_state, dae);
runtime_context.event_time = t;
Ytopo = Y;
if isempty(Ytopo) && isfield(case_data,'mpc') && isstruct(case_data.mpc)
    Ytopo = canonical_ybus_from_mpc(case_data.mpc);
end
[ok, err_id, err_msg, ~, cand] = stability.validate_runtime_candidate_compatibility( ...
    table, req, dae, sched, 'sg_on', Ytopo, runtime_context);
end

function [target_selected, audit, ok] = choose_sg_online_one_step( ...
    table, dae, sched, ec, Y, t, case_data, current_gfm, release_candidates)
%CHOOSE_SG_ONLINE_ONE_STEP  Authenticate exactly one staged GFM release.
%   The live AGSI scalar decides when a release may be considered.  This
%   helper is the independent physical authority: each target must be an
%   exact SG_ON table row, differ from the committed GFM set by one IBR, and
%   pass the validator's fingerprint, runtime, equilibrium/SSSA and resource
%   contracts.  No TS-step equilibrium or eigenvalue solve occurs here.
target_selected = [];
ok = false;
audit = struct('reason','NO_FEASIBLE_SG_ON', 'failure_id', ...
    'stability:gfm_selection:noAuthenticatedCandidate', ...
    'evaluated_candidates',0,'accepted_candidates',0, ...
    'selected_release_index',NaN,'candidate_margin',NaN, ...
    'candidate_fingerprint','');
if ~isstruct(table) || ~isfield(table,'sg_on') || ...
        ~isstruct(table.sg_on) || ~isfield(table.sg_on,'configurations')
    audit.reason = 'NO_AUTHENTICATED_SG_ON_TABLE';
    audit.failure_id = 'stability:gfm_selection:missingTable';
    return;
end
if isempty(current_gfm) || isempty(release_candidates)
    audit.reason = 'NO_RELEASE_CANDIDATE';
    audit.failure_id = 'stability:gfm_selection:noOneStepCandidate';
    return;
end
current_gfm = unique(current_gfm(:).','stable');
release_candidates = unique(release_candidates(:).','stable');
if any(~ismember(release_candidates,current_gfm))
    audit.reason = 'INVALID_RELEASE_SET';
    audit.failure_id = 'stability:gfm_selection:invalidOneStepSet';
    return;
end
% Runtime compatibility/fingerprint checks are repeated for each exact row;
% this prevents a previously authenticated winner from becoming a hidden
% authority after another device's mode has changed.
cfgs = table.sg_on.configurations;
accepted = repmat(struct(),0,1);
for q = 1:numel(release_candidates)
    k_release = release_candidates(q);
    target = setdiff(current_gfm,k_release,'stable');
    audit.evaluated_candidates = audit.evaluated_candidates + 1;
    match = [];
    for j = 1:numel(cfgs)
        c = cfgs(j);
        if ~isfield(c,'selected_gfm_indices') || ...
                ~isfield(c,'reference_resource_index')
            continue;
        end
        if isequal(sort(reshape(c.selected_gfm_indices,1,[])),sort(target)) && ...
                isscalar(c.reference_resource_index) && ...
                isfinite(c.reference_resource_index)
            match(end+1) = j; %#ok<AGROW>
        end
    end
    if numel(match) ~= 1
        continue;
    end
    c0 = cfgs(match);
    req = struct('mode','manual_override', ...
        'manual_candidate',struct( ...
        'selected_gfm_indices',target, ...
        'n_gfm_required',numel(target), ...
        'reference_resource_index',c0.reference_resource_index));
    runtime_context = assemble_runtime_context(ec.hybrid_state,dae);
    runtime_context.event_time = t;
    [valid,err_id,err_msg,~,c_auth] = ...
        stability.validate_runtime_candidate_compatibility( ...
        table,req,dae,sched,'sg_on',Y,runtime_context);
    if ~valid || ~isstruct(c_auth) || isempty(fieldnames(c_auth))
        continue;
    end
    % A manual match must retain the exact one-step relation.  The validator
    % authenticates the candidate but intentionally does not rank it.
    if ~isequal(sort(reshape(c_auth.selected_gfm_indices,1,[])),sort(target)) || ...
            numel(setdiff(current_gfm,c_auth.selected_gfm_indices)) ~= 1
        continue;
    end
    c_auth.release_index = k_release;
    c_auth.validation_failure_id = err_id;
    c_auth.validation_message = err_msg;
    accepted(end+1,1) = c_auth; %#ok<AGROW>
end
if isempty(accepted)
    audit.reason = 'NO_FEASIBLE_SG_ON_ONE_STEP';
    audit.failure_id = 'stability:gfm_selection:noOneStepCandidate';
    return;
end
% Frozen one-step ranking: robust margin first, then normalized headroom when
% supplied by the candidate evidence, then deterministic resource-ID tuple.
score = zeros(numel(accepted),4);
for j = 1:numel(accepted)
    margin = -Inf;
    if isfield(accepted(j),'margin') && isfinite(accepted(j).margin)
        margin = accepted(j).margin;
    end
    headroom = -Inf;
    if isfield(accepted(j),'minimum_normalized_headroom') && ...
            isfinite(accepted(j).minimum_normalized_headroom)
        headroom = accepted(j).minimum_normalized_headroom;
    end
    ids = '';
    if isfield(accepted(j),'resource_ids') && iscell(accepted(j).resource_ids)
        ids = strjoin(sort(accepted(j).resource_ids(accepted(j).selected_gfm_indices)),',');
    end
    score(j,:) = [-margin,-headroom,accepted(j).release_index,j];
    accepted(j).release_sort_key = ids;
end
% Use numeric score for the physics metrics and a stable lexical ID tie-break.
[~,ord] = sortrows(score,[1 2 3 4]);
if numel(ord)>1
    best_score = score(ord(1),1:3);
    tied = ord(all(score(ord,1:3)==best_score,2));
    if numel(tied)>1
        ids = cell(1,numel(tied));
        for j=1:numel(tied), ids{j}=accepted(tied(j)).release_sort_key; end
        [~,jj] = sort(ids); ord = [tied(jj),setdiff(ord,tied,'stable')];
    end
end
chosen = accepted(ord(1));
target_selected = reshape(chosen.selected_gfm_indices,1,[]);
audit.reason = 'AUTHENTICATED_ONE_STEP';
audit.failure_id = '';
audit.accepted_candidates = numel(accepted);
audit.selected_release_index = chosen.release_index;
if isfield(chosen,'margin'), audit.candidate_margin = chosen.margin; end
if isfield(chosen,'fingerprint'), audit.candidate_fingerprint = chosen.fingerprint; end
ok = true;
end

function [deadline, status] = compute_tdown(sg_on_cand, settings, actual_reclose)
%COMPUTE_TDOWN  Derive T_down from the AUTHENTICATED SG_ON candidate's Omega.
%   T_settle = ln(1/rho) / (-Omega_target); T_down = max(T_minimum_hold, T_settle).
%   Fail closed (status) if the candidate is missing or Omega is stale/unstable.
deadline = NaN;
status = 'PENDING';
if ~isstruct(sg_on_cand) || isempty(sg_on_cand)
    status = 'NO_FEASIBLE_SG_ON';
    return;
end
if ~isfield(sg_on_cand,'ready_to_commit') || ~sg_on_cand.ready_to_commit
    status = 'NO_FEASIBLE_SG_ON';
    return;
end
omega_target = sg_on_cand.omega;
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

function hl = auth_fail_log(failure_id, details)
%AUTH_FAIL_LOG  Uniform handler_log for an authentication failure that must
%   publish NO right sample and commit NO candidate. Preserves the
%   structured failure_id from the validator (advisor #6) instead of
%   collapsing to a generic sgOffSelectorNotReady.
hl = struct('applied', false, ...
    'failure_id', failure_id, ...
    'details', details, ...
    'candidate_committed', false, 'candidate_sg_online', false, ...
    'candidate_modes', struct(), 'failing_island_ids', [], ...
    'n_failing_islands', 0, 'selected_gfm_indices', [], ...
    'n_gfm_required', [], 'reference_resource_index', []);
end

function [T,status]=derive_handback_duration(table,dae,ec,settings,sync_ctl)
%DERIVE_HANDBACK_DURATION  Frozen C1 duration from the exact SG_ON spectrum.
%   The current GFM subset must have one authenticated SG_ON equilibrium/SSSA
%   row.  The duration is the maximum of the case minimum hold, the 95-percent
%   decay time of its least-damped physical mode, and the 95-percent response
%   time of the declared governor/exciter command lags.  No transient result
%   enters this calculation.
T=NaN; status='NO_AUTHENTICATED_SG_ON_HANDBACK';
if ~isstruct(table) || ~isfield(table,'sg_on') || ...
        ~isfield(table.sg_on,'configurations')
    return;
end
modes=current_mode_vector(dae,ec);
selected=find(strcmpi(modes,'gfm'));
cfgs=table.sg_on.configurations;
match=[];
for k=1:numel(cfgs)
    if isfield(cfgs(k),'selected_gfm_indices') && ...
            isequal(sort(reshape(cfgs(k).selected_gfm_indices,1,[])),sort(selected))
        match(end+1)=k; %#ok<AGROW>
    end
end
if numel(match)~=1, status='SG_ON_HANDBACK_CANDIDATE_MISMATCH'; return; end
c=cfgs(match);
if ~isfield(c,'ready_to_commit') || ~c.ready_to_commit || ...
        ~isfield(c,'omega') || ~isfinite(c.omega) || c.omega>=0
    status='SG_ON_HANDBACK_SSSA_UNSTABLE'; return;
end
rho=settings.rho;
if ~isfinite(rho) || rho<=0 || rho>=1
    status='SG_ON_HANDBACK_RHO_INVALID'; return;
end
t_mode=log(1/rho)/(-c.omega);
t_control=-log(rho)*max([sync_ctl.Tsv sync_ctl.Tch sync_ctl.TA]);
T=max([settings.T_minimum_hold,t_mode,t_control]);
status='C1_DURATION_AUTHENTICATED';
end

function [ok,x_right,y_right,u_right,ec_right,handler_log,reason,right_norm] = ...
    sg_off_support_transaction(t,x,y,Y,u,ec,dae,settings,candidate,direction)
%SG_OFF_SUPPORT_TRANSACTION  Atomic live GFM support augmentation/release.
%   Candidate identity and steady-state admissibility come only from the
%   project-built SG_OFF table.  The committed candidate's own certified
%   equilibrium input is installed with it, because the table certifies the PAIR
%   (configuration, eq_u_eq); transfer callbacks plus a live-Y full-KCL solve
%   are mandatory before mode/reference metadata is published.
ok=false; x_right=x; y_right=y; u_right=u; ec_right=ec;
handler_log=struct('details',''); reason=''; right_norm=inf;
if sg_online_state(dae,ec)
    reason='SG-off support transaction rejected because an SG is online.';
    return;
end
required={'selected_gfm_indices','reference_resource_index','ready_to_commit','feasible'};
for k=1:numel(required)
    if ~isfield(candidate,required{k})
        reason=sprintf('Authenticated support candidate lacks %s.',required{k});
        return;
    end
end
selected=unique(candidate.selected_gfm_indices(:).','stable');
ref=candidate.reference_resource_index;
if isempty(selected) || numel(selected)~=numel(candidate.selected_gfm_indices) || ...
        ~isequal(candidate.ready_to_commit,true) || ~isequal(candidate.feasible,true) || ...
        ~isscalar(ref) || ~isfinite(ref) || ~ismember(ref,selected)
    reason='Authenticated support candidate is not a ready nonempty referenced GFM set.';
    return;
end
current_modes=current_mode_vector(dae,ec);
current_gfm=find(strcmpi(current_modes,'gfm'));
if strcmp(direction,'augment')
    relation_ok=numel(selected)>numel(current_gfm) && all(ismember(current_gfm,selected));
elseif strcmp(direction,'release')
    relation_ok=numel(selected)<numel(current_gfm) && all(ismember(selected,current_gfm));
else
    relation_ok=false;
end
if ~relation_ok
    reason=sprintf('Support %s candidate violates the required strict set relation.',direction);
    return;
end
% Honour the certificate as a PAIR.  ibr_candidate_evaluate certifies
% feasibility/SSSA for (configuration, eq_u_eq) and stores that input on every
% candidate row (ibr_candidate_evaluate:325, persisted by
% ibr_config_selector:393).  trip_transaction already installs it.  This
% transaction previously kept u_right=u for a bumpless transfer, which committed
% the new configuration while leaving the PREVIOUS configuration's operating
% point in force -- on the IEEE14 arm up to 0.355 pu per unit away from the
% committed set's own certificate, with only the algebraic right-limit KCL as an
% acceptance test.  Install the committed candidate's certified input instead,
% and fail closed when a candidate carries none, so a configuration is never
% committed against an input for which nothing was certified
% (RECLOSE-2026-08-13-01).  apply_authenticated_candidate_inputs writes only the
% P_ref/Q_ref entries of the project-owned dual devices, so the offline SG
% synchronizer actuator and every E_ref remain untouched.
if ~isfield(candidate,'eq_u_eq') || isempty(candidate.eq_u_eq)
    reason=sprintf( ...
        'Support %s candidate carries no certified equilibrium input; refusing to commit an uncertified operating point.', ...
        direction);
    return;
end
try
    u_right=apply_authenticated_candidate_inputs(u,candidate.eq_u_eq,dae);
catch me
    reason=sprintf('Certified support input rejected: %s: %s',me.identifier,me.message);
    return;
end
% Preserve every non-IBR mode verbatim. In particular, an offline SG must
% remain breaker_open; the generic SG_ON target builder intentionally maps
% SGs to synchronous and therefore is not valid in this transaction.
target_modes=current_modes;
for k=1:numel(dae.devices)
    dev=dae.devices(k);
    is_ibr=isfield(dev,'capabilities') && ...
        isfield(dev.capabilities,'resource_type') && ...
        strcmpi(char(dev.capabilities.resource_type),'ibr');
    if ~is_ibr, continue; end
    if ismember(k,selected), target_modes{k}='gfm'; else, target_modes{k}='gfl'; end
end
changing=find_mode_changes(current_modes,target_modes);
if isempty(changing)
    reason='Support transaction contains no physical mode change.';
    return;
end
for k=1:numel(dae.devices)
    dev=dae.devices(k);
    is_ibr=isfield(dev,'capabilities') && ...
        isfield(dev.capabilities,'resource_type') && ...
        strcmpi(char(dev.capabilities.resource_type),'ibr');
    if ~is_ibr && ~strcmp(current_modes{k},target_modes{k})
        reason='SG-off support transaction attempted to mutate a non-IBR mode.';
        return;
    end
end
ec_right=ec;
ec_right.hybrid_state=stability.ts_hybrid_state_snapshot(ec.hybrid_state);
for k=1:numel(changing)
    idx=changing(k); dev=dae.devices(idx);
    key=matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
    ec_right.hybrid_state.device_modes.(key)=target_modes{idx};
end
try
    x_right=apply_device_transfers(x,y,u,ec,ec_right,dae);
catch me
    reason=sprintf('transfer map failed: %s: %s',me.identifier,me.message);
    return;
end
hs=ec_right.hybrid_state;
if ~isfield(hs,'reference_island_ids') || numel(hs.reference_island_ids)~=1
    reason='SG-off support transaction requires one authenticated live island ID.';
    return;
end
hs.selected_gfm_indices=selected;
hs.n_gfm_required=numel(selected);
hs.reference_resource_index=ref;
hs.reference_owner_indices=ref;
hs.gfm_reference_resource_indices=ref;
version=0;
if isfield(hs,'selector_table_version') && isnumeric(hs.selector_table_version) && ...
        isscalar(hs.selector_table_version) && isfinite(hs.selector_table_version)
    version=hs.selector_table_version;
end
version=version+1;
hs.selector_table_version=version;
hs.committed_config_fingerprint=sprintf( ...
    'sg_off_agsi_%s|selected=%s|ref=%d|version=%d', ...
    direction,mat2str(selected),ref,version);
ec_right.hybrid_state=hs;
[ok,y_right,reason,right_norm]=right_limit( ...
    x_right,y,Y,dae,u_right,ec_right,t,settings.kcl_tol);
if ok
    handler_log.details=sprintf( ...
        ['SG-off AGSI %s committed at t=%.3f; selected=%s, reference=%d, ' ...
         '%d device(s) transitioned.'], ...
        direction,t,mat2str(selected),ref,numel(changing));
end
end

function [ok, x_right, y_right, u_right, ec_right, handler_log, reason, right_norm, no_mode_change] = ...
    reselection_transaction(t, x, y, Y, u, ec, dae, settings, target_modes, ...
    target_selected, authority)
%RESELECTION_TRANSACTION  Commit an already-authorized Phase-2 target.
%   Authority is established outside the transaction by either the dynamic
%   severity supervisor or the legacy authenticated SG_ON selector.  This
%   function owns only mode transfer, hybrid metadata, and the right-limit KCL
%   acceptance.  Any failure leaves the accepted Phase-1 state unchanged.
ok=false; x_right=x; y_right=y; u_right=u; ec_right=ec;
reason=''; right_norm=inf; no_mode_change=false;
handler_log=struct('details','');
if ~iscell(target_modes) || numel(target_modes)~=numel(dae.devices)
    reason='authorized target mode vector is missing or has the wrong size';
    return;
end
if ~isnumeric(target_selected) || any(~isfinite(target_selected)) || ...
        any(target_selected<1) || any(target_selected>numel(dae.devices)) || ...
        numel(unique(target_selected))~=numel(target_selected)
    reason='authorized target GFM indices are invalid';
    return;
end
if ~any(strcmp(authority,{'severity','severity_sg_online_authenticated','selector'}))
    reason='unknown Phase-2 target authority';
    return;
end
current_modes=current_mode_vector(dae,ec);
if strcmp(authority,'severity_sg_online_authenticated')
    current_gfm=find(strcmpi(current_modes,'gfm'));
    if numel(setdiff(current_gfm,target_selected,'stable'))~=1 || ...
            ~all(ismember(target_selected,current_gfm))
        reason='authenticated SG_ON release must change exactly one current GFM IBR';
        return;
    end
end
changing=find_mode_changes(current_modes,target_modes);
if isempty(changing)
    no_mode_change=true; ok=true;
    handler_log.details=sprintf('%s reselection requires no mode change at t=%.3f.', ...
        authority,t);
    return;
end
ec_right=ec;
ec_right.hybrid_state=stability.ts_hybrid_state_snapshot(ec.hybrid_state);
for k=1:numel(changing)
    idx=changing(k); dev=dae.devices(idx);
    key=matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
    ec_right.hybrid_state.device_modes.(key)=target_modes{idx};
end
try
    x_right=apply_device_transfers(x,y,u,ec,ec_right,dae);
catch me
    reason=sprintf('transfer map failed: %s: %s',me.identifier,me.message);
    return;
end
hs=ec_right.hybrid_state;
hs.selected_gfm_indices=target_selected(:).';
hs.n_gfm_required=numel(target_selected);
% Reference ownership stays with the reclosed SG; no GFM is a reference owner.
if isfield(hs,'committed_config_fingerprint')
    version=0;
    if isfield(hs,'selector_table_version') && isnumeric(hs.selector_table_version) && ...
            isscalar(hs.selector_table_version) && isfinite(hs.selector_table_version)
        version=hs.selector_table_version;
    end
    version=version+1;
    hs.selector_table_version=version;
    hs.committed_config_fingerprint=sprintf( ...
        'sg_on_%s_reselection|selected=%s|n=%d|version=%d', ...
        authority,mat2str(target_selected(:).'),numel(target_selected),version);
end
ec_right.hybrid_state=hs;
[ok,y_right,reason,right_norm]=right_limit( ...
    x_right,y,Y,dae,u_right,ec_right,t,settings.kcl_tol);
if ok
    handler_log.details=sprintf('%s reselection committed at t=%.3f; %d device(s) transitioned.', ...
        authority,t,numel(changing));
end
end

function modes = build_target_modes_frozen(sg_on_result, dae)
%BUILD_TARGET_MODES_FROZEN  Legacy/fallback: target = authenticated selection.
nd = numel(dae.devices);
modes = cell(1, nd);
for k = 1:nd
    dev = dae.devices(k);
    if isfield(dev, 'capabilities') && isfield(dev.capabilities, 'resource_type') && ...
            strcmpi(char(dev.capabilities.resource_type), 'sg')
        modes{k} = 'synchronous';
    elseif isfield(sg_on_result,'selected_gfm_indices') && ...
            ismember(k, sg_on_result.selected_gfm_indices)
        modes{k} = 'gfm';
    else
        modes{k} = 'gfl';
    end
end
end

function modes = modes_from_selected(dae, selected)
nd = numel(dae.devices);
modes = cell(1, nd);
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

function [ok, current_gfm, severity] = post_reclose_severity( ...
    t, x, y, u, ec, dae, settings)
%POST_RECLOSE_SEVERITY  Complete 2-term evidence for each online GFM IBR.
%   S_i = sat(0.5*|V_i-V_ref,i|/0.10 + 0.5*|f_COI-f0|/0.50).
%   f_COI uses the same inertia-weighted online SG/GFM convention as the
%   published diagnostic.  The function returns ok=false unless every current
%   online switchable GFM maps uniquely to a healthy-PF voltage reference and
%   every required measurement is finite.  An empty current_gfm is valid.
[ok, online_ibr, severity_all]=online_ibr_severity(t,x,y,u,ec,dae,settings);
current_gfm=[]; severity=[];
if ~ok, return; end
modes=current_mode_vector(dae,ec);
mask=strcmpi(modes(online_ibr),'gfm');
current_gfm=online_ibr(mask);
severity=severity_all(mask);
end

function [ok, online_ibr, severity] = online_ibr_severity( ...
    t, x, y, u, ec, dae, settings)
%ONLINE_IBR_SEVERITY  Complete two-term AGSI evidence for every online IBR.
%   The scalar contains only J_V and J_f.  Feasibility, SSSA margin, current
%   limits, and reference ownership remain separate non-tradeable gates.
ok=false; online_ibr=[]; severity=[];
nd=numel(dae.devices);
freq=nan(1,nd); inertia=nan(1,nd); online=false(1,nd);
rec_cache=cell(1,nd);
for k=1:nd
    dev=dae.devices(k);
    xi=dae.device_offsets(k)+(1:dev.nx);
    ui=dae.u_offsets(k)+(1:dev.nu);
    try
        rec=dev.reconstruct(t,x(xi),y,u(ui),ec);
    catch
        return;
    end
    rec_cache{k}=rec;
    if ~isfield(rec,'online') || ~isscalar(rec.online)
        return;
    end
    online(k)=logical(rec.online);
    if ~online(k), continue; end
    if strcmpi(char(rec.mode),'sg') && isfield(rec,'omega') && ...
            isfinite(rec.omega) && isfield(rec,'H_system') && ...
            isfinite(rec.H_system) && rec.H_system>0
        freq(k)=settings.severity_f0_Hz*(1+rec.omega);
        inertia(k)=rec.H_system;
    elseif strcmpi(char(rec.mode),'gfm') && ...
            isfield(rec,'gfm') && isstruct(rec.gfm) && ...
            isfield(rec.gfm,'omega_m') && isfinite(rec.gfm.omega_m) && ...
            isfield(rec.gfm,'H_system') && isfinite(rec.gfm.H_system) && ...
            rec.gfm.H_system>0
        freq(k)=settings.severity_f0_Hz*(1+rec.gfm.omega_m);
        inertia(k)=rec.gfm.H_system;
    end
end
use=online & isfinite(freq) & isfinite(inertia) & inertia>0;
if ~any(use), return; end
fcoi=sum(inertia(use).*freq(use))/sum(inertia(use));
if ~isfinite(fcoi), return; end
for k=1:nd
    dev=dae.devices(k); rec=rec_cache{k};
    is_switchable_ibr=isfield(dev,'capabilities') && ...
        isfield(dev.capabilities,'resource_type') && ...
        strcmpi(char(dev.capabilities.resource_type),'ibr') && ...
        isfield(dev.capabilities,'voltage_forming_modes') && ...
        any(strcmpi(string(dev.capabilities.voltage_forming_modes),'gfm'));
    if is_switchable_ibr && online(k) && ...
            any(strcmpi(char(rec.mode),{'gfl','gfm'}))
        online_ibr(end+1)=k; %#ok<AGROW>
    end
end
severity=nan(1,numel(online_ibr));
for q=1:numel(online_ibr)
    k=online_ibr(q); dev=dae.devices(k); bp=dev.bus_position;
    if ~isscalar(bp) || bp<1 || 2*bp>numel(y), return; end
    Vm=abs(complex(y(2*bp-1),y(2*bp)));
    ref_idx=find(settings.healthy_pf_bus_ids==dev.bus_id);
    if numel(ref_idx)~=1 || ~isfinite(Vm), return; end
    vref=settings.healthy_pf_V(ref_idx);
    Jv=abs(Vm-vref)/settings.severity_dV_base;
    Jf=abs(fcoi-settings.severity_f0_Hz)/settings.severity_df_base_Hz;
    severity(q)=min(1,max(0,0.5*Jv+0.5*Jf));
end
ok=all(isfinite(severity));
end

function tf=sg_online_state(dae,ec)
%SG_ONLINE_STATE  True when any synchronous resource remains connected.
tf=false;
for k=1:numel(dae.devices)
    dev=dae.devices(k);
    is_sg=isfield(dev,'capabilities') && ...
        isfield(dev.capabilities,'resource_type') && ...
        strcmpi(char(dev.capabilities.resource_type),'sg');
    if ~is_sg, continue; end
    key=matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
    if isfield(ec.hybrid_state,'device_online') && ...
            isfield(ec.hybrid_state.device_online,key) && ...
            logical(ec.hybrid_state.device_online.(key))
        tf=true;
        return;
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
% event.  No SG or IBR differential coordinate is fabricated here.  Critically,
% keep the accepted left-limit inputs at the breaker close.  The historical
% u_right=initial_u assignment stepped every SG/IBR command at once (1.2876 pu
% in the frozen baseline); the online C1 controller now transfers those
% commands after the close. INITIAL_U remains an explicit target/provenance
% argument and is checked here, but is never committed as a right-limit step.
ec_right=ec; ec_right.hybrid_state=stability.ts_hybrid_state_snapshot(hs_candidate);
if ~isnumeric(initial_u) || numel(initial_u)~=numel(u) || any(~isfinite(initial_u))
    reason='Pre-event handback target is invalid or dimensionally stale.';
    return;
end
u_right=u;
dispatch=dispatch_snapshot(u_right,dae);
[ok,y_right,reason,right_norm]=right_limit(x_right,y,Y,dae,u_right,ec_right,t,kcl_tol);
end

function [cand,est,stats]=advance_adaptive_step(x0,y0,t0,h,dae,Ynet,u,ec, ...
    active,step_opt,s,sync_ctl,use_be,case_data)
%ADVANCE_ADAPTIVE_STEP One trial of the opt-in error-controlled stepper.
% Mirrors the step-doubling trapezoidal + Richardson-LTE algorithm of
% stability.ts_adaptive_driver (that file is never edited) but drives the
% canonical composite kernel stability.ts_step_composite exactly once per
% solve (no second composite residual/Jacobian; see ts_step_composite.m:6).
% Pure: operates on copies of the sync controller, never mutating the caller's
% state. Returns the FULL step, the fine two-half candidate, and a Richardson
% error estimate restricted to the active differential states.
%
%   cand : accepted-candidate fields {x,y,sync,u_end,converged,finite,
%          iterations,residual_norm}. On the trapezoidal path the candidate is
%          the FINE (two-half) solution; on a backward-Euler window step it is
%          the single BE solve.
%   est  : {usable,err,alg_res}. err is the weighted RMS Richardson estimate;
%          alg_res is the KCL residual at the fine solution (last ny entries of
%          the coupled terminal residual). Unusable/inf on a BE step or a
%          non-converged solve.
%   stats: {iterations,residual_norm,domain_rejected,solves} for counters.

% Advance the sync controller on a COPY over the full interval [t0,t0+h].
if use_be
    % Post-event Rannacher restart, mirroring the FIXED path exactly: TWO
    % backward-Euler half-steps (advance_rannacher_restart), convergence-
    % controlled, no Richardson estimate. The single full-h BE solve an
    % earlier revision used is a DIFFERENT trajectory from the fixed restart
    % and landed Newton deeper in the post-event low-voltage kink. Two half
    % steps are also the numerically gentler option for a C0 discontinuity.
    h2=h/2;
    if sync_ctl.active
        [u_h1,sync_h1]=advance_sync_controller(sync_ctl,x0,y0,t0,h2,dae,ec,u,case_data);
    else
        u_h1=u; sync_h1=sync_ctl;
    end
    opt_l=step_opt; opt_l.t_now=t0; opt_l.integration_method='backward_euler';
    left=stability.ts_step_composite(x0,y0,h2,dae,Ynet,u_h1,ec,active,opt_l);
    cand=struct('x',left.x_full,'y',left.y_full,'sync',sync_h1, ...
        'u_end',sync_h1.u_end,'converged',left.converged&&left.finite, ...
        'finite',left.finite,'iterations',left.iterations, ...
        'residual_norm',left.residual_norm);
    est=struct('usable',false,'err',inf,'alg_res',inf);
    stats=struct('iterations',left.iterations,'residual_norm',left.residual_norm, ...
        'domain_rejected',left.domain_rejected_trials,'solves',1);
    if ~(left.converged && left.finite), return; end
    if sync_ctl.active
        [u_h2,sync_h2]=advance_sync_controller(sync_h1,left.x_full,left.y_full, ...
            t0+h2,h2,dae,ec,u,case_data);
    else
        u_h2=u; sync_h2=sync_h1;
    end
    opt_r=step_opt; opt_r.t_now=t0+h2; opt_r.integration_method='backward_euler';
    right=stability.ts_step_composite(left.x_full,left.y_full,h2,dae,Ynet, ...
        u_h2,ec,active,opt_r);
    stats.iterations=stats.iterations+right.iterations;
    stats.residual_norm=max(stats.residual_norm,right.residual_norm);
    stats.domain_rejected=stats.domain_rejected+right.domain_rejected_trials;
    stats.solves=2;
    cand.x=right.x_full; cand.y=right.y_full; cand.sync=sync_h2;
    cand.u_end=sync_h2.u_end; cand.converged=right.converged&&right.finite;
    cand.finite=right.finite; cand.iterations=stats.iterations;
    cand.residual_norm=stats.residual_norm;
    return;   % BE restart: order 1, no LTE gate
end
if sync_ctl.active
    [u_full,sync_full]=advance_sync_controller(sync_ctl,x0,y0,t0,h,dae,ec,u,case_data);
else
    u_full=u; sync_full=sync_ctl;
end
opt_full=step_opt; opt_full.t_now=t0;
full=stability.ts_step_composite(x0,y0,h,dae,Ynet,u_full,ec,active,opt_full);

cand=struct('x',full.x_full,'y',full.y_full,'sync',sync_full, ...
    'u_end',sync_full.u_end,'converged',full.converged&&full.finite, ...
    'finite',full.finite,'iterations',full.iterations, ...
    'residual_norm',full.residual_norm);
est=struct('usable',false,'err',inf,'alg_res',inf);
stats=struct('iterations',full.iterations,'residual_norm',full.residual_norm, ...
    'domain_rejected',full.domain_rejected_trials,'solves',1);

if ~(full.converged && full.finite)
    return;   % reject; est stays unusable
end

% Fine (two composed half-step) solution for the Richardson estimate.
h2=h/2;
if sync_ctl.active
    [u_h1,sync_h1]=advance_sync_controller(sync_ctl,x0,y0,t0,h2,dae,ec,u,case_data);
else
    u_h1=u; sync_h1=sync_ctl;
end
% Each half-step needs its OWN predictor: an x_predictor built for a step of
% length h overshoots by 2x on an h/2 solve. Rescale when the caller supplied
% one (it is an extrapolation from x0, so the increment scales with the step).
opt_h1=step_opt; opt_h1.t_now=t0;
if isfield(step_opt,'x_predictor')
    opt_h1.x_predictor = x0 + (step_opt.x_predictor - x0)/2;
end
h1=stability.ts_step_composite(x0,y0,h2,dae,Ynet,u_h1,ec,active,opt_h1);
stats.iterations=stats.iterations+h1.iterations;
stats.residual_norm=max(stats.residual_norm,h1.residual_norm);
stats.domain_rejected=stats.domain_rejected+h1.domain_rejected_trials;
stats.solves=2;
if ~(h1.converged && h1.finite)
    cand.converged=false; return;
end
if sync_ctl.active
    [u_h2,sync_h2]=advance_sync_controller(sync_h1,h1.x_full,h1.y_full, ...
        t0+h2,h2,dae,ec,u,case_data);
else
    u_h2=u; sync_h2=sync_h1;
end
% The second half starts from the first half's solution, so the caller's
% predictor (an extrapolation from x0) no longer applies. Continue the same
% linear trend from the new base instead of reusing a stale target.
opt_h2=step_opt; opt_h2.t_now=t0+h2;
if isfield(step_opt,'x_predictor')
    opt_h2.x_predictor = h1.x_full + (h1.x_full - x0);
end
hh=stability.ts_step_composite(h1.x_full,h1.y_full,h2,dae,Ynet,u_h2,ec,active,opt_h2);
stats.iterations=stats.iterations+hh.iterations;
stats.residual_norm=max(stats.residual_norm,hh.residual_norm);
stats.domain_rejected=stats.domain_rejected+hh.domain_rejected_trials;
stats.solves=3;
if ~(hh.converged && hh.finite)
    cand.converged=false; return;
end

% Accept the FINE solution and its controller state.
cand.x=hh.x_full; cand.y=hh.y_full; cand.sync=sync_h2; cand.u_end=sync_h2.u_end;
cand.converged=true; cand.finite=hh.finite;
cand.iterations=stats.iterations; cand.residual_norm=stats.residual_norm;

% Richardson LTE (trapezoidal p=2, denominator 2^p-1=3), weighted RMS over the
% ACTIVE differential states only (frozen coordinates are identical in both
% solves so they contribute zero and would only dilute the norm).
ax=active(:)';
e=(hh.x_full-full.x_full)/3;
sc_x=s.atol_x + s.rtol_x.*max(abs(x0(ax)),abs(hh.x_full(ax)));
err_x=sqrt(mean((e(ax)./sc_x).^2));
ey=hh.y_full-full.y_full;
sc_y=s.atol_y + s.rtol_y.*max(abs(y0),abs(hh.y_full));
err_y=sqrt(mean((ey./sc_y).^2));
est.err=max(err_x,err_y);
% Algebraic error: the coupled terminal residual is [rx(active); g_kcl], so the
% KCL residual at the fine solution is its last ny entries (no new residual).
ny=numel(y0);
est.alg_res=norm(hh.terminal_residual_vector(end-ny+1:end),inf);
est.usable=isfinite(est.err) && isfinite(est.alg_res);
end

function reason=adaptive_reject_reason(cand,est,s)
if ~cand.converged
    reason='newton_nonconvergence';
elseif ~est.usable
    reason='nonfinite_estimate';
elseif est.alg_res>s.kcl_tol
    reason='algebraic_residual';
else
    reason='lte_exceeded';
end
end

function [step,stats]=advance_rannacher_restart(x0,y0,t0,h,dae,Ynet,u,ec,active,step_opt,s)
% Two backward-Euler half steps provide the standard Rannacher restart after
% a discontinuity. The intermediate landing is internal and unpublished.
be_opt=step_opt;
be_opt.integration_method='backward_euler';
h2=h/2;
[left,ls]=advance_with_subdivision(x0,y0,t0,h2,dae,Ynet,u,ec,active,be_opt,s,0);
stats=ls;
if ~left.converged || ~left.finite
    step=left;
    return;
end
[right,rs]=advance_with_subdivision(left.x_full,left.y_full,t0+h2,h2, ...
    dae,Ynet,u,ec,active,be_opt,s,0);
stats.attempts=ls.attempts+rs.attempts;
stats.accepted_leaf_steps=ls.accepted_leaf_steps+rs.accepted_leaf_steps;
stats.domain_rejected_trials=ls.domain_rejected_trials+rs.domain_rejected_trials;
stats.subdivision_depth=max(ls.subdivision_depth,rs.subdivision_depth);
stats.terminal_domain_failure=pick_terminal_failure( ...
    ls.terminal_domain_failure,rs.terminal_domain_failure,right,left);
if right.converged && right.finite
    stats.accepted_residual_norm=max( ...
        ls.accepted_residual_norm,rs.accepted_residual_norm);
end
step=right;
step.iterations=left.iterations+right.iterations;
step.residual_norm=max(left.residual_norm,right.residual_norm);
end

function u_new=apply_authenticated_candidate_inputs(u_new,u_candidate,dae)
% The selector and event must use one operating-point input contract. Only
% the project-owned P/Q-reference model consumes its authenticated P_ref/Q_ref
% entries; legacy voltage-reference devices retain their historical path.
if ~isvector(u_candidate) || numel(u_candidate)~=numel(u_new) || ...
        any(~isfinite(u_candidate))
    error('ts_simulate_ibr_hybrid:badCandidateInputs', ...
        'Authenticated candidate inputs must match the composite input vector.');
end
u_candidate=u_candidate(:);
for k=1:numel(dae.devices)
    dev=dae.devices(k);
    % Both project-owned P/Q-reference dual families are covered: the 16-state
    % coupled-swing model and the 17-state decoupled-swing model. A family left
    % out of this list is skipped silently, so the committed configuration would
    % run against the PREVIOUS operating point (RECLOSE-2026-08-13-01).
    if ~isfield(dev,'device_type') || ...
            ~any(strcmpi(char(dev.device_type), ...
                {'ibr_eecon49_dual','ibr_decoupled_dual'}))
        continue;
    end
    for wanted=["P_ref","Q_ref"]
        slot=find(strcmpi(string(dev.input_names),wanted));
        if numel(slot)~=1
            error('ts_simulate_ibr_hybrid:badCandidateInputs', ...
                'Device %s must declare exactly one %s input.', ...
                dev.device_id,char(wanted));
        end
        gi=dae.u_offsets(k)+slot;
        u_new(gi)=u_candidate(gi);
    end
end
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
q_contract=[];
if isfield(case_data.dispatch_contract.post_trip,'post_trip_Qg_MVAr')
    q_contract=case_data.dispatch_contract.post_trip.post_trip_Qg_MVAr;
    if ~isstruct(q_contract) || ~isscalar(q_contract)
        error('ts_simulate_ibr_hybrid:badDispatchContract', ...
            'post_trip_Qg_MVAr must be one scalar struct keyed by device_id.');
    end
end
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
    if ~isempty(q_contract)
        if ~isfield(q_contract,id)
            error('ts_simulate_ibr_hybrid:missingDispatchEntry', ...
                'Post-trip reactive dispatch lacks device %s.',id);
        end
        q_mvar=q_contract.(id);
        if ~isnumeric(q_mvar) || ~isscalar(q_mvar) || ~isreal(q_mvar) || ...
                ~isfinite(q_mvar)
            error('ts_simulate_ibr_hybrid:badDispatchEntry', ...
                'Post-trip reactive dispatch for %s must be finite real MVAr.',id);
        end
        q_slot=find(strcmpi(string(dev.input_names),'Q_ref'));
        if numel(q_slot)~=1
            error('ts_simulate_ibr_hybrid:badDispatchInput', ...
                'Device %s must declare exactly one Q_ref input.',id);
        end
        u_new(dae.u_offsets(k)+q_slot)=q_mvar/Sbase;
    end
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
omega_grid=reference_grid_omega(dae,x,y,u,ec);
gopt=struct('dV_max',case_data.synchronism.dV_max_pu, ...
    'df_max',case_data.synchronism.df_max_pu, ...
    'dtheta_max',case_data.synchronism.dtheta_max_deg, ...
    'dwell_min',settings.sync_dwell);
names=fieldnames(settings.sync_overrides);
for k=1:numel(names), gopt.(names{k})=settings.sync_overrides.(names{k}); end
guard=stability.synchronism_guard(Vbus,rec.V_open_circuit,rec.delta,rec.omega,omega_grid,gopt);
sync_pass=guard.passes;
prospective=stability.sg_prospective_close_metrics( ...
    t,x(xi),y,u(ui),ec,dev,case_data);
guard.passes_synchronism=sync_pass;
guard.prospective=prospective;
guard.passes=sync_pass && prospective.passes;
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
    'reclose_diag',struct(), ...
    'handback_duration_s',NaN,'handback_status','');
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
    'accepted_residual_per_step',[], ...
    'iter_per_step',[],'step_attempts',0,'accepted_steps',0,'status_log',[], ...
    'actual_mode_reselection_time',NaN,'reselection_status','NOT_REQUESTED', ...
    'reference_owner_indices',[],'gfm_reference_resource_indices',[], ...
    'reference_island_ids',[],'committed_config_fingerprint','', ...
    'pre_event_input_fingerprint','', ...
    'selector_table_fingerprint','', ...
    'domain_rejected_trials',0,'subdivision_depth',0);
meta=struct('method','trapezoidal_coupled_newton_shared','full_kcl',true, ...
    'event_aware',true,'failure_id','','failure_reason','', ...
    'domain_rejected_trials',0,'subdivision_depth',0);
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

function append_progress_event(settings,t,event_type,applied,details)
%APPEND_PROGRESS_EVENT  Presentation-only event trace for long batch runs.
if settings.progress_every<=0 || isempty(settings.progress_file), return; end
pfd=fopen(settings.progress_file,'a');
if pfd<0, return; end
cleanup=onCleanup(@() fclose(pfd)); %#ok<NASGU>
text=regexprep(char(string(details)),'[\r\n]+',' ');
fprintf(pfd,'EVENT t=%.4f type=%s applied=%d details=%s\n', ...
    t,char(event_type),logical(applied),text);
end

function value=ternary(condition,a,b)
if condition, value=a; else, value=b; end
end

function rc = assemble_runtime_context(hs, dae)
% Assemble the identity-aligned runtime context (Step F + Step 3). Reads
% committed event-left modes/online from hybrid_state (via makeValidName keys),
% materializes them in dae.devices positional order, and computes the eligible
% dual-mode IBR mask.
%
% Hold/lockout timers are read REAL from hybrid_state (Step 3): the ranker's
% hold/lockout predicates are now meaningful on the production path instead of
% being hardcoded to unblocked. Semantics mirror sg_event_handler.transition_blocked:
%   hold_timers(k)   > 0         -> a required transition on device k is held
%   lockout_timers(k) > event_time -> device k is locked out at event_time
% Missing key = unblocked (struct may omit a device). Malformed (field present
% but non-scalar / non-finite where a numeric scalar is required) is reported
% via runtime_context_malformed so the ranker fails closed.
n = numel(dae.devices);
device_modes = cell(1, n);
device_online = false(1, n);
hold_timers = zeros(1, n);
lockout_timers = -inf(1, n);
runtime_context_malformed = false;
for k = 1:n
    key = matlab.lang.makeValidName(char(dae.devices(k).device_id), 'ReplacementStyle','underscore');
    if isfield(hs,'device_modes') && isfield(hs.device_modes, key)
        device_modes{k} = char(hs.device_modes.(key));
    else
        device_modes{k} = 'gfl';
    end
    if isfield(hs,'device_online') && isfield(hs.device_online, key)
        device_online(k) = logical(hs.device_online.(key));
    end
    % Read real hold timer (seconds remaining; missing key = 0/unblocked).
    if isfield(hs,'hold_timers') && isstruct(hs.hold_timers) && isfield(hs.hold_timers, key)
        hv = hs.hold_timers.(key);
        if isnumeric(hv) && isscalar(hv) && isfinite(hv)
            hold_timers(k) = hv;
        else
            runtime_context_malformed = true;
        end
    end
    % Read real lockout timer (absolute unlock time; missing key = -inf/unblocked).
    if isfield(hs,'lockouts') && isstruct(hs.lockouts) && isfield(hs.lockouts, key)
        lv = hs.lockouts.(key);
        if isnumeric(lv) && isscalar(lv) && isfinite(lv)
            lockout_timers(k) = lv;
        else
            runtime_context_malformed = true;
        end
    end
end
eligible = false(1, n);
for k = 1:n
    if ~device_online(k), continue; end
    dev = dae.devices(k);
    caps = struct();
    if isfield(dev,'capabilities') && isstruct(dev.capabilities)
        caps = dev.capabilities;
    end
    rt = '';
    if isfield(caps,'resource_type'), rt = lower(char(caps.resource_type)); end
    if ~strcmp(rt,'ibr'), continue; end
    if isfield(caps,'can_switch_mode') && ~logical(caps.can_switch_mode), continue; end
    sup = {};
    if isfield(caps,'supported_modes'), sup = caps.supported_modes; end
    has_gfl = any(strcmpi(string(sup),'gfl'));
    has_gfm = any(strcmpi(string(sup),'gfm'));
    if has_gfl && has_gfm, eligible(k) = true; end
end
rc = struct('device_modes',{device_modes},'device_online',device_online, ...
    'hold_timers',hold_timers,'lockout_timers',lockout_timers, ...
    'event_time',0,'eligible_mask',eligible, ...
    'runtime_context_malformed',runtime_context_malformed);
end

function Y = canonical_ybus_from_mpc(mpc)
% Canonical complex Ybus from an mpc struct (mirrors the audited construction
% in ibr_selector_table.m: tap/shift, branch-status col 11, bus shunt G+B).
% Used by trip_transaction to derive the runtime topology fingerprint without
% the LOAD admittance term that the TS-specific build_ybus_local adds (so the
% validator's input fingerprint matches the build-time hash in the no-drift
% case — see composite_dae.build_ybus_local vs canonical_ybus_from_mpc).
bus = mpc.bus; br = mpc.branch; nb = size(bus, 1); Y = complex(zeros(nb));
for k = 1:size(br, 1)
    if size(br, 2) >= 11 && br(k, 11) == 0, continue; end
    from_id = br(k, 1); to_id = br(k, 2);
    i = find(bus(:, 1) == from_id, 1); j = find(bus(:, 1) == to_id, 1);
    if isempty(i) || isempty(j), continue; end
    r = br(k, 3); x = br(k, 4); b = br(k, 5);
    tap = br(k, 9); shift = br(k, 10);
    if tap == 0, tap = 1; end
    a = tap * exp(1i * deg2rad(shift));
    yser = 1 / (r + 1i * x);
    Y(i, i) = Y(i, i) + yser / (a * conj(a)) + 1i * b / 2;
    Y(j, j) = Y(j, j) + yser + 1i * b / 2;
    Y(i, j) = Y(i, j) - yser / conj(a);
    Y(j, i) = Y(j, i) - yser / a;
end

if size(bus, 2) >= 6 && isfield(mpc,'baseMVA') && mpc.baseMVA ~= 0
    Y = Y + diag((bus(:, 5) + 1i * bus(:, 6)) / mpc.baseMVA);
end
end

function [ok,xr,yr,ecr,reason,norm_right]=coordinated_sg_handback( ...
        t,x,y,Y,u,ec,dae,kcl_tol)
% CASE_DEFINED chronology override: once the SG breaker transaction has
% succeeded, return reference ownership to the SG and transfer every online
% dual-mode IBR to GFL atomically.  This is intentionally separate from the
% index/SSSA selector path and is accepted only by device transfer + full KCL.
ok=false; xr=x; yr=y; ecr=ec; reason=''; norm_right=Inf;
if ~isfield(ec,'hybrid_state') || ~isstruct(ec.hybrid_state)
    reason='Missing hybrid_state for coordinated handback.'; return;
end
hs=ec.hybrid_state;
for k=1:numel(dae.devices)
    dev=dae.devices(k); key=matlab.lang.makeValidName(char(dev.device_id), ...
        'ReplacementStyle','underscore');
    is_ibr=isfield(dev,'capabilities') && ...
        strcmpi(char(dev.capabilities.resource_type),'ibr');
    if is_ibr && isfield(hs.device_online,key) && logical(hs.device_online.(key))
        hs.device_modes.(key)='gfl';
    end
end
hs.selected_gfm_indices=[]; hs.n_gfm_required=0;
hs.gfm_reference_resource_indices=[];
if isfield(hs,'reference_owner_indices') && isempty(hs.reference_owner_indices)
    sgidx=find(arrayfun(@(d)isfield(d,'capabilities') && ...
        strcmpi(char(d.capabilities.resource_type),'sg'),dae.devices));
    hs.reference_owner_indices=sgidx;
end
ecr=ec; ecr.hybrid_state=stability.ts_hybrid_state_snapshot(hs);
try
    xr=apply_device_transfers(x,y,u,ec,ecr,dae);
catch me
    reason=sprintf('%s: %s',me.identifier,me.message); return;
end
[ok,yr,reason,norm_right]=right_limit(xr,y,Y,dae,u,ecr,t,kcl_tol);
end

function stamp=chronology_branch_stamp(mpc,from_bus,to_bus,bus_ids)
br=mpc.branch;
hit=find(((br(:,1)==from_bus & br(:,2)==to_bus) | ...
    (br(:,1)==to_bus & br(:,2)==from_bus)) & br(:,11)~=0);
if numel(hit)~=1
    error('ts_simulate_ibr_hybrid:lineTripBranch', ...
        'Chronology branch %g-%g must identify exactly one online branch.',from_bus,to_bus);
end
b=br(hit,:); z=b(3)+1i*b(4);
if abs(z)==0
    error('ts_simulate_ibr_hybrid:lineTripBranch','Chronology branch impedance is zero.');
end
ys=1/z; bc=b(5); tap=b(9); if tap==0, tap=1; end
tap=tap*exp(1i*pi/180*b(10));
Yff=(ys+1i*bc/2)/(abs(tap)^2);
Yft=-ys/conj(tap); Ytf=-ys/tap; Ytt=ys+1i*bc/2;
i=find(bus_ids==b(1),1); j=find(bus_ids==b(2),1);
stamp=zeros(numel(bus_ids));
stamp(i,i)=Yff; stamp(i,j)=Yft; stamp(j,i)=Ytf; stamp(j,j)=Ytt;
end

function [ok,y_right,reason,norm_right]=fault_right_limit_homotopy( ...
        x,y0,Ybase,sched,dae,u,ec,t,kcl_tol)
% Adaptive bisection of an a-priori 1/16 admittance increment is a
% NUMERICAL_METHOD initial-guess strategy only.  Failed substeps are halved
% down to 1/1024; the accepted endpoint still uses the exact sourced Zf and
% unchanged physical KCL tolerance.
y_right=y0; ok=false; reason=''; norm_right=Inf;
fp=sched.fault_bus_position;
lambda=0; dlambda=1/16; min_dlambda=1/1024;
while lambda < 1-10*eps
    target=min(1,lambda+dlambda);
    Yq=Ybase;
    Yq(fp,fp)=Yq(fp,fp)+target/sched.Zf;
    [stage_ok,y_next,stage_reason,stage_norm]=right_limit( ...
        x,y_right,Yq,dae,u,ec,t,kcl_tol);
    if ~stage_ok
        dlambda=dlambda/2;
        if dlambda < min_dlambda
            reason=sprintf('Fault homotopy failed near lambda=%.6f: %s',target,stage_reason);
            norm_right=stage_norm;
            return;
        end
        continue;
    end
    y_right=y_next; lambda=target;
    dlambda=min(1/16,2*dlambda);
end
norm_right=kcl_norm(dae,t,x,y_right,Yq,u,ec);
ok=isfinite(norm_right) && norm_right<=kcl_tol;
if ~ok, reason=sprintf('Exact-fault endpoint KCL %.3e exceeds %.3e.',norm_right,kcl_tol); end
end

function c=initialize_sync_controller(dae,u,sched,case_data)
c=struct('enabled',false,'active',false,'online',false,'sg_index',NaN,'x_delta',NaN, ...
    'x_omega',NaN,'u_tm',NaN,'u_efd',NaN,'bus_position',NaN,'restore_time',NaN, ...
    'H',NaN,'D',NaN,'w0',2*pi*case_data.base_values.frequency_Hz, ...
    'Tsv',0.2,'Tch',0.4,'TA',0.02,'R',0.05,'Pref',NaN, ...
    'omega_n',0.8,'zeta',1.0,'K_omega',NaN,'K_theta',NaN, ...
    'design_classification','PROJECT_DERIVED', ...
    'Tmax',NaN,'Efdmax',3.0, ...
    'Psv',NaN,'Pm',NaN,'Efd',NaN,'u_end',u,'target_u',u, ...
    'handback_indices',[],'handback_start_u',u,'handback_t0',NaN, ...
    'handback_T',NaN,'handback_active',false,'handback_complete',false, ...
    'handback_complete_time',NaN,'handback_alpha',0, ...
    'handback_status','NOT_STARTED','Pref_start',NaN,'Pref_target',NaN, ...
    'Efd_start',NaN,'Efd_target',NaN, ...
    'history_t',[],'history_Psv',[],'history_Pm',[],'history_command',[], ...
    'history_phase_error',[],'history_grid_omega',[], ...
    'history_Efd',[],'history_Efd_command',[],'history_Vopen',[], ...
    'history_handback_alpha',[]);
if ~sched.enabled || ~isfield(sched,'has_chronology') || ~sched.has_chronology
    return;
end
k=find(strcmp({dae.devices.device_id},sched.sg_id));
if numel(k)~=1 || dae.devices(k).nx~=6
    error('ts_simulate_ibr_hybrid:syncControllerSg', ...
        'Chronology synchronizer requires one six-state SG.');
end
slot=find(strcmpi(string(dae.devices(k).input_names),'Tm'));
efdslot=find(strcmpi(string(dae.devices(k).input_names),'Efd'));
if numel(slot)~=1 || numel(efdslot)~=1
    error('ts_simulate_ibr_hybrid:syncControllerTm','SG must expose one Tm and one Efd input.');
end
M=case_data.machines; scale=case_data.base_values.S_base_MVA/M.base.S_MVA;
c.enabled=true; c.sg_index=k; c.x_delta=dae.device_offsets(k)+1;
c.x_omega=dae.device_offsets(k)+2; c.u_tm=dae.u_offsets(k)+slot;
c.bus_position=dae.devices(k).bus_position; c.restore_time=sched.sg_on;
c.H=M.units.H/scale; c.D=M.units.D/scale;
c.u_efd=dae.u_offsets(k)+efdslot;
c.target_u=u(:);
for q=1:numel(dae.devices)
    if q==k, continue; end
    names=string(dae.devices(q).input_names);
    slots=find(ismember(lower(names),["p_ref","q_ref"]));
    c.handback_indices=[c.handback_indices,dae.u_offsets(q)+slots]; %#ok<AGROW>
end
c.Tmax=max([u(c.u_tm),1.3462]);
c.Pref=u(c.u_tm);
c.K_omega=4*c.H*c.zeta*c.omega_n-c.D;
c.K_theta=2*c.H*c.omega_n^2/c.w0;
end

function c=activate_sync_controller(c,u,t)
if ~c.enabled, return; end
c.active=true; c.online=false; c.Psv=u(c.u_tm); c.Pm=u(c.u_tm); c.Efd=u(c.u_efd); c.u_end=u;
c.history_t=t; c.history_Psv=c.Psv; c.history_Pm=c.Pm;
c.history_command=c.Pm; c.history_phase_error=NaN; c.history_grid_omega=NaN;
c.history_Efd=c.Efd; c.history_Efd_command=c.Efd; c.history_Vopen=NaN;
c.history_handback_alpha=NaN;
end

function c=enter_online_governor(c,u,t,T_handback)
% Bumpless transition to the Sauer-Pai Type-A non-reheat turbine and
% droop-governor equations after breaker close.  Pref is the frozen
% pre-event equilibrium mechanical input; the six EMF6 machine states are
% unchanged by this supervisory two-state prime-mover model.
if ~c.enabled, return; end
if ~isfinite(T_handback) || T_handback<=0
    error('ts_simulate_ibr_hybrid:badHandbackDuration', ...
        'C1 handback duration must be finite and positive.');
end
c.active=true; c.online=true; c.Psv=u(c.u_tm); c.Pm=u(c.u_tm);
c.Efd=u(c.u_efd); c.u_end=u;
c.handback_start_u=u(:); c.handback_t0=t; c.handback_T=T_handback;
c.handback_active=true; c.handback_complete=false;
c.handback_complete_time=NaN; c.handback_alpha=0;
c.handback_status='C1_ACTIVE';
c.Pref_start=c.Pm; c.Pref_target=c.target_u(c.u_tm);
c.Efd_start=c.Efd; c.Efd_target=c.target_u(c.u_efd);
c.history_t(end+1)=t; c.history_Psv(end+1)=c.Psv;
c.history_Pm(end+1)=c.Pm; c.history_command(end+1)=c.Pref;
c.history_phase_error(end+1)=NaN; c.history_grid_omega(end+1)=NaN;
c.history_Efd(end+1)=c.Efd; c.history_Efd_command(end+1)=c.Efd;
c.history_Vopen(end+1)=NaN;
c.history_handback_alpha(end+1)=0;
end

function [u_step,c]=advance_sync_controller(c,x,y,t,h,dae,ec,u,case_data)
omega=x(c.x_omega); wgrid=reference_grid_omega(dae,x,y,u,ec);
vb=complex(y(2*c.bus_position-1),y(2*c.bus_position));
if c.online
    % Sauer-Pai (4.100), (4.116):
    %   Tsv*dPsv/dt = -Psv + Pc - Delta_omega/R
    %   Tch*dPm/dt  = -Pm + Psv
    % Pc=Pref is frozen from the accepted pre-event equilibrium.  No AGC
    % or secondary integral is introduced.
    [am,~,~]=stability.c1_smoothstep(t+0.5*h,c.handback_t0,c.handback_T);
    [a1,~,~]=stability.c1_smoothstep(t+h,c.handback_t0,c.handback_T);
    pref_mid=c.Pref_start+am*(c.Pref_target-c.Pref_start);
    gp=struct('Tsv',c.Tsv,'Tch',c.Tch,'R',c.R,'Pref',pref_mid, ...
        'Pmin',0,'Pmax',c.Tmax);
    [Psv1,Pm1,command]=stability.sg_turbine_governor_step( ...
        c.Psv,c.Pm,omega,h,gp);
    u_step=u;
    if ~isempty(c.handback_indices)
        u_step(c.handback_indices)=c.handback_start_u(c.handback_indices)+ ...
            am*(c.target_u(c.handback_indices)-c.handback_start_u(c.handback_indices));
    end
    efd_mid=c.Efd_start+am*(c.Efd_target-c.Efd_start);
    efd_end=c.Efd_start+a1*(c.Efd_target-c.Efd_start);
    u_step(c.u_tm)=0.5*(c.Pm+Pm1); u_step(c.u_efd)=efd_mid;
    c.Psv=Psv1; c.Pm=Pm1; c.Efd=efd_end; c.u_end=u;
    if ~isempty(c.handback_indices)
        c.u_end(c.handback_indices)=c.handback_start_u(c.handback_indices)+ ...
            a1*(c.target_u(c.handback_indices)-c.handback_start_u(c.handback_indices));
    end
    c.u_end(c.u_tm)=Pm1; c.u_end(c.u_efd)=efd_end;
    c.handback_alpha=a1;
    if a1>=1
        c.handback_active=false; c.handback_complete=true;
        c.handback_complete_time=t+h; c.handback_status='C1_COMPLETE';
    end
    c.history_t(end+1)=t+h; c.history_Psv(end+1)=Psv1;
    c.history_Pm(end+1)=Pm1; c.history_command(end+1)=command;
    c.history_phase_error(end+1)=NaN; c.history_grid_omega(end+1)=wgrid;
    c.history_Efd(end+1)=efd_end; c.history_Efd_command(end+1)=efd_mid;
    c.history_Vopen(end+1)=NaN;
    c.history_handback_alpha(end+1)=a1;
    if any(~isfinite([Psv1 Pm1 command]))
        error('ts_simulate_ibr_hybrid:onlineGovernorNonFinite', ...
            'Post-reclose SG governor produced a non-finite state.');
    end
    return;
end
dev=dae.devices(c.sg_index); xi=dae.device_offsets(c.sg_index)+(1:dev.nx);
ui=dae.u_offsets(c.sg_index)+(1:dev.nu);
rec=dev.reconstruct(t,x(xi),y,u(ui),ec);
if ~isfield(rec,'V_open_circuit') || ~isfinite(rec.V_open_circuit)
    error('ts_simulate_ibr_hybrid:syncControllerVoltage', ...
        'SG synchronizer requires one finite open-circuit voltage phasor.');
end
Vopen=abs(rec.V_open_circuit);
phase_error=angle(exp(1i*(angle(vb)-angle(rec.V_open_circuit))));
% Breaker-open synchronizer command bound. Pmin MUST be negative: the model's
% damping torque D*omega vanishes at omega=0 (deviation), so with a non-negative
% command floor the synchronizer cannot RETARD a rotor that already matches grid
% speed but leads the grid angle. Then the proportional angle term K_theta*e_theta,
% when it needs to decelerate (e_theta demanding a negative command), is clipped
% to 0, the rotor coasts to omega=0 and the angle FREEZES at a standing offset
% (observed ~106 deg -> reclose SYNC_TIMEOUT). The offline command is the
% project-derived synchronizer actuator (a governor speed/torque bias during
% breaker-open alignment, not literal turbine output), so a symmetric authority
% Pmin=-Pmax restores the closed loop
%   2H de_omega/dt = -(D+K_omega) e_omega - K_theta e_theta,  de_theta/dt = w0 e_omega
% i.e. d2 e_theta/dt2 + 2*zeta*wn*d e_theta/dt + wn^2 e_theta = 0, which drives
% e_theta->0 from EITHER sign (proven by chk_sync_fix_oracle_tmp: Pmin=0 freezes,
% Pmin=-Pmax converges in ~5 s). The online governor (post-close) keeps Pmin=0
% because a loaded turbine genuinely cannot absorb power.
sopt=struct('H',c.H,'D',c.D,'omega_0',c.w0, ...
    'omega_n',c.omega_n,'zeta',c.zeta,'Tsv',c.Tsv,'Tch',c.Tch, ...
    'Pmin',-c.Tmax,'Pmax',c.Tmax);
[Psv1,Pm1,command]=stability.sg_offline_synchronizer_step( ...
    c.Psv,c.Pm,omega,wgrid,phase_error,h,sopt);
Efd_command=c.Efd;
if isfinite(Vopen) && Vopen>1e-8
    Efd_command=min(c.Efdmax,max(0,c.Efd*abs(vb)/Vopen));
end
ea=exp(-h/c.TA); Efd1=Efd_command+(c.Efd-Efd_command)*ea;
u_step=u; u_step(c.u_tm)=0.5*(c.Pm+Pm1); u_step(c.u_efd)=0.5*(c.Efd+Efd1);
c.Psv=Psv1; c.Pm=Pm1; c.Efd=Efd1; c.u_end=u;
c.u_end(c.u_tm)=Pm1; c.u_end(c.u_efd)=Efd1;
c.history_t(end+1)=t+h; c.history_Psv(end+1)=Psv1;
c.history_Pm(end+1)=Pm1; c.history_command(end+1)=command;
c.history_phase_error(end+1)=phase_error;
c.history_grid_omega(end+1)=wgrid;
c.history_Efd(end+1)=Efd1; c.history_Efd_command(end+1)=Efd_command;
c.history_Vopen(end+1)=Vopen;
c.history_handback_alpha(end+1)=NaN;
if any(~isfinite([Psv1 Pm1 command Efd1]))
    error('ts_simulate_ibr_hybrid:syncControllerNonFinite', ...
        'SG synchronizer produced a non-finite controller state.');
end

if case_data.base_values.frequency_Hz<=0
    error('ts_simulate_ibr_hybrid:syncControllerFrequency','Invalid frequency base.');
end
end

function w=reference_grid_omega(dae,x,y,u,ec)
w=0;
for k=1:numel(dae.devices)
    dev=dae.devices(k); xi=dae.device_offsets(k)+(1:dev.nx);
    ui=dae.u_offsets(k)+(1:dev.nu);
    out=dev.reconstruct(0,x(xi),y,u(ui),ec);
    if isfield(out,'online') && logical(out.online) && isfield(out,'gfm') && ...
            isstruct(out.gfm) && isfield(out.gfm,'omega_m') && isfinite(out.gfm.omega_m)
        w=out.gfm.omega_m; return;
    end
end
end
