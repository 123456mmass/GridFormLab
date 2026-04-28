function [options, setup] = auto_calibrate_cpf(app, case_data, method)
%AUTO_CALIBRATE_CPF Run base NR, pick weakest bus, set CPF defaults.

model = pf_prepare_case(case_data);
nr_options = struct('max_iter', 30, 'tolerance', app.tolerance_field.Value, ...
    'plot_results', false, 'verbose', false, 'enforce_q_limits', app.q_limit_checkbox.Value);
base_pf = powerflow_newton_raphson(case_data, nr_options);
if ~base_pf.converged
    error('Auto CPF setup failed because the base Newton-Raphson solve did not converge.');
end

[target_idx, reason] = pfapp.choose_auto_target_bus(model, base_pf);
target_bus = model.external_bus_ids(target_idx);

if strcmp(method, 'CPF Predictor-Corrector')
    [lambda_step, lambda_max, min_voltage, max_steps] = pfapp.predictor_defaults(model.num_buses);
else
    [lambda_step, lambda_max, min_voltage, max_steps] = pfapp.load_scaling_defaults(model.num_buses);
end

options = pfapp.common_options(app.tolerance_field.Value);
options.target_bus = target_bus;
options.lambda_step = lambda_step;
options.lambda_max = lambda_max;
options.min_voltage = min_voltage;
options.max_steps = max(max_steps, app.max_iter_field.Value);

setup = struct( ...
    'target_bus', target_bus, ...
    'lambda_step', lambda_step, ...
    'lambda_max', lambda_max, ...
    'min_voltage', min_voltage, ...
    'max_steps', options.max_steps, ...
    'base_voltage', base_pf.bus_voltage(target_idx), ...
    'reason', reason);
end
