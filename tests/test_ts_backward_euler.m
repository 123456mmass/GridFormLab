function tests = test_ts_backward_euler()
%TEST_TS_BACKWARD_EULER  P4 Backward Euler integrator tests (CORE_ONLY, NOT_ROUTED).
%   Source verified: NAODE book Section 4.1 eq 4.9 (y_{n+1}=y_n+h*f(t_{n+1},y_{n+1}));
%   first-order; L-stable (Section 8.4.1).
%
%   P4 scope (package-only): tested by DIRECT calls. ts_simulate.m /
%   ts_adaptive_driver.m are NOT modified. FIXED-STEP ONLY (adaptive requires
%   the frozen method-specific algebraic adaptive-error definition, correction 6).
%
%   Tests:
%     1. scalar stiff decay: L-stability (yn -> 0 for stiff lambda, any h>0)
%     2. analytic harmonic oscillator: BE step matches closed-form BE update
%     3. convergence order ~ 1 (global error halves when h halves)
%     4. algebraic residual at accepted endpoint (coupled DAE)
%     5. classical vs coupled paths both produce finite results
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
function [strategy, x0, y0] = scalar_stiff_strategy(lambda)
% Scalar stiff ODE x' = lambda*x (lambda < 0). y is a dummy algebraic var
% held at 0 via g(x,y) = y. Tests L-stability.
strategy.dae_f = @(x,y) lambda*x;
strategy.dae_g = @(x,y,~) y;
strategy.jac_y = @(x,y,~) 1;
strategy.needs_algebraic_solve = true;
strategy.provider = [];
x0 = 1; y0 = 0;
end

function test_scalar_stiff_lstable(testCase)
% L-stability: for x'=lambda*x with lambda=-100, BE gives
% x_{n+1} = x_n/(1-h*lambda). For h=0.1 >> 1/|lambda|, explicit Euler
% diverges but BE stays bounded and decays.
[strat, x0, y0] = scalar_stiff_strategy(-100);
h = 0.1;  % large step (h*|lambda| = 10 >> 1)
opt = struct('algebraic_tolerance',1e-10,'be_newton_tol',1e-12,'be_max_iter',50);
step = stability.ts_step_be(strat, x0, y0, h, [], opt);
% Closed-form BE: x1 = x0/(1-h*lambda) = 1/(1-0.1*(-100)) = 1/11
x1_exact = x0/(1-h*(-100));
testCase.verifyEqual(step.x_full(1), x1_exact, 'AbsTol', 1e-10, 'BE stiff decay matches closed-form.');
testCase.verifyTrue(step.corrector_converged, 'BE converged on stiff problem.');
testCase.verifyTrue(abs(step.x_full(1)) < abs(x0), 'BE decays (L-stable behavior).');
end

% =========================================================================
function [strategy, x0, y0] = harmonic_strategy()
% Harmonic oscillator x1' = x2; x2' = -x1. Analytic BE update:
%   [x1;x2]_{n+1} = (I - h*A)^{-1} [x1;x2]_n where A = [0 1; -1 0].
% y held at 0 (dummy algebraic).
strategy.dae_f = @(x,y) [x(2); -x(1)];
strategy.dae_g = @(x,y,~) y;
strategy.jac_y = @(x,y,~) eye(numel(y));
strategy.needs_algebraic_solve = true;
strategy.provider = [];
x0 = [1; 0]; y0 = 0;
end

function test_harmonic_matches_closed_form(testCase)
[strat, x0, y0] = harmonic_strategy();
h = 0.05;
opt = struct('algebraic_tolerance',1e-10,'be_newton_tol',1e-12,'be_max_iter',50);
step = stability.ts_step_be(strat, x0, y0, h, [], opt);
A = [0 1; -1 0];
x1_exact = (eye(2) - h*A) \ x0;
testCase.verifyEqual(step.x_full, x1_exact, 'AbsTol', 1e-9, 'BE harmonic matches closed-form (I-hA)^{-1} x0.');
testCase.verifyEqual(step.y_full, y0, 'AbsTol', 1e-12, 'algebraic y held.');
testCase.verifyTrue(step.corrector_converged, 'converged.');
end

% =========================================================================
function test_convergence_order_one(testCase)
% BE is first-order: global error ~ C*h. Integrate x'=lambda*x (lambda=-1)
% to t=1.0 with steps h, h/2, h/4. For order 1, err(h/2)/err(h) -> 0.5
% (error halves when h halves). The order estimate p = log(err_old/err_new)/log(2)
% should be ~ 1.
[strat, x0, y0] = scalar_stiff_strategy(-1);
t_end = 1.0;
hs = [0.1, 0.05, 0.025];
errs = zeros(size(hs));
opt = struct('algebraic_tolerance',1e-12,'be_newton_tol',1e-12,'be_max_iter',50);
for k = 1:numel(hs)
    h = hs(k);
    x = x0; y = y0;
    n = round(t_end/h);
    for j = 1:n
        st = stability.ts_step_be(strat, x, y, h, [], opt);
        x = st.x_full; y = st.y_full;
    end
    errs(k) = abs(x(1) - exp(-t_end));  % exact: exp(-1)
end
% Order 1: err(h/2)/err(h) -> 0.5 (error halves). Verify ratio in [0.4, 0.65].
ratio1 = errs(2)/errs(1);
ratio2 = errs(3)/errs(2);
testCase.verifyGreaterThan(ratio1, 0.4, 'err(h/2)/err(h) ~ 0.5 (order 1).');
testCase.verifyLessThan(ratio1, 0.65, 'err(h/2)/err(h) ~ 0.5 (order 1).');
testCase.verifyGreaterThan(ratio2, 0.4, 'err(h/4)/err(h/2) ~ 0.5 (order 1).');
testCase.verifyLessThan(ratio2, 0.65, 'err(h/4)/err(h/2) ~ 0.5 (order 1).');
end

% =========================================================================
function test_algebraic_residual_at_endpoint(testCase)
% For a coupled DAE, the accepted endpoint must satisfy g(x,y,Y)=0 within tol.
% Use x'=y; g = y - x (so y=x at the solution). Analytic BE: solve
% x1 - x0 - h*y1 = 0 and y1 - x1 = 0 => y1=x1, x1=x0/(1-h).
strategy.dae_f = @(x,y) y(1);
strategy.dae_g = @(x,y,~) y - x;
strategy.jac_y = @(x,y,~) 1;
strategy.needs_algebraic_solve = true;
strategy.provider = [];
x0 = 1; y0 = 1;  % consistent initial
h = 0.1;
opt = struct('algebraic_tolerance',1e-10,'be_newton_tol',1e-12,'be_max_iter',50);
step = stability.ts_step_be(strategy, x0, y0, h, [], opt);
alg_res = abs(step.y_full - step.x_full);
testCase.verifyLessThan(alg_res, 1e-9, 'algebraic residual g=y-x satisfied at endpoint.');
x1_exact = x0/(1-h);
testCase.verifyEqual(step.x_full(1), x1_exact, 'AbsTol', 1e-9, 'coupled BE matches closed-form.');
end

% =========================================================================
function test_classical_path_finite(testCase)
% Classical (linear-network) model: needs_algebraic_solve=false. dae_f solves
% a linear network internally. Use a 2-state classical-like model:
%   x' = f(x,Y) where f depends on x via a linear solve (simulated here).
strategy.dae_f = @(x,y,Y) [-2*x(1) + 0.5*x(2); x(1) - x(2)];
strategy.dae_g = [];
strategy.jac_y = [];
strategy.needs_algebraic_solve = false;
strategy.provider = [];
x0 = [0.3; 0.4]; y0 = [];
h = 0.05;
opt = struct('algebraic_tolerance',1e-10,'be_newton_tol',1e-12,'be_max_iter',50);
step = stability.ts_step_be(strategy, x0, y0, h, [], opt);
testCase.verifyTrue(step.finite, 'classical BE step finite.');
testCase.verifyTrue(step.corrector_converged, 'classical BE converged.');
% Closed-form BE: x1 = (I - h*A)^{-1} x0, A=[-2 0.5; 1 -1].
A = [-2 0.5; 1 -1];
x1_exact = (eye(2) - h*A) \ x0;
testCase.verifyEqual(step.x_full, x1_exact, 'AbsTol', 1e-9, 'classical BE matches closed-form.');
end

% =========================================================================
function test_unknown_integrator_still_fails(testCase)
% After registering backward_euler, unknown names must STILL fail closed.
testCase.verifyError(@() stability.resolve_ts_integrator(struct('integrator', 'bogus')), ...
    'resolve_ts_integrator:unknownIntegrator');
testCase.verifyError(@() stability.ts_integrator_step(struct('integrator', 'bogus')), ...
    'resolve_ts_integrator:unknownIntegrator');
end
