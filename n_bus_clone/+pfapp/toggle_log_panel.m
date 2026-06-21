function app = toggle_log_panel(app)
%TOGGLE_LOG_PANEL Show or hide the run log panel.

if ~isfield(app, 'log_visible') || isempty(app.log_visible)
    app.log_visible = true;
end

if app.log_visible
    app.outer_grid.RowHeight = {58, '1x', 0};
    app.log_panel.Visible = 'off';
    app.log_toggle.Text = '☰  Show Log';
    app.log_visible = false;
else
    app.outer_grid.RowHeight = {58, '1x', app.log_row_height};
    app.log_panel.Visible = 'on';
    app.log_toggle.Text = '☰  Hide Log';
    app.log_visible = true;
end
end
