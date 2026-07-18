function p1_analysis(app, panel)
%P1_ANALYSIS  Page 1: select the analysis (base-MATLAB uicontrol list).
%   wizard.pages.p1_analysis(app, panel) renders the analysis-selection page
%   into PANEL. Four analyses (pf/sssa/ts/ibr) with display name, description,
%   equilibrium required, events applicable, resource support.

reg = app.registry;
labels = arrayfun(@(r) sprintf('%s — %s', r.label, r.description), reg, ...
    'UniformOutput', false);
ids = {reg.id};
% Persist ids on the panel userdata for the selection callback.
setappdata(panel, 'analysis_ids', ids);
setappdata(panel, 'analysis_appfig', app.fig);

uicontrol('Parent', panel, 'Style', 'text', 'String', 'Select an analysis:', ...
    'Units', 'normalized', 'Position', [0.04 0.90 0.92 0.06], ...
    'HorizontalAlignment', 'left', 'FontWeight', 'bold', 'FontSize', 11);

init = 1;
if ~isempty(app.analysis)
    init = find(strcmp(ids, app.analysis), 1);
    if isempty(init), init = 1; end
end

lb = uicontrol('Parent', panel, 'Style', 'listbox', ...
    'Units', 'normalized', 'Position', [0.04 0.20 0.92 0.66], ...
    'String', labels, 'Max', 1, 'Min', 0, 'Value', init, ...
    'Callback', @(src, ~) wizard.pages.p1_analysis_selected(src, panel));

% Description panel below the list.
desc = uicontrol('Parent', panel, 'Style', 'text', 'Tag', 'p1_desc', ...
    'Units', 'normalized', 'Position', [0.04 0.04 0.92 0.14], ...
    'HorizontalAlignment', 'left', 'BackgroundColor', [1 1 1]);
setappdata(desc, 'descriptions', {reg.description});
wizard.pages.p1_analysis_selected(lb, panel);
end
