function tests = test_ibr_index_selected_gfm_commit()
%TEST_IBR_INDEX_SELECTED_GFM_COMMIT  Generic selector/event contract tests.
%   Falsifies hidden first-resource selection, count drift, reference drift,
%   partial mutation on invalid commits, and fabricated SSSA evidence.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
function test_selector_exact_one_two_three(testCase)
resources = generic_resources();
for n_required = 1:3
    opt = struct('n_gfm_required', n_required, ...
        'reference_resource_index', 2, 'gamma_req', 0.1);
    result = stability.ibr_config_selector(resources, struct(), struct(), opt);

    testCase.verifyEqual(result.n_gfm_required, n_required, 'AbsTol', 0);
    testCase.verifyEqual(numel(result.selected_gfm_indices), n_required, 'AbsTol', 0);
    testCase.verifyTrue(ismember(result.reference_resource_index, ...
        result.selected_gfm_indices));
    testCase.verifyTrue(result.structural_feasible);
    testCase.verifyFalse(result.sssa_evaluated);
    testCase.verifyFalse(result.ready_to_commit);
    testCase.verifyEqual(result.selection_status, ...
        'STRUCTURAL_CANDIDATES_ONLY', 'AbsTol', 0);

    expected_candidates = nchoosek(3, n_required - 1);
    testCase.verifyEqual(numel(result.configurations), expected_candidates, ...
        'AbsTol', 0);
    for k = 1:numel(result.configurations)
        c = result.configurations(k);
        testCase.verifyEqual(numel(c.selected_gfm_indices), n_required, 'AbsTol', 0);
        testCase.verifyTrue(ismember(c.reference_resource_index, ...
            c.selected_gfm_indices));
        testCase.verifyTrue(c.structural_feasible);
        testCase.verifyFalse(c.topology_evaluated);
        testCase.verifyFalse(c.sssa_evaluated);
        testCase.verifyEmpty(c.sssa_pass);
        testCase.verifyTrue(isnan(c.margin));
        testCase.verifyFalse(c.ready_to_commit);
        testCase.verifyFalse(c.feasible, ...
            'Structural-only candidate must not masquerade as fully feasible.');
    end
end
end

% =========================================================================
function test_selector_order_and_fingerprint_deterministic(testCase)
resources = generic_resources();
opt = struct('n_gfm_required', 2, 'reference_resource_index', 2);
r1 = stability.ibr_config_selector(resources, struct(), struct(), opt);
r2 = stability.ibr_config_selector(resources, struct(), struct(), opt);
testCase.verifyEqual(r1.selected_gfm_indices, [2 3], 'AbsTol', 0);
testCase.verifyEqual(r1.reference_resource_index, 2, 'AbsTol', 0);
testCase.verifyEqual(r1.fingerprint, r2.fingerprint, 'AbsTol', 0);
testCase.verifyEqual({r1.configurations.ordering_key}, ...
    {r2.configurations.ordering_key}, 'AbsTol', 0);
end

% =========================================================================
function test_selector_config_alignment_fails_closed(testCase)
resources = generic_resources();
scenario = struct();
scenario.config = struct('resource_ids', {{'wrong'}}, ...
    'mode', {{'gfl'}}, 'online', true);
result = stability.ibr_config_selector(resources, struct(), scenario, ...
    struct('n_gfm_required', 1));
testCase.verifyFalse(result.structural_feasible);
testCase.verifyEmpty(result.selected_gfm_indices);
testCase.verifyEqual(result.failure_id, ...
    'stability:ibr_config_selector:configDrift', 'AbsTol', 0);
end

% =========================================================================
function test_selector_missing_required_count_fails_closed(testCase)
resources = generic_resources();
result = stability.ibr_config_selector(resources,struct(),struct(),struct());
testCase.verifyFalse(result.structural_feasible);
testCase.verifyEmpty(result.selected_gfm_indices);
testCase.verifyEqual(result.failure_id, ...
    'stability:ibr_config_selector:badRequiredCount','AbsTol',0);
end

% =========================================================================
function test_selector_preserves_scenario_gamma_contract(testCase)
resources = generic_resources();
scenario = struct('selector',struct('gamma_req_rad_per_s',0.25));
result = stability.ibr_config_selector(resources, struct(), scenario, ...
    struct('n_gfm_required',1));
testCase.verifyEqual(result.gamma_req, 0.25, 'AbsTol', 0);
testCase.verifyTrue(contains(result.fingerprint, 'gamma=0.25'));
end

% =========================================================================
function test_event_commits_exact_one_two_three(testCase)
resources = generic_resources();
devices = generic_devices(resources);
for n_required = 1:3
    hs = stability.ts_hybrid_state_init(devices);
    selected = 2:(n_required + 1);
    committed = struct('selected_gfm_indices', selected, ...
        'n_gfm_required', n_required, ...
        'reference_resource_index', selected(end));
    event = struct('type', 'sg_trip_request', 't', 1.0, ...
        'sg_ids', {{'MachineAlpha'}}, ...
        'committed_selection', committed);

    [after, log] = stability.sg_event_handler(hs, event, devices);
    testCase.verifyTrue(log.applied);
    testCase.verifyTrue(log.right_limit_required);
    testCase.verifyFalse(after.device_online.MachineAlpha);
    testCase.verifyEqual(after.device_modes.MachineAlpha, ...
        'breaker_open', 'AbsTol', 0);
    for idx = 2:numel(devices)
        key = matlab.lang.makeValidName(devices(idx).device_id, ...
            'ReplacementStyle', 'underscore');
        if ismember(idx, selected)
            testCase.verifyEqual(after.device_modes.(key), 'GFM', 'AbsTol', 0);
        else
            testCase.verifyEqual(after.device_modes.(key), 'gfl', 'AbsTol', 0);
        end
    end
    testCase.verifyEqual(after.selected_gfm_indices, selected, 'AbsTol', 0);
    testCase.verifyEqual(after.n_gfm_required, n_required, 'AbsTol', 0);
    testCase.verifyEqual(after.reference_resource_index, selected(end), 'AbsTol', 0);
    testCase.verifyEqual(after.committed_selection, committed);
end
end

% =========================================================================
function test_ieee14_trip_snapshot_drives_physical_right_limit(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
ids = {'IBR2','IBR3','IBR6','IBR8'};
modes = struct('device_id',ids,'mode',repmat({'gfl'},1,4));
dispatch = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
devices = ibr.build_ieee14_sg_ibr_devices(c,modes,dispatch);
for n_required = 1:3
    before = stability.ts_hybrid_state_init(devices);
    selected = 2:(n_required+1);
    reference = selected(end); % prove reference need not be first selected
    committed = struct('selected_gfm_indices',selected, ...
        'n_gfm_required',n_required,'reference_resource_index',reference);
    event = struct('type','sg_trip_request','t',1.0, ...
        'sg_ids',{{'SG1'}},'committed_selection',committed);
    [right_state,log] = stability.sg_event_handler(before,event,devices);
    testCase.assertTrue(log.applied,log.details);
    cfg = struct('devices',devices,'hybrid_state',right_state, ...
        'selected_gfm_indices',selected,'n_gfm_required',n_required, ...
        'reference_resource_index',reference);
    eq = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
    testCase.assertTrue(eq.converged,eq.failure_reason);
    testCase.verifyLessThan(eq.physical_kcl_norm,1e-6);
    testCase.verifyEqual(eq.reference.device_index,reference,'AbsTol',0);
    testCase.verifyEqual(eq.partition.slack_input_unknowns,1,'AbsTol',0);
    testCase.verifyFalse(eq.devices(1).initial_online);
    for k = 2:numel(eq.devices)
        expected = 'gfl'; if ismember(k,selected), expected = 'gfm'; end
        testCase.verifyEqual(lower(eq.devices(k).initial_mode),expected);
    end
end
end

% =========================================================================
function test_event_malformed_commits_roll_back(testCase)
resources = generic_resources();
devices = generic_devices(resources);
base = stability.ts_hybrid_state_init(devices);

events = {
    struct('type','sg_trip_request','t',1.0,'sg_ids',{{'MachineAlpha'}})
    trip_event(struct('selected_gfm_indices',2,'n_gfm_required',2, ...
        'reference_resource_index',2))
    trip_event(struct('selected_gfm_indices',[2 2],'n_gfm_required',2, ...
        'reference_resource_index',2))
    trip_event(struct('selected_gfm_indices',99,'n_gfm_required',1, ...
        'reference_resource_index',99))
    trip_event(struct('selected_gfm_indices',[2 3],'n_gfm_required',2, ...
        'reference_resource_index',4))
    };
expected = {
    'stability:sg_event_handler:missingCommittedSelection'
    'stability:sg_event_handler:selectionCountMismatch'
    'stability:sg_event_handler:duplicateSelectedIndices'
    'stability:sg_event_handler:badSelectedIndices'
    'stability:sg_event_handler:referenceNotSelected'
    };
for k = 1:numel(events)
    [after, log] = stability.sg_event_handler(base, events{k}, devices);
    testCase.verifyFalse(log.applied);
    testCase.verifyTrue(isequaln(after, base), ...
        sprintf('Malformed transaction %d partially mutated hybrid state.', k));
    testCase.verifyEqual(log.failure_id, expected{k}, 'AbsTol', 0);
end
end

% =========================================================================
function test_event_offline_or_incapable_selection_rolls_back(testCase)
resources = generic_resources();
devices = generic_devices(resources);
event = trip_event(struct('selected_gfm_indices',2, ...
    'n_gfm_required',1,'reference_resource_index',2));

offline = stability.ts_hybrid_state_init(devices);
offline.device_online.ConverterAlpha = false;
[after_offline, log_offline] = stability.sg_event_handler(offline, event, devices);
testCase.verifyFalse(log_offline.applied);
testCase.verifyTrue(isequaln(after_offline, offline));
testCase.verifyEqual(log_offline.failure_id, ...
    'stability:sg_event_handler:selectedResourceIneligible', 'AbsTol', 0);

incapable_devices = devices;
incapable_devices(2).capabilities.can_switch_mode = false;
incapable = stability.ts_hybrid_state_init(incapable_devices);
[after_incapable, log_incapable] = stability.sg_event_handler( ...
    incapable, event, incapable_devices);
testCase.verifyFalse(log_incapable.applied);
testCase.verifyTrue(isequaln(after_incapable, incapable));
testCase.verifyEqual(log_incapable.failure_id, ...
    'stability:sg_event_handler:selectedResourceIneligible', 'AbsTol', 0);
end

% =========================================================================
function test_event_lockout_rolls_back_whole_transaction(testCase)
resources = generic_resources();
devices = generic_devices(resources);
hs = stability.ts_hybrid_state_init(devices);
hs.lockouts.ConverterBeta = 5.0;
event = trip_event(struct('selected_gfm_indices',3, ...
    'n_gfm_required',1,'reference_resource_index',3));
[after, log] = stability.sg_event_handler(hs, event, devices);
testCase.verifyFalse(log.applied);
testCase.verifyTrue(isequaln(after, hs));
testCase.verifyEqual(log.failure_id, ...
    'stability:sg_event_handler:modeTransitionBlocked', 'AbsTol', 0);
end

% =========================================================================
function test_scenario_carries_committed_reference(testCase)
resources = generic_resources();
committed = struct('selected_gfm_indices',[2 4], ...
    'n_gfm_required',2,'reference_resource_index',4);
scenario = stability.build_hybrid_scenario( ...
    struct('system_name','generic-index-contract'), resources, ...
    struct('committed_selection', committed));
testCase.verifyEqual(scenario.committed_selection, committed);
testCase.verifyEqual(scenario.config.selected_gfm_indices, [2 4], 'AbsTol', 0);
testCase.verifyEqual(scenario.config.n_gfm_required, 2, 'AbsTol', 0);
testCase.verifyEqual(scenario.reference_policy.reference_resource_index, 4, ...
    'AbsTol', 0);
testCase.verifyEqual(scenario.selector.n_gfm_required, 2, 'AbsTol', 0);
testCase.verifyTrue(contains(scenario.metadata.config_hash, 'reference=4'));
end

% =========================================================================
function test_scenario_rejects_reference_outside_selection(testCase)
resources = generic_resources();
bad = struct('selected_gfm_indices',[2 3], ...
    'n_gfm_required',2,'reference_resource_index',4);
testCase.verifyError(@() stability.build_hybrid_scenario( ...
    struct(), resources, struct('committed_selection', bad)), ...
    'stability:build_hybrid_scenario:referenceNotSelected');
end

% =========================================================================
function test_no_first_fieldname_selection_grep(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
src = fileread(fullfile(root, '+stability', 'sg_event_handler.m'));
testCase.verifyFalse(contains(src, 'fieldnames(hs.device_modes)'));
testCase.verifyTrue(contains(src, 'event.committed_selection'));
end

% =========================================================================
function event = trip_event(committed)
event = struct('type','sg_trip_request','t',1.0, ...
    'sg_ids',{{'MachineAlpha'}},'committed_selection',committed);
end

function resources = generic_resources()
base_provenance = struct('model','test','source','test contract', ...
    'classification','CASE_DEFINED','details','generic index test');
empty_limits = struct();
empty_ratings = struct();
sg = struct('resource_id','MachineAlpha','bus_id',101, ...
    'resource_type','sg','model_id','sg_emf6', ...
    'supported_modes',{{'synchronous','breaker_open'}}, ...
    'voltage_forming_modes','synchronous','initial_mode','synchronous', ...
    'initial_online',true,'can_switch_mode',true,'can_switch_online',true, ...
    'has_current_limiter',false,'has_frt',false,'can_black_start',false, ...
    'limits',empty_limits,'ratings',empty_ratings,'dynamic_params',struct(), ...
    'provenance',base_provenance);
resources = repmat(sg, 1, 5);
resources(1) = sg;
names = {'ConverterAlpha','ConverterBeta','ConverterGamma','ConverterDelta'};
for k = 1:4
    resources(k+1) = struct('resource_id',names{k},'bus_id',200+k, ...
        'resource_type','ibr','model_id','regfm_b1_dual', ...
        'supported_modes',{{'gfl','gfm','tripped'}}, ...
        'voltage_forming_modes','gfm','initial_mode','gfl', ...
        'initial_online',true,'can_switch_mode',true,'can_switch_online',true, ...
        'has_current_limiter',true,'has_frt',true,'can_black_start',false, ...
        'limits',empty_limits,'ratings',empty_ratings,'dynamic_params',struct(), ...
        'provenance',base_provenance);
end
end

function devices = generic_devices(resources)
devices = repmat(struct(), 1, numel(resources));
for k = 1:numel(resources)
    r = resources(k);
    devices(k).device_id = r.resource_id;
    devices(k).initial_mode = r.initial_mode;
    devices(k).initial_online = r.initial_online;
    devices(k).device_type = r.resource_type;
    capabilities = struct();
    capabilities.resource_type = r.resource_type;
    capabilities.supported_modes = r.supported_modes;
    capabilities.voltage_forming_modes = r.voltage_forming_modes;
    capabilities.can_switch_mode = r.can_switch_mode;
    capabilities.can_switch_online = r.can_switch_online;
    capabilities.has_current_limiter = r.has_current_limiter;
    capabilities.has_frt = r.has_frt;
    capabilities.can_black_start = r.can_black_start;
    devices(k).capabilities = capabilities;
end
end
