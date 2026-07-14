function tests = test_ieee14_1sg_4ibr_phase4()
%TEST_IEEE14_1SG_4IBR_PHASE4  Phase 4 mixed-equilibrium + case contract tests.
%   Verifies: SG1 dynamics sourced (Kodsi); dispatch contract (Pmax-proportional,
%   no load-shed); mixed equilibrium solver (SG online+4gfl, SG offline+GFM,
%   pure-GFL reject); fixed angle-gauge; deterministic fingerprint.
%
%   Source: project Phase 4 design (Plan agent). Production devices (Phase B1+).
%   Updated: removed synthetic stubs + config.sg_status; uses index-based config.
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
% SG online + 4 IBR gfl: production devices, index-based config.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devs = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
config = struct('devices', devs);
r = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(r.converged, ['SG online equilibrium must converge: ' r.failure_reason]);
testCase.verifyLessThan(r.residual_norm, 1e-6, 'residual within tolerance.');
testCase.verifyGreaterThan(r.rcond, 1e-10, 'reduced Jacobian well-conditioned.');
testCase.verifyLessThan(r.physical_kcl_norm,1e-6,'Every SG_ON KCL row passes.');
testCase.verifyEqual(r.vcon_vars,[1 2],'AbsTol',0, ...
    'REF bus fixes both Vm and angle in rectangular coordinates.');
testCase.verifyEqual(r.vcon_ref,[1.06;0],'AbsTol',0);
testCase.verifyEqual(r.reference.slack_input_names,{'Tm','Efd'});
end

% =========================================================================
function test_mixed_equilibrium_sg_off_gfm(testCase)
% SG offline: IBR2=GFM, IBR3/6/8=gfl. Production devices, index-based config.
% The reduced all-KCL initializer reconstructs exact per-device states from
% its solved terminal P/Q; the constructor warm-start is not treated as a root.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'GFM','gfl','gfl','gfl'});
disp_s = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
devs = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
% Set SG1 offline (breaker open)
for k = 1:numel(devs)
    if strcmp(devs(k).device_type, 'sg_emf6_composite')
        devs(k).initial_online = false;
        devs(k).mode = 'breaker_open';
        break;
    end
end
config = struct('devices', devs,'selected_gfm_indices',2, ...
    'n_gfm_required',1,'reference_resource_index',2);
r = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(r.converged, ['SG offline+GFM equilibrium must converge: ' r.failure_reason]);
testCase.verifyLessThan(r.residual_norm, 1e-6, 'residual within tolerance.');
testCase.verifyGreaterThan(r.rcond, 1e-10, 'reduced Jacobian well-conditioned.');
testCase.verifyLessThan(r.physical_kcl_norm,1e-6,'Every physical KCL row passes.');
testCase.verifyTrue(r.reference.balances_active_power,'Selected GFM is explicit P-balancing reference.');
end

% =========================================================================
function test_pure_gfl_island_rejected(testCase)
% All IBRs gfl + SG offline -> no voltage-forming source -> fail closed.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
devs = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
% Set SG1 offline
for k = 1:numel(devs)
    if strcmp(devs(k).device_type, 'sg_emf6_composite')
        devs(k).initial_online = false;
        devs(k).mode = 'breaker_open';
        break;
    end
end
config = struct('devices', devs);
r = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyFalse(r.converged, 'pure-GFL SG_OFF must not converge.');
testCase.verifyEqual(r.failure_id, 'mixed_equilibrium_solve:noVoltageFormingSource', ...
    'fails closed with noVoltageFormingSource.');
end

% =========================================================================
function test_equilibrium_fingerprint_deterministic(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devs = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
config = struct('devices', devs);
r1 = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
r2 = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyEqual(r1.fingerprint.config_hash, r2.fingerprint.config_hash, ...
    'AbsTol', 0, 'same config_hash.');
testCase.verifyEqual(r1.fingerprint.x0_hash, r2.fingerprint.x0_hash, ...
    'AbsTol', 0, 'same x0_hash (deterministic Newton).');
end

% =========================================================================
function test_reference_gauge_fixed(testCase)
% The gauge follows the selected voltage-forming resource index. For an
% SG-off GFM reference it eliminates only Im(Vref); every physical KCL row is
% retained and the reference P input supplies the balancing degree of freedom.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes_on = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
                  'mode',{'gfl','gfl','gfl','gfl'});
disp_on = struct('IBR2',40,'IBR3',0,'IBR6',0,'IBR8',0);
devs_on = ibr.build_ieee14_sg_ibr_devices(c, modes_on, disp_on);
cfg_on = struct('devices', devs_on);
modes_off = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
                   'mode',{'GFM','gfl','gfl','gfl'});
disp_off = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
devs_off = ibr.build_ieee14_sg_ibr_devices(c, modes_off, disp_off);
for k = 1:numel(devs_off)
    if strcmp(devs_off(k).device_type, 'sg_emf6_composite')
        devs_off(k).initial_online = false;
        devs_off(k).mode = 'breaker_open';
        break;
    end
end
cfg_off = struct('devices', devs_off, ...
    'selected_gfm_indices',2,'n_gfm_required',1, ...
    'reference_resource_index',2);
r_on = stability.mixed_equilibrium_solve(c, cfg_on, struct('verbose',false));
r_off = stability.mixed_equilibrium_solve(c, cfg_off, struct('verbose',false));
testCase.verifyEqual(r_on.vcon_vars,[1 2],'AbsTol',0, ...
    'SG REF fixes Re(V1)=Vm and Im(V1)=0 while Tm/Efd are solved.');
testCase.verifyEqual(r_on.vcon_ref,[1.06;0],'AbsTol',0);
testCase.verifyLessThan(r_on.physical_kcl_norm,1e-6);
testCase.verifyEqual(r_off.vcon_vars,4,'AbsTol',0,'IBR2 bus-2 gauge.');
testCase.verifyEqual(r_off.reference.device_index,2,'AbsTol',0);
testCase.verifyTrue(r_off.reference.balances_active_power);
testCase.verifyEqual(r_off.vcon_type,'coordinate_elimination_all_kcl');
testCase.verifyLessThan(r_off.physical_kcl_norm,1e-6, ...
    'No physical KCL row may be replaced by the angle coordinate.');
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
