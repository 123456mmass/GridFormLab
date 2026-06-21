function [fig, app] = create_gui_layout(app)
%CREATE_GUI_LAYOUT Modern professional layout for the n-bus studio.
%   [FIG, APP] = CREATE_GUI_LAYOUT(APP) builds (or, if APP.FIG already
%   holds a valid figure, REBUILDS IN PLACE) the full themed interface.
%   In-place rebuild lets toggle_theme swap light/dark cleanly without
%   orphaning a second window or losing the live app/fig references.
%
%   Layout:
%     header   - accent logo box, title + subtitle, theme/log toggles, status dot
%     sidebar  - case / method / solver / CPF / options / actions / help
%     content  - 4 metric cards, tab group (Analysis, Results, Advanced, SMIB),
%                action row, collapsible run log

% ── Resolve theme ───────────────────────────────────────────
if isfield(app, 'theme') && ~isempty(app.theme) && isfield(app, 'theme_mode') && ~isempty(app.theme_mode)
    theme = app.theme;
else
    theme = build_theme('light');
    app.theme_mode = 'light';
end
app.theme = theme;

% ── Figure: reuse if valid, else create ──────────────────────
if isfield(app, 'fig') && ~isempty(app.fig) && isvalid(app.fig)
    fig = app.fig;
    delete(fig.Children);          % clear previous build (rebuild in place)
    fig.Color = theme.canvas;
else
    fig = uifigure('Name', 'N-Bus Power Flow Studio', ...
        'Position', [40 40 1440 880], ...
        'Color', theme.canvas, ...
        'Icon', '');
    fig.AutoResizeChildren = 'off';
end
app.fig = fig;

% ── Outer grid: header + main + log ─────────────────────────
outer = uigridlayout(fig, [3 1]);
outer.Padding = [0 0 0 0];
outer.RowHeight = {58, '1x', 150};
outer.RowSpacing = 0;
outer.ColumnWidth = {'1x'};
outer.BackgroundColor = theme.canvas;
app.outer_grid = outer;
app.log_row_height = 150;

app = build_header(outer, app, theme);
app = build_main(outer, app, theme);
app = build_log_panel(outer, app, theme);
end

% ════════════════════════════════════════════════════════════
%  HEADER
% ════════════════════════════════════════════════════════════
function app = build_header(outer, app, theme)
header = uigridlayout(outer, [1 5]);
header.Layout.Row = 1;
header.Padding = [20 14 20 14];
header.RowHeight = {58};
header.ColumnWidth = {44, '1x', 116, 96, 86};
header.ColumnSpacing = 12;
header.BackgroundColor = theme.surface;

% Logo accent box
logo_box = uipanel(header, 'Title', '', 'BorderType', 'none');
logo_box.Layout.Row = 1;
logo_box.Layout.Column = 1;
logo_box.BackgroundColor = theme.primary;
lg_grid = uigridlayout(logo_box, [1 1]);
lg_grid.Padding = [0 0 0 0];
lg_grid.BackgroundColor = theme.primary;
app.logo_label = uilabel(lg_grid, 'Text', '⚡');
app.logo_label.Layout.Row = 1;
app.logo_label.Layout.Column = 1;
app.logo_label.FontName = 'Segoe UI';
app.logo_label.FontSize = 22;
app.logo_label.FontColor = [1 1 1];
app.logo_label.HorizontalAlignment = 'center';
app.logo_label.VerticalAlignment = 'center';

% Title + subtitle stack
title_stack = uigridlayout(header, [2 1]);
title_stack.Layout.Row = 1;
title_stack.Layout.Column = 2;
title_stack.Padding = [0 0 0 4];
title_stack.RowHeight = {30, 20};
title_stack.RowSpacing = 0;
title_stack.BackgroundColor = theme.surface;

app.title_label = uilabel(title_stack, 'Text', 'N-Bus Power Flow Studio');
app.title_label.Layout.Row = 1;
app.title_label.FontName = 'Segoe UI';
app.title_label.FontSize = 17;
app.title_label.FontWeight = 'bold';
app.title_label.FontColor = theme.ink;
app.title_label.HorizontalAlignment = 'left';
app.title_label.VerticalAlignment = 'bottom';

app.subtitle_label = uilabel(title_stack, 'Text', 'Power System Analysis · Load Flow · CPF · OPF · Small-Signal Stability');
app.subtitle_label.Layout.Row = 2;
app.subtitle_label.FontName = 'Segoe UI';
app.subtitle_label.FontSize = 10;
app.subtitle_label.FontColor = theme.muted;
app.subtitle_label.HorizontalAlignment = 'left';
app.subtitle_label.VerticalAlignment = 'top';

% Theme toggle
app.theme_toggle = uibutton(header, 'Text', toggle_label('theme', app.theme_mode));
app.theme_toggle.Layout.Row = 1;
app.theme_toggle.Layout.Column = 3;
style_button(app.theme_toggle, 'ghost', theme);
app.theme_toggle.Tooltip = 'Toggle light / dark theme';

% Log toggle
app.log_toggle = uibutton(header, 'Text', toggle_label('log', true));
app.log_toggle.Layout.Row = 1;
app.log_toggle.Layout.Column = 4;
style_button(app.log_toggle, 'ghost', theme);
app.log_toggle.Tooltip = 'Show / hide the run log';

% Version + status dot
status_stack = uigridlayout(header, [2 1]);
status_stack.Layout.Row = 1;
status_stack.Layout.Column = 5;
status_stack.Padding = [0 0 0 0];
status_stack.RowHeight = {18, 18};
status_stack.RowSpacing = 0;
status_stack.BackgroundColor = theme.surface;

app.version_label = uilabel(status_stack, 'Text', 'v3.0');
app.version_label.Layout.Row = 1;
app.version_label.FontName = 'Segoe UI';
app.version_label.FontSize = 9;
app.version_label.FontColor = theme.muted;
app.version_label.HorizontalAlignment = 'right';
app.version_label.VerticalAlignment = 'bottom';

app.status_dot = uilabel(status_stack, 'Text', '● Ready');
app.status_dot.Layout.Row = 2;
app.status_dot.FontName = 'Segoe UI';
app.status_dot.FontSize = 10;
app.status_dot.FontWeight = 'bold';
app.status_dot.FontColor = theme.success;
app.status_dot.HorizontalAlignment = 'right';
app.status_dot.VerticalAlignment = 'top';
end

% ════════════════════════════════════════════════════════════
%  MAIN
% ════════════════════════════════════════════════════════════
function app = build_main(outer, app, theme)
main = uigridlayout(outer, [1 2]);
main.Layout.Row = 2;
main.Padding = [14 14 14 14];
main.ColumnWidth = {360, '1x'};
main.RowHeight = {'1x'};
main.ColumnSpacing = 14;
main.BackgroundColor = theme.canvas;

app = build_sidebar(main, app, theme);
app = build_content(main, app, theme);
end

% ── Left sidebar ────────────────────────────────────────────
function app = build_sidebar(main, app, theme)
left_panel = uipanel(main, 'Title', '', 'BorderType', 'line', 'BorderColor', theme.border);
left_panel.Layout.Row = 1;
left_panel.Layout.Column = 1;
left_panel.BackgroundColor = theme.surface;
left_panel.Scrollable = 'on';

left_grid = uigridlayout(left_panel, [1 1]);
left_grid.Padding = [0 0 0 0];
left_grid.RowHeight = {'1x'};
left_grid.ColumnWidth = {'1x'};
left_grid.BackgroundColor = theme.surface;

controls = uigridlayout(left_grid, [29 1]);
controls.RowHeight = {8,26,32,28,8,26,32,8,26,30,30,30,8,26,30,30,30,30,8,26,24,24,24,8,42,32,32,8,'1x'};
controls.ColumnWidth = {'1x'};
controls.Padding = [14 14 14 14];
controls.RowSpacing = 5;
controls.Scrollable = 'on';
controls.BackgroundColor = theme.surface;

% Title
title_lbl = uilabel(controls, 'Text', 'Configuration');
title_lbl.Layout.Row = 2;
title_lbl.FontName = 'Segoe UI';
title_lbl.FontSize = 15;
title_lbl.FontWeight = 'bold';
title_lbl.FontColor = theme.ink;

% ── Case ──
section_label(controls, 'CASE', 3, theme);
app.case_dropdown = uidropdown(controls, 'Items', app.case_labels, 'Value', app.case_labels{1});
app.case_dropdown.Layout.Row = 4;
style_field(app.case_dropdown, theme);
app.browse_case_button = uibutton(controls, 'Text', '+  Browse Custom Case');
app.browse_case_button.Layout.Row = 5;
style_button(app.browse_case_button, 'ghost', theme);

% ── Method ──
section_label(controls, 'METHOD', 6, theme);
app.method_dropdown = uidropdown(controls, ...
    'Items', {'Newton-Raphson', 'Gauss-Seidel', 'CPF Load Scaling', ...
              'CPF Predictor-Corrector', 'AC OPF', 'OPF Economic Dispatch', ...
              'Full 5-bus Suite', 'SMIB Stability Analysis'}, ...
    'Value', 'Newton-Raphson');
app.method_dropdown.Layout.Row = 7;
style_field(app.method_dropdown, theme);

% ── Solver parameters ──
section_label(controls, 'SOLVER PARAMETERS', 9, theme);
app.max_iter_field = uieditfield(controls, 'numeric', ...
    'Value', 50, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
labeled_field(controls, 'Max Iterations', app.max_iter_field, 10, theme);

app.tolerance_field = uieditfield(controls, 'numeric', ...
    'Value', 1e-6, 'Limits', [eps Inf]);
labeled_field(controls, 'Tolerance', app.tolerance_field, 11, theme);

app.accel_field = uieditfield(controls, 'numeric', ...
    'Value', 1.4, 'Limits', [0.1 2.0]);
labeled_field(controls, 'GS Acceleration', app.accel_field, 12, theme);

% ── CPF ──
section_label(controls, 'CPF CONFIGURATION', 14, theme);
app.target_bus_field = uieditfield(controls, 'numeric', ...
    'Value', 5, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
labeled_field(controls, 'Target Bus', app.target_bus_field, 15, theme);

app.lambda_step_field = uieditfield(controls, 'numeric', ...
    'Value', 0.05, 'Limits', [eps Inf]);
labeled_field(controls, 'Lambda Step', app.lambda_step_field, 16, theme);

app.lambda_max_field = uieditfield(controls, 'numeric', ...
    'Value', 3.0, 'Limits', [eps Inf]);
labeled_field(controls, 'Lambda Max', app.lambda_max_field, 17, theme);

app.min_voltage_field = uieditfield(controls, 'numeric', ...
    'Value', 0.65, 'Limits', [0.01 2.0]);
labeled_field(controls, 'Min Voltage (pu)', app.min_voltage_field, 18, theme);

% ── Options ──
section_label(controls, 'OPTIONS', 20, theme);
app.q_limit_checkbox = uicheckbox(controls, 'Text', 'Enforce Q limits (PV → PQ)', 'Value', true);
app.q_limit_checkbox.Layout.Row = 21;
style_checkbox(app.q_limit_checkbox, theme);

app.auto_cpf_checkbox = uicheckbox(controls, 'Text', 'Auto CPF setup from base NR', 'Value', true);
app.auto_cpf_checkbox.Layout.Row = 22;
style_checkbox(app.auto_cpf_checkbox, theme);

app.auto_separate_checkbox = uicheckbox(controls, 'Text', 'Auto open plots after Run', 'Value', true);
app.auto_separate_checkbox.Layout.Row = 23;
style_checkbox(app.auto_separate_checkbox, theme);

% ── Actions ──
app.run_button = uibutton(controls, 'Text', '▶  Run Analysis');
app.run_button.Layout.Row = 25;
style_button(app.run_button, 'primary', theme);

btn_row = uigridlayout(controls, [1 2]);
btn_row.Layout.Row = 26;
btn_row.ColumnWidth = {'1x', '1x'};
btn_row.ColumnSpacing = 8;
btn_row.Padding = [0 0 0 0];
btn_row.BackgroundColor = theme.surface;
app.export_button = uibutton(btn_row, 'Text', 'Export');
app.export_button.Layout.Row = 1; app.export_button.Layout.Column = 1;
style_button(app.export_button, 'secondary', theme);
app.tests_button = uibutton(btn_row, 'Text', 'Tests');
app.tests_button.Layout.Row = 1; app.tests_button.Layout.Column = 2;
style_button(app.tests_button, 'accent', theme);

btn_row2 = uigridlayout(controls, [1 2]);
btn_row2.Layout.Row = 27;
btn_row2.ColumnWidth = {'1x', '1x'};
btn_row2.ColumnSpacing = 8;
btn_row2.Padding = [0 0 0 0];
btn_row2.BackgroundColor = theme.surface;
app.open_output_button = uibutton(btn_row2, 'Text', 'Output Dir');
app.open_output_button.Layout.Row = 1; app.open_output_button.Layout.Column = 1;
style_button(app.open_output_button, 'ghost', theme);
app.clear_button = uibutton(btn_row2, 'Text', 'Clear Log');
app.clear_button.Layout.Row = 1; app.clear_button.Layout.Column = 2;
style_button(app.clear_button, 'ghost', theme);

% ── Help card ──
help_card = uipanel(controls, 'Title', '', 'BorderType', 'line', 'BorderColor', theme.border);
help_card.Layout.Row = 29;
help_card.BackgroundColor = theme.surface_alt;
help_card_gr = uigridlayout(help_card, [1 1]);
help_card_gr.Padding = [10 10 10 10];
help_card_gr.BackgroundColor = theme.surface_alt;
app.help_text = uitextarea(help_card_gr, 'Editable', 'off');
app.help_text.FontName = 'Segoe UI';
app.help_text.FontSize = 10;
app.help_text.FontColor = theme.muted;
app.help_text.BackgroundColor = theme.surface_alt;
app.help_text.Value = { ...
    'Quick tips:', ...
    '• SMIB cases (Kundur) use the "SMIB Stability Analysis" method.', ...
    '• IEEE / Saadat cases use NR, GS, CPF, OPF, or the 5-bus suite.', ...
    '• CPF auto-setup runs base NR for stable defaults.', ...
    '• Exports write CSV / JSON / HTML under ./output.'};
end

% ── Right content ───────────────────────────────────────────
function app = build_content(main, app, theme)
right = uigridlayout(main, [3 1]);
right.Padding = [0 0 0 0];
right.RowHeight = {96, '1x', 46};
right.RowSpacing = 12;
right.ColumnWidth = {'1x'};
right.BackgroundColor = theme.canvas;

% Metric cards
metric_panel = uipanel(right, 'Title', '', 'BorderType', 'none');
metric_panel.Layout.Row = 1;
metric_panel.BackgroundColor = theme.canvas;
metric_grid = uigridlayout(metric_panel, [1 4]);
metric_grid.ColumnWidth = {'1x', '1x', '1x', '1x'};
metric_grid.RowHeight = {'1x'};
metric_grid.Padding = [0 0 0 0];
metric_grid.ColumnSpacing = 12;
metric_grid.BackgroundColor = theme.canvas;

[app.metric_card_1, app.metric_title_1, app.metric_value_1, app.metric_caption_1] = ...
    create_metric_card(metric_grid, 1, 'STATUS', 'Ready', 'Awaiting run', theme, theme.status);
[app.metric_card_2, app.metric_title_2, app.metric_value_2, app.metric_caption_2] = ...
    create_metric_card(metric_grid, 2, 'CASE', '5-Bus', 'IEEE test system', theme, theme.accent);
[app.metric_card_3, app.metric_title_3, app.metric_value_3, app.metric_caption_3] = ...
    create_metric_card(metric_grid, 3, 'METHOD', 'NR', 'Newton-Raphson', theme, theme.primary);
[app.metric_card_4, app.metric_title_4, app.metric_value_4, app.metric_caption_4] = ...
    create_metric_card(metric_grid, 4, 'CONVERGENCE', '--', 'Pending', theme, theme.purple);

% Tabs
tab_group = uitabgroup(right);
tab_group.Layout.Row = 2;
app.tab_group = tab_group;

% Tab 1: Analysis
plot_tab = uitab(tab_group, 'Title', '  Analysis  ');
plot_tab.BackgroundColor = theme.surface;
plot_grid = uigridlayout(plot_tab, [1 2]);
plot_grid.ColumnWidth = {'1x', '1x'};
plot_grid.Padding = [14 10 14 14];
plot_grid.ColumnSpacing = 14;
plot_grid.BackgroundColor = theme.surface;
app.ax_voltage = uiaxes(plot_grid);
app.ax_voltage.Layout.Row = 1; app.ax_voltage.Layout.Column = 1;
style_axes(app.ax_voltage, theme);
app.ax_conv = uiaxes(plot_grid);
app.ax_conv.Layout.Row = 1; app.ax_conv.Layout.Column = 2;
style_axes(app.ax_conv, theme);

% Tab 2: Results table
table_tab = uitab(tab_group, 'Title', '  Results Table  ');
table_tab.BackgroundColor = theme.surface;
table_pg = uigridlayout(table_tab, [1 1]);
table_pg.Padding = [14 10 14 14];
table_pg.BackgroundColor = theme.surface;
app.result_table = uitable(table_pg);
app.result_table.Layout.Row = 1; app.result_table.Layout.Column = 1;
app.result_table.FontName = 'Segoe UI';
app.result_table.FontSize = 12;
app.result_table.BackgroundColor = theme.table_bg;
app.result_table.ForegroundColor = theme.table_text;
app.result_table.RowStriping = 'off';
app.result_table.ColumnWidth = 'auto';

% Tab 3: Advanced plots
adv_tab = uitab(tab_group, 'Title', '  Advanced Plots  ');
adv_tab.BackgroundColor = theme.surface;
adv_pg = uigridlayout(adv_tab, [1 2]);
adv_pg.ColumnWidth = {'1x', '1x'};
adv_pg.Padding = [14 10 14 14];
adv_pg.ColumnSpacing = 14;
adv_pg.BackgroundColor = theme.surface;
app.ax_cpf = uiaxes(adv_pg);
app.ax_cpf.Layout.Row = 1; app.ax_cpf.Layout.Column = 1;
style_axes(app.ax_cpf, theme);
app.ax_opf = uiaxes(adv_pg);
app.ax_opf.Layout.Row = 1; app.ax_opf.Layout.Column = 2;
style_axes(app.ax_opf, theme);

% Tab 4: SMIB Stability
smib_tab = uitab(tab_group, 'Title', '  SMIB Stability  ');
smib_tab.BackgroundColor = theme.surface;
app.smib_tab = smib_tab;
smib_pg = uigridlayout(smib_tab, [2 1]);
smib_pg.RowHeight = {'1x', 150};
smib_pg.RowSpacing = 10;
smib_pg.Padding = [14 10 14 14];
smib_pg.BackgroundColor = theme.surface;

smib_ax_grid = uigridlayout(smib_pg, [1 2]);
smib_ax_grid.Layout.Row = 1;
smib_ax_grid.ColumnWidth = {'1x', '1x'};
smib_ax_grid.ColumnSpacing = 14;
smib_ax_grid.Padding = [0 0 0 0];
smib_ax_grid.BackgroundColor = theme.surface;
app.ax_smib_plane = uiaxes(smib_ax_grid);
app.ax_smib_plane.Layout.Row = 1; app.ax_smib_plane.Layout.Column = 1;
style_axes(app.ax_smib_plane, theme);
app.ax_smib_step = uiaxes(smib_ax_grid);
app.ax_smib_step.Layout.Row = 1; app.ax_smib_step.Layout.Column = 2;
style_axes(app.ax_smib_step, theme);

smib_table_pg = uigridlayout(smib_pg, [1 1]);
smib_table_pg.Layout.Row = 2;
smib_table_pg.Padding = [0 0 0 0];
smib_table_pg.BackgroundColor = theme.surface;
app.smib_table = uitable(smib_table_pg);
app.smib_table.Layout.Row = 1; app.smib_table.Layout.Column = 1;
app.smib_table.FontName = 'Segoe UI';
app.smib_table.FontSize = 12;
app.smib_table.BackgroundColor = theme.table_bg;
app.smib_table.ForegroundColor = theme.table_text;
app.smib_table.RowStriping = 'off';
app.smib_table.ColumnName = {'Eigenvalue', 'sigma (1/s)', 'omega (rad/s)', 'zeta', 'f (Hz)', 'Stable'};
app.smib_table.ColumnWidth = {130, 80, 90, 70, 70, 60};

% Action row
action_row = uigridlayout(right, [1 4]);
action_row.Layout.Row = 3;
action_row.ColumnWidth = {'1x', '1x', '1x', '1x'};
action_row.ColumnSpacing = 10;
action_row.Padding = [0 0 0 0];
action_row.BackgroundColor = theme.canvas;

app.separate_plot_button = uibutton(action_row, 'Text', 'Separate Plots');
app.separate_plot_button.Layout.Row = 1; app.separate_plot_button.Layout.Column = 1;
style_button(app.separate_plot_button, 'secondary', theme);
app.analysis_plot_button = uibutton(action_row, 'Text', 'Analysis Plots');
app.analysis_plot_button.Layout.Row = 1; app.analysis_plot_button.Layout.Column = 2;
style_button(app.analysis_plot_button, 'secondary', theme);
app.export_json_button = uibutton(action_row, 'Text', '{ }  JSON Export');
app.export_json_button.Layout.Row = 1; app.export_json_button.Layout.Column = 3;
style_button(app.export_json_button, 'secondary', theme);
app.export_html_button = uibutton(action_row, 'Text', '< >  HTML Report');
app.export_html_button.Layout.Row = 1; app.export_html_button.Layout.Column = 4;
style_button(app.export_html_button, 'secondary', theme);
end

% ── Log panel ───────────────────────────────────────────────
function app = build_log_panel(outer, app, theme)
log_panel = uipanel(outer, 'Title', '', 'BorderType', 'line', 'BorderColor', theme.border);
log_panel.Layout.Row = 3;
log_panel.BackgroundColor = theme.surface;
app.log_panel = log_panel;
app.log_visible = true;
log_grid = uigridlayout(log_panel, [1 2]);
log_grid.Padding = [12 10 12 10];
log_grid.ColumnWidth = {70, '1x'};
log_grid.ColumnSpacing = 10;
log_grid.BackgroundColor = theme.surface;

log_hdr = uigridlayout(log_grid, [2 1]);
log_hdr.Layout.Row = 1; log_hdr.Layout.Column = 1;
log_hdr.Padding = [0 0 0 0];
log_hdr.RowHeight = {20, '1x'};
log_hdr.BackgroundColor = theme.surface;
log_title = uilabel(log_hdr, 'Text', 'RUN LOG');
log_title.Layout.Row = 1;
log_title.FontName = 'Segoe UI';
log_title.FontSize = 9;
log_title.FontWeight = 'bold';
log_title.FontColor = theme.primary;
app.log_indicator = uilabel(log_hdr, 'Text', '');
app.log_indicator.Layout.Row = 2;
app.log_indicator.FontName = 'Segoe UI';
app.log_indicator.FontSize = 9;
app.log_indicator.FontColor = theme.muted;
app.log_indicator.VerticalAlignment = 'top';

app.log_area = uitextarea(log_grid, 'Editable', 'off');
app.log_area.Layout.Row = 1; app.log_area.Layout.Column = 2;
app.log_area.FontName = 'Consolas';
app.log_area.FontSize = 10;
app.log_area.FontColor = theme.ink;
app.log_area.BackgroundColor = theme.surface_alt;
app.log_area.Value = {'Ready. Select a case and method, then click Run.'};
end

% ════════════════════════════════════════════════════════════
%  THEME
% ════════════════════════════════════════════════════════════
function theme = build_theme(mode)
switch mode
    case 'light'
        theme = struct( ...
            'canvas',      [0.929 0.945 0.955], ...
            'surface',      [1.0 1.0 1.0], ...
            'surface_alt',  [0.965 0.970 0.978], ...
            'table_bg',     [0.10 0.11 0.13], ...
            'table_text',   [0.96 0.96 0.96], ...
            'border',       [0.84 0.88 0.92], ...
            'ink',          [0.09 0.13 0.20], ...
            'muted',        [0.42 0.47 0.56], ...
            'primary',      [0.00 0.42 0.62], ...
            'primary_dark', [0.00 0.30 0.46], ...
            'accent',       [0.88 0.38 0.13], ...
            'success',      [0.14 0.50 0.32], ...
            'purple',       [0.40 0.27 0.68], ...
            'status',       [0.00 0.42 0.62], ...
            'warning',      [0.90 0.55 0.00], ...
            'danger',       [0.84 0.16 0.16]);
    case 'dark'
        theme = struct( ...
            'canvas',      [0.09 0.10 0.12], ...
            'surface',      [0.15 0.16 0.19], ...
            'surface_alt',  [0.19 0.20 0.24], ...
            'table_bg',     [0.18 0.19 0.22], ...
            'table_text',   [0.90 0.92 0.95], ...
            'border',       [0.26 0.29 0.34], ...
            'ink',          [0.90 0.92 0.95], ...
            'muted',        [0.58 0.61 0.66], ...
            'primary',      [0.32 0.66 0.86], ...
            'primary_dark', [0.22 0.46 0.63], ...
            'accent',       [0.96 0.58 0.22], ...
            'success',      [0.26 0.62 0.42], ...
            'purple',       [0.58 0.43 0.84], ...
            'status',       [0.32 0.66 0.86], ...
            'warning',      [0.96 0.67 0.12], ...
            'danger',       [0.92 0.28 0.28]);
end
end

% ════════════════════════════════════════════════════════════
%  WIDGET HELPERS
% ════════════════════════════════════════════════════════════
function s = toggle_label(kind, val)
% Short label strings for toggle buttons. The theme button shows the mode
% the user will switch TO (matching the original behaviour).
switch kind
    case 'theme'
        if strcmp(val, 'light'); s = '☾  Dark'; else; s = '☀  Light'; end
    case 'log'
        s = '☰  Hide Log';
end
end

function section_label(parent, text, row, theme)
lbl = uilabel(parent, 'Text', text);
lbl.Layout.Row = row;
lbl.FontName = 'Segoe UI';
lbl.FontSize = 9;
lbl.FontWeight = 'bold';
lbl.FontColor = theme.primary;
end

function labeled_field(parent, label_text, field_widget, row, theme)
inner = uigridlayout(parent, [1 2]);
inner.Layout.Row = row;
inner.ColumnWidth = {110, '1x'};
inner.ColumnSpacing = 10;
inner.Padding = [0 0 0 0];
inner.BackgroundColor = theme.surface;
lbl = uilabel(inner, 'Text', label_text);
lbl.Layout.Row = 1; lbl.Layout.Column = 1;
lbl.FontName = 'Segoe UI';
lbl.FontSize = 10;
lbl.FontColor = theme.muted;
lbl.HorizontalAlignment = 'right';
lbl.VerticalAlignment = 'center';
field_widget.Parent = inner;
field_widget.Layout.Row = 1; field_widget.Layout.Column = 2;
end

function style_button(button, variant, theme)
button.FontName = 'Segoe UI';
button.FontSize = 11;
button.FontWeight = 'bold';
switch variant
    case 'primary'
        button.BackgroundColor = theme.primary;
        button.FontColor = [1 1 1];
    case 'accent'
        button.BackgroundColor = theme.accent;
        button.FontColor = [1 1 1];
    case 'ghost'
        button.BackgroundColor = theme.surface_alt;
        button.FontColor = theme.ink;
    otherwise
        button.BackgroundColor = theme.surface_alt;
        button.FontColor = theme.ink;
end
end

function style_field(control, theme)
control.FontName = 'Segoe UI';
control.FontSize = 11;
control.FontColor = theme.ink;
control.BackgroundColor = theme.surface_alt;
end

function style_checkbox(control, theme)
control.FontName = 'Segoe UI';
control.FontSize = 11;
control.FontColor = theme.ink;
end

function style_axes(ax, ~)
plot_ink = [0.10 0.10 0.10];
plot_grid = [0.82 0.82 0.82];
ax.FontName = 'Segoe UI';
ax.FontSize = 10;
ax.Color = [1 1 1];               % keep plot area white, never black
ax.XColor = plot_ink;             % fixed dark text; readable in both app themes
ax.YColor = plot_ink;
ax.GridColor = plot_grid;
ax.MinorGridColor = [0.90 0.90 0.90];
ax.Box = 'on';
grid(ax, 'on');
ax.GridAlpha = 0.55;
ax.MinorGridAlpha = 0.35;
ax.Title.FontName = 'Segoe UI';
ax.Title.Color = plot_ink;
ax.Title.FontWeight = 'bold';
ax.XLabel.Color = plot_ink;
ax.YLabel.Color = plot_ink;
end

function [panel, title_label, value_label, caption_label] = create_metric_card(parent, column, title_text, value_text, caption_text, theme, accent)
panel = uipanel(parent, 'Title', '', 'BorderType', 'line');
panel.Layout.Row = 1;
panel.Layout.Column = column;
panel.BackgroundColor = theme.surface;
panel.BorderColor = soften(accent, 0.55);

grid = uigridlayout(panel, [1 2]);
grid.RowHeight = {'1x'};
grid.ColumnWidth = {5, '1x'};
grid.Padding = [0 0 0 0];
grid.ColumnSpacing = 0;
grid.BackgroundColor = theme.surface;

% Left accent stripe (full height, single row — no RowSpan needed)
stripe = uipanel(grid, 'Title', '', 'BorderType', 'none');
stripe.Layout.Row = 1; stripe.Layout.Column = 1;
stripe.BackgroundColor = accent;

content = uigridlayout(grid, [3 1]);
content.Layout.Row = 1; content.Layout.Column = 2;
content.RowHeight = {16, '1x', 16};
content.Padding = [10 8 10 10];
content.RowSpacing = 2;
content.BackgroundColor = theme.surface;

title_label = uilabel(content, 'Text', title_text);
title_label.Layout.Row = 1;
title_label.FontName = 'Segoe UI';
title_label.FontSize = 9;
title_label.FontWeight = 'bold';
title_label.FontColor = accent;

value_label = uilabel(content, 'Text', value_text);
value_label.Layout.Row = 2;
value_label.FontName = 'Segoe UI';
value_label.FontSize = 18;
value_label.FontWeight = 'bold';
value_label.FontColor = theme.ink;
value_label.VerticalAlignment = 'center';

caption_label = uilabel(content, 'Text', caption_text);
caption_label.Layout.Row = 3;
caption_label.FontName = 'Segoe UI';
caption_label.FontSize = 9;
caption_label.FontColor = theme.muted;
end

function color = soften(color, amount)
color = color + (1 - color) * amount;
end
