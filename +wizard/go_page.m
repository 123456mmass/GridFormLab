function go_page(fig, delta)
%GO_PAGE  Navigate the wizard pages by delta (+1/-1).
%   wizard.go_page(fig, +1) advances to the next applicable page.
%   wizard.go_page(fig, -1) returns to the previous applicable page.
%   Skips non-applicable pages (e.g. events page for PF/SSSA).

app = fig.UserData.app;
pages = app.pages;
n = size(pages, 1);
target = app.current_page + delta;
while target >= 1 && target <= n && ~pages{target, 3}
    target = target + delta;
end
if target < 1 || target > n
    return;  % at the boundary; no-op
end
% Skip the events page when the selected analysis does not support events.
if strcmp(pages{target, 1}, 'p4_events') && ~wizard_events_applicable(app)
    target = target + delta;
    if target < 1 || target > n, return; end
end
app.current_page = target;
fig.UserData.app = app;
wizard.render_page(app);
end

function tf = wizard_events_applicable(app)
tf = false;
if ~isempty(app.analysis)
    reg = app.registry;
    idx = find(strcmp({reg.id}, app.analysis), 1);
    if ~isempty(idx), tf = reg(idx).events_applicable; end
end
end
