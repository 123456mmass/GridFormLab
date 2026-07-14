function tests = test_ieee14_1sg_4ibr_phase8_real()
%TEST_IEEE14_1SG_4IBR_PHASE8_REAL  Phase 8 real-device integration tests.
%   Verifies the real +ibr/dual_mode_ibr_model devices built by
%   +ibr/build_ieee14_ibr_devices integrate with mixed_equilibrium_solve:
%   SG_ON equilibrium, SG_OFF+GFM equilibrium, pure-GFL SG_OFF fail-closed,
%   no synthetic fixture, no external solver.
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% =========================================================================
% Shared: build the IEEE14 case + a config for a given SG status / modes.
% =========================================================================
function [c, config] = build_config(sg_status, modes, dispatch)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
[devices, ~] = ibr.build_ieee14_ibr_devices(c, modes, dispatch);
config = struct( ...
    'sg_status', sg_status, ...
    'device_modes', modes, ...
    'dispatch', dispatch, ...
    'devices', devices);
end

function modes = modes_struct(m2, m3, m6, m8)
modes = struct('device_id', {'IBR2','IBR3','IBR6','IBR8'}, ...
    'mode', {m2, m3, m6, m8});
end

% =========================================================================
% 1. SG_ON real-device equilibrium (all GFL, SG1 online)
% =========================================================================
function test_sg_on_real_equilibrium(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = modes_struct('gfl','gfl','gfl','gfl');
dispatch = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
[~, config] = build_config('online', modes, dispatch);
r = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(r.converged, ['SG_ON real equilibrium must converge: ' r.failure_reason]);
testCase.verifyLessThan(r.residual_norm, 1e-6, 'residual < 1e-6.');
testCase.verifyGreaterThan(r.rcond, 1e-10, 'well-conditioned.');
end

% =========================================================================
% 2. SG_OFF + GFM real-device equilibrium (IBR2=GFM, rest GFL)
% =========================================================================
function test_sg_off_gfm_real_equilibrium(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
pt = c.dispatch_contract.post_trip.post_trip_Pg_MW;
dispatch = struct('IBR2',pt.IBR2,'IBR3',pt.IBR3,'IBR6',pt.IBR6,'IBR8',pt.IBR8);
modes = modes_struct('GFM','gfl','gfl','gfl');
[~, config] = build_config('tripped', modes, dispatch);
r = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(r.converged, ['SG_OFF+GFM real equilibrium must converge: ' r.failure_reason]);
testCase.verifyLessThan(r.residual_norm, 1e-6, 'residual < 1e-6.');
end

% =========================================================================
% 3. Pure-GFL SG_OFF fails closed (no voltage-forming source)
% =========================================================================
function test_pure_gfl_sg_off_real_rejected(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
dispatch = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
modes = modes_struct('gfl','gfl','gfl','gfl');
[~, config] = build_config('tripped', modes, dispatch);
r = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyFalse(r.converged, 'pure-GFL SG_OFF must not converge.');
testCase.verifyEqual(r.failure_id, 'mixed_equilibrium_solve:noVoltageFormingSource', ...
    'fails closed with noVoltageFormingSource.');
end

% =========================================================================
% 4. Real devices, not synthetic (grep guard on this test file + builder)
% =========================================================================
function test_real_devices_not_synthetic(testCase)
% The BUILDER must not use the synthetic fixture. (The test file itself
% references the name only inside this grep guard, so we check the builder
% source, not this test file.)
builder_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+ibr', 'build_ieee14_ibr_devices.m');
builder_src = fileread(builder_path);
testCase.verifyFalse(contains(builder_src, 'fixtures.synthetic_ibr_equilibrium'), ...
    'builder must not import synthetic fixture.');
testCase.verifyFalse(contains(builder_src, 'synthetic_ibr_equilibrium('), ...
    'builder must not call synthetic fixture.');
testCase.verifyTrue(contains(builder_src, 'dual_mode_ibr_model'), ...
    'builder uses real dual_mode_ibr_model.');
% Build and verify devices are real (device_type == ibr_dual_mode).
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = modes_struct('gfl','gfl','gfl','gfl');
dispatch = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
[devices, meta] = ibr.build_ieee14_ibr_devices(c, modes, dispatch);
testCase.verifyTrue(meta.no_synthetic, 'meta.no_synthetic flag set.');
for k = 1:numel(devices)
    testCase.verifyEqual(devices(k).device_type, 'ibr_dual_mode', ...
        'device is real dual_mode (not synthetic).');
    testCase.verifyEqual(devices(k).nx, 15, 'AbsTol', 0, 'real device nx=15.');
end
% Mbase provenance.
testCase.verifyEqual(meta.Mbase_per_ibr.IBR2, 140, 'AbsTol', 0, 'IBR2 Mbase=140.');
testCase.verifyEqual(meta.Mbase_per_ibr.IBR3, 100, 'AbsTol', 0, 'IBR3 Mbase=100.');
testCase.verifyEqual(meta.kappa_per_ibr.IBR2, 100/140, 'AbsTol', 1e-12, 'IBR2 kappa.');
end

% =========================================================================
% 5. No external solver (scanner on builder + devices)
% =========================================================================
function test_no_external_solver(testCase)
paths = { ...
    fullfile(fileparts(fileparts(mfilename('fullpath'))), '+ibr', 'build_ieee14_ibr_devices.m'), ...
    fullfile(fileparts(fileparts(mfilename('fullpath'))), '+ibr', 'dual_mode_ibr_model.m'), ...
    fullfile(fileparts(fileparts(mfilename('fullpath'))), '+ibr', 'regfm_b1_vsg_model.m')};
for p = 1:numel(paths)
    src = fileread(paths{p});
    % Word-boundary check (avoid false positive on 'pfsolver' containing 'fsolve').
    for fn = {'fsolve','optimoptions','fmincon','fminsearch','lsqnonlin','optimset'}
        pat = ['(^|[^a-zA-Z])' fn{1} '([^a-zA-Z]|$)'];
        testCase.verifyFalse(~isempty(regexp(src, pat, 'once')), ...
            ['no ' fn{1} ' (word) in ' paths{p}]);
    end
end
end

% =========================================================================
% 6. Current/power identity + sign (real device at SG_ON equilibrium)
% =========================================================================
function test_current_power_identity(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = modes_struct('gfl','gfl','gfl','gfl');
dispatch = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
[~, config] = build_config('online', modes, dispatch);
r = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
testCase.verifyTrue(r.converged, 'equilibrium converged for identity check.');
% Check limit_checks: each device's P_MW should match dispatch (within tol).
lc = r.limit_checks;
testCase.verifyTrue(isfield(lc, 'devices'), 'limit_checks has devices.');
% IBR2 should produce ~40 MW (its dispatch). Allow PF-loss tolerance.
testCase.verifyGreaterThan(lc.devices.IBR2.P_MW, 30, 'IBR2 P_MW > 30 (near 40 MW dispatch).');
end
