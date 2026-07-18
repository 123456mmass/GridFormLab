function p6_results(app, panel)
%P6_RESULTS  Page 6: execution results (12 indexed sections).
%   Displays the adapted 12-section view model (wizard.adapt_result). If no
%   run has been executed yet, shows a placeholder.

if isempty(app.last_view)
    uicontrol('Parent', panel, 'Style', 'text', ...
        'String', 'No run executed yet. Click Run on the review page.', ...
        'Units', 'normalized', 'Position', [0.04 0.45 0.92 0.1]);
    return;
end
view = app.last_view;
setappdata(panel, 'p6_appfig', app.fig);

% Section list (left) + section content (right) two-pane layout.
secs = view.sections;
labels = arrayfun(@(s) sprintf('%d. %s [%s]', s.index, s.title, upper(s.status)), secs, ...
    'UniformOutput', false);
uicontrol('Parent', panel, 'Style', 'listbox', ...
    'String', labels, 'Units', 'normalized', 'Position', [0.02 0.10 0.40 0.84], ...
    'Max', 1, 'Min', 0, 'Value', 1, ...
    'Callback', @(src, ~) wizard.pages.p6_show_section(src, panel, view));
setappdata(panel, 'p6_view', view);

% Content area on the right.
uicontrol('Parent', panel, 'Style', 'edit', 'Tag', 'p6_content', ...
    'Units', 'normalized', 'Position', [0.44 0.10 0.54 0.84], ...
    'Max', 1e6, 'Min', 0, 'HorizontalAlignment', 'left', ...
    'BackgroundColor', [1 1 1]);
wizard.pages.p6_render_section(panel, view, 1);
end
