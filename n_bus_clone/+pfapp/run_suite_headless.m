function suite = run_suite_headless(app)
%RUN_SUITE_HEADLESS Run NR + GS + CPF-LS + CPF-PC on IEEE 5-bus.

case_data = case_ieee5bus();
nr_options = struct('max_iter', app.max_iter_field.Value, 'tolerance', app.tolerance_field.Value, ...
    'plot_results', false, 'verbose', false, 'enforce_q_limits', app.q_limit_checkbox.Value);
gs_options = struct('max_iter', max(300, app.max_iter_field.Value), 'tolerance', app.tolerance_field.Value, ...
    'acceleration', app.accel_field.Value, 'plot_results', false, 'verbose', false);
cpf_opts = pfapp.build_cpf_options(app, case_data, 'CPF Predictor-Corrector');

suite = struct();
suite.case_data = case_data;
suite.newton_raphson = powerflow_newton_raphson(case_data, nr_options);
suite.gauss_seidel = powerflow_gauss_seidel(case_data, gs_options);
suite.cpf_load_scaling = cpf_load_scaling(case_data, cpf_opts);
suite.cpf_predictor_corrector = cpf_predictor_corrector(case_data, cpf_opts);
end
