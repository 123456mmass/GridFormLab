function tests = test_opf()
%TEST_OPF Unit tests for Optimal Power Flow / Economic Dispatch.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_economic_dispatch_saadat_7_4(testCase)
    case_data = case_saadat_opf_example_7_4();
    result = economic_dispatch_opf(case_data, struct('verbose', false, 'plot_results', false));
    testCase.verifyTrue(result.converged, 'OPF should converge on Saadat 7.4');
    testCase.verifyEqual(sum(result.P_generation_MW), result.P_demand_MW, 'AbsTol', 1e-4, ...
        'Generation must equal demand');
    testCase.verifyGreaterThan(result.total_cost, 0);
end

function test_incremental_cost_equality(testCase)
    case_data = case_saadat_opf_example_7_4();
    result = economic_dispatch_opf(case_data, struct('verbose', false, 'plot_results', false));
    free_gens = result.active_limits == "free";
    if sum(free_gens) > 1
        ic_vals = result.incremental_cost(free_gens);
        testCase.verifyEqual(max(ic_vals) - min(ic_vals), 0, 'AbsTol', 1e-3, ...
            'Free generators should have equal incremental costs');
    end
end

function test_generator_limits_respected(testCase)
    case_data = case_saadat_opf_example_7_4();
    result = economic_dispatch_opf(case_data, struct('verbose', false, 'plot_results', false));
    testCase.verifyTrue(all(result.P_generation_MW >= result.P_min_MW - 1e-4));
    testCase.verifyTrue(all(result.P_generation_MW <= result.P_max_MW + 1e-4));
end

function test_total_cost_positive(testCase)
    case_data = case_saadat_opf_example_7_4();
    result = economic_dispatch_opf(case_data, struct('verbose', false, 'plot_results', false));
    testCase.verifyGreaterThan(result.total_cost, 0);
    for i = 1:numel(result.generator_cost)
        testCase.verifyGreaterThan(result.generator_cost(i), 0, ...
            sprintf('Generator %d cost should be positive', i));
    end
end

function test_no_cost_data_errors(testCase)
    bad_case = struct('system_name', 'bad', 'opf_data', struct('cost', [], 'P_demand_MW', 100));
    testCase.verifyError(@() economic_dispatch_opf(bad_case), '');
end
