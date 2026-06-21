function app = run_powerflow_gui()
%RUN_POWERFLOW_GUI Interactive GUI launcher for the n-bus power-flow toolkit.
%   Builds the themed interface, wires every callback through
%   pfapp.wire_callbacks (which captures the stable figure handle so the
%   wiring survives an in-place theme rebuild), and restores saved
%   preferences.

pf_init_paths();

app = struct();
app.last_result = [];
app.last_cpf = [];
app.last_suite = [];
app.last_opf = [];
app.last_smib = [];
app.last_case_data = [];
app.progress_dialog = [];
app.fig = [];

[app.case_labels, app.case_loaders] = pfapp.make_case_registry();
app.case_labels{end + 1} = 'Custom n-bus: (none)';
app.case_loaders{end + 1} = [];
app.custom_case_data = [];

% Build the layout (creates the figure) and store the live app on it.
[fig, app] = pfapp.create_gui_layout(app);
app.fig = fig;
fig.UserData.app = app;

% Wire all callbacks (closures capture fig, fetch live app from UserData).
pfapp.wire_callbacks(app, fig);

% Reflect the current case/method selection on the controls.
pfapp.update_method_state(app);
pfapp.plot_empty_state(app);

% Restore saved preferences.
app = pfapp.load_preferences(app);
% Reconcile case/method after restoring prefs (programmatic Value sets
% do not fire ValueChangedFcn), then refresh the control states.
app = pfapp.on_case_changed(app);
app = pfapp.update_method_state(app);
fig.UserData.app = app;

pfapp.append_log(app, 'N-Bus Power Flow Studio ready. Select a case and method, then Run.');
end
