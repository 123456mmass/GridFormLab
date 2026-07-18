function tests = test_wizard_dispatch()
%TEST_WIZARD_DISPATCH  Dispatch + result adapter + config_io headless tests.
%   Verifies wizard.dispatch_analysis calls the existing production launchers
%   verbatim and produces the same result schema as solve_case (single shared
%   dispatcher, G4). Also covers adapt_result (generic 12-section view model)
%   and config_io (wizard_config_v1 fingerprint round-trip).
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

%% ---- dispatch: PF ----
function test_dispatch_pf_matches_schema(tc)
req = wizard.build_request('pf','ieee5','options',struct('verbose',false,'plot_results',false));
r = wizard.dispatch_analysis(req);
tc.verifyTrue(r.converged);
tc.verifyEqual(r.launcher.analysis, 'pf');
tc.verifyEqual(r.launcher.case_id, 'ieee5');
tc.verifyTrue(isfield(r,'execution_summary'));
tc.verifyEqual(r.execution_summary.pf_invocations, 1);
tc.verifyEqual(r.metadata.method_executed, 'newton_raphson');
end

%% ---- dispatch: SSSA ----
function test_dispatch_sssa(tc)
req = wizard.build_request('sssa','ieee5','options',struct('verbose',false));
r = wizard.dispatch_analysis(req);
tc.verifyEqual(r.launcher.analysis, 'sssa');
tc.verifyEqual(r.execution_summary.sssa_invocations, 1);
tc.verifyGreaterThan(r.execution_summary.eigenvalue_count, 0);
end

%% ---- dispatch: TS ----
function test_dispatch_ts(tc)
req = wizard.build_request('ts','ieee5','options',struct('verbose',false,'plot_results',false));
r = wizard.dispatch_analysis(req);
tc.verifyEqual(r.launcher.analysis, 'ts');
tc.verifyEqual(r.execution_summary.ts_invocations, 1);
tc.verifyGreaterThan(r.execution_summary.ts_step_count, 0);
end

%% ---- dispatch: IBR events=false (event_free reaches production) ----
function test_dispatch_ibr_event_free(tc)
% Correction #6: events=false must reach production as an ACTUALLY empty
% schedule. event_free must be requested explicitly (default IBR carries events).
req = wizard.build_request('ibr','ieee14_1sg_4ibr', ...
    'options',struct('t_end',.1,'dt',.01,'plot_results',false), ...
    'events',struct('enabled',false));
r = wizard.dispatch_analysis(req);
tc.verifyTrue(r.converged);
tc.verifyEqual(size(r.events), [0 0]);
tc.verifyTrue(all(r.transaction_id == 0));
tc.verifyEqual(r.execution_summary.event_transactions, 0);
end

%% ---- dispatch: IBR with configured events ----
function test_dispatch_ibr_configured(tc)
ev = struct('enabled',true,'fault_bus',4,'Zf',1i*.1, ...
    'fault_on',.02,'fault_clear',.03,'sg_trip',.04,'sg_on',.06, ...
    'selected_gfm_indices',2:5,'reference_resource_index',2);
req = wizard.build_request('ibr','ieee14_1sg_4ibr', ...
    'options',struct('t_end',.1,'dt',.01,'plot_results',false),'events',ev);
r = wizard.dispatch_analysis(req);
% GFL-RMS10 is approved for normal operation, not LVRT.  The same configured
% fault that the legacy WECC route survived must fail closed rather than tune
% or freeze the new PLL/current equations to force a pass.
tc.verifyFalse(r.converged);
tc.verifyEqual(r.failure_id, 'ts_simulate_ibr_hybrid:rightLimit');
tc.verifyGreaterThan(r.execution_summary.event_transactions, 0);
end

%% ---- dispatch: error propagation ----
function test_dispatch_unknown_case(tc)
req = wizard.build_request('pf','bogus');
req.case_id = 'bogus';
tc.verifyError(@() wizard.dispatch_analysis(req), ...
    'solve_case:case');
end

%% ---- adapt_result: 12 sections ----
function test_adapt_result_has_12_sections(tc)
req = wizard.build_request('pf','ieee5','options',struct('verbose',false,'plot_results',false));
r = wizard.dispatch_analysis(req);
view = wizard.adapt_result(r, req);
tc.verifyEqual(numel(view.sections), 12);
% Every section has the contract fields.
for k = 1:12
    tc.verifyTrue(isfield(view.sections(k),'index'));
    tc.verifyTrue(isfield(view.sections(k),'title'));
    tc.verifyTrue(isfield(view.sections(k),'status'));
    tc.verifyTrue(isfield(view.sections(k),'content'));
end
end

function test_adapt_result_pf_statuses(tc)
req = wizard.build_request('pf','ieee5','options',struct('verbose',false,'plot_results',false));
r = wizard.dispatch_analysis(req);
view = wizard.adapt_result(r, req);
% PF analysis: PF section ok, SSSA/TS not_applicable.
tc.verifyEqual(view.sections(3).status, 'ok');   % PF verification
tc.verifyEqual(view.sections(4).status, 'not_applicable'); % SSSA
tc.verifyEqual(view.sections(5).status, 'not_applicable'); % TS
% Events: not_applicable for PF.
tc.verifyEqual(view.sections(8).status, 'not_applicable');
end

function test_adapt_result_ibr_event_free(tc)
req = wizard.build_request('ibr','ieee14_1sg_4ibr', ...
    'options',struct('t_end',.1,'dt',.01,'plot_results',false), ...
    'events',struct('enabled',false));
r = wizard.dispatch_analysis(req);
view = wizard.adapt_result(r, req);
tc.verifyEqual(view.sections(8).status, 'ok');
tc.verifyEqual(view.sections(8).content.policy, 'EVENT_FREE_NORMAL_OPERATION');
tc.verifyEqual(view.sections(8).content.event_transactions, 0);
end

function test_adapt_result_does_not_mutate_production(tc)
req = wizard.build_request('pf','ieee5','options',struct('verbose',false,'plot_results',false));
r = wizard.dispatch_analysis(req);
fn_before = fieldnames(r);
view = wizard.adapt_result(r, req); %#ok<NASGU>
fn_after = fieldnames(r);
tc.verifyEqual(fn_before, fn_after);
end

function test_adapt_result_no_fabricated_data(tc)
% Missing information must be NOT_RUN/NOT_APPLICABLE, never fabricated.
req = wizard.build_request('pf','ieee5','options',struct('verbose',false,'plot_results',false));
r = wizard.dispatch_analysis(req);
view = wizard.adapt_result(r, req);
% PF result has no state_names => state inventory must be not_run.
tc.verifyEqual(view.sections(6).status, 'not_run');
% Plots were disabled => plots section not_run.
tc.verifyEqual(view.sections(11).status, 'not_run');
end

%% ---- config_io: save/load round-trip ----
function test_config_io_roundtrip_pf(tc)
req = wizard.build_request('pf','ieee5','options',struct('verbose',false,'plot_results',false));
tmp = [tempname '_pf.json'];
cleanup = onCleanup(@() delete(tmp)); %#ok<NASGU>
wizard.config_io('save', req, tmp);
[loaded, fp2] = wizard.config_io('load', tmp);
tc.verifyEqual(loaded.analysis, 'pf');
tc.verifyEqual(loaded.case_id, 'ieee5');
tc.verifyEqual(loaded.events_policy, 'not_applicable');
% Fingerprint deterministic.
[~, fp1] = wizard.config_io('load', tmp);
tc.verifyEqual(fp1, fp2);
end

function test_config_io_roundtrip_ibr_events(tc)
ev = struct('enabled',true,'fault_bus',4,'Zf',1i*.1, ...
    'fault_on',.02,'fault_clear',.03,'sg_trip',.04,'sg_on',.06, ...
    'selected_gfm_indices',2:5,'reference_resource_index',2);
req = wizard.build_request('ibr','ieee14_1sg_4ibr', ...
    'options',struct('t_end',.1,'dt',.01,'plot_results',false),'events',ev);
tmp = [tempname '_ibr.json'];
cleanup = onCleanup(@() delete(tmp)); %#ok<NASGU>
wizard.config_io('save', req, tmp);
loaded = wizard.config_io('load', tmp);
tc.verifyEqual(loaded.analysis, 'ibr');
tc.verifyEqual(loaded.events_policy, 'configured');
tc.verifyEqual(loaded.events.fault_bus, 4);
% Complex Zf round-trips correctly.
tc.verifyEqual(loaded.events.Zf, 1i*.1);
end

function test_config_io_rejects_tampered_file(tc)
req = wizard.build_request('pf','ieee5','options',struct('verbose',false,'plot_results',false));
tmp = [tempname '_tamper.json'];
cleanup = onCleanup(@() delete(tmp)); %#ok<NASGU>
wizard.config_io('save', req, tmp);
% Tamper: change case_id without updating fingerprint.
txt = fileread(tmp);
rec = jsondecode(txt);
rec.request.case_id = 'ieee14';
fid = fopen(tmp, 'w'); fprintf(fid, '%s\n', jsonencode(rec, 'PrettyPrint', true)); fclose(fid);
tc.verifyError(@() wizard.config_io('load', tmp), ...
    'wizard:config_io:fingerprintMismatch');
end

function test_config_io_rejects_bad_schema(tc)
tmp = [tempname '_badschema.json'];
cleanup = onCleanup(@() delete(tmp)); %#ok<NASGU>
fid = fopen(tmp, 'w'); fprintf(fid, '%s\n', jsonencode(struct('schema_version','bogus'))); fclose(fid);
tc.verifyError(@() wizard.config_io('load', tmp), ...
    'wizard:config_io:badSchema');
end
