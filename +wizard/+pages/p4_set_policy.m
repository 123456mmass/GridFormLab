function p4_set_policy(panel, policy)
%P4_SET_POLICY  Callback: set the events policy (event_free / configured).
fig = getappdata(panel, 'p4_appfig');
app = fig.UserData.app;
app.events_policy = policy;
if strcmp(policy, 'event_free')
    app.events = [];
else
    app.events = wizard.defaults_for_method(app.analysis).ibr_events;
end
% Update radio button values.
btn_free = getappdata(panel, 'p4_btn_free');
btn_cfg = getappdata(panel, 'p4_btn_cfg');
if isgraphics(btn_free), set(btn_free, 'Value', strcmp(policy, 'event_free')); end
if isgraphics(btn_cfg), set(btn_cfg, 'Value', strcmp(policy, 'configured')); end
fig.UserData.app = app;
end
