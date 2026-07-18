function p1_analysis_selected(src, panel)
%P1_ANALYSIS_SELECTED  Callback: record the selected analysis.
fig = getappdata(panel, 'analysis_appfig');
ids = getappdata(panel, 'analysis_ids');
sel = get(src, 'Value');
if isempty(sel) || sel < 1 || sel > numel(ids), return; end
app = fig.UserData.app;
app.analysis = lower(ids{sel});
% Update accent color.
reg = app.registry;
idx = find(strcmp({reg.id}, app.analysis), 1);
if ~isempty(idx), app.accent = reg(idx).accent_color; end
% Refresh the description text.
desc = findobj(panel, 'Tag', 'p1_desc');
if ~isempty(desc)
    descriptions = getappdata(desc, 'descriptions');
    if ~isempty(descriptions) && sel <= numel(descriptions)
        set(desc, 'String', descriptions{sel});
    end
end
fig.UserData.app = app;
end
