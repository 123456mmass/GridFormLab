function app = stop_progress(app)
%STOP_PROGRESS Close the progress dialog if open.
%   Returns modified app struct.

if ~isempty(app.progress_dialog) && isvalid(app.progress_dialog)
    try
        close(app.progress_dialog);
    catch
    end
end
app.progress_dialog = [];
drawnow limitrate;
end
