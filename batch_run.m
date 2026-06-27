% Batch power flow analysis - no GUI, export results to files
pf_init_paths();

case_data = case_ieee5bus();
fprintf('Case: IEEE 5-Bus System\n');
fprintf('Buses: %d, Lines: %d\n\n', size(case_data.bus_data, 1), size(case_data.line_data, 1));

% --- Newton-Raphson ---
fprintf('=== Newton-Raphson ===\n');
nr_options = struct('max_iter', 20, 'tolerance', 1e-6, 'plot_results', false, 'verbose', true);
nr = powerflow_newton_raphson(case_data, nr_options);
fprintf('NR: converged=%d, iter=%d, P_loss=%.6f pu\n\n', nr.converged, nr.iterations, nr.P_loss_total);

% --- Gauss-Seidel ---
fprintf('=== Gauss-Seidel ===\n');
gs_options = struct('max_iter', 300, 'tolerance', 1e-6, 'acceleration', 1.4, 'plot_results', false, 'verbose', true);
gs = powerflow_gauss_seidel(case_data, gs_options);
fprintf('GS: converged=%d, iter=%d, P_loss=%.6f pu\n\n', gs.converged, gs.iterations, gs.P_loss_total);

% --- CPF Load Scaling ---
fprintf('=== CPF Load Scaling ===\n');
cpf_options = struct('target_bus', 5, 'lambda_step', 0.05, 'lambda_max', 1.5, ...
    'min_voltage', 0.65, 'max_steps', 80, 'tolerance', 1e-6, 'plot_results', false, 'verbose', true);
cpf_ls = cpf_load_scaling(case_data, cpf_options);
fprintf('CPF-LS: %d points, last lambda=%.4f, stop="%s"\n\n', numel(cpf_ls.lambdas), cpf_ls.lambdas(end), cpf_ls.stop_reason);

% --- CPF Predictor-Corrector ---
fprintf('=== CPF Predictor-Corrector ===\n');
cpf_pc = cpf_predictor_corrector(case_data, cpf_options);
fprintf('CPF-PC: %d points, last lambda=%.4f, stop="%s"\n\n', numel(cpf_pc.lambdas), cpf_pc.lambdas(end), cpf_pc.stop_reason);

% --- Export Results ---
outdir = 'output/batch_run';
if ~exist(outdir, 'dir'), mkdir(outdir); end

% Bus results comparison
fid = fopen(fullfile(outdir, 'bus_results_comparison.txt'), 'w');
fprintf(fid, '%-6s %-8s %-12s %-12s %-12s %-12s\n', 'Bus', 'Type', '|V| NR', '|V| GS', 'Angle NR', 'Angle GS');
for i = 1:size(case_data.bus_data, 1)
    bn = case_data.bus_data(i, 1);
    bt = case_data.bus_data(i, 2);
    fprintf(fid, '%-6d %-8d %-12.6f %-12.6f %-12.6f %-12.6f\n', ...
        bn, bt, abs(nr.bus_voltage(i)), abs(gs.bus_voltage(i)), ...
        nr.bus_angle_deg(i), gs.bus_angle_deg(i));
end
fclose(fid);

% CPF curves
dlmwrite(fullfile(outdir, 'cpf_load_scaling.csv'), [cpf_ls.lambdas', cpf_ls.target_voltage'], 'delimiter', ',');
dlmwrite(fullfile(outdir, 'cpf_predictor_corrector.csv'), [cpf_pc.lambdas', cpf_pc.target_voltage'], 'delimiter', ',');

% Summary
fid = fopen(fullfile(outdir, 'summary.txt'), 'w');
fprintf(fid, '=== BATCH POWER FLOW RESULTS ===\n');
fprintf(fid, 'Date: %s\n\n', datestr(now));
fprintf(fid, 'Case: IEEE 5-Bus\n');
fprintf(fid, 'Solvers: Newton-Raphson, Gauss-Seidel, CPF-LS, CPF-PC\n\n');
fprintf(fid, 'Newton-Raphson: converged=%d, iter=%d, P_loss=%.6f pu\n', nr.converged, nr.iterations, nr.P_loss_total);
fprintf(fid, 'Gauss-Seidel:   converged=%d, iter=%d, P_loss=%.6f pu\n', gs.converged, gs.iterations, gs.P_loss_total);
fprintf(fid, 'Max |V_GS - V_NR| = %.6e pu\n\n', max(abs(gs.bus_voltage - nr.bus_voltage)));
fprintf(fid, 'CPF Load Scaling:       %d points, lambda_max=%.4f (%s)\n', numel(cpf_ls.lambdas), cpf_ls.lambdas(end), cpf_ls.stop_reason);
fprintf(fid, 'CPF Predictor-Corrector: %d points, lambda_max=%.4f (%s)\n', numel(cpf_pc.lambdas), cpf_pc.lambdas(end), cpf_pc.stop_reason);
fclose(fid);

fprintf('\n=== DONE ===\n');
fprintf('Results saved to: %s/\n', outdir);
