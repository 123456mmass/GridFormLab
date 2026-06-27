function pf_plot_cpf_results(cpf)
%PF_PLOT_CPF_RESULTS Presentation-ready CPF plots for n-bus systems.

bus_ids = cpf.external_bus_ids(:);
lambdas = cpf.lambdas(:).';
voltages = cpf.bus_voltage;
angles = cpf.bus_angle_deg;

target_idx = find(bus_ids == cpf.target_bus, 1);
if isempty(target_idx)
    target_idx = min(max(1, cpf.target_bus_index), numel(bus_ids));
end

highlight_idx = select_highlight_buses(cpf, target_idx);
colors = cpf_palette();

fig = figure('Name', sprintf('%s - %s', cpf.system_name, cpf.method), ...
    'Color', 'w', 'Position', [60 45 1360 760]);
layout = tiledlayout(fig, 2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

ax_pv = nexttile(layout, [2 1]);
plot_target_curve(ax_pv, cpf, colors);

ax_v = nexttile(layout, [1 2]);
plot_bus_corridor(ax_v, lambdas, voltages, bus_ids, highlight_idx, target_idx, colors, ...
    '|V| (pu)', 'Voltage magnitude corridor');
yline(ax_v, 1.00, ':', '1.00 pu', 'Color', [0.45 0.45 0.45], ...
    'LineWidth', 1.0, 'HandleVisibility', 'off', 'LabelHorizontalAlignment', 'left');
yline(ax_v, 0.95, '--', '0.95 pu', 'Color', [0.72 0.18 0.14], ...
    'LineWidth', 1.0, 'HandleVisibility', 'off', 'LabelHorizontalAlignment', 'left');

ax_a = nexttile(layout, [1 2]);
if size(angles, 2) == numel(lambdas)
    plot_bus_corridor(ax_a, lambdas, angles, bus_ids, highlight_idx, target_idx, colors, ...
        'Angle (degree)', 'Voltage angle corridor');
else
    axis(ax_a, 'off');
    text(ax_a, 0.08, 0.55, 'Voltage angle history is not available for this CPF result.', ...
        'FontSize', 11, 'Interpreter', 'none');
end

sgtitle(layout, sprintf('%s - %s | stop: %s', cpf.system_name, cpf.method, cpf.stop_reason), ...
    'Interpreter', 'none', 'FontWeight', 'bold');
end

function colors = cpf_palette()
colors = struct();
colors.target = [0.83 0.20 0.15];
colors.weak = [ ...
    0.05 0.36 0.60; ...
    0.10 0.52 0.41; ...
    0.88 0.50 0.10; ...
    0.39 0.24 0.63; ...
    0.05 0.55 0.67];
colors.context = [0.78 0.80 0.83];
colors.grid = [0.88 0.90 0.92];
end

function highlight_idx = select_highlight_buses(cpf, target_idx)
final_voltage = cpf.bus_voltage(:, end);
[~, order] = sort(final_voltage, 'ascend');
highlight_idx = unique([target_idx; order(1:min(4, numel(order)))], 'stable');
end

function plot_target_curve(ax, cpf, colors)
hold(ax, 'on');
if cpf.nose_detected && cpf.nose_index > 1 && cpf.nose_index < numel(cpf.lambdas)
    upper_idx = 1:cpf.nose_index;
    lower_idx = cpf.nose_index:numel(cpf.lambdas);
    plot(ax, cpf.lambdas(upper_idx), cpf.target_voltage(upper_idx), '-', ...
        'LineWidth', 3.0, 'Color', colors.target);
    plot(ax, cpf.lambdas(lower_idx), cpf.target_voltage(lower_idx), '--', ...
        'LineWidth', 2.6, 'Color', [0.56 0.14 0.12]);
    scatter(ax, cpf.lambdas(upper_idx), cpf.target_voltage(upper_idx), 28, 'filled', ...
        'MarkerFaceColor', colors.target, 'MarkerEdgeColor', 'w', 'LineWidth', 0.7);
    scatter(ax, cpf.lambdas(lower_idx), cpf.target_voltage(lower_idx), 20, 'filled', ...
        'MarkerFaceColor', [0.56 0.14 0.12], 'MarkerEdgeColor', 'w', 'LineWidth', 0.6);
    text(ax, cpf.lambdas(max(2, round(numel(upper_idx) * 0.45))), ...
        cpf.target_voltage(max(2, round(numel(upper_idx) * 0.45))) + 0.01, ...
        'upper branch', 'Color', colors.target, 'FontWeight', 'bold');
    text(ax, cpf.lambdas(max(cpf.nose_index + 1, round((cpf.nose_index + numel(cpf.lambdas)) / 2))), ...
        cpf.target_voltage(max(cpf.nose_index + 1, round((cpf.nose_index + numel(cpf.lambdas)) / 2))) - 0.015, ...
        'lower branch', 'Color', [0.56 0.14 0.12], 'FontWeight', 'bold');
else
    plot(ax, cpf.lambdas, cpf.target_voltage, '-', ...
        'LineWidth', 3.0, 'Color', colors.target);
    scatter(ax, cpf.lambdas, cpf.target_voltage, 34, 'filled', ...
        'MarkerFaceColor', colors.target, 'MarkerEdgeColor', 'w', 'LineWidth', 0.7);
end
mark_cpf_points(ax, cpf, colors);
hold(ax, 'off');
style_axis(ax);
xlabel(ax, '\lambda loading factor');
ylabel(ax, sprintf('|V| at bus %g (pu)', cpf.target_bus));
title(ax, sprintf('PV curve - target bus %g', cpf.target_bus), 'FontWeight', 'bold');
if cpf.nose_detected && cpf.nose_index > 0
    subtitle(ax, sprintf('nose \\lambda %.3f, |V| %.4f pu | traced lower branch to \\lambda %.3f', ...
        cpf.nose_lambda, cpf.nose_voltage, cpf.lambdas(end)));
elseif contains(lower(cpf.stop_reason), 'lambda_max')
    subtitle(ax, sprintf('last \\lambda %.3f, last |V| %.4f pu | increase \\lambda_{max} to reveal nose', ...
        cpf.lambdas(end), cpf.target_voltage(end)));
else
    subtitle(ax, sprintf('last \\lambda %.3f, last |V| %.4f pu', ...
        cpf.lambdas(end), cpf.target_voltage(end)));
end
end

function plot_bus_corridor(ax, lambdas, values, bus_ids, highlight_idx, target_idx, colors, y_label, plot_title)
plot(ax, lambdas, values.', 'Color', colors.context, 'LineWidth', 0.7, 'HandleVisibility', 'off');
hold(ax, 'on');

for k = 1:numel(highlight_idx)
    idx = highlight_idx(k);
    line_color = line_color_for_bus(k, idx, target_idx, colors);
    if idx == target_idx
        line_width = 2.8;
        marker = 'o';
    else
        line_width = 2.0;
        marker = 'none';
    end
    plot(ax, lambdas, values(idx, :), '-', ...
        'Color', line_color, 'LineWidth', line_width, 'Marker', marker, ...
        'MarkerIndices', marker_indices(lambdas), 'MarkerSize', 4, ...
        'MarkerFaceColor', line_color, 'MarkerEdgeColor', 'w', ...
        'HandleVisibility', 'off');
end

label_line_ends(ax, lambdas, values, bus_ids, highlight_idx, target_idx, colors);
hold(ax, 'off');

style_axis(ax);
xlabel(ax, '\lambda loading factor');
ylabel(ax, y_label);
title(ax, plot_title, 'FontWeight', 'bold');
add_corridor_note(ax, numel(bus_ids), numel(highlight_idx));
end

function idx = marker_indices(lambdas)
idx = unique([1, round(linspace(1, numel(lambdas), min(8, numel(lambdas))))]);
end

function color = line_color_for_bus(k, idx, target_idx, colors)
if idx == target_idx
    color = colors.target;
else
    color = colors.weak(1 + mod(k - 1, size(colors.weak, 1)), :);
end
end

function label_line_ends(ax, lambdas, values, bus_ids, highlight_idx, target_idx, colors)
x_last = lambdas(end);
x_span = max(lambdas) - min(lambdas);
if x_span <= 0
    x_span = 1;
end
label_x = x_last + 0.018 * x_span;
xlim(ax, [min(lambdas), x_last + 0.14 * x_span]);

[~, label_order] = sort(values(highlight_idx, end), 'descend');
used_y = [];
for n = 1:numel(label_order)
    k = label_order(n);
    idx = highlight_idx(k);
    y = separate_label_y(values(idx, end), used_y, range(values(:)));
    used_y(end + 1) = y; %#ok<AGROW>
    color = line_color_for_bus(k, idx, target_idx, colors);
    if idx == target_idx
        label = sprintf('Target %g', bus_ids(idx));
        weight = 'bold';
    else
        label = sprintf('Bus %g', bus_ids(idx));
        weight = 'normal';
    end
    text(ax, label_x, y, label, 'Color', color, 'FontWeight', weight, ...
        'FontSize', 9, 'Interpreter', 'none', 'Clipping', 'off');
end
end

function y = separate_label_y(y, used_y, y_range)
if isempty(used_y)
    return;
end
if y_range <= 0 || ~isfinite(y_range)
    y_range = 1;
end
min_gap = 0.035 * y_range;
for guard = 1:20
    too_close = abs(y - used_y) < min_gap;
    if ~any(too_close)
        break;
    end
    y = y - min_gap;
end
end

function style_axis(ax)
plot_ink = [0.10 0.10 0.10];
grid(ax, 'on');
ax.GridAlpha = 0.55;
ax.MinorGridAlpha = 0.35;
ax.GridColor = [0.82 0.82 0.82];
ax.MinorGridColor = [0.90 0.90 0.90];
ax.Box = 'on';
ax.Color = [1 1 1];
ax.XColor = plot_ink;
ax.YColor = plot_ink;
ax.Title.Color = plot_ink;
ax.XLabel.Color = plot_ink;
ax.YLabel.Color = plot_ink;
ax.Layer = 'top';
end

function add_corridor_note(ax, bus_count, highlight_count)
txt = sprintf('%d buses total, %d highlighted', bus_count, highlight_count);
text(ax, 0.012, 0.04, txt, 'Units', 'normalized', 'Color', [0.35 0.38 0.40], ...
    'FontSize', 8.5, 'BackgroundColor', [1 1 1 0.72], 'Margin', 3, ...
    'Interpreter', 'none');
end

function mark_cpf_points(ax, cpf, colors)
if cpf.nose_index > 0
    plot(ax, cpf.nose_lambda, cpf.nose_voltage, 'p', 'MarkerSize', 15, ...
        'MarkerFaceColor', [0.98 0.71 0.17], 'MarkerEdgeColor', colors.target, ...
        'LineWidth', 1.3);
    if isfield(cpf, 'nose_detected') && cpf.nose_detected
        point_label = sprintf('nose %.3f', cpf.nose_lambda);
    else
        point_label = sprintf('max \\lambda %.3f', cpf.nose_lambda);
    end
    text(ax, cpf.nose_lambda, cpf.nose_voltage, ['  ' point_label], ...
        'VerticalAlignment', 'bottom', 'FontWeight', 'bold', 'Color', colors.target);
end
if cpf.lowest_index > 0 && cpf.lowest_index ~= cpf.nose_index
    plot(ax, cpf.lowest_lambda, cpf.lowest_voltage, 'v', 'MarkerSize', 9, ...
        'MarkerFaceColor', [0.20 0.20 0.20], 'MarkerEdgeColor', [0.20 0.20 0.20]);
end
end
