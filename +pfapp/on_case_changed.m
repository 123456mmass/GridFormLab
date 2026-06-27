function app = on_case_changed(app)
%ON_CASE_CHANGED Keep the selected method compatible with the new case.
%   When the user picks a Kundur SMIB case, auto-select the SMIB Stability
%   Analysis method; when they pick a steady-state power-flow case while an
%   SMIB method is active, fall back to Newton-Raphson.

method = app.method_dropdown.Value;
idx = find(strcmp(app.case_labels, app.case_dropdown.Value), 1);
if isempty(idx)
    return;
end
loader = app.case_loaders{idx};
if isempty(loader)
    % "Custom n-bus" slot — always a steady-state case.
    is_smib = false;
else
    try
        is_smib = pfapp.is_smib_case(loader());
    catch
        is_smib = false;
    end
end

if is_smib && ~strcmp(method, 'SMIB Stability Analysis')
    app.method_dropdown.Value = 'SMIB Stability Analysis';
    pfapp.append_log(app, 'Switched to SMIB Stability Analysis for the selected Kundur case.');
elseif ~is_smib && strcmp(method, 'SMIB Stability Analysis')
    app.method_dropdown.Value = 'Newton-Raphson';
    pfapp.append_log(app, 'Switched to Newton-Raphson for the selected power-flow case.');
end

pfapp.update_method_state(app);
end
