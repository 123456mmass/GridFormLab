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

for niter = 1:max_iter
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
            minimum_voltage_violation);
        return;
    end
    J = jacobian_fn(z);
    J_final = J;
    rcond_val = rcond(J);
    if rcond_val < eps
        z_sol = z;
        info = build_info(domain_rejected_trials, line_search_exhausted, ...
            residual_before_line_search, final_tested_alpha, ...
            minimum_trial_voltage, final_domain_violation, ...
            minimum_voltage_violation);
        return;
    end
    dz = -(J \ r);
    if any(~isfinite(dz))
        z_sol = z;
        info = build_info(domain_rejected_trials, line_search_exhausted, ...
            residual_before_line_search, final_tested_alpha, ...
            minimum_trial_voltage, final_domain_violation, ...
            minimum_voltage_violation);
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
            minimum_voltage_violation);
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
    minimum_voltage_violation);
end

% =========================================================================
function info = build_info(domain_rejected_trials, line_search_exhausted, ...
    residual_before_line_search, final_tested_alpha, minimum_trial_voltage, ...
    final_domain_violation, minimum_voltage_violation)
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
    'minimum_voltage_violation', minimum_voltage_violation);
end
