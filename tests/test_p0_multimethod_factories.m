function tests = test_p0_multimethod_factories()
%TEST_P0_MULTIMETHOD_FACTORIES  P0 package-level factory contracts (CORE_ONLY, NOT_ROUTED).
%   P0 scope (per plan §2 ownership route): the PF and TS factories are
%   package-level and tested by DIRECT calls. solve_case.m / ts_simulate.m /
%   ts_adaptive_driver.m are NOT modified. Production routing readiness is
%   NOT_READY until the single-owner integration files are separately resolved.
%
%   This test verifies:
%     PF:  - default NR resolution
%          - explicit NR resolution (default == explicit, AbsTol=0 end-to-end)
%          - unknown PF method fails closed
%          - factory returns NR strategy that calls powerflow_newton_raphson
%     TS:  - default trapezoidal resolution (no opt.method)
%          - alias resolution from legacy opt.method='trapezoidal'
%          - canonical opt.integrator field precedence over opt.method
%          - unknown integrator fails closed
%          - backward_euler/rk4/esdirk32 are notYetApproved in P0
%          - factory returns @ts_step_kernel for trapezoidal (bit-identical)
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
% PF factory tests
% =========================================================================

function test_pf_default_resolves_newton_raphson(testCase)
[mn, ms] = pfsolver.pf_resolve_method(struct());
testCase.verifyEqual(mn, 'newton_raphson', 'default method.');
testCase.verifyEqual(ms, 'default', 'absent field -> default source.');
end

function test_pf_explicit_newton_raphson(testCase)
[mn, ms] = pfsolver.pf_resolve_method(struct('pf_method', 'newton_raphson'));
testCase.verifyEqual(mn, 'newton_raphson');
testCase.verifyEqual(ms, 'explicit');
end

function test_pf_explicit_case_insensitive_and_trimmed(testCase)
[mn, ~] = pfsolver.pf_resolve_method(struct('pf_method', '  Newton_Raphson  '));
testCase.verifyEqual(mn, 'newton_raphson');
end

function test_pf_unknown_method_fails_closed(testCase)
% Unknown names fail closed. 'gauss_seidel' and 'bogus' are never registered.
testCase.verifyError(@() pfsolver.pf_resolve_method(struct('pf_method', 'gauss_seidel')), ...
    'pf_resolve_method:unknownMethod');
testCase.verifyError(@() pfsolver.pf_resolve_method(struct('pf_method', 'bogus')), ...
    'pf_resolve_method:unknownMethod');
end

function test_pf_strategy_unknown_fails_closed(testCase)
testCase.verifyError(@() pfsolver.pf_method_strategy('bogus'), ...
    'pf_method_strategy:unknownMethod');
testCase.verifyError(@() pfsolver.pf_method_strategy(''), ...
    'pf_method_strategy:missingName');
end

function test_pf_factory_nr_bit_identical_to_direct_call(testCase)
% The factory's .solve for newton_raphson MUST be bit-identical (AbsTol=0)
% to calling pfsolver.powerflow_newton_raphson directly on the same case+opt.
c = cases.case_ieee5bus();
opt = struct('verbose', false, 'plot_results', false, 'max_iter', 50, ...
    'tolerance', 1e-10, 'enforce_q_limits', false);
strat = pfsolver.pf_method_strategy('newton_raphson');
r_factory = strat.solve(c, opt);
r_direct = pfsolver.powerflow_newton_raphson(c, opt);
testCase.verifyEqual(r_factory.bus_voltage, r_direct.bus_voltage, 'AbsTol', 0);
testCase.verifyEqual(r_factory.bus_angle_deg, r_direct.bus_angle_deg, 'AbsTol', 0);
testCase.verifyEqual(r_factory.iterations, r_direct.iterations);
testCase.verifyEqual(r_factory.converged, r_direct.converged);
testCase.verifyEqual(r_factory.method, 'Newton-Raphson');
end

% =========================================================================
% TS integrator factory tests
% =========================================================================

function test_ts_default_resolves_trapezoidal(testCase)
[int, ms, ~] = stability.resolve_ts_integrator(struct());
testCase.verifyEqual(int, 'trapezoidal');
testCase.verifyEqual(ms, 'default');
end

function test_ts_alias_from_legacy_method(testCase)
[int, ms, ~] = stability.resolve_ts_integrator(struct('method', 'trapezoidal'));
testCase.verifyEqual(int, 'trapezoidal');
testCase.verifyEqual(ms, 'explicit_method_alias');
end

function test_ts_integrator_field_precedence(testCase)
% opt.integrator takes precedence over opt.method.
[int, ms, ~] = stability.resolve_ts_integrator( ...
    struct('integrator', 'trapezoidal', 'method', 'trapezoidal'));
testCase.verifyEqual(int, 'trapezoidal');
testCase.verifyEqual(ms, 'explicit_integrator');
end

function test_ts_resolved_opt_threads_back(testCase)
% After resolution, opt.integrator AND opt.method are both set so legacy
% consumers (result.method, plot_ts_result.m) keep working.
[~, ~, opt] = stability.resolve_ts_integrator(struct('method', 'trapezoidal'));
testCase.verifyEqual(opt.integrator, 'trapezoidal');
testCase.verifyEqual(opt.method, 'trapezoidal');
end

function test_ts_unknown_integrator_fails_closed(testCase)
testCase.verifyError(@() stability.resolve_ts_integrator(struct('integrator', 'bogus')), ...
    'resolve_ts_integrator:unknownIntegrator');
end

function test_ts_backward_euler_resolves_p4(testCase)
% P4: backward_euler is now registered (after P3.5 passed). Source verified
% (NAODE book Section 4.1 eq 4.9, L-stable Section 8.4.1). FIXED-STEP ONLY.
[int, ms, ~] = stability.resolve_ts_integrator(struct('integrator', 'backward_euler'));
testCase.verifyEqual(int, 'backward_euler');
testCase.verifyEqual(ms, 'explicit_integrator');
fn = stability.ts_integrator_step(struct('integrator', 'backward_euler'));
testCase.verifyEqual(func2str(fn), 'stability.ts_step_be');
end

function test_ts_rk4_resolves_p5(testCase)
% P5: rk4 is now registered (after P3.5 passed). Source: Sulí & Mayers 2003 p.352.
% capability='diagnostic' (bounded stability). FIXED-STEP ONLY.
[int, ms, ~] = stability.resolve_ts_integrator(struct('integrator', 'rk4'));
testCase.verifyEqual(int, 'rk4');
testCase.verifyEqual(ms, 'explicit_integrator');
fn = stability.ts_integrator_step(struct('integrator', 'rk4'));
testCase.verifyEqual(func2str(fn), 'stability.ts_step_rk4');
end

function test_ts_esdirk32_not_yet_approved_p0(testCase)
% esdirk32 is rejected at resolution time (the single source of validation).
% ts_integrator_step delegates to resolve_ts_integrator, so the surfaced
% error id is the resolver's. No executable step handle is ever returned.
testCase.verifyError(@() stability.resolve_ts_integrator(struct('integrator', 'esdirk32')), ...
    'resolve_ts_integrator:notYetApproved');
testCase.verifyError(@() stability.ts_integrator_step(struct('integrator', 'esdirk32')), ...
    'resolve_ts_integrator:notYetApproved');
end

function test_ts_factory_trapezoidal_is_step_kernel(testCase)
% The factory for 'trapezoidal' returns @stability.ts_step_kernel (bit-identical).
fn = stability.ts_integrator_step(struct('integrator', 'trapezoidal'));
testCase.verifyEqual(func2str(fn), 'stability.ts_step_kernel');
end

function test_ts_factory_default_is_step_kernel(testCase)
fn = stability.ts_integrator_step(struct());
testCase.verifyEqual(func2str(fn), 'stability.ts_step_kernel');
end
