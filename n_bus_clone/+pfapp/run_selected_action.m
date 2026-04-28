function app = run_selected_action(app, fig)
%RUN_SELECTED_ACTION Main Run button dispatch. Returns modified app.

pfapp.set_busy(app, true);
pfapp.start_progress(app, fig, 'Running power-flow solver ...', 'Please wait while the selected method is solving.');
cleanup = onCleanup(@() pfapp.set_busy(app, false));
try
    case_data = pfapp.load_selected_case(app);
    app.last_case_data = case_data;
    method = app.method_dropdown.Value;
    pfapp.append_log(app, sprintf('Running %s on %s ...', method, case_data.system_name));

    switch method
        case 'Newton-Raphson'
            options = pfapp.common_options(app.tolerance_field.Value);
            options.max_iter = app.max_iter_field.Value;
            options.enforce_q_limits = app.q_limit_checkbox.Value;
            result = powerflow_newton_raphson(case_data, options);
            app.last_result = result;
            app.last_cpf = [];
            app.last_suite = [];
            app.last_opf = [];
            pfapp.show_powerflow_result(app, result, app.tolerance_field.Value);
            pfapp.append_log(app, pfapp.powerflow_summary_line(result));

        case 'Gauss-Seidel'
            options = pfapp.common_options(app.tolerance_field.Value);
            options.max_iter = app.max_iter_field.Value;
            options.acceleration = app.accel_field.Value;
            result = powerflow_gauss_seidel(case_data, options);
            app.last_result = result;
            app.last_cpf = [];
            app.last_suite = [];
            app.last_opf = [];
            pfapp.show_powerflow_result(app, result, app.tolerance_field.Value);
            pfapp.append_log(app, pfapp.powerflow_summary_line(result));

        case 'CPF Load Scaling'
            options = pfapp.build_cpf_options(app, case_data, 'CPF Load Scaling');
            cpf = cpf_load_scaling(case_data, options);
            app.last_result = [];
            app.last_cpf = cpf;
            app.last_suite = [];
            app.last_opf = [];
            pfapp.show_cpf_result(app, cpf);
            pfapp.append_log(app, pfapp.cpf_summary_line(cpf));

        case 'CPF Predictor-Corrector'
            options = pfapp.build_cpf_options(app, case_data, 'CPF Predictor-Corrector');
            cpf = cpf_predictor_corrector(case_data, options);
            app.last_result = [];
            app.last_cpf = cpf;
            app.last_suite = [];
            app.last_opf = [];
            pfapp.show_cpf_result(app, cpf);
            pfapp.append_log(app, pfapp.cpf_summary_line(cpf));

        case 'OPF Economic Dispatch'
            result = economic_dispatch_opf(case_data, pfapp.common_options(app.tolerance_field.Value));
            app.last_result = [];
            app.last_cpf = [];
            app.last_suite = [];
            app.last_opf = result;
            pfapp.show_opf_result(app, result);
            pfapp.append_log(app, pfapp.opf_summary_line(result));

        case 'AC OPF'
            options = pfapp.common_options(app.tolerance_field.Value);
            options.max_iter = app.max_iter_field.Value;
            result = ac_optimal_power_flow(case_data, options);
            app.last_result = [];
            app.last_cpf = [];
            app.last_suite = [];
            app.last_opf = result;
            pfapp.show_opf_result(app, result);
            pfapp.append_log(app, pfapp.opf_summary_line(result));

        case 'Full 5-bus Suite'
            suite = pfapp.run_suite_headless(app);
            app.last_result = suite.newton_raphson;
            app.last_cpf = suite.cpf_load_scaling;
            app.last_suite = suite;
            app.last_opf = [];
            pfapp.show_suite_result(app, suite);
            pfapp.append_log(app, sprintf('Suite done: NR it=%d, GS it=%d, CPF points=%d/%d', ...
                suite.newton_raphson.iterations, suite.gauss_seidel.iterations, ...
                numel(suite.cpf_load_scaling.lambdas), numel(suite.cpf_predictor_corrector.lambdas)));
    end

    if app.auto_separate_checkbox.Value
        pfapp.open_separate_plots_action(app, fig);
    end
catch err
    pfapp.append_log(app, sprintf('ERROR: %s', err.message));
    uialert(fig, err.message, 'Run Failed');
end
end
