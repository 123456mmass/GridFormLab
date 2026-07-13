function tests = test_ts_rk4()
%TEST_TS_RK4  P5 RK4 integrator tests (CORE_ONLY, NOT_ROUTED, DIAGNOSTIC).
%   Source verified: Sulí & Mayers, An Introduction to Numerical Analysis,
%   2003, p.352 (Butcher tableau via Wikipedia).
%
%   P5 scope (package-only): tested by DIRECT calls. ts_simulate.m /
%   ts_adaptive_driver.m are NOT modified. FIXED-STEP ONLY (adaptive requires
%   the frozen method-specific algebraic adaptive-error definition, correction 6).
%   capability='diagnostic' (BOUNDED stability region, NOT A-stable).
%
%   Tests:
%     1. classical path: RK4 matches closed-form on x'=lambda*x (high accuracy)
%     2. convergence order ~ 4 (global error drops by ~16x when h halves)
%     3. harmonic oscillator: RK4 matches closed-form exp(A*t)
%     4. coupled DAE: algebraic residual satisfied at endpoint
%     5. 4-stage verification (corrector_iterations == 4)
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
function [strategy, x0, y0] = scalar_strategy(lambda)
% x' = lambda*x; y dummy held at 0. jac_y signature matches ts_jac_y_fd: (x,y,Y,dae_g).
strategy.dae_f = @(x,y) lambda*x;
strategy.dae_g = @(x,y,~) y;
strategy.jac_y = @(x,y,Y,dae_g) 1;
strategy.needs_algebraic_solve = true;
strategy.provider = [];
x0 = 1; y0 = 0;
end

function test_classical_matches_closed_form(testCase)
% For x'=lambda*x, classical RK4 with one step h gives:
%   x1 = (1 + h*lambda + (h*lambda)^2/2 + (h*lambda)^3/6 + (h*lambda)^4/24) * x0
% which is the 4th-order Taylor expansion of exp(h*lambda).
[strat, x0, y0] = scalar_strategy(-1);
h = 0.1;
opt = struct('algebraic_tolerance',1e-12);
step = stability.ts_step_rk4(strat, x0, y0, h, [], opt);
z = h*(-1);
x1_exact = (1 + z + z^2/2 + z^3/6 + z^4/24) * x0;
testCase.verifyEqual(step.x_full(1), x1_exact, 'AbsTol', 1e-12, 'classical RK4 matches 4th-order Taylor.');
testCase.verifyEqual(step.corrector_iterations, 4, '4 stages.');
testCase.verifyTrue(step.corrector_converged, 'converged.');
end

% =========================================================================
function test_convergence_order_four(testCase)
% RK4 is 4th-order: global error ~ C*h^4. Integrate x'=lambda*x (lambda=-1)
% to t=1.0; err(h/2)/err(h) ~ (1/2)^4 = 1/16 = 0.0625.
[strat, x0, y0] = scalar_strategy(-1);
t_end = 1.0;
hs = [0.1, 0.05, 0.025];
errs = zeros(size(hs));
opt = struct('algebraic_tolerance',1e-12);
for k = 1:numel(hs)
    h = hs(k);
    x = x0; y = y0;
    n = round(t_end/h);
    for j = 1:n
        st = stability.ts_step_rk4(strat, x, y, h, [], opt);
        x = st.x_full; y = st.y_full;
    end
    errs(k) = abs(x(1) - exp(-t_end));
end
% Order 4: err(h/2)/err(h) ~ 1/16 = 0.0625. Allow slack [0.04, 0.1].
ratio1 = errs(2)/errs(1);
ratio2 = errs(3)/errs(2);
testCase.verifyGreaterThan(ratio1, 0.04, 'err(h/2)/err(h) ~ 0.0625 (order 4).');
testCase.verifyLessThan(ratio1, 0.12, 'err(h/2)/err(h) ~ 0.0625 (order 4).');
testCase.verifyGreaterThan(ratio2, 0.04, 'err(h/4)/err(h/2) ~ 0.0625 (order 4).');
testCase.verifyLessThan(ratio2, 0.12, 'err(h/4)/err(h/2) ~ 0.0625 (order 4).');
end

% =========================================================================
function [strategy, x0, y0] = harmonic_strategy()
% x1' = x2; x2' = -x1. y held at 0. jac_y signature: (x,y,Y,dae_g).
strategy.dae_f = @(x,y) [x(2); -x(1)];
strategy.dae_g = @(x,y,~) y;
strategy.jac_y = @(x,y,Y,dae_g) eye(numel(y));
strategy.needs_algebraic_solve = true;
strategy.provider = [];
x0 = [1; 0]; y0 = 0;
end

function test_harmonic_matches_closed_form(testCase)
% Closed-form: x(t) = exp(A*t)*x0, A=[0 1;-1 0]. RK4 with one step h gives
% x1 = (I + h*A + (h*A)^2/2 + (h*A)^3/6 + (h*A)^4/24) * x0 (4th-order Taylor).
[strat, x0, y0] = harmonic_strategy();
h = 0.05;
opt = struct('algebraic_tolerance',1e-12);
step = stability.ts_step_rk4(strat, x0, y0, h, [], opt);
A = [0 1; -1 0];
M = h*A;
x1_exact = (eye(2) + M + M^2/2 + M^3/6 + M^4/24) * x0;
testCase.verifyEqual(step.x_full, x1_exact, 'AbsTol', 1e-12, 'harmonic RK4 matches Taylor.');
testCase.verifyEqual(step.corrector_iterations, 4, '4 stages.');
end

% =========================================================================
function test_coupled_dae_algebraic_residual(testCase)
% Coupled DAE: x'=y; g=y-x (so y=x at solution). RK4 should keep y=x at endpoint.
strategy.dae_f = @(x,y) y(1);
strategy.dae_g = @(x,y,~) y - x;
strategy.jac_y = @(x,y,Y,dae_g) 1;
strategy.needs_algebraic_solve = true;
strategy.provider = [];
x0 = 1; y0 = 1;  % consistent
h = 0.1;
opt = struct('algebraic_tolerance',1e-10);
step = stability.ts_step_rk4(strategy, x0, y0, h, [], opt);
testCase.verifyLessThan(abs(step.y_full - step.x_full), 1e-9, 'algebraic g=y-x satisfied.');
testCase.verifyEqual(step.corrector_iterations, 4, '4 stages.');
testCase.verifyTrue(step.finite, 'finite.');
end

% =========================================================================
function test_four_stages_recorded(testCase)
% corrector_iterations must be 4 (the stage count), regardless of model.
[strat, x0, y0] = scalar_strategy(-1);
opt = struct('algebraic_tolerance',1e-12);
step = stability.ts_step_rk4(strat, x0, y0, 0.05, [], opt);
testCase.verifyEqual(step.corrector_iterations, 4, 'RK4 records 4 stages.');
end

% =========================================================================
function test_unknown_integrator_still_fails(testCase)
testCase.verifyError(@() stability.resolve_ts_integrator(struct('integrator', 'bogus')), ...
    'resolve_ts_integrator:unknownIntegrator');
end
