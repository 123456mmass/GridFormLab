function app = export_last_action(app, fig)
%EXPORT_LAST_ACTION Export button callback. Returns modified app.

app = pfapp.set_busy(app, true);
app = pfapp.start_progress(app, fig, 'Exporting results ...', ...
    'Writing files under the output folder.');
try
    output_dir = fullfile(pwd, 'output');
    if ~isempty(app.last_result)
        prefix = pfapp.make_safe_name(sprintf('%s_%s', ...
            app.last_result.system_name, app.last_result.method));
        paths = pf_export_results(app.last_result, output_dir, prefix, ...
            struct('export_figures', true));
        pfapp.append_log(app, sprintf('Exported result: %s', paths.summary_txt));
        if isfield(paths, 'report_pdf') && ~isempty(paths.report_pdf)
            pfapp.append_log(app, sprintf('Formal report PDF: %s', paths.report_pdf));
        elseif isfield(paths, 'report_txt')
            pfapp.append_log(app, sprintf('Formal report TXT: %s', paths.report_txt));
        end
        if isfield(paths, 'report_pdf_error') && ~isempty(paths.report_pdf_error)
            pfapp.append_log(app, sprintf('PDF report warning: %s', paths.report_pdf_error));
        end
    elseif ~isempty(app.last_cpf)
        prefix = pfapp.make_safe_name(sprintf('%s_%s', ...
            app.last_cpf.system_name, app.last_cpf.method));
        paths = pf_export_cpf_results(app.last_cpf, output_dir, prefix, ...
            struct('export_figures', true));
        pfapp.append_log(app, sprintf('Exported CPF: %s', paths.summary_txt));
    elseif ~isempty(app.last_opf)
        prefix = pfapp.make_safe_name(sprintf('%s_%s', ...
            app.last_opf.system_name, app.last_opf.method));
        paths = pf_export_opf_results(app.last_opf, output_dir, prefix);
        pfapp.append_log(app, sprintf('Exported OPF: %s', paths.summary_txt));
    else
        pfapp.append_log(app, 'Nothing to export yet. Run a method first.');
    end
catch err
    pfapp.append_log(app, sprintf('EXPORT ERROR: %s', err.message));
    try
        uialert(fig, err.message, 'Export Failed');
    catch
    end
end
app = pfapp.set_busy(app, false);
end
