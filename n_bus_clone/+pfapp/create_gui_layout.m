function [fig, app] = create_gui_layout(app)
%CREATE_GUI_LAYOUT Build the uifigure, panels, and widgets. No callbacks wired.

theme = struct( ...
    'canvas', [0.94 0.96 0.98], ...
    'surface', [1.00 1.00 1.00], ...
    'surface_alt', [0.97 0.98 1.00], ...
    'border', [0.82 0.86 0.91], ...
    'ink', [0.09 0.13 0.20], ...
    'muted', [0.39 0.45 0.55], ...
    'primary', [0.02 0.44 0.62], ...
    'primary_dark', [0.02 0.31 0.44], ...
    'accent', [0.86 0.38 0.13], ...
    'success', [0.18 0.50 0.32]);

fig = uifigure('Name', 'N-Bus Power Flow Studio', 'Position', [60 60 1280 780], ...
    'Color', theme.canvas);
fig.CloseRequestFcn = @(src, event) delete(src);

main = uigridlayout(fig, [1 2]);
main.ColumnWidth = {360, '1x'};
main.RowHeight = {'1x'};
main.Padding = [18 18 18 18];
main.ColumnSpacing = 16;
main.BackgroundColor = theme.canvas;

left = uipanel(main, 'Title', '');
left.Layout.Row = 1;
left.Layout.Column = 1;
style_panel(left, theme);

controls = uigridlayout(left, [28 2]);
controls.RowHeight = {36, 20, 10, 22, 34, 34, 22, 34, 22, 34, 22, 34, 22, 34, 22, 34, 22, 34, 24, 24, 10, 38, 36, 36, 36, 12, 22, '1x'};
controls.ColumnWidth = {'1x', '1x'};
controls.Padding = [16 16 16 16];
controls.RowSpacing = 8;
controls.ColumnSpacing = 10;
controls.Scrollable = 'on';
controls.BackgroundColor = theme.surface;

title_label = uilabel(controls, 'Text', 'N-Bus Studio');
title_label.Layout.Row = 1;
title_label.Layout.Column = [1 2];
title_label.FontName = 'Segoe UI Semibold';
title_label.FontSize = 23;
title_label.FontWeight = 'bold';
title_label.FontColor = theme.ink;

subtitle_label = uilabel(controls, 'Text', 'PF / CPF / AC OPF analysis workspace');
subtitle_label.Layout.Row = 2;
subtitle_label.Layout.Column = [1 2];
subtitle_label.FontName = 'Segoe UI';
subtitle_label.FontSize = 11;
subtitle_label.FontColor = theme.muted;

right = uigridlayout(main, [4 1]);
right.Layout.Row = 1;
right.Layout.Column = 2;
right.RowHeight = {96, 300, '1x', 145};
right.ColumnWidth = {'1x'};
right.RowSpacing = 14;
right.BackgroundColor = theme.canvas;

metric_panel = uipanel(right, 'Title', '');
metric_panel.Layout.Row = 1;
style_panel(metric_panel, theme);
metric_grid = uigridlayout(metric_panel, [1 4]);
metric_grid.ColumnWidth = {'1x', '1x', '1x', '1x'};
metric_grid.RowHeight = {'1x'};
metric_grid.Padding = [10 10 10 10];
metric_grid.ColumnSpacing = 10;
metric_grid.BackgroundColor = theme.surface;
[app.metric_card_1, app.metric_title_1, app.metric_value_1, app.metric_caption_1] = ...
    create_metric_card(metric_grid, 1, 'STATUS', 'Ready', 'Awaiting run', theme, theme.primary);
[app.metric_card_2, app.metric_title_2, app.metric_value_2, app.metric_caption_2] = ...
    create_metric_card(metric_grid, 2, 'CASE', '5-bus', 'Demo system', theme, theme.accent);
[app.metric_card_3, app.metric_title_3, app.metric_value_3, app.metric_caption_3] = ...
    create_metric_card(metric_grid, 3, 'METHOD', 'NR', 'Newton-Raphson', theme, theme.success);
[app.metric_card_4, app.metric_title_4, app.metric_value_4, app.metric_caption_4] = ...
    create_metric_card(metric_grid, 4, 'FOCUS', '30-bus', 'Primary OPF validation', theme, [0.45 0.30 0.72]);

plot_panel = uipanel(right, 'Title', 'Analysis Dashboard');
plot_panel.Layout.Row = 2;
style_panel(plot_panel, theme);
plot_grid = uigridlayout(plot_panel, [1 2]);
plot_grid.ColumnWidth = {'1x', '1x'};
plot_grid.Padding = [12 10 12 12];
plot_grid.ColumnSpacing = 12;
plot_grid.BackgroundColor = theme.surface;
app.ax_voltage = uiaxes(plot_grid);
app.ax_voltage.Layout.Row = 1;
app.ax_voltage.Layout.Column = 1;
style_axes(app.ax_voltage, theme);
app.ax_conv = uiaxes(plot_grid);
app.ax_conv.Layout.Row = 1;
app.ax_conv.Layout.Column = 2;
style_axes(app.ax_conv, theme);

table_panel = uipanel(right, 'Title', 'Results Table');
table_panel.Layout.Row = 3;
style_panel(table_panel, theme);
table_grid = uigridlayout(table_panel, [1 1]);
table_grid.Padding = [12 10 12 12];
table_grid.BackgroundColor = theme.surface;
app.result_table = uitable(table_grid);
app.result_table.Layout.Row = 1;
app.result_table.Layout.Column = 1;
app.result_table.FontName = 'Segoe UI';
app.result_table.FontSize = 12;
app.result_table.BackgroundColor = [1 1 1; theme.surface_alt];
app.result_table.ForegroundColor = theme.ink;

log_panel = uipanel(right, 'Title', 'Run Log');
log_panel.Layout.Row = 4;
style_panel(log_panel, theme);
log_grid = uigridlayout(log_panel, [1 1]);
log_grid.Padding = [12 10 12 12];
log_grid.BackgroundColor = theme.surface;
app.log_area = uitextarea(log_grid, 'Editable', 'off');
app.log_area.FontName = 'Consolas';
app.log_area.FontSize = 11;
app.log_area.FontColor = theme.ink;
app.log_area.BackgroundColor = [0.98 0.99 1.00];
app.log_area.Value = {'Ready. Select a case/method, then click Run.'};

section_label(controls, 'Case and Method', 4, theme);
field_label(controls, 'Case', 5, 1, theme);
app.case_dropdown = uidropdown(controls, ...
    'Items', app.case_labels, ...
    'Value', '5-bus demo');
app.case_dropdown.Layout.Row = 5;
app.case_dropdown.Layout.Column = 2;
style_field(app.case_dropdown, theme);
app.browse_case_button = uibutton(controls, 'Text', 'Browse Custom n-bus Case');
app.browse_case_button.Layout.Row = 6;
app.browse_case_button.Layout.Column = [1 2];
style_button(app.browse_case_button, 'secondary', theme);

field_label(controls, 'Method', 7, 1, theme);
app.method_dropdown = uidropdown(controls, ...
    'Items', {'Newton-Raphson', 'Gauss-Seidel', 'CPF Load Scaling', 'CPF Predictor-Corrector', 'AC OPF', 'OPF Economic Dispatch', 'Full 5-bus Suite'}, ...
    'Value', 'Newton-Raphson');
app.method_dropdown.Layout.Row = 7;
app.method_dropdown.Layout.Column = 2;
style_field(app.method_dropdown, theme);

section_label(controls, 'Solver Controls', 9, theme);
field_label(controls, 'Max Iter', 10, 1, theme);
app.max_iter_field = uieditfield(controls, 'numeric', 'Value', 300, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
app.max_iter_field.Layout.Row = 10;
app.max_iter_field.Layout.Column = 2;
style_field(app.max_iter_field, theme);

field_label(controls, 'Tolerance', 11, 1, theme);
app.tolerance_field = uieditfield(controls, 'numeric', 'Value', 1e-6, 'Limits', [eps Inf]);
app.tolerance_field.Layout.Row = 11;
app.tolerance_field.Layout.Column = 2;
style_field(app.tolerance_field, theme);

field_label(controls, 'GS Acceleration', 12, 1, theme);
app.accel_field = uieditfield(controls, 'numeric', 'Value', 1.4, 'Limits', [0.1 2.0]);
app.accel_field.Layout.Row = 12;
app.accel_field.Layout.Column = 2;
style_field(app.accel_field, theme);

field_label(controls, 'Enforce Q limits', 13, 1, theme);
app.q_limit_checkbox = uicheckbox(controls, 'Text', 'PV -> PQ', 'Value', true);
app.q_limit_checkbox.Layout.Row = 13;
app.q_limit_checkbox.Layout.Column = 2;
style_checkbox(app.q_limit_checkbox, theme);

section_label(controls, 'CPF Setup', 15, theme);
field_label(controls, 'Target bus', 16, 1, theme);
app.target_bus_field = uieditfield(controls, 'numeric', 'Value', 5, 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
app.target_bus_field.Layout.Row = 16;
app.target_bus_field.Layout.Column = 2;
style_field(app.target_bus_field, theme);

field_label(controls, 'Lambda step', 17, 1, theme);
app.lambda_step_field = uieditfield(controls, 'numeric', 'Value', 0.05, 'Limits', [eps Inf]);
app.lambda_step_field.Layout.Row = 17;
app.lambda_step_field.Layout.Column = 2;
style_field(app.lambda_step_field, theme);

field_label(controls, 'Lambda max', 18, 1, theme);
app.lambda_max_field = uieditfield(controls, 'numeric', 'Value', 3.0, 'Limits', [eps Inf]);
app.lambda_max_field.Layout.Row = 18;
app.lambda_max_field.Layout.Column = 2;
style_field(app.lambda_max_field, theme);

field_label(controls, 'Min voltage', 19, 1, theme);
app.min_voltage_field = uieditfield(controls, 'numeric', 'Value', 0.65, 'Limits', [0.01 2.0]);
app.min_voltage_field.Layout.Row = 19;
app.min_voltage_field.Layout.Column = 2;
style_field(app.min_voltage_field, theme);

app.auto_cpf_checkbox = uicheckbox(controls, ...
    'Text', 'Auto CPF setup from base NR', ...
    'Value', true);
app.auto_cpf_checkbox.Layout.Row = 20;
app.auto_cpf_checkbox.Layout.Column = [1 2];
style_checkbox(app.auto_cpf_checkbox, theme);

app.auto_separate_checkbox = uicheckbox(controls, ...
    'Text', 'Auto open separate plots after Run', ...
    'Value', true);
app.auto_separate_checkbox.Layout.Row = 21;
app.auto_separate_checkbox.Layout.Column = [1 2];
style_checkbox(app.auto_separate_checkbox, theme);

app.run_button = uibutton(controls, 'Text', 'Run');
app.run_button.Layout.Row = 22;
app.run_button.Layout.Column = [1 2];
style_button(app.run_button, 'primary', theme);
app.export_button = uibutton(controls, 'Text', 'Export Last Result');
app.export_button.Layout.Row = 23;
app.export_button.Layout.Column = 1;
style_button(app.export_button, 'secondary', theme);

app.tests_button = uibutton(controls, 'Text', 'Run Tests');
app.tests_button.Layout.Row = 23;
app.tests_button.Layout.Column = 2;
style_button(app.tests_button, 'success', theme);
app.clear_button = uibutton(controls, 'Text', 'Clear Log');
app.clear_button.Layout.Row = 24;
app.clear_button.Layout.Column = 1;
style_button(app.clear_button, 'quiet', theme);

app.separate_plot_button = uibutton(controls, 'Text', 'Open Separate Plots');
app.separate_plot_button.Layout.Row = 24;
app.separate_plot_button.Layout.Column = 2;
style_button(app.separate_plot_button, 'secondary', theme);
app.analysis_plot_button = uibutton(controls, 'Text', '3D / CPF Ref Plots');
app.analysis_plot_button.Layout.Row = 25;
app.analysis_plot_button.Layout.Column = 1;
style_button(app.analysis_plot_button, 'secondary', theme);
app.open_output_button = uibutton(controls, 'Text', 'Show Output Path');
app.open_output_button.Layout.Row = 25;
app.open_output_button.Layout.Column = 2;
style_button(app.open_output_button, 'quiet', theme);

help_text = uitextarea(controls, 'Editable', 'off');
help_text.Layout.Row = [27 28];
help_text.Layout.Column = [1 2];
help_text.FontName = 'Segoe UI';
help_text.FontSize = 11;
help_text.FontColor = theme.muted;
help_text.BackgroundColor = theme.surface_alt;
help_text.Value = { ...
    'Operational notes', ...
    'Saadat 30-bus is the main AC OPF validation case.', ...
    'AC OPF uses only project-owned NR/search routines.', ...
    'CPF auto setup runs base NR and picks stable defaults.', ...
    'Exports write CSV/TXT/PDF/PNG under ./output.'};
end

function section_label(parent, text, row, theme)
label = uilabel(parent, 'Text', upper(text));
label.Layout.Row = row;
label.Layout.Column = [1 2];
label.FontName = 'Segoe UI Semibold';
label.FontSize = 11;
label.FontWeight = 'bold';
label.FontColor = theme.primary_dark;
end

function label = field_label(parent, text, row, col, theme)
label = uilabel(parent, 'Text', text);
label.Layout.Row = row;
label.Layout.Column = col;
label.FontName = 'Segoe UI';
label.FontSize = 12;
label.FontColor = theme.muted;
end

function style_panel(panel, theme)
panel.BackgroundColor = theme.surface;
panel.ForegroundColor = theme.ink;
panel.BorderColor = theme.border;
panel.FontName = 'Segoe UI Semibold';
panel.FontSize = 12;
panel.FontWeight = 'bold';
end

function style_button(button, variant, theme)
button.FontName = 'Segoe UI Semibold';
button.FontSize = 12;
button.FontWeight = 'bold';
switch variant
    case 'primary'
        button.BackgroundColor = theme.primary;
        button.FontColor = [1 1 1];
    case 'success'
        button.BackgroundColor = theme.success;
        button.FontColor = [1 1 1];
    case 'quiet'
        button.BackgroundColor = theme.surface_alt;
        button.FontColor = theme.muted;
    otherwise
        button.BackgroundColor = [0.89 0.93 0.96];
        button.FontColor = theme.primary_dark;
end
end

function style_field(control, theme)
control.FontName = 'Segoe UI';
control.FontSize = 12;
control.FontColor = theme.ink;
control.BackgroundColor = [0.99 1.00 1.00];
end

function style_checkbox(control, theme)
control.FontName = 'Segoe UI';
control.FontSize = 12;
control.FontColor = theme.ink;
end

function style_axes(ax, theme)
ax.FontName = 'Segoe UI';
ax.FontSize = 11;
ax.Color = [0.985 0.990 1.000];
ax.XColor = theme.muted;
ax.YColor = theme.muted;
ax.GridColor = [0.74 0.80 0.87];
ax.MinorGridColor = [0.86 0.90 0.94];
ax.Box = 'on';
grid(ax, 'on');
end

function [panel, title_label, value_label, caption_label] = create_metric_card(parent, column, title_text, value_text, caption_text, theme, accent)
panel = uipanel(parent, 'Title', '', 'BorderType', 'line');
panel.Layout.Row = 1;
panel.Layout.Column = column;
panel.BackgroundColor = theme.surface_alt;
panel.BorderColor = lighten(accent, 0.55);

grid = uigridlayout(panel, [3 1]);
grid.RowHeight = {18, '1x', 18};
grid.ColumnWidth = {'1x'};
grid.Padding = [10 7 10 7];
grid.RowSpacing = 2;
grid.BackgroundColor = theme.surface_alt;

title_label = uilabel(grid, 'Text', title_text);
title_label.Layout.Row = 1;
title_label.FontName = 'Segoe UI Semibold';
title_label.FontSize = 10;
title_label.FontWeight = 'bold';
title_label.FontColor = accent;

value_label = uilabel(grid, 'Text', value_text);
value_label.Layout.Row = 2;
value_label.FontName = 'Segoe UI Semibold';
value_label.FontSize = 18;
value_label.FontWeight = 'bold';
value_label.FontColor = theme.ink;

caption_label = uilabel(grid, 'Text', caption_text);
caption_label.Layout.Row = 3;
caption_label.FontName = 'Segoe UI';
caption_label.FontSize = 10;
caption_label.FontColor = theme.muted;
end

function color = lighten(color, amount)
color = color + (1 - color) * amount;
end
