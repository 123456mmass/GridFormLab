function update_method_state(app)
%UPDATE_METHOD_STATE Enable/disable UI fields based on selected method.

method = app.method_dropdown.Value;
is_gs = strcmp(method, 'Gauss-Seidel') || strcmp(method, 'Full 5-bus Suite');
is_cpf = startsWith(method, 'CPF');
auto_cpf = is_cpf && app.auto_cpf_checkbox.Value;
if is_gs && app.max_iter_field.Value < 300
    app.max_iter_field.Value = 300;
elseif strcmp(method, 'AC OPF') && app.max_iter_field.Value < 200
    app.max_iter_field.Value = 300;
elseif strcmp(method, 'Newton-Raphson') && app.max_iter_field.Value > 100
    app.max_iter_field.Value = 50;
end
app.accel_field.Enable = matlab.lang.OnOffSwitchState(is_gs);
app.q_limit_checkbox.Enable = matlab.lang.OnOffSwitchState(strcmp(method, 'Newton-Raphson') || strcmp(method, 'Full 5-bus Suite'));
app.auto_cpf_checkbox.Enable = matlab.lang.OnOffSwitchState(is_cpf);
app.target_bus_field.Enable = matlab.lang.OnOffSwitchState(is_cpf && ~auto_cpf);
app.lambda_step_field.Enable = matlab.lang.OnOffSwitchState(is_cpf && ~auto_cpf);
app.lambda_max_field.Enable = matlab.lang.OnOffSwitchState(is_cpf && ~auto_cpf);
app.min_voltage_field.Enable = matlab.lang.OnOffSwitchState(is_cpf && ~auto_cpf);
end
