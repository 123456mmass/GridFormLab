function app = start_progress(app, fig, title_text, message_text)
%DEPRECATED (Phase C): superseded by the Studio GUI (+studio/launch.m).
%   Header banner only; behavior unchanged.
%START_PROGRESS Open an indeterminate progress dialog.
%   Returns modified app struct.

app = pfapp.stop_progress(app);
try
    app.progress_dialog = uiprogressdlg(fig, ...
        'Title', title_text, ...
        'Message', message_text, ...
        'Indeterminate', 'on', ...
        'Cancelable', 'off', ...
        'Icon', 'info');
catch
    app.progress_dialog = [];
end
drawnow;
end
