function fig = create_figure(app)
%CREATE_FIGURE  Create the base-MATLAB wizard figure.
%   fig = wizard.create_figure(app) creates a classic figure (NOT uifigure,
%   per the user decision: base-MATLAB throughout, do not mix) with the
%   polished wizard appearance: fixed centered responsive window, light
%   neutral background, Sarabun/Segoe UI fonts with fallback.
%
%   The figure is created with the analysis accent color when known.

% HEADLESS: in a non-interactive (batch) MATLAB session, this raises
% MATLAB:hg:NonInteractiveFunctionSupport — matching the frozen partial-
% invocation contract (the old listdlg-based launcher raised the same ID).
% The programmatic path bypasses the UI entirely and never calls this.
if ~usejava('desktop') || ~feature('ShowFigureWindows')
    error('MATLAB:hg:NonInteractiveFunctionSupport', ...
        'Creating dialog boxes that block execution is not supported when MATLAB is in a configuration that is non-interactive or disables window display.');
end

accent = app.accent;
% Font fallback: Sarabun (Thai-friendly) -> Segoe UI (Windows default) -> default.
font = wizard_font();

fig = figure('Name', 'Analysis Wizard', ...
    'NumberTitle', 'off', ...
    'MenuBar', 'none', 'ToolBar', 'none', ...
    'Units', 'pixels', 'Position', [100 100 900 600], ...
    'Color', [0.95 0.95 0.97], ...
    'Resize', 'on', ...
    'CloseRequestFcn', @(src, ~) wizard.close_request(src), ...
    'WindowStyle', 'normal', ...
    'Color', [0.95 0.95 0.97]);
set(fig, 'Color', [0.95 0.95 0.97]);
movegui(fig, 'center');
set(fig, 'DefaultUicontrolFontName', font, ...
    'DefaultUicontrolFontSize', 10, ...
    'DefaultUipanelFontName', font, ...
    'DefaultUipanelFontSize', 10);

% Apply font + accent asUserData-backed defaults via app.
app.accent = accent;
app.font = font;
fig.UserData.app = app;
end

function f = wizard_font()
% Sarabun if available, else Segoe UI (Windows), else default.
candidates = {'Sarabun', 'Segoe UI', 'Helvetica'};
f = 'Helvetica';
for k = 1:numel(candidates)
    try
        % listfonts is available in base MATLAB.
        if ismember(candidates{k}, listfonts())
            f = candidates{k};
            return;
        end
    catch
        % fall through
    end
end
end
