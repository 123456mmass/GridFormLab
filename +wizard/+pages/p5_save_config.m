function p5_save_config(fig)
%P5_SAVE_CONFIG  Callback: save the current validated configuration.
app = fig.UserData.app;
[fn, path] = uiputfile('*.json', 'Save wizard configuration', 'wizard_config.json');
if isempty(fn) || isempty(path), return; end
fullpath = fullfile(path, fn);
% Build a request from the current state.
opts = app.user_options;
ev = app.events;
if isempty(ev) || ~isstruct(ev)
    req = wizard.build_request(app.analysis, app.case_id, 'options', opts);
else
    req = wizard.build_request(app.analysis, app.case_id, 'options', opts, 'events', ev);
end
try
    wizard.config_io('save', req, fullpath);
    msgbox(sprintf('Saved configuration:\n%s', fullpath), 'Wizard', 'modal');
catch e
    errordlg(sprintf('Save failed: %s', e.message), 'Save error', 'modal');
end
end
