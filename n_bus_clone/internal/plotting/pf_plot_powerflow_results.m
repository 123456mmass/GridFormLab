function pf_plot_powerflow_results(results, tolerance)
%PF_PLOT_POWERFLOW_RESULTS Presentation-ready plots for one solver result.

if nargin < 2 || isempty(tolerance)
    tolerance = 1e-6;
end

axis_info = pf_bus_axis_info(results.external_bus_ids);
bus_voltage = results.bus_voltage;
bus_angle_deg = results.bus_angle_deg;
mismatch_plot = results.mismatch_history;
iter = results.iterations;

figure('Name', sprintf('%s - %s', results.method, results.system_name), 'Color', 'w');
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
bar(axis_info.x, bus_voltage, 0.72, 'FaceColor', [0.11 0.39 0.57], 'EdgeColor', 'none');
hold on;
yline(1.0, '--', '1.00 pu', 'Color', [0.75 0.18 0.18], 'LineWidth', 1.2);
hold off;
xlabel(axis_info.xlabel);
ylabel('|V| (pu)');
title('Voltage Magnitude');
grid on;
ylim([min(0.85, min(bus_voltage) - 0.05), max(1.12, max(bus_voltage) + 0.05)]);
set(gca, 'GridAlpha', 0.18);
if ~isempty(axis_info.note)
    text(0.01, 0.96, axis_info.note, 'Units', 'normalized', ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
        'FontSize', 8, 'Color', [0.30 0.30 0.30]);
end

nexttile;
bar(axis_info.x, bus_angle_deg, 0.72, 'FaceColor', [0.85 0.45 0.17], 'EdgeColor', 'none');
xlabel(axis_info.xlabel);
ylabel('Angle (degree)');
title('Voltage Angle');
grid on;
set(gca, 'GridAlpha', 0.18);

nexttile([1 2]);
if isempty(mismatch_plot)
    semilogy(1, tolerance, 'o', 'Color', [0.25 0.25 0.25], 'MarkerFaceColor', [0.25 0.25 0.25]);
else
    semilogy(1:iter, mismatch_plot, '-o', ...
        'Color', [0.08 0.25 0.45], 'LineWidth', 2, ...
        'MarkerSize', 5, 'MarkerFaceColor', [0.08 0.25 0.45]);
end
hold on;
yline(tolerance, '--', sprintf('tol = %.0e', tolerance), 'Color', [0.75 0.18 0.18], 'LineWidth', 1.2);
hold off;
xlabel('Iteration');
ylabel('Max Mismatch (pu)');
title(sprintf('%s Convergence', results.method), 'Interpreter', 'none');
grid on;
set(gca, 'GridAlpha', 0.18);

sgtitle(sprintf('%s - %s', results.system_name, results.method), 'Interpreter', 'none', 'FontWeight', 'bold');
end
