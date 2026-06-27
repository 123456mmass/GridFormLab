function summary = run_powerflow_tests()
%RUN_POWERFLOW_TESTS Automated regression tests for the n-bus toolkit.
%   Includes Hadi Saadat textbook benchmarks from Chapters 6 and 7.

pf_init_paths();

tests = {};

tests{end + 1} = @test_ieee5_nr_regression;
tests{end + 1} = @test_ieee5_gs_matches_nr;
tests{end + 1} = @test_ieee14_nr_regression;
tests{end + 1} = @test_ieee300_nr_regression;
tests{end + 1} = @test_saadat_example_6_7;
tests{end + 1} = @test_saadat_example_6_8;
tests{end + 1} = @test_saadat_ieee30_selected_values;
tests{end + 1} = @test_saadat_opf_examples;
tests{end + 1} = @test_saadat_ieee30_ac_opf;
tests{end + 1} = @test_saadat_reference_catalog;
tests{end + 1} = @test_q_limit_switching;
tests{end + 1} = @test_cpf_methods;

passed = 0;
failed = 0;
failures = {};

fprintf('============================================================\n');
fprintf('POWER FLOW AUTOMATED TESTS\n');
fprintf('============================================================\n');

for i = 1:numel(tests)
    test_func = tests{i};
    test_name = func2str(test_func);
    try
        test_func();
        fprintf('PASS  %s\n', test_name);
        passed = passed + 1;
    catch err
        fprintf('FAIL  %s: %s\n', test_name, err.message);
        failed = failed + 1;
        failures{end + 1, 1} = struct('name', test_name, 'message', err.message); %#ok<AGROW>
    end
end

summary = struct('passed', passed, 'failed', failed, 'failures', {failures});
fprintf('============================================================\n');
fprintf('Tests passed: %d, failed: %d\n', passed, failed);
fprintf('============================================================\n');

if failed > 0
    error('run_powerflow_tests:Failed', '%d power-flow test(s) failed.', failed);
end
end

function test_ieee5_nr_regression()
options = struct('max_iter', 20, 'tolerance', 1e-6, 'plot_results', false, 'verbose', false);
results = powerflow_newton_raphson(case_ieee5bus(), options);
assert(results.converged, 'IEEE 5-bus NR did not converge.');
assert_equal(results.iterations, 4, 'IEEE 5-bus NR iteration count changed.');
assert_close(results.P_loss_total, 0.061474, 5e-6, 'IEEE 5-bus P loss changed.');
end

function test_ieee5_gs_matches_nr()
nr_options = struct('max_iter', 20, 'tolerance', 1e-6, 'plot_results', false, 'verbose', false);
gs_options = struct('max_iter', 300, 'tolerance', 1e-6, 'acceleration', 1.4, 'plot_results', false, 'verbose', false);
nr = powerflow_newton_raphson(case_ieee5bus(), nr_options);
gs = powerflow_gauss_seidel(case_ieee5bus(), gs_options);
assert(gs.converged, 'IEEE 5-bus GS did not converge.');
assert_close(max(abs(gs.bus_voltage - nr.bus_voltage)), 0, 1e-6, 'IEEE 5-bus GS voltage differs from NR.');
end

function test_ieee14_nr_regression()
options = struct('max_iter', 30, 'tolerance', 1e-6, 'plot_results', false, 'verbose', false);
results = powerflow_newton_raphson(case_ieee14bus(), options);
assert(results.converged, 'IEEE 14-bus NR did not converge.');
assert_close(results.P_loss_total, 0.133933, 5e-6, 'IEEE 14-bus P loss changed.');
end

function test_ieee300_nr_regression()
case_data = case_ieee300bus();
options = struct('max_iter', 60, 'tolerance', 1e-8, 'plot_results', false, 'verbose', false);
results = powerflow_newton_raphson(case_data, options);
ref = case_data.reference_solution;

assert(results.converged, 'IEEE 300-bus NR did not converge.');
assert_equal(results.metadata.num_buses, ref.num_buses, 'IEEE 300-bus bus count changed.');
assert_equal(results.metadata.num_lines, ref.num_lines, 'IEEE 300-bus line count changed.');
assert_close(results.P_total_load, ref.total_P_load, 1e-12, 'IEEE 300-bus total P load changed.');
assert_close(results.Q_total_load, ref.total_Q_load, 1e-12, 'IEEE 300-bus total Q load changed.');

for i = 1:numel(ref.selected_bus_ids)
    bus_i = ref.selected_bus_ids(i);
    idx = find(results.external_bus_ids == bus_i, 1, 'first');
    assert(~isempty(idx), sprintf('IEEE 300-bus reference bus %g was not found.', bus_i));
    assert_close(results.bus_voltage(idx), ref.selected_voltage(i), 3e-4, ...
        sprintf('IEEE 300-bus voltage mismatch at bus %g.', bus_i));
    assert_close(results.bus_angle_deg(idx), ref.selected_angle_deg(i), 5e-2, ...
        sprintf('IEEE 300-bus angle mismatch at bus %g.', bus_i));
end
end

function test_saadat_example_6_7()
case_data = case_saadat_example_6_7();
options = struct('max_iter', 500, 'tolerance', 1e-8, 'acceleration', 1.0, 'plot_results', false, 'verbose', false);
results = powerflow_gauss_seidel(case_data, options);
ref = case_data.reference_solution;
assert(results.converged, 'Saadat Example 6.7 GS did not converge.');
assert_close(results.bus_voltage(2), ref.bus_voltage(2), 2e-5, 'Saadat 6.7 V2 mismatch.');
assert_close(results.bus_voltage(3), ref.bus_voltage(3), 2e-5, 'Saadat 6.7 V3 mismatch.');
assert_close(results.bus_angle_deg(2), ref.bus_angle_deg(2), 2e-3, 'Saadat 6.7 angle 2 mismatch.');
assert_close(results.bus_angle_deg(3), ref.bus_angle_deg(3), 2e-3, 'Saadat 6.7 angle 3 mismatch.');
assert_close(results.P_generation(1), ref.slack_P_generation, 5e-4, 'Saadat 6.7 slack P mismatch.');
assert_close(results.Q_generation(1), ref.slack_Q_generation, 5e-4, 'Saadat 6.7 slack Q mismatch.');
end

function test_saadat_example_6_8()
case_data = case_saadat_example_6_8();
options = struct('max_iter', 500, 'tolerance', 1e-8, 'acceleration', 1.0, 'plot_results', false, 'verbose', false);
results = powerflow_gauss_seidel(case_data, options);
ref = case_data.reference_solution;
assert(results.converged, 'Saadat Example 6.8 GS did not converge.');
assert_close(results.bus_voltage(2), ref.bus_voltage(2), 2e-5, 'Saadat 6.8 V2 mismatch.');
assert_close(results.bus_voltage(3), ref.bus_voltage(3), 1e-8, 'Saadat 6.8 V3 mismatch.');
assert_close(results.bus_angle_deg(2), ref.bus_angle_deg(2), 3e-3, 'Saadat 6.8 angle 2 mismatch.');
assert_close(results.bus_angle_deg(3), ref.bus_angle_deg(3), 2e-3, 'Saadat 6.8 angle 3 mismatch.');
assert_close(results.P_generation(1), ref.slack_P_generation, 5e-4, 'Saadat 6.8 slack P mismatch.');
assert_close(results.Q_generation(1), ref.slack_Q_generation, 5e-4, 'Saadat 6.8 slack Q mismatch.');
assert_close(results.Q_generation(3), ref.pv_Q_generation, 5e-4, 'Saadat 6.8 PV Q mismatch.');
end

function test_saadat_ieee30_selected_values()
case_data = case_saadat_ieee30bus();
options = struct('max_iter', 50, 'tolerance', 1e-6, 'plot_results', false, 'verbose', false);
results = powerflow_newton_raphson(case_data, options);
ref = case_data.reference_solution;
assert(results.converged, 'Saadat IEEE 30-bus NR did not converge.');
for i = 1:numel(ref.selected_bus_ids)
    bus_i = ref.selected_bus_ids(i);
    assert_close(results.bus_voltage(bus_i), ref.selected_voltage(i), 3e-3, sprintf('Saadat IEEE30 voltage bus %d mismatch.', bus_i));
    assert_close(results.bus_angle_deg(bus_i), ref.selected_angle_deg(i), 5e-2, sprintf('Saadat IEEE30 angle bus %d mismatch.', bus_i));
end
assert_close(results.P_generation(1), ref.slack_P_generation, 1e-3, 'Saadat IEEE30 slack P mismatch.');
assert_close(results.Q_generation(1), ref.slack_Q_generation, 3e-3, 'Saadat IEEE30 slack Q mismatch.');
assert_close(results.P_total_gen, ref.total_P_generation, 1e-3, 'Saadat IEEE30 total P generation mismatch.');
end

function test_saadat_opf_examples()
cases = {@case_saadat_opf_example_7_4, @case_saadat_opf_example_7_5, @case_saadat_opf_example_7_6};
for k = 1:numel(cases)
    case_data = cases{k}();
    results = economic_dispatch_opf(case_data, struct('verbose', false, 'plot_results', false));
    ref = case_data.reference_solution;
    assert(results.converged, sprintf('Saadat OPF case %d did not converge.', k));
    assert_close(results.lambda, ref.lambda, 1e-8, sprintf('Saadat OPF case %d lambda mismatch.', k));
    assert_close(max(abs(results.P_generation_MW - ref.P_generation_MW)), 0, 1e-8, sprintf('Saadat OPF case %d dispatch mismatch.', k));
    assert_close(results.total_cost, ref.total_cost, 1e-8, sprintf('Saadat OPF case %d total cost mismatch.', k));
end
end

function test_saadat_ieee30_ac_opf()
case_data = case_saadat_ieee30bus();
options = struct('max_iter', 300, 'tolerance', 1e-6, 'plot_results', false, 'verbose', false);
results = ac_optimal_power_flow(case_data, options);

assert(results.converged, 'Saadat IEEE 30-bus AC OPF did not converge.');
assert_close(results.max_power_balance_mismatch, 0, 1e-6, 'Saadat IEEE30 AC OPF power balance mismatch too large.');
assert(all(results.bus_voltage >= results.V_min - 1e-6), 'Saadat IEEE30 AC OPF violated a voltage lower bound.');
assert(all(results.bus_voltage <= results.V_max + 1e-6), 'Saadat IEEE30 AC OPF violated a voltage upper bound.');
assert(all(results.P_generation_MW >= results.P_min_MW - 1e-5), 'Saadat IEEE30 AC OPF violated generator Pmin.');
assert(all(results.P_generation_MW <= results.P_max_MW + 1e-5), 'Saadat IEEE30 AC OPF violated generator Pmax.');
assert(all(results.Q_generation_MVAr >= results.Q_min_MVAr - 1e-5), 'Saadat IEEE30 AC OPF violated generator Qmin.');
assert(all(results.Q_generation_MVAr <= results.Q_max_MVAr + 1e-5), 'Saadat IEEE30 AC OPF violated generator Qmax.');
assert(~isempty(results.line_loading_percent), 'Saadat IEEE30 AC OPF should report line loading.');
assert(max(results.line_loading_percent) <= 100 + 1e-5, 'Saadat IEEE30 AC OPF violated a line MVA limit.');
assert_close(sum(results.P_generation_MW), 296.335960, 5e-3, 'Saadat IEEE30 AC OPF total generation changed.');
assert_close(results.total_cost, 4240.677441, 5e-3, 'Saadat IEEE30 AC OPF objective changed.');
end

function test_saadat_reference_catalog()
catalog = saadat_reference_catalog();
assert(numel(catalog) >= 9, 'Saadat reference catalog should include PF and OPF references.');
bus_counts = [catalog.bus_count];
assert(any(bus_counts == 30), 'Saadat catalog should include IEEE 30-bus reference.');
assert(any(strcmp({catalog.type}, 'OPF')), 'Saadat catalog should include OPF references.');
end

function test_q_limit_switching()
case_data = case_saadat_example_6_8();
case_data.bus_data(:, 9:10) = 0;
case_data.bus_data(:, 11) = -Inf;
case_data.bus_data(:, 12) = Inf;
case_data.bus_data(3, 11) = -1.0;
case_data.bus_data(3, 12) = 1.0;

options = struct('max_iter', 30, 'tolerance', 1e-8, 'plot_results', false, 'verbose', false);
results = powerflow_newton_raphson(case_data, options);
assert(results.converged, 'Q-limit switching case did not converge.');
assert(~isempty(results.q_limit_switching.events), 'Expected PV-to-PQ Q-limit event was not recorded.');
assert_equal(results.bus_type(3), 3, 'Bus 3 should switch from PV to PQ.');
assert_close(results.Q_generation(3), 1.0, 1e-7, 'Bus 3 Q generation was not fixed at Qmax.');
end

function test_cpf_methods()
options = struct('plot_results', false, 'verbose', false, 'tolerance', 1e-6, ...
    'target_bus', 5, 'lambda_step', 0.1, 'lambda_max', 0.5, 'max_steps', 10, 'min_voltage', 0.65);
cpf1 = cpf_load_scaling(case_ieee5bus(), options);
cpf2 = cpf_predictor_corrector(case_ieee5bus(), options);
assert(numel(cpf1.lambdas) >= 2, 'Load-scaling CPF did not produce enough points.');
assert(numel(cpf2.lambdas) >= 2, 'Predictor-corrector CPF did not produce enough points.');
assert(all(diff(cpf1.lambdas) >= -1e-12), 'Load-scaling CPF lambda did not progress monotonically.');

options30 = struct('plot_results', false, 'verbose', false, 'tolerance', 1e-6, ...
    'target_bus', 30, 'lambda_step', 0.05, 'lambda_max', 3.0, 'max_steps', 120, ...
    'min_voltage', 0.30, 'max_corrector_iter', 16);
cpf30 = cpf_predictor_corrector(case_saadat_ieee30bus(), options30);
assert(cpf30.nose_detected, 'Predictor-corrector CPF did not detect the IEEE 30-bus nose point.');
assert(any(diff(cpf30.lambdas) < -1e-6), 'Predictor-corrector CPF did not trace the lower branch after the nose.');
end

function assert_close(actual, expected, tolerance, message)
if abs(actual - expected) > tolerance
    error('%s Expected %.10g, got %.10g, tolerance %.3g.', message, expected, actual, tolerance);
end
end

function assert_equal(actual, expected, message)
if ~isequal(actual, expected)
    error('%s Expected %s, got %s.', message, mat2str(expected), mat2str(actual));
end
end
