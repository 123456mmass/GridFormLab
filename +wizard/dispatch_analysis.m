function result = dispatch_analysis(req)
%DISPATCH_ANALYSIS  Single shared dispatcher: validated request -> launcher.
%   result = wizard.dispatch_analysis(req) runs the production launcher for
%   the analysis specified in the validated request req. This is the ONE
%   dispatcher used by BOTH the wizard UI and the programmatic path (G4,
%   correction: "Wizard must call the same pure dispatcher as programmatic
%   path"). No duplicate dispatch exists anywhere.
%
%   dispatch_analysis calls the EXISTING production launchers verbatim:
%     pf   -> pfsolver.pf_resolve_method + pfsolver.pf_method_strategy(...).solve
%     sssa -> stability.multicase_sssa
%     ts   -> stability.ts_simulate
%     ibr  -> cases.scenario_ieee14_1sg_4ibr -> stability.ibr_configure_scenario
%             -> stability.run_hybrid_case
%
%   It does NOT introduce new solvers, new equations, or new event semantics.
%   events_policy='event_free' reaches the production runtime as an ACTUALLY
%   empty schedule (correction #6): for IBR, ibr_events.enabled=false is passed
%   through so run_hybrid_case produces the slim empty-schedule result; for TS,
%   the events struct is left empty so ts_simulate runs event-free.
%
%   The result schema, launcher sub-struct, execution_summary, and failure
%   IDs are produced by the production launchers and are NOT mutated here.
%   An additive launcher annotation (analysis/case_id/case_label/log_file)
%   is attached to mirror solve_case.m's existing result.launcher contract.
%
%   See also: wizard.BUILD_REQUEST, wizard.VALIDATE_REQUEST, wizard.ADAPT_RESULT.

req = wizard.validate_request(req);
analysis = req.analysis;
case_id = req.case_id;
opt = req.options;

% Locate the case entry (lazy; no solved-state load).
entries = wizard.discover_cases(analysis);
idx = find(strcmp(case_id, {entries.id}), 1);
if isempty(idx)
    error('wizard:dispatch_analysis:unknownCase', ...
        'Case %s not supported for %s.', case_id, analysis);
end
entry = entries(idx);
case_data = entry.loader();

% Attach the event spec to options for the TS/IBR launchers that consume it.
opt = attach_events(opt, req, analysis);

root = pf_init_paths();
logdir = fullfile(root, 'output', 'logs');
if ~exist(logdir, 'dir'), mkdir(logdir); end
stamp = datestr(now, 'yyyymmdd_HHMMSS');
logfile = fullfile(logdir, sprintf('%s_%s_%s.log', stamp, analysis, case_id));
diary(logfile);
diary_cleanup = onCleanup(@() diary('off')); %#ok<NASGU>

print_launcher_header(analysis, entry.label, logfile, case_data);
print_run_options(opt);

switch analysis
    case 'pf'
        [pf_method_name, pf_selection_source] = pfsolver.pf_resolve_method(opt);
        pf_strat = pfsolver.pf_method_strategy(pf_method_name);
        result = pf_strat.solve(case_data, opt);
        result = enrich_pf_metadata(result, pf_method_name, ...
            pf_selection_source, pf_strat);
    case 'sssa'
        result = stability.multicase_sssa(case_data, opt);
        result = annotate_sssa_result(result, opt);
    case 'ts'
        result = stability.ts_simulate(case_data, opt);
        if ~isfield(opt, 'plot_results') || opt.plot_results
            [fig, png] = plot_ts_result(result, entry.label, root, case_id);
            result.figure = fig; result.figure_file = png;
        end
    case 'ibr'
        result = run_ibr_analysis(case_data, opt, entry.label, root, case_id);
    otherwise
        error('wizard:dispatch_analysis:unknownAnalysis', ...
            'Unknown analysis ID %s.', analysis);
end

result = annotate_launcher_execution(analysis, result);
result.launcher = struct('analysis', analysis, 'case_id', case_id, ...
    'case_label', entry.label, 'log_file', logfile);

run_ok = ~isfield(result, 'converged') || logical(result.converged);
if run_ok
    fprintf('\nSTATUS: COMPLETE\n');
else
    fprintf('\nSTATUS: FAILED CLOSED\n');
end
fprintf('Saved log: %s\n', logfile);
diary('off');

% UI explanation path is handled by the wizard controller; do not block here.
% (solve_case.m opens a modal msgbox only in interactive mode; the wizard
%  shows results in-page instead.)
end

% =========================================================================
function opt = attach_events(opt, req, analysis)
% Pass the event spec through to the launcher's option ABI. For PF/SSSA,
% events are NOT_APPLICABLE and nothing is attached. For TS, the events
% struct flows into the ts_simulate option contract. For IBR, the nested
% ibr_events struct flows into run_hybrid_case.
registry = wizard.analysis_registry();
aidx = find(strcmp(analysis, {registry.id}), 1);
if ~registry(aidx).events_applicable, return; end
ev = req.events;
switch analysis
    case 'ts'
        if ~isempty(ev) && isfield(ev, 'enabled') && logical(ev.enabled)
            % Map the wizard event struct onto the TS option fields consumed
            % by ts_simulate (fault_bus, t_fault, t_clear, Zf). The wizard
            % event struct uses ibr-style names; the TS launcher uses
            % t_fault/t_clear. This mapping is a pure option translation,
            % not a new event semantic.
            opt.fault_bus = ev.fault_bus;
            opt.t_fault = ev.fault_on;
            opt.t_clear = ev.fault_clear;
            opt.Zf = ev.Zf;
        else
            % event_free: leave TS event fields absent/empty so ts_simulate
            % runs event-free (no fault applied).
        end
    case 'ibr'
        if ~isempty(ev)
            opt.ibr_events = ev;
        else
            % event_free for IBR: an explicit disabled struct reaches the
            % runtime as an empty schedule (correction #6).
            opt.ibr_events = struct('enabled', false);
        end
end
end

function result = enrich_pf_metadata(result, pf_method_name, pf_selection_source, pf_strat)
if ~isfield(result, 'metadata'), result.metadata = struct(); end
if ~isfield(result.metadata, 'method_executed')
    result.metadata.method_requested = pf_method_name;
    result.metadata.method_executed = pf_method_name;
    result.metadata.dispatch_requested = pf_method_name;
    result.metadata.method_source = pf_strat.method_source;
    result.metadata.selection_source = pf_selection_source;
    result.metadata.capability = pf_strat.capability;
    result.metadata.fallback_used = false;
    if isfield(result, 'max_mismatch')
        result.metadata.full_ac_mismatch = result.max_mismatch;
    end
else
    if ~isfield(result.metadata, 'dispatch_requested')
        result.metadata.dispatch_requested = pf_method_name;
    end
    if ~isfield(result.metadata, 'selection_source')
        result.metadata.selection_source = pf_selection_source;
    end
end
end

function result = run_ibr_analysis(case_data, opt, label, root, case_id)
scenario_opt = struct();
if isfield(opt, 'ibr_dispatch') && ~isempty(opt.ibr_dispatch)
    scenario_opt.dispatch = opt.ibr_dispatch;
end
base = cases.scenario_ieee14_1sg_4ibr(scenario_opt);
[scenario, selection] = stability.ibr_configure_scenario(base, opt);
if ~selection.ready
    result = struct('converged', false, 'metadata', struct( ...
        'failure', 'solve_case:ibr:initialSelection', ...
        'error', selection.failure_reason), 'selector_log', selection, ...
        'execution_summary', selection_failure_summary(selection));
    fprintf('\nIBR initial configuration rejected (no fallback).\n');
    stability.print_ibr_run_log(result);
    return;
end

if ~isfield(opt, 'ibr_events') || ~isstruct(opt.ibr_events)
    opt.ibr_events = event_struct_from_flat(opt);
end
result = stability.run_hybrid_case(scenario, opt);
result.selector_log = selection;
if isfield(result, 'execution_summary')
    result.execution_summary.selector_candidate_evaluations = selection.candidate_count;
    result.execution_summary.sssa_invocations = selection.sssa_evaluations;
end
stability.print_ibr_run_log(result);

plot_requested = ~isfield(opt, 'plot_results') || opt.plot_results;
plot_payload = all(isfield(result, {'t','bus_ids','device_ids', ...
    'device_frequency_Hz','device_bus_ids','bus_voltage_magnitude', ...
    'device_P_MW','device_Q_MVAr','device_current_magnitude', ...
    'device_current_limit_sys','sched'}));
if plot_requested && plot_payload && ~isempty(result.t)
    p = stability.plot_ibr_ts_results(result, struct( ...
        'output_dir', fullfile(root, 'output', 'plots'), ...
        'visible', logical(option_value(opt, 'plot_visible', false)), ...
        'prefix', case_id));
    result.figure_files = {p.freq_plot, p.power_plot};
    if result.converged
        plot_status = 'complete';
    else
        plot_status = 'PARTIAL / FAILED CLOSED';
    end
    fprintf('IBR plots (%s; %s):\n  %s\n  %s\n', ...
        label, plot_status, p.freq_plot, p.power_plot);
end
end

function summary = selection_failure_summary(selection)
summary = struct( ...
    'pf_stage_invocations', 3*selection.equilibrium_evaluations, ...
    'pf_stage_names', {{'selector_candidate_device/equilibrium/sssa_warm_starts'}}, ...
    'equilibrium_invocations', selection.equilibrium_evaluations, ...
    'equilibrium_newton_iterations', 0, ...
    'sssa_invocations', selection.sssa_evaluations, ...
    'selector_candidate_evaluations', selection.candidate_count, ...
    'ts_invocations', 0, 'ts_step_attempts', 0, 'ts_accepted_steps', 0, ...
    'ts_newton_iterations', 0, 'event_transactions', 0);
end

function ev = event_struct_from_flat(opt)
required = {'events_enabled','fault_bus','Zf','fault_on','fault_clear', ...
    'sg_trip','sg_on','post_trip_gfm_indices','post_trip_reference_resource_index'};
for k = 1:numel(required)
    if ~isfield(opt, required{k})
        error('wizard:dispatch_analysis:ibr:eventOptions', ...
            'Missing options.%s.', required{k});
    end
end
ev = struct('enabled', logical(opt.events_enabled), 'fault_bus', opt.fault_bus, ...
    'Zf', opt.Zf, 'fault_on', opt.fault_on, 'fault_clear', opt.fault_clear, ...
    'sg_trip', opt.sg_trip, 'sg_on', opt.sg_on, ...
    'selected_gfm_indices', opt.post_trip_gfm_indices, ...
    'reference_resource_index', opt.post_trip_reference_resource_index);
end

function result = annotate_launcher_execution(analysis, result)
if isfield(result, 'execution_summary'), return; end
summary = struct('pf_invocations', 0, 'sssa_invocations', 0, 'ts_invocations', 0, ...
    'solver_iterations', 0, 'linearized_state_count', 0, 'eigenvalue_count', 0, ...
    'ts_step_count', 0);
switch analysis
    case 'pf'
        summary.pf_invocations = 1;
        if isfield(result, 'iterations'), summary.solver_iterations = result.iterations; end
    case 'sssa'
        summary.sssa_invocations = 1;
        if isfield(result, 'newton_iterations'), summary.solver_iterations = result.newton_iterations; end
        if isfield(result, 'Afull'), summary.linearized_state_count = size(result.Afull, 1); end
        if isfield(result, 'eigenvalues'), summary.eigenvalue_count = numel(result.eigenvalues); end
    case 'ts'
        summary.ts_invocations = 1;
        if isfield(result, 'accepted_steps'), summary.ts_step_count = result.accepted_steps;
        elseif isfield(result, 't'), summary.ts_step_count = max(0, numel(result.t)-1); end
end
result.execution_summary = summary;
end

function result = annotate_sssa_result(result, opt)
if ~isfield(result, 'state_names') || isempty(result.state_names)
    result.state_names = arrayfun(@(k) sprintf('x%d', k), 1:size(result.Afull,1), ...
        'UniformOutput', false).';
else
    result.state_names = result.state_names(:);
end
if isfield(result, 'reduced_eigenvalues'), lam = result.reduced_eigenvalues(:);
else, lam = result.eigenvalues(:); end
tol = 1e-7;
if isfield(opt, 'stability_tolerance'), tol = opt.stability_tolerance; end
nu = sum(real(lam) > tol); ns = sum(real(lam) < -tol); nm = numel(lam) - nu - ns;
if isempty(lam), status = 'NOT APPLICABLE - NO RELATIVE MODES';
elseif nu > 0, status = 'UNSTABLE';
elseif nm > 0, status = 'MARGINAL';
else, status = 'ASYMPTOTICALLY STABLE'; end
result.stability_status = status;
result.stability_tolerance = tol;
result.root_counts = struct('stable', ns, 'marginal', nm, 'unstable', nu);
end

function print_launcher_header(analysis, case_label, logfile, case_data)
fprintf('\n============================================================\n');
fprintf('IN-HOUSE ANALYSIS LAUNCHER\n');
fprintf('Analysis : %s\n', upper(analysis));
fprintf('Case     : %s\n', case_label);
fprintf('Time     : %s\n', datestr(now, 31));
fprintf('Log      : %s\n', logfile);
fprintf('Engine   : project MATLAB code only (no external solver)\n');
fprintf('============================================================\n');
if isfield(case_data, 'schema_version')
    fprintf('Schema   : %s\n', case_data.schema_version);
end
if isfield(case_data, 'base_values')
    fprintf('Base     : %.6g MVA, %.6g Hz\n', ...
        case_data.base_values.S_base_MVA, case_data.base_values.frequency_Hz);
end
if isfield(case_data, 'bus_data')
    fprintf('Network  : %d buses, %d branches\n', ...
        size(case_data.bus_data, 1), size(case_data.line_data, 1));
end
end

function print_run_options(opt)
fprintf('\n---------------- RUN SETTINGS -------------------\n');
names = fieldnames(opt);
for k = 1:numel(names)
    name = names{k}; value = opt.(name);
    if islogical(value) && isscalar(value), text = mat2str(value);
    elseif isnumeric(value) && isscalar(value)
        if isreal(value), text = sprintf('%.12g', value);
        else, text = sprintf('%.12g %+.12gj', real(value), imag(value)); end
    elseif ischar(value) || (isstring(value) && isscalar(value)), text = char(value);
    elseif isempty(value), text = '[]';
    else, text = sprintf('<%s %s>', class(value), mat2str(size(value))); end
    fprintf('%-20s: %s\n', name, text);
end
end

function value = option_value(s, name, default)
value = default;
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); end
end
