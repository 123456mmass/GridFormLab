function tests = test_sssa_bundle_dispatch()
%TEST_SSSA_BUNDLE_DISPATCH  B2 SSSA explicit dispatch tests.
%   Verifies multicase_sssa dispatches via mutually-exclusive explicit
%   routes (model_bundle / model_fn / sssa_model), validates the SSSA model
%   via validate_sssa_model, executes via multimachine_ssa, and records
%   provenance. Any pair of explicit routes fails closed.
%
%   Source: project B2 design. Uses SYNTHETIC fixtures; no +ibr.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_sssa_model_dispatch(testCase)
% opt.sssa_model alone => execute via multimachine_ssa.
bundle = fixtures.synthetic_sssa_bundle();
opt = struct('sssa_model', bundle.sssa.model);
r = stability.multicase_sssa(struct(), opt);
testCase.verifyTrue(all(isfinite(r.eigenvalues)), 'finite eigenvalues.');
testCase.verifyEqual(r.metadata.dispatch, 'explicit_sssa_model', ...
    'provenance = explicit_sssa_model.');
end

function test_model_fn_dispatch(testCase)
% opt.model_fn (factory returns bundle) => use bundle.sssa.model.
opt = struct('model_fn', @fixtures.synthetic_sssa_bundle);
r = stability.multicase_sssa(struct(), opt);
testCase.verifyTrue(all(isfinite(r.eigenvalues)), 'finite eigenvalues.');
testCase.verifyEqual(r.metadata.dispatch, 'explicit_model_fn', ...
    'provenance = explicit_model_fn.');
end

function test_model_bundle_dispatch(testCase)
% opt.model_bundle (pre-built) => use bundle.sssa.model.
bundle = fixtures.synthetic_sssa_bundle();
opt = struct('model_bundle', bundle);
r = stability.multicase_ssa(struct(), opt);
testCase.verifyTrue(all(isfinite(r.eigenvalues)), 'finite eigenvalues.');
testCase.verifyEqual(r.metadata.dispatch, 'explicit_model_bundle', ...
    'provenance = explicit_model_bundle.');
end

function test_bundle_and_model_fn_fail_closed(testCase)
% model_bundle + model_fn => exclusiveDispatch.
bundle = fixtures.synthetic_sssa_bundle();
opt = struct('model_bundle', bundle, 'model_fn', @fixtures.synthetic_sssa_bundle);
testCase.verifyError(@() stability.multicase_sssa(struct(), opt), ...
    'multicase_ssa:exclusiveDispatch');
end

function test_bundle_and_sssa_model_fail_closed(testCase)
% model_bundle + sssa_model => exclusiveDispatch.
bundle = fixtures.synthetic_sssa_bundle();
opt = struct('model_bundle', bundle, 'sssa_model', bundle.sssa.model);
testCase.verifyError(@() stability.multicase_ssa(struct(), opt), ...
    'multicase_ssa:exclusiveDispatch');
end

function test_mfn_and_sssa_model_fail_closed(testCase)
% model_fn + sssa_model => exclusiveDispatch.
bundle = fixtures.synthetic_sssa_bundle();
opt = struct('model_fn', @fixtures.synthetic_sssa_bundle, ...
    'sssa_model', bundle.sssa.model);
testCase.verifyError(@() stability.multicase_ssa(struct(), opt), ...
    'multicase_ssa:exclusiveDispatch');
end

function test_analytic_eigenvalue_oracle(testCase)
% The synthetic linear model has analytic eigenvalues +/- i (undamped swing).
% Verify the SSSA result matches to a tight tolerance.
bundle = fixtures.synthetic_sssa_bundle();
opt = struct('sssa_model', bundle.sssa.model);
r = stability.multicase_ssa(struct(), opt);
ev = sort(r.eigenvalues, 'ComparisonMethod','real');
% Analytic: eig([0 1; -1 0]) = [+1i; -1i].
testCase.verifyEqual(real(ev(1)), 0, 'AbsTol', 1e-9, 'first ev real ~0.');
testCase.verifyEqual(real(ev(2)), 0, 'AbsTol', 1e-9, 'second ev real ~0.');
testCase.verifyEqual(abs(imag(ev(1))), 1, 'AbsTol', 1e-9, 'first ev imag ~+/-1.');
end

function test_built_in_string_unchanged(testCase)
% When no explicit route supplied, built-in string chain runs (unchanged).
% Use a real Padiyar case via the built-in path.
c = cases.case_padiyar_two_area_4m_avr();
opt = struct('model','padiyar_1_1_manual','excitation','manual');
r = stability.multicase_ssa(c, opt);
testCase.verifyTrue(all(isfinite(r.eigenvalues)), 'built-in finite eigenvalues.');
end
