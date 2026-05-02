function tests = test_cpf()
%TEST_CPF Unit tests for Continuation Power Flow solvers.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_load_scaling_5bus(testCase)
    case_data = case_ieee5bus();
    opts = struct('verbose', false, 'plot_results', false, 'target_bus', 5, ...
        'lambda_step', 0.1, 'lambda_max', 2.0);
    result = cpf_load_scaling(case_data, opts);
    testCase.verifyGreaterThan(numel(result.lambdas), 0, 'Should produce at least some points');
    testCase.verifyGreaterThan(max(result.lambdas), 0.5);
end

function test_predictor_corrector_5bus(testCase)
    case_data = case_ieee5bus();
    opts = struct('verbose', false, 'plot_results', false, 'target_bus', 5, ...
        'lambda_step', 0.1, 'lambda_max', 2.0);
    result = cpf_predictor_corrector(case_data, opts);
    testCase.verifyGreaterThan(numel(result.lambdas), 0);
    testCase.verifyGreaterThan(max(result.lambdas), 0.5);
end

function test_predictor_corrector_14bus(testCase)
    case_data = case_ieee14bus();
    opts = struct('verbose', false, 'plot_results', false, 'target_bus', 14, ...
        'lambda_step', 0.05, 'lambda_max', 1.5, 'max_steps', 100);
    result = cpf_predictor_corrector(case_data, opts);
    testCase.verifyGreaterThan(numel(result.lambdas), 0);
end

function test_voltage_decreases_with_lambda(testCase)
    case_data = case_ieee5bus();
    opts = struct('verbose', false, 'plot_results', false, 'target_bus', 5, ...
        'lambda_step', 0.05, 'lambda_max', 2.0);
    result = cpf_load_scaling(case_data, opts);
    if numel(result.target_voltage) > 2
        testCase.verifyLessThanOrEqual(result.target_voltage(end), result.target_voltage(1) + 0.1, ...
            'Voltage should generally decrease under load scaling');
    end
end
