function render_page(app)
%RENDER_PAGE  Render the current wizard page into the figure.
%   wizard.render_page(app) clears the content panel of app.fig and renders
%   the page builder for app.current_page.
%
%   Page builders live in +wizard/+pages/* (nested package, correction #1).
%   Each builder is a function(app, panel) that populates the given panel
%   with base-MATLAB uipanel/uicontrol controls (three-column Label /
%   Control / Unit-or-source layout, polished styling).
%
%   This dispatcher selects the builder by page index. Unknown page indices
%   fail closed.

pages = app.pages;
idx = app.current_page;
if idx < 1 || idx > size(pages, 1)
    error('wizard:render_page:badPage', 'Bad page index %d.', idx);
end
builder_name = pages{idx, 1};

% Get or create the content panel.
panel = wizard_content_panel(app);
% Clear existing children of the content panel.
delete(findobj(panel, 'Type', 'uipanel'));
delete(findobj(panel, 'Type', 'uicontrol'));
delete(findobj(panel, 'Type', 'uitable'));

% Header label.
wizard_render_header(app, panel, pages{idx, 2});

% Dispatch to the page builder (nested package +wizard/+pages/<name>).
content = uipanel('Parent', panel, 'Units', 'normalized', ...
    'Position', [0.02 0.02 0.96 0.86], 'BorderType', 'none');
fn = str2func(['wizard.pages.' builder_name]);
fn(app, content);

% Footer navigation (Back / Next / Run / Cancel).
wizard_render_footer(app, panel);
end

function panel = wizard_content_panel(app)
% Reuse the single content panel stored on the figure.
panel = findobj(app.fig, 'Tag', 'wizard_content');
if isempty(panel)
    panel = uipanel('Parent', app.fig, 'Tag', 'wizard_content', ...
        'Units', 'normalized', 'Position', [0.02 0.02 0.96 0.96], ...
        'BorderType', 'none');
end
end

function wizard_render_header(app, panel, title)
% Header: step indicator (left) + page title.
% Method accent color.
accent = app.accent;
% Step indicator: row of dots for each page, current highlighted.
n_pages = size(app.pages, 1);
hdr = uipanel('Parent', panel, 'Units', 'normalized', ...
    'Position', [0 0.92 1 0.08], 'BorderType', 'none');
x0 = 0.02; w = 0.06; gap = 0.015;
for k = 1:n_pages
    x = x0 + (k-1) * (w + gap);
    if k == app.current_page
        c = accent;
    else
        c = [0.8 0.8 0.8];
    end
    uicontrol('Parent', hdr, 'Style', 'text', 'String', sprintf('%d', k), ...
        'Units', 'normalized', 'Position', [x 0.2 w 0.6], ...
        'BackgroundColor', c, 'ForegroundColor', [1 1 1], ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end
uicontrol('Parent', hdr, 'Style', 'text', 'String', title, ...
    'Units', 'normalized', 'Position', [0.45 0.2 0.5 0.6], ...
    'HorizontalAlignment', 'left', 'FontWeight', 'bold', 'FontSize', 12);
end

function wizard_render_footer(app, panel)
% Footer: Back / Next / Run / Cancel (fixed footer, user decision).
ftr = uipanel('Parent', panel, 'Units', 'normalized', ...
    'Position', [0 0 1 0.06], 'BorderType', 'none');
n_pages = size(app.pages, 1);
% Back
uicontrol('Parent', ftr, 'Style', 'pushbutton', 'String', '< Back', ...
    'Units', 'normalized', 'Position', [0.02 0.15 0.12 0.7], ...
    'Callback', @(~,~) wizard.go_page(app.fig, -1), ...
    'Enable', string(app.current_page > 1));
% Next
uicontrol('Parent', ftr, 'Style', 'pushbutton', 'String', 'Next >', ...
    'Units', 'normalized', 'Position', [0.16 0.15 0.12 0.7], ...
    'Callback', @(~,~) wizard.go_page(app.fig, +1), ...
    'Enable', string(app.current_page < n_pages));
% Run
uicontrol('Parent', ftr, 'Style', 'pushbutton', 'String', 'Run', ...
    'Units', 'normalized', 'Position', [0.62 0.15 0.12 0.7], ...
    'FontWeight', 'bold', 'Callback', @(~,~) wizard.run_from_ui(app.fig));
% Cancel
uicontrol('Parent', ftr, 'Style', 'pushbutton', 'String', 'Cancel', ...
    'Units', 'normalized', 'Position', [0.76 0.15 0.12 0.7], ...
    'Callback', @(~,~) wizard.cancel(app.fig));
end
