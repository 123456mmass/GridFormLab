function p2_case(app, panel)
%P2_CASE  Page 2: select the case (base-MATLAB listbox).
%   Lazy case discovery (correction #8): enumerates case metadata via
%   wizard.discover_cases WITHOUT executing PF/equilibrium or loading solved
%   states.

if isempty(app.analysis)
    uicontrol('Parent', panel, 'Style', 'text', ...
        'String', 'Please select an analysis first (Back).', ...
        'Units', 'normalized', 'Position', [0.04 0.45 0.92 0.1]);
    return;
end
entries = wizard.discover_cases(app.analysis);
app.cases = entries;
setappdata(panel, 'case_ids', {entries.id});
setappdata(panel, 'case_appfig', app.fig);

labels = arrayfun(@(e) sprintf('%s — %s', e.id, e.label), entries, ...
    'UniformOutput', false);
uicontrol('Parent', panel, 'Style', 'text', 'String', 'Select a case:', ...
    'Units', 'normalized', 'Position', [0.04 0.90 0.92 0.06], ...
    'HorizontalAlignment', 'left', 'FontWeight', 'bold', 'FontSize', 11);

init = 1;
if ~isempty(app.case_id)
    init = find(strcmp({entries.id}, app.case_id), 1);
    if isempty(init), init = 1; end
end
uicontrol('Parent', panel, 'Style', 'listbox', ...
    'Units', 'normalized', 'Position', [0.04 0.20 0.92 0.66], ...
    'String', labels, 'Max', 1, 'Min', 0, 'Value', init, ...
    'Callback', @(src, ~) wizard.pages.p2_case_selected(src, panel));

uicontrol('Parent', panel, 'Style', 'text', 'Tag', 'p2_desc', ...
    'Units', 'normalized', 'Position', [0.04 0.04 0.92 0.14], ...
    'HorizontalAlignment', 'left', 'BackgroundColor', [1 1 1]);
end
