function results = benchmark_all_methods(case_data, options)
%BENCHMARK_ALL_METHODS Run all applicable solvers and compare performance.
%   Headless multi-method benchmark with timing and convergence stats.
%
%   results = benchmark_all_methods(case_data)
%   results = benchmark_all_methods(case_data, options)
%
%   Options:
%       verbose (true)     - print progress
%       export_results (true) - write CSV/JSON to ./output
%       tolerance (1e-6)   - convergence tolerance
%       max_iter_nr (50)   - max iterations for NR
%       max_iter_gs (300)  - max iterations for GS

if nargin < 1 || isempty(case_data)
    case_data = case_ieee5bus();
end
if nargin < 2
    options = struct();
end

pf_init_paths();

verbose = pf_get_option(options, 'verbose', true);
export_results = pf_get_option(options, 'export_results', true);
tolerance = pf_get_option(options, 'tolerance', 1e-6);
max_iter_nr = pf_get_option(options, 'max_iter_nr', 50);
max_iter_gs = pf_get_option(options, 'max_iter_gs', 300);

methods = {'Newton-Raphson', 'Gauss-Seidel'};
results = struct();

if verbose
    fprintf('============================================================\n');
    fprintf('  MULTI-METHOD BENCHMARK: %s\n', upper(case_data.system_name));
    fprintf('============================================================\n\n');
end

% ── Newton-Raphson ──
if verbose, fprintf('Running Newton-Raphson ...\n'); end
tic;
try
    nr_opts = struct('max_iter', max_iter_nr, 'tolerance', tolerance, ...
        'verbose', false, 'plot_results', false);
    results.nr = powerflow_newton_raphson(case_data, nr_opts);
    results.nr.elapsed_sec = toc;
    if verbose
        fprintf('  Converged: %d  Iterations: %d  Time: %.3f s  P_loss: %.6f pu\n', ...
            results.nr.converged, results.nr.iterations, results.nr.elapsed_sec, results.nr.P_loss_total);
    end
catch err
    results.nr = struct('converged', false, 'iterations', 0, 'elapsed_sec', toc, 'error', err.message);
    if verbose, fprintf('  FAILED: %s\n', err.message); end
end

% ── Gauss-Seidel ──
if verbose, fprintf('Running Gauss-Seidel ...\n'); end
tic;
try
    gs_opts = struct('max_iter', max_iter_gs, 'tolerance', tolerance, ...
        'verbose', false, 'plot_results', false);
    results.gs = powerflow_gauss_seidel(case_data, gs_opts);
    results.gs.elapsed_sec = toc;
    if verbose
        fprintf('  Converged: %d  Iterations: %d  Time: %.3f s  P_loss: %.6f pu\n', ...
            results.gs.converged, results.gs.iterations, results.gs.elapsed_sec, results.gs.P_loss_total);
    end
catch err
    results.gs = struct('converged', false, 'iterations', 0, 'elapsed_sec', toc, 'error', err.message);
    if verbose, fprintf('  FAILED: %s\n', err.message); end
end

% ── Summary ──
if verbose
    fprintf('\n--- BENCHMARK SUMMARY ---\n');
    if isfield(results, 'nr') && results.nr.converged
        fprintf('NR:  %d iter, %.3f s, P_loss=%.6f pu\n', results.nr.iterations, results.nr.elapsed_sec, results.nr.P_loss_total);
    else
        fprintf('NR:  FAILED\n');
    end
    if isfield(results, 'gs') && results.gs.converged
        fprintf('GS:  %d iter, %.3f s, P_loss=%.6f pu\n', results.gs.iterations, results.gs.elapsed_sec, results.gs.P_loss_total);
    else
        fprintf('GS:  FAILED\n');
    end
    if isfield(results, 'nr') && isfield(results, 'gs') && results.nr.converged && results.gs.converged
        speedup = results.gs.elapsed_sec / max(results.nr.elapsed_sec, 0.001);
        fprintf('Speedup (NR vs GS): %.1fx\n', speedup);
        fprintf('Voltage agreement: %.6f pu max diff\n', ...
            max(abs(results.nr.bus_voltage - results.gs.bus_voltage)));
    end
end

% ── Export ──
if export_results
    output_dir = fullfile(pwd, 'output');
    if ~exist(output_dir, 'dir'), mkdir(output_dir); end

    name = matlab.lang.makeValidName(case_data.system_name);

    % CSV summary
    csv_path = fullfile(output_dir, sprintf('benchmark_%s.csv', name));
    fid = fopen(csv_path, 'w');
    fprintf(fid, 'Method,Converged,Iterations,Time_sec,P_loss_pu,Q_loss_pu\n');
    if isfield(results, 'nr')
        fprintf(fid, 'NR,%d,%d,%.4f,%.6f,%.6f\n', ...
            results.nr.converged, results.nr.iterations, results.nr.elapsed_sec, ...
            results.nr.P_loss_total, results.nr.Q_loss_total);
    end
    if isfield(results, 'gs')
        fprintf(fid, 'GS,%d,%d,%.4f,%.6f,%.6f\n', ...
            results.gs.converged, results.gs.iterations, results.gs.elapsed_sec, ...
            results.gs.P_loss_total, results.gs.Q_loss_total);
    end
    fclose(fid);
    if verbose, fprintf('\nBenchmark CSV: %s\n', csv_path); end

    % JSON export
    json_path = fullfile(output_dir, sprintf('benchmark_%s.json', name));
    export = struct();
    if isfield(results, 'nr')
        export.nr = struct('converged', results.nr.converged, 'iterations', results.nr.iterations, ...
            'time_sec', results.nr.elapsed_sec, 'P_loss_pu', results.nr.P_loss_total);
    end
    if isfield(results, 'gs')
        export.gs = struct('converged', results.gs.converged, 'iterations', results.gs.iterations, ...
            'time_sec', results.gs.elapsed_sec, 'P_loss_pu', results.gs.P_loss_total);
    end
    fid = fopen(json_path, 'w');
    fprintf(fid, '%s', jsonencode(export, 'PrettyPrint', true));
    fclose(fid);
    if verbose, fprintf('Benchmark JSON: %s\n', json_path); end

    % Convergence comparison plot
    f = figure('Name', 'Benchmark Convergence', 'Color', 'w', 'Visible', 'off');
    hold on;
    if isfield(results, 'nr') && ~isempty(results.nr.mismatch_history)
        semilogy(1:numel(results.nr.mismatch_history), results.nr.mismatch_history, '-o', ...
            'LineWidth', 1.5, 'MarkerSize', 4, 'DisplayName', 'NR');
    end
    if isfield(results, 'gs') && ~isempty(results.gs.mismatch_history)
        semilogy(1:numel(results.gs.mismatch_history), results.gs.mismatch_history, '-s', ...
            'LineWidth', 1.5, 'MarkerSize', 4, 'DisplayName', 'GS');
    end
    xlabel('Iteration'); ylabel('Max Mismatch');
    title(sprintf('%s — Convergence Comparison', case_data.system_name));
    legend('Location', 'best'); grid on;
    saveas(f, fullfile(output_dir, sprintf('benchmark_%s.png', name)));
    close(f);
    if verbose, fprintf('Benchmark plot: %s\n', fullfile(output_dir, sprintf('benchmark_%s.png', name))); end
end

results.system_name = case_data.system_name;
results.methods = methods;
end
