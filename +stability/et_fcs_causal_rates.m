function out = et_fcs_causal_rates(t, theta_rad, Vmag_pu, opt)
%ET_FCS_CAUSAL_RATES  Causal SI/ROCOF/ROCOV rates over ACCEPTED steps only.
%   OUT = ET_FCS_CAUSAL_RATES(T,THETA_RAD,VMAG_PU,OPT) derives, sample by
%   sample, the instantaneous frequency, RoCoF and RoCoV from a monotonically
%   advancing series of ACCEPTED steps:
%
%       f_k     = f0 + (theta_k - theta_{k-1}) / (2*pi*(t_k - t_{k-1}))
%       rocof_k = (f_k - f_{k-1}) / (t_k - t_{k-1})
%       rocov_k = (Vmag_k - Vmag_{k-1}) / (t_k - t_{k-1})
%
%   CAUSALITY. Every output at index k uses ONLY samples with index <= k. The
%   historical metric used gradient(), whose INTERIOR points are CENTRAL
%   differences spanning k-1..k+1 -- i.e. the reported rate at the decision
%   instant depended on a FUTURE accepted step. This estimator is strictly
%   one-sided (backward) so a decision taken at t_k is a function of the past
%   history alone. A sample is VALID only once the causal stencil it needs
%   exists.
%
%   ACCEPTED-STEP / REJECTED-ROLLBACK CONTRACT. The caller must pass only
%   samples the integrator ACCEPTED. A rejected step leaves the time unchanged,
%   so a rejected rollback shows up here as a NON-ADVANCING time (dt <= dup_tol);
%   such a sample is flagged (n_duplicate_time / n_nonadvancing) and its rate is
%   left NaN+invalid rather than divided by ~0. Duplicate event instants (two
%   accepted samples at the same t) are treated identically.
%
%   WARMUP VALIDITY. Rates are VALID only when (i) the sample has a usable
%   causal stencil, (ii) dt > min_dt, (iii) all inputs finite, and (iv) the
%   elapsed time since the first sample is >= opt.warmup_s. Before warmup the
%   rate is NaN and valid=false -- no early claim is made on a cold filter.
%
%   OPT (defaults in brackets):
%     nominal_hz [60]  nominal frequency f0
%     warmup_s   [0.02] minimum elapsed time before any rate is valid
%     min_dt     [1e-9] smallest usable step (non-advancing below this)
%     dup_tol    [1e-12] time-equality tolerance for duplicate/rollback samples
%
%   Classification PROJECT_DERIVED numerical estimator. It changes no model,
%   tolerance or state contract; it only defines when a rate is trustworthy.

arguments
    t (:,1) double
    theta_rad (:,1) double
    Vmag_pu (:,1) double
    opt struct = struct()
end

f0 = 60.0;
if isfield(opt,'nominal_hz') && ~isempty(opt.nominal_hz), f0 = double(opt.nominal_hz); end
warmup_s = 0.02;
if isfield(opt,'warmup_s') && ~isempty(opt.warmup_s), warmup_s = double(opt.warmup_s); end
min_dt = 1e-9;
if isfield(opt,'min_dt') && ~isempty(opt.min_dt), min_dt = double(opt.min_dt); end
dup_tol = 1e-12;
if isfield(opt,'dup_tol') && ~isempty(opt.dup_tol), dup_tol = double(opt.dup_tol); end

n = numel(t);
if numel(theta_rad) ~= n || numel(Vmag_pu) ~= n
    error('stability:et_fcs_causal_rates:lengthMismatch', ...
        't, theta_rad and Vmag_pu must have the same length.');
end

f_hz = nan(n,1); rocof = nan(n,1); rocov = nan(n,1);
valid = false(n,1);
n_dup = 0; n_nonadv = 0;

if n >= 1
    theta = unwrap(theta_rad(:));
    % First usable causal stencil index is 2 (needs one past sample for rate),
    % and 3 for RoCoF (needs two frequency estimates). We flag validity per
    % sample accordingly.
    for k = 2:n
        dt = t(k) - t(k-1);
        if ~isfinite(dt) || dt <= dup_tol
            n_dup = n_dup + 1;
            continue;                          % duplicate/rollback instant
        end
        if dt < min_dt
            n_nonadv = n_nonadv + 1;
            continue;
        end
        f_hz(k) = f0 + (theta(k) - theta(k-1)) / (2*pi*dt);
        rocov(k) = (Vmag_pu(k) - Vmag_pu(k-1)) / dt;
        if k >= 3 && isfinite(f_hz(k-1))
            rocof(k) = (f_hz(k) - f_hz(k-1)) / dt;
        end
    end
    % A sample is fully VALID only if all three rates are finite AND the warmup
    % window has elapsed. Cold samples (< warmup) are masked to NaN and false so
    % no rate claim -- and no accidental read -- escapes before warmup. The
    % masking is applied AFTER differencing so the first WARM sample still uses
    % the genuine preceding rate estimate (standard filter warmup).
    warmup_ok = (t(:) - t(1)) >= warmup_s;
    cold = ~warmup_ok;
    f_hz(cold) = NaN; rocof(cold) = NaN; rocov(cold) = NaN;
    valid = isfinite(f_hz) & isfinite(rocof) & isfinite(rocov);
end

first_valid = find(valid, 1, 'first');
out = struct();
out.f_hz = f_hz;
out.rocof_hz_s = rocof;
out.rocov_pu_s = rocov;
out.valid = valid;
out.first_valid_index = first_valid;
out.n_samples = n;
out.n_duplicate_time = n_dup;
out.n_nonadvancing = n_nonadv;
out.warmup_s = warmup_s;
out.min_dt = min_dt;
out.dup_tol = dup_tol;
out.nominal_hz = f0;
out.method = 'causal_backward_accepted_steps';
out.classification = 'PROJECT_DERIVED';
out.causal = true;
end
