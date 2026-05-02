function app = run_powerflow_gui()
%RUN_POWERFLOW_GUI Interactive GUI launcher for the n-bus power-flow toolkit.

pf_init_paths();
pfapp.start_ai_service();

app = struct();
app.last_result = [];
app.last_cpf = [];
app.last_suite = [];
app.last_opf = [];
app.last_case_data = [];
[app.case_labels, app.case_loaders] = pfapp.make_case_registry();
app.case_labels{end + 1} = 'Custom n-bus: (none)';
app.case_loaders{end + 1} = [];
app.custom_case_data = [];
app.progress_dialog = [];

[fig, app] = pfapp.create_gui_layout(app);
fig.CloseRequestFcn = @(src, event) close_gui();

% ── Wire callbacks ──
app.method_dropdown.ValueChangedFcn = @(src, event) update_method_state();
app.auto_cpf_checkbox.ValueChangedFcn = @(src, event) update_method_state();
app.browse_case_button.ButtonPushedFcn = @(src, event) browse_custom_case();
app.run_button.ButtonPushedFcn = @(src, event) run_selected();
app.export_button.ButtonPushedFcn = @(src, event) export_last();
app.export_json_button.ButtonPushedFcn = @(src, event) export_json();
app.export_html_button.ButtonPushedFcn = @(src, event) export_html();
app.tests_button.ButtonPushedFcn = @(src, event) run_tests();
app.clear_button.ButtonPushedFcn = @(src, event) set(app.log_area, 'Value', {'Ready.'});
app.separate_plot_button.ButtonPushedFcn = @(src, event) open_separate_plots();
app.analysis_plot_button.ButtonPushedFcn = @(src, event) open_analysis_plots();
app.open_output_button.ButtonPushedFcn = @(src, event) pfapp.append_log(app, fullfile(pwd, 'output'));
app.theme_toggle.ButtonPushedFcn = @(src, event) toggle_theme();
app.log_toggle.ButtonPushedFcn = @(src, event) toggle_log();
app.ai_send_button.ButtonPushedFcn = @(src, event) ai_chat();
app.ai_analyze_button.ButtonPushedFcn = @(src, event) ai_analyze();

pfapp.update_method_state(app);
pfapp.plot_empty_state(app);

% ── Load saved preferences ──
app = pfapp.load_preferences(app);

% ── Nested callbacks ──

    function run_selected()
        app = pfapp.run_selected_action(app, fig);
    end

    function export_last()
        app = pfapp.export_last_action(app, fig);
    end

    function export_json()
        app = pfapp.export_json_action(app, fig);
    end

    function export_html()
        app = pfapp.export_html_action(app, fig);
    end

    function open_separate_plots()
        pfapp.open_separate_plots_action(app, fig);
    end

    function open_analysis_plots()
        app = pfapp.open_analysis_plots_action(app, fig);
    end

    function run_tests()
        app = pfapp.run_tests_action(app, fig);
    end

    function browse_custom_case()
        app = pfapp.browse_custom_case(app, fig);
        if isfield(app, 'case_labels')
            app.case_dropdown.Items = app.case_labels;
        end
    end

    function update_method_state()
        pfapp.update_method_state(app);
    end

    function toggle_theme()
        app = pfapp.toggle_theme(app, fig);
    end

    function toggle_log()
        app = pfapp.toggle_log_panel(app);
    end

    function ai_chat()
        app = pfapp.ai_chat_action(app);
    end

    function ai_analyze()
        app = pfapp.ai_analyze_action(app, fig);
    end

    function close_gui()
        pidfile = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'ai_service', 'ai_service.pid');
        if isfile(pidfile)
            try
                pid = fileread(pidfile);
                pid = strtrim(pid);
                if ispc
                    system(sprintf('taskkill /PID %s /F 2>nul', pid));
                else
                    system(sprintf('kill %s 2>/dev/null', pid));
                end
                delete(pidfile);
            catch
            end
        end
        delete(fig);
    end
end
