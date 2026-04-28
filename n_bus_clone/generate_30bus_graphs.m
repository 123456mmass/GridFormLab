% generate_30bus_graphs.m
% Run NR, GS, CPF (load scaling + predictor-corrector) on IEEE 30-bus
% and save all figures as PNG for the report.

addpath(fullfile(pwd, 'internal'));
pf_init_paths();

out_dir = fullfile(pwd, 'output');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

case_data = cases.case_matpower_ieee30bus();

% --- Run NR ---
fprintf('Running NR on 30-bus...\n');
opts_nr = struct('plot_results', false, 'verbose', false, 'tolerance', 1e-6);
nr = powerflow_newton_raphson(case_data, opts_nr);
fprintf('NR: converged=%d, %d iterations, final mismatch %.2e, P_loss %.6f pu\n', ...
    nr.converged, nr.iterations, nr.mismatch_history(end), nr.P_loss_total);

% NR plot
pf_plot_powerflow_results(nr, 1e-6);
exportgraphics(gcf, fullfile(out_dir, 'nr_30bus_voltage_convergence.png'), ...
    'Resolution', 200);
close(gcf);

% NR voltage magnitude bar chart (standalone)
figure('Color', 'w', 'Position', [100 100 1200 500]);
axis_info = pf_bus_axis_info(nr.external_bus_ids);
bar(axis_info.x, nr.bus_voltage, 0.7, 'FaceColor', [0.11 0.39 0.57], 'EdgeColor', 'none');
hold on;
yline(1.0, '--', '1.00 pu', 'Color', [0.75 0.18 0.18], 'LineWidth', 1.2);
hold off;
xlabel(axis_info.xlabel); ylabel('|V| (pu)');
title('NR Voltage Magnitude - IEEE 30-Bus');
grid on;
exportgraphics(gcf, fullfile(out_dir, 'nr_30bus_voltage.png'), 'Resolution', 200);
close(gcf);

% NR angle bar chart
figure('Color', 'w', 'Position', [100 100 1200 500]);
bar(axis_info.x, nr.bus_angle_deg, 0.7, 'FaceColor', [0.85 0.45 0.17], 'EdgeColor', 'none');
xlabel(axis_info.xlabel); ylabel('Angle (deg)');
title('NR Voltage Angle - IEEE 30-Bus');
grid on;
exportgraphics(gcf, fullfile(out_dir, 'nr_30bus_angle.png'), 'Resolution', 200);
close(gcf);

% Save NR summary as text
fid = fopen(fullfile(out_dir, 'nr_30bus_summary.txt'), 'w');
fprintf(fid, 'NR 30-Bus Results\n');
fprintf(fid, 'Iterations: %d\n', nr.iterations);
fprintf(fid, 'Max Mismatch: %.2e\n', max(nr.mismatch_history));
fprintf(fid, 'Total P Gen: %.4f pu\n', nr.P_total_gen);
fprintf(fid, 'Total Q Gen: %.4f pu\n', nr.Q_total_gen);
fprintf(fid, 'Total P Load: %.4f pu\n', nr.P_total_load);
fprintf(fid, 'Total Q Load: %.4f pu\n', nr.Q_total_load);
fprintf(fid, 'Total P Loss: %.4f pu\n', nr.P_loss_total);
fprintf(fid, 'Total Q Loss: %.4f pu\n', nr.Q_loss_total);
fclose(fid);

% --- Run GS ---
fprintf('Running GS on 30-bus...\n');
opts_gs = struct('plot_results', false, 'verbose', false, 'tolerance', 1e-4, ...
    'max_iter', 1000, 'acceleration_factor', 1.3);
gs = powerflow_gauss_seidel(case_data, opts_gs);
fprintf('GS: converged=%d, %d iterations, final mismatch %.2e, P_loss %.6f pu\n', ...
    gs.converged, gs.iterations, gs.mismatch_history(end), gs.P_loss_total);

% GS plot
pf_plot_powerflow_results(gs, 1e-6);
exportgraphics(gcf, fullfile(out_dir, 'gs_30bus_voltage_convergence.png'), ...
    'Resolution', 200);
close(gcf);

% GS voltage magnitude bar chart
figure('Color', 'w', 'Position', [100 100 1200 500]);
bar(axis_info.x, gs.bus_voltage, 0.7, 'FaceColor', [0.76 0.32 0.11], 'EdgeColor', 'none');
hold on;
yline(1.0, '--', '1.00 pu', 'Color', [0.75 0.18 0.18], 'LineWidth', 1.2);
hold off;
xlabel(axis_info.xlabel); ylabel('|V| (pu)');
title('GS Voltage Magnitude - IEEE 30-Bus');
grid on;
exportgraphics(gcf, fullfile(out_dir, 'gs_30bus_voltage.png'), 'Resolution', 200);
close(gcf);

% Save GS summary as text
fid = fopen(fullfile(out_dir, 'gs_30bus_summary.txt'), 'w');
fprintf(fid, 'GS 30-Bus Results\n');
fprintf(fid, 'Iterations: %d\n', gs.iterations);
fprintf(fid, 'Max Mismatch: %.2e\n', max(gs.mismatch_history));
fprintf(fid, 'Total P Gen: %.4f pu\n', gs.P_total_gen);
fprintf(fid, 'Total Q Gen: %.4f pu\n', gs.Q_total_gen);
fprintf(fid, 'Total P Load: %.4f pu\n', gs.P_total_load);
fprintf(fid, 'Total Q Load: %.4f pu\n', gs.Q_total_load);
fprintf(fid, 'Total P Loss: %.4f pu\n', gs.P_loss_total);
fclose(fid);

% --- NR vs GS Convergence Comparison ---
pf_plot_convergence_comparison({nr, gs}, {'Newton-Raphson', 'Gauss-Seidel'});
exportgraphics(gcf, fullfile(out_dir, 'nr_vs_gs_convergence_30bus.png'), ...
    'Resolution', 200);
close(gcf);

% --- NR vs GS Voltage Magnitude Comparison ---
figure('Color', 'w', 'Position', [100 100 1400 550]);
bar_width = 0.35;
x_nr = axis_info.x - bar_width/2;
x_gs = axis_info.x + bar_width/2;
b1 = bar(x_nr, nr.bus_voltage, bar_width, 'FaceColor', [0.11 0.39 0.57], ...
    'EdgeColor', 'none', 'DisplayName', 'Newton-Raphson');
hold on;
b2 = bar(x_gs, gs.bus_voltage, bar_width, 'FaceColor', [0.76 0.32 0.11], ...
    'EdgeColor', 'none', 'DisplayName', 'Gauss-Seidel');
yline(1.0, '--', '1.00 pu', 'Color', [0.75 0.18 0.18], 'LineWidth', 1.2);
xlabel(axis_info.xlabel); ylabel('|V| (pu)');
title('NR vs GS Voltage Magnitude - IEEE 30-Bus');
legend('Location', 'best');
grid on;
exportgraphics(gcf, fullfile(out_dir, 'nr_vs_gs_voltage_30bus.png'), ...
    'Resolution', 200);
close(gcf);

% --- NR vs GS Voltage Angle Comparison ---
figure('Color', 'w', 'Position', [100 100 1400 550]);
bar(x_nr, nr.bus_angle_deg, bar_width, 'FaceColor', [0.11 0.39 0.57], ...
    'EdgeColor', 'none', 'DisplayName', 'Newton-Raphson');
hold on;
bar(x_gs, gs.bus_angle_deg, bar_width, 'FaceColor', [0.76 0.32 0.11], ...
    'EdgeColor', 'none', 'DisplayName', 'Gauss-Seidel');
xlabel(axis_info.xlabel); ylabel('Angle (deg)');
title('NR vs GS Voltage Angle - IEEE 30-Bus');
legend('Location', 'best');
grid on;
exportgraphics(gcf, fullfile(out_dir, 'nr_vs_gs_angle_30bus.png'), ...
    'Resolution', 200);
close(gcf);

% --- Run CPF Load Scaling ---
fprintf('Running CPF Load Scaling on 30-bus...\n');
opts_cpf = struct('plot_results', false, 'verbose', false, 'tolerance', 1e-6, ...
    'lambda_step', 0.1, 'lambda_max', 4.0, 'min_voltage', 0.4, 'max_steps', 300, ...
    'target_bus', 30);
cpf_ls = cpf_load_scaling(case_data, opts_cpf);
fprintf('CPF LS: %d steps, stop reason: %s\n', numel(cpf_ls.lambdas), cpf_ls.stop_reason);

% CPF load scaling plot
pf_plot_cpf_results(cpf_ls);
exportgraphics(gcf, fullfile(out_dir, 'cpf_load_scaling_30bus.png'), ...
    'Resolution', 200);
close(gcf);

% --- Run CPF Predictor-Corrector ---
fprintf('Running CPF Predictor-Corrector on 30-bus...\n');
opts_cpf_pc = struct('plot_results', false, 'verbose', false, 'tolerance', 1e-6, ...
    'step_size', 0.1, 'lambda_max', 5.0, 'min_voltage', 0.2, 'max_steps', 400, ...
    'target_bus', 30);
cpf_pc = cpf_predictor_corrector(case_data, opts_cpf_pc);
fprintf('CPF PC: %d steps, stop reason: %s, nose: %d\n', ...
    numel(cpf_pc.lambdas), cpf_pc.stop_reason, cpf_pc.nose_detected);

% CPF predictor-corrector plot
pf_plot_cpf_results(cpf_pc);
exportgraphics(gcf, fullfile(out_dir, 'cpf_predictor_corrector_30bus.png'), ...
    'Resolution', 200);
close(gcf);

% --- CPF Comparison: PV curves side by side ---
figure('Color', 'w', 'Position', [60 45 1400 600]);
tcl = tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

% Load scaling PV curve
nexttile;
plot(cpf_ls.lambdas, cpf_ls.target_voltage, '-o', ...
    'Color', [0.05 0.36 0.60], 'LineWidth', 2, 'MarkerSize', 5, ...
    'MarkerFaceColor', [0.05 0.36 0.60]);
xlabel('\lambda loading factor'); ylabel(sprintf('|V| at Bus %d (pu)', cpf_ls.target_bus));
title('CPF Load Scaling');
grid on;
subtitle(sprintf('%d steps, stop: %s, last \\lambda = %.3f', ...
    numel(cpf_ls.lambdas), cpf_ls.stop_reason, max(cpf_ls.lambdas)));

% PC PV curve
nexttile;
if cpf_pc.nose_detected && cpf_pc.nose_index > 1
    upper_idx = 1:cpf_pc.nose_index;
    lower_idx = cpf_pc.nose_index:numel(cpf_pc.lambdas);
    plot(cpf_pc.lambdas(upper_idx), cpf_pc.target_voltage(upper_idx), '-', ...
        'LineWidth', 2.5, 'Color', [0.83 0.20 0.15]);
    hold on;
    plot(cpf_pc.lambdas(lower_idx), cpf_pc.target_voltage(lower_idx), '--', ...
        'LineWidth', 2.5, 'Color', [0.56 0.14 0.12]);
    scatter(cpf_pc.lambdas(upper_idx), cpf_pc.target_voltage(upper_idx), 24, 'filled', ...
        'MarkerFaceColor', [0.83 0.20 0.15]);
    scatter(cpf_pc.lambdas(lower_idx), cpf_pc.target_voltage(lower_idx), 18, 'filled', ...
        'MarkerFaceColor', [0.56 0.14 0.12]);
    plot(cpf_pc.nose_lambda, cpf_pc.nose_voltage, 'p', 'MarkerSize', 14, ...
        'MarkerFaceColor', [0.98 0.71 0.17], 'MarkerEdgeColor', [0.83 0.20 0.15], ...
        'LineWidth', 1.3);
    text(cpf_pc.nose_lambda + 0.02, cpf_pc.nose_voltage, ...
        sprintf('nose \\lambda=%.3f', cpf_pc.nose_lambda), ...
        'FontWeight', 'bold', 'Color', [0.83 0.20 0.15]);
    text(cpf_pc.lambdas(round(numel(upper_idx)*0.4)), ...
        cpf_pc.target_voltage(round(numel(upper_idx)*0.4)) + 0.01, ...
        'upper branch', 'FontWeight', 'bold', 'Color', [0.83 0.20 0.15]);
    text(cpf_pc.lambdas(min(numel(cpf_pc.lambdas), cpf_pc.nose_index + 8)), ...
        cpf_pc.target_voltage(min(numel(cpf_pc.lambdas), cpf_pc.nose_index + 8)) - 0.015, ...
        'lower branch', 'FontWeight', 'bold', 'Color', [0.56 0.14 0.12]);
    hold off;
else
    plot(cpf_pc.lambdas, cpf_pc.target_voltage, '-o', ...
        'Color', [0.83 0.20 0.15], 'LineWidth', 2, 'MarkerSize', 5, ...
        'MarkerFaceColor', [0.83 0.20 0.15]);
end
xlabel('\lambda loading factor'); ylabel(sprintf('|V| at Bus %d (pu)', cpf_pc.target_bus));
title('CPF Predictor-Corrector');
grid on;
subtitle(sprintf('%d steps, stop: %s, last \\lambda = %.3f', ...
    numel(cpf_pc.lambdas), cpf_pc.stop_reason, max(cpf_pc.lambdas)));

sgtitle('CPF Method Comparison - IEEE 30-Bus', 'FontWeight', 'bold');
exportgraphics(gcf, fullfile(out_dir, 'cpf_comparison_30bus.png'), ...
    'Resolution', 200);
close(gcf);

fprintf('\nAll graphs saved to %s\n', out_dir);
fprintf('Files generated:\n');
d = dir(fullfile(out_dir, '*.png'));
for i = 1:numel(d)
    fprintf('  %s\n', d(i).name);
end
