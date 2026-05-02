function tests = test_gs_solver()
%TEST_GS_SOLVER Unit tests for Gauss-Seidel power flow solver.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_converges_5bus(testCase)
    case_data = case_ieee5bus();
    result = powerflow_gauss_seidel(case_data, struct('verbose', false, 'plot_results', false));
    testCase.verifyTrue(result.converged, 'GS should converge on 5-bus');
end

function test_converges_14bus(testCase)
    case_data = case_ieee14bus();
    result = powerflow_gauss_seidel(case_data, struct('verbose', false, 'plot_results', false, ...
        'max_iter', 500));
    testCase.verifyTrue(result.converged, 'GS should converge on 14-bus');
end

function test_agrees_with_nr(testCase)
    case_data = case_ieee5bus();
    nr = powerflow_newton_raphson(case_data, struct('verbose', false, 'plot_results', false));
    gs = powerflow_gauss_seidel(case_data, struct('verbose', false, 'plot_results', false));
    testCase.verifyTrue(nr.converged && gs.converged);
    max_diff = max(abs(nr.bus_voltage - gs.bus_voltage));
    testCase.verifyLessThan(max_diff, 0.01, 'NR and GS voltages should agree within 0.01 pu');
end

function test_acceleration_factor(testCase)
    case_data = case_ieee5bus();
    r1 = powerflow_gauss_seidel(case_data, struct('verbose', false, 'plot_results', false, ...
        'acceleration', 1.0, 'max_iter', 500));
    r2 = powerflow_gauss_seidel(case_data, struct('verbose', false, 'plot_results', false, ...
        'acceleration', 1.6, 'max_iter', 500));
    testCase.verifyTrue(r1.converged && r2.converged);
    testCase.verifyLessThanOrEqual(r2.iterations, r1.iterations + 50, ...
        'Higher acceleration should not significantly increase iterations');
end
