function show_cpf_result(app, cpf)
%SHOW_CPF_RESULT Display CPF results in table and PV-curve plots.

if isfield(cpf, 'bus_angle_deg') && size(cpf.bus_angle_deg, 2) == numel(cpf.lambdas)
    target_angle = cpf.bus_angle_deg(cpf.target_bus_index, :).';
else
    target_angle = nan(numel(cpf.lambdas), 1);
end
data = table(cpf.lambdas(:), cpf.target_voltage(:), target_angle, ...
    'VariableNames', {'lambda', sprintf('V_target_bus_%g', cpf.target_bus), sprintf('Angle_target_bus_%g', cpf.target_bus)});
app.result_table.Data = data;
pfapp.style_result_table(app, 'cpf');
if cpf.nose_detected
    status_value = 'Nose found';
    status_color = [0.83 0.20 0.15];
else
    status_value = 'Traced';
    status_color = [0.18 0.50 0.32];
end
pfapp.update_dashboard_metrics(app, ...
    {'CPF STATUS', 'POINTS', 'MAX LAMBDA', 'LOWEST V'}, ...
    {status_value, sprintf('%d', numel(cpf.lambdas)), sprintf('%.3f', max(cpf.lambdas)), sprintf('%.4f pu', min(cpf.target_voltage))}, ...
    {cpf.method, sprintf('Target bus %g', cpf.target_bus), cpf.stop_reason, 'Target-bus voltage'}, ...
    {status_color, [0.02 0.44 0.62], [0.86 0.38 0.13], [0.45 0.30 0.72]});

pfapp.reset_axes_state(app.ax_voltage);
plot(app.ax_voltage, cpf.lambdas, cpf.target_voltage, '-o', ...
    'Color', [0.83 0.20 0.15], 'MarkerFaceColor', [0.83 0.20 0.15], 'LineWidth', 2.0);
title(app.ax_voltage, sprintf('%s PV Curve', cpf.method), 'Interpreter', 'none');
xlabel(app.ax_voltage, '\lambda');
ylabel(app.ax_voltage, sprintf('|V| Bus %g pu', cpf.target_bus));
grid(app.ax_voltage, 'on');

pfapp.reset_axes_state(app.ax_conv);
if isfield(cpf, 'bus_angle_deg') && size(cpf.bus_angle_deg, 2) == numel(cpf.lambdas)
    plot(app.ax_conv, cpf.lambdas, cpf.bus_angle_deg', 'Color', [0.76 0.78 0.80], 'LineWidth', 0.7);
    hold(app.ax_conv, 'on');
    plot(app.ax_conv, cpf.lambdas, cpf.bus_angle_deg(cpf.target_bus_index, :), '-o', ...
        'Color', [0.83 0.20 0.15], 'LineWidth', 2.0, 'MarkerFaceColor', [0.83 0.20 0.15]);
    hold(app.ax_conv, 'off');
    title(app.ax_conv, sprintf('Voltage Angles, target bus %g highlighted', cpf.target_bus));
    ylabel(app.ax_conv, 'Angle (degree)');
else
    plot(app.ax_conv, cpf.lambdas, cpf.bus_voltage', 'Color', [0.76 0.78 0.80], 'LineWidth', 0.7);
    hold(app.ax_conv, 'on');
    plot(app.ax_conv, cpf.lambdas, cpf.bus_voltage(cpf.target_bus_index, :), '-o', ...
        'Color', [0.83 0.20 0.15], 'LineWidth', 2.0, 'MarkerFaceColor', [0.83 0.20 0.15]);
    hold(app.ax_conv, 'off');
    title(app.ax_conv, sprintf('Voltage Magnitudes, target bus %g highlighted', cpf.target_bus));
    ylabel(app.ax_conv, '|V| pu');
end
xlabel(app.ax_conv, '\lambda');
grid(app.ax_conv, 'on');
end
