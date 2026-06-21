function open_cpf_reference_figure(cpf)
[plot_bus_id, plot_voltage, note_text] = pfapp.choose_reference_pv_series(cpf);
figure('Name', 'CPF Predictor-Corrector Reference Plot', 'Color', 'w', 'Position', [160 80 980 680]);
plot(cpf.lambdas, plot_voltage, 'k-', 'LineWidth', 2.2);
hold on;
plot(cpf.lambdas, plot_voltage, 'ko', 'MarkerFaceColor', [0.10 0.40 0.62], 'MarkerSize', 5);
pfapp.mark_cpf_points(cpf, plot_voltage);

if numel(cpf.lambdas) >= 3
    idx0 = 1;
    idx1 = min(3, numel(cpf.lambdas));
    idxn = max(cpf.nose_index, idx1);
    x0 = cpf.lambdas(idx0);
    x1 = cpf.lambdas(idx1);
    xn = cpf.lambdas(idxn);
    y0 = plot_voltage(idx0);
    y1 = plot_voltage(idx1);
    yn = plot_voltage(idxn);

    xline(x0, '--', '\lambda_0', 'LabelVerticalAlignment', 'bottom');
    xline(x1, '--', '\lambda_1', 'LabelVerticalAlignment', 'bottom');
    xline(xn, '--', 'nose', 'LabelVerticalAlignment', 'bottom');

    annotation('textarrow', [0.31 0.38], [0.80 0.72], 'String', 'PREDICTOR STEP');
    annotation('textarrow', [0.63 0.55], [0.73 0.70], 'String', 'CORRECTOR STEP');
    annotation('textarrow', [0.76 0.68], [0.62 0.58], 'String', 'BIFURCATION / NOSE POINT');

    y_margin = min([y0, y1, yn]) - 0.04;
    y_margin = max(y_margin, min(plot_voltage) - 0.08);
    plot([x0 xn], [y_margin y_margin], 'k-', 'LineWidth', 1.5);
    plot([x0 x0], [y_margin - 0.01 y_margin + 0.01], 'k-');
    plot([xn xn], [y_margin - 0.01 y_margin + 0.01], 'k-');
    text(mean([x0 xn]), y_margin + 0.01, 'LOADABILITY MARGIN', 'HorizontalAlignment', 'center');

    text(x0, y0, '  A', 'FontWeight', 'bold');
    text(x1, y1, '  B', 'FontWeight', 'bold');
    text(mean([x0 x1]), mean([y0 y1]) - 0.03, 'C', 'FontWeight', 'bold');
end

hold off;
xlabel('\lambda');
ylabel(sprintf('|V| at bus %g', plot_bus_id));
title('CPF Predictor-Corrector Conceptual PV Curve');
if ~isempty(note_text)
    subtitle(note_text, 'Interpreter', 'none');
end
grid on;
end
