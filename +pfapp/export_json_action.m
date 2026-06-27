function app = export_json_action(app, fig)
%EXPORT_JSON_ACTION Export last result as structured JSON.

app = pfapp.set_busy(app, true);
app = pfapp.start_progress(app, fig, 'Exporting JSON ...', 'Writing structured JSON file.');
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
    json_path = fullfile(output_dir, [prefix, '.json']);
    json_text = jsonencode(data, 'PrettyPrint', true);
    fid = fopen(json_path, 'w');
    if fid < 0
        error('Cannot open %s for writing.', json_path);
    end
    fprintf(fid, '%s', json_text);
    fclose(fid);

    pfapp.append_log(app, sprintf('JSON exported: %s', json_path));
catch err
    pfapp.append_log(app, sprintf('JSON EXPORT ERROR: %s', err.message));
    try
        uialert(fig, err.message, 'JSON Export Failed');
    catch
    end
end
app = pfapp.set_busy(app, false);
end
