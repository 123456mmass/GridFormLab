function tests = test_nr_solver()
%TEST_NR_SOLVER Unit tests for Newton-Raphson power flow solver.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_converges_5bus(testCase)
    case_data = case_ieee5bus();
    result = powerflow_newton_raphson(case_data, struct('verbose', false, 'plot_results', false));
    testCase.verifyTrue(result.converged, 'NR should converge on 5-bus');
    testCase.verifyLessThanOrEqual(result.iterations, 20, 'NR should converge quickly on 5-bus');
end

function test_converges_14bus(testCase)
    case_data = case_ieee14bus();
    result = powerflow_newton_raphson(case_data, struct('verbose', false, 'plot_results', false));
    testCase.verifyTrue(result.converged, 'NR should converge on 14-bus');
    testCase.verifyLessThanOrEqual(result.iterations, 50);
end

function test_converges_30bus(testCase)
    case_data = case_saadat_ieee30bus();
    result = powerflow_newton_raphson(case_data, struct('verbose', false, 'plot_results', false));
    testCase.verifyTrue(result.converged, 'NR should converge on 30-bus');
    testCase.verifyLessThanOrEqual(result.iterations, 100);
end

function test_power_balance(testCase)
    case_data = case_ieee5bus();
    result = powerflow_newton_raphson(case_data, struct('verbose', false, 'plot_results', false));
    testCase.verifyTrue(result.converged);
    total_gen = result.P_total_gen + result.Q_total_gen;
    total_load = result.P_total_load + result.Q_total_load;
    total_loss = result.P_loss_total + result.Q_loss_total;
    testCase.verifyEqual(total_gen, total_load + total_loss, 'AbsTol', 1e-4, ...
        'Total generation must equal load + losses');
end

function test_voltage_magnitudes_valid(testCase)
    case_data = case_ieee5bus();
    result = powerflow_newton_raphson(case_data, struct('verbose', false, 'plot_results', false));
    testCase.verifyTrue(all(result.bus_voltage > 0.5 & result.bus_voltage < 1.5), ...
        'All bus voltages should be in valid range');
end

function test_convergence_monotonic(testCase)
    case_data = case_ieee5bus();
    result = powerflow_newton_raphson(case_data, struct('verbose', false, 'plot_results', false));
    if numel(result.mismatch_history) > 2
        mid = round(numel(result.mismatch_history) / 2);
        last_half = result.mismatch_history(mid:end);
        testCase.verifyTrue(issorted(last_half(end:-1:1)), ...
            'Mismatch should decrease monotonically in final iterations');
    end
end

function test_q_limit_enforcement(testCase)
    case_data = case_saadat_ieee30bus();
    result = powerflow_newton_raphson(case_data, struct('verbose', false, 'plot_results', false, ...
        'enforce_q_limits', true));
    testCase.verifyTrue(result.converged, 'NR with Q-limits should converge on 30-bus');
end

function test_invalid_case_errors(testCase)
    try
        powerflow_newton_raphson(struct());
        testCase.verifyTrue(false, 'Should have thrown an error on empty struct');
    catch
        testCase.verifyTrue(true);
    end
end
