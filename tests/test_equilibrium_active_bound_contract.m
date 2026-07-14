function tests = test_equilibrium_active_bound_contract()
%TEST_EQUILIBRIUM_ACTIVE_BOUND_CONTRACT  G2 active-bound solver contract tests.
%   Exercises the corrected stability.active_bound_run outer active-set loop
%   and the end-to-end mixed_equilibrium_solve callback path using the
%   zero-current diagnostic fixture.
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% ===== Falsification coverage (a)-(n) =======================================

function test_interior_positive_raw_dot_remains_interior(testCase)
% (a) A strictly interior x with positive raw_dot classifies as interior.
    dev = fixtures.active_bound_diag_device(2.0, -0.5, 0.5);
    y = zeros(28, 1); y(9) = 1.0; y(10) = 0.0;   % bus_position 5
    specs = dev.equilibrium_constraint_specs([0.1; 0.0], y, [], struct());
    rg = specs(1).classify_fn([0.1; 0.0], y, [], struct());
    testCase.verifyEqual(rg, 'interior');
end

function test_interior_negative_raw_dot_remains_interior(testCase)
% (b) A strictly interior x with negative raw_dot classifies as interior.
    dev = fixtures.active_bound_diag_device(2.0, -0.5, 0.5);
    y = zeros(28, 1); y(9) = 1.0; y(10) = 0.0;
    specs = dev.equilibrium_constraint_specs([-0.1; 0.0], y, [], struct());
    rg = specs(1).classify_fn([-0.1; 0.0], y, [], struct());
    testCase.verifyEqual(rg, 'interior');
end

function test_upper_outward_classifies_upper(testCase)
% (c) x above hi classifies as upper.
    dev = fixtures.active_bound_diag_device(2.0, -0.5, 0.5);
    y = zeros(28, 1); y(9) = 1.0; y(10) = 0.0;
    specs = dev.equilibrium_constraint_specs([0.7; 0.0], y, [], struct());
    rg = specs(1).classify_fn([0.7; 0.0], y, [], struct());
    testCase.verifyEqual(rg, 'upper');
end

function test_upper_at_bound_with_inward_release(testCase)
% (c) x at upper bound with inward (negative) raw_dot releases to interior.
    dev = fixtures.active_bound_diag_device(-2.0, -0.5, 0.5);  % k<0: raw_dot=-2*x
    y = zeros(28, 1); y(9) = 1.0; y(10) = 0.0;
    specs = dev.equilibrium_constraint_specs([0.5; 0.0], y, [], struct());
    rg = specs(1).classify_fn([0.5; 0.0], y, [], struct());
    testCase.verifyEqual(rg, 'interior');
end

function test_lower_outward_classifies_lower(testCase)
% (d) x below lo classifies as lower.
    dev = fixtures.active_bound_diag_device(2.0, -0.5, 0.5);
    y = zeros(28, 1); y(9) = 1.0; y(10) = 0.0;
    specs = dev.equilibrium_constraint_specs([-0.7; 0.0], y, [], struct());
    rg = specs(1).classify_fn([-0.7; 0.0], y, [], struct());
    testCase.verifyEqual(rg, 'lower');
end

function test_lower_at_bound_with_inward_release(testCase)
% (d) x at lower bound with inward (positive) raw_dot releases to interior.
    dev = fixtures.active_bound_diag_device(-2.0, -0.5, 0.5);  % raw_dot=-2*x >0 at x=-0.5
    y = zeros(28, 1); y(9) = 1.0; y(10) = 0.0;
    specs = dev.equilibrium_constraint_specs([-0.5; 0.0], y, [], struct());
    rg = specs(1).classify_fn([-0.5; 0.0], y, [], struct());
    testCase.verifyEqual(rg, 'interior');
end

function test_zero_raw_dot_at_each_boundary_stays_active(testCase)
% Zero raw derivative at a boundary is complementarity-active, not interior.
    dev = fixtures.active_bound_diag_device(0.0, -0.5, 0.5);
    y = zeros(28, 1); y(9) = 1.0;
    specs = dev.equilibrium_constraint_specs([0.5; 0.0], y, [], struct());
    testCase.verifyEqual(specs(1).classify_fn([0.5; 0.0], y, [], struct()), 'upper');
    testCase.verifyEqual(specs(1).classify_fn([-0.5; 0.0], y, [], struct()), 'lower');
end

function test_ordinary_x_bound_residual_fn(testCase)
% (f) Ordinary x-bound residual_fn: interior=k*x, upper=x-hi, lower=x-lo.
    dev = fixtures.active_bound_diag_device(2.0, -0.5, 0.5);
    y = zeros(28, 1);
    specs = dev.equilibrium_constraint_specs([0.3; 0.0], y, [], struct());
    r_int = specs(1).residual_fn([0.3; 0.0], y, [], struct(), 'interior');
    testCase.verifyEqual(r_int, 0.6, 'AbsTol', 1e-12);
    r_up = specs(1).residual_fn([0.3; 0.0], y, [], struct(), 'upper');
    testCase.verifyEqual(r_up, -0.2, 'AbsTol', 1e-12);
    r_lo = specs(1).residual_fn([-0.3; 0.0], y, [], struct(), 'lower');
    testCase.verifyEqual(r_lo, 0.2, 'AbsTol', 1e-12);
end

function test_voltage_style_residual_fn_no_hardcoded_arithmetic(testCase)
% (g) Voltage-style residual uses |Vbus|+kiv*x, proving residual_fn is invoked.
    dev = fixtures.active_bound_diag_device(2.0, -0.5, 0.5, 3.0, 0.95, 1.05);
    y = zeros(28, 1); y(9) = 1.0; y(10) = 0.0;   % |Vbus|=1.0
    specs = dev.equilibrium_constraint_specs([0.1; 0.05], y, [], struct());
    % EVSM = 1.0 + 3*0.05 = 1.15
    % upper residual = 1.15 - 1.05 = 0.10
    r_up = specs(2).residual_fn([0.1; 0.05], y, [], struct(), 'upper');
    testCase.verifyEqual(r_up, 0.10, 'AbsTol', 1e-9);
    % lower residual = 1.15 - 0.95 = 0.20
    r_lo = specs(2).residual_fn([0.1; 0.05], y, [], struct(), 'lower');
    testCase.verifyEqual(r_lo, 0.20, 'AbsTol', 1e-9);
    % interior = raw_dot = k*x2 = 2*0.05 = 0.10
    r_int = specs(2).residual_fn([0.1; 0.05], y, [], struct(), 'interior');
    testCase.verifyEqual(r_int, 0.10, 'AbsTol', 1e-9);
end

function test_infeasible_upper_projection(testCase)
% (e) A device forced to a value above hi must be projected/locked at upper.
    dev = fixtures.active_bound_diag_device(2.0, -0.5, 0.5);
    y = zeros(28, 1); y(9) = 1.0; y(10) = 0.0;
    specs = dev.equilibrium_constraint_specs([0.8; 0.0], y, [], struct());
    rg = specs(1).classify_fn([0.8; 0.0], y, [], struct());
    testCase.verifyEqual(rg, 'upper');
    % Upper residual forces x = hi when r=0.
    r_up = specs(1).residual_fn([0.8; 0.0], y, [], struct(), 'upper');
    testCase.verifyEqual(r_up, 0.3, 'AbsTol', 1e-12);  % 0.8 - 0.5
end

function test_infeasible_lower_projection(testCase)
% A state below its lower bound is classified lower and projected by equality.
    dev = fixtures.active_bound_diag_device(2.0, -0.5, 0.5);
    y = zeros(28, 1); y(9) = 1.0;
    specs = dev.equilibrium_constraint_specs([-0.8; 0.0], y, [], struct());
    testCase.verifyEqual( ...
        specs(1).classify_fn([-0.8; 0.0], y, [], struct()), 'lower');
    testCase.verifyEqual( ...
        specs(1).residual_fn([-0.8; 0.0], y, [], struct(), 'lower'), ...
        -0.3, 'AbsTol', 1e-12);
end

function test_admissible_fn_returns_logical_scalar(testCase)
% Callbacks return finite scalars / scalar logicals.
    dev = fixtures.active_bound_diag_device(2.0, -0.5, 0.5);
    y = zeros(28, 1); y(9) = 1.0; y(10) = 0.0;
    specs = dev.equilibrium_constraint_specs([0.1; 0.0], y, [], struct());
    for i = 1:2
        ok = specs(i).admissible_fn([0.1; 0.0], y, [], struct(), 'interior');
        testCase.verifyTrue(islogical(ok) && isscalar(ok));
        raw = specs(i).raw_dot_fn([0.1; 0.0], y, [], struct());
        testCase.verifyTrue(isfinite(raw) && isscalar(raw));
    end
end

% ===== Direct active_bound_run failure-ID contract tests ====================
% These build a minimal all_specs cell and a trivial base_residual_fn so the
% outer active-set loop is exercised in isolation.

function [specs_cell, base_res] = build_minimal_ab_setup(x0, classify_fn, residual_fn, raw_dot_fn, admissible_fn)
% One device, one constraint state at local_idx 1, offset 0, no inputs.
    entry.offset = 0;
    entry.u_offset = 0;
    entry.dev_nu = 0;
    entry.dev_nx = 1;
    s.local_idx = 1;
    s.classify_fn = classify_fn;
    s.residual_fn = residual_fn;
    s.raw_dot_fn = raw_dot_fn;
    s.admissible_fn = admissible_fn;
    s.description = 'minimal';
    entry.specs = s;
    specs_cell = {entry};
    % Base residual is just the unconstrained dx/dt = 0 target on state 1.
    base_res = @(z) z(1);
    % Suppress unused-output lint on x0 (kept for API symmetry).
    if isempty(x0), return; end
end

function test_active_bound_run_interior_success(testCase)
% (j)/(k) Interior regime that converges returns success with empty fail_id.
    classify = @(xd,y,u,ec) 'interior';
    residual = @(xd,y,u,ec,locked) 0.0;  % always-zero residual
    rawdot = @(xd,y,u,ec) 0.0;
    admissible = @(xd,y,u,ec,locked) true;
    [specs_cell, base_res] = build_minimal_ab_setup([0.0], ...
        classify, residual, rawdot, admissible);
    z0 = 0.0;
    [z_sol, niter, cv, rn, rc, fid, frs, oi, rh] = stability.active_bound_run( ...
        z0, base_res, 3e-6, 1, [], [], [], [], 0, 0, [], [], ...
        specs_cell, struct(), 1e-8, 50, false);
    testCase.verifyTrue(cv);
    testCase.verifyEqual(fid, '');
    testCase.verifyEqual(z_sol, 0.0, 'AbsTol', 1e-9);
    testCase.verifyEqual(oi, 1);
    testCase.verifyTrue(~isempty(rh));
end

function test_active_bound_run_bad_spec_missing_raw_dot_fn(testCase)
% (k) A spec missing raw_dot_fn yields badActiveBoundSpec.
    classify = @(xd,y,u,ec) 'interior';
    residual = @(xd,y,u,ec,locked) 0.0;
    admissible = @(xd,y,u,ec,locked) true;
    entry.offset = 0;
    entry.u_offset = 0;
    entry.dev_nu = 0;
    entry.dev_nx = 1;
    s.local_idx = 1;
    s.classify_fn = classify;
    s.residual_fn = residual;
    s.admissible_fn = admissible;
    s.description = 'missing raw_dot_fn';
    entry.specs = s;
    specs_cell = {entry};
    base_res = @(z) z(1);
    [z_sol, niter, cv, rn, rc, fid, frs, oi, rh] = stability.active_bound_run( ...
        0.0, base_res, 3e-6, 1, [], [], [], [], 0, 0, [], [], ...
        specs_cell, struct(), 1e-8, 50, false);
    testCase.verifyFalse(cv);
    testCase.verifyEqual(fid, 'mixed_equilibrium_solve:badActiveBoundSpec');
end

function test_active_bound_run_nonfinite_raw_dot(testCase)
% (k) A non-finite raw_dot_fn yields nonFiniteActiveBound.
    classify = @(xd,y,u,ec) 'interior';
    residual = @(xd,y,u,ec,locked) 0.0;
    rawdot = @(xd,y,u,ec) NaN;
    admissible = @(xd,y,u,ec,locked) true;
    [specs_cell, base_res] = build_minimal_ab_setup([0.0], ...
        classify, residual, rawdot, admissible);
    [z_sol, niter, cv, rn, rc, fid, frs, oi, rh] = stability.active_bound_run( ...
        0.0, base_res, 3e-6, 1, [], [], [], [], 0, 0, [], [], ...
        specs_cell, struct(), 1e-8, 50, false);
    testCase.verifyFalse(cv);
    testCase.verifyEqual(fid, 'mixed_equilibrium_solve:nonFiniteActiveBound');
end

function test_active_bound_run_bad_regime_value(testCase)
% (k) classify_fn returning an invalid regime string yields badActiveBoundSpec.
    classify = @(xd,y,u,ec) 'bogus';
    residual = @(xd,y,u,ec,locked) 0.0;
    rawdot = @(xd,y,u,ec) 0.0;
    admissible = @(xd,y,u,ec,locked) true;
    [specs_cell, base_res] = build_minimal_ab_setup([0.0], ...
        classify, residual, rawdot, admissible);
    [z_sol, niter, cv, rn, rc, fid, frs, oi, rh] = stability.active_bound_run( ...
        0.0, base_res, 3e-6, 1, [], [], [], [], 0, 0, [], [], ...
        specs_cell, struct(), 1e-8, 50, false);
    testCase.verifyFalse(cv);
    testCase.verifyEqual(fid, 'mixed_equilibrium_solve:badActiveBoundSpec');
end

function test_active_bound_run_inconsistent_admissibility(testCase)
% (k) Regime matches but admissible_fn returns false -> activeBoundInconsistent.
    % classify always returns 'upper'; residual forces z=hi=0.5 so Newton
    % converges to a fixed point; admissible then returns false.
    classify = @(xd,y,u,ec) 'upper';
    residual = @(xd,y,u,ec,locked) xd(1) - 0.5;  % r=0 => x=0.5
    rawdot = @(xd,y,u,ec) 1.0;  % positive => consistent with upper
    admissible = @(xd,y,u,ec,locked) false;  % but admissibility fails
    [specs_cell, base_res] = build_minimal_ab_setup([0.5], ...
        classify, residual, rawdot, admissible);
    [z_sol, niter, cv, rn, rc, fid, frs, oi, rh] = stability.active_bound_run( ...
        0.5, base_res, 3e-6, 1, [], [], [], [], 0, 0, [], [], ...
        specs_cell, struct(), 1e-8, 50, false);
    testCase.verifyFalse(cv);
    testCase.verifyEqual(fid, 'mixed_equilibrium_solve:activeBoundInconsistent');
end

function test_active_bound_run_residual_exception_is_returned(testCase)
% A bad residual callback must fail closed through failure_id, not escape.
    [specs_cell, base_res] = build_minimal_ab_setup(0.0, ...
        @(xd,y,u,ec) 'interior', @residual_throws, ...
        @(xd,y,u,ec) 0.0, @(xd,y,u,ec,locked) true);
    [~, ~, cv, ~, ~, fid] = stability.active_bound_run( ...
        0.0, base_res, 1e-6, 1, [], [], [], [], 0, 0, [], [], ...
        specs_cell, struct(), 1e-8, 10, false);
    testCase.verifyFalse(cv);
    testCase.verifyEqual(fid, 'mixed_equilibrium_solve:badActiveBoundSpec');
end

function test_active_bound_run_nonfinite_residual_is_returned(testCase)
% NaN from a locked residual is a nonFiniteActiveBound failure.
    [specs_cell, base_res] = build_minimal_ab_setup(0.0, ...
        @(xd,y,u,ec) 'interior', @(xd,y,u,ec,locked) NaN, ...
        @(xd,y,u,ec) 0.0, @(xd,y,u,ec,locked) true);
    [~, ~, cv, ~, ~, fid] = stability.active_bound_run( ...
        0.0, base_res, 1e-6, 1, [], [], [], [], 0, 0, [], [], ...
        specs_cell, struct(), 1e-8, 10, false);
    testCase.verifyFalse(cv);
    testCase.verifyEqual(fid, 'mixed_equilibrium_solve:nonFiniteActiveBound');
end

function test_active_bound_run_admissibility_exception_is_returned(testCase)
% An admissibility callback exception is a badActiveBoundSpec failure.
    [specs_cell, base_res] = build_minimal_ab_setup(0.0, ...
        @(xd,y,u,ec) 'interior', @(xd,y,u,ec,locked) 0.0, ...
        @(xd,y,u,ec) 0.0, @admissible_throws);
    [~, ~, cv, ~, ~, fid] = stability.active_bound_run( ...
        0.0, base_res, 1e-6, 1, [], [], [], [], 0, 0, [], [], ...
        specs_cell, struct(), 1e-8, 10, false);
    testCase.verifyFalse(cv);
    testCase.verifyEqual(fid, 'mixed_equilibrium_solve:badActiveBoundSpec');
end

function test_active_bound_run_reconstructs_solved_slack_input(testCase)
% The callback must see the current solved slack input on every residual call.
    entry.offset = 0;
    entry.u_offset = 0;
    entry.dev_nu = 1;
    entry.dev_nx = 1;
    s.local_idx = 1;
    s.classify_fn = @(xd,y,u,ec) 'interior';
    s.residual_fn = @(xd,y,u,ec,locked) xd(1) - u(1);
    s.raw_dot_fn = @(xd,y,u,ec) xd(1) - u(1);
    s.admissible_fn = @(xd,y,u,ec,locked) abs(u(1) - 2.0) < 1e-8;
    s.description = 'solved slack reconstruction';
    entry.specs = s;
    base_res = @(z) [z(1); z(2) - 2.0];
    [z_sol, ~, cv, ~, ~, fid] = stability.active_bound_run( ...
        [0.0; 1.0], base_res, 1e-6, 1, [], [], [], [], [], 0, 0.0, 1, ...
        {entry}, struct(), 1e-10, 20, false);
    testCase.verifyTrue(cv);
    testCase.verifyEqual(fid, '');
    testCase.verifyEqual(z_sol, [2.0; 2.0], 'AbsTol', 1e-9);
end

function test_active_bound_run_reports_newton_failure(testCase)
% A constant nonzero residual has a singular FD Jacobian and must fail closed.
    [specs_cell, base_res] = build_minimal_ab_setup(0.0, ...
        @(xd,y,u,ec) 'interior', @(xd,y,u,ec,locked) 1.0, ...
        @(xd,y,u,ec) 0.0, @(xd,y,u,ec,locked) true);
    [~, ~, cv, ~, ~, fid] = stability.active_bound_run( ...
        0.0, base_res, 1e-6, 1, [], [], [], [], 0, 0, [], [], ...
        specs_cell, struct(), 1e-10, 5, false);
    testCase.verifyFalse(cv);
    testCase.verifyEqual(fid, 'mixed_equilibrium_solve:activeBoundNewton');
end

function test_active_bound_run_detects_regime_cycle(testCase)
% upper -> lower -> upper repeats a previously visited locked set.
    [specs_cell, base_res] = build_minimal_ab_setup(0.0, ...
        @cycle_classify, @cycle_residual, ...
        @(xd,y,u,ec) 0.0, @(xd,y,u,ec,locked) true);
    [~, ~, cv, ~, ~, fid] = stability.active_bound_run( ...
        0.0, base_res, 1e-6, 1, [], [], [], [], 0, 0, [], [], ...
        specs_cell, struct(), 1e-10, 20, false);
    testCase.verifyFalse(cv);
    testCase.verifyEqual(fid, 'mixed_equilibrium_solve:activeBoundCycle');
end

function test_active_bound_run_reports_max_outer(testCase)
% A 2-cycle combined with a 3-cycle visits six unique regime sets; the
% predeclared five-outer limit therefore fires before the combined repeat.
    entry.offset = 0;
    entry.u_offset = 0;
    entry.dev_nu = 0;
    entry.dev_nx = 2;
    s1.local_idx = 1;
    s1.classify_fn = @cycle_classify;
    s1.residual_fn = @cycle_residual;
    s1.raw_dot_fn = @(xd,y,u,ec) 0.0;
    s1.admissible_fn = @(xd,y,u,ec,locked) true;
    s1.description = 'two-cycle';
    s2.local_idx = 2;
    s2.classify_fn = @three_cycle_classify;
    s2.residual_fn = @three_cycle_residual;
    s2.raw_dot_fn = @(xd,y,u,ec) 0.0;
    s2.admissible_fn = @(xd,y,u,ec,locked) true;
    s2.description = 'three-cycle';
    entry.specs = [s1; s2];
    [~, ~, cv, ~, ~, fid, ~, outer] = stability.active_bound_run( ...
        [0.0; 0.0], @(z) z, 1e-6, [1 2], [], [], [], [], 0, 0, [], [], ...
        {entry}, struct(), 1e-10, 20, false);
    testCase.verifyFalse(cv);
    testCase.verifyEqual(fid, 'mixed_equilibrium_solve:activeBoundMaxOuter');
    testCase.verifyEqual(outer, 5);
end

function test_no_external_solver_dependency(testCase)
% (n) No fsolve/optimization/external-solver references in active-bound path.
    for f = {'active_bound_run','active_bound_classify','active_bound_collect'}
        src = fileread(fullfile('+stability', [f{1} '.m']));
        testCase.verifyFalse(contains(src, 'fsolve'), f{1});
        testCase.verifyFalse(contains(src, 'optimoptions'), f{1});
        testCase.verifyFalse(contains(src, 'fmincon'), f{1});
        testCase.verifyFalse(contains(src, 'linprog'), f{1});
        testCase.verifyFalse(contains(src, 'lsqnonlin'), f{1});
    end
end

% ===== End-to-end mixed_equilibrium_solve callback-path tests ==============

function test_G1_empty_callback_identity(testCase)
% (n) An empty-callback device set must take the G1 fast path: identical to a
% pure composite_newton solve and leaves no active-bound fields populated.
    c = cases.case_ieee14_1sg_4ibr_auto_vsg();
    modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
                   'mode',{'gfl','gfl','gfl','gfl'});
    disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
    devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
    config = struct('devices', devices);
    eq = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
    testCase.verifyTrue(eq.converged, 'G1 equilibrium must converge.');
    % G1 path leaves the G2 regime-history field empty (no callback exercised).
    testCase.verifyEqual(eq.active_bound_outer_iterations, 0);
    testCase.verifyTrue(isempty(eq.active_bound_regime_history));
    testCase.verifyEqual(eq.failure_id, '');
end

function test_mixed_equilibrium_solve_enters_callback_path(testCase)
% (m) End-to-end: IEEE14 SG online + zero-current diagnostic device with a
% declared equilibrium_constraint_specs. The G2 active-bound path must be
% exercised (regime_history non-empty) and converge with KCL intact.
    c = cases.case_ieee14_1sg_4ibr_auto_vsg();
    modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
                   'mode',{'gfl','gfl','gfl','gfl'});
    disp_s = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
    devices = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
    % Add empty equilibrium_constraint_specs to each IEEE14 device so the
    % struct array fields match the diagnostic device (which declares one).
    for i = 1:numel(devices)
        devices(i).equilibrium_constraint_specs = [];
    end
    % Build a case_ctx so the diagnostic device adopts the real bus layout
    % and is structurally compatible for concatenation.
    ext_buses = c.mpc.bus(:,1).';
    case_ctx = struct('bus_id', 5, 'bus_position', 5, 'bus_ids', ext_buses);
    diag_dev = fixtures.active_bound_diag_device(2.0, -0.5, 0.5, ...
        3.0, 0.95, 1.05, case_ctx);
    % The production builder returns a column struct array (nd-by-1).
    % Append the diagnostic device along that existing device dimension.
    devices = [devices; diag_dev];
    config = struct('devices', devices);
    eq = stability.mixed_equilibrium_solve(c, config, struct('verbose',false));
    testCase.verifyTrue(eq.converged, 'G2 equilibrium must converge.');
    % The active-bound path must have been reached: regime history non-empty.
    testCase.verifyTrue(~isempty(eq.active_bound_regime_history), ...
        'active-bound path must be exercised when a device declares specs.');
    testCase.verifyEqual(eq.failure_id, '');
    % (l) Every physical KCL row retained: physical_kcl_norm must be ~0.
    testCase.verifyLessThan(eq.physical_kcl_norm, 1e-6, ...
        'Physical KCL residual must be ~0 (no KCL row removed).');
end

function test_no_KCL_rows_removed_in_solver_source(testCase)
% (l) Static check: the generic solver must never touch an algebraic/KCL row.
% The locked_residual only replaces rows whose z-index maps to a constrained
% differential state (found via active_x_idx); algebraic rows are untouched.
    src = fileread('+stability/active_bound_run.m');
    % The replacement path uses find(active_x == gidx), so only differential
    % rows can ever be replaced. Confirm no broad slice assignment that could
    % hit KCL rows (e.g. r(nx_active+1:end) = ...).
    testCase.verifyFalse(contains(src, 'r(nx_active+1:end)'));
    testCase.verifyFalse(contains(src, 'r(end-'));
    % residual_fn is invoked for every regime including interior.
    testCase.verifyTrue(contains(src, 'residual_fn(x_dev, y_full, u_dev, eq_ctx, reg)'));
end

function test_locked_regime_stable_across_FD(testCase)
% (i) The locked regime struct is captured once per outer iteration and passed
% unchanged into residual, line search, and FD evaluations. Verify by source
% inspection: wres/wjac closures share the same `locked` variable.
    src = fileread('+stability/active_bound_run.m');
    % wres and wjac both close over `locked` (the history{end} snapshot).
    testCase.verifyTrue(contains(src, 'locked = history{end};'));
    testCase.verifyTrue(contains(src, '@(wz) locked_residual(wz, locked,'));
    testCase.verifyTrue(contains(src, '@(wz) fd_jac(wz, wres, fd_eps);'));
end

function r = residual_throws(~, ~, ~, ~, ~)
    error('fixture:residualFailure', 'intentional residual callback failure');
    r = 0; %#ok<UNRCH>
end

function ok = admissible_throws(~, ~, ~, ~, ~)
    error('fixture:admissibilityFailure', 'intentional admissibility callback failure');
    ok = false; %#ok<UNRCH>
end

function regime = cycle_classify(xd, ~, ~, ~)
    if xd(1) < 0.5
        regime = 'upper';
    else
        regime = 'lower';
    end
end

function r = cycle_residual(xd, ~, ~, ~, locked)
    if strcmp(locked, 'upper')
        r = xd(1) - 1.0;
    else
        r = xd(1);
    end
end

function regime = three_cycle_classify(xd, ~, ~, ~)
    if xd(2) < 0.5
        regime = 'upper';
    elseif xd(2) < 1.5
        regime = 'interior';
    else
        regime = 'lower';
    end
end

function r = three_cycle_residual(xd, ~, ~, ~, locked)
    switch locked
        case 'upper'
            r = xd(2) - 1.0;
        case 'interior'
            r = xd(2) - 2.0;
        otherwise
            r = xd(2);
    end
end
