function app = export_html_action(app, fig)
%EXPORT_HTML_ACTION Export last result as a standalone HTML report.

app = pfapp.set_busy(app, true);
app = pfapp.start_progress(app, fig, 'Generating HTML report ...', 'Building standalone HTML document.');
try
    output_dir = fullfile(pwd, 'output');
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end

    data = pfapp.collect_export_data(app);
    if isempty(data)
        pfapp.append_log(app, 'Nothing to export. Run a method first.');
        app = pfapp.set_busy(app, false);
        return;
    end

    prefix = pfapp.make_safe_name(sprintf('%s_%s', data.system_name, data.method));
    html_path = fullfile(output_dir, [prefix, '.html']);
    html_text = pfapp.build_html_report(data);
    fid = fopen(html_path, 'w');
    if fid < 0
        error('Cannot open %s for writing.', html_path);
    end
    fprintf(fid, '%s', html_text);
    fclose(fid);

    pfapp.append_log(app, sprintf('HTML report exported: %s', html_path));
catch err
    pfapp.append_log(app, sprintf('HTML EXPORT ERROR: %s', err.message));
    try
        uialert(fig, err.message, 'HTML Export Failed');
    catch
    end
end
app = pfapp.set_busy(app, false);
end
