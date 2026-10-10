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
% DISPLAY FILTER ONLY.  The owner keeps the offered working set to the two
% production networks (2026-09-26); hidden catalog cases stay fully runnable
% by id through solve_case, scripts/reporting/ and the routing tests.  Only
% app.case_id flows to the later pages (p3 re-discovers the FULL list and
% looks that id up), so trimming the listbox here cannot orphan anything.
entries = entries([entries.gui_visible]);
if isempty(entries)
    error('wizard:pages:p2_case:noVisibleCases', ...
        'Analysis %s offers no visible cases.', app.analysis);
end
app.cases = entries;
setappdata(panel, 'case_ids', {entries.id});
setappdata(panel, 'case_appfig', app.fig);

labels = arrayfun(@(e) sprintf('%s — %s', e.id, e.label), entries, ...
    'UniformOutput', false);
uicontrol('Parent', panel, 'Style', 'text', 'String', 'Select a case:', ...
    'Units', 'normalized', 'Position', [0.06 0.82 0.88 0.08], ...
    'HorizontalAlignment', 'left', 'FontWeight', 'bold', 'FontSize', 11);

init = 1;
if ~isempty(app.case_id)
    init = find(strcmp({entries.id}, app.case_id), 1);
    if isempty(init), init = 1; end
end
lb = uicontrol('Parent', panel, 'Style', 'listbox', ...
    'Units', 'normalized', 'Position', [0.06 0.34 0.88 0.46], ...
    'String', labels, 'Max', 1, 'Min', 0, 'Value', init, ...
    'Callback', @(src, ~) wizard.pages.p2_case_selected(src, panel));

uicontrol('Parent', panel, 'Style', 'text', 'Tag', 'p2_desc', ...
    'Units', 'normalized', 'Position', [0.06 0.12 0.88 0.16], ...
    'HorizontalAlignment', 'left', 'BackgroundColor', [1 1 1]);

% The displayed initial row is a real selection. Commit it immediately so
% clicking Next without first changing rows cannot leave case_id empty.
wizard.pages.p2_case_selected(lb, panel);
end
