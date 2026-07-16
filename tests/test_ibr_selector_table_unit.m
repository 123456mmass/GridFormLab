function tests = test_ibr_selector_table_unit()
%TEST_IBR_SELECTOR_TABLE_UNIT  Synthetic-table unit tests for selector ranking + fingerprints + schema.
%   Falsifies hidden ranking rules, fingerprint drift, and schema normalization
%   defects using a SYNTHETIC authenticated selector table / candidate evidence.
%   No physical IEEE14 SCR/equilibrium/SSSA gates are exercised here (those are
%   in test_ieee14_ibr_sg_on_integration). This suite uses the structural-only
%   path of ibr_config_selector (no case_data) so ranking/identity contracts are
%   tested without Newton/SSSA solves.
%
%   All assertions go through PUBLIC entry points only:
%     stability.ibr_config_selector
%     stability.ibr_selector_table
%     stability.reference_owner_schema
%   No local subfunction of any production file is called directly.
%
%   Source: F1/F5/F6/C1/C7 user-approved validation-closure plan.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root, '-begin');
testCase.addTeardown(@() rmpath(root));
pf_init_paths();
end

% =========================================================================
% Ranking contract (structural-only path; synthetic resources)
% =========================================================================

function test_all_gfl_candidate_is_single_empty_subset(testCase)
% SG_ON context n_gfm_required=0 -> exactly one candidate, empty selected set.
res = generic_selector_result(struct('n_gfm_required', 0, 'sg_online', true));
testCase.verifyEqual(numel(res.configurations), 1);
cfg = res.configurations(1);
testCase.verifyEmpty(cfg.selected_gfm_indices);
testCase.verifyEqual(cfg.n_gfm_required, 0);
testCase.verifyEmpty(cfg.reference_resource_index);
testCase.verifyEqual(cfg.reason, 'sg_on_all_gfl_no_gfm_required');
% ready_to_commit must be false without SSSA evidence (no false readiness).
testCase.verifyFalse(cfg.ready_to_commit);
end

function test_fewer_gfm_sorts_first_when_tied(testCase)
% With 4 eligible IBRs, n_required=1 yields 4 candidates. All have the same
% n_mode_changes only if starting modes are symmetric; the single selected
% GFM produces 1 mode change in each. Ordering among them is the tie-break.
res = generic_selector_result(struct('n_gfm_required', 1));
cfgs = res.configurations;
testCase.verifyEqual(numel(cfgs), 4);
% Every n_required=1 candidate has exactly 1 GFM selected.
for k = 1:numel(cfgs)
    testCase.verifyEqual(numel(cfgs(k).selected_gfm_indices), 1);
end
% The first-selected candidate has the lowest resource-ID tie-break.
first_sel = cfgs(1).selected_gfm_indices;
ids = resource_ids_for();
first_ids = ids(first_sel);
testCase.verifyEqual(cfgs(1).tie_break, strjoin(first_ids, ','));
end

function test_n_mode_changes_orders_candidates(testCase)
% Start from a committed config where IBR index 2 is already GFM. Candidates
% that keep index 2 as GFM should have fewer mode changes than those that
% switch to a different single GFM.
% modes must be wrapped in a cell so struct() builds a scalar struct, not a
% struct array (struct('modes',row_cell) would expand into a struct array).
modes = {'gfl','gfm','gfl','gfl','gfl'};  % SG(1) + 4 IBRs, IBR2 already GFM
res = generic_selector_result(struct('n_gfm_required', 1, 'modes', {modes}));
cfgs = res.configurations;
% Candidate selecting IBR2 should have 0 mode changes; others have 2
% (deactivate IBR2 -> gfl, activate the chosen one -> gfm).
nchanges = [cfgs.n_mode_changes];
testCase.verifyTrue(any(nchanges == 0));
testCase.verifyEqual(min(nchanges), 0);
% The 0-mode-change candidate must rank first (ordering_key sorts ascending).
testCase.verifyEqual(cfgs(1).n_mode_changes, 0);
end

function test_resource_id_tiebreak_is_deterministic(testCase)
% Two calls with identical inputs must produce identical selected indices.
res1 = generic_selector_result(struct('n_gfm_required', 2));
res2 = generic_selector_result(struct('n_gfm_required', 2));
testCase.verifyEqual(res1.selected_config.selected_gfm_indices, ...
    res2.selected_config.selected_gfm_indices, 'AbsTol', 0);
testCase.verifyEqual(res1.configurations(1).tie_break, ...
    res2.configurations(1).tie_break);
% tie_break must be the sorted-joined resource IDs of the selected set.
sel = res1.selected_config.selected_gfm_indices;
ids = resource_ids_for();
expected_tb = strjoin(sort(ids(sel)), ',');
testCase.verifyEqual(res1.configurations(1).tie_break, expected_tb);
end

function result = generic_selector_result(over)
% Build a structural-only selector result from synthetic resources.
% over.n_gfm_required (required), over.modes (optional committed modes cell,
%   must be a ROW cell to avoid struct() creating a struct array),
% over.reference_resource_index (optional), over.gamma_req (optional),
% over.sg_online (optional, required true when n_gfm_required==0).
resources = synthetic_resources();
modes = arrayfun(@(r) char(r.initial_mode), resources, 'UniformOutput', false);
if isfield(over, 'modes')
    m = over.modes;
    if iscell(m) && numel(m) == numel(resources)
        modes = reshape(m, 1, []);
    end
end
opt = struct('n_gfm_required', over.n_gfm_required);
if isfield(over, 'reference_resource_index') && ~isempty(over.reference_resource_index)
    opt.reference_resource_index = over.reference_resource_index;
end
if isfield(over, 'gamma_req') && ~isempty(over.gamma_req)
    opt.gamma_req = over.gamma_req;
else
    opt.gamma_req = 0.1;
end
if isfield(over, 'sg_online') && ~isempty(over.sg_online)
    opt.sg_online = over.sg_online;
elseif over.n_gfm_required == 0
    opt.sg_online = true;  % n_required=0 requires SG_ON context
end
scenario = struct('selector', struct('gamma_req', opt.gamma_req), ...
    'config', struct('resource_ids', {resource_ids_for()}, 'modes', {modes}, ...
    'online', [resources.initial_online]));
result = stability.ibr_config_selector(resources, struct(), scenario, opt);
end

function ids = resource_ids_for()
r = synthetic_resources();
ids = cell(1, numel(r));
for k = 1:numel(r)
    ids{k} = char(r(k).resource_id);
end
end

function test_reference_constraint_filters_subsets(testCase)
% reference_resource_index must be a member of every retained candidate.
pref = 3;
res = generic_selector_result(struct('n_gfm_required', 2, ...
    'reference_resource_index', pref));
cfgs = res.configurations;
for k = 1:numel(cfgs)
    testCase.verifyTrue(ismember(pref, cfgs(k).selected_gfm_indices));
    testCase.verifyEqual(cfgs(k).reference_resource_index, pref);
end
% Number of retained candidates = choose(remaining_eligible, n-1).
% 4 eligible IBRs, pick 2 containing index 3 -> choose(3,1)=3.
testCase.verifyEqual(numel(cfgs), 3);
end

function test_insufficient_eligible_fails_closed(testCase)
% Requesting more GFMs than eligible must fail closed with a documented id.
res = generic_selector_result(struct('n_gfm_required', 99));
testCase.verifyEqual(res.selection_status, 'NO_STRUCTURAL_CANDIDATE');
testCase.verifyEqual(res.failure_id, ...
    'stability:ibr_config_selector:insufficientEligibleGfm');
testCase.verifyFalse(res.ready_to_commit);
end

function test_zero_resources_fails_closed(testCase)
res = stability.ibr_config_selector(repmat(struct(),1,0), struct(), struct(), ...
    struct('n_gfm_required', 1, 'gamma_req', 0.1));
testCase.verifyFalse(res.ready_to_commit);
end

function test_bad_gamma_req_errors(testCase)
testCase.verifyError(@() generic_selector_result( ...
    struct('n_gfm_required', 1, 'gamma_req', -1)), ...
    'stability:ibr_config_selector:badGammaReq');
end

% =========================================================================
% Selector table fingerprint (ibr_selector_table)
% =========================================================================

function test_selector_table_builds_sg_off_and_sg_on(testCase)
% The table builder must produce both contexts. Uses a minimal case_data so
% the builder can serialize the fingerprint without full evaluation.
cd = synthetic_case_data();
resources = synthetic_resources();
scenario = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {resource_ids_for()}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
table = stability.ibr_selector_table(cd, resources, scenario, opt);
testCase.verifyTrue(isfield(table, 'sg_off'));
testCase.verifyTrue(isfield(table, 'sg_on'));
testCase.verifyTrue(isfield(table, 'selector_table_fingerprint'));
testCase.verifyTrue(isfield(table, 'gamma_req'));
testCase.verifyEqual(table.gamma_req, 0.1, 'AbsTol', 0);
testCase.verifyEqual(table.built_at, 'precomputed_before_ts');
testCase.verifyTrue(~isempty(table.selector_table_fingerprint));
% Gate: fingerprint must NOT be the all-ones collision (ffffffff) that the
% pre-fix saturating-multiply hash produced for every input.
testCase.verifyNotEqual(table.selector_table_fingerprint, 'selector_table|ffffffff');
end

function test_fingerprint_immutable_for_identical_inputs(testCase)
% Gate: identical inputs -> identical fingerprint (deterministic).
cd = synthetic_case_data();
resources = synthetic_resources();
scenario = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {resource_ids_for()}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
t1 = stability.ibr_selector_table(cd, resources, scenario, opt);
t2 = stability.ibr_selector_table(cd, resources, scenario, opt);
testCase.verifyEqual(t1.selector_table_fingerprint, ...
    t2.selector_table_fingerprint);
% Gate: not the ffffffff collision.
testCase.verifyNotEqual(t1.selector_table_fingerprint, 'selector_table|ffffffff');
end

function test_fingerprint_changes_when_topology_changes(testCase)
% Gate: a change to the canonical topology input (branch data) must change
% the fingerprint. Uses structural-only path (no mpc) so the selector does
% not attempt full SCR/equilibrium/SSSA evaluation on synthetic resources;
% the fingerprint is still built from the serialized branch matrix.
cd1 = synthetic_case_data();
cd2 = synthetic_case_data();
cd2.mpc.branch(1,3) = cd2.mpc.branch(1,3) + 0.5;  % materially different reactance
resources = synthetic_resources();
scenario = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {resource_ids_for()}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
t1 = stability.ibr_selector_table(cd1, resources, scenario, opt);
t2 = stability.ibr_selector_table(cd2, resources, scenario, opt);
testCase.verifyNotEqual(t1.selector_table_fingerprint, ...
    t2.selector_table_fingerprint);
% Gate: neither is the ffffffff collision.
testCase.verifyNotEqual(t1.selector_table_fingerprint, 'selector_table|ffffffff');
testCase.verifyNotEqual(t2.selector_table_fingerprint, 'selector_table|ffffffff');
end

function test_fingerprint_changes_when_dispatch_changes(testCase)
% Gate: same topology, different dispatch contract -> different fingerprint.
% Uses structural-only path (no mpc) so the dispatch is the differentiator.
cd = struct();   % no mpc -> structural-only selector path
resources = synthetic_resources();
scenario1 = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {resource_ids_for()}, ...
    'dispatch', struct('P_pu', [0.1 0.1 0.1 0.1 0.1])));
scenario2 = scenario1;
scenario2.config.dispatch = struct('P_pu', [0.2 0.1 0.1 0.1 0.1]);
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
t1 = stability.ibr_selector_table(cd, resources, scenario1, opt);
t2 = stability.ibr_selector_table(cd, resources, scenario2, opt);
testCase.verifyNotEqual(t1.selector_table_fingerprint, ...
    t2.selector_table_fingerprint);
testCase.verifyNotEqual(t1.selector_table_fingerprint, 'selector_table|ffffffff');
end

function test_fingerprint_changes_when_resource_order_changes(testCase)
% Gate: same resources in a different ORDER must change the fingerprint
% (resource_ids ordering is part of the canonical serialization).
cd = struct();
res1 = synthetic_resources();
res2 = synthetic_resources();
% Swap two IBRs (indices 2 and 3) so the resource_ids order differs.
tmp = res2(2); res2(2) = res2(3); res2(3) = tmp;
ids1 = resource_ids_for();
ids2 = cell(1, numel(res2));
for k = 1:numel(res2), ids2{k} = char(res2(k).resource_id); end
scenario1 = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {ids1}));
scenario2 = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {ids2}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
t1 = stability.ibr_selector_table(cd, res1, scenario1, opt);
t2 = stability.ibr_selector_table(cd, res2, scenario2, opt);
testCase.verifyNotEqual(t1.selector_table_fingerprint, ...
    t2.selector_table_fingerprint);
end

% =========================================================================
% Reference-owner schema normalization (reference_owner_schema)
% =========================================================================
% reference_owner_schema reads online/mode status from hybrid_state.device_online
% and hybrid_state.device_modes (runtime state), NOT from devices.initial_*
% (static metadata). So every schema test must build a hybrid_state whose
% device_online/device_modes are consistent with the owner being tested.
% Validation order: cardinality -> sort -> per-owner (online, voltage-forming,
% capable, gfm-ref-capable) -> duplicateIsland (last).

function test_schema_legacy_alias_sg_off_single_island(testCase)
% SG_OFF single-island: legacy alias must equal gfm_reference_resource_indices(1).
devs = synthetic_devices();
hs = make_hybrid_state(devs);
hs.reference_resource_index = 3;  % legacy scalar (GFM index 3, online & GFM-capable)
norm = stability.reference_owner_schema(hs, devs, struct());
testCase.verifyTrue(norm.is_single_island);
testCase.verifyEqual(norm.reference_island_ids, 1);
testCase.verifyEqual(norm.reference_owner_indices, 3);
testCase.verifyEqual(norm.gfm_reference_resource_indices, 3);
testCase.verifyEqual(norm.reference_resource_index, 3);
end

function test_schema_canonical_multi_island_arrays(testCase)
devs = synthetic_devices();
hs = make_hybrid_state(devs);
hs.reference_owner_indices = [3; 4];
hs.gfm_reference_resource_indices = [3; NaN];  % island 2 owned by SG
hs.reference_island_ids = [1; 2];
% Device 4 (index 4) must be online and voltage-forming to be an owner.
% Index 4 is an IBR; set it to GFM mode online so it can own island 2.
hs.device_modes.(device_key_for('ConverterBeta')) = 'gfm';
norm = stability.reference_owner_schema(hs, devs, struct());
testCase.verifyFalse(norm.is_single_island);
testCase.verifyEqual(norm.reference_island_ids, [1; 2]);
testCase.verifyEqual(norm.reference_owner_indices, [3; 4]);
testCase.verifyEqual(norm.gfm_reference_resource_indices, [3; NaN]);
% Multi-island scalar alias must be empty (unsupported).
testCase.verifyEmpty(norm.reference_resource_index);
end

function test_schema_alias_mismatch_fails_closed(testCase)
devs = synthetic_devices();
hs = make_hybrid_state(devs);
hs.reference_resource_index = 3;        % legacy says 3
hs.reference_owner_indices = 4;          % canonical says 4
hs.gfm_reference_resource_indices = 4;
hs.reference_island_ids = 1;
hs.device_modes.(device_key_for('ConverterBeta')) = 'gfm';
testCase.verifyError(@() stability.reference_owner_schema(hs, devs, struct()), ...
    'stability:reference_owner_schema:aliasMismatch');
end

function test_schema_alias_points_to_sg_fails_closed(testCase)
devs = synthetic_devices();
hs = make_hybrid_state(devs);
hs.reference_resource_index = 1;        % points to SG (index 1)
hs.reference_owner_indices = 1;
hs.gfm_reference_resource_indices = 1;
hs.reference_island_ids = 1;
testCase.verifyError(@() stability.reference_owner_schema(hs, devs, struct()), ...
    'stability:reference_owner_schema:aliasPointsToSg');
end

function test_schema_cardinality_mismatch_fails_closed(testCase)
devs = synthetic_devices();
hs = make_hybrid_state(devs);
hs.reference_owner_indices = [3; 4];
hs.gfm_reference_resource_indices = [3];   % length mismatch
hs.reference_island_ids = [1; 2];
testCase.verifyError(@() stability.reference_owner_schema(hs, devs, struct()), ...
    'stability:reference_owner_schema:cardinalityMismatch');
end

function test_schema_duplicate_island_fails_closed(testCase)
devs = synthetic_devices();
hs = make_hybrid_state(devs);
hs.reference_owner_indices = [3; 4];
hs.gfm_reference_resource_indices = [3; 4];
hs.reference_island_ids = [1; 1];   % duplicate
hs.device_modes.(device_key_for('ConverterBeta')) = 'gfm';
testCase.verifyError(@() stability.reference_owner_schema(hs, devs, struct()), ...
    'stability:reference_owner_schema:duplicateIsland');
end

function test_schema_owner_offline_fails_closed(testCase)
devs = synthetic_devices();
hs = make_hybrid_state(devs);
% Owner = index 3 (ConverterBeta). Force it offline in runtime hybrid_state.
hs.device_online.(device_key_for('ConverterBeta')) = false;
hs.reference_owner_indices = 3;
hs.gfm_reference_resource_indices = 3;
hs.reference_island_ids = 1;
testCase.verifyError(@() stability.reference_owner_schema(hs, devs, struct()), ...
    'stability:reference_owner_schema:ownerOffline');
end

function test_schema_gfm_ref_not_gfm_capable_fails_closed(testCase)
devs = synthetic_devices();
% Canonical-only (no legacy alias) so aliasMismatch/aliasPointsToSg are
% skipped. Owner = IBR index 3 (online, gfm mode, GFM-capable) passes the
% owner checks; its gfm_reference points to index 1 (SG), which is NOT
% GFM-capable -> gfmRefNotGfm.
hs = make_hybrid_state(devs);
hs.reference_owner_indices = 3;
hs.gfm_reference_resource_indices = 1;  % GFM ref points to SG (not GFM-capable)
hs.reference_island_ids = 1;
% Ensure no legacy alias is set (make_hybrid_state sets it to []).
testCase.verifyEmpty(hs.reference_resource_index);
testCase.verifyError(@() stability.reference_owner_schema(hs, devs, struct()), ...
    'stability:reference_owner_schema:gfmRefNotGfm');
end

function test_schema_empty_canonical_returns_empty(testCase)
devs = synthetic_devices();
hs = make_hybrid_state(devs);
hs = rmfield(hs, 'reference_owner_indices');   % no canonical fields
hs = rmfield(hs, 'gfm_reference_resource_indices');
hs = rmfield(hs, 'reference_island_ids');
hs = rmfield(hs, 'reference_resource_index');
norm = stability.reference_owner_schema(hs, devs, struct());
testCase.verifyEmpty(norm.reference_owner_indices);
testCase.verifyEmpty(norm.reference_island_ids);
testCase.verifyEmpty(norm.gfm_reference_resource_indices);
testCase.verifyEmpty(norm.reference_resource_index);
testCase.verifyEmpty(norm.selected_gfm_indices);
end

% =========================================================================
% Local synthetic fixtures (self-authenticated; no external case dependency)
% =========================================================================

function resources = synthetic_resources()
% 1 SG + 4 dual-mode IBRs (matches IEEE14 1-SG+4-IBR shape without physical params).
% supported_modes uses STRING ARRAYS (not nested cell arrays) so struct-array
% assignment stays homogeneous (cell arrays of differing length would make the
% struct heterogeneous and fail with MATLAB:heterogeneousStrucAssignment).
base = struct('resource_id','','bus_id',0, ...
    'resource_type','sg','model_id','sg_emf6', ...
    'supported_modes',["synchronous","breaker_open"], ...
    'voltage_forming_modes','synchronous','initial_mode','synchronous', ...
    'initial_online',true,'can_switch_mode',true,'can_switch_online',true, ...
    'has_current_limiter',false,'has_frt',false,'can_black_start',false, ...
    'limits',struct(),'ratings',struct(),'dynamic_params',struct(), ...
    'provenance',struct('model','test','source','test contract', ...
    'classification','CASE_DEFINED','details','synthetic unit test'));
resources = repmat(base, 1, 5);
resources(1).resource_id = 'MachineAlpha';
resources(1).bus_id = 101;
names = {'ConverterAlpha','ConverterBeta','ConverterGamma','ConverterDelta'};
for k = 1:4
    resources(k+1).resource_id = names{k};
    resources(k+1).bus_id = 200 + k;
    resources(k+1).resource_type = 'ibr';
    resources(k+1).model_id = 'regfm_b1_dual';
    resources(k+1).supported_modes = ["gfl","gfm","tripped"];
    resources(k+1).voltage_forming_modes = 'gfm';
    resources(k+1).initial_mode = 'gfl';
    resources(k+1).has_current_limiter = true;
    resources(k+1).has_frt = true;
end
end

function devs = synthetic_devices()
resources = synthetic_resources();
devs = repmat(struct(), 1, numel(resources));
for k = 1:numel(resources)
    r = resources(k);
    devs(k).device_id = r.resource_id;
    devs(k).initial_mode = r.initial_mode;
    devs(k).initial_online = r.initial_online;
    devs(k).device_type = r.resource_type;
    caps = struct();
    caps.resource_type = r.resource_type;
    caps.supported_modes = r.supported_modes;
    caps.voltage_forming_modes = r.voltage_forming_modes;
    caps.can_switch_mode = r.can_switch_mode;
    caps.can_switch_online = r.can_switch_online;
    caps.has_current_limiter = r.has_current_limiter;
    caps.has_frt = r.has_frt;
    caps.can_black_start = r.can_black_start;
    devs(k).capabilities = caps;
end
end

function cd = synthetic_case_data()
% Minimal case_data with .mpc (bus/branch/baseMVA) for fingerprint serialization.
mpc = struct();
mpc.baseMVA = 100;
mpc.bus = [1 1 0 0 0 0 1 1.06 0 0 0 0;
           2 2 21.7 12.7 0 0 1 1.045 0 0 0 0;
           3 2 94.2 19.0 0 0 1 1.01 0 0 0 0];
mpc.branch = [1 2 0.01938 0.05917 0.0528 0 0 0 0 0 1;
              1 3 0.05403 0.22304 0.0492 0 0 0 0 0 1];
cd = struct('mpc', mpc);
end

function key = device_key_for(device_id)
% Match the key derivation used by production (sg_event_handler / schema).
key = matlab.lang.makeValidName(char(device_id), 'ReplacementStyle', 'underscore');
end

function hs = make_hybrid_state(devs)
% Build a hybrid_state whose device_online / device_modes reflect a valid
% SG_OFF runtime: SG online+synchronous, IBRs online+gfm (voltage-forming).
% reference_owner_schema reads online/mode from here (runtime state), NOT
% from devices.initial_* (static metadata). Tests that need a different mode
% for a specific device override hs.device_modes.(key) after this call.
hs = struct();
hs.device_online = struct();
hs.device_modes = struct();
for k = 1:numel(devs)
    key = device_key_for(devs(k).device_id);
    hs.device_online.(key) = logical(devs(k).initial_online);
    % Voltage-forming mode so the device can own a reference: SG -> synchronous,
    % IBR -> gfm. (initial_mode for IBRs is 'gfl', which is not voltage-forming.)
    if strcmpi(char(devs(k).device_type), 'sg')
        hs.device_modes.(key) = 'synchronous';
    else
        hs.device_modes.(key) = 'gfm';
    end
end
% Empty canonical reference fields by default.
hs.reference_owner_indices = [];
hs.gfm_reference_resource_indices = [];
hs.reference_island_ids = [];
hs.reference_resource_index = [];
end
