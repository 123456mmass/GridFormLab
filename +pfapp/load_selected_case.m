function case_data = load_selected_case(app)
%DEPRECATED (Phase C): superseded by the Studio GUI (+studio/launch.m).
%   Header banner only; behavior unchanged.
%LOAD_SELECTED_CASE Look up the selected case from the dropdown.

idx = find(strcmp(app.case_labels, app.case_dropdown.Value), 1);
if isempty(idx)
    error('Unknown case selection: %s', app.case_dropdown.Value);
end
loader = app.case_loaders{idx};
if isempty(loader)
    if isempty(app.custom_case_data)
        error('No custom n-bus case loaded. Click Browse Custom n-bus Case first.');
    end
    case_data = app.custom_case_data;
else
    case_data = loader();
end
end
