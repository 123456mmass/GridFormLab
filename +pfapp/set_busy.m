function app = set_busy(app, is_busy)
%SET_BUSY Enable/disable buttons during long operations.
%   Returns modified app struct.

if is_busy
    state = 'off';
else
    app = pfapp.stop_progress(app);
    state = 'on';
end

fields = {'run_button', 'export_button', 'tests_button', ...
          'separate_plot_button', 'analysis_plot_button', ...
          'auto_separate_checkbox'};
for i = 1:numel(fields)
    if isfield(app, fields{i}) && ~isempty(app.(fields{i}))
        app.(fields{i}).Enable = state;
    end
end
drawnow limitrate;
end
