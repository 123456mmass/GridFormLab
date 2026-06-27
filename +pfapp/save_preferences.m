function save_preferences(app)
%SAVE_PREFERENCES Persist user preferences using setpref.

try
    setpref('NbusStudio', 'theme_mode', app.theme_mode);
    setpref('NbusStudio', 'last_case', app.case_dropdown.Value);
    setpref('NbusStudio', 'last_method', app.method_dropdown.Value);
    setpref('NbusStudio', 'max_iter', app.max_iter_field.Value);
    setpref('NbusStudio', 'tolerance', app.tolerance_field.Value);
    setpref('NbusStudio', 'auto_cpf', app.auto_cpf_checkbox.Value);
    setpref('NbusStudio', 'auto_separate', app.auto_separate_checkbox.Value);
    setpref('NbusStudio', 'q_limits', app.q_limit_checkbox.Value);
catch
end
end
