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
% SG_ON has an authenticated online SG reference owner even for all-GFL;
% leaving this alias empty would make mixed_equilibrium_solve ambiguous and
% would violate the SG1 owner contract.  The synthetic table's SG is index 1.
testCase.verifyEqual(cfg.reference_resource_index, 1);
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
% 3-layer fingerprint split (Step A — falsification, RED until Step B)
% =========================================================================
% The fingerprint MUST be split into three layers exposed on the table:
%   selector_input_fingerprint      = hash(immutable inputs + context topology)
%   candidate_evidence_fingerprint  = hash(canonical full candidate evidence)
%   selector_table_fingerprint      = hash(schema_version + input + evidence)
% These tests FAIL against the current single-aggregate table (which exposes
% only selector_table_fingerprint) and turn GREEN when Step B exposes all
% three. They are the layer-change matrix oracle: two structs differing in
% exactly one field must change exactly the expected layers.

function test_table_exposes_three_fingerprint_layers(testCase)
% Gate: the built table must expose all three fingerprint fields, not only
% the aggregate. RED until Step B adds selector_input_fingerprint and
% candidate_evidence_fingerprint as stored table fields.
table = build_synthetic_table();
testCase.verifyTrue(isfield(table, 'selector_table_fingerprint'));
testCase.verifyTrue(isfield(table, 'selector_input_fingerprint'), ...
    'table must expose selector_input_fingerprint (3-layer split).');
testCase.verifyTrue(isfield(table, 'candidate_evidence_fingerprint'), ...
    'table must expose candidate_evidence_fingerprint (3-layer split).');
testCase.verifyTrue(~isempty(table.selector_input_fingerprint));
testCase.verifyTrue(~isempty(table.candidate_evidence_fingerprint));
testCase.verifyTrue(~isempty(table.selector_table_fingerprint));
% The three are distinct hashes (input != evidence != aggregate).
testCase.verifyNotEqual(table.selector_input_fingerprint, ...
    table.candidate_evidence_fingerprint);
testCase.verifyNotEqual(table.selector_table_fingerprint, ...
    table.selector_input_fingerprint);
testCase.verifyNotEqual(table.selector_table_fingerprint, ...
    table.candidate_evidence_fingerprint);
end

function test_table_exposes_schema_version(testCase)
% Gate: the closed auth envelope carries an explicit schema version so a
% bump invalidates cross-version tables. RED until Step B.
table = build_synthetic_table();
testCase.verifyTrue(isfield(table, 'selector_schema_version'));
testCase.verifyEqual(table.selector_schema_version, 'selector_table_v2');
end

function test_fingerprint_layers_deterministic_for_identical_inputs(testCase)
% Gate: identical inputs -> identical all-three layers (determinism).
t1 = build_synthetic_table();
t2 = build_synthetic_table();
testCase.verifyEqual(t1.selector_input_fingerprint, t2.selector_input_fingerprint);
testCase.verifyEqual(t1.candidate_evidence_fingerprint, t2.candidate_evidence_fingerprint);
testCase.verifyEqual(t1.selector_table_fingerprint, t2.selector_table_fingerprint);
end

function test_topology_mutation_changes_input_and_table_only(testCase)
% Layer-change matrix oracle: a topology (branch) change must change
% selector_input_fingerprint AND selector_table_fingerprint, but NOT
% candidate_evidence_fingerprint (the candidate universe is unchanged
% when only the immutable network data changes).
% NOTE: changing branch data may also alter which candidates are feasible
% (equilibrium/SCR depend on topology); to isolate the LAYER that changed,
% this test mutates a branch reactance by a tiny amount on a
% structural-only path (no mpc-derived evaluator) so the candidate set is
% structurally the same. RED until Step B exposes the split.
cd1 = synthetic_case_data();
cd2 = synthetic_case_data();
cd2.mpc.branch(1,3) = cd2.mpc.branch(1,3) + 0.5;  % topology mutation
resources = synthetic_resources();
scenario = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {resource_ids_for()}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
t1 = stability.ibr_selector_table(cd1, resources, scenario, opt);
t2 = stability.ibr_selector_table(cd2, resources, scenario, opt);
testCase.verifyNotEqual(t1.selector_input_fingerprint, t2.selector_input_fingerprint);
testCase.verifyNotEqual(t1.selector_table_fingerprint, t2.selector_table_fingerprint);
% Evidence (candidate universe) is unaffected by a pure topology change
% on the structural-only path:
testCase.verifyEqual(t1.candidate_evidence_fingerprint, ...
    t2.candidate_evidence_fingerprint);
end

function test_candidate_mutation_changes_evidence_and_table_only(testCase)
% Layer-change matrix oracle: a candidate-evidence mutation (different
% selected GFM set) must change candidate_evidence_fingerprint AND
% selector_table_fingerprint, but NOT selector_input_fingerprint (the
% immutable inputs are unchanged).
resources = synthetic_resources();
scenario = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {resource_ids_for()}));
opt1 = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
opt2 = struct('sg_off', struct('n_gfm_required', 2), ...
    'sg_on', struct('n_gfm_required', 0));
cd = synthetic_case_data();
t1 = stability.ibr_selector_table(cd, resources, scenario, opt1);
t2 = stability.ibr_selector_table(cd, resources, scenario, opt2);
% Different n_gfm_required -> different candidate universe -> different evidence.
testCase.verifyNotEqual(t1.candidate_evidence_fingerprint, ...
    t2.candidate_evidence_fingerprint);
testCase.verifyNotEqual(t1.selector_table_fingerprint, t2.selector_table_fingerprint);
% Immutable inputs (bus/branch/baseMVA/resources/dispatch/gamma_req) unchanged:
testCase.verifyEqual(t1.selector_input_fingerprint, t2.selector_input_fingerprint);
end

function test_no_candidate_field_serializes_as_unknown_marker(testCase)
% Gate: the shared canonical serializer must NOT collapse any commit-
% relevant candidate field to '?' (the lossy path in the prior local
% struct_to_str). Every cell/struct field must participate deterministically.
% RED until Step B routes evidence through the shared serializer.
table = build_synthetic_table();
% Round-trip: rebuild the evidence fingerprint from the table's own
% configurations and confirm it matches the stored value. If any field
% serializes as '?', two tables differing in that field would collide.
cfgs_off = table.sg_off.configurations;
cfgs_on = table.sg_on.configurations;
evidence = struct( ...
    'sg_off_universe', config_array_to_str_shared(cfgs_off), ...
    'sg_on_universe', config_array_to_str_shared(cfgs_on));
[~, ~, ev_fp] = compute_selector_table_fingerprint(struct(), evidence);
testCase.verifyEqual(table.candidate_evidence_fingerprint, ev_fp);
end

function table = build_synthetic_table()
cd = synthetic_case_data();
resources = synthetic_resources();
scenario = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {resource_ids_for()}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
table = stability.ibr_selector_table(cd, resources, scenario, opt);
end

function s = config_array_to_str_shared(cfgs)
% Deterministic serialization of the candidate array, mirroring the
% shared canonical serializer. Used by the round-trip test to prove the
% stored evidence fingerprint matches a fresh recompute from the table's
% own configurations (no '?' collapse).
if isempty(cfgs)
    s = 'none';
    return;
end
parts = cell(1, numel(cfgs));
for i = 1:numel(cfgs)
    parts{i} = scalar_struct_to_str_shared(cfgs(i));
end
s = strjoin(parts, ';');
end

function s = scalar_struct_to_str_shared(st)
% Recursive canonical serialization (numeric/char/string/logical/cell/
% struct scalar + array/complex). Must match the shared implementation in
% internal/compute_selector_table_fingerprint exactly; if it drifts the
% round-trip test fails and flags the divergence.
if ~isstruct(st) || isempty(st)
    s = '';
    return;
end
fns = sort(fieldnames(st));
parts = {};
for k = 1:numel(fns)
    v = st.(fns{k});
    f = fns{k};
    if isnumeric(v)
        if ~isreal(v)
            parts{end+1} = sprintf('%s=(re=%s,im=%s)', f, ...
                mat2str(real(v(:)')), mat2str(imag(v(:)'))); %#ok<AGROW>
        else
            parts{end+1} = sprintf('%s=%s', f, mat2str(v(:)')); %#ok<AGROW>
        end
    elseif ischar(v)
        parts{end+1} = sprintf('%s=%s', f, v); %#ok<AGROW>
    elseif isstring(v)
        parts{end+1} = sprintf('%s=%s', f, char(v)); %#ok<AGROW>
    elseif islogical(v)
        parts{end+1} = sprintf('%s=%d', f, v); %#ok<AGROW>
    elseif iscell(v)
        parts{end+1} = sprintf('%s=[%s]', f, cell_to_str_shared(v)); %#ok<AGROW>
    elseif isstruct(v) && isscalar(v)
        parts{end+1} = sprintf('%s={%s}', f, scalar_struct_to_str_shared(v)); %#ok<AGROW>
    elseif isstruct(v) && ~isscalar(v)
        elems = cell(1, numel(v));
        for i = 1:numel(v)
            elems{i} = scalar_struct_to_str_shared(v(i));
        end
        parts{end+1} = sprintf('%s=[%s]', f, strjoin(elems, ';')); %#ok<AGROW>
    else
        parts{end+1} = sprintf('%s=?', f); %#ok<AGROW>
    end
end
s = strjoin(parts, ',');
end

function s = cell_to_str_shared(c)
if isempty(c)
    s = '';
    return;
end
elems = cell(1, numel(c));
for i = 1:numel(c)
    v = c{i};
    if isnumeric(v)
        elems{i} = mat2str(v(:)');
    elseif ischar(v)
        elems{i} = v;
    elseif isstring(v)
        elems{i} = char(v);
    elseif islogical(v)
        elems{i} = sprintf('%d', v);
    else
        elems{i} = '?';
    end
end
s = strjoin(elems, '/');
end

% =========================================================================
% Single-island build gate (Step C — island_components)
% =========================================================================
% The table builder must call stability.island_components on the build-time
% topology and fail closed (multiIslandUnsupported) when more than one
% ENERGIZED island exists, BEFORE any candidate enumeration. An isolated bus
% with no load/shunt/resource is de-energized and does NOT count.

function test_single_energized_island_builds_ok(testCase)
% Gate: a connected 1-island network with one loaded bus builds successfully
% and records exactly one energized island.
cd = synthetic_case_data();
resources = synthetic_resources();
scenario = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {resource_ids_for()}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
table = stability.ibr_selector_table(cd, resources, scenario, opt);
testCase.verifyEqual(table.energized_island_count, 1);
testCase.verifyEqual(numel(table.reference_island_ids), 1);
testCase.verifyTrue(isfield(table, 'build_islands'));
end

function test_dead_isolated_bus_does_not_count_as_energized(testCase)
% Gate: a network with one energized island PLUS one dead isolated bus
% (no load/shunt/resource) reports exactly ONE energized island. The dead
% bus is its own (de-energized) component but must NOT trip the multi-island
% gate. Independent oracle: hand-built 3-bus Y where bus 3 is isolated
% (off-diagonal zeros) and has Pd=Qd=Gs=Bs=0.
nb = 3;
Y = zeros(nb);
Y(1,2) = -1/(0.01938 + 1i*0.05917); Y(2,1) = Y(1,2);
Y(1,1) =  1/(0.01938 + 1i*0.05917) + 1i*0.0528/2;
Y(2,2) =  1/(0.01938 + 1i*0.05917) + 1i*0.0528/2;
Y(3,3) = 0;
mpc = struct();
mpc.baseMVA = 100;
mpc.bus = [1 1 0   0   0 0 1 1.06 0 0 0 0;   % slack, no load/shunt
           2 2 21.7 12.7 0 0 1 1.045 0 0 0 0; % load -> energized
           3 1 0   0   0 0 1 1.0   0 0 0 0]; % isolated, no load/shunt
mpc.branch = [1 2 0.01938 0.05917 0.0528 0 0 0 0 0 1]; % only branch 1-2
cd = struct('mpc', mpc);
resources = synthetic_resources();
scenario = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {resource_ids_for()}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
table = stability.ibr_selector_table(cd, resources, scenario, opt);
% Bus 2 has load -> energized. Bus 3 isolated + no load/shunt -> de-energized.
testCase.verifyEqual(table.energized_island_count, 1);
testCase.verifyEqual(numel(table.reference_island_ids), 1);
end

function test_two_energized_islands_fail_closed(testCase)
% Gate: two electrically separated components BOTH carrying load -> 2 energized
% islands -> must FAIL CLOSED with multiIslandUnsupported BEFORE any candidate
% enumeration (independent oracle: two disconnected loaded subgraphs).
nb = 4;
Y = zeros(nb);
% Component A: buses 1-2 connected, bus 2 has load
Y(1,2) = -1/(0.01938 + 1i*0.05917); Y(2,1) = Y(1,2);
Y(1,1) =  1/(0.01938 + 1i*0.05917);
Y(2,2) =  1/(0.01938 + 1i*0.05917);
% Component B: buses 3-4 connected, bus 4 has load
Y(3,4) = -1/(0.05403 + 1i*0.22304); Y(4,3) = Y(3,4);
Y(3,3) =  1/(0.05403 + 1i*0.22304);
Y(4,4) =  1/(0.05403 + 1i*0.22304);
mpc = struct();
mpc.baseMVA = 100;
mpc.bus = [1 1 0   0   0 0 1 1.06 0 0 0 0;
           2 2 21.7 12.7 0 0 1 1.045 0 0 0 0;
           3 1 0   0   0 0 1 1.0   0 0 0 0;
           4 2 94.2 19.0 0 0 1 1.01  0 0 0 0];
mpc.branch = [1 2 0.01938 0.05917 0.0528 0 0 0 0 0 1;
              3 4 0.05403 0.22304 0.0492 0 0 0 0 0 1];
cd = struct('mpc', mpc);
resources = synthetic_resources();
scenario = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {resource_ids_for()}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
testCase.verifyError(@() stability.ibr_selector_table(cd, resources, scenario, opt), ...
    'stability:ibr_selector_table:multiIslandUnsupported');
end

function test_actual_island_id_recorded_not_literal_one(testCase)
% Gate: the table records the actual BFS-derived island ID (sorted by min bus
% position), NOT a hardcoded literal. For the synthetic topology the energized
% island must have island_id == 1 (single island), and the table's
% reference_island_ids must match the build_islands struct.
cd = synthetic_case_data();
resources = synthetic_resources();
scenario = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {resource_ids_for()}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
table = stability.ibr_selector_table(cd, resources, scenario, opt);
testCase.verifyEqual(numel(table.build_islands), table.energized_island_count);
testCase.verifyEqual(table.reference_island_ids, [table.build_islands.island_id]);
end

function test_inconsistent_ybus_mpc_branch_fails_closed(testCase)
% Gate: if mpc.branch lists a branch that the build-time Ybus did NOT join
% (Ybus off-diagonal below tol), island_components raises ybusBranchInconsistent
% and the builder must NOT suppress it. Independent oracle: branch row 2->3
% with branch STATUS = 0 (col 11). canonical_ybus_from_mpc skips status-0
% rows (Ybus(2,3) == 0), but island_components cross-checks ALL branch rows
% regardless of status -> raises ybusBranchInconsistent.
cd = synthetic_case_data();
cd.mpc.branch(end+1, :) = [2 3 0.01 0.01 0.01 0 0 0 0 0 0]; % status=0 -> Ybus skip
resources = synthetic_resources();
scenario = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {resource_ids_for()}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
testCase.verifyError(@() stability.ibr_selector_table(cd, resources, scenario, opt), ...
    'stability:island_components:ybusBranchInconsistent');
end

% =========================================================================
% Runtime rerank + ranker fail-closed contract (Step D, Q2 minimum set)
% =========================================================================
% These tests exercise stability.runtime_rerank_candidates directly with
% synthetic configurations and an identity-aligned runtime_context. They
% assert the corrected post-fix behavior (advisor Q2, Revision 4): rejected
% rows are removed before sorting, incomplete context returns EMPTY (not the
% nonempty input), and the ranker derives the resource count from the context
% (not from numel(configurations)).

function test_rejected_build_winner_excluded_runner_up_wins(testCase)
% Gate: when the build-time winner is runtime-blocked (held IBR on a required
% transition), it must be EXCLUDED and a compatible runner-up returned as the
% runtime winner. Independent oracle: explicit transition count + sortrows.
% This is the regression guard for defect 2 (rejected rows returned).
baseline = repmat({'gfl'}, 1, 5);            % all GFL at event left
c1 = make_candidate([2], baseline, 0.3, true); % selects IBR2, higher margin (build winner)
c2 = make_candidate([3], baseline, 0.2, true); % selects IBR3, lower margin
cands = [c1, c2];
rc = make_runtime_context(baseline);
rc.hold_timers(2) = 5;                       % IBR2 held -> c1 requires transition + blocked
[ranked, ~, rr] = stability.runtime_rerank_candidates(cands, rc);
testCase.verifyEqual(numel(ranked), 1);        % c1 excluded, only c2 survives
testCase.verifyEqual(ranked(1).selected_gfm_indices, [3]); % runner-up is commit authority
testCase.verifyTrue(any(strcmp(rr, 'holdTimerBlocksRequiredTransition')));
end

function test_rejected_rows_removed_from_returned_ranking(testCase)
% Gate: rejected rows must be removed BEFORE sorting, not merely annotated.
% Independent oracle: count survivors vs inputs.
baseline = repmat({'gfl'}, 1, 5);
c1 = make_candidate([2], baseline, 0.3, true);  % build winner, held -> blocked
c2 = make_candidate([3], baseline, 0.2, true);
c3 = make_candidate([4], baseline, 0.1, true);
cands = [c1, c2, c3];
rc = make_runtime_context(baseline);
rc.hold_timers(2) = 5;                          % blocks c1 only
[ranked, ~, rr] = stability.runtime_rerank_candidates(cands, rc);
testCase.verifyEqual(numel(ranked), 2);           % c1 excluded; c2, c3 survive
testCase.verifyEqual(ranked(1).selected_gfm_indices, [3]);
testCase.verifyEqual(ranked(2).selected_gfm_indices, [4]);
testCase.verifyEqual(numel(rr), 1);               % only c1's rejection reason retained
end

function test_incomplete_context_returns_empty_not_input(testCase)
% Gate: incomplete runtime context fails closed returning an EMPTY ranked
% array (defect 3 fix), NOT the nonempty input. A caller checking
% isempty(ranked) must see true. Independent oracle: numel(ranked)==0.
baseline = repmat({'gfl'}, 1, 5);
c1 = make_candidate([2], baseline, 0.3, true);
cands = c1;
rc = struct('device_modes', {baseline}); % missing hold/lockout/event_time/online/eligible
[ranked, order_key, rr] = stability.runtime_rerank_candidates(cands, rc);
testCase.verifyEqual(numel(ranked), 0);    % EMPTY, not the 1-element input
testCase.verifyEmpty(order_key);
testCase.verifyEqual(numel(rr), 1);
testCase.verifyTrue(startsWith(rr{1}, 'missingRuntimeContext:'));
end

function test_resource_count_derived_from_context_not_candidate_count(testCase)
% Gate: the ranker derives the resource count from numel(rc.device_modes)
% (defect 1 fix), NOT from numel(configurations). A context with N=5
% resources but only 2 candidates must process normally (the old code would
% have errored with runtimeContextDeviceCountMismatch because 5 ~= 2).
baseline = repmat({'gfl'}, 1, 5);  % 5 resources (1 SG + 4 IBRs)
c1 = make_candidate([2], baseline, 0.3, true);
c2 = make_candidate([3], baseline, 0.2, true);
cands = [c1, c2];                   % 2 candidates < 5 resources
rc = make_runtime_context(baseline);
[ranked, ~, ~] = stability.runtime_rerank_candidates(cands, rc);
testCase.verifyEqual(numel(ranked), 2); % both compatible, context correctly sized
end

function test_held_device_already_in_desired_mode_stays_admissible(testCase)
% Gate (advisor finding #8): a held IBR ALREADY in the candidate's desired
% mode must NOT be rejected. No transition required -> hold is irrelevant.
% Independent oracle: the in-mode resource has baseline == candidate mode.
baseline = {'synchronous','gfm','gfl','gfl','gfl'}; % IBR2 already GFM
c1 = make_candidate([2], baseline, 0.3, true);        % selects IBR2 (it's GFM -> no transition)
cands = c1;
rc = make_runtime_context(baseline);
rc.hold_timers(2) = 5;                                % IBR2 held, but no transition required
[ranked, ~, ~] = stability.runtime_rerank_candidates(cands, rc);
testCase.verifyEqual(numel(ranked), 1);               % held-in-mode is admissible
testCase.verifyEqual(ranked(1).selected_gfm_indices, [2]);
end

function test_lockout_at_event_time_is_allowed_matches_handler(testCase)
% Gate: lockout semantics must match sg_event_handler.m:538 (value > timestamp
% blocks; value <= timestamp allowed). lockout == event_time is allowed.
baseline = repmat({'gfl'}, 1, 5);
c1 = make_candidate([2], baseline, 0.3, true);
cands = c1;
rc = make_runtime_context(baseline);
rc.event_time = 10.0;
rc.lockout_timers(2) = 10.0; % == event_time -> allowed (handler: value > timestamp blocks)
[ranked, ~, ~] = stability.runtime_rerank_candidates(cands, rc);
testCase.verifyEqual(numel(ranked), 1);
rc.lockout_timers(2) = 10.001; % > event_time -> blocked
[ranked, ~, rr] = stability.runtime_rerank_candidates(cands, rc);
testCase.verifyEqual(numel(ranked), 0);
testCase.verifyTrue(any(strcmp(rr, 'lockoutBlocksRequiredTransition')));
end

function test_margin_ordering_is_numeric_not_string(testCase)
% Gate: margin ordering uses numeric -margin (ascending), NOT lexicographic
% string sort. A margin of 0.2 must outrank 0.1 (regression guard for the
% margin-string-sort bug, advisor finding #1). Independent oracle: explicit
% -margin comparison.
baseline = repmat({'gfl'}, 1, 5);
c1 = make_candidate([2], baseline, 0.1, true); % margin 0.1
c2 = make_candidate([3], baseline, 0.2, true); % margin 0.2 (larger -> outranks)
cands = [c1, c2]; % c1 first in input order
rc = make_runtime_context(baseline);
[ranked, ~, ~] = stability.runtime_rerank_candidates(cands, rc);
testCase.verifyEqual(ranked(1).selected_gfm_indices, [3]); % margin 0.2 first
testCase.verifyEqual(ranked(2).selected_gfm_indices, [2]);
end

function test_no_survivors_returns_empty_not_rejected_first(testCase)
% Gate: when ALL candidates are runtime-incompatible, the ranker returns an
% EMPTY ranked array, never a rejected-looking first row.
baseline = repmat({'gfl'}, 1, 5);
c1 = make_candidate([2], baseline, 0.3, true);
c2 = make_candidate([3], baseline, 0.2, true);
cands = [c1, c2];
rc = make_runtime_context(baseline);
rc.hold_timers(2) = 5;  % blocks c1
rc.hold_timers(3) = 5;  % blocks c2
[ranked, order_key, ~] = stability.runtime_rerank_candidates(cands, rc);
testCase.verifyEqual(numel(ranked), 0);
testCase.verifyEmpty(order_key);
end

function test_eligible_mode_length_mismatch_rejected(testCase)
% Gate: a candidate whose modes vector length does not match the resource
% count (n_res from context) is rejected with candidateModeCountMismatch.
% Independent oracle: 5-resource context vs a 3-mode candidate.
baseline = repmat({'gfl'}, 1, 5);
c1 = make_candidate([2], baseline, 0.3, true);
c1.modes = {'gfm','gfl','gfl'}; % wrong length (3, not 5)
cands = c1;
rc = make_runtime_context(baseline);
[ranked, ~, rr] = stability.runtime_rerank_candidates(cands, rc);
testCase.verifyEqual(numel(ranked), 0);
testCase.verifyTrue(any(strcmp(rr, 'candidateModeCountMismatch')));
end

function c = make_candidate(selected, baseline_modes, margin, feasible)
% Build a synthetic runtime-rerank candidate. selected = IBR indices that are
% GFM; all other resources stay 'gfl'. margin and feasibility are set
% explicitly. selected must be a row vector.
if nargin < 4, feasible = true; end
n_res = numel(baseline_modes);
c = struct();
c.selected_gfm_indices = selected(:)';
c.n_gfm_required = numel(c.selected_gfm_indices);
c.feasible = feasible;
c.margin = margin;
c.n_mode_changes = 0;   % ranker recomputes this; stored value unused
c.tie_break = '';
c.reason = '';
c.failure_id = '';
c.modes = repmat({'gfl'}, 1, n_res);
c.modes(c.selected_gfm_indices) = {'gfm'};
end

function rc = make_runtime_context(baseline_modes)
% Build an identity-aligned runtime_context for the 5-resource (1 SG + 4 IBRs)
% case. SG (index 1) is NOT eligible; all IBRs are eligible dual-mode.
% baseline_modes: cell(1,N) committed event-left modes. event_time = 10.0.
% hold/lockout default to unblocked; device_online defaults to all true.
n_res = numel(baseline_modes);
rc = struct();
rc.device_modes = baseline_modes;
rc.device_online = true(1, n_res);
rc.hold_timers = zeros(1, n_res);
rc.lockout_timers = -inf(1, n_res);
rc.event_time = 10.0;
rc.eligible_mask = [false, true(1, n_res - 1)];
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

% =========================================================================
% ONE real pinned manual SG_OFF physical integration (Step J)
% =========================================================================
% Builds the REAL IEEE14 selector table ONCE, SG_OFF pinned to n_gfm_required=4
% reference=2, and asserts the authenticated candidate. LABEL accurately: this
% is a MANUAL pinned physical integration and does NOT prove automatic
% multi-count readiness (that gate is Phase 7). It verifies: candidate present
% and correct, ready, margin/omega recorded, 3-layer fingerprints populated,
% single-island build gate passes, and the validator accepts the unchanged
% post-fault-clear live topology.

function test_real_ieee14_pinned_manual_sg_off_integration(testCase)
% LABEL: MANUAL pinned SG_OFF physical integration (not automatic readiness).
s = cases.scenario_ieee14_1sg_4ibr();
[devices, ~] = stability.build_mixed_resource_devices(s.case_data, s.resources, s.scenario_opt);
eq = stability.mixed_equilibrium_solve(s.case_data, struct('devices', devices), struct('verbose', false));
testCase.assertTrue(eq.converged, eq.failure_reason);
table_opt = struct();
table_opt.sg_off = struct('n_gfm_required', 4, 'reference_resource_index', 2);
table_opt.sg_on = struct('n_gfm_required', 0);
table = stability.ibr_selector_table(s.case_data, s.resources, s, table_opt);
% Candidate [2 3 4 5], ref=2, n=4 present AND ready.
testCase.verifyTrue(isfield(table, 'sg_off'));
sel = table.sg_off.selected_config;
testCase.verifyEqual(sort(sel.selected_gfm_indices), [2 3 4 5]);
testCase.verifyEqual(sel.reference_resource_index, 2);
testCase.verifyEqual(sel.n_gfm_required, 4);
testCase.verifyTrue(sel.ready_to_commit);
testCase.verifyTrue(isfinite(sel.margin));
testCase.verifyTrue(isfinite(sel.omega));
testCase.verifyEqual(sel.fd_eps_values,3e-6*[0.5 1 2],'AbsTol',0);
testCase.verifyTrue(all(isfinite(sel.fd_omegas)));
testCase.verifyTrue(sel.fd_classification_consistent);
testCase.verifyTrue(sel.fd_robust_margin_pass);
testCase.verifyEqual(sel.omega,max(sel.fd_omegas),'AbsTol',0);
% 3-layer fingerprints populated.
testCase.verifyTrue(isfield(table, 'selector_input_fingerprint') && ~isempty(table.selector_input_fingerprint));
testCase.verifyTrue(isfield(table, 'candidate_evidence_fingerprint') && ~isempty(table.candidate_evidence_fingerprint));
testCase.verifyTrue(isfield(table, 'selector_table_fingerprint') && ~isempty(table.selector_table_fingerprint));
testCase.verifyEqual(table.selector_schema_version, 'selector_table_v2');
% Closed auth envelope present.
testCase.verifyTrue(isfield(table, 'selector_auth_inputs') && isstruct(table.selector_auth_inputs));
% Single-island build gate: exactly one energized island, reference_island_ids recorded.
testCase.verifyEqual(table.energized_island_count, 1);
testCase.verifyFalse(isempty(table.reference_island_ids));
end

function test_real_ieee14_validator_accepts_unchanged_live_topology(testCase)
% Gate: validator accepts the authenticated table when the live topology
% (post-fault-clear canonical Y) matches the build topology — i.e. the
% no-drift case authenticates. Uses real IEEE14 devices + a synthetic
% identity-aligned runtime_context and the validator's manual_override path.
s = cases.scenario_ieee14_1sg_4ibr();
[devices, ~] = stability.build_mixed_resource_devices(s.case_data, s.resources, s.scenario_opt);
eq = stability.mixed_equilibrium_solve(s.case_data, struct('devices', devices), struct('verbose', false));
testCase.assertTrue(eq.converged, eq.failure_reason);
table_opt = struct();
table_opt.sg_off = struct('n_gfm_required', 4, 'reference_resource_index', 2);
table_opt.sg_on = struct('n_gfm_required', 0);
table = stability.ibr_selector_table(s.case_data, s.resources, s, table_opt);
% Use the BUILD-TIME topology_payload stored in the table: this is the exact
% canonical Ybus the input fingerprint was built from. Feeding it back through
% the validator must reproduce the stored input fingerprint (no-drift case ->
% auth passes). This is the round-trip self-consistency contract, and avoids
% duplicating the Ybus builder inside the test.
Ytopo = [];
if isfield(table, 'selector_auth_inputs') && isstruct(table.selector_auth_inputs) && ...
        isfield(table.selector_auth_inputs, 'topology_payload')
    Ytopo = table.selector_auth_inputs.topology_payload;
end
testCase.verifyFalse(isempty(Ytopo));
% Synthetic identity-aligned runtime_context matching dae.devices order.
n = numel(devices);
device_modes = repmat({'gfl'}, 1, n);
device_online = true(1, n);
hold_timers = zeros(1, n);
lockout_timers = -inf(1, n);
eligible = false(1, n);
for k = 1:n
    caps = struct();
    if isfield(devices(k), 'capabilities') && isstruct(devices(k).capabilities)
        caps = devices(k).capabilities;
    end
    rt = ''; if isfield(caps, 'resource_type'), rt = lower(char(caps.resource_type)); end
    csw = false; if isfield(caps, 'can_switch_mode'), csw = logical(caps.can_switch_mode); end
    sup = {}; if isfield(caps, 'supported_modes'), sup = caps.supported_modes; end
    if strcmp(rt, 'ibr') && csw && any(strcmpi(string(sup), 'gfl')) && any(strcmpi(string(sup), 'gfm'))
        eligible(k) = true;
    end
end
runtime_context = struct('device_modes', {device_modes}, 'device_online', device_online, ...
    'hold_timers', hold_timers, 'lockout_timers', lockout_timers, ...
    'event_time', 10.0, 'eligible_mask', eligible);
% Build the dae (required by the validator).
dae = stability.composite_dae(s.case_data, eq.devices, struct('load_model', 'cz_p_cz_q'));
% manual_override path with the pinned tuple.
req = struct('mode', 'manual_override', 'manual_candidate', struct( ...
    'selected_gfm_indices', [2 3 4 5], 'n_gfm_required', 4, 'reference_resource_index', 2));
sched = struct();
[ok, err_id, ~, ~, cand] = stability.validate_runtime_candidate_compatibility( ...
    table, req, dae, sched, 'sg_off', Ytopo, runtime_context);
testCase.verifyTrue(ok, sprintf('validator rejected unchanged topology: %s', err_id));
testCase.verifyEqual(sort(cand.selected_gfm_indices), [2 3 4 5]);
testCase.verifyEqual(cand.reference_resource_index, 2);
testCase.verifyTrue(cand.ready_to_commit);
end
