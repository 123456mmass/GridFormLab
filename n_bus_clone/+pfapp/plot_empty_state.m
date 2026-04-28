function plot_empty_state(app)
%PLOT_EMPTY_STATE Clear both axes with placeholder titles.

pfapp.reset_axes_state(app.ax_voltage);
cla(app.ax_voltage);
app.ax_voltage.Color = [0.985 0.990 1.000];
app.ax_voltage.XTick = [];
app.ax_voltage.YTick = [];
app.ax_voltage.XLim = [0 1];
app.ax_voltage.YLim = [0 1];
text(app.ax_voltage, 0.5, 0.58, 'Voltage and Stability', ...
    'HorizontalAlignment', 'center', 'FontName', 'Segoe UI Semibold', ...
    'FontSize', 16, 'Color', [0.09 0.13 0.20]);
text(app.ax_voltage, 0.5, 0.44, 'Run PF, CPF, or AC OPF to populate this panel.', ...
    'HorizontalAlignment', 'center', 'FontName', 'Segoe UI', ...
    'FontSize', 11, 'Color', [0.39 0.45 0.55]);
title(app.ax_voltage, '');
box(app.ax_voltage, 'on');

pfapp.reset_axes_state(app.ax_conv);
cla(app.ax_conv);
app.ax_conv.Color = [0.985 0.990 1.000];
app.ax_conv.XTick = [];
app.ax_conv.YTick = [];
app.ax_conv.XLim = [0 1];
app.ax_conv.YLim = [0 1];
text(app.ax_conv, 0.5, 0.58, 'Convergence and Dispatch', ...
    'HorizontalAlignment', 'center', 'FontName', 'Segoe UI Semibold', ...
    'FontSize', 16, 'Color', [0.09 0.13 0.20]);
text(app.ax_conv, 0.5, 0.44, 'Iterations, CPF curve, or OPF loading appears here.', ...
    'HorizontalAlignment', 'center', 'FontName', 'Segoe UI', ...
    'FontSize', 11, 'Color', [0.39 0.45 0.55]);
title(app.ax_conv, '');
box(app.ax_conv, 'on');
end
