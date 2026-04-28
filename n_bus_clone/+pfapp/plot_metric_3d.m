function plot_metric_3d(values, method_labels, case_labels, plot_title)
nexttile;
bar3(pfapp.fillmissing_for_plot(values));
title(plot_title, 'Interpreter', 'none');
xlabel('System');
ylabel('Solver');
zlabel(plot_title, 'Interpreter', 'none');
set(gca, 'XTick', 1:numel(case_labels), 'XTickLabel', pfapp.shorten_labels(case_labels), ...
    'YTick', 1:numel(method_labels), 'YTickLabel', method_labels);
xtickangle(35);
grid on;
view(-42, 28);
end
