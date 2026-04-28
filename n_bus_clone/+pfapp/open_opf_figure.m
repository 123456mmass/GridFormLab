function open_opf_figure(result)
if isfield(result, 'bus_voltage')
    figure('Name', sprintf('%s - AC OPF', result.system_name), ...
        'Color', 'w', 'Position', [140 90 1080 620]);
    tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile;
    bar(result.external_bus_ids, result.bus_voltage, 0.65, 'FaceColor', [0.13 0.43 0.57], 'EdgeColor', 'none');
    hold on;
    plot(result.external_bus_ids, result.V_min, 'r--');
    plot(result.external_bus_ids, result.V_max, 'r--');
    hold off;
    xlabel('Bus');
    ylabel('|V| (pu)');
    title('Voltage Profile');
    grid on;

    nexttile;
    bar(result.generator_ids, result.P_generation_MW, 0.65, 'FaceColor', [0.82 0.44 0.17], 'EdgeColor', 'none');
    xlabel('Generator');
    ylabel('P generation (MW)');
    title(sprintf('Dispatch, demand %.0f MW', result.P_demand_MW));
    grid on;

    nexttile;
    bar(result.generator_ids, result.generator_cost, 0.65, 'FaceColor', [0.31 0.53 0.24], 'EdgeColor', 'none');
    xlabel('Generator');
    ylabel('Cost ($/h)');
    title(sprintf('Total %.2f $/h', result.total_cost));
    grid on;

    nexttile;
    if isfield(result, 'line_loading_percent') && ~isempty(result.line_loading_percent)
        bar(result.line_loading_percent, 0.65, 'FaceColor', [0.38 0.38 0.46], 'EdgeColor', 'none');
        yline(100, 'r--');
        ylabel('Loading (%)');
        title('Line Loading');
    else
        bar(max(result.line_from_MVA, result.line_to_MVA), 0.65, 'FaceColor', [0.38 0.38 0.46], 'EdgeColor', 'none');
        ylabel('MVA');
        title('Line Apparent Flow');
    end
    xlabel('Line');
    grid on;

    sgtitle(sprintf('%s - AC Optimal Power Flow', result.system_name), 'Interpreter', 'none');
    return;
end

figure('Name', sprintf('%s - OPF Economic Dispatch', result.system_name), ...
    'Color', 'w', 'Position', [140 100 980 540]);
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
bar(result.generator_ids, result.P_generation_MW, 0.65, 'FaceColor', [0.13 0.43 0.57], 'EdgeColor', 'none');
xlabel('Generator');
ylabel('P generation (MW)');
title(sprintf('Dispatch, demand %.0f MW', result.P_demand_MW));
grid on;

nexttile;
bar(result.generator_ids, result.generator_cost, 0.65, 'FaceColor', [0.82 0.44 0.17], 'EdgeColor', 'none');
xlabel('Generator');
ylabel('Cost ($/h)');
title(sprintf('Total %.2f $/h, lambda %.4f', result.total_cost, result.lambda));
grid on;

sgtitle(sprintf('%s - OPF Economic Dispatch', result.system_name), 'Interpreter', 'none');
end
