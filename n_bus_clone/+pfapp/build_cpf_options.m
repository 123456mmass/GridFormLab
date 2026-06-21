function options = build_cpf_options(app, case_data, method)
%BUILD_CPF_OPTIONS Build CPF options struct with optional auto-calibration.

if nargin < 2 || isempty(case_data)
    case_data = pfapp.load_selected_case(app);
end
if nargin < 3 || isempty(method)
    method = app.method_dropdown.Value;
end
options = pfapp.common_options(app.tolerance_field.Value);
if app.auto_cpf_checkbox.Value && startsWith(method, 'CPF')
    [options, setup] = pfapp.auto_calibrate_cpf(app, case_data, method);
    pfapp.apply_cpf_setup(app, setup);
    pfapp.append_log(app, sprintf('Auto CPF setup: bus %g (%s), step=%.3f, lambda max=%.2f, Vmin=%.2f, steps=%d', ...
        setup.target_bus, setup.reason, setup.lambda_step, setup.lambda_max, setup.min_voltage, setup.max_steps));
else
    options.max_steps = app.max_iter_field.Value;
    options.target_bus = app.target_bus_field.Value;
    options.lambda_step = app.lambda_step_field.Value;
    options.lambda_max = app.lambda_max_field.Value;
    options.min_voltage = app.min_voltage_field.Value;
end
options.min_lambda_step = max(options.lambda_step / 16, eps);
options.max_lambda_step = options.lambda_step;
if strcmp(method, 'CPF Predictor-Corrector')
    options.max_corrector_iter = 16;
end
end
