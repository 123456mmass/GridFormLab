function append_log(app, message)
%DEPRECATED (Phase C): superseded by the Studio GUI (+studio/launch.m).
%   Header banner only; behavior unchanged.
%APPEND_LOG Timestamp and append a message to the log area.

timestamp = char(datetime('now', 'Format', 'HH:mm:ss'));
current = app.log_area.Value;
if ischar(current)
    current = {current};
end
app.log_area.Value = [current(:); {sprintf('[%s] %s', timestamp, message)}];
drawnow limitrate;
end
