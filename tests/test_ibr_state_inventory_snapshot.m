function tests = test_ibr_state_inventory_snapshot()
%TEST_IBR_STATE_INVENTORY_SNAPSHOT  Falsification tests for Section H Phase 1.
%
%   Covers: ibr.device_contract_metadata (registry dispatch + frozen layouts)
%   and ibr.state_inventory_snapshot (Section H state/input/resource inventory).
%
%   These tests are falsification instruments: they verify index identity,
%   state ownership, citation provenance, and fail-closed behavior. They do
%   NOT validate production numerical equations. No external solver, inv,
%   pinv, or loaded solution is used.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
    clear functions;
    rehash;
    rehash toolboxcache;
end

% =========================================================================
function tc = make_gfm_dev()
% Minimal REGFM_B1 G2 device struct for metadata dispatch (no closures needed).
tc = struct();
tc.device_id = 'IBR1';
tc.bus_id = 2;
tc.bus_position = 2;
tc.bus_ids = [1 2 3 6 8];
tc.device_type = 'ibr_gfm';
tc.mode = 'GFM';
tc.nx = 13;
tc.nu = 2;
tc.state_names = {'omega_m','delta_IT','x_washout','x_Eint','delta_PLL', ...
    'x_PLL_int','Pinv_f','Idinv_f','Qinv_f','Vinv_f','Iqinv_f', ...
    'delta_ITmax','delta_ITmin'};
tc.input_names = {'P_ref','V_ref'};
end

function tc = make_gfl_dev()
tc = struct();
tc.device_id = 'IBR2';
tc.bus_id = 3;
tc.bus_position = 3;
tc.bus_ids = [1 2 3 6 8];
tc.device_type = 'ibr_gfl_wecc_regca_reeca';
tc.mode = 'gfl';
tc.nx = 7;
tc.nu = 2;
tc.state_names = {'Vt_f','P_f','Iq_cmd_f','Pord','Vlvpl_f','Ip_reg','Iq_reg'};
tc.input_names = {'P_ref','Q_ref'};
end

function tc = make_sg_dev()
% Minimal non-IBR SG device struct with the SAME top-level fields as the IBR
% helpers so struct vertcat in make_dae succeeds.
tc = struct();
tc.device_id = 'SG1';
tc.bus_id = 1;
tc.bus_position = 1;
tc.bus_ids = [1 2 3 6 8];
tc.device_type = 'sg_emf6';
tc.mode = 'synchronous';
tc.nx = 6;
tc.nu = 2;
tc.state_names = {'delta','omega','Edp','Eqp','psi_d','psi_q'};
tc.input_names = {'Tm','Efd'};
end

function tc = make_dual_dev()
tc = struct();
tc.device_id = 'IBR3';
tc.bus_id = 6;
tc.bus_position = 4;
tc.bus_ids = [1 2 3 6 8];
tc.device_type = 'ibr_dual_mode';
tc.mode = 'GFM';
tc.nx = 20;
tc.nu = 3;
tc.state_names = [strcat('gfm_', ...
    {'omega_m','delta_IT','x_washout','x_Eint','delta_PLL','x_PLL_int', ...
     'Pinv_f','Idinv_f','Qinv_f','Vinv_f','Iqinv_f','delta_ITmax','delta_ITmin'}), ...
    strcat('gfl_', ...
    {'Vt_f','P_f','Iq_cmd_f','Pord','Vlvpl_f','Ip_reg','Iq_reg'})];
tc.input_names = {'P_ref','Q_ref','V_ref'};
end

function dae = make_dae(devs)
% Minimal composite DAE: devices + offsets + u0. No closures required for the
% metadata/inventory layer.
dae.devices = devs;
off = zeros(numel(devs),1);
for k = 2:numel(devs)
    off(k) = off(k-1) + devs(k-1).nx;
end
dae.device_offsets = off;
% u0 offsets
uoff = zeros(numel(devs),1);
for k = 2:numel(devs)
    uoff(k) = uoff(k-1) + devs(k-1).nu;
end
dae.u_offsets = uoff;
total_u = sum(arrayfun(@(d) d.nu, devs));
dae.u0 = ones(total_u,1);
end

% =========================== registry tests ==============================
function test_gfm_registry_13_rows(testCase)
m = ibr.device_contract_metadata(make_gfm_dev());
testCase.assertEqual(numel(m.state_metadata), 13);
testCase.assertEqual({m.state_metadata.state_name}, ...
    {'omega_m','delta_IT','x_washout','x_Eint','delta_PLL','x_PLL_int', ...
     'Pinv_f','Idinv_f','Qinv_f','Vinv_f','Iqinv_f','delta_ITmax','delta_ITmin'});
end

function test_gfm_rows_have_metadata(testCase)
m = ibr.device_contract_metadata(make_gfm_dev());
for k = 1:numel(m.state_metadata)
    r = m.state_metadata(k);
    testCase.assertFalse(isempty(r.state_symbol));
    testCase.assertFalse(isempty(r.equation_source));
    testCase.assertFalse(isempty(r.equation_classification));
    testCase.assertFalse(isempty(r.unit));
    testCase.assertFalse(isempty(r.frame));
    testCase.assertEqual(r.local_state_index, k);
    testCase.assertEqual(r.citation_status, 'PAGE_LEVEL');
    testCase.assertEqual(r.state_branch, 'gfm');
end
end

function test_gfl_registry_7_rows(testCase)
m = ibr.device_contract_metadata(make_gfl_dev());
testCase.assertEqual(numel(m.state_metadata), 7);
testCase.assertEqual({m.state_metadata.state_name}, ...
    {'Vt_f','P_f','Iq_cmd_f','Pord','Vlvpl_f','Ip_reg','Iq_reg'});
end

function test_gfl_no_pll_label(testCase)
m = ibr.device_contract_metadata(make_gfl_dev());
for k = 1:numel(m.state_metadata)
    r = m.state_metadata(k);
    blob = [lower(r.state_name) lower(r.state_symbol) lower(r.equation_source) ...
            lower(r.equation_classification) lower(r.frame)];
    testCase.assertFalse(contains(blob, 'pll'), ...
        sprintf('GFL state %s must not be labelled PLL.', r.state_name));
    testCase.assertEqual(r.citation_status, 'BLOCK_LEVEL_NOT_PAGE_CITED');
    testCase.assertEqual(r.state_branch, 'gfl');
    testCase.assertEqual(r.frame, 'device-local');
end
end

function test_dual_registry_composed_20_rows(testCase)
m = ibr.device_contract_metadata(make_dual_dev());
testCase.assertEqual(numel(m.state_metadata), 20);
gfm_part = m.state_metadata(1:13);
gfl_part = m.state_metadata(14:20);
testCase.assertTrue(all(strcmp({gfm_part.state_branch},'gfm')));
testCase.assertTrue(all(strcmp({gfl_part.state_branch},'gfl')));
% Names prefixed
testCase.assertEqual({gfm_part.state_name}, ...
    strcat('gfm_', {'omega_m','delta_IT','x_washout','x_Eint','delta_PLL', ...
     'x_PLL_int','Pinv_f','Idinv_f','Qinv_f','Vinv_f','Iqinv_f', ...
     'delta_ITmax','delta_ITmin'}));
testCase.assertEqual({gfl_part.state_name}, ...
    strcat('gfl_', {'Vt_f','P_f','Iq_cmd_f','Pord','Vlvpl_f','Ip_reg','Iq_reg'}));
% Source symbols preserved (unprefixed, LaTeX-style as in the registry)
testCase.assertEqual({gfm_part.state_symbol}, ...
    {'omega_m','delta_IT','x_washout','x_Eint','delta_PLL','x_PLL_int', ...
     'P_inv,f','I_d,inv,f','Q_inv,f','V_inv,f','I_q,inv,f', ...
     'delta_IT,max','delta_IT,min'});
end

function test_wrong_state_order_fails(testCase)
d = make_gfm_dev();
tmp = d.state_names{1}; d.state_names{1} = d.state_names{2}; d.state_names{2} = tmp;
testCase.assertError(@() ibr.device_contract_metadata(d), ...
    'ibr:device_contract_metadata:unknownContract');
end

function test_wrong_input_order_fails(testCase)
d = make_gfm_dev();
d.input_names = {'V_ref','P_ref'};
testCase.assertError(@() ibr.device_contract_metadata(d), ...
    'ibr:device_contract_metadata:unknownContract');
end

function test_unknown_device_type_fails(testCase)
d = make_gfm_dev();
d.device_type = 'ibr_unknown';
testCase.assertError(@() ibr.device_contract_metadata(d), ...
    'ibr:device_contract_metadata:unknownContract');
end

function test_wrong_nx_fails(testCase)
d = make_gfm_dev();
d.nx = 12;
testCase.assertError(@() ibr.device_contract_metadata(d), ...
    'ibr:device_contract_metadata:unknownContract');
end

% ===================== state inventory snapshot tests ====================
function test_inventory_cardinality_single_gfm(testCase)
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = 1:13;
snap = ibr.state_inventory_snapshot(dae, asi);
testCase.assertEqual(numel(snap.state_rows), 13);
testCase.assertEqual(snap.counts.nx_total_ibr, 13);
testCase.assertEqual(snap.counts.nx_total_system, 13);
testCase.assertEqual(snap.counts.nx_active, 13);
testCase.assertEqual(snap.counts.nx_frozen, 0);
end

function test_inventory_mixed_sg_ibr_skips_sg(testCase)
% A non-IBR "SG" device must be skipped in IBR_ONLY scope.
sg = make_sg_dev();
gfm = make_gfm_dev();
dae = make_dae([sg, gfm]);
asi = (sg.nx+1):(sg.nx+gfm.nx);   % only GFM active
snap = ibr.state_inventory_snapshot(dae, asi);
testCase.assertEqual(numel(snap.state_rows), 13);
testCase.assertEqual(snap.counts.nx_total_ibr, 13);
testCase.assertEqual(snap.counts.nx_total_system, 19);
testCase.assertEqual(snap.n_devices_total, 2);
testCase.assertEqual(snap.n_ibr_devices, 1);
end

function test_full_system_scope_fails_with_sg(testCase)
sg = make_sg_dev();
gfm = make_gfm_dev();
dae = make_dae([sg, gfm]);
asi = 7:19;
opt.scope = "FULL_SYSTEM";
testCase.assertError(@() ibr.state_inventory_snapshot(dae, asi, opt), ...
    'ibr:state_inventory_snapshot:fullSystemScopeUnsupported');
end

function test_active_maps_to_device_local_equation(testCase)
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = 1:13;
snap = ibr.state_inventory_snapshot(dae, asi);
for k = 1:numel(snap.state_rows)
    r = snap.state_rows(k);
    testCase.assertEqual(r.device_index, 1);
    testCase.assertEqual(r.device_id, 'IBR1');
    testCase.assertEqual(r.local_state_index, k);
    testCase.assertEqual(r.global_state_index, k);
    testCase.assertEqual(r.active_state_position, k);
    testCase.assertEqual(r.state_status, 'ACTIVE_IN_ARED');
    testCase.assertTrue(r.in_Ared);
    testCase.assertFalse(isempty(r.equation_source));
end
end

function test_frozen_state_retained_in_inventory(testCase)
% GFM with delta_ITmin frozen (ESFlag=0) — simulate by excluding state 13.
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = 1:12;   % state 13 frozen out
snap = ibr.state_inventory_snapshot(dae, asi);
testCase.assertEqual(numel(snap.state_rows), 13);   % still 13 rows
frozen_rows = snap.state_rows(13);
testCase.assertEqual(frozen_rows.state_status, 'FROZEN_NOT_IN_ARED');
testCase.assertFalse(frozen_rows.in_Ared);
testCase.assertTrue(isnan(frozen_rows.active_state_position));
testCase.assertEqual(snap.counts.nx_active, 12);
testCase.assertEqual(snap.counts.nx_frozen, 1);
end

function test_dual_gfm_mode_gfl_branch_inactive(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:13;   % GFM branch active
snap = ibr.state_inventory_snapshot(dae, asi);
testCase.assertEqual(numel(snap.state_rows), 20);
for k = 14:20
    r = snap.state_rows(k);
    testCase.assertEqual(r.state_status, 'INACTIVE_MODE_NOT_IN_ARED');
    testCase.assertFalse(r.in_Ared);
    testCase.assertEqual(r.state_branch, 'gfl');
end
for k = 1:13
    r = snap.state_rows(k);
    testCase.assertEqual(r.state_status, 'ACTIVE_IN_ARED');
    testCase.assertEqual(r.state_branch, 'gfm');
end
testCase.assertEqual(snap.counts.nx_active, 13);
testCase.assertEqual(snap.counts.nx_inactive_anchor, 7);
end

function test_dual_gfl_mode_gfm_branch_inactive(testCase)
dual = make_dual_dev();
dual.mode = 'gfl';
dae = make_dae(dual);
asi = 14:20;   % GFL branch active
snap = ibr.state_inventory_snapshot(dae, asi);
for k = 1:13
    r = snap.state_rows(k);
    testCase.assertEqual(r.state_status, 'INACTIVE_MODE_NOT_IN_ARED');
    testCase.assertEqual(r.state_branch, 'gfm');
end
for k = 14:20
    r = snap.state_rows(k);
    testCase.assertEqual(r.state_status, 'ACTIVE_IN_ARED');
    testCase.assertEqual(r.state_branch, 'gfl');
end
testCase.assertEqual(snap.counts.nx_active, 7);
testCase.assertEqual(snap.counts.nx_inactive_anchor, 13);
end

function test_offline_overrides_mode(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = [];
% Build event_context with device offline
hs.device_modes.IBR3 = 'tripped';
hs.device_online.IBR3 = false;
opt.event_context = struct('hybrid_state', hs);
% empty active set with one device — bypass the empty-active guard by
% using a trivial active set of one state then forcing offline via context
asi = 1;
snap = ibr.state_inventory_snapshot(dae, asi, opt);
for k = 1:numel(snap.state_rows)
    r = snap.state_rows(k);
    testCase.assertEqual(r.state_status, 'OFFLINE_NOT_IN_ARED');
    testCase.assertFalse(r.in_Ared);
    testCase.assertFalse(r.online);
end
testCase.assertEqual(snap.counts.nx_offline, 20);
end

function test_sssa_dimension_mismatch_fails(testCase)
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = 1:13;
opt.sssa.A = zeros(12,12);   % wrong size
opt.sssa.active_state_indices = 1:13;
testCase.assertError(@() ibr.state_inventory_snapshot(dae, asi, opt), ...
    'ibr:state_inventory_snapshot:sssaDimMismatch');
end

function test_sssa_active_mismatch_fails(testCase)
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = 1:13;
opt.sssa.A = zeros(13,13);
opt.sssa.active_state_indices = 1:12;   % mismatch
testCase.assertError(@() ibr.state_inventory_snapshot(dae, asi, opt), ...
    'ibr:state_inventory_snapshot:sssaActiveMismatch');
end

function test_sssa_match_ared_cardinality_verified(testCase)
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = 1:13;
opt.sssa.A = eye(13);
opt.sssa.active_state_indices = 1:13;
snap = ibr.state_inventory_snapshot(dae, asi, opt);
testCase.assertTrue(snap.ared_cardinality_check.verified);
testCase.assertEqual(snap.ared_cardinality_check.size_Ared, 13);
for k = 1:13
    r = snap.state_rows(k);
    testCase.assertEqual(r.reduced_state_index, k);
    testCase.assertEqual(r.reduced_state_index_status, 'AVAILABLE');
end
end

function test_no_sssa_reduced_index_unavailable(testCase)
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = 1:13;
snap = ibr.state_inventory_snapshot(dae, asi);
for k = 1:13
    r = snap.state_rows(k);
    testCase.assertEqual(r.reduced_state_index_status, 'NOT_AVAILABLE_NO_SSSA');
    testCase.assertTrue(isnan(r.reduced_state_index));
end
end

function test_physical_index_always_unavailable_phase1(testCase)
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = 1:13;
opt.sssa.A = eye(13);
opt.sssa.active_state_indices = 1:13;
opt.sssa.physical_A = eye(13);   % present but must NOT be consumed in Phase 1
snap = ibr.state_inventory_snapshot(dae, asi, opt);
for k = 1:13
    r = snap.state_rows(k);
    testCase.assertTrue(isnan(r.physical_coordinate_index));
    testCase.assertEqual(r.physical_coordinate_index_status, 'NOT_AVAILABLE_PHASE_1');
end
end

function test_missing_resource_map_reports_not_available(testCase)
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = 1:13;
snap = ibr.state_inventory_snapshot(dae, asi);
testCase.assertEqual(snap.resource_map_status, 'NOT_AVAILABLE');
for k = 1:13
    r = snap.state_rows(k);
    testCase.assertTrue(isnan(r.resource_index));
    testCase.assertEqual(r.resource_index_status, 'NOT_AVAILABLE');
end
end

function test_valid_resource_map_resolves_by_id(testCase)
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = 1:13;
rm(1).resource_index = 4;
rm(1).resource_id = 'IBR1';
rm(1).device_index = 1;
rm(1).device_id = 'IBR1';
rm(1).bus_id = 2;
opt.resource_map = rm;
snap = ibr.state_inventory_snapshot(dae, asi, opt);
testCase.assertEqual(snap.resource_map_status, 'AVAILABLE');
for k = 1:13
    r = snap.state_rows(k);
    testCase.assertEqual(r.resource_index, 4);
    testCase.assertEqual(r.resource_index_status, 'AVAILABLE');
end
end

function test_resource_map_missing_device_fails(testCase)
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = 1:13;
rm(1).resource_index = 4;
rm(1).resource_id = 'OTHER';
rm(1).device_index = 99;
rm(1).device_id = 'OTHER';
rm(1).bus_id = 2;
opt.resource_map = rm;
testCase.assertError(@() ibr.state_inventory_snapshot(dae, asi, opt), ...
    'ibr:state_inventory_snapshot:resourceMapMissingDevice');
end

function test_input_offsets_contiguous(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:20;
snap = ibr.state_inventory_snapshot(dae, asi);
% Input rows: 3 inputs * 1 device
testCase.assertEqual(numel(snap.input_rows), 3);
g = [snap.input_rows.global_input_index];
testCase.assertEqual(g, [1 2 3]);
testCase.assertEqual({snap.input_rows.input_name}, {'P_ref','Q_ref','V_ref'});
end

function test_input_equilibrium_value_from_u_eq(testCase)
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = 1:13;
opt.u_eq = [0.5; 1.0];
snap = ibr.state_inventory_snapshot(dae, asi, opt);
testCase.assertEqual(snap.input_rows(1).equilibrium_value, 0.5);
testCase.assertEqual(snap.input_rows(2).equilibrium_value, 1.0);
testCase.assertEqual(snap.input_rows(1).equilibrium_value_status, 'AVAILABLE_OPT');
end

function test_u_eq_conflict_fails(testCase)
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = 1:13;
opt.u_eq = [0.5; 1.0];
opt.sssa.A = eye(13);
opt.sssa.active_state_indices = 1:13;
opt.sssa.u_eq = [0.6; 1.0];   % differs
testCase.assertError(@() ibr.state_inventory_snapshot(dae, asi, opt), ...
    'ibr:state_inventory_snapshot:uEqConflict');
end

function test_duplicate_active_indices_fail(testCase)
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = [1 1 2 3 4 5 6 7 8 9 10 11 12];
testCase.assertError(@() ibr.state_inventory_snapshot(dae, asi), ...
    'ibr:state_inventory_snapshot:duplicateActive');
end

function test_active_out_of_range_fails(testCase)
gfm = make_gfm_dev();
dae = make_dae(gfm);
asi = 1:14;
testCase.assertError(@() ibr.state_inventory_snapshot(dae, asi), ...
    'ibr:state_inventory_snapshot:activeOutOfRange');
end

function test_mode_gfm_active_branch_correct(testCase)
% Verify the dual-mode branch-from-mode mapping: GFM mode -> gfm branch active
dual = make_dual_dev();
dual.mode = 'GFM';
dae = make_dae(dual);
asi = 1:13;
snap = ibr.state_inventory_snapshot(dae, asi);
% GFM branch active, GFL branch inactive-mode anchor
testCase.assertEqual(snap.state_rows(1).state_status, 'ACTIVE_IN_ARED');
testCase.assertEqual(snap.state_rows(14).state_status, 'INACTIVE_MODE_NOT_IN_ARED');
end

function test_no_external_solver_in_new_files(testCase)
% Static source guard: the two new +ibr files must not call external solvers,
% inv, pinv, or shared numerical routines.
fns = {'ibr.device_contract_metadata', 'ibr.state_inventory_snapshot'};
for k = 1:numel(fns)
    p = which(fns{k});
    testCase.assertFalse(isempty(p), sprintf('%s not found on path', fns{k}));
    txt = fileread(p);
    % Lowercase bareword scan (this is a falsification guard, not a parser).
    bad = {'matpower','psat','pgaz','simulink','fmincon','quadprog','linprog', ...
        'ode45','ode15s','fsolve','inv(','pinv('};
    for j = 1:numel(bad)
        testCase.assertFalse(contains(lower(txt), lower(bad{j})), ...
            sprintf('%s must not contain %s', fns{k}, bad{j}));
    end
end
end
