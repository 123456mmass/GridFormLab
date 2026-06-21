pf_init_paths;
app = struct();
app.last_result=[]; app.last_cpf=[]; app.last_suite=[]; app.last_opf=[];
app.last_smib=[]; app.last_case_data=[]; app.progress_dialog=[]; app.fig=[];
[app.case_labels, app.case_loaders] = pfapp.make_case_registry();
app.case_labels{end+1}='Custom n-bus: (none)'; app.case_loaders{end+1}=[];
app.custom_case_data=[];
[fig, app] = pfapp.create_gui_layout(app);
app.fig=fig; fig.Visible='on'; drawnow; fig.UserData.app=app;
pfapp.wire_callbacks(app, fig);

outdir = fullfile(pwd, 'output', 'gui_capture'); if ~exist(outdir,'dir'); mkdir(outdir); end

% --- NR Analysis tab ---
items = app.case_dropdown.Items;
idx = find(~cellfun(@isempty, regexpi(items,'ieee 5')),1);
app.case_dropdown.Value = items{idx};
app = pfapp.on_case_changed(app);
app.method_dropdown.Value='Newton-Raphson';
app = pfapp.run_selected_action(app, fig);
fig.UserData.app=app; app=fig.UserData.app;
app.tab_group.SelectedTab = findobj(app.tab_group,'Title','  Analysis  ');
drawnow; pause(0.4);
fr = getframe(fig); imwrite(fr.cdata, fullfile(outdir,'04_analysis.png'));

% --- NR Results Table tab ---
app.tab_group.SelectedTab = findobj(app.tab_group,'Title','  Results Table  ');
drawnow; pause(0.4);
fr = getframe(fig); imwrite(fr.cdata, fullfile(outdir,'05_nr_results.png'));

% --- SMIB Classical + light ---
app = fig.UserData.app;
cla_idx = find(~cellfun(@isempty, regexpi(app.case_dropdown.Items,'classical')),1);
app.case_dropdown.Value = app.case_dropdown.Items{cla_idx(1)};
app = pfapp.on_case_changed(app);
app = pfapp.run_selected_action(app, fig);
fig.UserData.app=app;
drawnow; pause(0.4);
fr = getframe(fig); imwrite(fr.cdata, fullfile(outdir,'02_smib_tab.png'));

% --- SMIB Dark ---
app = fig.UserData.app;
app = pfapp.toggle_theme(app, fig); fig.UserData.app=app;
drawnow; pause(0.4);
fr = getframe(fig); imwrite(fr.cdata, fullfile(outdir,'03_smib_dark.png'));

delete(fig);
fprintf('captured to %s\n', outdir);
