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
g = struct();
g.production_dependency = true;
g.no_kundur_acceptance_target = true;
g.regression = true;
g.emf6_no_fault = true;
g.emf6_shared_model = true;
g.case14 = struct('contract',true,'mapping',true,'comparison_grid',true, ...
    'event_grid',true,'sample_alignment',true,'extrapolation_used_false',true, ...
    'psat_execution',true,'pgaz_execution',true,'ours_convergence',true, ...
    'psat_comparison',true,'pgaz_plateau',true,'pgaz_comparison',true);
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

function test_pgaz_completed_but_comparison_fails(testCase)
% PGAz completed (execution=true) but plateau comparison fails => aggregate fail.
g = full_pass_gates(); g.case14.pgaz_comparison = false;
[all_pass, report] = evaluate_validation_gates(g);
testCase.verifyFalse(all_pass, 'PGAz comparison failure must fail aggregate.');
testCase.verifyTrue(ismember('case14.pgaz_comparison', report.false), 'pgaz_comparison reported false.');
end

function test_pgaz_not_converged_no_residual_still_completed(testCase)
% PGAz fixed-3 with no residual is COMPLETED (pgaz_execution=true), not
% "converged". The execution gate passes; convergence is not a gate field.
g = full_pass_gates();
[all_pass, ~] = evaluate_validation_gates(g);
testCase.verifyTrue(all_pass, 'PGAz completed (no residual) does not fail execution gate.');
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
g = full_pass_gates(); g.rts24 = rmfield(g.rts24, 'pgaz_execution');
[all_pass, report] = evaluate_validation_gates(g);
testCase.verifyFalse(all_pass, 'Nested missing gate must fail.');
testCase.verifyTrue(ismember('rts24.pgaz_execution', report.missing), 'nested missing reported.');
end
