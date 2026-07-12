function tests = test_bundle_validation()
%TEST_BUNDLE_VALIDATION  B1 production bundle validation tests.
%   Verifies that ts_simulate calls stability.validate_ts_bundle on every
%   explicit model_bundle AND every model_fn factory result BEFORE
%   run_model_bundle. Malformed bundles must fail closed BEFORE any solver
%   runs (stable error IDs from validate_ts_bundle:* / validate_ts_strategy:*
%   / validate_sssa_model:*).
%
%   Source: project B1 design (docs/project/plans/ibr_interface_foundation.md).
%   Uses a SYNTHETIC plugin (fixtures.synthetic_linear_generator); no +ibr.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function testCase = base_opt()
testCase = struct('t_end',1,'dt',0.02,'fault_bus',4,'t_fault',1.0, ...
    't_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz','corrector_mode','adaptive', ...
    'corrector_iter',10,'max_corrector_iter',10,'verbose',false, ...
    'fault_enabled',true);
end

function test_model_bundle_missing_ts_fail_closed(testCase)
% B1: explicit model_bundle missing bundle.ts must fail BEFORE solving.
c = cases.case_matpower6_case14();
opt = base_opt();
opt.model_bundle = struct('metadata',struct('dispatch','explicit_model_bundle'));
testCase.verifyError(@() stability.ts_simulate(c, opt), ...
    'validate_ts_bundle:missingTs');
end

function test_model_bundle_missing_strategy_fail_closed(testCase)
% B1: bundle.ts missing the strategy field must fail BEFORE solving.
c = cases.case_matpower6_case14();
opt = base_opt();
bundle = fixtures.synthetic_linear_generator(c, opt);
bundle.ts = rmfield(bundle.ts, 'strategy');
opt.model_bundle = bundle;
testCase.verifyError(@() stability.ts_simulate(c, opt), ...
    'validate_ts_bundle:missingTsField');
end

function test_model_bundle_bad_x0_fail_closed(testCase)
% B1: non-finite bundle.ts.x0 must fail BEFORE solving.
c = cases.case_matpower6_case14();
opt = base_opt();
bundle = fixtures.synthetic_linear_generator(c, opt);
bundle.ts.x0 = [inf; nan];
opt.model_bundle = bundle;
testCase.verifyError(@() stability.ts_simulate(c, opt), ...
    'validate_ts_bundle:badX0');
end

function test_model_bundle_bad_y0_fail_closed(testCase)
% B1: non-finite bundle.ts.y0 must fail BEFORE solving.
c = cases.case_matpower6_case14();
opt = base_opt();
bundle = fixtures.synthetic_linear_generator(c, opt);
bundle.ts.y0 = [1; inf; 0; 0];
opt.model_bundle = bundle;
testCase.verifyError(@() stability.ts_simulate(c, opt), ...
    'validate_ts_bundle:badY0');
end

function test_model_bundle_bad_topology_shape_fail_closed(testCase)
% B1: non-square topology matrix must fail BEFORE solving.
c = cases.case_matpower6_case14();
opt = base_opt();
bundle = fixtures.synthetic_linear_generator(c, opt);
bundle.ts.topology.Ypre = [1 2 3; 4 5 6];   % 2x3, non-square
opt.model_bundle = bundle;
testCase.verifyError(@() stability.ts_simulate(c, opt), ...
    'validate_ts_bundle:badTopo');
end

function test_model_bundle_missing_mapping_fail_closed(testCase)
% B1: bundle.ts.mapping missing gen_buses must fail BEFORE solving.
c = cases.case_matpower6_case14();
opt = base_opt();
bundle = fixtures.synthetic_linear_generator(c, opt);
bundle.ts.mapping = rmfield(bundle.ts.mapping, 'gen_buses');
opt.model_bundle = bundle;
testCase.verifyError(@() stability.ts_simulate(c, opt), ...
    'validate_ts_bundle:missingMapping');
end

function test_model_fn_bad_bundle_fail_closed(testCase)
% B1: a model_fn that returns a malformed bundle (missing ts) must fail
% BEFORE solving (factory result is also validated).
c = cases.case_matpower6_case14();
opt = base_opt();
opt.model_fn = @(case_data, o) struct('metadata',struct('dispatch','x'));
testCase.verifyError(@() stability.ts_simulate(c, opt), ...
    'validate_ts_bundle:missingTs');
end

function test_model_bundle_valid_runs(testCase)
% B1: a valid bundle still runs end-to-end (validation passes, then execute).
c = cases.case_matpower6_case14();
opt = base_opt();
bundle = fixtures.synthetic_linear_generator(c, opt);
opt.model_bundle = bundle;
r = stability.ts_simulate(c, opt);
testCase.verifyTrue(all(isfinite(r.delta(:))), 'valid bundle run finite.');
testCase.verifyEqual(r.metadata.dispatch, 'explicit_model_bundle', ...
    'provenance = explicit_model_bundle.');
end
