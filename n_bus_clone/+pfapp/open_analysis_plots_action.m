function open_analysis_plots_action(app, fig)
%OPEN_ANALYSIS_PLOTS_ACTION Build 3D benchmark and CPF reference figures.

pfapp.set_busy(app, true);
pfapp.start_progress(app, fig, 'Building analysis plots ...', 'Generating benchmark and CPF reference figures.');
cleanup = onCleanup(@() pfapp.set_busy(app, false));
try
    pfapp.append_log(app, 'Building 3D benchmark and CPF reference plots ...');
    benchmark_idx = cellfun(@(loader) ~isempty(loader) && pfapp.is_powerflow_case_loader(loader), app.case_loaders);
    pfapp.open_benchmark_3d_plots(app.case_labels(benchmark_idx), app.case_loaders(benchmark_idx), pfapp.common_options(app.tolerance_field.Value), app.accel_field.Value);
    if ~isempty(app.last_cpf)
        pfapp.open_cpf_reference_figure(app.last_cpf);
    else
        case_data = pfapp.load_selected_case(app);
        cpf_defaults = pfapp.build_cpf_options(app, case_data, 'CPF Predictor-Corrector');
        cpf_defaults.plot_results = false;
        cpf_defaults.verbose = false;
        pfapp.open_cpf_reference_figure(cpf_predictor_corrector(case_data, cpf_defaults));
    end
    pfapp.append_log(app, 'Opened 3D benchmark and CPF reference plots.');
catch err
    pfapp.append_log(app, sprintf('ANALYSIS PLOT ERROR: %s', err.message));
    uialert(fig, err.message, 'Analysis Plot Failed');
end
end
