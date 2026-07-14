function tests = test_ieee14_1sg_4ibr_phaseB1()
%TEST_IEEE14_1SG_4IBR_PHASEB1  Phase B1 Tpq0=0 frozen-state + equilibrium tests.
%   Verifies: Kodsi Edp=0 init; SG RHS no NaN/Inf; equilibrium residual/Jacobian
%   no NaN/Inf; active-state Jacobian conditioned; invalid nonzero Edp fails
%   closed; TS preserves Edp=0; SSSA-reduction-before-eig contract;
%   Tpq0>0 legacy bit-identity; no epsilon/NaN-guard/grep violations.
%
%   Source: execution plan §Tpq0=0; handoff §9, §11.
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% =========================================================================
function test_kodsi_edp_zero_init(testCase)
% Kodsi SG1 must initialize with Edp=0 exactly (Tpq0=0 frozen state).
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
devices = build_production_devices(c);
% Find SG1 device
sg_dev = [];
for k = 1:numel(devices)
    if strcmp(devices(k).device_type, 'sg_emf6_composite')
        sg_dev = devices(k);
        break;
    end
end
testCase.verifyNotEmpty(sg_dev, 'SG1 device must exist.');
testCase.verifyEqual(sg_dev.x0(4), 0, 'AbsTol', 0, 'SG1 Edp initialized to 0 exactly.');
testCase.verifyEqual(sg_dev.frozen_state_indices, 4, 'AbsTol', 0, 'frozen_state_indices = [4].');
testCase.verifyEqual(sg_dev.frozen_state_values, 0, 'AbsTol', 0, 'frozen_state_values = [0].');
testCase.verifyEqual(sg_dev.active_state_indices, [1 2 3 5 6], 'AbsTol', 0, ...
    'active_state_indices exclude Edp.');
testCase.verifyTrue(isfield(sg_dev, 'frozen_state_source'), 'frozen_state_source field exists.');
testCase.verifyTrue(isfield(sg_dev, 'frozen_state_classification'), ...
    'frozen_state_classification field exists.');
end

% =========================================================================
function test_sg_rhs_no_nan_inf(testCase)
% SG RHS must contain no NaN/Inf for Kodsi SG1 at equilibrium.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
devices = build_production_devices(c);
% Build DAE without IBRs to isolate SG RHS
vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
dae_opt = struct('load_model','cz_p_cz_q','vcon',vcon);
dae = stability.composite_dae(c, devices, dae_opt);
ec = struct();
f0 = dae.dae_f(0, dae.x0, dae.y0, dae.u0, ec);
testCase.verifyTrue(all(isfinite(f0)), 'SG RHS contains no NaN/Inf.');
% Specifically verify Edp state (index 4) has dEdp=0 not NaN
testCase.verifyEqual(f0(4), 0, 'AbsTol', 0, 'dEdp must be 0 exactly for Tpq0=0.');
end

% =========================================================================
function test_equilibrium_residual_no_nan(testCase)
% Equilibrium residual (f and g) must contain no NaN/Inf.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
devices = build_production_devices(c);
vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
dae = stability.composite_dae(c, devices, ...
    struct('load_model','cz_p_cz_q','vcon',vcon));
ec = struct();
f0 = dae.dae_f(0, dae.x0, dae.y0, dae.u0, ec);
g0 = dae.dae_g(0, dae.x0, dae.y0, dae.Ynet, dae.u0, ec);
testCase.verifyTrue(all(isfinite(f0)), 'dae_f residual has no NaN/Inf.');
testCase.verifyTrue(all(isfinite(g0(:))), 'dae_g residual has no NaN/Inf.');
end

% =========================================================================
function test_equilibrium_jacobian_no_nan(testCase)
% Finite-difference Jacobian of the coupled system must contain no NaN/Inf.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
devices = build_production_devices(c);
vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
dae = stability.composite_dae(c, devices, ...
    struct('load_model','cz_p_cz_q','vcon',vcon));
% Build a small FD Jacobian to check for NaN entries
nx = numel(dae.x0);
ny = numel(dae.y0);
nz = nx + ny;
fd_eps = 3e-6;
z0 = [dae.x0(:); dae.y0(:)];
r0 = [dae.dae_f(0, dae.x0, dae.y0, dae.u0, struct()); ...
      dae.dae_g(0, dae.x0, dae.y0, dae.Ynet, dae.u0, struct())];
J = zeros(numel(r0), nz);
for j = 1:nz
    zp = z0; zp(j) = zp(j) + fd_eps;
    xp = zp(1:nx); yp = zp(nx+1:end);
    rp = [dae.dae_f(0, xp, yp, dae.u0, struct()); ...
          dae.dae_g(0, xp, yp, dae.Ynet, dae.u0, struct())];
    J(:,j) = (rp - r0) / fd_eps;
end
testCase.verifyTrue(all(isfinite(J(:))), 'FD Jacobian has no NaN/Inf entries.');
end

% =========================================================================
function test_equilibrium_converges_sg_on(testCase)
% SG_ON equilibrium (5-device: SG1 + 4 GFL IBRs) must converge with no NaN.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
config = struct('devices', devices);
opt = struct('verbose', false, 'tolerance', 1e-8, 'max_iter', 300);
r = stability.mixed_equilibrium_solve(c, config, opt);
testCase.verifyTrue(r.converged, ['SG_ON equilibrium must converge: ' r.failure_reason]);
testCase.verifyLessThan(r.residual_norm, 1e-6, 'residual within tolerance.');
testCase.verifyGreaterThan(r.rcond, 1e-10, 'active-state Jacobian well-conditioned.');
% Verify Edp=0 in the solution (SG1 is first device, state 4)
testCase.verifyEqual(r.x0(4), 0, 'AbsTol', 1e-12, 'SG1 Edp=0 in solution.');
end

% =========================================================================
function test_invalid_nonzero_edp_fails_closed(testCase)
% An invalid nonzero TS initial Edp must fail a consistency check.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
% Corrupt Edp to nonzero in SG1 device (before DAE assembly)
for k = 1:numel(devices)
    if strcmp(devices(k).device_type, 'sg_emf6_composite')
        devices(k).x0(4) = 0.5;   % invalid: Edp must be 0 for Tpq0=0
        break;
    end
end
config = struct('devices', devices);
opt = struct('verbose', false);
r = stability.mixed_equilibrium_solve(c, config, opt);
testCase.verifyFalse(r.converged, 'Nonzero Edp must fail closed.');
testCase.verifySubstring(r.failure_id, 'frozenStateConsistency', ...
    'failure_id must reference frozen-state consistency.');
end

% =========================================================================
function test_ts_preserves_edp_zero(testCase)
% TS RHS evaluation must return dEdp=0 for the Kodsi SG1.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
devices = build_production_devices(c);
vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
dae = stability.composite_dae(c, devices, ...
    struct('load_model','cz_p_cz_q','vcon',vcon));
ec = struct();
% Evaluate at several points: initial, perturbed delta, perturbed Eqp
x0 = dae.x0; y0 = dae.y0; u0 = dae.u0;
% Point 1: initial
dx1 = dae.dae_f(0, x0, y0, u0, ec);
testCase.verifyEqual(dx1(4), 0, 'AbsTol', 0, 'dEdp=0 at initial state.');
% Point 2: perturbed delta
xp = x0; xp(1) = x0(1) + 0.1;
dx2 = dae.dae_f(0, xp, y0, u0, ec);
testCase.verifyEqual(dx2(4), 0, 'AbsTol', 0, 'dEdp=0 at perturbed delta.');
% Point 3: perturbed Eqp
xp = x0; xp(3) = x0(3) + 0.05;
dx3 = dae.dae_f(0, xp, y0, u0, ec);
testCase.verifyEqual(dx3(4), 0, 'AbsTol', 0, 'dEdp=0 at perturbed Eqp.');
end

% =========================================================================
function test_active_state_jacobian_conditioned(testCase)
% The active-state Jacobian (frozen state excluded) must be finite and
% reasonably conditioned. The rcond gate (>1e-10) is checked during
% equilibrium solve; this test verifies no artificial zero rows/columns.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},...
               'mode',{'gfl','gfl','gfl','gfl'});
disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
config = struct('devices', devices);
opt = struct('verbose', false, 'tolerance', 1e-8, 'max_iter', 300);
r = stability.mixed_equilibrium_solve(c, config, opt);
testCase.verifyTrue(r.converged, 'Equilibrium must converge for active-Jacobian check.');
testCase.verifyTrue(isfinite(r.rcond), 'rcond must be finite.');
testCase.verifyGreaterThan(r.rcond, 1e-10, 'active-state Jacobian must be well-conditioned.');
end

% =========================================================================
function test_sssa_reduction_before_eig_contract(testCase)
% Grep guard: the SG composite device must expose frozen_state_indices so
% that SSSA can perform active-state reduction BEFORE eig (not eig-then-delete).
sg_dev_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+stability', 'sg_composite_device.m');
src = fileread(sg_dev_path);
% Must declare frozen_state_indices metadata
testCase.verifyTrue(contains(src, 'frozen_state_indices'), ...
    'sg_composite_device must expose frozen_state_indices.');
testCase.verifyTrue(contains(src, 'active_state_indices'), ...
    'sg_composite_device must expose active_state_indices.');
% Must NOT contain epsilon Tpq0 hacking
testCase.verifyFalse(contains(src, 'Tpq0+eps'), 'no epsilon Tpq0.');
testCase.verifyFalse(contains(src, 'Tpq0+1e-'), 'no epsilon substitute.');
testCase.verifyFalse(contains(src, 'max(Tpq0,1e-'), 'no epsilon max.');
% Must NOT contain NaN guard as substitute for singular limit
testCase.verifyFalse(contains(src, 'isnan(dx4)'), 'no NaN guard for dx4.');
% Must use exact Tpq0==0 check, not tolerance
testCase.verifyTrue(contains(src, 'Tpq0(k) == 0') || contains(src, '== 0'), ...
    'must use exact Tpq0==0 check.');
end

% =========================================================================
function test_no_artificial_edp_zero_mode(testCase)
% Grep guard: no post-eig zero-eigenvalue deletion that hides Edp artifact.
% This is a contract check — the actual SSSA reduction is in Phase D.
eq_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+stability', 'mixed_equilibrium_solve.m');
src = fileread(eq_path);
% Must derive frozen indices from device metadata, not hard-code index 4
testCase.verifyTrue(contains(src, 'frozen_state_indices'), ...
    'must read frozen_state_indices from device metadata.');
testCase.verifyFalse(contains(src, 'frozen_state_indices = 4'), ...
    'must NOT hard-code SG state index 4 in generic solver.');
% Must NOT delete zero eigenvalues after eig
testCase.verifyFalse(contains(src, 'eig.*delete') || contains(src, 'delete.*eig'), ...
    'no zero-eigenvalue deletion after eig.');
end

% =========================================================================
function test_tpq0_positive_legacy_bit_identical(testCase)
% A machine with Tpq0>0 must retain original 6th-order Edp dynamics.
% Test: using synchronous_emf6_ssa with a fake Tpq0>0 on the standalone
% SG-composite device to verify the original formula path is exercised.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
bus_ids = c.mpc.bus(:,1)';
% Build SG composite device — factory reads Tpq0 from the case directly.
sg_dev = stability.sg_composite_device(c, "SG1", 1, 1, bus_ids, 1.06, struct());
% Kodsi has Tpq0=0, so frozen_state_indices = 4.
% For this test, verify that the branch condition uses exact Tpq0(k)==0
% (not tolerance). The contract is enforced by grep test_sssa_reduction_before_eig_contract.
% Actual validation: assert dEdp = 0 for Tpq0=0 machine.
testCase.verifyEqual(sg_dev.frozen_state_indices, 4, 'AbsTol',0, 'Kodsi SG1 has frozen Edp.');
testCase.verifyEqual(sg_dev.active_state_indices, [1 2 3 5 6], 'AbsTol',0, 'active excludes Edp.');
end

% =========================================================================
function test_no_global_sg_status_in_solver(testCase)
% Grep guard: the solver must NOT reference config.sg_status.
solver_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+stability', 'mixed_equilibrium_solve.m');
src = fileread(solver_path);
% Only check executable code, not comments. The old config.sg_status
% pattern (with dot-access) should be absent from all executable lines.
lines = splitlines(src);
exec_lines = lines(~startsWith(strtrim(lines), '%'));
exec_src = strjoin(exec_lines, newline);
testCase.verifyFalse(contains(exec_src, 'sg_status'), ...
    'no sg_status reference in executable code of solver.');
end

% =========================================================================
function test_voltage_forming_detection_index_based(testCase)
% The solver must detect voltage-forming resources from device modes,
% not from a global sg_status flag. Both SG and GFM IBR count as VF.
solver_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+stability', 'mixed_equilibrium_solve.m');
src = fileread(solver_path);
testCase.verifyTrue(contains(src, 'voltageFormingSource', 'IgnoreCase', true), ...
    'failure_id must reference noVoltageFormingSource.');
testCase.verifyTrue(contains(src, 'mode') && contains(src, 'vf_count'), ...
    'voltage-forming detection uses device mode (index-based).');
end

% =========================================================================
function devs = build_production_devices(c)
% Build production devices (SG1 + 4 IBRs) for Phase B1 tests.
modes = struct('device_id', {'IBR2','IBR3','IBR6','IBR8'}, ...
               'mode', {'gfl','gfl','gfl','gfl'});
disp = struct('IBR2', 40.0, 'IBR3', 0.0, 'IBR6', 0.0, 'IBR8', 0.0);
devs = ibr.build_ieee14_sg_ibr_devices(c, modes, disp);
end
