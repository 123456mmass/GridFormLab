function stop_progress(app)
%STOP_PROGRESS Close the progress dialog if open.

if ~isempty(app.progress_dialog) && isvalid(app.progress_dialog)
    close(app.progress_dialog);
end
app.progress_dialog = [];
drawnow limitrate;
end
