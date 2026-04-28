function set_busy(app, is_busy)
%SET_BUSY Enable/disable buttons during long operations.

if is_busy
    state = 'off';
else
    pfapp.stop_progress(app);
    state = 'on';
end
app.run_button.Enable = state;
app.export_button.Enable = state;
app.tests_button.Enable = state;
app.separate_plot_button.Enable = state;
app.analysis_plot_button.Enable = state;
app.auto_separate_checkbox.Enable = state;
drawnow limitrate;
end
