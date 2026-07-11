function [y, info, Jyy] = ts_algebraic_solve(x, y, Y, dae_g, jac_y_fn, tol, Jyy)
%TS_ALGEBRAIC solve Shared damped-Newton algebraic solver for g(x,y,Y)=0.
%   [Y, INFO] = ts_algebraic_solve(X, Y0, Y_ADM, DAEG, JAC_Y_FN, TOL) solves
%   g(x,y,Y)=0 by damped Newton with a backtracking line search.
%   [Y, INFO] = ts_algebraic_solve(..., JYY) reuses the precomputed Jacobian
%   JYY (re-evaluating only on line-search failure), matching the validated
%   fixed-step behavior where dg/dy is computed once per step start.
%
%   INFO: iterations, final_residual, converged, line_search_failures.

if nargin < 7 || isempty(Jyy)
    Jyy = jac_y_fn(x, y, Y, dae_g);
end
g0 = dae_g(x, y, Y);
y = y(:);
info = struct('iterations',0,'final_residual',norm(g0,inf), ...
    'converged',norm(g0,inf)<=tol,'line_search_failures',0);

for k = 1:30
    g = dae_g(x, y, Y);
    nr = norm(g, inf);
    info.iterations = k;
    info.final_residual = nr;
    if nr <= tol
        info.converged = true; return;
    end
    step = -(Jyy \ g);
    if any(~isfinite(step))
        info.converged = false; return;
    end
    alpha = 1; accepted = false;
    while alpha >= 2^-16
        yt = y + alpha*step;
        gt = dae_g(x, yt, Y);
        if all(isfinite(gt)) && norm(gt,inf) < nr
            y = yt; accepted = true; break;
        end
        alpha = alpha/2;
    end
    if ~accepted
        info.line_search_failures = info.line_search_failures + 1;
        Jyy = jac_y_fn(x, y, Y, dae_g);
        step = -(Jyy \ g);
        if all(isfinite(step))
            yt = y + step;
            gt = dae_g(x, yt, Y);
            if all(isfinite(gt)) && norm(gt,inf) < nr
                y = yt; accepted = true;
            end
        end
        if ~accepted
            info.converged = false; return;
        end
    end
end
info.final_residual = norm(dae_g(x, y, Y), inf);
info.converged = info.final_residual <= tol;
if ~info.converged && info.final_residual > 100*tol
    error('ts_algebraic_solve:failed', ...
        'Algebraic solve failed: residual=%.3e (tol=%.3e).', ...
        info.final_residual, tol);
end
end
