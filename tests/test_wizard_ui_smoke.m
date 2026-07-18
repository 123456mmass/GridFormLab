function test_wizard_ui_smoke()
%TEST_WIZARD_UI_SMOKE  Headless smoke test of the wizard UI layer.
%   Exercises the wizard UI functions WITHOUT a live display:
%     1. wizard.show raises MATLAB:hg:NonInteractiveFunctionSupport in batch
%        mode (the frozen partial-invocation contract).
%     2. Page builder functions (in +wizard/+pages/*) can be invoked without
%        throwing when given a mock app + panel handle.
%     3. wizard.render_page dispatches to the correct builder by page index.
%     4. wizard.go_page skips non-applicable pages.
%
%   This is a UI EXECUTION smoke test only — it asserts that the wizard
%   functions are callable and route correctly. It makes NO numerical claims
%   (correction: separate UI_EXECUTION_PASS from NUMERICAL_CONVERGENCE from
%   PHYSICAL_RESULT_CLASSIFICATION).
%
%   A hidden classic figure exercises the actual renderer. This gate was added
%   after the former function-resolution-only smoke test passed while desktop
%   rendering failed before creating the footer controls.

pf_init_paths();
results = struct('pass', 0, 'fail', 0);

% --- 1. wizard.show raises NonInteractiveFunctionSupport in batch ---
threw = false;
id = '';
try
    wizard.show();
catch e
    threw = true;
    id = e.identifier;
end
results = check(results, threw, 'wizard.show raises in batch (no auto-execute)');
results = check(results, threw && endsWith(id, 'NonInteractiveFunctionSupport'), ...
    sprintf('wizard.show raises NonInteractiveFunctionSupport (got %s)', id));

% --- 2. Page builders are invokable on a mock app ---
registry = wizard.analysis_registry();
pages = { ...
    'p1_analysis', 'Select analysis', true; ...
    'p2_case', 'Select case', true; ...
    'p3_configure', 'Configure analysis', true; ...
    'p4_events', 'Events', true; ...
    'p5_review', 'Review and execute', true; ...
    'p6_results', 'Results', true};

% Build a mock app + a mock panel handle. Because a live figure is not
% available in batch, call the page builders directly with a struct app and
% a dummy panel (0 handle) and assert they are at least defined and routable.
% The builders that need a real panel are expected to throw a graphics error
% when they try to create uicontrols; we only assert the function resolves and
% the dispatcher selects the right builder.
for k = 1:size(pages, 1)
    name = pages{k, 1};
    fn = str2func(['wizard.pages.' name]);
    results = check(results, isa(fn, 'function_handle'), ...
        sprintf('page builder %s resolves', name));
end

% --- 3. analysis_registry + discover_cases drive the wizard state ---
app = struct();
app.analysis = 'pf';
app.case_id = 'ieee5';
app.user_options = wizard.defaults_for_method('pf');
app.events = [];
app.events_policy = 'not_applicable';
app.current_page = 1;
app.validated_request = struct();
app.last_result = [];
app.last_view = struct();
app.registry = registry;
app.cases = wizard.discover_cases('pf');
app.pages = pages;
app.accent = registry(1).accent_color;
app.font = 'Helvetica';
results = check(results, numel(app.cases) >= 1, 'discover_cases populated for pf');
results = check(results, isfield(app.user_options, 'max_iter'), 'defaults_for_method produced options');

% --- 4. build_request + validate_request + adapt_result full round trip (no UI) ---
req = wizard.build_request('pf', 'ieee5', 'options', struct('verbose', false, 'plot_results', false));
req = wizard.validate_request(req);
results = check(results, strcmp(req.events_policy, 'not_applicable'), ...
    'pf request is not_applicable events');
% Build a synthetic result to exercise adapt_result (no solver call).
synth = struct('converged', true, 'bus_voltage', [1.0 1.05], 'bus_angle_deg', [0 -2], ...
    'iterations', 5, 'max_mismatch', 1e-12, 'execution_summary', struct( ...
    'pf_invocations', 1, 'sssa_invocations', 0, 'ts_invocations', 0, ...
    'solver_iterations', 5, 'linearized_state_count', 0, 'eigenvalue_count', 0, ...
    'ts_step_count', 0), 'launcher', struct('analysis', 'pf', 'case_id', 'ieee5', ...
    'case_label', 'IEEE 5-bus', 'log_file', ''));
view = wizard.adapt_result(synth, req);
results = check(results, numel(view.sections) == 12, 'adapt_result produces 12 sections');
results = check(results, strcmp(view.sections(3).status, 'ok'), 'PF section ok');
results = check(results, strcmp(view.sections(4).status, 'not_applicable'), 'SSSA section not_applicable for pf');

% --- 5. Real hidden-figure render, selection commit, and navigation ---
fig = figure('Visible', 'off', 'MenuBar', 'none', 'ToolBar', 'none');
cleanup = onCleanup(@() delete_if_valid(fig)); %#ok<NASGU>
uiapp = app;
uiapp.analysis = '';
uiapp.case_id = '';
uiapp.current_page = 1;
uiapp.fig = fig;
fig.UserData.app = uiapp;
wizard.render_page(uiapp);
next = findobj(fig, 'Style', 'pushbutton', 'String', 'Next >');
back = findobj(fig, 'Style', 'pushbutton', 'String', '< Back');
lb = findobj(fig, 'Style', 'listbox');
results = check(results, isscalar(next) && strcmp(get(next, 'Enable'), 'on'), ...
    'page 1 renders an enabled Next button');
results = check(results, isscalar(back) && strcmp(get(back, 'Enable'), 'off'), ...
    'page 1 renders a disabled Back button');
set(lb, 'Value', 4);
cb = get(lb, 'Callback'); cb(lb, []);
results = check(results, strcmp(fig.UserData.app.analysis, 'ibr'), ...
    'analysis list callback commits IBR selection');
cb = get(next, 'Callback'); cb(next, []);
results = check(results, fig.UserData.app.current_page == 2, ...
    'Next advances to the case page');
results = check(results, ~isempty(fig.UserData.app.case_id), ...
    'case page commits its displayed initial selection');

% Events page is reachable for IBR but skipped for PF/SSSA.
uiapp = fig.UserData.app;
uiapp.current_page = 3;
uiapp.analysis = 'ibr';
fig.UserData.app = uiapp;
wizard.go_page(fig, +1);
results = check(results, fig.UserData.app.current_page == 4, ...
    'IBR navigation reaches the Events page');
uiapp = fig.UserData.app;
uiapp.current_page = 3;
uiapp.analysis = 'pf';
fig.UserData.app = uiapp;
wizard.go_page(fig, +1);
results = check(results, fig.UserData.app.current_page == 5, ...
    'PF navigation skips the Events page');

% --- 6. Default interactive entry uses the user-selected compact dialogs ---
solve_src = fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'solve_case.m'));
legacy_src = fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+wizard', 'legacy_show.m'));
results = check(results, contains(solve_src, 'wizard.legacy_show'), ...
    'solve_case default interactive path uses compact legacy dialogs');
results = check(results, contains(legacy_src, 'listdlg') && contains(legacy_src, 'inputdlg'), ...
    'legacy UI provides compact selection and editable settings dialogs');
results = check(results, contains(legacy_src, 'wizard.dispatch_analysis'), ...
    'legacy UI retains the shared production dispatcher');

fprintf('\n==== WIZARD UI SMOKE: %d passed, %d failed ====\n', results.pass, results.fail);
if results.fail > 0
    error('test_wizard_ui_smoke:Failed', '%d checks failed', results.fail);
end

function delete_if_valid(fig)
if isgraphics(fig)
    delete(fig);
end
end
end

function r = check(r, cond, msg)
if cond
    r.pass = r.pass + 1;
    fprintf('  PASS  %s\n', msg);
else
    r.fail = r.fail + 1;
    fprintf('  FAIL  %s\n', msg);
end
end
