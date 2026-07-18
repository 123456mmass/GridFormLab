function p5_review(app, panel)
%P5_REVIEW  Page 5: read-only review of the run contract.
%   Displays a human-readable contract summary (analysis, case, options,
%   events policy) before execution. Save Configuration writes a
%   wizard_config_v1 file with its own fingerprint.

if isempty(app.analysis) || isempty(app.case_id)
    uicontrol('Parent', panel, 'Style', 'text', ...
        'String', 'Please select an analysis and a case first (Back).', ...
        'Units', 'normalized', 'Position', [0.04 0.45 0.92 0.1]);
    return;
end
setappdata(panel, 'p5_appfig', app.fig);

% Build a summary string.
opt = app.user_options;
if isempty(fieldnames(opt))
    opt = wizard.defaults_for_method(app.analysis, wizard.discover_cases(app.analysis));
end
ev_pol = app.events_policy;
if isempty(ev_pol), ev_pol = 'event_free'; end
lines = { ...
    sprintf('Analysis : %s', app.analysis); ...
    sprintf('Case     : %s', app.case_id); ...
    sprintf('Events   : %s', ev_pol); ...
    'Options  :'; };
fn = fieldnames(opt);
for k = 1:numel(fn)
    lines{end+1} = sprintf('  %-20s = %s', fn{k}, wizard.pages.format_value(opt.(fn{k}))); %#ok<AGROW>
end
uicontrol('Parent', panel, 'Style', 'text', ...
    'String', strjoin(lines, newline), ...
    'Units', 'normalized', 'Position', [0.04 0.10 0.92 0.84], ...
    'HorizontalAlignment', 'left', 'BackgroundColor', [1 1 1]);

% Save Configuration button (own fingerprint, correction: separate from
% Section H / selector fingerprints).
uicontrol('Parent', panel, 'Style', 'pushbutton', 'String', 'Save configuration...', ...
    'Units', 'normalized', 'Position', [0.04 0.01 0.20 0.06], ...
    'Callback', @(~,~) wizard.pages.p5_save_config(app.fig));
end
