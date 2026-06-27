function app = update_method_state(app)
%UPDATE_METHOD_STATE Enable/disable UI fields based on selected method.
%   Sets reasonable default max_iter per method when method changes and
%   keeps SMIB analysis isolated from the steady-state solver controls.

method = app.method_dropdown.Value;
is_gs = strcmp(method, 'Gauss-Seidel') || strcmp(method, 'Full 5-bus Suite');
is_cpf = startsWith(method, 'CPF');
is_opf = strcmp(method, 'AC OPF') || strcmp(method, 'OPF Economic Dispatch');
is_suite = strcmp(method, 'Full 5-bus Suite');
is_smib = strcmp(method, 'SMIB Stability Analysis');
auto_cpf = is_cpf && app.auto_cpf_checkbox.Value;

% Steady-state solvers use max_iter/tolerance; SMIB ignores them.
pf_controls = ~is_smib;

% Set appropriate default max_iter when switching TO a method.
current_val = app.max_iter_field.Value;
switch method
    case 'Gauss-Seidel'
        if current_val < 100; app.max_iter_field.Value = 300; end
    case 'Newton-Raphson'
        if current_val > 200; app.max_iter_field.Value = 50; end
    case 'AC OPF'
        if current_val < 50 || current_val > 500; app.max_iter_field.Value = 200; end
    case 'Full 5-bus Suite'
        if current_val < 100; app.max_iter_field.Value = 300; end
end

app.accel_field.Enable = matlab.lang.OnOffSwitchState(is_gs && pf_controls);
app.q_limit_checkbox.Enable = matlab.lang.OnOffSwitchState( ...
    pf_controls && (strcmp(method, 'Newton-Raphson') || is_suite));
app.auto_cpf_checkbox.Enable = matlab.lang.OnOffSwitchState(is_cpf && pf_controls);
app.target_bus_field.Enable = matlab.lang.OnOffSwitchState(is_cpf && ~auto_cpf && pf_controls);
app.lambda_step_field.Enable = matlab.lang.OnOffSwitchState(is_cpf && ~auto_cpf && pf_controls);
app.lambda_max_field.Enable = matlab.lang.OnOffSwitchState(is_cpf && ~auto_cpf && pf_controls);
app.min_voltage_field.Enable = matlab.lang.OnOffSwitchState(is_cpf && ~auto_cpf && pf_controls);

% For SMIB, dim the solver/CPF parameter fields (purely cosmetic — they are
% simply not consumed).
if is_smib
    app.max_iter_field.Enable = 'off';
    app.tolerance_field.Enable = 'off';
else
    app.max_iter_field.Enable = 'on';
    app.tolerance_field.Enable = 'on';
end

% Reflect the method on the status dot / METHOD metric card.
try
    if is_smib
        app.status_dot.Text = '● SMIB';
        app.status_dot.FontColor = app.theme.purple;
    elseif is_cpf
        app.status_dot.Text = '● CPF';
        app.status_dot.FontColor = app.theme.accent;
    elseif is_opf
        app.status_dot.Text = '● OPF';
        app.status_dot.FontColor = app.theme.primary;
    else
        app.status_dot.Text = '● Ready';
        app.status_dot.FontColor = app.theme.success;
    end
catch
end
end
