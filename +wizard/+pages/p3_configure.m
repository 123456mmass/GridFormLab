function p3_configure(app, panel)
%P3_CONFIGURE  Page 3: configure the analysis (dynamic per method).
%   Renders a three-column Label / Control / Unit-or-source layout of the
%   options for the selected analysis. Fields are populated from
%   wizard.defaults_for_method; the user may edit values that flow into
%   app.user_options on Run.

if isempty(app.analysis) || isempty(app.case_id)
    uicontrol('Parent', panel, 'Style', 'text', ...
        'String', 'Please select an analysis and a case first (Back).', ...
        'Units', 'normalized', 'Position', [0.04 0.45 0.92 0.1]);
    return;
end
opt = wizard.defaults_for_method(app.analysis, find_entry(app));
app.user_options = opt;
setappdata(panel, 'p3_appfig', app.fig);

% Events applicability banner.
reg = app.registry;
aidx = find(strcmp({reg.id}, app.analysis), 1);
events_app = reg(aidx).events_applicable;
banner = 'Events: NOT_APPLICABLE';
if events_app, banner = 'Events: configurable on the next page'; end
uicontrol('Parent', panel, 'Style', 'text', 'String', banner, ...
    'Units', 'normalized', 'Position', [0.04 0.90 0.92 0.06], ...
    'HorizontalAlignment', 'left', 'FontWeight', 'bold');

% Three-column table of options (Label / Value / Unit-or-source).
fields = fieldnames(opt);
n = numel(fields);
data = cell(n, 3);
for k = 1:n
    v = opt.(fields{k});
    data{k, 1} = fields{k};
    data{k, 2} = wizard.pages.format_value(v);
    data{k, 3} = wizard.pages.classify(fields{k});
end
t = uitable('Parent', panel, 'Data', data, ...
    'ColumnName', {'Option', 'Value', 'Class/Source'}, ...
    'Units', 'normalized', 'Position', [0.04 0.10 0.92 0.76], ...
    'ColumnWidth', {180 200 200}, 'RowName', []);
setappdata(panel, 'p3_table', t);
end

function entry = find_entry(app)
entries = wizard.discover_cases(app.analysis);
idx = find(strcmp(app.case_id, {entries.id}), 1);
if isempty(idx), entry = struct(); else, entry = entries(idx); end
end
