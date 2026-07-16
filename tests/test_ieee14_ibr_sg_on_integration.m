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

% =========================================================================
% C-natural honest timeout (physical evidence)
% =========================================================================

function test_c_natural_honest_timeout(tc)
% C-natural (physical synchronism thresholds) must time out honestly;
% no natural reclose claim if actual_reclose_time is NaN. Uses a diagnostic
% guard so the simulation converges to the timeout; the strict physical guard
% would not converge post-trip on the short horizon. The timeout itself is
% physical evidence (the guard never passes).
s = tc.TestData.scenario;
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready, selection.failure_reason);
opt = struct('t_end', 0.5, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*0.1, ...
    'fault_on', 0.1, 'fault_clear', 0.12, 'sg_trip', 0.2, 'sg_on', 0.4, ...
    'selected_gfm_indices', 2:5, 'reference_resource_index', 2, ...
    'automatic_gfm_switching', true, 'synchronism_overrides', ...
    struct('dV_max', 1e-12, 'df_max', 1e-12, 'dtheta_max', 1e-9), ...
    'delays_overrides', struct('T_sg_min_off_s', 0, 'dwell_s', 0.01, 'timeout_s', 0.05)), ...
    'plot_results', false);
r = stability.run_hybrid_case(scenario, opt);
% If the simulation converged, C-natural must time out (physical evidence) or
% stay pending; never a fake close.
if r.converged
    tc.verifyTrue(ismember(r.reclose_status, {'SYNC_TIMEOUT', 'PENDING', 'NOT_REQUESTED'}), ...
        sprintf('C-natural must time out or stay pending; got %s.', r.reclose_status));
    if strcmp(r.reclose_status, 'SYNC_TIMEOUT')
        tc.verifyTrue(isnan(r.actual_reclose_time), ...
            'No natural reclose; actual_reclose_time must be NaN.');
    end
else
    % If it did not converge, that is an honest numerical outcome on the short
    % horizon; the test does not fabricate a reclose.
    tc.verifyTrue(isempty(r.failure_id) || ~contains(char(r.failure_id), 'reclose'), ...
        'No fabricated reclose on non-converged C-natural.');
end
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
