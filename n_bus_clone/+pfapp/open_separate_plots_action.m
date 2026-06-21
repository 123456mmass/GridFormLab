function open_separate_plots_action(app, fig)
%OPEN_SEPARATE_PLOTS_ACTION Open standalone figures for the last result.

try
    if ~isempty(app.last_smib)
        pfapp.open_smib_figure(app);
        return;
    elseif ~isempty(app.last_suite)
        pfapp.open_suite_figure(app.last_suite);
        pfapp.append_log(app, 'Opened separate suite plots.');
    elseif ~isempty(app.last_result)
        pfapp.open_powerflow_figure(app.last_result);
        pfapp.append_log(app, 'Opened separate power-flow plots with voltage angle.');
    elseif ~isempty(app.last_cpf)
        pfapp.open_cpf_figure(app.last_cpf);
        pfapp.append_log(app, pfapp.cpf_opened_plot_line(app.last_cpf));
    elseif ~isempty(app.last_opf)
        pfapp.open_opf_figure(app.last_opf);
        pfapp.append_log(app, sprintf('Opened separate %s plots.', app.last_opf.method));
    else
        pfapp.append_log(app, 'No plot to open yet. Run a method first.');
    end
catch err
    pfapp.append_log(app, sprintf('PLOT ERROR: %s', err.message));
    uialert(fig, err.message, 'Open Plot Failed');
end
end
