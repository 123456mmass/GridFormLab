function tests = test_bundle_adaptive()
%TEST_BUNDLE_ADAPTIVE  B9 bundle fixed/adaptive routing tests.
%   Verifies run_model_bundle dispatches via opt.stepper:
%     - absent or 'fixed' => fixed-step loop (default)
%     - 'adaptive' => ts_adaptive_driver (canonical, shared kernel+events)
%   Default stays FIXED. Explicit adaptive works end-to-end.
%
%   Source: project B9 design. Uses SYNTHETIC fixtures over IEEE14; no +ibr.
%   Device params are ASSUMED_DIAGNOSTIC (excluded from production acceptance).

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function testCase = base_opt()
testCase = struct('t_end',1.5,'dt',0.02,'fault_bus',4,'t_fault',1.0, ...
    't_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz','corrector_mode','adaptive', ...
    'corrector_iter',10,'max_corrector_iter',10,'verbose',false, ...
    'fault_enabled',true);
end

function test_bundle_default_fixed(testCase)
% Default (no stepper) => fixed-step. Result has no adaptive fields.
c = cases.case_matpower6_case14();
opt = base_opt();
bundle = fixtures.synthetic_linear_generator(c, opt);
opt.model_bundle = bundle;
r = stability.ts_simulate(c, opt);
testCase.verifyTrue(all(isfinite(r.delta(:))), 'finite fixed trajectory.');
testCase.verifyFalse(isfield(r,'dt_history'), 'default fixed has no dt_history.');
testCase.verifyEqual(r.metadata.dispatch, 'explicit_model_bundle', ...
    'provenance preserved.');
end

function test_bundle_explicit_fixed(testCase)
% opt.stepper='fixed' => fixed-step.
c = cases.case_matpower6_case14();
opt = base_opt();
opt.stepper = 'fixed';
bundle = fixtures.synthetic_linear_generator(c, opt);
opt.model_bundle = bundle;
r = stability.ts_simulate(c, opt);
testCase.verifyTrue(all(isfinite(r.delta(:))), 'finite fixed trajectory.');
testCase.verifyFalse(isfield(r,'dt_history'), 'fixed has no dt_history.');
end

function test_bundle_adaptive_runs(testCase)
% opt.stepper='adaptive' => ts_adaptive_driver; adaptive fields present.
c = cases.case_matpower6_case14();
opt = base_opt();
opt.stepper = 'adaptive';
opt.dt_min = 1e-4; opt.dt_max = 0.05;
opt.atol_x = 1e-6; opt.rtol_x = 1e-4;
opt.atol_y = 1e-5; opt.rtol_y = 1e-4;
bundle = fixtures.synthetic_linear_generator(c, opt);
opt.model_bundle = bundle;
r = stability.ts_simulate(c, opt);
testCase.verifyTrue(all(isfinite(r.delta(:))), 'finite adaptive trajectory.');
testCase.verifyTrue(isfield(r,'dt_history'), 'adaptive has dt_history.');
testCase.verifyEqual(r.stepper, 'adaptive', 'stepper=adaptive.');
testCase.verifyTrue(r.accepted_steps >= 1, 'at least one accepted step.');
end

function test_bundle_adaptive_provenance(testCase)
% Adaptive bundle preserves dispatch provenance.
c = cases.case_matpower6_case14();
opt = base_opt();
opt.stepper = 'adaptive';
opt.dt_min = 1e-4; opt.dt_max = 0.05;
bundle = fixtures.synthetic_linear_generator(c, opt);
opt.model_bundle = bundle;
r = stability.ts_simulate(c, opt);
testCase.verifyEqual(r.metadata.dispatch, 'explicit_model_bundle', ...
    'adaptive provenance preserved.');
end

function test_bundle_adaptive_event_landing(testCase)
% Adaptive bundle with a fault event lands the event and records diagnostics.
c = cases.case_matpower6_case14();
opt = base_opt();
opt.stepper = 'adaptive';
opt.dt_min = 1e-4; opt.dt_max = 0.05;
opt.atol_x = 1e-6; opt.rtol_x = 1e-4;
opt.atol_y = 1e-5; opt.rtol_y = 1e-4;
bundle = fixtures.synthetic_linear_generator(c, opt);
opt.model_bundle = bundle;
r = stability.ts_simulate(c, opt);
% Should land on t_fault=1.0 and t_clear=1.1 within event_tol.
t_arr = r.t(:)';
testCase.verifyTrue(any(abs(t_arr - opt.t_fault) < 1e-10), 'lands t_fault.');
testCase.verifyTrue(any(abs(t_arr - opt.t_clear) < 1e-10), 'lands t_clear.');
testCase.verifyTrue(numel(r.event_diagnostics) >= 2, 'event diagnostics recorded.');
end
