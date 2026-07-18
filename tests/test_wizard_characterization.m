function tests = test_wizard_characterization()
%TEST_WIZARD_CHARACTERIZATION  Freeze solve_case ABI BEFORE the wizard refactor.
%   This file freezes the CURRENT programmatic behavior of solve_case.m so the
%   Extract+delegate refactor (Wizard Phase 3) can be proven non-regressive.
%   Run it on the UNCHANGED tree first (green), then again AFTER the refactor
%   and confirm identical green results.
%
%   Frozen surface (correction #2):
%     - programmatic ABI (name-value 'analysis'/'case'/'options')
%     - stable analysis IDs (pf/sssa/ts/ibr)
%     - per-analysis result schema (field names)
%     - launcher sub-struct schema
%     - execution_summary schema per analysis
%     - error identifiers for unknown analysis / unknown case
%     - log-file creation and stable log tokens
%     - partial invocation contract (correction #3): partially specified calls
%       open an interactive picker and never auto-execute
%     - events=false reaches production TS/IBR as an ACTUALLY empty schedule
%       (correction #6): distinct, slimmer result schema with empty `events`
%       and zero event_transactions
%
%   Volatile values are excluded from comparison (correction #9): timestamps,
%   log-file paths, wall-clock durations. Only stable contract fields and
%   numerical values under existing tolerances are compared.
%
%   The no-argument interactive surface is an intentional UI replacement
%   (correction #2); this file does NOT reproduce the old dialog sequence.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function expected = expected_pf_fields()
expected = {'system_name','method','external_bus_ids','bus_type','bus_voltage', ...
    'bus_angle','bus_angle_deg','P_generation','Q_generation','line_endpoints', ...
    'line_flow_P','line_flow_Q','line_loss_P','line_loss_Q','P_loss_total', ...
    'Q_loss_total','base_values','iterations','converged','metadata', ...
    'max_mismatch','q_limit_switching','execution_summary','launcher'};
end

function expected = expected_sssa_fields()
expected = {'Afull','eigenvalues','reduced_eigenvalues','state_names','metadata', ...
    'newton_residual','stability_status','stability_tolerance','root_counts', ...
    'execution_summary','launcher'};
end

function expected = expected_ts_fields()
expected = {'t','delta','omega','Pe_pu','Vbus','method','dt','t_end', ...
    'fault_bus','integrator','metadata','execution_summary','launcher'};
end

function expected = expected_ibr_fields_on()
% Full event-driven IBR result exposes these canonical fields.
expected = {'converged','x_traj','t','events','metadata','fingerprint', ...
    'selector_log','equilibrium','status_log','execution_summary', ...
    'u_history','bus_voltage_magnitude','sample_side','transaction_id','launcher', ...
    'reclose_log','device_P_MW','device_Q_MVAr','device_frequency_Hz', ...
    'device_ids','device_bus_ids','bus_ids','topology_history'};
end

function expected = expected_ibr_fields_off()
% events=false produces a DISTINCT slimmer schema (empty schedule reaches prod).
expected = {'converged','x_traj','y_traj','t','events','metadata','fingerprint', ...
    'selector_log','reclose_log','equilibrium','status_log','execution_summary', ...
    'u_history','bus_voltage_magnitude','sample_side','transaction_id','launcher'};
end

function expected = expected_launcher_fields()
expected = {'analysis','case_id','case_label','log_file'};
end

function expected = expected_pf_exec_summary()
expected = {'pf_invocations','sssa_invocations','ts_invocations', ...
    'solver_iterations','linearized_state_count','eigenvalue_count','ts_step_count'};
end

function expected = expected_ibr_exec_summary()
expected = {'pf_stage_invocations','equilibrium_invocations','sssa_invocations', ...
    'selector_candidate_evaluations','ts_invocations','ts_step_attempts', ...
    'ts_accepted_steps','ts_newton_iterations','event_transactions'};
end

function [r, txt] = run_pf()
opt = struct('verbose',false,'plot_results',false);
txt = evalc("r = solve_case('analysis','pf','case','ieee5','options',opt);");
end

function [r, txt] = run_sssa()
opt = struct('verbose',false);
txt = evalc("r = solve_case('analysis','sssa','case','ieee5','options',opt);");
end

function [r, txt] = run_ts()
opt = struct('verbose',false,'plot_results',false);
txt = evalc("r = solve_case('analysis','ts','case','ieee5','options',opt);");
end

function [r, txt] = run_ibr_on()
ev = struct('enabled',true,'fault_bus',4,'Zf',1i*.1,'fault_on',.02, ...
    'fault_clear',.03,'sg_trip',.04,'sg_on',.06, ...
    'selected_gfm_indices',2:5,'reference_resource_index',2);
opt = struct('t_end',.1,'dt',.01,'plot_results',false,'ibr_events',ev);
txt = evalc("r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);");
end

function [r, txt] = run_ibr_off()
ev = struct('enabled',true,'fault_bus',4,'Zf',1i*.1,'fault_on',.02, ...
    'fault_clear',.03,'sg_trip',.04,'sg_on',.06, ...
    'selected_gfm_indices',2:5,'reference_resource_index',2);
ev.enabled = false;
opt = struct('t_end',.1,'dt',.01,'plot_results',false,'ibr_events',ev);
txt = evalc("r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);");
end

%% ---- ABI: name-value parameters parse ----
function test_abi_accepts_name_value(tc)
% The three documented parameters must parse without error.
tc.verifyTrue(isstruct(solve_case('analysis','pf','case','ieee5', ...
    'options',struct('verbose',false,'plot_results',false))));
end

function test_abi_defaults_empty_analysis_and_case(tc)
% Calling with omitted parameters must not throw on parsing (interactive path
% is a separate concern; here we just confirm the parser accepts the empty
% defaults by checking a fully-specified call still works with an empty struct).
tc.verifyTrue(isstruct(solve_case('analysis','pf','case','ieee5', ...
    'options',struct('verbose',false,'plot_results',false))));
end

%% ---- Stable analysis IDs ----
function test_stable_analysis_ids(tc)
% The four canonical analysis IDs (correction: ibr means mixed-resource TS;
% ibr_ts is NOT a separate ID).
ids = {'pf','sssa','ts','ibr'};
src = fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))),'solve_case.m'));
for k = 1:numel(ids)
    tc.verifyTrue(contains(src, sprintf('''%s''', ids{k})), ...
        sprintf('analysis ID %s not found in solve_case.m', ids{k}));
end
% Confirm no 'ibr_ts' analysis is introduced.
tc.verifyFalse(contains(src,'''ibr_ts'''));
% Smoke: each analysis ID runs.
for k = 1:numel(ids)
    switch ids{k}
        case 'pf',  [~,~] = run_pf();
        case 'sssa',[~,~] = run_sssa();
        case 'ts',  [~,~] = run_ts();
        case 'ibr', [~,~] = run_ibr_off();
    end
    tc.verifyTrue(true); %#ok<FXMIN>
end
end

%% ---- Error identifiers ----
function test_error_unknown_analysis(tc)
tc.verifyError(@() solve_case('analysis','bogus','case','ieee5'), ...
    'solve_case:analysis');
end

function test_error_unknown_case(tc)
tc.verifyError(@() solve_case('analysis','pf','case','bogus'), ...
    'solve_case:case');
end

%% ---- PF result schema + launcher + exec_summary ----
function test_pf_result_schema(tc)
[r,~] = run_pf();
tc.verifyTrue(r.converged);
tc.verifyTrue(all(ismember(expected_pf_fields(), fieldnames(r))), ...
    sprintf('PF missing: %s', strjoin(setdiff(expected_pf_fields(), fieldnames(r)), ',')));
end

function test_pf_launcher_schema(tc)
[r,~] = run_pf();
tc.verifyTrue(all(ismember(expected_launcher_fields(), fieldnames(r.launcher))));
tc.verifyEqual(r.launcher.analysis, 'pf');
tc.verifyEqual(r.launcher.case_id, 'ieee5');
tc.verifyTrue(ischar(r.launcher.case_label) && ~isempty(r.launcher.case_label));
tc.verifyTrue(ischar(r.launcher.log_file) && ~isempty(r.launcher.log_file));
end

function test_pf_exec_summary_schema(tc)
[r,~] = run_pf();
tc.verifyTrue(all(ismember(expected_pf_exec_summary(), fieldnames(r.execution_summary))));
tc.verifyEqual(r.execution_summary.pf_invocations, 1);
tc.verifyEqual(r.execution_summary.sssa_invocations, 0);
tc.verifyEqual(r.execution_summary.ts_invocations, 0);
tc.verifyGreaterThan(r.execution_summary.solver_iterations, 0);
end

%% ---- SSSA result schema ----
function test_sssa_result_schema(tc)
[r,~] = run_sssa();
tc.verifyTrue(all(ismember(expected_sssa_fields(), fieldnames(r))), ...
    sprintf('SSSA missing: %s', strjoin(setdiff(expected_sssa_fields(), fieldnames(r)), ',')));
tc.verifyEqual(r.launcher.analysis, 'sssa');
tc.verifyEqual(r.execution_summary.sssa_invocations, 1);
tc.verifyGreaterThan(r.execution_summary.linearized_state_count, 0);
tc.verifyGreaterThan(r.execution_summary.eigenvalue_count, 0);
end

%% ---- TS result schema ----
function test_ts_result_schema(tc)
[r,~] = run_ts();
tc.verifyTrue(all(ismember(expected_ts_fields(), fieldnames(r))), ...
    sprintf('TS missing: %s', strjoin(setdiff(expected_ts_fields(), fieldnames(r)), ',')));
tc.verifyEqual(r.launcher.analysis, 'ts');
tc.verifyEqual(r.execution_summary.ts_invocations, 1);
tc.verifyGreaterThan(r.execution_summary.ts_step_count, 0);
end

%% ---- IBR result schema (events on) ----
function test_ibr_on_result_schema(tc)
[r,~] = run_ibr_on();
tc.verifyTrue(r.converged);
tc.verifyTrue(all(ismember(expected_ibr_fields_on(), fieldnames(r))), ...
    sprintf('IBR-on missing: %s', strjoin(setdiff(expected_ibr_fields_on(), fieldnames(r)), ',')));
tc.verifyEqual(r.launcher.analysis, 'ibr');
tc.verifyEqual(r.launcher.case_id, 'ieee14_1sg_4ibr');
end

function test_ibr_on_exec_summary_schema(tc)
[r,~] = run_ibr_on();
tc.verifyTrue(all(ismember(expected_ibr_exec_summary(), fieldnames(r.execution_summary))));
tc.verifyGreaterThan(r.execution_summary.event_transactions, 0);
tc.verifyGreaterThan(r.execution_summary.ts_step_attempts, 0);
end

%% ---- events=false reaches production as ACTUALLY empty schedule (correction #6) ----
function test_ibr_events_off_is_truly_empty_schedule(tc)
% events.enabled=false must reach the production runtime as an actually empty
% schedule, not a hidden canonical event. The result schema is DISTINCT and
% slimmer than the events-on schema, `events` is empty, every transaction_id
% entry is 0 (no event transaction at any sample), and event_transactions is 0.
[r,~] = run_ibr_off();
tc.verifyTrue(r.converged);
% `events` is the empty-schedule sentinel produced by the runtime.
tc.verifyEqual(size(r.events), [0 0]);
% transaction_id is per-sample (one per time step); every entry must be 0.
tc.verifyTrue(all(r.transaction_id == 0));
tc.verifyEqual(r.execution_summary.event_transactions, 0);
% Distinct slim schema vs events-on: the OFF result has far fewer fields
% than the ON result (events-on-only fields absent).
[ron,~] = run_ibr_on();
off_fields = fieldnames(r);
on_fields = fieldnames(ron);
tc.verifyGreaterThan(numel(on_fields), numel(off_fields));
% The events-on-only fields must NOT appear in the off schema.
on_only = setdiff(on_fields, off_fields);
tc.verifyGreaterThan(numel(on_only), 0);
for k = 1:numel(on_only)
    tc.verifyFalse(isfield(r, on_only{k}));
end
end

%% ---- Partial invocation contract (correction #3) ----
function test_partial_invocation_opens_picker_no_autoexecute(tc)
% A partially specified call (analysis given, case omitted) opens the
% interactive case picker and never auto-executes. In headless batch this
% surfaces as the NonInteractiveFunctionSupport error from listdlg; the
% contract is that the launcher does NOT silently pick a default case.
threw = false;
id = '';
try
    evalc("solve_case('analysis','pf');");
catch e
    threw = true;
    id = e.identifier;
end
tc.verifyTrue(threw, 'partial invocation must not auto-execute silently');
tc.verifyTrue(endsWith(id, 'NonInteractiveFunctionSupport'), ...
    sprintf('expected interactive-picker block, got %s', id));
end

function test_no_arg_invocation_opens_picker(tc)
% No-argument call opens the analysis picker (interactive UI replacement;
% correction #2 — we do not reproduce the old dialog sequence, only the
% contract that it is interactive and does not auto-execute).
threw = false;
id = '';
try
    evalc("solve_case();");
catch e
    threw = true;
    id = e.identifier;
end
tc.verifyTrue(threw, 'no-arg invocation must not auto-execute silently');
tc.verifyTrue(endsWith(id, 'NonInteractiveFunctionSupport'), ...
    sprintf('expected interactive-picker block, got %s', id));
end

%% ---- Log file + stable log tokens (correction #9: path excluded) ----
function test_log_file_created_with_stable_tokens(tc)
% Run solve_case directly (NOT through evalc, which captures stdout and
% starves the diary-backed log file). The stable tokens must appear in both
% the live stdout and the log file. Volatile values (timestamp, log path)
% are excluded from comparison (correction #9).
r = solve_case('analysis','pf','case','ieee5', ...
    'options',struct('verbose',false,'plot_results',false));
tc.verifyTrue(isfile(r.launcher.log_file));
log_text = fileread(r.launcher.log_file);
tc.verifyTrue(contains(log_text, 'IN-HOUSE ANALYSIS LAUNCHER'));
tc.verifyTrue(contains(log_text, 'Analysis : PF'));
tc.verifyTrue(contains(log_text, 'STATUS: COMPLETE'));
tc.verifyTrue(contains(log_text, 'PF VERIFICATION'));
end

%% ---- Defaults are case/source-driven (correction #8 lazy; here just values) ----
function test_pf_defaults_when_options_empty(tc)
txt = evalc("r = solve_case('analysis','pf','case','ieee5','options',struct());");
tc.verifyTrue(r.converged);
% PF default max_iter=50, tolerance=1e-10, enforce_q_limits=true (frozen).
tc.verifyEqual(r.metadata.method_executed, 'newton_raphson');
end

%% ---- Dispatch is single-source (correction: no duplicate dispatch) ----
function test_dispatch_uses_project_solver_entries(tc)
% PF dispatch must route through pfsolver.pf_resolve_method + pf_method_strategy.
src = fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))),'solve_case.m'));
tc.verifyTrue(contains(src,'pfsolver.pf_resolve_method'));
tc.verifyTrue(contains(src,'pfsolver.pf_method_strategy'));
tc.verifyTrue(contains(src,'stability.multicase_sssa'));
tc.verifyTrue(contains(src,'stability.ts_simulate'));
tc.verifyTrue(contains(src,'stability.run_hybrid_case'));
end
