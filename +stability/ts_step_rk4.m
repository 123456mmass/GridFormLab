function step = ts_step_rk4(strategy, x, y, h, Y, opt)
%TS_STEP_RK4  Classical 4-stage RK4 single-step kernel (CORE_ONLY, NOT_ROUTED, DIAGNOSTIC).
%   STEP = TS_STEP_RK4(STRATEGY, X, Y, H, Y_ADM, OPT) performs one classical RK4
%   step of size H on the DAE  x' = f(x,y,Y),  0 = g(x,y,Y).
%
%   Source (VERIFIED, Sulí & Mayers, An Introduction to Numerical Analysis,
%   2003, p.352, Butcher tableau via Wikipedia):
%       c = [0; 1/2; 1/2; 1]
%       A = [ 0   0   0   0 ;
%             1/2 0   0   0 ;
%             0   1/2 0   0 ;
%             0   0   1   0 ]
%       b = [1/6; 1/3; 1/3; 1/6]
%   Stage equations (semi-explicit DAE form):
%       Stage 1: X1 = x_n          ; solve g(X1,Y1,Y)=0 ; K1 = f(X1,Y1)
%       Stage 2: X2 = x_n + h/2*K1 ; solve g(X2,Y2,Y)=0 ; K2 = f(X2,Y2)
%       Stage 3: X3 = x_n + h/2*K2 ; solve g(X3,Y3,Y)=0 ; K3 = f(X3,Y3)
%       Stage 4: X4 = x_n + h*K3   ; solve g(X4,Y4,Y)=0 ; K4 = f(X4,Y4)
%       Final:   x_{n+1} = x_n + h/6*(K1 + 2*K2 + 2*K3 + K4)
%                re-solve g(x_{n+1}, y_{n+1}, Y) = 0
%
%   P5 scope (package-only, per plan §2 ownership route):
%   This integrator is a SIBLING of ts_step_kernel; it does NOT modify
%   ts_step_kernel. Registered in ts_integrator_step / resolve_ts_integrator
%   ONLY after P3.5 passes. capability = 'diagnostic' (RK4 has a BOUNDED
%   stability region, NOT A-stable; it is NOT a production replacement for
%   trapezoidal on stiff DAEs). Tested by direct calls; ts_simulate.m /
%   ts_adaptive_driver.m are NOT modified. CORE_ONLY / NOT_ROUTED.
%
%   FIXED-STEP ONLY in P5 (per user correction 6): the method-specific
%   algebraic adaptive-error definition for RK4 is NOT frozen yet. Requesting
%   stepper='adaptive' with integrator='rk4' must fail closed (adaptiveNotFrozen).
%
%   For the classical (linear-network) model (needs_algebraic_solve=false):
%   the algebraic state y is solved inside dae_f (V = Y\Iinj), so each stage's
%   algebraic solve is implicit in the dae_f call (the network is re-solved at
%   each stage's X_i). No separate ts_algebraic_solve needed. This mirrors the
%   classical_step split in ts_step_kernel.m.
%
%   Provider (R1): evaluated at the 4 stage times t, t+h/2, t+h/2, t+h.
%   When strategy.provider is absent, legacy dae_f/dae_g are called with NO u.
%
%   Step struct returned (matches ts_step_kernel's contract):
%     x_full, y_full, f0, f1, corrector_iterations, corrector_residual,
%     corrector_update, corrector_converged, algebraic_residual, finite.
%   (For RK4, corrector_iterations = 4 (stages), corrector_residual = LTE-free
%    placeholder = norm of final re-solve residual, corrector_converged = true
%    if all stage algebraic solves converged.)

if nargin < 6, opt = struct(); end
g_tol = get_field(opt, 'algebraic_tolerance', 1e-8);

has_provider = isfield(strategy, 'provider') && ~isempty(strategy.provider);

if strategy.needs_algebraic_solve
    if has_provider
        step = rk4_coupled_provider(strategy, x, y, h, Y, opt, g_tol);
    else
        step = rk4_coupled(strategy, x, y, h, Y, opt, g_tol);
    end
else
    if has_provider
        step = rk4_classical_provider(strategy, x, y, h, Y, opt, g_tol);
    else
        step = rk4_classical(strategy, x, y, h, Y, opt, g_tol);
    end
end
end

% =========================================================================
function step = rk4_classical(strategy, x, y, h, Y, ~, g_tol)
% Classical (linear-network) model: network solved inside dae_f at each X_i.
dae_f = strategy.dae_f;   % @(x,y,Y)
x = x(:); y = y(:);

f0 = dae_f(x, y, Y);
K1 = f0;
X2 = x + h/2*K1;
K2 = dae_f(X2, y, Y);
X3 = x + h/2*K2;
K3 = dae_f(X3, y, Y);
X4 = x + h*K3;
K4 = dae_f(X4, y, Y);

x_new = x + h/6*(K1 + 2*K2 + 2*K3 + K4);
% Final algebraic re-solve (network solved inside dae_f at x_new).
f1 = dae_f(x_new, y, Y);
alg_res = 0;  % classical: network solved exactly inside dae_f
all_finite = all(isfinite(x_new)) && all(isfinite(f1));
step = struct( ...
    'x_full', x_new, 'y_full', y, ...
    'f0', f0, 'f1', f1, ...
    'corrector_iterations', 4, ...
    'corrector_residual', 0, ...
    'corrector_update', norm(x_new - x, inf), ...
    'corrector_converged', all_finite, ...
    'algebraic_residual', alg_res, ...
    'finite', all_finite);
end

% =========================================================================
function step = rk4_coupled(strategy, x, y, h, Y, ~, g_tol)
% Coupled DAE: each stage solves the algebraic network via ts_algebraic_solve.
dae_f = strategy.dae_f;
dae_g = strategy.dae_g;
jac_y = strategy.jac_y;
x = x(:); y = y(:);

% Stage 1
[y1, alg1] = stability.ts_algebraic_solve(x, y, Y, dae_g, jac_y, g_tol, []);
if ~alg1.converged, error('ts_step_rk4:stage1Algebraic', ...
    'RK4 stage 1 algebraic solve failed: res=%.3e.', alg1.final_residual); end
K1 = dae_f(x, y1);

% Stage 2
X2 = x + h/2*K1;
[y2, alg2] = stability.ts_algebraic_solve(X2, y1, Y, dae_g, jac_y, g_tol, []);
if ~alg2.converged, error('ts_step_rk4:stage2Algebraic', ...
    'RK4 stage 2 algebraic solve failed: res=%.3e.', alg2.final_residual); end
K2 = dae_f(X2, y2);

% Stage 3
X3 = x + h/2*K2;
[y3, alg3] = stability.ts_algebraic_solve(X3, y2, Y, dae_g, jac_y, g_tol, []);
if ~alg3.converged, error('ts_step_rk4:stage3Algebraic', ...
    'RK4 stage 3 algebraic solve failed: res=%.3e.', alg3.final_residual); end
K3 = dae_f(X3, y3);

% Stage 4
X4 = x + h*K3;
[y4, alg4] = stability.ts_algebraic_solve(X4, y3, Y, dae_g, jac_y, g_tol, []);
if ~alg4.converged, error('ts_step_rk4:stage4Algebraic', ...
    'RK4 stage 4 algebraic solve failed: res=%.3e.', alg4.final_residual); end
K4 = dae_f(X4, y4);

x_new = x + h/6*(K1 + 2*K2 + 2*K3 + K4);
% Final algebraic re-solve at the endpoint.
[y_new, algf] = stability.ts_algebraic_solve(x_new, y4, Y, dae_g, jac_y, g_tol, []);
if ~algf.converged, error('ts_step_rk4:finalAlgebraic', ...
    'RK4 final algebraic re-solve failed: res=%.3e.', algf.final_residual); end
f1 = dae_f(x_new, y_new);
alg_res = norm(dae_g(x_new, y_new, Y), inf);
all_finite = all(isfinite(x_new)) && all(isfinite(y_new)) && all(isfinite(f1));
step = struct( ...
    'x_full', x_new, 'y_full', y_new, ...
    'f0', K1, 'f1', f1, ...
    'corrector_iterations', 4, ...
    'corrector_residual', alg_res, ...
    'corrector_update', norm(x_new - x, inf), ...
    'corrector_converged', algf.converged && all_finite, ...
    'algebraic_residual', alg_res, ...
    'finite', all_finite);
end

% =========================================================================
function step = rk4_classical_provider(strategy, x, y, h, Y, opt, g_tol)
provider = strategy.provider;
t0 = 0; if isfield(opt,'t') && ~isempty(opt.t), t0 = opt.t; end
event_context = []; if isfield(opt,'event_context') && ~isempty(opt.event_context)
    event_context = opt.event_context; end
dae_f_u = strategy.dae_f_u;
x = x(:); y = y(:);

u1 = stability.eval_input_provider(provider, t0, event_context);
u2 = stability.eval_input_provider(provider, t0 + h/2, event_context);
u3 = stability.eval_input_provider(provider, t0 + h/2, event_context);
u4 = stability.eval_input_provider(provider, t0 + h, event_context);

f0 = dae_f_u(x, y, Y, u1);
K1 = f0;
X2 = x + h/2*K1;
K2 = dae_f_u(X2, y, Y, u2);
X3 = x + h/2*K2;
K3 = dae_f_u(X3, y, Y, u3);
X4 = x + h*K3;
K4 = dae_f_u(X4, y, Y, u4);

x_new = x + h/6*(K1 + 2*K2 + 2*K3 + K4);
f1 = dae_f_u(x_new, y, Y, u4);
alg_res = 0;
all_finite = all(isfinite(x_new)) && all(isfinite(f1));
step = struct( ...
    'x_full', x_new, 'y_full', y, ...
    'f0', f0, 'f1', f1, ...
    'corrector_iterations', 4, ...
    'corrector_residual', 0, ...
    'corrector_update', norm(x_new - x, inf), ...
    'corrector_converged', all_finite, ...
    'algebraic_residual', alg_res, ...
    'finite', all_finite);
end

% =========================================================================
function step = rk4_coupled_provider(strategy, x, y, h, Y, opt, g_tol)
provider = strategy.provider;
t0 = 0; if isfield(opt,'t') && ~isempty(opt.t), t0 = opt.t; end
event_context = []; if isfield(opt,'event_context') && ~isempty(opt.event_context)
    event_context = opt.event_context; end
dae_f_u = strategy.dae_f_u;
dae_g_u = strategy.dae_g_u;
jac_y_u = strategy.jac_y_u;
x = x(:); y = y(:);

u1 = stability.eval_input_provider(provider, t0, event_context);
u2 = stability.eval_input_provider(provider, t0 + h/2, event_context);
u3 = stability.eval_input_provider(provider, t0 + h/2, event_context);
u4 = stability.eval_input_provider(provider, t0 + h, event_context);

% Stage 1
[y1, alg1] = stability.ts_algebraic_solve_u(x, y, Y, dae_g_u, jac_y_u, g_tol, [], u1);
if ~alg1.converged, error('ts_step_rk4:stage1Algebraic', ...
    'RK4 provider stage 1 algebraic failed: res=%.3e.', alg1.final_residual); end
K1 = dae_f_u(x, y1, u1);
% Stage 2
X2 = x + h/2*K1;
[y2, alg2] = stability.ts_algebraic_solve_u(X2, y1, Y, dae_g_u, jac_y_u, g_tol, [], u2);
if ~alg2.converged, error('ts_step_rk4:stage2Algebraic', ...
    'RK4 provider stage 2 algebraic failed: res=%.3e.', alg2.final_residual); end
K2 = dae_f_u(X2, y2, u2);
% Stage 3
X3 = x + h/2*K2;
[y3, alg3] = stability.ts_algebraic_solve_u(X3, y2, Y, dae_g_u, jac_y_u, g_tol, [], u3);
if ~alg3.converged, error('ts_step_rk4:stage3Algebraic', ...
    'RK4 provider stage 3 algebraic failed: res=%.3e.', alg3.final_residual); end
K3 = dae_f_u(X3, y3, u3);
% Stage 4
X4 = x + h*K3;
[y4, alg4] = stability.ts_algebraic_solve_u(X4, y3, Y, dae_g_u, jac_y_u, g_tol, [], u4);
if ~alg4.converged, error('ts_step_rk4:stage4Algebraic', ...
    'RK4 provider stage 4 algebraic failed: res=%.3e.', alg4.final_residual); end
K4 = dae_f_u(X4, y4, u4);

x_new = x + h/6*(K1 + 2*K2 + 2*K3 + K4);
[y_new, algf] = stability.ts_algebraic_solve_u(x_new, y4, Y, dae_g_u, jac_y_u, g_tol, [], u4);
if ~algf.converged, error('ts_step_rk4:finalAlgebraic', ...
    'RK4 provider final algebraic re-solve failed: res=%.3e.', algf.final_residual); end
f1 = dae_f_u(x_new, y_new, u4);
alg_res = norm(dae_g_u(x_new, y_new, Y, u4), inf);
all_finite = all(isfinite(x_new)) && all(isfinite(y_new)) && all(isfinite(f1));
step = struct( ...
    'x_full', x_new, 'y_full', y_new, ...
    'f0', K1, 'f1', f1, ...
    'corrector_iterations', 4, ...
    'corrector_residual', alg_res, ...
    'corrector_update', norm(x_new - x, inf), ...
    'corrector_converged', algf.converged && all_finite, ...
    'algebraic_residual', alg_res, ...
    'finite', all_finite);
end

% =========================================================================
function v = get_field(opt, name, default)
if isfield(opt, name) && ~isempty(opt.(name)), v = opt.(name); else, v = default; end
end
