function tests = test_dynamic_accuracy_benchmark_catalog()
%TEST_DYNAMIC_ACCURACY_BENCHMARK_CATALOG Guardrails for accuracy claims.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_catalog_contains_only_model_reconstruction_benchmarks(testCase)
    c = cases.dynamic_accuracy_benchmark_catalog();
    ids = string({c.id});
    testCase.verifyFalse(any(ids == "kundur_e123"), ...
        'Kundur E12.3 remains a reconstruction work item, not a passed benchmark.');
    testCase.verifyTrue(any(ids == "sauer_pai_e83"));
    testCase.verifyFalse(any(contains(lower(ids), "au14") | contains(lower(ids), "state")), ...
        'Published state-space-only cases must not be counted as model accuracy benchmarks.');
end

function test_all_claimed_benchmarks_meet_tolerance(testCase)
    c = cases.dynamic_accuracy_benchmark_catalog();
    for k = 1:numel(c)
        testCase.verifyLessThanOrEqual(c(k).max_error_percent, c(k).tolerance_percent, ...
            sprintf('%s exceeds declared tolerance', c(k).name));
    end
end
