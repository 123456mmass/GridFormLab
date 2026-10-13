function [z_sol, niter, converged, residual_norm, rcond_val, J_final, info] = ...
    composite_newton(z0, residual_fn, jacobian_fn, tol, max_iter, verbose, opt)
%COMPOSITE_NEWTON  One damped-Newton owner for composite DAE solves (Phase B).
%   [Z_SOL, NITER, CONVERGED, RESIDUAL_NORM, RCOND, J_FINAL] = composite_newton(
%       Z0, RESIDUAL_FN, JACOBIAN_FN, TOL, MAX_ITER, VERBOSE) solves
%       residual_fn(z) = 0 by damped Newton with a backtracking line search.
%
%   [Z_SOL, NITER, CONVERGED, RESIDUAL_NORM, RCOND, J_FINAL, INFO] = composite_newton(
%       Z0, RESIDUAL_FN, JACOBIAN_FN, TOL, MAX_ITER, VERBOSE, OPT) accepts an
%       optional OPT struct. When OPT is omitted or lacks a
%       trial_exception_classifier, behavior is exactly the six-output form:
%       the first six outputs and the exception behavior are unchanged.
%
%   Domain-preserving line search (opt-in):
%     When OPT.trial_exception_classifier is a function handle, the line-search
%     trial evaluation residual_fn(z_new) is wrapped so that a CLASSIFIED
%     device-domain exception is treated as a REJECTED trial (alpha is halved
%     via the existing backtracking) instead of aborting the solve. Only the
%     exact confirmed domain-violation identifier is accepted; every other
%     exception is rethrown immediately. The accepted-point residual, the
%     Jacobian/FD evaluations, and the final residual/Jacobian reporting
%     remain uncaught. Rejected-trial state/residual is never consumed.
%
%   OPT fields (all optional):
%     trial_exception_classifier  @(me) logical; exact-ID domain predicate
%     trial_exception_diagnostic  @(z_trial, me) struct; pure read-only
%                                  attribution (no DAE/device callbacks)
%     jacobian_reuse              logical; opt-in within-step chord reuse
%                                  (absent = false = legacy byte-identical
%                                  loop). A reused Jacobian only supplies the
%                                  chord direction; the true residual, the
%                                  convergence test, the rcond/finite gates
%                                  and the line search are unchanged.
%     jacobian_reuse_ratio        scalar in (0,1), default 0.5; a reused
%                                  Jacobian stays valid only while the
%                                  previous accepted step took alpha==1.0 and
%                                  reduced the true residual to at most
%                                  ratio * ||r||. Any backtracked step, a
%                                  slower reduction, or a rejected chord
%                                  forces a fresh Jacobian at the current
%                                  iterate (info.jacobian_rebuilds).
%
%   INFO (additive, bounded; always returned, also under nargout<7):
%     domain_rejected_trials      nonnegative integer count
%     line_search_exhausted       logical (terminal iteration exhausted alpha)
%     residual_before_line_search scalar or NaN (residual at the current
%                                  iterate when the terminal line search began)
%     final_tested_alpha          scalar or NaN (last alpha tested in the
%                                  terminal line search; 20 rejections => 2^-19)
%     minimum_trial_voltage       scalar or NaN (min terminal |V| across
%                                  classified rejected trials, from diagnostic)
%     final_domain_violation      scalar struct or struct([]) (diagnostic of
%                                  the last classified rejection)
%     minimum_voltage_violation   scalar struct or struct([]) (diagnostic with
%                                  the lowest minimum_trial_voltage)
%     jacobian_evaluations        nonnegative integer count (fresh
%                                  jacobian_fn builds inside the loop)
%     jacobian_reused             nonnegative integer count (chord steps on
%                                  the held Jacobian; 0 when reuse is off)
%     jacobian_rebuilds           nonnegative integer count (forced fresh
%                                  builds under the reuse policy)
%
%   This is the SINGLE Newton owner reused by:
%     - mixed_equilibrium_solve (equilibrium residual [f; g_free] = 0)
%     - ts_simulate_composite trapezoidal step (correction 7:
%       [x1 - x0 - h/2*(f0+f1); g_free] = 0)
%     - the single right-limit event solve (correction 4: g_free(x_reset,y)=0)
%
%   The caller supplies residual_fn(z) -> r (length == numel(z)) and
%   jacobian_fn(z) -> J (square). Both equilibrium (f=0) and trapezoidal
%   (x1-x0-h/2(f0+f1)=0) residuals are handled because the owner is agnostic
%   to the residual's structure — it just drives ||r||_inf < tol.
%
%   Reuses the validated damped-Newton pattern from mixed_equilibrium_solve/
%   inhouse_newton (backtracking line search, alpha halved up to 20 times,
%   rcond gate). No external solver. Base MATLAB backslash only.
%
%   Source: PROJECT_DERIVED numerical method (damped Newton). The pattern is
%   audited in mixed_equilibrium_solve (Phase 4) and reused verbatim here.

if nargin < 6, verbose = false; end
if nargin < 7, opt = struct(); end
classifier = [];
diagnostic_fn = [];
if isfield(opt,'trial_exception_classifier') && ...
        isa(opt.trial_exception_classifier,'function_handle')
    classifier = opt.trial_exception_classifier;
end
if isfield(opt,'trial_exception_diagnostic') && ...
        isa(opt.trial_exception_diagnostic,'function_handle')
    diagnostic_fn = opt.trial_exception_diagnostic;
end

z = z0(:);
converged = false;
residual_norm = inf;
rcond_val = NaN;
J_final = [];

% Additive diagnostics (always initialized so every return path is stable).
domain_rejected_trials = 0;
line_search_exhausted = false;
residual_before_line_search = NaN;
final_tested_alpha = NaN;
minimum_trial_voltage = NaN;
final_domain_violation = struct([]);
minimum_voltage_violation = struct([]);
jacobian_evaluations = 0;
jacobian_reused = 0;
jacobian_rebuilds = 0;
last_full_step = false;
last_good_reduction = false;

% Within-step Jacobian reuse (opt-in, default off). A reused Jacobian only supplies
% the chord direction; the true residual, the convergence test, the rcond/finite
% gates and the line search are unchanged. A poor reduction, a backtracked step or
% a rejected chord forces a fresh Jacobian at the current iterate.
reuse_on = false; reuse_ratio = 0.5;
if isfield(opt,'jacobian_reuse')
    if ~islogical(opt.jacobian_reuse) || ~isscalar(opt.jacobian_reuse)
        error('stability:composite_newton:badJacobianReuse', ...
            'jacobian_reuse must be a logical scalar.');
    end
    reuse_on = opt.jacobian_reuse;
end
if isfield(opt,'jacobian_reuse_ratio')
    rr = opt.jacobian_reuse_ratio;
    if ~isnumeric(rr) || ~isscalar(rr) || ~isfinite(rr) || rr <= 0 || rr >= 1
        error('stability:composite_newton:badJacobianReuseRatio', ...
            'jacobian_reuse_ratio must be a finite scalar in (0,1).');
    end
    reuse_ratio = double(rr);
end
J_have = false; force_fresh = true;
for niter = 1:max_iter
    if niter > 1
        % Reuse policy: the previous iterate must have accepted an alpha==1
        % step that at least halved the residual. Any backtracking, a smaller
        % reduction, or a prior evaluation at a NEW point (the convergence-test
        % Jacobian) invalidates the reuse and forces a fresh build.
        force_fresh = ~last_full_step || ~last_good_reduction;
    end
    r = residual_fn(z);
    residual_norm = norm(r, inf);
    if residual_norm < tol
        J_final = jacobian_fn(z);
        rcond_val = rcond(J_final);
        converged = true;
        z_sol = z;
        info = build_info(domain_rejected_trials, line_search_exhausted, ...
            residual_before_line_search, final_tested_alpha, ...
            minimum_trial_voltage, final_domain_violation, ...
            minimum_voltage_violation, jacobian_evaluations, ...
            jacobian_reused, jacobian_rebuilds);
        return;
    end
    if reuse_on && J_have && ~force_fresh
        % Chord step on the Jacobian built at the previous iterate. The true
        % residual, the convergence test and every gate below are unchanged.
        jacobian_reused = jacobian_reused + 1;
    else
        if reuse_on && J_have
            % The reuse policy itself forced this fresh build: the previous
            % iterate backtracked or reduced the residual too slowly, so the
            % held Jacobian is stale and must be rebuilt at the current one.
            jacobian_rebuilds = jacobian_rebuilds + 1;
        end
        J = jacobian_fn(z);
        J_final = J;
        J_have = true;
        force_fresh = false;
        jacobian_evaluations = jacobian_evaluations + 1;
    end
    rcond_val = rcond(J);
    if rcond_val < eps
        z_sol = z;
        info = build_info(domain_rejected_trials, line_search_exhausted, ...
            residual_before_line_search, final_tested_alpha, ...
            minimum_trial_voltage, final_domain_violation, ...
            minimum_voltage_violation, jacobian_evaluations, ...
            jacobian_reused, jacobian_rebuilds);
        return;
    end
    dz = -(J \ r);
    if any(~isfinite(dz))
        z_sol = z;
        info = build_info(domain_rejected_trials, line_search_exhausted, ...
            residual_before_line_search, final_tested_alpha, ...
            minimum_trial_voltage, final_domain_violation, ...
            minimum_voltage_violation, jacobian_evaluations, ...
            jacobian_reused, jacobian_rebuilds);
        return;
    end
    alpha = 1.0;
    accepted = false;
    residual_before_line_search = residual_norm;
    for ls = 1:20
        z_new = z + alpha * dz;
        if isempty(classifier)
            % Default path: exact legacy behavior (exceptions propagate).
            r_new = residual_fn(z_new);
        else
            % Domain-preserving path: a classified domain violation during a
            % line-search trial is a rejected trial, not an abort. The
            % accepted iterate z, the current residual r, residual_norm,
            % and J_final are never assigned from a rejected trial.
            try
                r_new = residual_fn(z_new);
            catch me
                if classifier(me)
                    domain_rejected_trials = domain_rejected_trials + 1;
                    final_tested_alpha = alpha;
                    diag = struct([]);
                    trial_min_v = NaN;
                    if ~isempty(diagnostic_fn)
                        try
                            diag = diagnostic_fn(z_new, me);
                            if isstruct(diag) && isfield(diag,'minimum_trial_voltage') ...
                                    && isscalar(diag.minimum_trial_voltage) && ...
                                    isfinite(diag.minimum_trial_voltage)
                                trial_min_v = diag.minimum_trial_voltage;
                            end
                        catch %#ok<CTCH>
                            % A diagnostic callback failure must never mask
                            % the original device exception. Rethrow so the
                            % root failure stays visible.
                            rethrow(me);
                        end
                    end
                    if isfinite(trial_min_v)
                        if ~isfinite(minimum_trial_voltage) || ...
                                trial_min_v < minimum_trial_voltage
                            minimum_trial_voltage = trial_min_v;
                            minimum_voltage_violation = diag;
                        end
                    end
                    final_domain_violation = diag;
                    alpha = alpha * 0.5;
                    continue;
                else
                    rethrow(me);
                end
            end
        end
        final_tested_alpha = alpha;
        if all(isfinite(r_new)) && norm(r_new, inf) < residual_norm
            accepted = true;
            % The reused-Jacobian policy looks at HOW the step was accepted:
            % an undamped full step that at least halved the residual keeps a
            % chord step viable at the next iterate; anything else is stale.
            last_full_step = (alpha == 1.0);
            last_good_reduction = norm(r_new, inf) <= reuse_ratio * residual_norm;
            break;
        end
        alpha = alpha * 0.5;
    end
    if ~accepted
        % Fail closed at the last accepted point.  The alpha value after
        % the final rejection has never satisfied the decrease contract
        % and therefore must not be applied.
        line_search_exhausted = true;
        z_sol = z;
        info = build_info(domain_rejected_trials, line_search_exhausted, ...
            residual_before_line_search, final_tested_alpha, ...
            minimum_trial_voltage, final_domain_violation, ...
            minimum_voltage_violation, jacobian_evaluations, ...
            jacobian_reused, jacobian_rebuilds);
        return;
    end
    z = z_new;
    if verbose
        fprintf('  composite_newton iter %d: residual=%.3e alpha=%.3f rcond=%.3e\n', ...
            niter, residual_norm, alpha, rcond_val);
    end
end
z_sol = z;
J_final = jacobian_fn(z);
rcond_val = rcond(J_final);
residual_norm = norm(residual_fn(z), inf);
info = build_info(domain_rejected_trials, line_search_exhausted, ...
    residual_before_line_search, final_tested_alpha, ...
    minimum_trial_voltage, final_domain_violation, ...
    minimum_voltage_violation, jacobian_evaluations, ...
    jacobian_reused, jacobian_rebuilds);
end

% =========================================================================
function info = build_info(domain_rejected_trials, line_search_exhausted, ...
    residual_before_line_search, final_tested_alpha, minimum_trial_voltage, ...
    final_domain_violation, minimum_voltage_violation, ...
    jacobian_evaluations, jacobian_reused, jacobian_rebuilds)
%BUILD_INFO  Assemble the additive Newton diagnostics struct.
%   Every field is initialized before the iteration loop so all return paths
%   (convergence, rcond gate, non-finite step, line-search exhaustion,
%   max-iter exhaustion) publish a stable shape.
info = struct( ...
    'domain_rejected_trials', domain_rejected_trials, ...
    'line_search_exhausted', logical(line_search_exhausted), ...
    'residual_before_line_search', residual_before_line_search, ...
    'final_tested_alpha', final_tested_alpha, ...
    'minimum_trial_voltage', minimum_trial_voltage, ...
    'final_domain_violation', final_domain_violation, ...
    'minimum_voltage_violation', minimum_voltage_violation, ...
    'jacobian_evaluations', jacobian_evaluations, ...
    'jacobian_reused', jacobian_reused, ...
    'jacobian_rebuilds', jacobian_rebuilds);
end
