function show_opf_result(app, result)
%SHOW_OPF_RESULT Display OPF results in table and plots.

if isfield(result, 'Q_generation_MVAr')
    data = table(result.generator_ids(:), result.generator_bus_ids(:), ...
        result.P_generation_MW(:), result.Q_generation_MVAr(:), result.incremental_cost(:), ...
        result.generator_cost(:), result.active_limits(:), ...
        'VariableNames', {'Generator', 'Bus', 'P_MW', 'Q_MVAr', 'IncrementalCost', 'Cost_per_h', 'Limit'});
else
    data = table(result.generator_ids(:), result.P_generation_MW(:), result.incremental_cost(:), ...
        result.generator_cost(:), result.active_limits(:), ...
        'VariableNames', {'Generator', 'P_MW', 'IncrementalCost', 'Cost_per_h', 'Limit'});
end
app.result_table.Data = data;
pfapp.style_result_table(app, 'opf');
if isfield(result, 'max_power_balance_mismatch')
    if isfield(result, 'line_loading_percent') && ~isempty(result.line_loading_percent)
        line_value = sprintf('%.1f%%', max(result.line_loading_percent));
        line_caption = 'Max line loading';
    else
        line_value = sprintf('%.1f MVA', max(max(result.line_from_MVA, result.line_to_MVA)));
        line_caption = 'Max line flow';
    end
    pfapp.update_dashboard_metrics(app, ...
        {'AC OPF', 'TOTAL COST', 'MISMATCH', 'LINE'}, ...
        {ternary(result.converged, 'Feasible', 'Check'), sprintf('%.2f', result.total_cost), sprintf('%.1e', result.max_power_balance_mismatch), line_value}, ...
        {result.system_name, '$/h objective', 'Final NR mismatch', line_caption}, ...
        {[0.18 0.50 0.32], [0.86 0.38 0.13], [0.02 0.44 0.62], [0.45 0.30 0.72]});
else
    pfapp.update_dashboard_metrics(app, ...
        {'ECON DISPATCH', 'TOTAL COST', 'LAMBDA', 'GENERATORS'}, ...
        {ternary(result.converged, 'Solved', 'Check'), sprintf('%.2f', result.total_cost), sprintf('%.3f', result.lambda), sprintf('%d', numel(result.generator_ids))}, ...
        {result.system_name, '$/h objective', '$/MWh', 'Dispatch units'}, ...
        {[0.18 0.50 0.32], [0.86 0.38 0.13], [0.02 0.44 0.62], [0.45 0.30 0.72]});
end

pfapp.reset_axes_state(app.ax_voltage);
if isfield(result, 'bus_voltage')
    bar(app.ax_voltage, result.external_bus_ids, result.bus_voltage, 0.65);
    hold(app.ax_voltage, 'on');
    plot(app.ax_voltage, result.external_bus_ids, result.V_min, 'r--');
    plot(app.ax_voltage, result.external_bus_ids, result.V_max, 'r--');
    hold(app.ax_voltage, 'off');
    title(app.ax_voltage, 'AC OPF Voltage');
    xlabel(app.ax_voltage, 'Bus');
    ylabel(app.ax_voltage, '|V| pu');
else
    bar(app.ax_voltage, result.generator_ids, result.P_generation_MW, 0.65);
    title(app.ax_voltage, 'OPF Dispatch');
    xlabel(app.ax_voltage, 'Generator');
    ylabel(app.ax_voltage, 'P MW');
end
grid(app.ax_voltage, 'on');

pfapp.reset_axes_state(app.ax_conv);
if isfield(result, 'line_loading_percent') && ~isempty(result.line_loading_percent)
    bar(app.ax_conv, result.line_loading_percent, 0.65);
    yline(app.ax_conv, 100, 'r--');
    title(app.ax_conv, sprintf('Cost %.2f $/h, max line %.1f%%', result.total_cost, max(result.line_loading_percent)));
    xlabel(app.ax_conv, 'Line');
    ylabel(app.ax_conv, 'Loading %');
else
    bar(app.ax_conv, result.generator_ids, result.generator_cost, 0.65);
    title(app.ax_conv, sprintf('Cost %.2f $/h, lambda %.4f', result.total_cost, result.lambda));
    xlabel(app.ax_conv, 'Generator');
    ylabel(app.ax_conv, 'Cost $/h');
end
grid(app.ax_conv, 'on');
end

function value = ternary(condition, true_value, false_value)
if condition
    value = true_value;
else
    value = false_value;
end
end
