function wire_callbacks(app, fig)
%WIRE_CALLBACKS Attach all GUI callbacks after (re)building the layout.
%   pfapp.wire_callbacks(app, fig) wires every interactive widget to its
%   action function via the central pfapp.cb dispatcher. Callbacks capture
%   only the stable figure handle FIG and fetch the live app struct from
%   FIG.UserData.app on every invocation, so the wiring stays valid after
%   an in-place theme rebuild (which replaces every widget handle).
%
%   This is the single source of truth for callback wiring — called both by
%   run_powerflow_gui (initial build) and toggle_theme (post-rebuild).

    app.method_dropdown.ValueChangedFcn   = @(~,~) pfapp.cb(fig, @pfapp.update_method_state,   false);
    app.case_dropdown.ValueChangedFcn     = @(~,~) pfapp.cb(fig, @pfapp.on_case_changed,       false);
    app.auto_cpf_checkbox.ValueChangedFcn = @(~,~) pfapp.cb(fig, @pfapp.update_method_state,   false);
    app.browse_case_button.ButtonPushedFcn = @(~,~) pfapp.cb(fig, @pfapp.browse_custom_case,   true);
    app.run_button.ButtonPushedFcn        = @(~,~) pfapp.cb(fig, @pfapp.run_selected_action,   true);
    app.export_button.ButtonPushedFcn     = @(~,~) pfapp.cb(fig, @pfapp.export_last_action,    true);
    app.export_json_button.ButtonPushedFcn = @(~,~) pfapp.cb(fig, @pfapp.export_json_action,   true);
    app.export_html_button.ButtonPushedFcn  = @(~,~) pfapp.cb(fig, @pfapp.export_html_action,  true);
    app.tests_button.ButtonPushedFcn      = @(~,~) pfapp.cb(fig, @pfapp.run_tests_action,      true);
    app.clear_button.ButtonPushedFcn      = @(~,~) pfapp.cb(fig, @pfapp.clear_log_action,      false);
    app.separate_plot_button.ButtonPushedFcn = @(~,~) pfapp.cb(fig, @pfapp.open_separate_plots_action, true);
    app.analysis_plot_button.ButtonPushedFcn = @(~,~) pfapp.cb(fig, @pfapp.open_analysis_plots_action, true);
    app.open_output_button.ButtonPushedFcn   = @(~,~) pfapp.cb(fig, @pfapp.open_output_action, false);
    app.theme_toggle.ButtonPushedFcn      = @(~,~) pfapp.cb(fig, @pfapp.toggle_theme,          true);
    app.log_toggle.ButtonPushedFcn        = @(~,~) pfapp.cb(fig, @pfapp.toggle_log_panel,       false);

    fig.CloseRequestFcn = @(~,~) pfapp.close_fig(fig);
end
