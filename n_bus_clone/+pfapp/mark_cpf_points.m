function mark_cpf_points(cpf, plot_voltage)
if cpf.nose_index > 0
    plot(cpf.nose_lambda, plot_voltage(cpf.nose_index), 'p', 'MarkerSize', 14, ...
        'MarkerFaceColor', [0.80 0.22 0.16], 'MarkerEdgeColor', [0.80 0.22 0.16]);
end
if cpf.lowest_index > 0 && cpf.lowest_index ~= cpf.nose_index
    plot(cpf.lowest_lambda, plot_voltage(cpf.lowest_index), 'v', 'MarkerSize', 9, ...
        'MarkerFaceColor', [0.20 0.20 0.20], 'MarkerEdgeColor', [0.20 0.20 0.20]);
end
end
