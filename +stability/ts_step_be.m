function step = ts_step_be(strategy, x, y, h, Y, opt)
%TS_STEP_BE  Backward Euler single-step kernel (CORE_ONLY, NOT_ROUTED).
%   STEP = TS_STEP_BE(STRATEGY, X, Y, H, Y_ADM, OPT) performs one backward Euler
%   step of size H on the DAE  x' = f(x,y,Y),  0 = g(x,y,Y).
%
%   Source (VERIFIED, NAODE book Section 4.1 eq 4.9):
%       y_{n+1} = y_n + h * f(t_{n+1}, y_{n+1})
%   i.e. the differential state is updated implicitly:
%       x_{n+1} = x_n + h * f(x_{n+1}, y_{n+1}, u_{n+1})
%   with the algebraic constraint enforced at the endpoint:
%       g(x_{n+1}, y_{n+1}, Y_left) = 0
%   L-stable (NAODE Section 8.4.1: yn -> 0 as Real(lambda) -> -inf).
%   First-order accurate.
%
%   P4 scope (package-only, per plan §2 ownership route):
%   This integrator is a SIBLING of ts_step_kernel; it does NOT modify
%   ts_step_kernel. It is registered in ts_integrator_step / resolve_ts_integrator
%   ONLY after P3.5 (coupled-DAE Jacobian contract) passes. It is tested by
%   direct calls; ts_simulate.m / ts_adaptive_driver.m are NOT modified.
%   CORE_ONLY / NOT_ROUTED. Production routing readiness NOT_READY until the
%   single-owner integration files are separately resolved.
%
%   FIXED-STEP ONLY in P4 (per user correction 6): the method-specific algebraic
%   adaptive-error definition for BE is NOT frozen yet. Requesting
%   stepper='adaptive' with integrator='backward_euler' must fail closed
%   (adaptiveNotFrozen). This file implements the fixed-step endpoint residual
%   solve only.
%
%   Residual solved at the endpoint (coupled Newton via ts_coupled_jacobian):
%       R_x = x_{n+1} - x_n - h * f(x_{n+1}, y_{n+1})
%       R_g = g(x_{n+1}, y_{n+1}, Y)
%   Jacobian: J = [I-h*dfdx, -h*dfdy; dgdx, dgdy] from ts_coupled_jacobian.
%   Newton: [dx; dy] = J \ [R_x; R_g], damped line search, rcond >= 1e-13.
%
%   For the classical (linear-network) model (needs_algebraic_solve=false):
%   the algebraic state y is solved inside dae_f (V = Y\Iinj), so the residual
%   is in x alone: R_x = x_{n+1} - x_n - h * f(x_{n+1}, y(x_{n+1}), Y). Newton
%   on x with df/dx via FD (no coupled Jacobian needed). This mirrors the
%   classical_step split in ts_step_kernel.m.
%
%   Provider (R1): evaluated at the endpoint t+h (single stage, c=1). Same as
%   trapezoidal's u1. When strategy.provider is absent, legacy dae_f/dae_g are
%   called with NO u argument (FP-identical to a provider-free BE step).
%
%   Step struct returned (matches ts_step_kernel's contract):
%     x_full, y_full, f0, f1, corrector_iterations, corrector_residual,
%     corrector_update, corrector_converged, algebraic_residual, finite.

if nargin < 6, opt = struct(); end
g_tol = get_field(opt, 'algebraic_tolerance', 1e-8);
newton_tol = get_field(opt, 'be_newton_tol', 1e-10);
max_iter = get_field(opt, 'be_max_iter', 30);
rcond_min = 1e-13;

has_provider = isfield(strategy, 'provider') && ~isempty(strategy.provider);

if strategy.needs_algebraic_solve
    if has_provider
        step = be_coupled_provider(strategy, x, y, h, Y, opt, g_tol, newton_tol, max_iter, rcond_min);
    else
        step = be_coupled(strategy, x, y, h, Y, opt, g_tol, newton_tol, max_iter, rcond_min);
    end
else
    if has_provider
        step = be_classical_provider(strategy, x, y, h, Y, opt, g_tol, newton_tol, max_iter, rcond_min);
    else
        step = be_classical(strategy, x, y, h, Y, opt, g_tol, newton_tol, max_iter, rcond_min);
    end
end
end

% =========================================================================
function step = be_coupled(strategy, x, y, h, Y, ~, g_tol, newton_tol, max_iter, rcond_min)
% Coupled Newton on (x_{n+1}, y_{n+1}) for the backward Euler residual.
dae_f = strategy.dae_f;
dae_g = strategy.dae_g;
x = x(:); y = y(:);
x0 = x; y0 = y;

% Initial guess: explicit Euler predictor x + h*f(x,y), y unchanged.
f0 = dae_f(x, y);
x_new = x + h*f0;
y_new = y;

converged = false; resn = Inf; upd = Inf; ci = 0;
for ci = 1:max_iter
    R_x = x_new - x0 - h*dae_f(x_new, y_new);
    R_g = dae_g(x_new, y_new, Y);
    R = [R_x(:); R_g(:)];
    resn = norm(R, inf);
    if resn <= newton_tol && norm(R_g, inf) <= g_tol
        converged = true; break;
    end
    % Coupled Jacobian via the P3.5 contract.
    Jfull = stability.ts_coupled_jacobian(x_new, y_new, dae_f, dae_g, Y, struct(), struct());
    % Apply the BE structure: J_solve = [I-h*dfdx, -h*dfdy; dgdx, dgdy].
    % ts_coupled_jacobian returns [dfdx, dfdy; dgdx, dgdy]; scale the top blocks.
    nx = numel(x_new); ny = numel(y_new);
    J_solve = Jfull;
    J_solve(1:nx, 1:nx) = eye(nx) - h*Jfull(1:nx, 1:nx);
    J_solve(1:nx, nx+(1:ny)) = -h*Jfull(1:nx, nx+(1:ny));
    if rcond(J_solve) < rcond_min
        error('ts_step_be:singularJacobian', ...
            'Backward Euler coupled Jacobian singular (rcond=%.3e < %.3e) at ci=%d.', ...
            rcond(J_solve), rcond_min, ci);
    end
    delta = -(J_solve \ R);
    % Damped line search.
    alpha = 1; accepted = false;
    while alpha >= 2^-16
        xt = x_new + alpha*delta(1:nx);
        yt = y_new + alpha*delta(nx+(1:ny));
        fx = dae_f(xt, yt); gx = dae_g(xt, yt, Y);
        rx = xt - x0 - h*fx;
        Rt = [ rx(:) ; gx(:) ];
        if all(isfinite(Rt)) && norm(Rt, inf) < resn
            x_new = xt; y_new = yt; accepted = true; break;
        end
        alpha = alpha/2;
    end
    if ~accepted
        error('ts_step_be:lineSearchFailed', ...
            'Backward Euler line search exhausted at ci=%d, resn=%.3e.', ci, resn);
    end
    upd = norm(delta, inf);
end

f1 = dae_f(x_new, y_new);
alg_res = norm(dae_g(x_new, y_new, Y), inf);
all_finite = all(isfinite(x_new)) && all(isfinite(y_new)) && all(isfinite(f1)) && all(isfinite(resn));
step = struct( ...
    'x_full', x_new, 'y_full', y_new, ...
    'f0', f0, 'f1', f1, ...
    'corrector_iterations', ci, ...
    'corrector_residual', resn, ...
    'corrector_update', upd, ...
    'corrector_converged', converged, ...
    'algebraic_residual', alg_res, ...
    'finite', all_finite);
end

% =========================================================================
function step = be_classical(strategy, x, y, h, Y, ~, g_tol, newton_tol, max_iter, rcond_min)
% Classical (linear-network) model: y solved inside dae_f. Newton on x alone.
dae_f = strategy.dae_f;   % @(x,y,Y)
x = x(:); y = y(:);
x0 = x;

f0 = dae_f(x, y, Y);
x_new = x + h*f0;
y_new = y;

converged = false; resn = Inf; upd = Inf; ci = 0;
for ci = 1:max_iter
    % Residual in x: R = x_new - x0 - h*f(x_new, y_new, Y). y_new is consistent
    % via the linear network solved inside dae_f at x_new.
    f_at = dae_f(x_new, y_new, Y);
    R = x_new - x0 - h*f_at;
    resn = norm(R, inf);
    if resn <= newton_tol
        converged = true; break;
    end
    % df/dx via central FD (the network is linear in y given x, so df/dy is
    % implicit; we only need df/dx for the x-Newton). Use the derived
    % eps^(1/3) rule from the P3.5 contract (NOT copied from ts_jac_y_fd).
    nx = numel(x_new);
    Jxx = zeros(nx, nx, 'like', x_new);
    hrule = 6e-6;
    for j = 1:nx
        hj = hrule*(1 + abs(x_new(j)));
        if hj == 0, hj = hrule; end
        xp = x_new; xm = x_new;
        xp(j) = xp(j) + hj;
        xm(j) = xm(j) - hj;
        Jxx(:,j) = (dae_f(xp, y_new, Y) - dae_f(xm, y_new, Y)) / (2*hj);
    end
    J_solve = eye(nx) - h*Jxx;
    if rcond(J_solve) < rcond_min
        error('ts_step_be:singularJacobian', ...
            'Backward Euler classical Jacobian singular (rcond=%.3e) at ci=%d.', ...
            rcond(J_solve), ci);
    end
    delta = -(J_solve \ R);
    alpha = 1; accepted = false;
    while alpha >= 2^-16
        xt = x_new + alpha*delta;
        Rt = xt - x0 - h*dae_f(xt, y_new, Y);
        if all(isfinite(Rt)) && norm(Rt, inf) < resn
            x_new = xt; accepted = true; break;
        end
        alpha = alpha/2;
    end
    if ~accepted
        error('ts_step_be:lineSearchFailed', ...
            'Backward Euler classical line search exhausted at ci=%d.', ci);
    end
    upd = norm(delta, inf);
end

% Re-solve y at the accepted x_new for consistency (network solved in dae_f).
f1 = dae_f(x_new, y_new, Y);
alg_res = 0;  % classical: network solved exactly inside dae_f
all_finite = all(isfinite(x_new)) && all(isfinite(y_new)) && all(isfinite(f1)) && all(isfinite(resn));
step = struct( ...
    'x_full', x_new, 'y_full', y_new, ...
    'f0', f0, 'f1', f1, ...
    'corrector_iterations', ci, ...
    'corrector_residual', resn, ...
    'corrector_update', upd, ...
    'corrector_converged', converged, ...
    'algebraic_residual', alg_res, ...
    'finite', all_finite);
end

% =========================================================================
function step = be_coupled_provider(strategy, x, y, h, Y, opt, g_tol, newton_tol, max_iter, rcond_min)
% Provider-aware coupled BE (R1). Provider evaluated at t+h (single stage c=1).
provider = strategy.provider;
t0 = 0; if isfield(opt,'t') && ~isempty(opt.t), t0 = opt.t; end
event_context = []; if isfield(opt,'event_context') && ~isempty(opt.event_context)
    event_context = opt.event_context; end
u1 = stability.eval_input_provider(provider, t0 + h, event_context);
dae_f_u = strategy.dae_f_u;
dae_g_u = strategy.dae_g_u;
x = x(:); y = y(:);
x0 = x; y0 = y;

f0 = dae_f_u(x, y, u1);
x_new = x + h*f0;
y_new = y;

converged = false; resn = Inf; upd = Inf; ci = 0;
for ci = 1:max_iter
    R_x = x_new - x0 - h*dae_f_u(x_new, y_new, u1);
    R_g = dae_g_u(x_new, y_new, Y, u1);
    R = [R_x(:); R_g(:)];
    resn = norm(R, inf);
    if resn <= newton_tol && norm(R_g, inf) <= g_tol
        converged = true; break;
    end
    Jfull = stability.ts_coupled_jacobian(x_new, y_new, ...
        @(xx,yy) dae_f_u(xx,yy,u1), @(xx,yy,YY) dae_g_u(xx,yy,YY,u1), Y, struct(), struct());
    nx = numel(x_new); ny = numel(y_new);
    J_solve = Jfull;
    J_solve(1:nx, 1:nx) = eye(nx) - h*Jfull(1:nx, 1:nx);
    J_solve(1:nx, nx+(1:ny)) = -h*Jfull(1:nx, nx+(1:ny));
    if rcond(J_solve) < rcond_min
        error('ts_step_be:singularJacobian', ...
            'BE provider Jacobian singular (rcond=%.3e) at ci=%d.', rcond(J_solve), ci);
    end
    delta = -(J_solve \ R);
    alpha = 1; accepted = false;
    while alpha >= 2^-16
        xt = x_new + alpha*delta(1:nx);
        yt = y_new + alpha*delta(nx+(1:ny));
        fx = dae_f_u(xt, yt, u1); gx = dae_g_u(xt, yt, Y, u1);
        rx = xt - x0 - h*fx;
        Rt = [ rx(:) ; gx(:) ];
        if all(isfinite(Rt)) && norm(Rt, inf) < resn
            x_new = xt; y_new = yt; accepted = true; break;
        end
        alpha = alpha/2;
    end
    if ~accepted
        error('ts_step_be:lineSearchFailed', ...
            'BE provider line search exhausted at ci=%d.', ci);
    end
    upd = norm(delta, inf);
end
f1 = dae_f_u(x_new, y_new, u1);
alg_res = norm(dae_g_u(x_new, y_new, Y, u1), inf);
all_finite = all(isfinite(x_new)) && all(isfinite(y_new)) && all(isfinite(f1)) && all(isfinite(resn));
step = struct( ...
    'x_full', x_new, 'y_full', y_new, ...
    'f0', f0, 'f1', f1, ...
    'corrector_iterations', ci, ...
    'corrector_residual', resn, ...
    'corrector_update', upd, ...
    'corrector_converged', converged, ...
    'algebraic_residual', alg_res, ...
    'finite', all_finite);
end

% =========================================================================
function step = be_classical_provider(strategy, x, y, h, Y, opt, g_tol, newton_tol, max_iter, rcond_min)
provider = strategy.provider;
t0 = 0; if isfield(opt,'t') && ~isempty(opt.t), t0 = opt.t; end
event_context = []; if isfield(opt,'event_context') && ~isempty(opt.event_context)
    event_context = opt.event_context; end
u1 = stability.eval_input_provider(provider, t0 + h, event_context);
dae_f_u = strategy.dae_f_u;
x = x(:); y = y(:); x0 = x;

f0 = dae_f_u(x, y, Y, u1);
x_new = x + h*f0; y_new = y;
converged = false; resn = Inf; upd = Inf; ci = 0;
for ci = 1:max_iter
    f_at = dae_f_u(x_new, y_new, Y, u1);
    R = x_new - x0 - h*f_at;
    resn = norm(R, inf);
    if resn <= newton_tol, converged = true; break; end
    nx = numel(x_new); hrule = 6e-6;
    Jxx = zeros(nx, nx, 'like', x_new);
    for j = 1:nx
        hj = hrule*(1 + abs(x_new(j)));
        if hj == 0, hj = hrule; end
        xp = x_new; xm = x_new; xp(j) = xp(j) + hj; xm(j) = xm(j) - hj;
        Jxx(:,j) = (dae_f_u(xp, y_new, Y, u1) - dae_f_u(xm, y_new, Y, u1)) / (2*hj);
    end
    J_solve = eye(nx) - h*Jxx;
    if rcond(J_solve) < rcond_min
        error('ts_step_be:singularJacobian', ...
            'BE classical provider Jacobian singular (rcond=%.3e) at ci=%d.', rcond(J_solve), ci);
    end
    delta = -(J_solve \ R);
    alpha = 1; accepted = false;
    while alpha >= 2^-16
        xt = x_new + alpha*delta;
        Rt = xt - x0 - h*dae_f_u(xt, y_new, Y, u1);
        if all(isfinite(Rt)) && norm(Rt, inf) < resn
            x_new = xt; accepted = true; break;
        end
        alpha = alpha/2;
    end
    if ~accepted
        error('ts_step_be:lineSearchFailed', ...
            'BE classical provider line search exhausted at ci=%d.', ci);
    end
    upd = norm(delta, inf);
end
f1 = dae_f_u(x_new, y_new, Y, u1);
alg_res = 0;
all_finite = all(isfinite(x_new)) && all(isfinite(y_new)) && all(isfinite(f1)) && all(isfinite(resn));
step = struct( ...
    'x_full', x_new, 'y_full', y_new, ...
    'f0', f0, 'f1', f1, ...
    'corrector_iterations', ci, ...
    'corrector_residual', resn, ...
    'corrector_update', upd, ...
    'corrector_converged', converged, ...
    'algebraic_residual', alg_res, ...
    'finite', all_finite);
end

% =========================================================================
function v = get_field(opt, name, default)
if isfield(opt, name) && ~isempty(opt.(name)), v = opt.(name); else, v = default; end
end
