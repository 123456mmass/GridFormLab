function tests = test_validation_gate_logic()
%TEST_VALIDATION_GATE_LOGIC  Strict aggregate gate semantics. Verifies that
%   missing EMF6 / production-dependency / no-Kundur gates, missing metrics,
%   non-converged steps, contract failures, extrapolation, and over-tolerance
%   all force the aggregate to FAIL — never a silent optional pass. A
%   fully-present, all-true gate set passes.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function g = full_pass_gates()
% Phase B: PGAz is a secondary diagnostic only. The required gate set
% excludes all PGAz-dependent fields (pgaz_execution, pgaz_plateau,
% pgaz_comparison). PSAT is the required cross-validation reference.
g = struct();
g.production_dependency = true;
g.no_kundur_acceptance_target = true;
g.regression = true;
g.emf6_no_fault = true;
g.emf6_shared_model = true;
g.case14 = struct('contract',true,'mapping',true,'comparison_grid',true, ...
    'event_grid',true,'sample_alignment',true,'extrapolation_used_false',true, ...
    'psat_execution',true,'ours_convergence',true, ...
    'psat_comparison',true);
g.rts24 = g.case14;
end

function test_all_present_true_passes(testCase)
g = full_pass_gates();
[all_pass, report] = evaluate_validation_gates(g);
testCase.verifyTrue(all_pass, 'All-present all-true must pass.');
testCase.verifyTrue(isempty(report.missing) && isempty(report.false), 'No missing/false gates.');
end

function test_emf6_gate_missing_fails(testCase)
g = full_pass_gates(); g = rmfield(g, 'emf6_no_fault');
[all_pass, report] = evaluate_validation_gates(g);
testCase.verifyFalse(all_pass, 'Missing EMF6 gate must fail.');
testCase.verifyTrue(ismember('emf6_no_fault', report.missing), 'EMF6 reported missing.');
end

function test_production_dependency_missing_fails(testCase)
g = full_pass_gates(); g = rmfield(g, 'production_dependency');
[all_pass, ~] = evaluate_validation_gates(g);
testCase.verifyFalse(all_pass, 'Missing production-dependency gate must fail.');
end

function test_no_kundur_gate_missing_fails(testCase)
g = full_pass_gates(); g = rmfield(g, 'no_kundur_acceptance_target');
[all_pass, ~] = evaluate_validation_gates(g);
testCase.verifyFalse(all_pass, 'Missing no-Kundur gate must fail.');
end

function test_extrapolation_used_fails(testCase)
g = full_pass_gates(); g.case14.extrapolation_used_false = false;
[all_pass, report] = evaluate_validation_gates(g);
testCase.verifyFalse(all_pass, 'Extrapolation used must fail.');
testCase.verifyTrue(ismember('case14.extrapolation_used_false', report.false), 'extrapolation gate reported false.');
end

function test_pgaz_comparison_failure_does_not_fail_aggregate(testCase)
% Phase B: PGAz is a secondary diagnostic only. PGAz comparison failure
% must NOT fail the aggregate gate (PSAT is the required reference).
g = full_pass_gates();
g.case14.pgaz_comparison = false;   % reported, not required
g.case14.pgaz_execution = false;   % reported, not required
g.case14.pgaz_plateau = false;      % reported, not required
[all_pass, report] = evaluate_validation_gates(g);
testCase.verifyTrue(all_pass, 'PGAz diagnostic failures must not fail the aggregate gate.');
testCase.verifyTrue(isempty(report.missing), 'No required gate should be missing.');
end

function test_pgaz_fields_absent_does_not_fail_aggregate(testCase)
% Phase B: a gate struct with NO PGAz fields at all must still pass,
% because PGAz is not part of the required gate set.
g = full_pass_gates();
[all_pass, report] = evaluate_validation_gates(g);
testCase.verifyTrue(all_pass, 'Gate struct without PGAz fields must pass.');
testCase.verifyTrue(~isfield(g.case14, 'pgaz_comparison'), 'pgaz_comparison absent by design.');
end

function test_comparison_grid_invalid_fails(testCase)
g = full_pass_gates(); g.rts24.comparison_grid = false;
[all_pass, ~] = evaluate_validation_gates(g);
testCase.verifyFalse(all_pass, 'Invalid comparison grid must fail.');
end

function test_metric_over_tolerance_fails(testCase)
g = full_pass_gates(); g.case14.psat_comparison = false;
[all_pass, ~] = evaluate_validation_gates(g);
testCase.verifyFalse(all_pass, 'Over-tolerance metric must fail.');
end

function test_nan_gate_value_fails(testCase)
g = full_pass_gates(); g.case14.psat_comparison = NaN;
[all_pass, report] = evaluate_validation_gates(g);
testCase.verifyFalse(all_pass, 'NaN gate value must fail.');
testCase.verifyTrue(ismember('case14.psat_comparison', report.invalid), 'NaN reported invalid.');
end

function test_nested_missing_fails(testCase)
% Phase B: PGAz fields are not required, so removing a REQUIRED (PSAT)
% field must fail. Removing a PGAz field must NOT fail.
g = full_pass_gates();
g.rts24 = rmfield(g.rts24, 'psat_execution');   % required -> must fail
[all_pass, report] = evaluate_validation_gates(g);
testCase.verifyFalse(all_pass, 'Nested missing REQUIRED gate must fail.');
testCase.verifyTrue(ismember('rts24.psat_execution', report.missing), 'nested missing reported.');
end
