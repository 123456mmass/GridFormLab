function res = ts_adaptive_driver(strat, x0, y0, t_span, events, opt)
%TS_ADAPTIVE_DRIVER  Generic adaptive-step (variable dt) TS controller.
%   RES = ts_adaptive_driver(STRAT, X0, Y0, T_SPAN, EVENTS, OPT) integrates the
%   DAE ẋ=f(x,y,Y), 0=g(x,y,Y) over T_SPAN = [t0, t_end] using an implicit
%   trapezoidal one-step (ts_step_kernel) with step doubling, a fine-solution
%   LTE estimator, weighted state-aware norm, accept/reject, and a dt
%   controller. This is the ONE adaptive controller shared by classical,
%   Padiyar, and EMF6 via the model-strategy contract.
%
%   Numerical method (see docs/project/plans/adaptive_ts_track_a.md):
%     - Implicit trapezoidal: global order p=2, local order p+1=3.
%     - Step doubling: one full step of size h -> x_full; two half steps of
%       size h/2 -> x_halfhalf. Accepted candidate = x_halfhalf.
%     - Fine-solution LTE estimator: e = (x_halfhalf - x_full) / (2^p - 1)
%       = (x_halfhalf - x_full) / 3  (p=2). Project-derived; proven by analytic
%       test (test_ts_adaptive_lte, Test C) before production use.
%     - Weighted norm: sc_i = atol_i + rtol_i*max(|x_n_i|,|x_cand_i|);
%       err_x = rms(e_i / sc_i). No max(|x|,1) floor.
%     - Combined DAE error: err = max(err_x, err_y) with voltage scaling.
%     - Accept iff err <= 1 and algebraic residual <= g_tol. On reject, halve
%       dt and retry from the same (x,y).
%     - dt controller (accept): dt_new = dt*min(fac_max,max(fac_min,
%       fac*(1/err)^(1/(p+1)))) = dt*...*(1/err)^(1/3). Exponent 1/3.
%     - Exact event landing: if the next event time is within dt, shrink dt to
%       land exactly on the event. The arrival step uses the LEFT topology only;
%       at the event, switch topology and re-solve y under the right topology.
%       No trapezoidal step or interpolation crosses a topology change.
%     - Rejection: restore x, y, Jyy/cache, topology-local mutable state
%       exactly; do NOT alter accepted output arrays; append exactly one
%       rejection diagnostic record.
%     - Fail-closed: if dt hits dt_min and err > 1, ERROR with diagnostics
%       (no silent fixed-step fallback).
%
%   EVENTS is a struct with fields Ypre, Yfault, Ypost, t_fault, t_clear,
%   fault_enabled, matching ts_topology_at's convention.
%
%   Result schema (frozen, see plan §5): r.t is the accepted raw adaptive grid
%   (strictly increasing, unique); r.dt is scalar nominal; r.dt_nominal;
%   r.dt_history = diff(r.t); r.lte_history (per accepted step); r.accepted_steps;
%   r.rejected_steps; r.rejection_history (struct array); r.event_diagnostics.

p = 2;                                  % trapezoidal global order
q = p + 1;                              % local order (LTE ~ O(h^q))
denom = 2^p - 1;                         % Richardson fine-solution denom = 3
exp_ctl = 1/q;                           % controller exponent = 1/3

t0 = t_span(1); t_end = t_span(2);
dt = opt.dt_init;  if isempty(dt), dt = opt.dt_nominal; end
dt_min = opt.dt_min;
dt_max = opt.dt_max;
fac     = opt.controller_fac;      if isempty(fac),     fac = 0.9;     end
fac_min = opt.controller_fac_min;  if isempty(fac_min),  fac_min = 0.2;  end
fac_max = opt.controller_fac_max;  if isempty(fac_max),  fac_max = 5.0;  end
reject_limit = opt.reject_limit;   if isempty(reject_limit), reject_limit = 10; end

atol_x = opt.atol_x;   if isempty(atol_x), atol_x = 1e-6;  end
rtol_x = opt.rtol_x;   if isempty(rtol_x), rtol_x = 1e-4;  end
atol_y = opt.atol_y;   if isempty(atol_y), atol_y = 1e-5;  end
rtol_y = opt.rtol_y;   if isempty(rtol_y), rtol_y = 1e-4;  end
g_tol  = opt.algebraic_tolerance;

kopt = struct('max_corrector_iter',opt.max_corrector_iter, ...
    'corrector_abs_tol',opt.corrector_abs_tol, ...
    'corrector_rel_tol',opt.corrector_rel_tol, ...
    'corrector_mode', opt.corrector_mode, ...
    'algebraic_tolerance', g_tol);
if strcmp(opt.corrector_mode,'fixed')
    if isfield(opt,'corrector_iter') && ~isempty(opt.corrector_iter)
        kopt.max_corrector_iter = opt.corrector_iter;
    else
        kopt.max_corrector_iter = 3;
    end
end

% --- Accepted trajectory storage -------------------------------------------
t_acc = t0;
x = x0(:); y = y0(:);
Y_rec0 = events.Ypre;
rec0 = strat.reconstruct(x, y, Y_rec0);
delta_hist = rec0.delta;   % row [1, ng]
omega_hist = rec0.omega;
Pe_hist = rec0.Pe;
Vbus_hist = rec0.Vbus;
t_hist = t0;
dt_history = zeros(0,1); lte_history = zeros(0,1);
rejection_history = struct('time',{},'attempted_dt',{},'error_norm',{}, ...
    'reason',{},'retry_dt',{},'topology',{},'algebraic_residual',{}, ...
    'rejection_count',{});
event_diagnostics = struct('time',{},'side',{},'topology',{}, ...
    'algebraic_residual',{});

% --- Event times (sorted, unique) -----------------------------------------
event_times = [];
if events.fault_enabled
    if isfinite(events.t_fault) && events.t_fault > t0 && events.t_fault < t_end
        event_times = [event_times; events.t_fault]; end
    if isfinite(events.t_clear) && events.t_clear > t0 && events.t_clear < t_end
        event_times = [event_times; events.t_clear]; end
end
event_times = sort(unique(event_times));

t = t0;
ng = strat.state_split.ng;
nb = numel(y)/2;
accepted_steps = 0; rejected_steps = 0;

while t < t_end - 1e-14
    % Next event within dt? Shrink dt to land exactly on the event.
    t_target = t + dt;
    next_event = [];
    for et = event_times.'
        if et > t + 1e-14 && et < t_target + 1e-14
            next_event = et; t_target = et; break;
        end
    end
    if t_target > t_end, t_target = t_end; end
    h = t_target - t;
    if h < dt_min, h = dt_min; t_target = t + h; end
    if t_target > t_end, t_target = t_end; h = t_target - t; end

    Y_now = stability.ts_topology_at(t, events, events.Ypre, events.Yfault, events.Ypost);

    % --- Step doubling: one full step h, two half steps h/2 ---------------
    reject_count = 0;
    accepted = false;
    while ~accepted
        step_full = stability.ts_step_kernel(strat, x, y, h, Y_now, kopt);
        step_h1  = stability.ts_step_kernel(strat, x, y, h/2, Y_now, kopt);
        step_h2  = stability.ts_step_kernel(strat, step_h1.x_full, step_h1.y_full, h/2, Y_now, kopt);
        x_halfhalf = step_h2.x_full; y_halfhalf = step_h2.y_full;
        x_full = step_full.x_full;

        % Fine-solution LTE estimator e = (x_halfhalf - x_full)/(2^p-1) = /3.
        e = (x_halfhalf - x_full) / denom;

        % Weighted state-aware norm (no max(|x|,1) floor).
        sc_x = atol_x + rtol_x * max(abs(x), abs(x_halfhalf));
        err_x = sqrt(mean((e ./ sc_x).^2));

        % Combined DAE error: include algebraic (voltage) error.
        e_y = (y_halfhalf - step_full.y_full);
        sc_y = atol_y + rtol_y * max(abs(y), abs(y_halfhalf));
        err_y = sqrt(mean((e_y ./ sc_y).^2));
        err = max(err_x, err_y);

        alg_res = step_h2.algebraic_residual;
        if strat.needs_algebraic_solve == false
            alg_res = 0;   % classical: linear, exact by construction
        end

        if err <= 1 && alg_res <= g_tol
            % Accept. Advance to the fine solution x_halfhalf, y_halfhalf.
            x = x_halfhalf; y = y_halfhalf;
            accepted_steps = accepted_steps + 1;
            t = t_target;
            t_hist = [t_hist; t]; %#ok<AGROW>
            dt_history = [dt_history; h]; %#ok<AGROW>
            lte_history = [lte_history; err]; %#ok<AGROW>
            accepted = true;
            % Event landing: if we landed on an event, switch topology and
            % re-solve y under the right topology; record left/right diag.
            % Public sample uses the RIGHT-limit y (per event convention §6).
            if ~isempty(next_event) && abs(t - next_event) < 1e-14
                Y_right = stability.ts_topology_at(t + 1e-14, events, events.Ypre, events.Yfault, events.Ypost);
                y_left = y;
                if strat.needs_algebraic_solve
                    Jyy_r = strat.jac_y(x, y, Y_right);
                    [y_right, alg_r] = stability.ts_algebraic_solve(x, y, Y_right, strat.dae_g, @stability.ts_jac_y_fd, g_tol, Jyy_r);
                    if ~alg_r.converged
                        error('ts_adaptive_driver:eventAlgebraic', ...
                            'Right-topology algebraic solve failed at event t=%.6g: residual=%.3e.', t, alg_r.final_residual);
                    end
                    alg_res_right = alg_r.final_residual;
                else
                    y_right = y;  % classical: re-solved inline in dae_f next step
                    alg_res_right = 0;
                end
                event_diagnostics = [event_diagnostics; struct( ...
                    'time', t, 'side', 'right', 'topology', 'right', ...
                    'algebraic_residual', alg_res_right)]; %#ok<AGROW>
                event_diagnostics = [event_diagnostics; struct( ...
                    'time', t, 'side', 'left', 'topology', 'left', ...
                    'algebraic_residual', alg_res)]; %#ok<AGROW>
                y = y_right;
            end
            % Record the public sample AFTER any event topology switch, so
            % the stored Vbus at t_event reflects the right-limit (faulted)
            % voltage (event convention §6). Pass the current-topology Y so
            % classical (linear-network) reconstruction uses the right Y.
            Y_rec = stability.ts_topology_at(t, events, events.Ypre, events.Yfault, events.Ypost);
            rec = strat.reconstruct(x, y, Y_rec);
            delta_hist = [delta_hist; rec.delta]; %#ok<AGROW>
            omega_hist = [omega_hist; rec.omega]; %#ok<AGROW>
            Pe_hist = [Pe_hist; rec.Pe]; %#ok<AGROW>
            Vbus_hist = [Vbus_hist; rec.Vbus]; %#ok<AGROW>
            % dt controller (accept): dt_new = dt*min(fac_max,max(fac_min,fac*(1/err)^(1/q))).
            if err > 0
                factor = min(fac_max, max(fac_min, fac*(1/err)^(exp_ctl)));
            else
                factor = fac_max;
            end
            dt = min(dt_max, max(dt_min, dt * factor));
        else
            % Reject: restore committed state (x,y unchanged), append one
            % rejection diagnostic, halve dt, retry.
            rejected_steps = rejected_steps + 1;
            reject_count = reject_count + 1;
            reason = '';
            if err > 1, reason = 'lte_exceeded'; end
            if alg_res > g_tol, reason = [reason, ';algebraic_residual']; end
            rejection_history = [rejection_history; struct( ...
                'time', t, 'attempted_dt', h, 'error_norm', err, 'reason', reason, ...
                'retry_dt', max(dt_min, h/2), 'topology', topo_name(Y_now,events), ...
                'algebraic_residual', alg_res, 'rejection_count', reject_count)]; %#ok<AGROW>
            dt = h/2;
            if dt < dt_min * (1 - 1e-14)
                if err > 1
                    error('ts_adaptive_driver:dtMinExhausted', ...
                        ['Adaptive step rejected at t=%.6g after %d retries; dt hit dt_min=%.3e ' ...
                        'with error=%.3e (tol=1). No silent fixed-step fallback.'], ...
                        t, reject_count, dt_min, err);
                end
                error('ts_adaptive_driver:dtMinExhausted', ...
                    ['Adaptive step rejected at t=%.6g after %d retries; dt hit dt_min=%.3e ' ...
                    'with algebraic residual=%.3e (tol=%.3e). No silent fixed-step fallback.'], ...
                    t, reject_count, dt_min, alg_res, g_tol);
            end
            if reject_count >= reject_limit
                error('ts_adaptive_driver:rejectLimit', ...
                    ['Adaptive step rejected %d times at t=%.6g; error=%.3e, dt=%.3e. ' ...
                    'No silent fixed-step fallback.'], reject_count, t, err, h);
            end
            h = dt;
            t_target = t + h;
            % Re-check event landing with the new smaller dt.
            for et = event_times.'
                if et > t + 1e-14 && et < t_target + 1e-14
                    t_target = et; h = t_target - t; break;
                end
            end
            if t_target > t_end, t_target = t_end; h = t_target - t; end
        end
    end
end

res = struct();
res.t = t_hist(:);
res.delta = delta_hist;
res.omega = omega_hist;
res.Pe_pu = Pe_hist;
res.Vbus = Vbus_hist;
res.dt = opt.dt_nominal;
res.dt_nominal = opt.dt_nominal;
res.dt_history = dt_history;
res.lte_history = lte_history;
res.accepted_steps = accepted_steps;
res.rejected_steps = rejected_steps;
res.rejection_history = rejection_history;
res.event_diagnostics = event_diagnostics;
res.stepper = 'adaptive';
res.p = p; res.q = q; res.denominator = denom; res.controller_exponent = exp_ctl;
end

% =========================================================================
function name = topo_name(Y, events)
if ~events.fault_enabled, name = 'pre'; return; end
if max(abs(Y(:) - events.Ypre(:)),[],'all') == 0, name = 'pre'; return; end
if max(abs(Y(:) - events.Yfault(:)),[],'all') == 0, name = 'fault'; return; end
if max(abs(Y(:) - events.Ypost(:)),[],'all') == 0, name = 'post'; return; end
name = 'unknown';
end
