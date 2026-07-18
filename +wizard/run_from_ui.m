function run_from_ui(fig)
%RUN_FROM_UI  Build, validate, and dispatch the request from the wizard UI.
%   wizard.run_from_ui(fig) reads the current wizard selections, builds a
%   request via wizard.build_request, validates it, and dispatches it via
%   wizard.dispatch_analysis (the SAME dispatcher used by the programmatic
%   path, G4). The result is adapted into the 12-section view model and the
%   wizard advances to the results page.
%
%   Inline validation messages are shown on failure rather than repeated modal
%   dialogs (user decision). Errors from dispatch propagate to the results
%   page as a failed-closed status, not as a modal popup.

app = fig.UserData.app;
analysis = app.analysis;
case_id = app.case_id;
if isempty(analysis) || isempty(case_id)
    wizard_show_inline(fig, 'Select an analysis and a case before running.');
    return;
end

% Build the request from the wizard state.
opts = app.user_options;
ev = app.events;
req = wizard.build_request(analysis, case_id, 'options', opts);
if ~isempty(ev) && isstruct(ev)
    req = wizard.build_request(analysis, case_id, 'options', opts, 'events', ev, ...
        'interactive', true);
else
    req = wizard.build_request(analysis, case_id, 'options', opts, ...
        'interactive', true);
end

try
    req = wizard.validate_request(req);
catch e
    wizard_show_inline(fig, sprintf('Validation: %s', e.message));
    return;
end
app.validated_request = req;
fig.UserData.app = app;

% Dispatch (single shared dispatcher). Separate execution from convergence
% from physical-stability classification (correction #6).
try
    result = wizard.dispatch_analysis(req);
catch e
    result = struct('converged', false, 'failure_id', e.identifier, ...
        'failure_reason', e.message);
end
app.last_result = result;
app.last_view = wizard.adapt_result(result, req);

% Advance to the results page.
pages = app.pages;
app.current_page = find(strcmp({pages{:,1}}, 'p6_results'), 1);
if isempty(app.current_page), app.current_page = size(pages,1); end
fig.UserData.app = app;
wizard.render_page(app);
end

function wizard_show_inline(fig, msg)
% Inline validation: write to a status text control rather than a modal dialog.
panel = findobj(fig, 'Tag', 'wizard_content');
if isempty(panel), return; end
% Reuse or create a status line at the bottom of the content panel.
status = findobj(panel, 'Tag', 'wizard_inline_status');
if isempty(status)
    status = uicontrol('Parent', panel, 'Style', 'text', 'Tag', 'wizard_inline_status', ...
        'Units', 'normalized', 'Position', [0.02 0.005 0.96 0.04], ...
        'ForegroundColor', [0.7 0.1 0.1], 'HorizontalAlignment', 'center', ...
        'FontWeight', 'bold');
end
set(status, 'String', msg);
drawnow;
end
