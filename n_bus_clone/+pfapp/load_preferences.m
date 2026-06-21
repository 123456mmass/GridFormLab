function app = load_preferences(app)
%LOAD_PREFERENCES Restore user preferences from previous session.

try
    if ispref('NbusStudio', 'theme_mode')
        mode = getpref('NbusStudio', 'theme_mode');
        if ~strcmp(mode, app.theme_mode)
            app.theme_mode = mode;
        end
    end
    if ispref('NbusStudio', 'last_case')
        val = getpref('NbusStudio', 'last_case');
        if any(strcmp(app.case_dropdown.Items, val))
            app.case_dropdown.Value = val;
        end
    end
    if ispref('NbusStudio', 'last_method')
        val = getpref('NbusStudio', 'last_method');
        if any(strcmp(app.method_dropdown.Items, val))
            app.method_dropdown.Value = val;
        end
    end
    if ispref('NbusStudio', 'max_iter')
        app.max_iter_field.Value = getpref('NbusStudio', 'max_iter');
    end
    if ispref('NbusStudio', 'tolerance')
        app.tolerance_field.Value = getpref('NbusStudio', 'tolerance');
    end
    if ispref('NbusStudio', 'auto_cpf')
        app.auto_cpf_checkbox.Value = getpref('NbusStudio', 'auto_cpf');
    end
    if ispref('NbusStudio', 'auto_separate')
        app.auto_separate_checkbox.Value = getpref('NbusStudio', 'auto_separate');
    end
    if ispref('NbusStudio', 'q_limits')
        app.q_limit_checkbox.Value = getpref('NbusStudio', 'q_limits');
    end
    pfapp.append_log(app, 'Preferences loaded from previous session.');
catch
end
end
