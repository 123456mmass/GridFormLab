function app = clear_log_action(app)
%DEPRECATED (Phase C): superseded by the Studio GUI (+studio/launch.m).
%   Header banner only; behavior unchanged.
%CLEAR_LOG_ACTION Reset the run log to the ready message.
app.log_area.Value = {'Ready.'};
end
