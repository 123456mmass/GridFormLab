function paths = pf_export_results(results, output_dir, file_prefix, options)
%PF_EXPORT_RESULTS Export power-flow results to CSV, text, and optional figures.

if nargin < 2 || isempty(output_dir)
    output_dir = fullfile(pwd, 'output');
end
if nargin < 3 || isempty(file_prefix)
    file_prefix = make_safe_name(sprintf('%s_%s', results.system_name, results.method));
end
if nargin < 4
    options = struct();
end

export_figures = pf_get_option(options, 'export_figures', true);
export_report = pf_get_option(options, 'export_report', true);
export_report_pdf = pf_get_option(options, 'export_report_pdf', true);
tolerance = pf_get_option(options, 'tolerance', 1e-6);

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

bus_csv = fullfile(output_dir, [file_prefix '_bus_results.csv']);
line_csv = fullfile(output_dir, [file_prefix '_line_results.csv']);
summary_txt = fullfile(output_dir, [file_prefix '_summary.txt']);
figure_png = fullfile(output_dir, [file_prefix '_plots.png']);

bus_table = table( ...
    results.external_bus_ids(:), ...
    results.bus_type(:), ...
    results.bus_voltage(:), ...
    results.bus_angle_deg(:), ...
    results.P_generation(:), ...
    results.Q_generation(:), ...
    results.P_load(:), ...
    results.Q_load(:), ...
    results.P_net_specified(:), ...
    results.Q_net_specified(:), ...
    results.Q_min(:), ...
    results.Q_max(:), ...
    'VariableNames', {'Bus', 'Type', 'V_pu', 'Angle_deg', 'Pgen_pu', 'Qgen_pu', ...
    'Pload_pu', 'Qload_pu', 'Pnet_spec_pu', 'Qnet_spec_pu', 'Qmin_pu', 'Qmax_pu'});

line_table = table( ...
    results.line_endpoints(:, 1), ...
    results.line_endpoints(:, 2), ...
    results.line_flow_P(:), ...
    results.line_flow_Q(:), ...
    results.line_loss_P(:), ...
    results.line_loss_Q(:), ...
    results.line_tap_ratio(:), ...
    results.line_phase_shift_deg(:), ...
    'VariableNames', {'From', 'To', 'P_from_pu', 'Q_from_pu', ...
    'P_loss_pu', 'Q_loss_pu', 'Tap', 'PhaseShift_deg'});

writetable(bus_table, bus_csv);
writetable(line_table, line_csv);
write_summary(results, summary_txt);

paths = struct('bus_csv', bus_csv, 'line_csv', line_csv, 'summary_txt', summary_txt);

if export_report
    report_paths = pf_export_powerflow_report(results, output_dir, file_prefix, ...
        struct('export_pdf', export_report_pdf));
    paths.report_txt = report_paths.report_txt;
    if isfield(report_paths, 'report_pdf')
        paths.report_pdf = report_paths.report_pdf;
    end
    if isfield(report_paths, 'report_pdf_error')
        paths.report_pdf_error = report_paths.report_pdf_error;
    end
end

if export_figures
    old_visible = get(0, 'DefaultFigureVisible');
    cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_visible));
    set(0, 'DefaultFigureVisible', 'off');
    pf_plot_powerflow_results(results, tolerance);
    save_current_figure(figure_png);
    close(gcf);
    paths.figure_png = figure_png;
    clear cleanup;
end
end

function write_summary(results, filename)
fid = fopen(filename, 'w');
if fid < 0
    error('Could not open %s for writing.', filename);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'Power Flow Summary\n');
fprintf(fid, 'System: %s\n', results.system_name);
fprintf(fid, 'Method: %s\n', results.method);
fprintf(fid, 'Converged: %d\n', results.converged);
fprintf(fid, 'Iterations: %d\n', results.iterations);
fprintf(fid, 'Total P generation: %.8f pu\n', results.P_total_gen);
fprintf(fid, 'Total Q generation: %.8f pu\n', results.Q_total_gen);
fprintf(fid, 'Total P load: %.8f pu\n', results.P_total_load);
fprintf(fid, 'Total Q load: %.8f pu\n', results.Q_total_load);
fprintf(fid, 'Total P loss: %.8f pu\n', results.P_loss_total);
fprintf(fid, 'Total Q loss: %.8f pu\n', results.Q_loss_total);
fprintf(fid, 'P balance residual: %.8e pu\n', ...
    results.P_total_gen + results.P_shunt_injected_total - results.P_total_load - results.P_loss_total);
fprintf(fid, 'Q balance residual: %.8e pu\n', ...
    results.Q_total_gen + results.Q_shunt_injected_total - results.Q_total_load - results.Q_loss_total);

if isfield(results, 'q_limit_switching') && ~isempty(results.q_limit_switching.events)
    fprintf(fid, '\nQ-limit switching events:\n');
    for i = 1:numel(results.q_limit_switching.events)
        event = results.q_limit_switching.events(i);
        fprintf(fid, 'Round %d, bus %d: %s -> %s, Q before %.8f, fixed %.8f at %s\n', ...
            event.round, event.bus_id, event.from_type, event.to_type, ...
            event.Q_generation_before, event.Q_fixed, event.limit_type);
    end
end
end

function save_current_figure(filename)
try
    exportgraphics(gcf, filename, 'Resolution', 200);
catch
    saveas(gcf, filename);
end
end

function safe_name = make_safe_name(name)
safe_name = regexprep(char(name), '[^A-Za-z0-9_]+', '_');
safe_name = regexprep(safe_name, '_+', '_');
safe_name = regexprep(safe_name, '^_|_$', '');
end
