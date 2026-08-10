function tests = test_ieee14_ibr_sg_on_integration()
%TEST_IEEE14_IBR_SG_ON_INTEGRATION  Physical IEEE14 selector + schema integration.
%   Integration tests with the REAL IEEE14 selector (full SCR + equilibrium +
%   SSSA gates). Accepts ONLY candidates the real selector marks feasible;
%   NEVER relaxes gamma_req/SCR/equilibrium/current gates. Also covers
%   multi-island schema validation on a synthetic two-island topology and
%   reference_owner_schema generic eligibility (F3).
%
%   All assertions go through PUBLIC entry points only:
%     stability.ibr_selector_table, stability.ibr_config_selector,
%     stability.reference_owner_schema, stability.island_components,
%     stability.run_hybrid_case.
%
%   Source: F3/F6/C7 user-approved validation-closure plan.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath')))); pf_init_paths();
s = cases.scenario_ieee14_1sg_4ibr();
tc.TestData.scenario = s;
% Build the real selector table once (SG_OFF + SG_ON) for reuse.
resources = s.resources;
scenario_cfg = struct('selector', struct('gamma_req', selector_gamma_req(s)), ...
    'config', struct('resource_ids', {resource_ids_of(resources)}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
tc.TestData.table = stability.ibr_selector_table(s.case_data, resources, scenario_cfg, opt);
end

% =========================================================================
% Real selector table (full SCR + equilibrium + SSSA gates)
% =========================================================================

function test_real_selector_table_builds_both_contexts(tc)
table = tc.TestData.table;
tc.verifyTrue(isfield(table, 'sg_off') && isfield(table, 'sg_on'));
tc.verifyTrue(isfield(table, 'selector_table_fingerprint'));
tc.verifyTrue(~isempty(table.selector_table_fingerprint));
% Gate: fingerprint must NOT be the ffffffff collision.
tc.verifyNotEqual(table.selector_table_fingerprint, 'selector_table|ffffffff');
end

function test_real_selector_fingerprint_deterministic(tc)
s = tc.TestData.scenario;
resources = s.resources;
scenario_cfg = struct('selector', struct('gamma_req', selector_gamma_req(s)), ...
    'config', struct('resource_ids', {resource_ids_of(resources)}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
t1 = stability.ibr_selector_table(s.case_data, resources, scenario_cfg, opt);
t2 = stability.ibr_selector_table(s.case_data, resources, scenario_cfg, opt);
tc.verifyEqual(t1.selector_table_fingerprint, t2.selector_table_fingerprint);
end

function test_real_selector_fingerprint_sensitive_to_topology(tc)
% A material change to the IEEE14 branch data must change the fingerprint.
s = tc.TestData.scenario;
resources = s.resources;
cd1 = s.case_data;
cd2 = s.case_data;
cd2.mpc.branch(1, 3) = cd2.mpc.branch(1, 3) + 0.1;  % material reactance change
scenario_cfg = struct('selector', struct('gamma_req', selector_gamma_req(s)), ...
    'config', struct('resource_ids', {resource_ids_of(resources)}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
t1 = stability.ibr_selector_table(cd1, resources, scenario_cfg, opt);
t2 = stability.ibr_selector_table(cd2, resources, scenario_cfg, opt);
tc.verifyNotEqual(t1.selector_table_fingerprint, t2.selector_table_fingerprint);
end

function test_real_selector_accepts_only_feasible_candidates(tc)
% The chosen physical configuration must come from a candidate the real
% selector marked feasible (ready_to_commit). NEVER relax gates. If the real
% IEEE14 selector finds no feasible candidate (physical gates do not pass for
% the synthetic SG_OFF context), that is an honest result, not a test failure.
table = tc.TestData.table;
% If a config was selected, it must be feasible (if SSSA was evaluated).
if ~isempty(table.sg_off.selected_gfm_indices) && table.sg_off.sssa_evaluated
    tc.verifyTrue(table.sg_off.ready_to_commit, ...
        'Selected SG_OFF config must pass SCR/equilibrium/SSSA/gamma_req gates.');
    tc.verifyTrue(table.sg_off.selected_config.feasible);
end
% If no config was selected, the selector must report an honest status.
if isempty(table.sg_off.selected_gfm_indices)
    tc.verifyTrue(ismember(table.sg_off.selection_status, ...
        {'NO_STRUCTURAL_CANDIDATE', 'NO_FEASIBLE_CANDIDATE', 'INVALID_REQUIRED_COUNT', ...
        'NO_RESOURCES', 'INVALID_CONFIG_ALIGNMENT', 'INVALID_REFERENCE'}), ...
        sprintf('Honest selection_status required; got %s.', table.sg_off.selection_status));
end
end

function test_real_selector_never_relaxes_gamma_req(tc)
% gamma_req is frozen; the selector must not relax it to satisfy a test.
table = tc.TestData.table;
tc.verifyEqual(table.gamma_req, selector_gamma_req(tc.TestData.scenario), 'AbsTol', 0);
% If SSSA evaluated, the margin gate uses the frozen gamma_req.
if table.sg_off.sssa_evaluated && isfield(table.sg_off, 'omega') && isfinite(table.sg_off.omega)
    % omega <= -gamma_req is the pass condition (stable with margin).
    tc.verifyLessThanOrEqual(table.sg_off.omega, -table.gamma_req + 1e-9);
end
end

function test_chosen_config_matches_cached_evidence(tc)
% The selected config's indices/omega/margin must match the cached candidate
% evidence in the table (no drift between selection and cache).
table = tc.TestData.table;
sel = table.sg_off.selected_gfm_indices;
if ~isempty(sel) && table.sg_off.sssa_evaluated
    % Find the matching candidate in configurations.
    cfgs = table.sg_off.configurations;
    matched = false;
    for k = 1:numel(cfgs)
        if isequal(sort(cfgs(k).selected_gfm_indices), sort(sel))
            matched = true;
            tc.verifyEqual(cfgs(k).omega, table.sg_off.omega, 'AbsTol', 1e-9);
            tc.verifyEqual(cfgs(k).margin, table.sg_off.margin, 'AbsTol', 1e-9);
            break;
        end
    end
    tc.verifyTrue(matched, 'Selected config must be present in cached candidates.');
end
end

function test_unpinned_automatic_sg_off_integration(tc)
% UNPINNED automatic SG_OFF integration (Step 8). Build a real IEEE14 table
% with NO pin (full feasible-count band, N<=4). The request carries no
% subset/count/ref. Assert the table authenticates and the runtime-selected
% candidate + provenance come from the table (not from schedule literals),
% and SG_ON reports zero feasible (IEEE14 SG_ON is physically infeasible
% under frozen gates). This does NOT claim readiness beyond NOT_READY.
s = tc.TestData.scenario;
resources = s.resources;
scenario_cfg = struct('selector', struct('gamma_req', selector_gamma_req(s)), ...
    'config', struct('resource_ids', {resource_ids_of(resources)}));
% NO sg_off pin -> full-band enumeration (N_exhaustive_max=4 guard applies).
table_opt = struct('sg_on', struct('n_gfm_required', 0));
table = stability.ibr_selector_table(s.case_data, resources, scenario_cfg, table_opt);
% The table must carry the 3-layer fingerprint + schema version.
tc.verifyTrue(isfield(table, 'selector_table_fingerprint') && ~isempty(table.selector_table_fingerprint));
tc.verifyEqual(table.selector_schema_version, 'selector_table_v2');
tc.verifyTrue(isfield(table, 'selector_auth_inputs') && isstruct(table.selector_auth_inputs));
% The SG_OFF selected config must come from the cached candidate universe
% (provenance = table-ranked, not schedule literals). If the frozen gates find
% no feasible SG_OFF candidate, that is an honest outcome (not a test failure).
if ~isempty(table.sg_off.selected_gfm_indices)
    tc.verifyTrue(table.sg_off.ready_to_commit);
    matched = false;
    for k = 1:numel(table.sg_off.configurations)
        if isequal(sort(table.sg_off.configurations(k).selected_gfm_indices), ...
                sort(table.sg_off.selected_gfm_indices))
            matched = true; break;
        end
    end
    tc.verifyTrue(matched, 'Automatic SG_OFF selected config must be in the cached universe.');
else
    tc.verifyTrue(ismember(table.sg_off.selection_status, ...
        {'NO_FEASIBLE_CANDIDATE', 'NO_STRUCTURAL_CANDIDATE'}), ...
        sprintf('Honest selection_status required; got %s.', table.sg_off.selection_status));
end
% SG_ON is physically infeasible under frozen gates -> honest zero-feasible.
tc.verifyFalse(table.sg_on.ready_to_commit);
tc.verifyTrue(ismember(table.sg_on.selection_status, ...
    {'NO_FEASIBLE_CANDIDATE', 'NO_STRUCTURAL_CANDIDATE'}));
end

% =========================================================================
% C-natural honest timeout (physical evidence)
% =========================================================================

function test_c_natural_honest_timeout(tc)
% C-natural (public IEEE14 demo defaults, C1-test corrected). Uses the
% physical synchronism thresholds from the case file:
% dV_max=0.05, df_max=0.001, dtheta_max=10, dwell=0.5, timeout=5.0.
% fault=3.0/3.1, trip=5.0, sg_on=8.0, t_end=15.0 — public timeline.
% NO synchronism_overrides, NO delays_overrides. The test asserts
% SYNC_TIMEOUT at ~13.0s (8.0 + 5.0). This run honours the complete
% dynamic path between trip and reconnect.
s = tc.TestData.scenario;
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready, selection.failure_reason);
opt = struct('t_end', 15.0, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*0.1, ...
    'fault_on', 3.0, 'fault_clear', 3.1, 'sg_trip', 5.0, 'sg_on', 8.0, ...
    'selected_gfm_indices', 2:5, 'reference_resource_index', 2, ...
    'automatic_gfm_switching', true), 'plot_results', false, ...
    'max_step_subdivisions', 9, 'state_predictor', 'linear_kcl');
% NO synchronism_overrides, NO delays_overrides.
r = stability.run_hybrid_case(scenario, opt);
% C-natural must time out on physical defaults (no diagnostic overrides).
tc.verifyEqual(r.reclose_status, 'SYNC_TIMEOUT');
tc.verifyEqual(r.requested_sg_on_time, 8.0);
tc.verifyTrue(isnan(r.actual_reclose_time));
% Timeout event logged at ~13.0 s (8.0 + 5.0).
timeout_mask = strcmp({r.event_log.type}, 'sg_reclose_timeout');
tc.verifyTrue(any(timeout_mask), ...
    'C-natural must contain sg_reclose_timeout record.');
tc.verifyEqual(r.event_log(find(timeout_mask,1)).t, 13.0, 'AbsTol', 0.02);
end

% =========================================================================
% Multi-island schema validation (synthetic two-island topology)
% =========================================================================

function test_island_components_detects_two_islands(tc)
% Build a synthetic Ybus with two disconnected components and verify
% island_components (Ybus BFS) detects them.
Y = zeros(4);
% Island 1: buses 1-2 connected.
Y(1,2) = -10i; Y(2,1) = -10i;
Y(1,1) = 10i; Y(2,2) = 10i;
% Island 2: buses 3-4 connected.
Y(3,4) = -5i; Y(4,3) = -5i;
Y(3,3) = 5i; Y(4,4) = 5i;
mpc = struct('bus', [1 1 0 0 0 0 1 1.0 0 0 0 0; 2 1 0 0 0 0 1 1.0 0 0 0 0; ...
    3 1 0 0 0 0 1 1.0 0 0 0 0; 4 1 0 0 0 0 1 1.0 0 0 0 0], ...
    'branch', [1 2 0 0.1 0 0 0 0 0 0 1; 3 4 0 0.2 0 0 0 0 0 0 1]);
islands = stability.island_components(Y, mpc, struct());
tc.verifyEqual(numel(islands), 2);
% Each island has 2 buses.
for k = 1:2
    tc.verifyEqual(numel(islands(k).bus_positions), 2);
end
end

function test_island_components_branch_crosscheck(tc)
% If mpc.branch connects two buses that Ybus does not, fail closed.
Y = zeros(2);
Y(1,1) = 1; Y(2,2) = 1;  % no off-diagonal -> buses 1,2 disconnected in Y
mpc = struct('bus', [1 1 0 0 0 0 1 1.0 0 0 0 0; 2 1 0 0 0 0 1 1.0 0 0 0 0], ...
    'branch', [1 2 0 0.1 0 0 0 0 0 0 1]);  % but branch says connected
tc.verifyError(@() stability.island_components(Y, mpc, struct()), ...
    'stability:island_components:ybusBranchInconsistent');
end

function test_per_island_vf_check_catches_orphaned_energized_island(tc)
% C1 FALSIFICATION via the PRODUCTION helper stability.per_island_vf_check.
% A global "any VF exists" check is INSUFFICIENT when the network has multiple
% islands. Build a two-island Ybus where island A has a voltage-forming source
% but island B is energized (has load) yet has NO voltage-forming source. The
% production helper (called by trip_transaction in ts_simulate_ibr_hybrid.m)
% must flag island B; a global check that breaks at the first VF resource
% found anywhere would return has_vf=true and MASK island B's deficit — the
% exact defect C1 fixed.
Y = zeros(4);
% Island 1: buses 1-2 connected, bus 2 has load (Pd,Qd).
Y(1,2) = -10i; Y(2,1) = -10i;
Y(1,1) = 10i; Y(2,2) = 10i;
% Island 2: buses 3-4 connected, bus 3 has load (energized, no VF source).
Y(3,4) = -5i; Y(4,3) = -5i;
Y(3,3) = 5i; Y(4,4) = 5i;
mpc = struct('bus', [1 1 0 0 0 0 1 1.0 0 0 0 0; ...
                     2 1 30 10 0 0 1 1.0 0 0 0 0; ...  % load on bus 2 (island A)
                     3 1 25 8 0 0 1 1.0 0 0 0 0; ...   % load on bus 3 (island B)
                     4 1 0 0 0 0 1 1.0 0 0 0 0], ...
              'branch', [1 2 0 0.1 0 0 0 0 0 0 1; 3 4 0 0.2 0 0 0 0 0 0 1]);
% Devices: SG1 on bus 1 (voltage-forming via 'synchronous'), IBR2 on bus 3
% (GFL mode — NOT voltage-forming). The SG is the tripped device (sg_id).
devs = struct('device_id','','bus_position',0,'capabilities',struct());
devs = repmat(devs,2,1);
devs(1).device_id = 'SG1'; devs(1).bus_position = 1;
devs(1).capabilities = struct('voltage_forming_modes','synchronous');
devs(2).device_id = 'IBR2'; devs(2).bus_position = 3;
devs(2).capabilities = struct('voltage_forming_modes','gfm');
% Candidate hybrid_state: SG1 breaker open (offline), IBR2 online in GFL mode.
hs = struct( ...
    'device_online', struct('SG1', false, 'IBR2', true), ...
    'device_modes',  struct('SG1', 'breaker_open', 'IBR2', 'gfl'));
% Production helper: SG1 is the tripped sg_id (excluded from VF sources).
[has_vf, failing_ids, vf_positions] = stability.per_island_vf_check( ...
    Y, mpc, devs, hs, 'SG1');
% Island A (buses 1-2): SG1 is offline (tripped), so NO online VF source.
% Island B (buses 3-4): IBR2 is GFL (not voltage-forming), so NO VF source.
% Both islands are energized (load) but lack an online VF source.
tc.verifyFalse(has_vf, 'Per-island check must fail: no island has a VF source.');
tc.verifyEqual(numel(failing_ids), 2, ...
    'Both energized islands must be flagged as failing.');
tc.verifyTrue(ismember(1, failing_ids), 'Island A (id=1) must be failing.');
tc.verifyTrue(ismember(2, failing_ids), 'Island B (id=2) must be failing.');
% vf_positions must be empty: SG1 is excluded (tripped), IBR2 is GFL.
tc.verifyTrue(isempty(vf_positions), ...
    'No online voltage-forming bus positions (SG1 tripped, IBR2 is GFL).');
% Now flip IBR2 to GFM mode — island B gains a VF source, island A still
% lacks one (SG1 offline). Only island A should fail.
hs.device_modes.IBR2 = 'gfm';
[has_vf2, failing_ids2, vf_positions2] = stability.per_island_vf_check( ...
    Y, mpc, devs, hs, 'SG1');
tc.verifyFalse(has_vf2, 'Island A still lacks a VF source (SG1 tripped).');
tc.verifyEqual(numel(failing_ids2), 1, 'Only island A must fail now.');
tc.verifyEqual(failing_ids2(1), 1, 'Island A (id=1) must be the failing one.');
tc.verifyEqual(vf_positions2, 3, 'IBR2 (bus 3) must be the VF source.');
% Demonstrate why a GLOBAL check is wrong for the same input: it would
% find IBR2's VF source and report has_vf=true, masking island A.
islands = stability.island_components(Y, mpc, ...
    struct('online_vf_positions', vf_positions2));
global_would_pass = any([islands.has_online_vf_source]);
tc.verifyTrue(global_would_pass, ...
    'Sanity: a global "any VF" test passes here, which is why per-island is required.');
end

function test_reference_owner_schema_generic_eligibility(tc)
% F3: reference owner eligibility is generic (online, voltage-forming,
% capability-permitted, island membership), NOT tied to PF/MATPOWER REF bus.
% Build a synthetic devices array where an IBR (not the REF bus) owns the
% reference.
devs = synthetic_dual_island_devices();
hs = make_hybrid_state(devs);
% Owner = IBR index 2 (online, gfm mode, GFM-capable) for island 1.
hs.reference_owner_indices = 2;
hs.gfm_reference_resource_indices = 2;
hs.reference_island_ids = 1;
norm = stability.reference_owner_schema(hs, devs, struct());
tc.verifyEqual(norm.reference_owner_indices, 2, 'AbsTol', 0);
tc.verifyEqual(norm.gfm_reference_resource_indices, 2, 'AbsTol', 0);
% The owner is an IBR, not the PF REF bus -> generic eligibility holds.
tc.verifyTrue(~strcmpi(char(devs(2).device_type), 'sg'));
end

% =========================================================================
% Local helpers
% =========================================================================

function g = selector_gamma_req(scenario)
g = 0.1;
if isfield(scenario, 'scenario_opt') && isfield(scenario.scenario_opt, 'selector')
    sel = scenario.scenario_opt.selector;
    if isfield(sel, 'gamma_req') && ~isempty(sel.gamma_req)
        g = sel.gamma_req;
    elseif isfield(sel, 'gamma_req_rad_per_s') && ~isempty(sel.gamma_req_rad_per_s)
        g = sel.gamma_req_rad_per_s;
    end
end
end

function ids = resource_ids_of(resources)
ids = cell(1, numel(resources));
for k = 1:numel(resources), ids{k} = char(resources(k).resource_id); end
end

function devs = synthetic_dual_island_devices()
% 1 SG + 2 IBRs for a synthetic two-island topology test.
base = struct('device_id','','initial_mode','gfm','initial_online',true, ...
    'device_type','ibr','capabilities',struct());
base.capabilities = struct('resource_type','ibr','supported_modes',["gfl","gfm"], ...
    'voltage_forming_modes','gfm','can_switch_mode',true,'can_switch_online',true, ...
    'has_current_limiter',true,'has_frt',true,'can_black_start',false);
devs = repmat(base, 1, 3);
devs(1).device_id = 'SG1'; devs(1).device_type = 'sg'; devs(1).initial_mode = 'synchronous';
devs(1).capabilities.resource_type = 'sg';
devs(1).capabilities.supported_modes = ["synchronous","breaker_open"];
devs(1).capabilities.voltage_forming_modes = 'synchronous';
devs(2).device_id = 'IBR2';
devs(3).device_id = 'IBR3';
end

function hs = make_hybrid_state(devs)
hs = struct();
hs.device_online = struct();
hs.device_modes = struct();
for k = 1:numel(devs)
    key = matlab.lang.makeValidName(char(devs(k).device_id), 'ReplacementStyle', 'underscore');
    hs.device_online.(key) = logical(devs(k).initial_online);
    if strcmpi(char(devs(k).device_type), 'sg')
        hs.device_modes.(key) = 'synchronous';
    else
        hs.device_modes.(key) = 'gfm';
    end
end
hs.reference_owner_indices = [];
hs.gfm_reference_resource_indices = [];
hs.reference_island_ids = [];
hs.reference_resource_index = [];
end
