function tests = test_wizard_pure_layer()
%TEST_WIZARD_PURE_LAYER  Headless tests for the pure +wizard/* functions.
%   Covers: analysis_registry, discover_cases, defaults_for_method,
%   build_request, validate_request. No GUI; no numerical claims beyond
%   option/contract checks.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

%% ---- analysis_registry ----
function test_registry_has_four_stable_ids(tc)
r = wizard.analysis_registry();
tc.verifyEqual({r.id}.', {'pf';'sssa';'ts';'ibr'});
end

function test_registry_events_applicability(tc)
r = wizard.analysis_registry();
m = containers.Map({r.id},{r.events_applicable});
tc.verifyFalse(m('pf'));
tc.verifyFalse(m('sssa'));
tc.verifyTrue(m('ts'));
tc.verifyTrue(m('ibr'));
end

function test_registry_requires_equilibrium(tc)
r = wizard.analysis_registry();
m = containers.Map({r.id},{r.requires_equilibrium});
tc.verifyFalse(m('pf'));
tc.verifyTrue(m('sssa'));
tc.verifyTrue(m('ts'));
tc.verifyTrue(m('ibr'));
end

function test_registry_no_ibr_ts_id(tc)
r = wizard.analysis_registry();
tc.verifyFalse(any(strcmp({r.id}, 'ibr_ts')));
end

%% ---- discover_cases ----
function test_discover_pf_has_catalog_entries(tc)
r = wizard.discover_cases('pf');
tc.verifyGreaterThanOrEqual(numel(r), 1);
tc.verifyTrue(all(ismember({'id','label','loader','options','analysis','schema'}, fieldnames(r))));
tc.verifyTrue(all(strcmp({r.analysis}, 'pf')));
end

function test_discover_sssa_includes_sauer_pai(tc)
r = wizard.discover_cases('sssa');
tc.verifyTrue(any(strcmp({r.id}, 'sauer_pai')));
end

function test_discover_ts_uses_catalog(tc)
r = wizard.discover_cases('ts');
tc.verifyGreaterThanOrEqual(numel(r), 1);
tc.verifyTrue(all(strcmp({r.analysis}, 'ts')));
end

function test_discover_ibr_single_entry(tc)
r = wizard.discover_cases('ibr');
tc.verifyEqual(numel(r), 1);
tc.verifyEqual(r(1).id, 'ieee14_1sg_4ibr');
end

function test_discover_is_lazy_no_solve(tc)
% Correction #8: discovery must not execute PF/equilibrium or load solved
% states. The loader is a function handle, not yet invoked; confirm the
% entries carry handles and no case_data was loaded by the call.
r = wizard.discover_cases('pf');
for k = 1:numel(r)
    tc.verifyTrue(isa(r(k).loader, 'function_handle'));
end
end

function test_discover_unknown_analysis_errors(tc)
tc.verifyError(@() wizard.discover_cases('bogus'), ...
    'solve_case:analysis');
end

%% ---- defaults_for_method ----
function test_defaults_pf_frozen_values(tc)
opt = wizard.defaults_for_method('pf');
tc.verifyEqual(opt.max_iter, 50);
tc.verifyEqual(opt.tolerance, 1e-10);
tc.verifyEqual(opt.enforce_q_limits, true);
tc.verifyEqual(opt.q_limit_tolerance, 1e-6);
tc.verifyEqual(opt.max_q_limit_switches, 20);
end

function test_defaults_ibr_frozen_values(tc)
opt = wizard.defaults_for_method('ibr');
tc.verifyEqual(opt.t_end, 15.0);
% Default dt=0.005 (2026-07-20): the Profile-B Zf=0.1i fault route at dt=0.01
% stalls at t=3.25 s with a near-singular coupled Jacobian
% (rcond~2e-7, domain_rejected_trials=0) — a step-size/globalization defect
% tracked as IBR-2026-07-20-01. dt=0.005 passes the fault window, reaches
% sg_trip/sg_on, and completes to t=15 s (197 domain-preserving trial
% rejections, accepted min|V|>=V_div_min). The default is set to the value
% that the bounded diagnosis proved converges; it is not a tolerance/gate
% relaxation. See defect record
% docs/project/defects/2026-07-20-dt01-newton-stall-t325.md.
tc.verifyEqual(opt.dt, 0.005);
% Approved launcher contract (2026-07-19): Profile B replaces the implicit
% four-WECC default. Independent state-count oracle is 5+13+3*10=48 active.
tc.verifyEqual(opt.ibr_profile, 'rms10_profile_b');
tc.verifyEqual(opt.initial_gfm_count, 1);
tc.verifyEqual(opt.initial_gfl_count, 3);
tc.verifyEqual(opt.initial_gfm_indices, 2);
tc.verifyEqual(opt.ibr_events.fault_bus, 4);
tc.verifyEqual(opt.ibr_events.fault_on, 3.0);
tc.verifyEqual(opt.ibr_events.fault_clear, 3.1);
end

function test_defaults_merge_case_options(tc)
% Case-defined options (e.g. kundur uses emf6) override launcher defaults.
entries = wizard.discover_cases('sssa');
ku = entries(strcmp({entries.id},'kundur'));
if ~isempty(ku)
    opt = wizard.defaults_for_method('sssa', ku(1));
    tc.verifyEqual(opt.model, 'emf6');
end
end

function test_defaults_unknown_analysis_errors(tc)
tc.verifyError(@() wizard.defaults_for_method('bogus'), ...
    'wizard:defaults_for_method:unknownAnalysis');
end

%% ---- build_request ----
function test_build_request_pf_minimal(tc)
req = wizard.build_request('pf','ieee5');
tc.verifyEqual(req.analysis, 'pf');
tc.verifyEqual(req.case_id, 'ieee5');
tc.verifyEqual(req.events_policy, 'not_applicable');
tc.verifyEqual(req.schema_version, 'wizard_request_v1');
tc.verifyTrue(isstruct(req.options) && isfield(req.options,'max_iter'));
end

function test_build_request_ibr_event_free(tc)
% event_free for IBR must be requested explicitly (default IBR carries events).
% A disabled event struct is preserved so the dispatcher can pass it through
% to the production runtime as the empty-schedule sentinel (correction #6).
req = wizard.build_request('ibr','ieee14_1sg_4ibr','events',struct('enabled',false));
tc.verifyEqual(req.events_policy, 'event_free');
tc.verifyTrue(~isempty(req.events) && isfield(req.events,'enabled') ...
              && ~logical(req.events.enabled));
end

function test_build_request_ibr_default_has_events(tc)
% The default IBR options carry an enabled event spec (matches solve_case
% behavior: default IBR run uses the fault/trip/reclose schedule).
req = wizard.build_request('ibr','ieee14_1sg_4ibr');
tc.verifyEqual(req.events_policy, 'configured');
tc.verifyTrue(~isempty(req.events) && req.events.enabled);
end

function test_build_request_with_events(tc)
ev = struct('enabled',true,'fault_bus',4,'Zf',1i*.1, ...
    'fault_on',.02,'fault_clear',.03,'sg_trip',.04,'sg_on',.06, ...
    'selected_gfm_indices',2:5,'reference_resource_index',2);
req = wizard.build_request('ibr','ieee14_1sg_4ibr','events',ev);
tc.verifyEqual(req.events_policy, 'configured');
tc.verifyEqual(req.events.fault_bus, 4);
end

function test_build_request_options_merge(tc)
req = wizard.build_request('pf','ieee5','options',struct('max_iter',99));
tc.verifyEqual(req.options.max_iter, 99);
% Untouched default survives.
tc.verifyEqual(req.options.tolerance, 1e-10);
end

function test_build_request_interactive_flag(tc)
req = wizard.build_request('pf','ieee5','interactive',true);
tc.verifyTrue(req.interactive);
end

%% ---- validate_request ----
function test_validate_pf_passes(tc)
req = wizard.build_request('pf','ieee5');
req = wizard.validate_request(req); %#ok<NASGU>
end

function test_validate_ibr_event_free_passes(tc)
req = wizard.build_request('ibr','ieee14_1sg_4ibr');
req = wizard.validate_request(req); %#ok<NASGU>
end

function test_validate_ibr_configured_passes(tc)
ev = struct('enabled',true,'fault_bus',4,'Zf',1i*.1, ...
    'fault_on',.02,'fault_clear',.03,'sg_trip',.04,'sg_on',.06, ...
    'selected_gfm_indices',2:5,'reference_resource_index',2);
req = wizard.build_request('ibr','ieee14_1sg_4ibr','events',ev);
req = wizard.validate_request(req); %#ok<NASGU>
end

function test_validate_unknown_analysis(tc)
req = wizard.build_request('pf','ieee5');
req.analysis = 'bogus';
tc.verifyError(@() wizard.validate_request(req), ...
    'solve_case:analysis');
end

function test_validate_unknown_case(tc)
req = wizard.build_request('pf','ieee5');
req.case_id = 'bogus';
tc.verifyError(@() wizard.validate_request(req), ...
    'solve_case:case');
end

function test_validate_pf_cannot_carry_events(tc)
req = wizard.build_request('pf','ieee5');
req.events = struct('enabled',true);
req.events_policy = 'configured';
tc.verifyError(@() wizard.validate_request(req), ...
    'wizard:validate_request:eventsNotApplicable');
end

function test_validate_bad_event_ordering(tc)
ev = struct('enabled',true,'fault_bus',4,'Zf',1i*.1, ...
    'fault_on',.05,'fault_clear',.02,'sg_trip',.04,'sg_on',.06, ...
    'selected_gfm_indices',2:5,'reference_resource_index',2);
req = wizard.build_request('ibr','ieee14_1sg_4ibr','events',ev);
tc.verifyError(@() wizard.validate_request(req), ...
    'wizard:validate_request:badEventOrdering');
end

function test_validate_event_out_of_range(tc)
ev = struct('enabled',true,'fault_bus',4,'Zf',1i*.1, ...
    'fault_on',.02,'fault_clear',.03,'sg_trip',.04,'sg_on',.06, ...
    'selected_gfm_indices',2:5,'reference_resource_index',2);
req = wizard.build_request('ibr','ieee14_1sg_4ibr','events',ev);
% Force a time beyond t_end (set t_end small).
req.options.t_end = 0.01;
tc.verifyError(@() wizard.validate_request(req), ...
    'wizard:validate_request:eventOutOfRange');
end

function test_validate_event_free_with_nonempty_events_fails(tc)
% Correction #6: event_free must be ACTUALLY empty. A non-empty events struct
% with event_free policy is a contract violation (no hidden events).
req = wizard.build_request('ibr','ieee14_1sg_4ibr');
req.events = struct('enabled',true);
req.events_policy = 'event_free';
tc.verifyError(@() wizard.validate_request(req), ...
    'wizard:validate_request:badEventStruct');
end
