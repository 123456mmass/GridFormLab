function [ok, reason, audit] = certify_support_transition( ...
    t, x_right, y_right, u_right, ec_right, Y, dae, settings, candidate)
%CERTIFY_SUPPORT_TRANSITION  Fail-closed forward trial before a support commit.
%   [OK, REASON, AUDIT] = CERTIFY_SUPPORT_TRANSITION(T, X_RIGHT, Y_RIGHT,
%   U_RIGHT, EC_RIGHT, Y, DAE, SETTINGS, CANDIDATE) integrates the ACCEPTED
%   right state of a support transaction (post-transfer, post right-limit KCL,
%   with or without incumbent conditioning) forward for a short horizon with
%   the installed certified input and event context held constant, using the
%   same canonical coupled-trapezoidal kernel the production driver uses
%   (stability.ts_step_composite). The transaction is REFUSED when the trial
%   loses synchronism (the validated relative-angle excursion reaches the
%   unstable-equilibrium separation) or fails to converge.
%
%   The trial is the DECISION ORACLE for the support transaction: the same DAE
%   and the same kernel production integrates, so it answers "does the island
%   ride this arrival" from the governing equations rather than from a fitted
%   threshold. Its faithfulness is established: started from the untouched
%   arrival of the t=22.0521 [2 4] commit it reproduces the independently known
%   production outcome (19.7 deg, omega -> 1.00017, matching the baseline run
%   that went on to a healthy release), while the same commit conditioned to the
%   destination equilibrium slips to 376 deg.
%
%   The horizon is derived, never fitted:
%     t_settle = log(1/rho) / (-candidate.omega)
%   is the repository's own CASE_DEFINED settling formula (case_data.delays
%   records rho=0.05 and the formula string; compute_tdown and
%   derive_handback_duration use the identical expression on certified
%   SSSA spectra). The trial horizon is max(t_settle, sync_dwell), rounded
%   UP to an integer number of periods of the candidate's dominant
%   oscillatory mode when one exists, so the trial always covers the full
%   settling envelope of the certified destination.
%
%   Contract (AGSI-2026-08-14-02):
%   - Reads only the devices whose mode is 'gfm' in EC_RIGHT (the frozen-
%     branch states of GFL devices are never read: dual-branch trap).
%   - The excursion metric is the validated decisive-replay metric
%     (chk_t53_replay_basin_tmp.m:98-99): unwrap each device angle along
%     trial time, subtract the first device's time series, and take the max
%     drift of those relative angles. Measured separation between riding and
%     slipping arrivals in this system: 15.6-19.7 deg versus 376-4358 deg.
%   - Early-exits on the first step whose excursion reaches the limit; the
%     exit is exact for a max-over-window criterion, not an approximation.
%   - Step failures are retried with BOUNDED subdivision (depth 4:
%     0.01 -> 0.000625 s), the same recovery pattern the production driver
%     uses after events (max_step_subdivisions, ts_simulate_ibr_hybrid
%     :243-275). A step that still fails after exhausting the depth rejects
%     the trial fail-closed (no subdivision is a tolerance change).
%   - Never mutates any input: every step operates on local copies and the
%     kernel itself is re-entrant (no persistent/global state on this path).
%   - Fewer than two formers is trivially certified because there is no
%     pairwise relation to protect.
%
%   Classification of the numeric choices (see the approved plan):
%     horizon formula + rho ......... CASE_DEFINED (case_data.delays)
%     horizon floor (sync_dwell) .... CASE_DEFINED (case_data.synchronism)
%     horizon cap ................... PROJECT_DERIVED arithmetic of the
%                                     candidate's own certified spectrum
%     pole-slip limit ................ PROJECT_DERIVED unstable-equilibrium
%                                     separation (180 deg); see the block
%                                     comment at slip_limit_deg.
%     trial dt = 0.01 s ............. NUMERICAL_METHOD: the validated
%                                     decisive-replay step; not the
%                                     production dt.
%     subdivision depth 4 ........... NUMERICAL_METHOD: mirrors the
%                                     driver's post-event recovery; bounded,
%                                     exact-fail-closed at the floor.
%     state_predictor = linear_kcl .. NUMERICAL_METHOD: mirrors the canonical
%                                     production chronology's predictor; it
%                                     changes only the Newton initial guess,
%                                     never the trapezoidal residual or the
%                                     acceptance tolerance (ts_step_composite
%                                     :107-127).

trial_dt = 0.01;          % NUMERICAL_METHOD, see header.
subdiv_max = 4;           % NUMERICAL_METHOD, see header.
% PROJECT_DERIVED loss-of-synchronism boundary. This is the UNSTABLE
% EQUILIBRIUM separation, not the 90-degree steady-state pull-out limit:
% under the equal-area criterion a machine (or a heavily damped grid-forming
% VSG, whose first swing is smaller than a synchronous machine's) may swing
% past the P-delta peak and still recover, and published grid-forming
% transient-stability analyses state the loss-of-synchronism condition at the
% unstable equilibrium point (~180 deg - delta_SEP), not at 90 deg. A first
% implementation used 90 deg and false-rejected a support commit that the
% production baseline rode healthily (measured: 19.7 deg stable arrival vs
% 376 deg slip on the same commit). The measured separation between riding and
% slipping arrivals in this system is 15.6-19.7 deg versus 376-4358 deg, so any
% limit between roughly 120 and 500 deg yields identical verdicts on the
% available evidence; 180 deg is the unambiguous out-of-step separation.
slip_limit_deg = 180.0;

ok = false;
reason = '';
audit = struct('applied', false, 'classification', 'PROJECT_DERIVED', ...
    'horizon', NaN, 'trial_dt', trial_dt, 'slip_limit_deg', slip_limit_deg, ...
    'steps_run', 0, 't_reached', 0, 'peak_excursion_deg', 0, ...
    'peak_speed_spread_Hz', 0, 'subdivisions', 0, 'gfm_device_ids', {{}}, ...
    'exit_reason', '', 'failure_id', '');

% --- input validation ------------------------------------------------------
if ~isnumeric(t) || ~isscalar(t) || ~isfinite(t) || ...
        ~isnumeric(x_right) || ~isvector(x_right) || any(~isfinite(x_right(:))) || ...
        ~isnumeric(y_right) || ~isvector(y_right) || any(~isfinite(y_right(:))) || ...
        ~isnumeric(u_right) || ~isvector(u_right) || any(~isfinite(u_right(:))) || ...
        ~isstruct(dae) || ~isfield(dae,'devices') || ~isfield(dae,'device_offsets') || ...
        ~isstruct(ec_right) || ~isfield(ec_right,'hybrid_state') || ...
        ~isfield(ec_right.hybrid_state,'device_modes') || ...
        ~isstruct(settings) || ~isstruct(candidate)
    audit.failure_id = 'certify_support_transition:badInputs';
    audit.exit_reason = audit.failure_id;
    reason = 'The certificate requires finite right-state vectors and a complete DAE/context.';
    return;
end
if ~isnumeric(Y) || ~all(isfinite(Y(:))) || size(Y,1) ~= size(Y,2)
    audit.failure_id = 'certify_support_transition:badInputs';
    audit.exit_reason = audit.failure_id;
    reason = 'The live network admittance must be a finite square matrix.';
    return;
end

% --- mode-aware GFM set (never read frozen GFL-branch states) --------------
nd = numel(dae.devices);
ga = []; go = []; ids = {};
for k = 1:nd
    dev = dae.devices(k);
    key = matlab.lang.makeValidName(char(dev.device_id), ...
        'ReplacementStyle','underscore');
    if ~isfield(ec_right.hybrid_state.device_modes, key), continue; end
    if ~strcmpi(char(ec_right.hybrid_state.device_modes.(key)), 'gfm'), continue; end
    if isfield(ec_right.hybrid_state,'device_online') && ...
            isfield(ec_right.hybrid_state.device_online,key) && ...
            ~logical(ec_right.hybrid_state.device_online.(key))
        continue;
    end
    nm = dev.state_names;
    jd = find(strcmp(nm,'gfm_delta_VSG'));
    jo = find(strcmp(nm,'gfm_omega_VSG'));
    if numel(jd) ~= 1 || numel(jo) ~= 1
        audit.failure_id = 'certify_support_transition:badDeviceLayout';
        audit.exit_reason = audit.failure_id;
        reason = sprintf('Device %s must own exactly one gfm_delta_VSG/gfm_omega_VSG pair.', ...
            char(dev.device_id));
        return;
    end
    ga(end+1) = dae.device_offsets(k) + jd; %#ok<AGROW>
    go(end+1) = dae.device_offsets(k) + jo; %#ok<AGROW>
    ids{end+1} = char(dev.device_id); %#ok<AGROW>
end
audit.gfm_device_ids = ids;
if numel(ga) < 2
    ok = true;
    audit.applied = true;
    audit.exit_reason = 'fewerThanTwoFormers';
    return;
end

% --- horizon from the repository's own settling formula --------------------
rho = settings.rho;
if ~isfield(candidate,'omega') || ~isfinite(candidate.omega) || ...
        candidate.omega >= 0
    audit.failure_id = 'certify_support_transition:badCandidateSpectrum';
    audit.exit_reason = audit.failure_id;
    reason = 'The candidate carries no finite stable damping margin for the horizon derivation.';
    return;
end
if ~isfinite(rho) || rho <= 0 || rho >= 1
    audit.failure_id = 'certify_support_transition:badInputs';
    audit.exit_reason = audit.failure_id;
    reason = 'settings.rho must be a finite fraction in (0,1) for the settling formula.';
    return;
end
t_settle = log(1/rho)/(-candidate.omega);
T = t_settle;
if isfield(settings,'sync_dwell') && isfinite(settings.sync_dwell) && ...
        settings.sync_dwell > 0
    T = max(T, settings.sync_dwell);
end
if isfield(candidate,'physical_eigenvalues') && ~isempty(candidate.physical_eigenvalues)
    lam = candidate.physical_eigenvalues(:);
    osc = lam(isfinite(lam) & abs(imag(lam)) > 0);
    if ~isempty(osc)
        [~, q] = max(real(osc));
        period = 2*pi/abs(imag(osc(q)));
        T = ceil(T/period - 1e-12)*period;  % round UP to whole periods
    end
end
audit.horizon = T;

% --- forward trial on private copies ----------------------------------------
active = stability.ts_dynamic_state_indices(dae, ec_right);
X = x_right(:); yy = y_right(:);
X_prev = X;
t_local = 0;
A = X(ga);              % angle history, one column per accepted trial sample
peak_exc = 0; peak_spread = 0;
f0 = 60;
if isfield(settings,'severity_f0_Hz') && isfinite(settings.severity_f0_Hz)
    f0 = settings.severity_f0_Hz;
end
while t_local < T - 1e-12
    h = trial_dt;
    subdiv = 0;
    step_ok = false; step = [];
    while subdiv <= subdiv_max
        sopt = struct('newton_tol', settings.newton_tol, ...
            'max_iter', settings.max_iter, 'fd_eps', settings.fd_eps, ...
            'verbose', false, 'full_kcl', true, ...
            't_now', t + t_local, 'domain_preserving_trials', true, ...
            'state_predictor', 'linear_kcl');
        if t_local > 0
            % Linear extrapolation from the last two accepted trial states,
            % mirroring the production predictor rebuild (the predictor
            % changes only the Newton initial guess, never the residual).
            sopt.x_predictor = X + (h/(t_local))* (X - X_prev);
        end
        try
            cand = stability.ts_step_composite(X, yy, h, dae, Y, ...
                u_right(:), ec_right, active, sopt);
        catch me
            audit.failure_id = 'certify_support_transition:trialNonconvergence';
            audit.exit_reason = audit.failure_id;
            audit.steps_run = size(A,2)-1;
            audit.t_reached = t_local;
            reason = sprintf('Certificate trial threw %s: %s at t+%.4f s.', ...
                me.identifier, me.message, t_local);
            return;
        end
        if cand.converged && cand.finite
            step = cand; step_ok = true; break;
        end
        subdiv = subdiv + 1;
        h = h/2;
    end
    if ~step_ok
        audit.failure_id = 'certify_support_transition:trialNonconvergence';
        audit.exit_reason = audit.failure_id;
        audit.steps_run = size(A,2)-1;
        audit.t_reached = t_local;
        audit.subdivisions = subdiv;
        reason = sprintf(['Certificate trial step did not converge at t+%.4f s ' ...
            'after %d subdivisions.'], t_local, subdiv);
        return;
    end
    if subdiv > 0, audit.subdivisions = audit.subdivisions + subdiv; end
    X_prev = X;
    X = step.x_full; yy = step.y_full;
    t_local = t_local + h;
    A = [A, X(ga)]; %#ok<AGROW>
    audit.steps_run = size(A,2)-1;
    audit.t_reached = t_local;
    % Validated decisive-replay metric (chk_t53_replay_basin_tmp.m:98-99):
    % unwrap each device angle along trial time, subtract the first device's
    % series, max drift of those relative angles.
    U = unwrap(A, [], 2);
    rel = U - U(1,:);
    exc = max(max(abs(rel - rel(:,1))))*180/pi;
    peak_exc = max(peak_exc, exc);
    W = X(go);
    peak_spread = max(peak_spread, (max(W)-min(W))*f0);
    if exc >= slip_limit_deg
        ok = false;
        audit.applied = true;
        audit.peak_excursion_deg = peak_exc;
        audit.peak_speed_spread_Hz = peak_spread;
        audit.failure_id = 'certify_support_transition:lostSynchronism';
        audit.exit_reason = sprintf('excursion %.2f deg at trial t+%.4f s', ...
            exc, t_local);
        reason = sprintf(['Transition certificate refused: relative-angle ' ...
            'excursion reached %.2f deg (limit %.0f deg) at trial time +%.3f s.'], ...
            exc, slip_limit_deg, t_local);
        return;
    end
end

ok = true;
audit.applied = true;
audit.peak_excursion_deg = peak_exc;
audit.peak_speed_spread_Hz = peak_spread;
audit.exit_reason = 'completed';
end
