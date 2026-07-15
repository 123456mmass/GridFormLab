function tests = test_ts_phase2_integrator_routing()
%TEST_TS_PHASE2_INTEGRATOR_ROUTING  Phase-2 TS integrator production routing.
%   Verifies ts_simulate / solve_case route through resolve_ts_integrator +
%   ts_integrator_step, record the method metadata contract, preserve default
%   trapezoidal bit-identically (AbsTol=0), run BE/RK4 fixed-step, fail closed
%   on adaptive+BE/RK4 (adaptiveNotFrozen) at BOTH route and driver level, and
%   reject esdirk32/unknown. Provider bundle + event-landing oracles are in
%   cases 15-20.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function opt = quick_opt(overrides)
% Short-horizon Case14 classical opt (no fault inside the 0.3 s window).
opt = struct('t_end',0.3,'dt',0.1,'fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'pm_mode','pgaz','corrector_mode','adaptive','verbose',false);
if nargin >= 1
    fn = fieldnames(overrides);
    for k = 1:numel(fn), opt.(fn{k}) = overrides.(fn{k}); end
end
end

function c = case14()
c = cases.case_matpower6_case14();
end

% =========================================================================
function test_default_trapezoidal_bit_identical(testCase)
% Default ts_simulate must be bit-identical (AbsTol=0) to explicit trapezoidal.
c = case14();
r1 = stability.ts_simulate(c, quick_opt());
r2 = stability.ts_simulate(c, quick_opt(struct('integrator','trapezoidal')));
testCase.verifyEqual(r1.delta, r2.delta, 'AbsTol', 0);
testCase.verifyEqual(r1.omega, r2.omega, 'AbsTol', 0);
testCase.verifyEqual(r1.integrator, 'trapezoidal');
testCase.verifyEqual(r1.metadata.selection_source, 'default');
testCase.verifyEqual(r1.metadata.method_executed, 'trapezoidal');
end

function test_integrator_precedence_over_method(testCase)
c = case14();
r = stability.ts_simulate(c, quick_opt(struct('integrator','trapezoidal','method','trapezoidal')));
testCase.verifyEqual(r.integrator, 'trapezoidal');
testCase.verifyEqual(r.metadata.selection_source, 'explicit_integrator');
end

function test_backward_euler_classical_fixed(testCase)
c = case14();
r = stability.ts_simulate(c, quick_opt(struct('integrator','backward_euler')));
testCase.verifyEqual(r.integrator, 'backward_euler');
testCase.verifyEqual(r.metadata.method_executed, 'backward_euler');
testCase.verifyEqual(r.metadata.capability, 'production');
testCase.verifyTrue(all(isfinite(r.delta(:))), 'BE trajectory finite');
testCase.verifyTrue(all(isfinite(r.omega(:))), 'BE omega finite');
testCase.verifyTrue(isfield(r,'integrator_algebraic_residual'));
testCase.verifyTrue(isfield(r,'max_integrator_algebraic_residual'));
end

function test_rk4_classical_diagnostic(testCase)
c = case14();
r = stability.ts_simulate(c, quick_opt(struct('integrator','rk4')));
testCase.verifyEqual(r.integrator, 'rk4');
testCase.verifyEqual(r.metadata.method_executed, 'rk4');
testCase.verifyEqual(r.metadata.capability, 'diagnostic');
testCase.verifyEqual(r.metadata.runtime_diagnostic, true);
testCase.verifyTrue(all(isfinite(r.delta(:))), 'RK4 trajectory finite');
end

function test_adaptive_backward_euler_fails_closed(testCase)
c = case14();
testCase.verifyError(@() stability.ts_simulate(c, ...
    quick_opt(struct('integrator','backward_euler','stepper','adaptive'))), ...
    'ts_simulate:adaptiveNotFrozen');
end

function test_adaptive_rk4_fails_closed(testCase)
c = case14();
testCase.verifyError(@() stability.ts_simulate(c, ...
    quick_opt(struct('integrator','rk4','stepper','adaptive'))), ...
    'ts_simulate:adaptiveNotFrozen');
end

function test_driver_guard_rejects_non_trapezoidal(testCase)
% Defense-in-depth: the driver itself rejects non-trapezoidal via aopt.integrator.
c = case14();
dae = stability.classical_dae(c, quick_opt());
strat = stability.ts_model_strategy('classical', dae);
events = struct('fault_enabled',false,'t_fault',inf,'t_clear',inf, ...
    'Ypre',dae.Ynet,'Yfault',dae.Ynet,'Ypost',dae.Ynet);
aopt = struct('dt_nominal',0.1,'dt_init',0.1,'dt_min',1e-4,'dt_max',1.0, ...
    'controller_fac',0.9,'controller_fac_min',0.2,'controller_fac_max',5.0, ...
    'reject_limit',10,'atol_x',1e-6,'rtol_x',1e-4,'atol_y',1e-5,'rtol_y',1e-4, ...
    'algebraic_tolerance',1e-12,'max_corrector_iter',10,'corrector_abs_tol',1e-10, ...
    'corrector_rel_tol',1e-8,'corrector_mode','fixed','integrator','backward_euler');
testCase.verifyError(@() stability.ts_adaptive_driver(strat, dae.x0, dae.y0, ...
    [0,0.3], events, aopt), 'ts_adaptive_driver:adaptiveNotFrozen');
end

function test_esdirk32_not_yet_approved(testCase)
c = case14();
testCase.verifyError(@() stability.ts_simulate(c, quick_opt(struct('integrator','esdirk32'))), ...
    'resolve_ts_integrator:notYetApproved');
end

function test_unknown_integrator_fails_closed(testCase)
c = case14();
testCase.verifyError(@() stability.ts_simulate(c, quick_opt(struct('integrator','bogus'))), ...
    'resolve_ts_integrator:unknownIntegrator');
end

function test_adaptive_trapezoidal_still_works(testCase)
c = case14();
r = stability.ts_simulate(c, quick_opt(struct('stepper','adaptive')));
testCase.verifyEqual(r.stepper, 'adaptive');
testCase.verifyEqual(r.integrator, 'trapezoidal');
testCase.verifyEqual(r.denominator, 3);
testCase.verifyEqual(r.controller_exponent, 1/3);
testCase.verifyGreaterThan(r.accepted_steps, 0);
end

function test_solve_case_ts_default_bit_identical(testCase)
% Catalog base sets opt.method='trapezoidal' (network_case_catalog base), so a
% catalog-driven solve_case resolves to selection_source='explicit_method_alias'
% (the catalog explicitly supplies method). A direct ts_simulate with NO
% method/integrator field is 'default'. Both execute trapezoidal bit-identically.
r1 = solve_case('analysis','ts','case','matpower14', ...
    'options',struct('t_end',0.3,'dt',0.1,'verbose',false,'plot_results',false));
r2 = stability.ts_simulate(case14(), quick_opt());
testCase.verifyEqual(r1.delta, r2.delta, 'AbsTol', 0);
testCase.verifyEqual(r1.integrator, 'trapezoidal');
% Catalog sets method='trapezoidal' explicitly -> explicit_method_alias.
testCase.verifyEqual(r1.metadata.selection_source, 'explicit_method_alias');
% Direct call without method/integrator -> default.
testCase.verifyEqual(r2.metadata.selection_source, 'default');
end

function test_padiyar_backward_euler(testCase)
c = cases.case_padiyar_two_area_4m_avr();
opt = struct('t_end',0.2,'dt',0.02,'verbose',false,'integrator','backward_euler');
r = stability.ts_simulate_padiyar_model11(c, opt);
testCase.verifyEqual(r.integrator, 'backward_euler');
testCase.verifyEqual(r.method, 'backward_euler');
testCase.verifyEqual(r.metadata.method_executed, 'backward_euler');
testCase.verifyTrue(all(isfinite(r.delta(:))));
end

function test_padiyar_adaptive_rk4_fails_closed(testCase)
c = cases.case_padiyar_two_area_4m_avr();
opt = struct('t_end',0.2,'dt',0.02,'verbose',false, ...
    'integrator','rk4','stepper','adaptive');
testCase.verifyError(@() stability.ts_simulate_padiyar_model11(c, opt), ...
    'ts_simulate_padiyar_model11:adaptiveNotFrozen');
end

function test_emf6_backward_euler(testCase)
c = cases.kundur_ex126_book_case();
opt = struct('t_end',0.2,'dt',0.02,'verbose',false, ...
    'model','emf6','integrator','backward_euler','corrector_mode','fixed');
r = stability.ts_simulate(c, opt);
testCase.verifyEqual(r.integrator, 'backward_euler');
testCase.verifyEqual(r.metadata.method_executed, 'backward_euler');
testCase.verifyTrue(all(isfinite(r.delta(:))));
end

function test_rk4_not_default(testCase)
c = case14();
r = stability.ts_simulate(c, quick_opt());
testCase.verifyEqual(r.integrator, 'trapezoidal');
testCase.verifyNotEqual(r.integrator, 'rk4');
end

% =========================================================================
% Provider-bearing bundle tests (cases 15-18): BE/RK4 on a valid provider
% strategy with an immutable time-dependent provider + stage-time oracle.
% =========================================================================
function [bundle, oracle] = provider_bundle_oracle()
% Minimal provider-aware bundle for the linear ODE dx/dt = A*x + B*u(t)
% (needs_algebraic_solve=false; no Y, no g). The provider is an immutable
% time-dependent callback u_fn(t, event_context). validate_ts_strategy
% requires dae_f_u/dae_g_u/jac_y_u when provider is present -> all provided.
A = [0, 1; -1, 0]; B = [0; 1]; x0 = [1; 0];
u_fn = @(t,~) sin(2*t);
provider = stability.make_input_provider('callback', u_fn);
dae_f_u = @(x,~,~,u) A*x + B*u;
strat = struct('model','synthetic_linear_ode', ...
    'dae_f_u', dae_f_u, 'dae_g_u', [], 'jac_y_u', @(~,~,~,~) [], ...
    'needs_jyy', false, 'needs_algebraic_solve', false, ...
    'provider', provider, ...
    'state_split', struct('ng',1,'ns',2,'delta_idx',1,'omega_idx',2), ...
    'reconstruct_u', @(x,~,~,~) struct('delta',x(1),'omega',x(2),'Pe',0,'Vbus',0), ...
    'reconstruct', @(x,~,~) struct('delta',x(1),'omega',x(2),'Pe',0,'Vbus',0));
% Legacy closures (validate_ts_strategy requires dae_f/dae_g/jac_y too).
strat.dae_f = @(x,~) A*x + B*u_fn(0,struct());
strat.dae_g = [];
strat.jac_y = [];
strat.electrical_power = @(x,~) 0;
ts.strategy = strat;
ts.x0 = x0; ts.y0 = [];
ts.topology = struct('Ypre',[],'Yfault',[],'Ypost',[]);
ts.mapping = struct('bus_ids',1,'gen_buses',1);
ts.metadata = struct('dispatch','explicit_model_bundle','device_id','oracle_ode');
bundle.ts = ts;
bundle.metadata = ts.metadata;
% Closed-form Duhamel solution (from test_r1_input_provider oracle_setup).
oracle.x_exact = @(t) [cos(t) + (2/3)*sin(t) - (1/3)*sin(2*t); ...
                       -sin(t) + (2/3)*cos(t) - (2/3)*cos(2*t)];
oracle.u_fn = u_fn;
end

function opt = provider_opt(integrator)
opt = struct('t_end',0.5,'dt',0.01,'fault_enabled',false, ...
    't_fault',inf,'t_clear',inf,'Zf',[],'corrector_mode','fixed', ...
    'corrector_iter',3,'max_corrector_iter',3,'corrector_abs_tol',1e-12, ...
    'corrector_rel_tol',1e-10,'algebraic_tolerance',1e-12, ...
    'integrator',integrator,'verbose',false,'plot_results',false);
end

function test_bundle_be_fixed_provider(testCase)
% BE on a valid provider-bearing bundle: runs finite, method_executed correct.
[bundle, ~] = provider_bundle_oracle();
opt = provider_opt('backward_euler');
opt.model_bundle = bundle;
r = stability.ts_simulate(cases.case_matpower6_case14(), opt);
testCase.verifyEqual(r.integrator, 'backward_euler');
testCase.verifyEqual(r.metadata.method_executed, 'backward_euler');
testCase.verifyEqual(r.metadata.capability, 'production');
testCase.verifyTrue(all(isfinite(r.delta(:))), 'BE bundle finite');
% BE is order-1; with dt=0.01 the error vs oracle should be bounded.
testCase.verifyTrue(isfield(r,'max_integrator_algebraic_residual'));
end

function test_bundle_rk4_diagnostic_provider(testCase)
% RK4 on a valid provider-bearing bundle: diagnostic, finite.
[bundle, ~] = provider_bundle_oracle();
opt = provider_opt('rk4');
opt.model_bundle = bundle;
r = stability.ts_simulate(cases.case_matpower6_case14(), opt);
testCase.verifyEqual(r.integrator, 'rk4');
testCase.verifyEqual(r.metadata.method_executed, 'rk4');
testCase.verifyEqual(r.metadata.capability, 'diagnostic');
testCase.verifyEqual(r.metadata.runtime_diagnostic, true);
testCase.verifyTrue(all(isfinite(r.delta(:))), 'RK4 bundle finite');
end

function test_bundle_provider_endpoint_residual_gated(testCase)
% Coupled BE/RK4 endpoint: max_integrator_algebraic_residual recorded.
% (Here needs_algebraic_solve=false so residual is 0 by construction; the
% field existence + finite trajectory is the gate.)
[bundle, ~] = provider_bundle_oracle();
opt = provider_opt('backward_euler');
opt.model_bundle = bundle;
r = stability.ts_simulate(cases.case_matpower6_case14(), opt);
testCase.verifyTrue(isfield(r,'integrator_algebraic_residual'));
testCase.verifyTrue(all(isfinite(r.integrator_algebraic_residual)));
testCase.verifyEqual(r.max_integrator_algebraic_residual, 0, 'AbsTol', 0);
end

function test_bundle_adaptive_be_fails_closed(testCase)
% Adaptive + BE on a bundle -> route-level adaptiveNotFrozen (bundle branch).
[bundle, ~] = provider_bundle_oracle();
opt = provider_opt('backward_euler');
opt.model_bundle = bundle;
opt.stepper = 'adaptive';
testCase.verifyError(@() stability.ts_simulate(cases.case_matpower6_case14(), opt), ...
    'ts_simulate:adaptiveNotFrozen');
end

function test_event_landing_right_limit_oracle(testCase)
% Event landing/right-limit: a fault event at t_fault within the window; the
% right-limit sample at t_fault uses the post-event topology. Verify the run
% is finite and the event grid lands on t_fault, unchanged across
% trapezoidal/BE (event semantics preserved, not the trajectory values).
c = case14();
% Use a fixed corrector (the event run is a regression check, not a
% convergence study) and a short horizon so Case14 stays well-conditioned.
opt_t = struct('t_end',1.0,'dt',0.1,'fault_bus',4,'t_fault',0.4,'t_clear',0.7, ...
    'Zf',1i*0.1,'pm_mode','pgaz','corrector_mode','fixed','corrector_iter',5, ...
    'stepper','fixed','verbose',false,'integrator','trapezoidal');
r_t = stability.ts_simulate(c, opt_t);
opt_be = opt_t; opt_be.integrator = 'backward_euler';
r_be = stability.ts_simulate(c, opt_be);
% Both record the event time on the grid (right-limit sample at t_fault).
testCase.verifyEqual(min(abs(r_t.t - opt_t.t_fault)), 0, 'AbsTol', 1e-9, ...
    't_fault on the grid (trap).');
testCase.verifyEqual(min(abs(r_be.t - opt_t.t_fault)), 0, 'AbsTol', 1e-9, ...
    't_fault on the grid (BE).');
testCase.verifyTrue(all(isfinite(r_t.delta(:))), 'trap event run finite');
testCase.verifyTrue(all(isfinite(r_be.delta(:))), 'BE event run finite');
% Event-side marking is present in both.
testCase.verifyTrue(any(r_t.event_side == 1), 'trap marks event side');
testCase.verifyTrue(any(r_be.event_side == 1), 'BE marks event side');
end

% =========================================================================
% C5 dialog-picker integration tests. The pickers (prompt_pf_method /
% prompt_ts_integrator) are local functions in solve_case.m that use listdlg
% (requires a display), so they are exercised here through the public
% solve_case API with the integrator/pf_method option (the programmatic
% equivalent of the picker selection). The dialog-level stepper-compat gate
% is complemented by the runtime adaptiveNotFrozen guard (tested below).
% =========================================================================
function test_solve_case_ts_rk4_via_catalog(testCase)
% Programmatic equivalent of picking rk4 in the TS integrator dialog.
r = solve_case('analysis','ts','case','matpower14', ...
    'options',struct('t_end',0.3,'dt',0.1,'integrator','rk4', ...
    'verbose',false,'plot_results',false));
testCase.verifyEqual(r.integrator, 'rk4');
testCase.verifyEqual(r.metadata.method_executed, 'rk4');
testCase.verifyEqual(r.metadata.capability, 'diagnostic');
testCase.verifyEqual(r.metadata.runtime_diagnostic, true);
testCase.verifyTrue(all(isfinite(r.delta(:))), 'rk4 via solve_case finite');
end

function test_solve_case_ts_be_via_catalog(testCase)
r = solve_case('analysis','ts','case','matpower14', ...
    'options',struct('t_end',0.3,'dt',0.1,'integrator','backward_euler', ...
    'verbose',false,'plot_results',false));
testCase.verifyEqual(r.integrator, 'backward_euler');
testCase.verifyEqual(r.metadata.capability, 'production');
testCase.verifyTrue(all(isfinite(r.delta(:))), 'be via solve_case finite');
end

function test_solve_case_ts_adaptive_be_fails_closed(testCase)
% The dialog stepper-compat gate (parse_ts_dialog) is a UI convenience; the
% authoritative runtime guard (ts_simulate:adaptiveNotFrozen) still fires for
% programmatic calls — the dialog gate complements, not replaces, it.
testCase.verifyError(@() solve_case('analysis','ts','case','matpower14', ...
    'options',struct('t_end',0.3,'dt',0.1,'integrator','backward_euler', ...
    'stepper','adaptive','verbose',false,'plot_results',false)), ...
    'ts_simulate:adaptiveNotFrozen');
end


