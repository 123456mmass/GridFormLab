function result = show(varargin)
%SHOW  Open the analysis wizard (base-MATLAB UI controller).
%   result = wizard.show() opens the full analysis wizard with no
%   pre-populated selections.
%   result = wizard.show('analysis',ID,'case',ID,'options',OPT) opens the
%   wizard with the supplied analysis/case/options pre-populated (partial
%   invocation contract, correction #3: NEVER auto-executes).
%
%   The wizard collects the remaining selections and, on Run, calls
%   wizard.dispatch_analysis (the SAME dispatcher used by the programmatic
%   path in solve_case, G4).
%
%   This is the wizard controller. It is THIN: page rendering lives in
%   +wizard/+pages/* and result rendering in +wizard/+render/* (nested
%   packages, correction #1). The controller wires callbacks and routes to
%   the pure functions (build_request / validate_request / dispatch_analysis
%   / adapt_result).
%
%   HEADLESS NOTE: in a non-interactive (batch) MATLAB session, opening the
%   wizard figure raises MATLAB:hg:NonInteractiveFunctionSupport, matching
%   the frozen partial-invocation contract (characterization gate). The
%   programmatic path (solve_case with both analysis and case given) bypasses
%   the UI entirely.

p = inputParser;
addParameter(p, 'analysis', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'case', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'options', struct(), @isstruct);
parse(p, varargin{:});
analysis = lower(char(p.Results.analysis));
case_id = lower(char(p.Results.case));
user_opt = p.Results.options;

% Build the wizard application state.
app = wizard_init_state(analysis, case_id, user_opt);

% Create the base-MATLAB figure and render the current page.
fig = wizard.create_figure(app);
app.fig = fig;
fig.UserData.app = app;

% Render the initial page (Page 1 unless both analysis+case given, in which
% case jump to the review/configure page). Partial invocation never
% auto-executes: even with both given, the user must click Run.
if ~isempty(analysis) && ~isempty(case_id)
    app.current_page = 5;  % review page
else
    app.current_page = 1;  % analysis selection
end
wizard.render_page(app);

% Wait for the user to interact (modal-style) or return the figure handle.
% In batch mode, the figure creation above raises NonInteractiveFunctionSupport
% before reaching here, satisfying the partial-invocation contract.
uiwait(fig);

% After the wizard closes, return the last result (if any).
result = app.last_result;
if isempty(result), result = []; end
end

function app = wizard_init_state(analysis, case_id, user_opt)
app = struct();
app.analysis = analysis;
app.case_id = case_id;
app.user_options = user_opt;
app.events = [];
app.events_policy = 'event_free';
app.current_page = 1;
app.validated_request = struct();
app.last_result = [];
app.fig = [];
app.registry = wizard.analysis_registry();
app.cases = struct();
app.pages = wizard_page_list();
app.accent = [0.20 0.45 0.75];  % default; overridden by analysis
end

function pages = wizard_page_list()
pages = { ...
    'p1_analysis', 'Select analysis', true; ...
    'p2_case', 'Select case', true; ...
    'p3_configure', 'Configure analysis', true; ...
    'p4_events', 'Events', true; ...   % dynamically skipped for PF/SSSA
    'p5_review', 'Review and execute', true; ...
    'p6_results', 'Results', true};
end
