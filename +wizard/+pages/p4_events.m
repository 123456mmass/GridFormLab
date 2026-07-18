function p4_events(app, panel)
%P4_EVENTS  Page 4: event selection and editor (TS and IBR only).
%   First asks 'Use events?': No events (EVENT_FREE_NORMAL_OPERATION) or
%   Configure. The event-free path produces an explicitly empty event list
%   (correction #6: events=false reaches the production runtime as an
%   ACTUALLY empty schedule).

reg = app.registry;
aidx = find(strcmp({reg.id}, app.analysis), 1);
if isempty(aidx) || ~reg(aidx).events_applicable
    uicontrol('Parent', panel, 'Style', 'text', ...
        'String', 'Events: NOT_APPLICABLE to this analysis.', ...
        'Units', 'normalized', 'Position', [0.04 0.45 0.92 0.1]);
    return;
end
setappdata(panel, 'p4_appfig', app.fig);

uicontrol('Parent', panel, 'Style', 'text', ...
    'String', 'Use events?', ...
    'Units', 'normalized', 'Position', [0.04 0.90 0.92 0.06], ...
    'HorizontalAlignment', 'left', 'FontWeight', 'bold');

% Radio-like toggle via two pushbuttons that set events_policy.
cur = app.events_policy;
if isempty(cur) || strcmp(cur, 'not_applicable'), cur = 'event_free'; end
btn_free = uicontrol('Parent', panel, 'Style', 'radiobutton', ...
    'String', 'No events (EVENT_FREE_NORMAL_OPERATION)', ...
    'Units', 'normalized', 'Position', [0.04 0.78 0.92 0.08], ...
    'Value', strcmp(cur, 'event_free'), ...
    'Callback', @(~,~) wizard.pages.p4_set_policy(panel, 'event_free'));
btn_cfg = uicontrol('Parent', panel, 'Style', 'radiobutton', ...
    'String', 'Configure events', ...
    'Units', 'normalized', 'Position', [0.04 0.68 0.92 0.08], ...
    'Value', strcmp(cur, 'configured'), ...
    'Callback', @(~,~) wizard.pages.p4_set_policy(panel, 'configured'));
setappdata(panel, 'p4_btn_free', btn_free);
setappdata(panel, 'p4_btn_cfg', btn_cfg);

% Event field table (shown only when configured). Uses the IBR default event
% struct as the starting point.
ev = app.events;
if isempty(ev) || ~isstruct(ev) || isempty(fieldnames(ev))
    ev = wizard.defaults_for_method(app.analysis).ibr_events;
end
fields = fieldnames(ev);
n = numel(fields);
data = cell(n, 2);
for k = 1:n
    data{k, 1} = fields{k};
    data{k, 2} = wizard.pages.format_value(ev.(fields{k}));
end
t = uitable('Parent', panel, 'Data', data, ...
    'ColumnName', {'Field', 'Value'}, ...
    'Units', 'normalized', 'Position', [0.04 0.10 0.92 0.54], ...
    'ColumnWidth', {180 220}, 'RowName', []);
setappdata(panel, 'p4_table', t);
end
