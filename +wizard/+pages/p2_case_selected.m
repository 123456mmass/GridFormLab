function p2_case_selected(src, panel)
%P2_CASE_SELECTED  Callback: record the selected case.
fig = getappdata(panel, 'case_appfig');
ids = getappdata(panel, 'case_ids');
sel = get(src, 'Value');
if isempty(sel) || sel < 1 || sel > numel(ids), return; end
app = fig.UserData.app;
app.case_id = lower(ids{sel});
fig.UserData.app = app;
end
