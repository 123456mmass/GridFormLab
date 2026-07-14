function [z_sol, niter, converged, residual_norm, rcond_val, J_final] = ...
    composite_newton(z0, residual_fn, jacobian_fn, tol, max_iter, verbose)
%COMPOSITE_NEWTON  One damped-Newton owner for composite DAE solves (Phase B).
%   [Z_SOL, NITER, CONVERGED, RESIDUAL_NORM, RCOND, J_FINAL] = composite_newton(
%       Z0, RESIDUAL_FN, JACOBIAN_FN, TOL, MAX_ITER, VERBOSE) solves
%   residual_fn(z) = 0 by damped Newton with a backtracking line search.
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
z = z0(:);
converged = false;
residual_norm = inf;
rcond_val = NaN;
J_final = [];
for niter = 1:max_iter
    r = residual_fn(z);
    residual_norm = norm(r, inf);
    if residual_norm < tol
        converged = true;
        z_sol = z;
        return;
    end
    J = jacobian_fn(z);
    rcond_val = rcond(J);
    if rcond_val < eps
        z_sol = z;
        return;
    end
    dz = -(J \ r);
    if any(~isfinite(dz))
        z_sol = z;
        return;
    end
    alpha = 1.0;
    for ls = 1:20
        z_new = z + alpha * dz;
        r_new = residual_fn(z_new);
        if all(isfinite(r_new)) && norm(r_new, inf) < residual_norm
            break;
        end
        alpha = alpha * 0.5;
    end
    z = z + alpha * dz;
    if verbose
        fprintf('  composite_newton iter %d: residual=%.3e alpha=%.3f rcond=%.3e\n', ...
            niter, residual_norm, alpha, rcond_val);
    end
end
z_sol = z;
J_final = jacobian_fn(z);
residual_norm = norm(residual_fn(z), inf);
end
