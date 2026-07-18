function tests = test_ibr_gfl_rms10_sssa()
%TEST_IBR_GFL_RMS10_SSSA  Profile B SSSA integration (SG1 + GFM + 3xRMS10).
%   Builds the IEEE14 1-SG + 4-IBR system with IBR3/6/8 as GFL-RMS10,
%   solves the online-SG equilibrium, and verifies composite_sssa_model
%   differentiates the same production device closures (no hand-built A).
%   This exercises the generic-ABI integration contract: SSSA differentiates
%   the SAME equations that TS integrates, assembled by the shared kernel.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();

c = cases.case_ieee14_1sg_4ibr_auto_vsg();
% Profile B: IBR2 GFM, IBR3/6/8 GFL-RMS10, SG1 online.
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
    'mode',{'GFM','gfl','gfl','gfl'}, ...
    'gfl_family',{'','rms10','rms10','rms10'});
dispatch = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
[devices,~] = ibr.build_ieee14_sg_ibr_devices(c,modes,dispatch);
cfg = struct('devices',devices,'device_modes',modes);
eq = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
testCase.assertTrue(eq.converged, eq.failure_reason);
testCase.assertLessThan(eq.physical_kcl_norm, 1e-6);

opt = struct('full_kcl',true,'u_eq',eq.u_eq, ...
    'event_context',eq.equilibrium_context, ...
    'active_state_indices',eq.active_state_indices);
sssa = stability.composite_sssa_model(devices,eq.x0,eq.y0,c,opt);

testCase.TestData.case_data = c;
testCase.TestData.devices = devices;
testCase.TestData.eq = eq;
testCase.TestData.sssa = sssa;
testCase.TestData.modes = modes;
end

function test_sssa_uses_shared_kernel_no_hand_built_A(testCase)
% The device supplies closures only; SSSA differentiates them via the shared
% composite_sssa_model kernel (A_full = fx - fy*(gy\gx)). No GFL-specific A.
s = testCase.TestData.sssa;
testCase.verifyTrue(all(isfinite(s.A_full(:))));
testCase.verifyEqual(size(s.A_full,1),size(s.A_full,2),'AbsTol',0);
testCase.verifyGreaterThan(s.gy_rcond,1e-10);
end

function test_sssa_active_dimension_matches_profile_B(testCase)
% Profile B: SG1(5 active; EMF6 angle gauge is a coordinate, not a state) +
% GFM_IBR2(13) + 3xRMS10(10) = 48 active states.
s = testCase.TestData.sssa;
eq = testCase.TestData.eq;
testCase.verifyEqual(s.nx_active, 48, 'AbsTol', 0);
testCase.verifyEqual(numel(eq.active_state_indices), 48, 'AbsTol', 0);
testCase.verifyEqual(size(s.A,1), 48, 'AbsTol', 0);
testCase.verifyEqual(numel(s.eigenvalues), 48, 'AbsTol', 0);
end

function test_sssa_eigenvalues_finite(testCase)
s = testCase.TestData.sssa;
ev = s.eigenvalues;
testCase.verifyTrue(all(isfinite(ev)));
testCase.verifyEqual(numel(ev), 48, 'AbsTol', 0);
end

function test_sssa_distinguishes_execution_from_stability(testCase)
% SSSA_EXECUTION_PASS (the kernel ran, finite eigenvalues) is distinct from
% PHYSICAL_STABILITY_RESULT. We do not require stability; we only require
% the kernel produced finite eigenvalues without tuning.
s = testCase.TestData.sssa;
testCase.verifyTrue(all(isfinite(s.eigenvalues)));
end
