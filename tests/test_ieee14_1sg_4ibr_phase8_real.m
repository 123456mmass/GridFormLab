function tests = test_ieee14_1sg_4ibr_phase8_real()
%TEST_IEEE14_1SG_4IBR_PHASE8_REAL  Phase 8 real-device integration tests.
%   Verifies real production devices (SG1 + 4 dual-mode IBRs) integrate with
%   mixed_equilibrium_solve using index-based config (no sg_status global rule).
%   Updated for Phase B1: uses build_ieee14_sg_ibr_devices (SG+IBR together).
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% =========================================================================
function test_sg_on_real_equilibrium(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
config = struct('devices', devices);
r = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(r.converged, ['SG_ON real equilibrium must converge: ' r.failure_reason]);
testCase.verifyLessThan(r.residual_norm, 1e-6, 'residual < 1e-6.');
testCase.verifyGreaterThan(r.rcond, 1e-10, 'well-conditioned.');
end

% =========================================================================
function test_sg_off_gfm_real_equilibrium(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
pt = c.dispatch_contract.post_trip.post_trip_Pg_MW;
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'GFM','gfl','gfl','gfl'});
disp_s = struct('IBR2',pt.IBR2,'IBR3',pt.IBR3,'IBR6',pt.IBR6,'IBR8',pt.IBR8);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
% Set SG1 offline
for k = 1:numel(devices)
    if strcmp(devices(k).device_type, 'sg_emf6_composite')
        devices(k).initial_online = false;
        devices(k).mode = 'breaker_open';
        break;
    end
end
config = struct('devices', devices);
r = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(r.converged, ['SG_OFF+GFM real equilibrium must converge: ' r.failure_reason]);
testCase.verifyLessThan(r.residual_norm, 1e-6, 'residual < 1e-6.');
end

% =========================================================================
function test_pure_gfl_sg_off_real_rejected(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
% Set SG1 offline
for k = 1:numel(devices)
    if strcmp(devices(k).device_type, 'sg_emf6_composite')
        devices(k).initial_online = false;
        devices(k).mode = 'breaker_open';
        break;
    end
end
config = struct('devices', devices);
r = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyFalse(r.converged, 'pure-GFL SG_OFF must not converge.');
testCase.verifyEqual(r.failure_id, 'mixed_equilibrium_solve:noVoltageFormingSource', ...
    'fails closed with noVoltageFormingSource.');
end

% =========================================================================
function test_real_devices_not_synthetic(testCase)
% The BUILDER must use the generic engine (not synthetic fixture).
builder_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+ibr', 'build_ieee14_sg_ibr_devices.m');
builder_src = fileread(builder_path);
testCase.verifyFalse(contains(builder_src, 'fixtures.synthetic_ibr_equilibrium'), ...
    'builder must not import synthetic fixture.');
testCase.verifyTrue(contains(builder_src, 'build_mixed_resource_devices'), ...
    'builder delegates to generic build_mixed_resource_devices.');
% Build and verify devices include SG1 (real EMF6 device).
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
[devices, meta] = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
testCase.verifyTrue(meta.no_synthetic, 'meta.no_synthetic flag set.');
testCase.verifyEqual(numel(devices), 5, '5 devices (SG1 + 4 IBRs).');
testCase.verifyEqual(devices(1).device_type, 'sg_emf6_composite', 'SG1 is real EMF6.');
testCase.verifyEqual(devices(1).nx, 6, 'AbsTol', 0, 'SG1 nx=6.');
for k = 2:numel(devices)
    testCase.verifyEqual(devices(k).device_type, 'ibr_dual_mode', ...
        'IBR is real dual_mode.');
    testCase.verifyEqual(devices(k).nx, 15, 'AbsTol', 0, 'real IBR nx=15.');
end
end

% =========================================================================
function test_no_external_solver(testCase)
paths = { ...
    fullfile(fileparts(fileparts(mfilename('fullpath'))), '+ibr', 'build_ieee14_sg_ibr_devices.m'), ...
    fullfile(fileparts(fileparts(mfilename('fullpath'))), '+ibr', 'dual_mode_ibr_model.m'), ...
    fullfile(fileparts(fileparts(mfilename('fullpath'))), '+ibr', 'regfm_b1_vsg_model.m')};
for p = 1:numel(paths)
    src = fileread(paths{p});
    for fn = {'fsolve','optimoptions','fmincon','fminsearch','lsqnonlin','optimset'}
        pat = ['(^|[^a-zA-Z])' fn{1} '([^a-zA-Z]|$)'];
        testCase.verifyFalse(~isempty(regexp(src, pat, 'once')), ...
            ['no ' fn{1} ' (word) in ' paths{p}]);
    end
end
end

% =========================================================================
function test_current_power_identity(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
config = struct('devices', devices);
r = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(r.converged, 'equilibrium converged for identity check.');
lc = r.limit_checks;
testCase.verifyTrue(isfield(lc, 'devices'), 'limit_checks has devices.');
testCase.verifyGreaterThan(lc.devices.IBR2.P_MW, 30, 'IBR2 P_MW > 30 (near 40 MW dispatch).');
end
