function update_method_state(app)
%UPDATE_METHOD_STATE Enable/disable UI fields based on selected method.
%   Sets reasonable default max_iter per method when method changes.

method = app.method_dropdown.Value;
is_gs = strcmp(method, 'Gauss-Seidel') || strcmp(method, 'Full 5-bus Suite');
is_cpf = startsWith(method, 'CPF');
auto_cpf = is_cpf && app.auto_cpf_checkbox.Value;

% Set appropriate default max_iter when switching TO a method.
% Only adjust if the current value looks like a leftover from another method
% (i.e. don't downgrade a user-set value that's already reasonable).
current_val = app.max_iter_field.Value;
switch method
    case 'Gauss-Seidel'
        if current_val < 100
            app.max_iter_field.Value = 300;
        end
    case 'Newton-Raphson'
        if current_val > 200
            app.max_iter_field.Value = 50;
        end
    case 'AC OPF'
        if current_val < 50 || current_val > 500
            app.max_iter_field.Value = 200;
        end
    case 'Full 5-bus Suite'
        if current_val < 100
            app.max_iter_field.Value = 300;
        end
end

app.accel_field.Enable = matlab.lang.OnOffSwitchState(is_gs);
app.q_limit_checkbox.Enable = matlab.lang.OnOffSwitchState( ...
    strcmp(method, 'Newton-Raphson') || strcmp(method, 'Full 5-bus Suite'));
app.auto_cpf_checkbox.Enable = matlab.lang.OnOffSwitchState(is_cpf);
app.target_bus_field.Enable = matlab.lang.OnOffSwitchState(is_cpf && ~auto_cpf);
app.lambda_step_field.Enable = matlab.lang.OnOffSwitchState(is_cpf && ~auto_cpf);
app.lambda_max_field.Enable = matlab.lang.OnOffSwitchState(is_cpf && ~auto_cpf);
app.min_voltage_field.Enable = matlab.lang.OnOffSwitchState(is_cpf && ~auto_cpf);
end
