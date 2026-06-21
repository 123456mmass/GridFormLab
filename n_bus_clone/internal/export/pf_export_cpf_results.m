function paths = pf_export_cpf_results(cpf, output_dir, file_prefix, options)
%PF_EXPORT_CPF_RESULTS Export CPF curve data, summary, and optional figure.

if nargin < 2 || isempty(output_dir)
    output_dir = fullfile(pwd, 'output');
end
if nargin < 3 || isempty(file_prefix)
    file_prefix = make_safe_name(sprintf('%s_%s', cpf.system_name, cpf.method));
end
if nargin < 4
    options = struct();
end

export_figures = pf_get_option(options, 'export_figures', true);

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

curve_csv = fullfile(output_dir, [file_prefix '_cpf_curve.csv']);
summary_txt = fullfile(output_dir, [file_prefix '_cpf_summary.txt']);
figure_png = fullfile(output_dir, [file_prefix '_cpf_curve.png']);

bus_voltage_names = cellstr(compose('V_bus_%g', cpf.external_bus_ids));
curve_table = array2table([cpf.lambdas(:), cpf.target_voltage(:), cpf.bus_voltage'], ...
    'VariableNames', [{'lambda', sprintf('V_target_bus_%g', cpf.target_bus)}, bus_voltage_names(:).']);
writetable(curve_table, curve_csv);
write_cpf_summary(cpf, summary_txt);

paths = struct('curve_csv', curve_csv, 'summary_txt', summary_txt);

if export_figures
    old_visible = get(0, 'DefaultFigureVisible');
    cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', old_visible));
    set(0, 'DefaultFigureVisible', 'off');
    pf_plot_cpf_results(cpf);
    save_current_figure(figure_png);
    close(gcf);
    paths.figure_png = figure_png;
    clear cleanup;
end
end

function write_cpf_summary(cpf, filename)
fid = fopen(filename, 'w');
if fid < 0
    error('Could not open %s for writing.', filename);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'CPF Summary\n');
fprintf(fid, 'System: %s\n', cpf.system_name);
fprintf(fid, 'Method: %s\n', cpf.method);
fprintf(fid, 'Target bus: %g\n', cpf.target_bus);
fprintf(fid, 'Solved points: %d\n', numel(cpf.lambdas));
fprintf(fid, 'Stop reason: %s\n', cpf.stop_reason);
fprintf(fid, 'Nose detected: %d\n', cpf.nose_detected);
fprintf(fid, 'Nose lambda: %.8f\n', cpf.nose_lambda);
fprintf(fid, 'Nose voltage: %.8f\n', cpf.nose_voltage);
fprintf(fid, 'Lowest lambda: %.8f\n', cpf.lowest_lambda);
fprintf(fid, 'Lowest voltage: %.8f\n', cpf.lowest_voltage);
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
