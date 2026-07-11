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

function test_singular_jacobian_returns_nonconverged(testCase)
% Phase B failure semantics: an islanded bus produces a singular Ybus and
% hence a singular Jacobian. The solver must return a structured non-converged
% result (NOT a plausible result, NOT a silent NaN propagation).
    c = struct('system_name','islanded', ...
        'base_values',struct('S_base_MVA',100,'V_base_kV',1,'frequency_Hz',60), ...
        'bus_data',[1 1 1.0 0 0 0 0 0 0 0 -Inf Inf; 2 3 1.0 0 0 0 1 0.5 0 0 -Inf Inf], ...
        'line_data',[1 1 0.001 0.01 0 1 0]);
    c = cases.standardize_case(c);
    r = powerflow_newton_raphson(c, struct('verbose',false,'plot_results',false,'enforce_q_limits',false));
    testCase.verifyFalse(r.converged, 'Islanded bus must not converge.');
    testCase.verifyEqual(r.reason, 'singular_jacobian', 'Exact reason required.');
    testCase.verifyTrue(isfield(r,'finite_status'), 'finite_status field required.');
    testCase.verifyTrue(isfield(r,'max_mismatch'), 'max_mismatch field required.');
    testCase.verifyTrue(isfield(r,'iterations'), 'iterations field required.');
    testCase.verifyGreaterThanOrEqual(r.iterations, 1, 'At least one iteration must run.');
end

function test_nonconverged_max_iter_returns_reason(testCase)
% Phase B failure semantics: max-iteration exhaustion returns reason='max_iterations'.
    c = case_ieee5bus();
    r = powerflow_newton_raphson(c, struct('verbose',false,'plot_results',false,'max_iter',1));
    testCase.verifyFalse(r.converged, 'max_iter=1 must not converge.');
    testCase.verifyEqual(r.reason, 'max_iterations', 'Exact reason required.');
    testCase.verifyEqual(r.finite_status, 'all_finite', 'State is finite.');
    testCase.verifyTrue(isfield(r,'max_mismatch'), 'max_mismatch field required.');
    testCase.verifyLessThanOrEqual(r.iterations, 1, 'iterations must respect max_iter cap.');
end

function test_converged_has_reason_converged(testCase)
% Phase B failure semantics: the converged path populates the new fields
% additively (reason='converged', finite_status='all_finite', max_mismatch finite).
    c = case_ieee5bus();
    r = powerflow_newton_raphson(c, struct('verbose',false,'plot_results',false));
    testCase.verifyTrue(r.converged, '5-bus must converge.');
    testCase.verifyEqual(r.reason, 'converged', 'Converged reason required.');
    testCase.verifyEqual(r.finite_status, 'all_finite', 'Converged state is finite.');
    testCase.verifyTrue(isfield(r,'max_mismatch'), 'max_mismatch field required.');
    testCase.verifyTrue(isfinite(r.max_mismatch), 'max_mismatch must be finite.');
end
