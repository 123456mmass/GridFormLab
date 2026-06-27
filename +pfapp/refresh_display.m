function refresh_display(app)
%REFRESH_DISPLAY Re-render the last result into the rebuilt GUI.
%   pfapp.refresh_display(app) is called after an in-place theme rebuild so
%   the user does not lose the currently displayed result. It inspects the
%   app.last_* fields in priority order and re-runs the matching show_*
%   renderer, or falls back to the empty-state placeholder.

if ~isempty(app) && isfield(app, 'last_suite') && ~isempty(app.last_suite)
    pfapp.show_suite_result(app, app.last_suite);
elseif ~isempty(app) && isfield(app, 'last_smib') && ~isempty(app.last_smib)
    pfapp.show_smib_result(app);
elseif ~isempty(app) && isfield(app, 'last_opf') && ~isempty(app.last_opf)
    pfapp.show_opf_result(app, app.last_opf);
elseif ~isempty(app) && isfield(app, 'last_cpf') && ~isempty(app.last_cpf)
    pfapp.show_cpf_result(app, app.last_cpf);
elseif ~isempty(app) && isfield(app, 'last_result') && ~isempty(app.last_result)
    pfapp.show_powerflow_result(app, app.last_result, app.tolerance_field.Value);
else
    pfapp.plot_empty_state(app);
end
end
