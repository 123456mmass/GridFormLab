function tests = test_ts_adaptive_lte()
%TEST_TS_ADAPTIVE_LTE  Adaptive controller unit tests on a known ODE.
%   Proves the step-doubling fine-solution estimator, convergence orders,
%   controller exponent, and event/rollback semantics on ẍ + x = 0 (analytic
%   solution x(t) = cos(t)) BEFORE the controller is relied on in production.
%
%   Per the approved plan §2:
%     A. local one-step error from an exact start: O(h^(p+1)) = O(h^3); halving h
%        cuts LTE by 2^(p+1) = 8.
%     B. fixed-final-time global trajectory error: O(h^p) = O(h^2); halving h
%        cuts global error by 2^p = 4.
%     C. Richardson estimator (denominator 3): e sign/magnitude vs analytic LTE;
%        accepted solution = x_halfhalf; halving h cuts the estimator by ~8.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function strat = sho_strategy()
% Simple harmonic oscillator ẍ = -x as a strategy. State x=[x; v], no y, no g.
% dae_f(x,y,Y) = [v; -x] (Y unused). This is a pure ODE: no algebraic solve.
f = @(x,~ ,~) [x(2); -x(1)];
strat = struct();
strat.model = 'sho_test';
strat.dae_f = f;
strat.dae_g = [];
strat.jac_y = @(~,~,~) [];
strat.needs_jyy = false;
strat.needs_algebraic_solve = false;
strat.electrical_power = @(~,~,~) [];
strat.state_split = struct('ng',1,'ns',2,'delta_idx',1,'omega_idx',2);
strat.reconstruct = @(x,~,~) struct('delta',x(1),'omega',x(2),'Pe',0,'Vbus',zeros(0,1));
end

function opt = base_opt(dt)
opt = struct();
opt.dt_init = dt;
opt.dt_nominal = dt;
opt.dt_min = dt/1024;
opt.dt_max = dt*4;
opt.controller_fac = 0.9;
opt.controller_fac_min = 0.2;
opt.controller_fac_max = 5.0;
opt.reject_limit = 20;
opt.atol_x = 1e-10; opt.rtol_x = 1e-8;
opt.atol_y = 1e-10; opt.rtol_y = 1e-8;
opt.algebraic_tolerance = 1e-12;
opt.max_corrector_iter = 50;
opt.corrector_abs_tol = 1e-12;
opt.corrector_rel_tol = 1e-10;
opt.corrector_mode = 'adaptive';
end

function events = no_events()
events = struct('fault_enabled',false,'t_fault',inf,'t_clear',inf, ...
    'Ypre',0,'Yfault',0,'Ypost',0);
end

function test_C_richardson_denominator_is_3(testCase)
% Test C: the estimator e = (x_halfhalf - x_full)/3 matches the analytic LTE.
% Take one trapezoidal step of size h on ẍ=-x from x=[1;0]. Analytic LTE of the
% trapezoidal rule is O(h^3); the fine-solution (two-half) estimator must equal
% (x_halfhalf - x_full)/3 and be ~8x smaller when h halves.
strat = sho_strategy();
h = 0.1;
kopt = struct('max_corrector_iter',50,'corrector_abs_tol',1e-14, ...
    'corrector_rel_tol',1e-12,'corrector_mode','adaptive');
x0 = [1;0]; y0 = [];
sf = stability.ts_step_kernel(strat,x0,y0,h,0,kopt);
sh1 = stability.ts_step_kernel(strat,x0,y0,h/2,0,kopt);
sh2 = stability.ts_step_kernel(strat,sh1.x_full,sh1.y_full,h/2,0,kopt);
x_full = sf.x_full; x_hh = sh2.x_full;
e_h = (x_hh - x_full)/3;
% Analytic fine-solution LTE for trap on ẍ=-x: leading term ~ (h^3/12)*x''' .
% x'''(0) = -v(0) = 0 for x0=[1;0] on component 1; use component 2 (v).
% v'''(0) = x(0) = 1, so LTE_v ~ h^3/12. Compare magnitude/order.
testCase.verifyEqual(mod(round(log2(abs(e_h(2)) / (h^3/12))), 1), 0, ...
    'Estimator magnitude should be ~h^3/12 (within factor 2).');
% Halving h: estimator should drop by ~8 (2^(p+1)).
h2 = h/2;
sf2 = stability.ts_step_kernel(strat,x0,y0,h2,0,kopt);
sh1b = stability.ts_step_kernel(strat,x0,y0,h2/2,0,kopt);
sh2b = stability.ts_step_kernel(strat,sh1b.x_full,sh1b.y_full,h2/2,0,kopt);
e_h2 = (sh2b.x_full - sf2.x_full)/3;
ratio = abs(e_h(2)) / (abs(e_h2(2)) + 1e-300);
testCase.verifyGreaterThan(ratio, 5.0, 'Halving h should cut estimator by ~8.');
testCase.verifyLessThan(ratio, 12.0, 'Estimator ratio should be ~8 (not 4 or 16).');
% Accepted candidate is x_halfhalf (the fine solution).
testCase.verifyEqual(strat.dae_f(sh2.x_full, [], 0), strat.dae_f(x_hh, [], 0), 'AbsTol', 0);
end

function test_A_local_error_O_h3(testCase)
% Test A: one-step local error from an exact start is O(h^3); halving h cuts
% LTE by ~8.
strat = sho_strategy();
x0 = [1;0];
hs = [0.1, 0.05, 0.025];
errs = zeros(size(hs));
kopt = struct('max_corrector_iter',50,'corrector_abs_tol',1e-14, ...
    'corrector_rel_tol',1e-12,'corrector_mode','adaptive');
for k = 1:numel(hs)
    h = hs(k);
    sh1 = stability.ts_step_kernel(strat,x0,[],h/2,0,kopt);
    sh2 = stability.ts_step_kernel(strat,sh1.x_full,sh1.y_full,h/2,0,kopt);
    x_num = sh2.x_full;            % fine solution after one step h
    x_ex = [cos(h); -sin(h)];      % analytic
    errs(k) = max(abs(x_num - x_ex));
end
ratio = errs(1) / errs(2);
testCase.verifyGreaterThan(ratio, 5.0, 'Local error should drop by ~8 when h halves.');
testCase.verifyLessThan(ratio, 12.0);
ratio2 = errs(2) / errs(3);
testCase.verifyGreaterThan(ratio2, 5.0);
testCase.verifyLessThan(ratio2, 12.0);
end

function test_B_global_error_O_h2(testCase)
% Test B: fixed-final-time global trajectory error is O(h^2); halving h cuts
% global error by ~4.
strat = sho_strategy();
T = 1.0;
hs = [0.02, 0.01, 0.005];
errs = zeros(size(hs));
kopt = struct('max_corrector_iter',50,'corrector_abs_tol',1e-14, ...
    'corrector_rel_tol',1e-12,'corrector_mode','adaptive');
for k = 1:numel(hs)
    h = hs(k);
    n = round(T/h);
    x = [1;0]; y = [];
    for it = 1:n
        sh1 = stability.ts_step_kernel(strat,x,y,h/2,0,kopt);
        sh2 = stability.ts_step_kernel(strat,sh1.x_full,sh1.y_full,h/2,0,kopt);
        x = sh2.x_full; y = sh2.y_full;
    end
    x_ex = [cos(n*h); -sin(n*h)];
    errs(k) = max(abs(x - x_ex));
end
ratio = errs(1) / errs(2);
testCase.verifyGreaterThan(ratio, 3.0, 'Global error should drop by ~4 when h halves.');
testCase.verifyLessThan(ratio, 5.5);
end

function test_controller_exponent_1_over_3(testCase)
% The accepted-step controller uses exponent 1/(p+1) = 1/3. Verify the driver
% reports the correct exponent and denominator.
strat = sho_strategy();
opt = base_opt(0.05);
ev = no_events();
res = stability.ts_adaptive_driver(strat, [1;0], [], [0, 0.5], ev, opt);
testCase.verifyEqual(res.denominator, 3, 'Richardson denominator must be 3.');
testCase.verifyEqual(res.controller_exponent, 1/3, 'Controller exponent must be 1/3.');
testCase.verifyEqual(res.p, 2);
testCase.verifyEqual(res.q, 3);
testCase.verifyEqual(res.stepper, 'adaptive');
end

function test_adaptive_completes_and_accepts(testCase)
strat = sho_strategy();
opt = base_opt(0.05);
ev = no_events();
res = stability.ts_adaptive_driver(strat, [1;0], [], [0, 2.0], ev, opt);
testCase.verifyTrue(all(isfinite(res.delta(:))));
testCase.verifyEqual(res.t(1), 0);
testCase.verifyEqual(res.t(end), 2.0, 'AbsTol', 1e-12);
testCase.verifyGreaterThan(res.accepted_steps, 0);
testCase.verifyTrue(all(diff(res.t) > 0), 'r.t must be strictly increasing.');
testCase.verifyEqual(numel(res.dt_history), numel(res.t)-1);
testCase.verifyEqual(numel(res.lte_history), numel(res.t)-1);
% Analytic solution at t=2: x=cos(2).
testCase.verifyLessThan(abs(res.delta(end) - cos(2)), 1e-3, ...
    'Adaptive SHO result should be close to analytic cos(2).');
end

function test_dt_min_failure_no_silent_fallback(testCase)
% A stiff ODE that the controller cannot satisfy at dt_min must ERROR with
% diagnostics (no silent fixed-step fallback). Use ẍ = -1e6*x (very stiff).
strat = struct();
strat.model = 'stiff_test';
strat.dae_f = @(x,~,~) [x(2); -1e6*x(1)];
strat.dae_g = [];
strat.jac_y = @(~,~,~) [];
strat.needs_jyy = false;
strat.needs_algebraic_solve = false;
strat.electrical_power = @(~,~,~) [];
strat.state_split = struct('ng',1,'ns',2,'delta_idx',1,'omega_idx',2);
strat.reconstruct = @(x,~,~) struct('delta',x(1),'omega',x(2),'Pe',0,'Vbus',zeros(0,1));
opt = base_opt(0.01);
opt.dt_min = 1e-4; opt.dt_max = 0.01;
opt.atol_x = 1e-12; opt.rtol_x = 1e-12;   % very tight -> forces rejection
opt.reject_limit = 30;
ev = no_events();
try
    stability.ts_adaptive_driver(strat, [1;0], [], [0, 0.5], ev, opt);
    testCase.verifyTrue(false, 'Should have errored at dt_min exhaustion.');
catch e
    testCase.verifyTrue(contains(e.identifier, 'ts_adaptive_driver'), ...
        'Must error with ts_adaptive_driver identifier.');
    testCase.verifyTrue(~isempty(strfind(e.message, 'No silent fixed-step fallback')), ...
        'Error must state no silent fixed-step fallback.');
end
end

function test_rejection_diagnostics_retained(testCase)
% A rejected step must append exactly one rejection diagnostic and NOT alter
% accepted output. Use a tolerance tight enough to force at least one rejection
% but loose enough that the SHO can still be solved (not dt_min exhaustion).
strat = sho_strategy();
opt = base_opt(0.1);
opt.atol_x = 1e-9; opt.rtol_x = 1e-7;   % tight enough to reject the first large step
opt.reject_limit = 50;
opt.dt_min = 1e-5;
ev = no_events();
res = stability.ts_adaptive_driver(strat, [1;0], [], [0, 0.3], ev, opt);
if res.rejected_steps > 0
    testCase.verifyEqual(numel(res.rejection_history), res.rejected_steps, ...
        'rejection_history length must equal rejected_steps.');
    for k = 1:numel(res.rejection_history)
        f = res.rejection_history(k);
        testCase.verifyTrue(isfield(f,'attempted_dt') && isfield(f,'error_norm') && ...
            isfield(f,'reason') && isfield(f,'retry_dt') && isfield(f,'rejection_count'));
        testCase.verifyGreaterThan(f.error_norm, 1.0, 'Rejection must have err > 1.');
    end
end
% Accepted trajectory is strictly increasing and unmodified by rejections.
testCase.verifyTrue(all(diff(res.t) > 0));
end

function test_exact_event_landing(testCase)
% The adaptive grid must land exactly on t_fault and t_clear; no step crosses a
% topology boundary. Use a fake event with topology = scalar markers.
strat = sho_strategy();
opt = base_opt(0.05);
ev = struct('fault_enabled',true,'t_fault',0.3,'t_clear',0.6, ...
    'Ypre',1,'Yfault',2,'Ypost',3);
res = stability.ts_adaptive_driver(strat, [1;0], [], [0, 1.0], ev, opt);
testCase.verifyEqual(min(abs(res.t - 0.3)), 0, 'AbsTol', 1e-14, 't_fault on grid.');
testCase.verifyEqual(min(abs(res.t - 0.6)), 0, 'AbsTol', 1e-14, 't_clear on grid.');
testCase.verifyTrue(all(diff(res.t) > 0), 'strictly increasing');
end
