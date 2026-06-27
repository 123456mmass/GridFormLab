function show_powerflow_result(app, result, tolerance)
%SHOW_POWERFLOW_RESULT Display NR/GS results in table and plots.

axis_info = pf_bus_axis_info(result.external_bus_ids);
bus_table = table(axis_info.display_index, result.external_bus_ids(:), result.bus_type(:), result.bus_voltage(:), ...
    result.bus_angle_deg(:), result.P_generation(:), result.Q_generation(:), ...
    result.P_load(:), result.Q_load(:), ...
    'VariableNames', {'BusIdx', 'BusID', 'Type', 'V_pu', 'Angle_deg', 'Pgen_pu', 'Qgen_pu', 'Pload_pu', 'Qload_pu'});
app.result_table.Data = bus_table;
pfapp.style_result_table(app, 'powerflow');
if result.converged
    status_value = 'Converged';
    status_color = [0.18 0.50 0.32];
else
    status_value = 'Check';
    status_color = [0.83 0.20 0.15];
end
pfapp.update_dashboard_metrics(app, ...
    {'STATUS', 'ITERATIONS', 'P LOSS', 'MIN |V|'}, ...
    {status_value, sprintf('%d', result.iterations), sprintf('%.4f pu', result.P_loss_total), sprintf('%.4f pu', min(result.bus_voltage))}, ...
    {result.method, result.system_name, sprintf('%.2f MW', result.P_loss_total * result.base_values.S_base_MVA), 'Lowest bus voltage'}, ...
    {status_color, [0.02 0.44 0.62], [0.86 0.38 0.13], [0.45 0.30 0.72]});

pfapp.reset_axes_state(app.ax_voltage);
bar(app.ax_voltage, axis_info.x, result.bus_voltage, 0.72);
title(app.ax_voltage, sprintf('%s Voltage', result.method), 'Interpreter', 'none');
xlabel(app.ax_voltage, axis_info.xlabel);
ylabel(app.ax_voltage, '|V| pu');
grid(app.ax_voltage, 'on');
if ~isempty(axis_info.note)
    text(app.ax_voltage, 0.01, 0.96, axis_info.note, 'Units', 'normalized', ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
        'FontSize', 8, 'Color', [0.30 0.30 0.30]);
end

pfapp.reset_axes_state(app.ax_conv);
if ~isempty(result.mismatch_history)
    semilogy(app.ax_conv, 1:numel(result.mismatch_history), result.mismatch_history, '-o', 'LineWidth', 1.7);
    hold(app.ax_conv, 'on');
    yline(app.ax_conv, tolerance, '--r', sprintf('tol %.0e', tolerance));
    hold(app.ax_conv, 'off');
end
if result.converged
    title(app.ax_conv, 'Convergence - PASSED');
else
    title(app.ax_conv, 'Convergence - NOT CONVERGED');
end
xlabel(app.ax_conv, 'Iteration');
ylabel(app.ax_conv, 'Max mismatch');
grid(app.ax_conv, 'on');
end
