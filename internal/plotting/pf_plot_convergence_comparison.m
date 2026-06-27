function pf_plot_convergence_comparison(results_list, labels)
%PF_PLOT_CONVERGENCE_COMPARISON Compare convergence histories across methods.

if nargin < 2 || isempty(labels)
    labels = cell(size(results_list));
    for i = 1:numel(results_list)
        labels{i} = results_list{i}.method;
    end
end

colors = [0.08 0.25 0.45; 0.76 0.32 0.11; 0.14 0.50 0.32; 0.45 0.20 0.55];
figure('Name', 'Power Flow Convergence Comparison', 'Color', 'w');
hold on;
plotted_labels = {};
for i = 1:numel(results_list)
    history = results_list{i}.mismatch_history;
    if isempty(history)
        continue;
    end
    plotted_labels{end + 1} = labels{min(i, numel(labels))};
    color = colors(mod(i - 1, size(colors, 1)) + 1, :);
    semilogy(1:numel(history), history, '-o', 'LineWidth', 2, ...
        'MarkerSize', 5, 'Color', color, 'MarkerFaceColor', color);
end
hold off;
xlabel('Iteration');
ylabel('Max Mismatch (pu)');
title('NR vs GS Convergence');
legend(plotted_labels, 'Location', 'northeast', 'Interpreter', 'none');
grid on;
set(gca, 'GridAlpha', 0.18);
end
