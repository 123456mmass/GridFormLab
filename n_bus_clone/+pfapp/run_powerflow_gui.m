function app = run_powerflow_gui()
%RUN_POWERFLOW_GUI Interactive GUI launcher for the n-bus power-flow toolkit.
%   Run from MATLAB:
%       cd('C:\Users\qwert\OneDrive\Desktop\api\n_bus_clone')
%       run_powerflow_gui

pf_init_paths();

app = struct();
app.last_result = [];
app.last_cpf = [];
app.last_suite = [];
app.last_opf = [];
app.last_case_data = [];
[app.case_labels, app.case_loaders] = pfapp.make_case_registry();
app.custom_case_data = [];
app.progress_dialog = [];

[fig, app] = pfapp.create_gui_layout(app);

% --- Wire callbacks ---
app.method_dropdown.ValueChangedFcn = @(src, event) update_method_state();
app.auto_cpf_checkbox.ValueChangedFcn = @(src, event) update_method_state();
app.browse_case_button.ButtonPushedFcn = @(src, event) browse_custom_case();
app.run_button.ButtonPushedFcn = @(src, event) run_selected();
app.export_button.ButtonPushedFcn = @(src, event) export_last();
app.tests_button.ButtonPushedFcn = @(src, event) run_tests();
app.clear_button.ButtonPushedFcn = @(src, event) set(app.log_area, 'Value', {'Ready.'});
app.separate_plot_button.ButtonPushedFcn = @(src, event) open_separate_plots();
app.analysis_plot_button.ButtonPushedFcn = @(src, event) open_analysis_plots();
app.open_output_button.ButtonPushedFcn = @(src, event) pfapp.append_log(app, fullfile(pwd, 'output'));

pfapp.update_method_state(app);
pfapp.plot_empty_state(app);

% --- Thin nested wrappers (closures over app/fig) ---

    function run_selected()
        app = pfapp.run_selected_action(app, fig);
    end

    function export_last()
        pfapp.export_last_action(app, fig);
    end

    function open_separate_plots()
        pfapp.open_separate_plots_action(app, fig);
    end

    function open_analysis_plots()
        pfapp.open_analysis_plots_action(app, fig);
    end

    function run_tests()
        pfapp.run_tests_action(app, fig);
    end

    function case_data = load_selected_case()
        case_data = pfapp.load_selected_case(app);
    end

    function browse_custom_case()
        app = pfapp.browse_custom_case(app, fig);
    end

    function options = cpf_options(case_data, method)
        options = pfapp.build_cpf_options(app, case_data, method);
    end

    function suite = run_suite_headless()
        suite = pfapp.run_suite_headless(app);
    end

    function update_method_state()
        pfapp.update_method_state(app);
    end

    function [options, setup] = auto_calibrate_cpf(case_data, method)
        [options, setup] = pfapp.auto_calibrate_cpf(app, case_data, method);
    end

    function apply_cpf_setup(setup)
        pfapp.apply_cpf_setup(app, setup);
    end
end
