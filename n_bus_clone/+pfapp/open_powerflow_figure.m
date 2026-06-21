function open_powerflow_figure(result)
axis_info = pf_bus_axis_info(result.external_bus_ids);
figure('Name', sprintf('%s - %s', result.system_name, result.method), ...
    'Color', 'w', 'Position', [100 70 1160 760]);
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
bar(axis_info.x, result.bus_voltage, 0.72, 'FaceColor', [0.10 0.40 0.62], 'EdgeColor', 'none');
yline(1.0, '--', '1.00 pu', 'Color', [0.72 0.18 0.14], 'LineWidth', 1.1);
xlabel(axis_info.xlabel);
ylabel('|V| pu');
title('Voltage Magnitude');
grid on;
style_axes(gca);
if ~isempty(axis_info.note)
    text(0.01, 0.96, axis_info.note, 'Units', 'normalized', ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
        'FontSize', 8, 'Color', [0.30 0.30 0.30]);
end

nexttile;
bar(axis_info.x, result.bus_angle_deg, 0.72, 'FaceColor', [0.88 0.48 0.16], 'EdgeColor', 'none');
xlabel(axis_info.xlabel);
ylabel('Angle (degree)');
title('Voltage Angle');
grid on;
style_axes(gca);

nexttile;
if ~isempty(result.mismatch_history)
    semilogy(1:numel(result.mismatch_history), result.mismatch_history, '-o', ...
        'LineWidth', 2, 'MarkerFaceColor', [0.08 0.25 0.45]);
end
xlabel('Iteration');
ylabel('Max mismatch pu');
title('Convergence');
grid on;
style_axes(gca);

nexttile;
plot(axis_info.x, result.P_generation - result.P_load, '-o', ...
    axis_info.x, result.Q_generation - result.Q_load, '-s', 'LineWidth', 1.8);
xlabel(axis_info.xlabel);
ylabel('Net injection pu');
title('Net P/Q Injection');
lgd = legend({'P net', 'Q net'}, 'Location', 'best');
lgd.TextColor = [0 0 0];
lgd.Color = [1 1 1];
grid on;
style_axes(gca);

st = sgtitle(sprintf('%s - %s', result.system_name, result.method), 'Interpreter', 'none');
st.Color = [0.10 0.10 0.10];
end

function style_axes(ax)
plot_ink = [0.10 0.10 0.10];
ax.Color = [1 1 1];
ax.XColor = plot_ink;
ax.YColor = plot_ink;
ax.GridColor = [0.82 0.82 0.82];
ax.GridAlpha = 0.55;
ax.FontSize = 10;
ax.Title.Color = plot_ink;
ax.XLabel.Color = plot_ink;
ax.YLabel.Color = plot_ink;
end
