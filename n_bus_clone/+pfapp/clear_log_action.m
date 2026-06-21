function app = clear_log_action(app)
%CLEAR_LOG_ACTION Reset the run log to the ready message.
app.log_area.Value = {'Ready.'};
end
