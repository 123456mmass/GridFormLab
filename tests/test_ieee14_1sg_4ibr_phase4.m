function tests = test_ieee14_1sg_4ibr_phase4()
%TEST_IEEE14_1SG_4IBR_PHASE4  Phase 4 mixed-equilibrium + case contract tests.
%   Verifies: SG1 dynamics sourced (Kodsi); dispatch contract (Pmax-proportional,
%   no load-shed); mixed equilibrium solver (SG_ON, SG_OFF+GFM, pure-GFL reject);
%   fixed angle-gauge; deterministic fingerprint.
%
%   Source: project Phase 4 design (Plan agent). Synthetic stubs for IBR
%   devices (ASSUMED_DIAGNOSTIC scaffolding); real GFL/VSG models are Phase 5-6.
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% =========================================================================
function test_ieee14_sg1_dynamics_sourced(testCase)
% SG1 uses Kodsi Table A.2 values (not classical defaults H=5/D=0/X'd=0.30).
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
testCase.verifyTrue(isfield(c,'machines'), 'case has machines struct.');
testCase.verifyEqual(c.machines.base.S_MVA, 615, 'AbsTol', 0, 'Kodsi 615 MVA base.');
testCase.verifyEqual(c.machines.units.H, 5.148, 'AbsTol', 0, 'Kodsi H=5.148.');
testCase.verifyEqual(c.machines.units.D, 2, 'AbsTol', 0, 'Kodsi D=2.');
testCase.verifyEqual(c.machines.reactances.Xd, 0.8979, 'AbsTol', 0, 'Kodsi Xd.');
testCase.verifyEqual(c.machines.reactances.Xdp, 0.2995, 'AbsTol', 0, 'Kodsi Xdp.');
testCase.verifyEqual(c.machines.reactances.Xdpp, 0.23, 'AbsTol', 0, 'Kodsi Xdpp.');
testCase.verifyEqual(c.machines.time_constants.Tpd0, 7.4, 'AbsTol', 0, 'Kodsi Tpd0.');
testCase.verifyEqual(c.machines.time_constants.Tppd0, 0.03, 'AbsTol', 0, 'Kodsi Tppd0.');
testCase.verifyEqual(c.machines.time_constants.Tppq0, 0.033, 'AbsTol', 0, 'Kodsi Tppq0.');
% NOT classical defaults.
testCase.verifyNotEqual(c.machines.units.H, 5.0, 'not classical H=5.0.');
testCase.verifyNotEqual(c.machines.units.D, 0, 'not classical D=0.');
testCase.verifyNotEqual(c.machines.reactances.Xdp, 0.30, 'not classical Xdp=0.30.');
% Base conversion: scale = 100/615.
scale = 100/615;
testCase.verifyEqual(c.machines.reactances.Xd * scale, 0.8979 * 100/615, ...
    'AbsTol', 1e-12, 'base conversion X_system = X_device*Ssys/Smach.');
end

% =========================================================================
function test_dispatch_pmax_proportional(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
pt = c.dispatch_contract.post_trip;
testCase.verifyEqual(pt.participation.IBR2 + pt.participation.IBR3 + ...
    pt.participation.IBR6 + pt.participation.IBR8, 1.0, 'AbsTol', 1e-12, ...
    'participation factors sum to 1.');
% Each proportional to Pmax: IBR2/140 == IBR3/100.
testCase.verifyEqual(pt.participation.IBR2/140, pt.participation.IBR3/100, ...
    'AbsTol', 1e-12, 'equal Pmax-normalized participation.');
end

% =========================================================================
function test_dispatch_no_load_shed(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
testCase.verifyEqual(c.dispatch_contract.load_shed_MW, 0, 'AbsTol', 0, 'no load-shed.');
pt = c.dispatch_contract.post_trip.post_trip_Pg_MW;
total_pg = pt.IBR2 + pt.IBR3 + pt.IBR6 + pt.IBR8;
testCase.verifyGreaterThanOrEqual(total_pg, 259.0, 'post-trip Pg covers load 259 MW.');
end

% =========================================================================
function test_dispatch_current_within_imaxss(testCase)
% Each IBR's post-trip Pg is within its Pmax (steady-state current < ImaxSS).
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
pt = c.dispatch_contract.post_trip.post_trip_Pg_MW;
testCase.verifyLessThan(pt.IBR2, c.dispatch_contract.pmax_MW.IBR2, 'IBR2 < Pmax.');
testCase.verifyLessThan(pt.IBR3, c.dispatch_contract.pmax_MW.IBR3, 'IBR3 < Pmax.');
testCase.verifyLessThan(pt.IBR6, c.dispatch_contract.pmax_MW.IBR6, 'IBR6 < Pmax.');
testCase.verifyLessThan(pt.IBR8, c.dispatch_contract.pmax_MW.IBR8, 'IBR8 < Pmax.');
end

% =========================================================================
function test_mixed_equilibrium_sg_on(testCase)
% SG_ON config: all IBRs gfl, SG1 online. The equilibrium solver should
% converge (uses the PF warm-start + fixed gauge + synthetic gfl stubs).
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
devs = build_synthetic_devices(c, 'online', struct('IBR2',40,'IBR3',0,'IBR6',0,'IBR8',0));
config = struct('sg_status','online', ...
    'device_modes', struct( ...
        'device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
        'mode',{'gfl','gfl','gfl','gfl'}), ...
    'dispatch', struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0), ...
    'devices', devs);
r = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(r.converged, ['SG_ON equilibrium must converge: ' r.failure_reason]);
testCase.verifyLessThan(r.residual_norm, 1e-6, 'residual within tolerance.');
testCase.verifyGreaterThan(r.rcond, 1e-10, 'reduced Jacobian well-conditioned.');
end

% =========================================================================
function test_mixed_equilibrium_sg_off_gfm(testCase)
% SG_OFF config: IBR2='GFM', IBR3/6/8='gfl'. The GFM forms voltage through
% its device equations (Eq.13 output stage). The fixed gauge stays on bus 1.
% NOTE: uses synthetic GFM stub (f=0 equilibrium); real VSG model is Phase 5-6.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
pt = c.dispatch_contract.post_trip.post_trip_Pg_MW;
disp = struct('IBR2',pt.IBR2,'IBR3',pt.IBR3,'IBR6',pt.IBR6,'IBR8',pt.IBR8);
devs = build_synthetic_devices(c, 'tripped', disp, 'IBR2');
config = struct('sg_status','tripped', ...
    'device_modes', struct( ...
        'device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
        'mode',{'GFM','gfl','gfl','gfl'}), ...
    'dispatch', disp, 'devices', devs);
r = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(r.converged, ['SG_OFF+GFM equilibrium must converge: ' r.failure_reason]);
testCase.verifyLessThan(r.residual_norm, 1e-6, 'residual within tolerance.');
end

% =========================================================================
function test_pure_gfl_island_rejected(testCase)
% SG_OFF with ALL IBRs gfl -> no voltage-forming source -> fail closed.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
disp = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
devs = build_synthetic_devices(c, 'tripped', disp);
config = struct('sg_status','tripped', ...
    'device_modes', struct( ...
        'device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
        'mode',{'gfl','gfl','gfl','gfl'}), ...
    'dispatch', disp, 'devices', devs);
r = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyFalse(r.converged, 'pure-GFL SG_OFF must not converge.');
testCase.verifyEqual(r.failure_id, 'mixed_equilibrium_solve:noVoltageFormingSource', ...
    'fails closed with noVoltageFormingSource.');
end

% =========================================================================
function test_equilibrium_fingerprint_deterministic(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
pt = c.dispatch_contract.post_trip.post_trip_Pg_MW;
disp = struct('IBR2',pt.IBR2,'IBR3',pt.IBR3,'IBR6',pt.IBR6,'IBR8',pt.IBR8);
devs = build_synthetic_devices(c, 'tripped', disp, 'IBR2');
config = struct('sg_status','tripped', ...
    'device_modes', struct( ...
        'device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
        'mode',{'GFM','gfl','gfl','gfl'}), ...
    'dispatch', disp, 'devices', devs);
r1 = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
r2 = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyEqual(r1.fingerprint.config_hash, r2.fingerprint.config_hash, ...
    'AbsTol', 0, 'same config_hash.');
testCase.verifyEqual(r1.fingerprint.x0_hash, r2.fingerprint.x0_hash, ...
    'AbsTol', 0, 'same x0_hash (deterministic Newton).');
end

% =========================================================================
function test_reference_gauge_fixed(testCase)
% Grep guard: the solver uses the ANGLE-ONLY gauge (Im(V1)=0 fixed, Re(V1) free),
% not a 2-variable complex-voltage vcon. Approved by clarification 1/5
% (angle-only vcon; Re(V1) is a solved unknown). The gauge must NOT dynamically
% change by config.
solver_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+stability', 'mixed_equilibrium_solve.m');
src = fileread(solver_path);
testCase.verifyTrue(contains(src, 'vcon.vars = 2'), 'vcon.vars fixed at 2 (Im(V1), angle-only).');
testCase.verifyTrue(contains(src, 'vcon.rows = 2'), 'vcon.rows fixed at 2 (Im(V1) row).');
testCase.verifyFalse(contains(src, 'vcon.vars = [1, 2]'), 'old 2-variable vcon removed.');
% Structural check: both SG_ON and SG_OFF+GFM use the same angle-only gauge.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
devs_on = build_synthetic_devices(c, 'online', struct('IBR2',40,'IBR3',0,'IBR6',0,'IBR8',0));
cfg_on = struct('sg_status','online', ...
    'device_modes', struct('device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
    'mode',{'gfl','gfl','gfl','gfl'}), ...
    'dispatch', struct('IBR2',40,'IBR3',0,'IBR6',0,'IBR8',0), 'devices', devs_on);
pt = c.dispatch_contract.post_trip.post_trip_Pg_MW;
disp_off = struct('IBR2',pt.IBR2,'IBR3',pt.IBR3,'IBR6',pt.IBR6,'IBR8',pt.IBR8);
devs_off = build_synthetic_devices(c, 'tripped', disp_off, 'IBR2');
cfg_off = struct('sg_status','tripped', ...
    'device_modes', struct('device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
    'mode',{'GFM','gfl','gfl','gfl'}), ...
    'dispatch', disp_off, 'devices', devs_off);
r_on = stability.mixed_equilibrium_solve(c, cfg_on, struct('verbose',false));
r_off = stability.mixed_equilibrium_solve(c, cfg_off, struct('verbose',false));
testCase.verifyEqual(r_on.vcon_vars, 2, 'AbsTol', 0, 'SG_ON angle-only gauge var=2.');
testCase.verifyEqual(r_off.vcon_vars, 2, 'AbsTol', 0, 'SG_OFF angle-only gauge var=2.');
testCase.verifyEqual(r_on.vcon_ref, r_off.vcon_ref, 'AbsTol', 0, 'same gauge ref (0).');
end

% =========================================================================
function test_no_external_solver_dependency_phase4(testCase)
% The new solver must not call fsolve/optimoptions/etc.
solver_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+stability', 'mixed_equilibrium_solve.m');
src = fileread(solver_path);
for fn = {'fsolve','optimoptions','fmincon','fminsearch','lsqnonlin','optimset'}
    testCase.verifyFalse(contains(src, fn{1}), ['no ' fn{1} ' in solver.']);
end
end

% =========================================================================
function devs = build_synthetic_devices(case_data, sg_status, dispatch, gfm_device_id)
%BUILD_SYNTHETIC_DEVICES  Test helper: build synthetic IBR stubs for a config.
%   sg_status: 'online' | 'tripped'. gfm_device_id: which IBR is GFM (or '').
%   SG1 is NOT a device in the list; when online, its slack is the PF. When
%   tripped, no SG device. The IBRs use the synthetic_ibr_equilibrium fixture.
ibr_ids = {'IBR2','IBR3','IBR6','IBR8'};
dev_cells = cell(numel(ibr_ids), 1);
for k = 1:numel(ibr_ids)
    did = ibr_ids{k};
    bus = case_data.devices.(did).bus;
    if nargin >= 4 && strcmp(did, gfm_device_id)
        mode = 'GFM';
    else
        mode = 'gfl';
    end
    disp_MW = dispatch.(did);
    dev_cells{k} = fixtures.synthetic_ibr_equilibrium( ...
        string(did), bus, mode, disp_MW);
end
devs = vertcat(dev_cells{:});
end
