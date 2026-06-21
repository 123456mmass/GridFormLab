function open_suite_figure(suite)
axis_info = pf_bus_axis_info(suite.newton_raphson.external_bus_ids);
figure('Name', 'IEEE 5 Power Flow Suite', 'Color', 'w', 'Position', [100 70 1180 760]);
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
plot(axis_info.x, suite.newton_raphson.bus_voltage, '-o', ...
    axis_info.x, suite.gauss_seidel.bus_voltage, '-s', 'LineWidth', 1.8);
xlabel(axis_info.xlabel);
ylabel('|V| pu');
title('NR vs GS Voltage Magnitude');
legend({'Newton-Raphson', 'Gauss-Seidel'}, 'Location', 'best');
grid on;
if ~isempty(axis_info.note)
    text(0.01, 0.96, axis_info.note, 'Units', 'normalized', ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', ...
        'FontSize', 8, 'Color', [0.30 0.30 0.30]);
end

nexttile;
plot(axis_info.x, suite.newton_raphson.bus_angle_deg, '-o', ...
    axis_info.x, suite.gauss_seidel.bus_angle_deg, '-s', 'LineWidth', 1.8);
xlabel(axis_info.xlabel);
ylabel('Angle (degree)');
title('NR vs GS Voltage Angle');
legend({'Newton-Raphson', 'Gauss-Seidel'}, 'Location', 'best');
grid on;

nexttile;
semilogy(1:numel(suite.newton_raphson.mismatch_history), suite.newton_raphson.mismatch_history, '-o', ...
    1:numel(suite.gauss_seidel.mismatch_history), suite.gauss_seidel.mismatch_history, '-s', 'LineWidth', 1.6);
xlabel('Iteration');
ylabel('Max mismatch pu');
title('NR vs GS Convergence');
legend({'Newton-Raphson', 'Gauss-Seidel'}, 'Location', 'best');
grid on;

nexttile;
plot(suite.cpf_load_scaling.lambdas, suite.cpf_load_scaling.target_voltage, '-o', ...
    suite.cpf_predictor_corrector.lambdas, suite.cpf_predictor_corrector.target_voltage, '-s', 'LineWidth', 1.8);
xlabel('\lambda');
ylabel('|V| target bus pu');
title('CPF PV Curve Comparison');
legend({'Load Scaling', 'Predictor-Corrector'}, 'Location', 'best');
grid on;

sgtitle('IEEE 5-Bus Power Flow Suite', 'Interpreter', 'none');
end
