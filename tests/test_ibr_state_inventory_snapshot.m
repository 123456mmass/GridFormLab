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
%
%   Retargeted 2026-10-08: the retired REGFM_B1 (13-state) and WECC (7-state)
%   IBR contracts were removed from ibr.device_contract_metadata, so the former
%   make_gfm_dev()/make_gfl_dev() fixtures -- which existed only to dispatch
%   those two contracts -- are gone.  Every IBR fixture below is the real
%   ibr.eecon49_dual device (16 states, common 1:3 / gfl 4:9 / gfm 10:16,
%   inputs P_ref,Q_ref,E_ref).  This is a retarget onto the surviving family,
%   not a rename of a retired one; the registry fails closed on anything else.

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
% Minimal EECON49 dual device struct for metadata dispatch (no closures needed).
% The surviving ibr.eecon49_dual_mode_model publishes 16 states whose branch
% ownership is
%   [1:3]  'common'  i_d, i_q, V_dc          (shared plant)
%   [4:9]  'gfl'     gfl_*                   (PLL-owning controller)
%   [10:16] 'gfm'    gfm_*                   (VSG, no PLL)
% and THREE inputs {'P_ref','Q_ref','E_ref'}.  device_contract_metadata
% dispatches on an exact (device_type, nx, nu, state_names, input_names) match
% and fails closed otherwise, so these literals are the contract, not a
% convenience copy: any drift here makes the fixture itself fail closed.
tc = struct();
tc.device_id = 'IBR3';
tc.bus_id = 6;
tc.bus_position = 4;
tc.bus_ids = [1 2 3 6 8];
tc.device_type = 'ibr_eecon49_dual';
tc.mode = 'GFM';
tc.nx = 16;
tc.nu = 3;
tc.state_names = {'i_d','i_q','V_dc', ...
    'gfl_delta_PLL','gfl_xi_PLL','gfl_xi_P','gfl_xi_Q', ...
    'gfl_xi_Id','gfl_xi_Iq', ...
    'gfm_delta_VSG','gfm_omega_VSG','gfm_E','gfm_xi_Vd','gfm_xi_Vq', ...
    'gfm_xi_Id','gfm_xi_Iq'};
tc.input_names = {'P_ref','Q_ref','E_ref'};
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
function test_dual_registry_composed_16_rows(testCase)
% The surviving eecon49_dual contract: 16 rows whose branch ownership is
% common 1:3 / gfl 4:9 / gfm 10:16.  The retired fixtures asserted a 13-row
% 'gfm_regfm_b1' and a 7-row 'gfl_wecc_regca_reeca' contract; neither device
% type survives.
m = ibr.device_contract_metadata(make_dual_dev());
testCase.assertEqual(numel(m.state_metadata), 16);
testCase.assertEqual(m.contract_id, 'eecon49_dual');
common_part = m.state_metadata(1:3);
gfl_part = m.state_metadata(4:9);
gfm_part = m.state_metadata(10:16);
testCase.assertTrue(all(strcmp({common_part.state_branch},'common')));
testCase.assertTrue(all(strcmp({gfl_part.state_branch},'gfl')));
testCase.assertTrue(all(strcmp({gfm_part.state_branch},'gfm')));
testCase.assertEqual({common_part.state_name}, {'i_d','i_q','V_dc'});
testCase.assertEqual({gfl_part.state_name}, ...
    {'gfl_delta_PLL','gfl_xi_PLL','gfl_xi_P','gfl_xi_Q','gfl_xi_Id','gfl_xi_Iq'});
testCase.assertEqual({gfm_part.state_name}, ...
    {'gfm_delta_VSG','gfm_omega_VSG','gfm_E','gfm_xi_Vd','gfm_xi_Vq', ...
     'gfm_xi_Id','gfm_xi_Iq'});
% Source symbols are the EECON49 LaTeX-style ones, unprefixed.
testCase.assertEqual({common_part.state_symbol}, {'I_d','I_q','V_dc'});
testCase.assertEqual({gfl_part.state_symbol}, ...
    {'theta_PLL','xi_PLL','xi_P','xi_Q','xi_Id','xi_Iq'});
testCase.assertEqual({gfm_part.state_symbol}, ...
    {'theta','omega','E','xi_Vd','xi_Vq','xi_Id','xi_Iq'});
% The GFM controller must own no PLL coordinate.
testCase.assertFalse(any(contains(lower({gfm_part.state_symbol}),'pll')));
end

function test_dual_rows_have_metadata(testCase)
m = ibr.device_contract_metadata(make_dual_dev());
for k = 1:numel(m.state_metadata)
    r = m.state_metadata(k);
    testCase.assertFalse(isempty(r.state_symbol));
    testCase.assertFalse(isempty(r.equation_source));
    testCase.assertFalse(isempty(r.equation_classification));
    testCase.assertFalse(isempty(r.unit));
    testCase.assertFalse(isempty(r.frame));
    testCase.assertEqual(r.local_state_index, k);
end
% Every state symbol on the GFM controller is a real GFM coordinate.
testCase.assertTrue(all(strcmp({m.state_metadata(10:16).state_branch},'gfm')));
end

function test_wrong_state_order_fails(testCase)
d = make_dual_dev();
tmp = d.state_names{1}; d.state_names{1} = d.state_names{2}; d.state_names{2} = tmp;
testCase.assertError(@() ibr.device_contract_metadata(d), ...
    'ibr:device_contract_metadata:unknownContract');
end

function test_wrong_input_order_fails(testCase)
d = make_dual_dev();
d.input_names = {'Q_ref','P_ref','E_ref'};
testCase.assertError(@() ibr.device_contract_metadata(d), ...
    'ibr:device_contract_metadata:unknownContract');
end

function test_unknown_device_type_fails(testCase)
d = make_dual_dev();
d.device_type = 'ibr_unknown';
testCase.assertError(@() ibr.device_contract_metadata(d), ...
    'ibr:device_contract_metadata:unknownContract');
end

function test_wrong_nx_fails(testCase)
d = make_dual_dev();
d.nx = 15;
testCase.assertError(@() ibr.device_contract_metadata(d), ...
    'ibr:device_contract_metadata:unknownContract');
end

% ===================== state inventory snapshot tests ====================
function test_inventory_cardinality_single_dual(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:16;
snap = ibr.state_inventory_snapshot(dae, asi);
testCase.assertEqual(numel(snap.state_rows), 16);
testCase.assertEqual(snap.counts.nx_total_ibr, 16);
testCase.assertEqual(snap.counts.nx_total_system, 16);
testCase.assertEqual(snap.counts.nx_active, 16);
testCase.assertEqual(snap.counts.nx_frozen, 0);
end

function test_inventory_mixed_sg_ibr_skips_sg(testCase)
% A non-IBR "SG" device must be skipped in IBR_ONLY scope.
sg = make_sg_dev();
dual = make_dual_dev();
dae = make_dae([sg, dual]);
asi = (sg.nx+1):(sg.nx+dual.nx);   % only IBR active
snap = ibr.state_inventory_snapshot(dae, asi);
testCase.assertEqual(numel(snap.state_rows), 16);
testCase.assertEqual(snap.counts.nx_total_ibr, 16);
testCase.assertEqual(snap.counts.nx_total_system, 22);
testCase.assertEqual(snap.n_devices_total, 2);
testCase.assertEqual(snap.n_ibr_devices, 1);
end

function test_full_system_scope_fails_with_sg(testCase)
sg = make_sg_dev();
dual = make_dual_dev();
dae = make_dae([sg, dual]);
asi = 7:22;
opt.scope = "FULL_SYSTEM";
testCase.assertError(@() ibr.state_inventory_snapshot(dae, asi, opt), ...
    'ibr:state_inventory_snapshot:fullSystemScopeUnsupported');
end

function test_active_maps_to_device_local_equation(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:16;
snap = ibr.state_inventory_snapshot(dae, asi);
for k = 1:numel(snap.state_rows)
    r = snap.state_rows(k);
    testCase.assertEqual(r.device_index, 1);
    testCase.assertEqual(r.device_id, 'IBR3');
    testCase.assertEqual(r.local_state_index, k);
    testCase.assertEqual(r.global_state_index, k);
    testCase.assertEqual(r.active_state_position, k);
    testCase.assertEqual(r.state_status, 'ACTIVE_IN_ARED');
    testCase.assertTrue(r.in_Ared);
    testCase.assertFalse(isempty(r.equation_source));
end
end

function test_frozen_state_retained_in_inventory(testCase)
% Dual device with its last state frozen (ESFlag=0) — simulate by excluding 16.
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:15;   % state 16 frozen out
snap = ibr.state_inventory_snapshot(dae, asi);
testCase.assertEqual(numel(snap.state_rows), 16);   % still 16 rows
frozen_rows = snap.state_rows(16);
testCase.assertEqual(frozen_rows.state_status, 'FROZEN_NOT_IN_ARED');
testCase.assertFalse(frozen_rows.in_Ared);
testCase.assertTrue(isnan(frozen_rows.active_state_position));
testCase.assertEqual(snap.counts.nx_active, 15);
testCase.assertEqual(snap.counts.nx_frozen, 1);
end

function test_dual_gfm_mode_gfl_branch_inactive(testCase)
% The 16-state eecon49_dual layout (common 1:3, gfl 4:9, gfm 10:16).  In GFM
% the ACTIVE set is the 10 states the device itself reports for GFM -- shared
% plant 1:3 plus GFM controller 10:16 -- and the GFL branch 4:9 is the
% inactive-mode anchor (6 states).
dual = make_dual_dev();
dae = make_dae(dual);
asi = [1:3 10:16];   % GFM branch active (10 states)
snap = ibr.state_inventory_snapshot(dae, asi);
testCase.assertEqual(numel(snap.state_rows), 16);
for k = 4:9
    r = snap.state_rows(k);
    testCase.assertEqual(r.state_status, 'INACTIVE_MODE_NOT_IN_ARED');
    testCase.assertFalse(r.in_Ared);
    testCase.assertEqual(r.state_branch, 'gfl');
end
for k = [1 2 3 10:16]
    r = snap.state_rows(k);
    testCase.assertEqual(r.state_status, 'ACTIVE_IN_ARED');
end
testCase.assertEqual(snap.counts.nx_active, 10);
testCase.assertEqual(snap.counts.nx_inactive_anchor, 6);
end

function test_dual_gfl_mode_gfm_branch_inactive(testCase)
% Mirror of the above: in GFL the active set is shared plant 1:3 plus the GFL
% controller 4:9 = 9 states, and the GFM branch 10:16 is the anchor (7 states).
dual = make_dual_dev();
dual.mode = 'gfl';
dae = make_dae(dual);
asi = 1:9;   % GFL branch active (9 states)
snap = ibr.state_inventory_snapshot(dae, asi);
for k = 10:16
    r = snap.state_rows(k);
    testCase.assertEqual(r.state_status, 'INACTIVE_MODE_NOT_IN_ARED');
    testCase.assertEqual(r.state_branch, 'gfm');
end
for k = 1:9
    r = snap.state_rows(k);
    testCase.assertEqual(r.state_status, 'ACTIVE_IN_ARED');
end
testCase.assertEqual(snap.counts.nx_active, 9);
testCase.assertEqual(snap.counts.nx_inactive_anchor, 7);
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
testCase.assertEqual(snap.counts.nx_offline, 16);
end

function test_sssa_dimension_mismatch_fails(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:16;
opt.sssa.A = zeros(15,15);   % wrong size
opt.sssa.active_state_indices = 1:16;
testCase.assertError(@() ibr.state_inventory_snapshot(dae, asi, opt), ...
    'ibr:state_inventory_snapshot:sssaDimMismatch');
end

function test_sssa_active_mismatch_fails(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:16;
opt.sssa.A = zeros(16,16);
opt.sssa.active_state_indices = 1:15;   % mismatch
testCase.assertError(@() ibr.state_inventory_snapshot(dae, asi, opt), ...
    'ibr:state_inventory_snapshot:sssaActiveMismatch');
end

function test_sssa_match_ared_cardinality_verified(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:16;
opt.sssa.A = eye(16);
opt.sssa.active_state_indices = 1:16;
snap = ibr.state_inventory_snapshot(dae, asi, opt);
testCase.assertTrue(snap.ared_cardinality_check.verified);
testCase.assertEqual(snap.ared_cardinality_check.size_Ared, 16);
for k = 1:16
    r = snap.state_rows(k);
    testCase.assertEqual(r.reduced_state_index, k);
    testCase.assertEqual(r.reduced_state_index_status, 'AVAILABLE');
end
end

function test_no_sssa_reduced_index_unavailable(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:16;
snap = ibr.state_inventory_snapshot(dae, asi);
for k = 1:16
    r = snap.state_rows(k);
    testCase.assertEqual(r.reduced_state_index_status, 'NOT_AVAILABLE_NO_SSSA');
    testCase.assertTrue(isnan(r.reduced_state_index));
end
end

function test_physical_index_always_unavailable_phase1(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:16;
opt.sssa.A = eye(16);
opt.sssa.active_state_indices = 1:16;
opt.sssa.physical_A = eye(16);   % present but must NOT be consumed in Phase 1
snap = ibr.state_inventory_snapshot(dae, asi, opt);
for k = 1:16
    r = snap.state_rows(k);
    testCase.assertTrue(isnan(r.physical_coordinate_index));
    testCase.assertEqual(r.physical_coordinate_index_status, 'NOT_AVAILABLE_PHASE_1');
end
end

function test_missing_resource_map_reports_not_available(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:16;
snap = ibr.state_inventory_snapshot(dae, asi);
testCase.assertEqual(snap.resource_map_status, 'NOT_AVAILABLE');
for k = 1:16
    r = snap.state_rows(k);
    testCase.assertTrue(isnan(r.resource_index));
    testCase.assertEqual(r.resource_index_status, 'NOT_AVAILABLE');
end
end

function test_valid_resource_map_resolves_by_id(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:16;
rm(1).resource_index = 4;
rm(1).resource_id = 'IBR3';
rm(1).device_index = 1;
rm(1).device_id = 'IBR3';
rm(1).bus_id = 6;
opt.resource_map = rm;
snap = ibr.state_inventory_snapshot(dae, asi, opt);
testCase.assertEqual(snap.resource_map_status, 'AVAILABLE');
for k = 1:16
    r = snap.state_rows(k);
    testCase.assertEqual(r.resource_index, 4);
    testCase.assertEqual(r.resource_index_status, 'AVAILABLE');
end
end

function test_resource_map_missing_device_fails(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:16;
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
asi = 1:16;
snap = ibr.state_inventory_snapshot(dae, asi);
% Input rows: 3 inputs * 1 device (the EECON49 dual takes P_ref, Q_ref, E_ref).
testCase.assertEqual(numel(snap.input_rows), 3);
g = [snap.input_rows.global_input_index];
testCase.assertEqual(g, [1 2 3]);
testCase.assertEqual({snap.input_rows.input_name}, {'P_ref','Q_ref','E_ref'});
end

function test_input_equilibrium_value_from_u_eq(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:16;
opt.u_eq = [0.5; 1.0; 1.02];
snap = ibr.state_inventory_snapshot(dae, asi, opt);
testCase.assertEqual(snap.input_rows(1).equilibrium_value, 0.5);
testCase.assertEqual(snap.input_rows(2).equilibrium_value, 1.0);
testCase.assertEqual(snap.input_rows(3).equilibrium_value, 1.02);
testCase.assertEqual(snap.input_rows(1).equilibrium_value_status, 'AVAILABLE_OPT');
end

function test_u_eq_conflict_fails(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:16;
opt.u_eq = [0.5; 1.0; 1.02];
opt.sssa.A = eye(16);
opt.sssa.active_state_indices = 1:16;
opt.sssa.u_eq = [0.6; 1.0; 1.02];   % differs
testCase.assertError(@() ibr.state_inventory_snapshot(dae, asi, opt), ...
    'ibr:state_inventory_snapshot:uEqConflict');
end

function test_duplicate_active_indices_fail(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = [1 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15];
testCase.assertError(@() ibr.state_inventory_snapshot(dae, asi), ...
    'ibr:state_inventory_snapshot:duplicateActive');
end

function test_active_out_of_range_fails(testCase)
dual = make_dual_dev();
dae = make_dae(dual);
asi = 1:17;
testCase.assertError(@() ibr.state_inventory_snapshot(dae, asi), ...
    'ibr:state_inventory_snapshot:activeOutOfRange');
end

function test_mode_gfm_active_branch_correct(testCase)
% Verify the dual-mode branch-from-mode mapping: GFM mode -> the GFM
% controller block (10:16) is active, the GFL block (4:9) is the anchor.
dual = make_dual_dev();
dual.mode = 'GFM';
dae = make_dae(dual);
asi = [1:3 10:16];
snap = ibr.state_inventory_snapshot(dae, asi);
testCase.assertEqual(snap.state_rows(1).state_status, 'ACTIVE_IN_ARED');
testCase.assertEqual(snap.state_rows(10).state_status, 'ACTIVE_IN_ARED');
testCase.assertEqual(snap.state_rows(4).state_status, 'INACTIVE_MODE_NOT_IN_ARED');
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
