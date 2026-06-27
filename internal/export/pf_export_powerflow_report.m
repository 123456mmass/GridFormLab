function paths = pf_export_powerflow_report(results, output_dir, file_prefix, options)
%PF_EXPORT_POWERFLOW_REPORT Export a detailed power-flow report as TXT/PDF.

if nargin < 2 || isempty(output_dir)
    output_dir = fullfile(pwd, 'output');
end
if nargin < 3 || isempty(file_prefix)
    file_prefix = make_safe_name(sprintf('%s_%s', results.system_name, results.method));
end
if nargin < 4
    options = struct();
end

export_pdf = pf_get_option(options, 'export_pdf', true);
font_size = pf_get_option(options, 'font_size', 7.5);
lines_per_page = pf_get_option(options, 'lines_per_page', 67);

if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

report_lines = pf_format_powerflow_report(results);
txt_file = fullfile(output_dir, [file_prefix '_report.txt']);
pdf_file = fullfile(output_dir, [file_prefix '_report.pdf']);

write_text_report(report_lines, txt_file);

paths = struct('report_txt', txt_file);

if export_pdf
    try
        write_pdf_report(report_lines, pdf_file, font_size, lines_per_page);
        paths.report_pdf = pdf_file;
    catch err
        paths.report_pdf = '';
        paths.report_pdf_error = err.message;
        warning('pf_export_powerflow_report:PdfExportFailed', ...
            'Report TXT was written, but PDF export failed: %s', err.message);
    end
end
end

function write_text_report(report_lines, filename)
fid = fopen(filename, 'w');
if fid < 0
    error('Could not open %s for writing.', filename);
end
cleanup = onCleanup(@() fclose(fid));
for i = 1:numel(report_lines)
    fprintf(fid, '%s\n', report_lines{i});
end
end

function write_pdf_report(report_lines, filename, font_size, lines_per_page)
if exist(filename, 'file')
    delete(filename);
end

num_pages = max(1, ceil(numel(report_lines) / lines_per_page));
for page = 1:num_pages
    first_line = (page - 1) * lines_per_page + 1;
    last_line = min(page * lines_per_page, numel(report_lines));
    page_lines = report_lines(first_line:last_line);
    page_text = strjoin(page_lines, newline);

    fig = figure('Visible', 'off', 'Color', 'w', ...
        'Units', 'inches', 'Position', [0 0 8.5 11], ...
        'PaperUnits', 'inches', 'PaperPosition', [0 0 8.5 11]);
    try
        ax = axes(fig, 'Position', [0.055 0.04 0.91 0.93]);
        axis(ax, 'off');
        text(ax, 0, 1, page_text, ...
            'Units', 'normalized', ...
            'VerticalAlignment', 'top', ...
            'HorizontalAlignment', 'left', ...
            'FontName', 'Courier New', ...
            'FontSize', font_size, ...
            'Interpreter', 'none');
        text(ax, 0.5, 0.005, sprintf('Page %d of %d', page, num_pages), ...
            'Units', 'normalized', ...
            'VerticalAlignment', 'bottom', ...
            'HorizontalAlignment', 'center', ...
            'FontName', 'Courier New', ...
            'FontSize', font_size - 0.5, ...
            'Interpreter', 'none');
        drawnow;

        export_args = {'ContentType', 'vector', 'BackgroundColor', 'white'};
        if page > 1
            export_args = [export_args, {'Append', true}]; %#ok<AGROW>
        end
        exportgraphics(ax, filename, export_args{:});
    catch err
        if ishandle(fig)
            close(fig);
        end
        rethrow(err);
    end
    if ishandle(fig)
        close(fig);
    end
end
end

function safe_name = make_safe_name(name)
safe_name = regexprep(char(name), '[^A-Za-z0-9_]+', '_');
safe_name = regexprep(safe_name, '_+', '_');
safe_name = regexprep(safe_name, '^_|_$', '');
end
