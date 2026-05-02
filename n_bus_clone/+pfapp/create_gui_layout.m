function [fig, app] = create_gui_layout(app)
%CREATE_GUI_LAYOUT Modern web-app inspired layout with dark/light theme support.

persistent theme
if isempty(theme)
    theme = build_theme('light');
end

app.theme = theme;
app.theme_mode = 'light';

fig = uifigure('Name', 'N-Bus Power Flow Studio', ...
    'Position', [40 40 1340 820], ...
    'Color', theme.canvas, ...
    'Icon', '');
fig.CloseRequestFcn = @(src, event) delete(src);
fig.AutoResizeChildren = 'off';

% ── Outer grid: header + main + log ──
outer = uigridlayout(fig, [3 1]);
outer.Padding = [0 0 0 0];
outer.RowHeight = {52, '1x', 140};
outer.RowSpacing = 0;
outer.ColumnWidth = {'1x'};
outer.BackgroundColor = theme.canvas;
app.outer_grid = outer;
app.log_row_height = 140;

% ── Header bar ──────────────────────────────────────────────
header = uigridlayout(outer, [1 4]);
header.Layout.Row = 1;
header.Padding = [20 14 20 14];
header.RowHeight = {52};
header.ColumnWidth = {'1x', 120, 80, 120};
header.ColumnSpacing = 12;
header.BackgroundColor = theme.surface;

app.logo_label = uilabel(header, 'Text', 'N-Bus Studio');
app.logo_label.Layout.Row = 1;
app.logo_label.Layout.Column = 1;
app.logo_label.FontName = 'Segoe UI';
app.logo_label.FontSize = 18;
app.logo_label.FontWeight = 'bold';
app.logo_label.FontColor = theme.primary;
app.logo_label.HorizontalAlignment = 'left';
app.logo_label.VerticalAlignment = 'center';

app.theme_toggle = uibutton(header, 'Text', 'Dark Mode');
app.theme_toggle.Layout.Row = 1;
app.theme_toggle.Layout.Column = 2;
app.theme_toggle.FontName = 'Segoe UI';
app.theme_toggle.FontSize = 11;
app.theme_toggle.BackgroundColor = theme.surface_alt;
app.theme_toggle.FontColor = theme.ink;

app.log_toggle = uibutton(header, 'Text', 'Hide Log');
app.log_toggle.Layout.Row = 1;
app.log_toggle.Layout.Column = 3;
app.log_toggle.FontName = 'Segoe UI';
app.log_toggle.FontSize = 11;
app.log_toggle.BackgroundColor = theme.surface_alt;
app.log_toggle.FontColor = theme.ink;

app.version_label = uilabel(header, 'Text', 'v2.0');
app.version_label.Layout.Row = 1;
app.version_label.Layout.Column = 4;
app.version_label.FontName = 'Segoe UI';
app.version_label.FontSize = 10;
app.version_label.FontColor = theme.muted;
app.version_label.HorizontalAlignment = 'right';
app.version_label.VerticalAlignment = 'center';

% ── Main content grid ───────────────────────────────────────
main = uigridlayout(outer, [1 2]);
main.Layout.Row = 2;
main.Padding = [16 16 16 16];
main.ColumnWidth = {370, '1x'};
main.RowHeight = {'1x'};
main.ColumnSpacing = 14;
main.BackgroundColor = theme.canvas;

% ── Left sidebar ────────────────────────────────────────────
left_panel = uipanel(main, 'Title', '', 'BorderType', 'none');
left_panel.Layout.Row = 1;
left_panel.Layout.Column = 1;
left_panel.BackgroundColor = theme.surface;
left_panel.Scrollable = 'on';

left_grid = uigridlayout(left_panel, [1 1]);
left_grid.Padding = [0 0 0 0];
left_grid.RowHeight = {'1x'};
left_grid.ColumnWidth = {'1x'};
left_grid.BackgroundColor = theme.surface;

controls = uigridlayout(left_grid, [32 1]);
controls.RowHeight = {14, 40, 10, 36, 26, 36, 26, 14, 36, 26, 36, 26, 36, 26, 14, 36, 26, 36, 26, 36, 26, 36, 12, 42, 38, 38, 38, 38, 12, 22, '1x'};
controls.ColumnWidth = {'1x'};
controls.Padding = [16 12 16 16];
controls.RowSpacing = 6;
controls.Scrollable = 'on';
controls.BackgroundColor = theme.surface;

% Title
title_lbl = uilabel(controls, 'Text', 'Controls');
title_lbl.Layout.Row = 2;
title_lbl.FontName = 'Segoe UI';
title_lbl.FontSize = 22;
title_lbl.FontWeight = 'bold';
title_lbl.FontColor = theme.ink;

% ── Case section ──
section_label(controls, 'CASE', 4, theme);
app.case_dropdown = uidropdown(controls, 'Items', app.case_labels, 'Value', app.case_labels{1});
app.case_dropdown.Layout.Row = 5;
style_field(app.case_dropdown, theme);
app.browse_case_button = uibutton(controls, 'Text', '+ Browse Custom Case');
app.browse_case_button.Layout.Row = 6;
style_button(app.browse_case_button, 'ghost', theme);

% ── Method section ──
section_label(controls, 'METHOD', 8, theme);
app.method_dropdown = uidropdown(controls, ...
    'Items', {'Newton-Raphson', 'Gauss-Seidel', 'CPF Load Scaling', ...
              'CPF Predictor-Corrector', 'AC OPF', 'OPF Economic Dispatch', ...
              'Full 5-bus Suite'}, ...
    'Value', 'Newton-Raphson');
app.method_dropdown.Layout.Row = 9;
style_field(app.method_dropdown, theme);

% ── Solver params ──
section_label(controls, 'SOLVER PARAMETERS', 11, theme);
app.max_iter_field = uieditfield(controls, 'numeric', ...
    'Value', 300, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
labeled_field(controls, 'Max Iterations', app.max_iter_field, 12, theme);

app.tolerance_field = uieditfield(controls, 'numeric', ...
    'Value', 1e-6, 'Limits', [eps Inf]);
labeled_field(controls, 'Tolerance', app.tolerance_field, 13, theme);

app.accel_field = uieditfield(controls, 'numeric', ...
    'Value', 1.4, 'Limits', [0.1 2.0]);
labeled_field(controls, 'GS Acceleration', app.accel_field, 14, theme);

% ── CPF Setup ──
section_label(controls, 'CPF CONFIGURATION', 16, theme);
app.target_bus_field = uieditfield(controls, 'numeric', ...
    'Value', 5, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
labeled_field(controls, 'Target Bus', app.target_bus_field, 17, theme);

app.lambda_step_field = uieditfield(controls, 'numeric', ...
    'Value', 0.05, 'Limits', [eps Inf]);
labeled_field(controls, 'Lambda Step', app.lambda_step_field, 18, theme);

app.lambda_max_field = uieditfield(controls, 'numeric', ...
    'Value', 3.0, 'Limits', [eps Inf]);
labeled_field(controls, 'Lambda Max', app.lambda_max_field, 19, theme);

app.min_voltage_field = uieditfield(controls, 'numeric', ...
    'Value', 0.65, 'Limits', [0.01 2.0]);
labeled_field(controls, 'Min Voltage (pu)', app.min_voltage_field, 20, theme);

% ── Options ──
section_label(controls, 'OPTIONS', 22, theme);
app.q_limit_checkbox = uicheckbox(controls, 'Text', 'Enforce Q limits (PV -> PQ)', 'Value', true);
app.q_limit_checkbox.Layout.Row = 23;
style_checkbox(app.q_limit_checkbox, theme);

app.auto_cpf_checkbox = uicheckbox(controls, 'Text', 'Auto CPF setup from base NR', 'Value', true);
app.auto_cpf_checkbox.Layout.Row = 24;
style_checkbox(app.auto_cpf_checkbox, theme);

app.auto_separate_checkbox = uicheckbox(controls, 'Text', 'Auto open plots after Run', 'Value', true);
app.auto_separate_checkbox.Layout.Row = 25;
style_checkbox(app.auto_separate_checkbox, theme);

% ── Action buttons ──
app.run_button = uibutton(controls, 'Text', 'Run Analysis');
app.run_button.Layout.Row = 26;
style_button(app.run_button, 'primary', theme);

btn_row = uigridlayout(controls, [1 2]);
btn_row.Layout.Row = 27;
btn_row.ColumnWidth = {'1x', '1x'};
btn_row.ColumnSpacing = 8;
btn_row.Padding = [0 0 0 0];
btn_row.BackgroundColor = theme.surface;

app.export_button = uibutton(btn_row, 'Text', 'Export');
app.export_button.Layout.Row = 1;
app.export_button.Layout.Column = 1;
style_button(app.export_button, 'secondary', theme);

app.tests_button = uibutton(btn_row, 'Text', 'Tests');
app.tests_button.Layout.Row = 1;
app.tests_button.Layout.Column = 2;
style_button(app.tests_button, 'accent', theme);

btn_row2 = uigridlayout(controls, [1 2]);
btn_row2.Layout.Row = 28;
btn_row2.ColumnWidth = {'1x', '1x'};
btn_row2.ColumnSpacing = 8;
btn_row2.Padding = [0 0 0 0];
btn_row2.BackgroundColor = theme.surface;

app.ai_analyze_button = uibutton(btn_row2, 'Text', 'AI Analyze');
app.ai_analyze_button.Layout.Row = 1;
app.ai_analyze_button.Layout.Column = 1;
style_button(app.ai_analyze_button, 'accent', theme);

app.clear_button = uibutton(btn_row2, 'Text', 'Clear Log');
app.clear_button.Layout.Row = 1;
app.clear_button.Layout.Column = 2;
style_button(app.clear_button, 'ghost', theme);

btn_row3 = uigridlayout(controls, [1 2]);
btn_row3.Layout.Row = 29;
btn_row3.ColumnWidth = {'1x', '1x'};
btn_row3.ColumnSpacing = 8;
btn_row3.Padding = [0 0 0 0];
btn_row3.BackgroundColor = theme.surface;

app.open_output_button = uibutton(btn_row3, 'Text', 'Output Dir');
app.open_output_button.Layout.Row = 1;
app.open_output_button.Layout.Column = 1;
style_button(app.open_output_button, 'ghost', theme);

% ── Help card ──
help_card = uipanel(controls, 'Title', '', 'BorderType', 'line');
help_card.Layout.Row = 30;
help_card.BackgroundColor = theme.surface_alt;
help_card.BorderColor = theme.border;
help_card_gr = uigridlayout(help_card, [1 1]);
help_card_gr.Padding = [10 10 10 10];
help_card_gr.BackgroundColor = theme.surface_alt;
app.help_text = uitextarea(help_card_gr, 'Editable', 'off');
app.help_text.FontName = 'Segoe UI';
app.help_text.FontSize = 10;
app.help_text.FontColor = theme.muted;
app.help_text.BackgroundColor = theme.surface_alt;
app.help_text.Value = { ...
    'Tips:', ...
    '- Saadat 30-bus is the primary AC OPF validation case.', ...
    '- CPF auto setup runs base NR for stable defaults.', ...
    '- Exports write CSV/JSON/HTML/XLSX under ./output.', ...
    '- Use Dark mode toggle for low-light work.'};

% ── Right content area ──────────────────────────────────────
right = uigridlayout(main, [3 1]);
right.Padding = [0 0 0 0];
right.RowHeight = {88, '1x', 160};
right.RowSpacing = 14;
right.ColumnWidth = {'1x'};
right.BackgroundColor = theme.canvas;

% ── Metric cards row ──
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

% ── Main content tabs ──
tab_group = uitabgroup(right);
tab_group.Layout.Row = 2;

% Tab 1: Analysis plots
plot_tab = uitab(tab_group, 'Title', 'Analysis');
plot_tab.BackgroundColor = theme.surface;
plot_grid = uigridlayout(plot_tab, [1 2]);
plot_grid.ColumnWidth = {'1x', '1x'};
plot_grid.Padding = [14 10 14 14];
plot_grid.ColumnSpacing = 14;
plot_grid.BackgroundColor = theme.surface;

app.ax_voltage = uiaxes(plot_grid);
app.ax_voltage.Layout.Row = 1;
app.ax_voltage.Layout.Column = 1;
style_axes(app.ax_voltage, theme);

app.ax_conv = uiaxes(plot_grid);
app.ax_conv.Layout.Row = 1;
app.ax_conv.Layout.Column = 2;
style_axes(app.ax_conv, theme);

% Tab 2: Results table
table_tab = uitab(tab_group, 'Title', 'Results Table');
table_tab.BackgroundColor = theme.surface;
table_pg = uigridlayout(table_tab, [1 1]);
table_pg.Padding = [14 10 14 14];
table_pg.BackgroundColor = theme.surface;

app.result_table = uitable(table_pg);
app.result_table.Layout.Row = 1;
app.result_table.Layout.Column = 1;
app.result_table.FontName = 'Segoe UI';
app.result_table.FontSize = 11;
app.result_table.BackgroundColor = [1 1 1; theme.surface_alt];
app.result_table.ForegroundColor = theme.ink;
app.result_table.ColumnWidth = 'auto';

% Tab 3: Advanced plots
adv_tab = uitab(tab_group, 'Title', 'Advanced Plots');
adv_tab.BackgroundColor = theme.surface;
adv_pg = uigridlayout(adv_tab, [1 2]);
adv_pg.ColumnWidth = {'1x', '1x'};
adv_pg.Padding = [14 10 14 14];
adv_pg.ColumnSpacing = 14;
adv_pg.BackgroundColor = theme.surface;

app.ax_cpf = uiaxes(adv_pg);
app.ax_cpf.Layout.Row = 1;
app.ax_cpf.Layout.Column = 1;
style_axes(app.ax_cpf, theme);

app.ax_opf = uiaxes(adv_pg);
app.ax_opf.Layout.Row = 1;
app.ax_opf.Layout.Column = 2;
style_axes(app.ax_opf, theme);

% Tab 4: AI Chat
chat_tab = uitab(tab_group, 'Title', 'AI Chat');
chat_tab.BackgroundColor = theme.surface;
chat_pg = uigridlayout(chat_tab, [2 1]);
chat_pg.RowHeight = {'1x', 60};
chat_pg.RowSpacing = 8;
chat_pg.Padding = [14 10 14 14];
chat_pg.BackgroundColor = theme.surface;

app.ai_chat_display = uitextarea(chat_pg, 'Editable', 'off');
app.ai_chat_display.Layout.Row = 1;
app.ai_chat_display.FontName = 'Segoe UI';
app.ai_chat_display.FontSize = 11;
app.ai_chat_display.FontColor = theme.ink;
app.ai_chat_display.BackgroundColor = theme.surface_alt;
app.ai_chat_display.Value = {'AI chat panel — ask questions about your power flow results.', ...
    '', 'Make sure the AI service is running:', ...
    '  cd ai_service && python server.py'};

chat_input_row = uigridlayout(chat_pg, [1 2]);
chat_input_row.Layout.Row = 2;
chat_input_row.ColumnWidth = {'1x', 80};
chat_input_row.ColumnSpacing = 8;
chat_input_row.Padding = [0 0 0 0];
chat_input_row.BackgroundColor = theme.surface;

app.ai_chat_input = uieditfield(chat_input_row, 'text', ...
    'Placeholder', 'Type your question...');
app.ai_chat_input.Layout.Row = 1;
app.ai_chat_input.Layout.Column = 1;
app.ai_chat_input.FontName = 'Segoe UI';
app.ai_chat_input.FontSize = 12;
app.ai_chat_input.FontColor = theme.ink;
app.ai_chat_input.BackgroundColor = theme.surface_alt;

app.ai_send_button = uibutton(chat_input_row, 'Text', 'Send');
app.ai_send_button.Layout.Row = 1;
app.ai_send_button.Layout.Column = 2;
style_button(app.ai_send_button, 'primary', theme);

% Actions row under tabs
action_row = uigridlayout(right, [1 4]);
action_row.Layout.Row = 3;
action_row.ColumnWidth = {'1x', '1x', '1x', '1x'};
action_row.ColumnSpacing = 10;
action_row.Padding = [0 0 0 0];
action_row.BackgroundColor = theme.canvas;

app.separate_plot_button = uibutton(action_row, 'Text', 'Separate Plots');
app.separate_plot_button.Layout.Row = 1;
app.separate_plot_button.Layout.Column = 1;
style_button(app.separate_plot_button, 'secondary', theme);

app.analysis_plot_button = uibutton(action_row, 'Text', 'Analysis Plots');
app.analysis_plot_button.Layout.Row = 1;
app.analysis_plot_button.Layout.Column = 2;
style_button(app.analysis_plot_button, 'secondary', theme);

app.export_json_button = uibutton(action_row, 'Text', '{ } JSON Export');
app.export_json_button.Layout.Row = 1;
app.export_json_button.Layout.Column = 3;
style_button(app.export_json_button, 'secondary', theme);

app.export_html_button = uibutton(action_row, 'Text', '< > HTML Report');
app.export_html_button.Layout.Row = 1;
app.export_html_button.Layout.Column = 4;
style_button(app.export_html_button, 'secondary', theme);

% ── Log panel (collapsible) ──
log_panel = uipanel(outer, 'Title', 'Run Log', 'BorderType', 'none');
log_panel.Layout.Row = 3;
log_panel.BackgroundColor = theme.surface;
app.log_panel = log_panel;
log_grid = uigridlayout(log_panel, [1 1]);
log_grid.Padding = [14 10 14 14];
log_grid.BackgroundColor = theme.surface;

app.log_area = uitextarea(log_grid, 'Editable', 'off');
app.log_area.FontName = 'Consolas';
app.log_area.FontSize = 10;
app.log_area.FontColor = theme.ink;
app.log_area.BackgroundColor = theme.surface_alt;
app.log_area.Value = {'Ready. Select a case and method, then click Run.'};
end

% ── Theme builder ───────────────────────────────────────────
function theme = build_theme(mode)
switch mode
    case 'light'
        theme = struct( ...
            'canvas',     [0.945 0.955 0.965], ...
            'surface',    [1.0 1.0 1.0], ...
            'surface_alt',[0.965 0.970 0.980], ...
            'border',     [0.82 0.86 0.91], ...
            'ink',        [0.08 0.12 0.20], ...
            'muted',      [0.40 0.45 0.55], ...
            'primary',    [0.00 0.40 0.60], ...
            'primary_dark',[0.00 0.28 0.42], ...
            'accent',     [0.85 0.36 0.12], ...
            'success',    [0.15 0.48 0.30], ...
            'purple',     [0.42 0.28 0.70], ...
            'status',     [0.00 0.40 0.60], ...
            'warning',    [0.90 0.55 0.00], ...
            'danger',     [0.85 0.15 0.15]);
    case 'dark'
        theme = struct( ...
            'canvas',     [0.08 0.09 0.11], ...
            'surface',    [0.14 0.15 0.17], ...
            'surface_alt',[0.18 0.19 0.22], ...
            'border',     [0.25 0.28 0.33], ...
            'ink',        [0.88 0.90 0.93], ...
            'muted',      [0.55 0.58 0.63], ...
            'primary',    [0.30 0.65 0.85], ...
            'primary_dark',[0.20 0.45 0.62], ...
            'accent',     [0.95 0.55 0.20], ...
            'success',    [0.25 0.60 0.40], ...
            'purple',     [0.55 0.40 0.82], ...
            'status',     [0.30 0.65 0.85], ...
            'warning',    [0.95 0.65 0.10], ...
            'danger',     [0.90 0.25 0.25]);
end
end

% ── Widget helpers ──────────────────────────────────────────
function section_label(parent, text, row, theme)
lbl = uilabel(parent, 'Text', text);
lbl.Layout.Row = row;
lbl.FontName = 'Segoe UI';
lbl.FontSize = 10;
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
lbl.Layout.Row = 1;
lbl.Layout.Column = 1;
lbl.FontName = 'Segoe UI';
lbl.FontSize = 11;
lbl.FontColor = theme.muted;
lbl.HorizontalAlignment = 'right';
lbl.VerticalAlignment = 'center';

field_widget.Parent = inner;
field_widget.Layout.Row = 1;
field_widget.Layout.Column = 2;
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
        button.BackgroundColor = theme.surface;
        button.FontColor = theme.muted;
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

function style_axes(ax, theme)
ax.FontName = 'Segoe UI';
ax.FontSize = 10;
ax.Color = theme.surface_alt;
ax.XColor = theme.muted;
ax.YColor = theme.muted;
ax.GridColor = [0.75 0.80 0.87];
ax.MinorGridColor = [0.86 0.90 0.94];
ax.Box = 'on';
grid(ax, 'on');
ax.GridAlpha = 0.4;
end

function [panel, title_label, value_label, caption_label] = create_metric_card(parent, column, title_text, value_text, caption_text, theme, accent)
panel = uipanel(parent, 'Title', '', 'BorderType', 'line');
panel.Layout.Row = 1;
panel.Layout.Column = column;
panel.BackgroundColor = theme.surface;
panel.BorderColor = soften(accent, 0.6);

grid = uigridlayout(panel, [3 1]);
grid.RowHeight = {16, '1x', 16};
grid.ColumnWidth = {'1x'};
grid.Padding = [12 8 12 10];
grid.RowSpacing = 2;
grid.BackgroundColor = theme.surface;

title_label = uilabel(grid, 'Text', title_text);
title_label.Layout.Row = 1;
title_label.FontName = 'Segoe UI';
title_label.FontSize = 9;
title_label.FontWeight = 'bold';
title_label.FontColor = accent;

value_label = uilabel(grid, 'Text', value_text);
value_label.Layout.Row = 2;
value_label.FontName = 'Segoe UI';
value_label.FontSize = 20;
value_label.FontWeight = 'bold';
value_label.FontColor = theme.ink;

caption_label = uilabel(grid, 'Text', caption_text);
caption_label.Layout.Row = 3;
caption_label.FontName = 'Segoe UI';
caption_label.FontSize = 9;
caption_label.FontColor = theme.muted;
end

function color = soften(color, amount)
color = color + (1 - color) * amount;
end

function on_fig_resize()
    % Keep log panel at reasonable height on resize
    if isfield(app, 'log_visible') && ~app.log_visible
        app.outer_grid.RowHeight = {52, '1x', 0};
    end
end
