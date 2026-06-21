function test_gui_smoke()
%TEST_GUI_SMOKE Headless end-to-end exercise of the rebuilt GUI.
%   Builds the GUI (invisible), drives every SMIB model through the Run
%   dispatcher, toggles the theme, runs a power-flow case, and exports --
%   asserting that no callbacks throw and the dashboard/table populate.

pf_init_paths();
results = struct('pass', 0, 'fail', 0);

% Build the GUI exactly as the launcher does, but invisible.
app = struct();
app.last_result=[]; app.last_cpf=[]; app.last_suite=[]; app.last_opf=[];
app.last_smib=[]; app.last_case_data=[]; app.progress_dialog=[]; app.fig=[];
[app.case_labels, app.case_loaders] = pfapp.make_case_registry();
app.case_labels{end+1} = 'Custom n-bus: (none)';
app.case_loaders{end+1} = [];
app.custom_case_data = [];

[fig, app] = pfapp.create_gui_layout(app);
app.fig = fig;
fig.Visible = 'off';
fig.UserData.app = app;
pfapp.wire_callbacks(app, fig);

% --- SMIB cases through the Run dispatcher ---
all_items = app.case_dropdown.Items;
smib_idx = find(~cellfun(@isempty, regexpi(all_items, 'Kundur SMIB')));
results = check(results, numel(smib_idx) == 4, sprintf('found %d Kundur SMIB cases', numel(smib_idx)));
for i = 1:numel(smib_idx)
    lbl = all_items{smib_idx(i)};
    app = fig.UserData.app;
    app.case_dropdown.Value = lbl;
    app = pfapp.on_case_changed(app);
    results = check(results, strcmp(app.method_dropdown.Value, 'SMIB Stability Analysis'), ...
        sprintf('%s: method auto-switched to SMIB', lbl));
    app = pfapp.run_selected_action(app, fig);
    fig.UserData.app = app;
    app = fig.UserData.app;
    results = check(results, ~isempty(app.last_smib), sprintf('%s: last_smib populated', lbl));
    r = app.last_smib.analyze;
    results = check(results, ~isempty(r.eigenvalues), sprintf('%s: eigenvalues present', lbl));
    results = check(results, ~isempty(app.metric_value_1.Text), sprintf('%s: dashboard populated', lbl));
    results = check(results, size(app.smib_table.Data,1) > 0, sprintf('%s: eigenvalue table populated', lbl));
    fprintf('  info %s -> stable=%d, states=%d\n', lbl, r.is_stable, numel(r.eigenvalues));
end

% --- PSS model must be stable (PSS restores stability) ---
app = fig.UserData.app;
pss_idx = find(~cellfun(@isempty, regexpi(app.case_dropdown.Items, 'PSS')));
app.case_dropdown.Value = app.case_dropdown.Items{pss_idx(1)};
app = pfapp.run_selected_action(app, fig);
fig.UserData.app = app;
app = fig.UserData.app;
results = check(results, app.last_smib.analyze.is_stable, 'SMIB PSS: stable (PSS restores stability)');

% --- Theme toggle (rebuild in place): no throw, preserves result ---
app = fig.UserData.app;
mode_before = app.theme_mode;
app = pfapp.toggle_theme(app, fig);
fig.UserData.app = app;
app = fig.UserData.app;
results = check(results, ~strcmp(app.theme_mode, mode_before), 'theme: mode toggled');
results = check(results, ~isempty(app.last_smib), 'theme: last_smib preserved across rebuild');
results = check(results, isvalid(app.fig), 'theme: figure still valid');
results = check(results, size(app.smib_table.Data,1) > 0, 'theme: SMIB table re-rendered after rebuild');

% --- Toggle back to light ---
app = fig.UserData.app;
app = pfapp.toggle_theme(app, fig);
fig.UserData.app = app;

% --- Power-flow (NR) still works and clears the SMIB view ---
app = fig.UserData.app;
items = app.case_dropdown.Items;
idx = find(~cellfun(@isempty, regexpi(items, 'ieee 5')), 1);
app.case_dropdown.Value = items{idx};
app = pfapp.on_case_changed(app);
app.method_dropdown.Value = 'Newton-Raphson';
app = pfapp.update_method_state(app);
app = pfapp.run_selected_action(app, fig);
fig.UserData.app = app;
app = fig.UserData.app;
results = check(results, ~isempty(app.last_result) && app.last_result.converged, 'NR on IEEE 5-bus: converged');
results = check(results, isempty(app.last_smib), 'NR: last_smib cleared');

% --- Export (CSV + PNG) of the SMIB result ---
app = fig.UserData.app;
cla_idx = find(~cellfun(@isempty, regexpi(app.case_dropdown.Items, 'classical')));
app.case_dropdown.Value = app.case_dropdown.Items{cla_idx(1)};
app = pfapp.on_case_changed(app);
app = pfapp.run_selected_action(app, fig);
fig.UserData.app = app;
app = fig.UserData.app;
outdir = fullfile(pwd, 'output', 'gui_smoke');
if exist(outdir,'dir'); rmdir(outdir,'s'); end
app = pfapp.export_smib_result(app, outdir);
fig.UserData.app = app;
results = check(results, exist(fullfile(outdir,'SMIB_Model_A_eigenvalues.csv'),'file')==2, 'export: eigenvalue CSV written');
results = check(results, exist(fullfile(outdir,'SMIB_Model_A_splane.png'),'file')==2, 'export: s-plane PNG written');
results = check(results, exist(fullfile(outdir,'SMIB_Model_A_step_response.png'),'file')==2, 'export: step PNG written');

% --- Standalone SMIB figures (Separate Plots path) ---
app = fig.UserData.app;
try
    pfapp.open_smib_figure(app);
    results = check(results, true, 'open_smib_figure: no throw');
    % close any popped-up figures
    figs = findall(0, 'Type', 'figure');
    close(figs(figs ~= app.fig));
catch e
    results = check(results, false, sprintf('open_smib_figure threw: %s', e.message));
end

delete(fig);
fprintf('\n==== GUI SMOKE TEST: %d passed, %d failed ====\n', results.pass, results.fail);
if results.fail > 0; error('test_gui_smoke:Failed', '%d checks failed', results.fail); end
end

function r = check(r, cond, msg)
if cond
    r.pass = r.pass + 1;
    fprintf('  PASS  %s\n', msg);
else
    r.fail = r.fail + 1;
    fprintf('  FAIL  %s\n', msg);
end
end
