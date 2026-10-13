function tests = test_composite_newton_contract()
%TEST_COMPOSITE_NEWTON_CONTRACT  Focused damped-Newton return contracts.
%   Falsifies two numerical-method failure modes:
%     1) a fully rejected backtracking search must not mutate the iterate;
%     2) J_FINAL and RCOND must describe the exact returned root, including
%        convergence at the caller-supplied initial point.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_rejected_line_search_preserves_last_accepted_point(testCase)
% A constant residual cannot satisfy the strict decrease acceptance gate.
% The supplied nonsingular Jacobian isolates the line-search return path.
z0 = 3;
residual_fn = @(~) 1;
jacobian_fn = @(~) 1;

[z_sol, niter, converged, residual_norm, rcond_val, J_final] = ...
    stability.composite_newton(z0, residual_fn, jacobian_fn, ...
    1e-12, 5, false);

testCase.verifyFalse(converged);
testCase.verifyEqual(niter, 1, 'AbsTol', 0);
testCase.verifyEqual(z_sol, z0, 'AbsTol', 0, ...
    'A rejected trial step must never alter the last accepted iterate.');
testCase.verifyEqual(residual_norm, 1, 'AbsTol', 0);
testCase.verifyEqual(J_final, 1, 'AbsTol', 0);
testCase.verifyEqual(rcond_val, 1, 'AbsTol', 0);
end

function test_initial_root_reports_final_jacobian_condition(testCase)
% An initial-root return still owes callers a Jacobian and conditioning
% diagnostic evaluated at the returned point.
A = [2, 0; 0, 0.5];
z0 = [1; -2];
b = A * z0;
residual_fn = @(z) A * z - b;
jacobian_fn = @(~) A;

[z_sol, niter, converged, residual_norm, rcond_val, J_final] = ...
    stability.composite_newton(z0, residual_fn, jacobian_fn, ...
    1e-12, 5, false);

testCase.verifyTrue(converged);
testCase.verifyEqual(niter, 1, 'AbsTol', 0);
testCase.verifyEqual(z_sol, z0, 'AbsTol', 0);
testCase.verifyEqual(residual_norm, 0, 'AbsTol', 0);
testCase.verifyEqual(J_final, A, 'AbsTol', 0);
testCase.verifyTrue(isfinite(rcond_val));
testCase.verifyEqual(rcond_val, rcond(A), 'AbsTol', 0);
end

function test_converged_step_reports_jacobian_at_solution(testCase)
% This system reaches its root in one Newton step, while its Jacobian
% changes between the initial point and the root.
z0 = [0; 0];
residual_fn = @(z) [z(1) - 1; (1 + z(1)) * z(2)];
jacobian_fn = @(z) [1, 0; z(2), 1 + z(1)];
J_at_root = [1, 0; 0, 2];

[z_sol, niter, converged, residual_norm, rcond_val, J_final] = ...
    stability.composite_newton(z0, residual_fn, jacobian_fn, ...
    1e-12, 5, false);

testCase.verifyTrue(converged);
testCase.verifyEqual(niter, 2, 'AbsTol', 0);
testCase.verifyEqual(z_sol, [1; 0], 'AbsTol', 0);
testCase.verifyEqual(residual_norm, 0, 'AbsTol', 0);
testCase.verifyEqual(J_final, J_at_root, 'AbsTol', 0);
testCase.verifyEqual(rcond_val, rcond(J_at_root), 'AbsTol', 0);
end

function test_default_opt_preserves_six_output_legacy_behavior(testCase)
% Omitted OPT must reproduce the six-output legacy contract exactly:
% the first six outputs and the exception behavior are unchanged.
A = [2, 0; 0, 0.5];
z0 = [1; -2];
b = A * z0;
residual_fn = @(z) A * z - b;
jacobian_fn = @(~) A;

[z6, n6, c6, r6, rc6, J6] = stability.composite_newton(z0, residual_fn, ...
    jacobian_fn, 1e-12, 5, false);
[z7, n7, c7, r7, rc7, J7, info7] = stability.composite_newton(z0, residual_fn, ...
    jacobian_fn, 1e-12, 5, false, struct());

testCase.verifyEqual(z7, z6, 'AbsTol', 0);
testCase.verifyEqual(n7, n6, 'AbsTol', 0);
testCase.verifyEqual(c7, c6, 'AbsTol', 0);
testCase.verifyEqual(r7, r6, 'AbsTol', 0);
testCase.verifyEqual(rc7, rc6, 'AbsTol', 0);
testCase.verifyEqual(J7, J6, 'AbsTol', 0);
% Additive info shape is always present and clean on the legacy path.
testCase.verifyEqual(info7.domain_rejected_trials, 0, 'AbsTol', 0);
testCase.verifyFalse(info7.line_search_exhausted);
testCase.verifyTrue(isfield(info7,'residual_before_line_search'));
testCase.verifyTrue(isfield(info7,'final_tested_alpha'));
testCase.verifyTrue(isfield(info7,'minimum_trial_voltage'));
testCase.verifyTrue(isfield(info7,'final_domain_violation'));
testCase.verifyTrue(isfield(info7,'minimum_voltage_violation'));
end

function test_domain_trial_rejected_then_smaller_alpha_accepted(testCase)
% A classified domain exception on the full-step trial must be treated as a
% rejected trial: alpha is halved via the EXISTING backtracking and the
% accepted iterate comes only from the smaller-alpha valid trial.
%  f(z) = [z1 - 2; z2 - 0.5]  with root [2;0.5]; from z0=[0;1], r=[-2;0.5],
%  J=I, dz=[2;-0.5]; full step z_new=[2;0.5]=root. We throw the domain ID
%  ONLY on the FIRST evaluation at the root (one-shot nested-function flag),
%  so the alpha=0.5 trial [1;0.75] is accepted and the next iteration
%  converges without re-throwing at the root.
z0 = [0; 1];
root = [2; 0.5];
thrown = false;  % shared workspace for the nested closure
    function r = rfn(z)
        if ~thrown && abs(z(1) - root(1)) < 1e-12 && abs(z(2) - root(2)) < 1e-12
            thrown = true;
            error('ibr:gfl_rms10_model:lowVoltagePowerInversion', ...
                'Trial outside the runtime voltage domain.');
        end
        r = [z(1) - root(1); z(2) - root(2)];
    end
residual_fn = @rfn;
jacobian_fn = @(~) [1, 0; 0, 1];

opt = struct( ...
    'trial_exception_classifier', @(me) strcmp(me.identifier, ...
        'ibr:gfl_rms10_model:lowVoltagePowerInversion'), ...
    'trial_exception_diagnostic', @(z_trial,~) struct( ...
        'minimum_trial_voltage', abs(z_trial(2)), ...
        'violating_devices', empty_violating_devices()));

[z_sol, ~, converged, ~, ~, ~, info] = stability.composite_newton( ...
    z0, residual_fn, jacobian_fn, 1e-12, 20, false, opt);

testCase.verifyTrue(converged);
testCase.verifyEqual(z_sol, root, 'AbsTol', 1e-9, ...
    'Accepted iterate must come from the smaller-alpha valid trial, not the rejected one.');
testCase.verifyEqual(info.domain_rejected_trials, 1, 'AbsTol', 0);
testCase.verifyFalse(info.line_search_exhausted);
% The rejected trial's voltage (|z2| at full step = 0.5) is recorded.
testCase.verifyEqual(info.minimum_trial_voltage, 0.5, 'AbsTol', 0);
end

function test_all_domain_trials_exhaust(testCase)
% When every line-search trial throws the classified domain ID, the solve
% must fail closed at the last accepted point with bounded diagnostics.
% The residual is VALID at z0 (so the current-iterate evaluation does not
% throw) but throws the domain ID for every trial z_new != z0.
z0 = [0.5; 0];
residual_fn = @(z) domain_test_residual_throw_off_anchor(z, z0);
jacobian_fn = @(~) [1, 0; 0, 1];

opt = struct( ...
    'trial_exception_classifier', @(me) strcmp(me.identifier, ...
        'ibr:gfl_rms10_model:lowVoltagePowerInversion'), ...
    'trial_exception_diagnostic', @(z_trial,~) struct( ...
        'minimum_trial_voltage', abs(z_trial(1)), ...
        'violating_devices', empty_violating_devices()));

[z_sol, niter, converged, residual_norm, ~, ~, info] = stability.composite_newton( ...
    z0, residual_fn, jacobian_fn, 1e-12, 5, false, opt);

testCase.verifyFalse(converged);
testCase.verifyEqual(niter, 1, 'AbsTol', 0);
testCase.verifyEqual(z_sol, z0, 'AbsTol', 0, ...
    'A rejected trial must never alter the last accepted iterate.');
testCase.verifyEqual(residual_norm, norm(residual_fn(z0), inf), 'AbsTol', 0);
testCase.verifyEqual(info.domain_rejected_trials, 20, 'AbsTol', 0);
testCase.verifyTrue(info.line_search_exhausted);
testCase.verifyEqual(info.final_tested_alpha, 2^-19, 'AbsTol', 0);
testCase.verifyEqual(info.residual_before_line_search, ...
    norm(residual_fn(z0), inf), 'AbsTol', 0);
end

function r = domain_test_residual_throw_off_anchor(z, anchor)
% Valid residual at the anchor; throws the domain ID for any trial that
% has moved off the anchor (i.e., every line-search trial z_new = z + alpha*dz
% with alpha > 0). This isolates the line-search exhaustion path.
if norm(z - anchor, inf) > 1e-12
    error('ibr:gfl_rms10_model:lowVoltagePowerInversion', ...
        'Trial outside the runtime voltage domain.');
end
r = [z(1) - 2; z(2)];
end

function test_non_domain_exception_rethrows_immediately(testCase)
% An exception whose identifier is NOT the confirmed domain ID must
% propagate unchanged: no alpha halving, no swallowed root failure.
z0 = [0; 0];
residual_fn = @(z) bad_state_residual(z);
jacobian_fn = @(~) [1, 0; 0, 1];
opt = struct( ...
    'trial_exception_classifier', @(me) strcmp(me.identifier, ...
        'ibr:gfl_rms10_model:lowVoltagePowerInversion'));

thrown = false;
got_id = '';
try
    stability.composite_newton(z0, residual_fn, jacobian_fn, 1e-12, 5, false, opt);
catch me
    thrown = true;
    got_id = me.identifier;
end
testCase.verifyTrue(thrown, 'Non-domain exception must propagate.');
testCase.verifyEqual(got_id, 'ibr:gfl_rms10_model:badState');
end

function r = bad_state_residual(~)
% Always throws the non-domain badState ID (returns nothing because it
% always throws; the throw propagates before the missing return matters).
error('ibr:gfl_rms10_model:badState', 'Hard error must propagate.');
end

function test_domain_exception_at_accepted_point_rethrows(testCase)
% A classified domain exception at the CURRENT/INITIAL residual evaluation
% (not a line-search trial) must propagate; the accepted point is invalid
% and must not be relabeled as a rejected trial.
z0 = [0; 0];
residual_fn = @(z) accepted_point_domain_throw(z);
jacobian_fn = @(~) [1, 0; 0, 1];
opt = struct( ...
    'trial_exception_classifier', @(me) strcmp(me.identifier, ...
        'ibr:gfl_rms10_model:lowVoltagePowerInversion'));

thrown = false;
got_id = '';
try
    stability.composite_newton(z0, residual_fn, jacobian_fn, 1e-12, 5, false, opt);
catch me
    thrown = true;
    got_id = me.identifier;
end
testCase.verifyTrue(thrown);
testCase.verifyEqual(got_id, 'ibr:gfl_rms10_model:lowVoltagePowerInversion');
end

function r = accepted_point_domain_throw(~)
% Always throws the domain ID at the current point; composite_newton must
% not relabel it as a rejected trial.
error('ibr:gfl_rms10_model:lowVoltagePowerInversion', 'Accepted point invalid.');
end

function test_domain_exception_from_jacobian_rethrows(testCase)
% A classified domain exception raised by the Jacobian/FD evaluation must
% propagate (no line-search alpha owns an FD perturbation).
z0 = [0; 0];
residual_fn = @(z) [z(1); z(2)];
jacobian_fn = @jac_domain_throw;
opt = struct( ...
    'trial_exception_classifier', @(me) strcmp(me.identifier, ...
        'ibr:gfl_rms10_model:lowVoltagePowerInversion'));

thrown = false;
got_id = '';
try
    stability.composite_newton(z0, residual_fn, jacobian_fn, 1e-12, 5, false, opt);
catch me
    thrown = true;
    got_id = me.identifier;
end
testCase.verifyTrue(thrown);
testCase.verifyEqual(got_id, 'ibr:gfl_rms10_model:lowVoltagePowerInversion');
end

function J = jac_domain_throw(~)
% Always throws the domain ID during Jacobian/FD evaluation.
error('ibr:gfl_rms10_model:lowVoltagePowerInversion', 'FD perturbation invalid.');
end

function test_reuse_off_returns_legacy_counts(testCase)
% With jacobian_reuse absent (or false) every Newton direction must come from
% a FRESH Jacobian exactly as the legacy loop: no reuse, no rebuild counter.
% The solve starts at the root (residual 0), so the convergence test fires
% before any Jacobian is needed: evaluations = 0, iterations = 1.
A = [2, 0; 0, 0.5];
z0 = [1; -2];
b = A * z0;
residual_fn = @(z) A * z - b;
jacobian_fn = @(~) A;

[~, n_legacy, c_legacy, r_legacy, rc_legacy, J_legacy, info_legacy] = ...
    stability.composite_newton(z0, residual_fn, jacobian_fn, ...
    1e-12, 50, false, struct());
opt = struct('jacobian_reuse', false);
[~, n_off, c_off, r_off, rc_off, J_off, info_off] = ...
    stability.composite_newton(z0, residual_fn, jacobian_fn, ...
    1e-12, 50, false, opt);

testCase.verifyEqual(n_off, n_legacy, 'AbsTol', 0);
testCase.verifyEqual(c_off, c_legacy);
testCase.verifyEqual(r_off, r_legacy, 'AbsTol', 0);
testCase.verifyEqual(rc_off, rc_legacy, 'AbsTol', 0);
testCase.verifyEqual(J_off, J_legacy, 'AbsTol', 0);
% The initial point IS the root: no Jacobian was consumed by a direction.
testCase.verifyEqual(info_legacy.jacobian_evaluations, 0, 'AbsTol', 0);
testCase.verifyEqual(info_off.jacobian_evaluations, 0, 'AbsTol', 0);
testCase.verifyEqual(info_off.jacobian_reused, 0, 'AbsTol', 0);
testCase.verifyEqual(info_off.jacobian_rebuilds, 0, 'AbsTol', 0);
testCase.verifyFalse(info_off.line_search_exhausted);
end

function test_reuse_off_off_root_iteration_counts(testCase)
% Off the root, every non-converged iteration of the legacy loop must come
% from a fresh jacobian_fn build: evaluations == iterations.
A = [2, 0; 0, 0.5];
z0 = [1; 1];          % residual 2, needs Newton steps
b = A * [3; 7];       % root [3;7]
residual_fn = @(z) A * z - b;
jacobian_fn = @(~) A;

[~, n, converged, ~, ~, ~, info] = stability.composite_newton( ...
    z0, residual_fn, jacobian_fn, 1e-12, 50, false, struct());
testCase.verifyTrue(converged);
testCase.verifyGreaterThan(n, 1);
% Every non-terminal iteration consumes one fresh direction build. The final
% iteration is the convergence test (residual already below tol), whose
% wrap-up J_final build is not charged to the counters — the same convention
% as the root-at-z0 case above (evaluations = 0 = n - 1).
testCase.verifyEqual(info.jacobian_evaluations, n - 1, 'AbsTol', 0, ...
    'Legacy loop builds a fresh Jacobian at every non-terminal iteration.');
testCase.verifyEqual(info.jacobian_reused, 0, 'AbsTol', 0);
testCase.verifyEqual(info.jacobian_rebuilds, 0, 'AbsTol', 0);
end

function test_reuse_equiv_and_reduces_jacobian_builds(testCase)
% Chord-method transparency case: a FIXED Jacobian approximation A0 (the
% same handle value every iteration) lets the reuse policy hold ONE fresh
% build across every accepted full step with a good reduction. The root, the
% iteration count, the final residual and J_final/rcond must be identical to
% the legacy loop, with strictly fewer jacobian_fn builds.
z_star = [3; 7];
z0 = [1; -2];
residual_fn = @(z) z - z_star;                 % A = I
jacobian_fn = @(~) diag([1, 1.5]);             % fixed chord matrix A0

[~, n_legacy, converged_legacy, r_legacy, rc_legacy, J_legacy, info_legacy] = ...
    stability.composite_newton(z0, residual_fn, jacobian_fn, ...
    1e-8, 50, false, struct());
opt = struct('jacobian_reuse', true, 'jacobian_reuse_ratio', 0.5);
[z_sol, n, converged, r, rc, J, info] = stability.composite_newton( ...
    z0, residual_fn, jacobian_fn, 1e-8, 50, false, opt);

testCase.verifyEqual(n, n_legacy, 'AbsTol', 0, ...
    'Chord reuse must not change the iteration count.');
testCase.verifyTrue(converged);
testCase.verifyTrue(converged_legacy);
testCase.verifyEqual(z_sol, z_star, 'AbsTol', 1e-6);
% Both finals satisfy the SAME tolerance contract; the exact landing points
% may differ because the chord direction differs from the Newton direction.
testCase.verifyLessThan(r, 1e-8);
testCase.verifyLessThan(r_legacy, 1e-8);
testCase.verifyEqual(J, J_legacy, 'AbsTol', 0);
testCase.verifyEqual(info_legacy.jacobian_evaluations, n_legacy - 1, 'AbsTol', 0, ...
    'Legacy loop rebuilds at every non-terminal iteration.');
testCase.verifyEqual(info_legacy.jacobian_reused, 0, 'AbsTol', 0);
testCase.verifyEqual(info.jacobian_evaluations, 1, 'AbsTol', 0, ...
    'One fresh build must serve every iteration here.');
testCase.verifyEqual(info.jacobian_rebuilds, 0, 'AbsTol', 0);
testCase.verifyEqual(info.jacobian_evaluations + info.jacobian_reused, ...
    n_legacy - 1, 'AbsTol', 0, ...
    'A direction is consumed at every non-terminal iteration.');
testCase.verifyGreaterThan(info.jacobian_reused, 0);
end

function test_reuse_refreshes_after_poor_reduction(testCase)
% A chord step that reduces the residual by less than reuse_ratio must force
% a fresh Jacobian at the next iterate: the rebuild counter must advance, and
% the fresh build must supply the BETTER chord so the solve converges. The
% residual is linear r(z)=H z; the FIRST jacobian_fn call (at z0) returns a
% poor approximation with swapped eigen-scales, every later call returns the
% exact H. The poor chord step's reduction falls below ratio, the policy
% rebuilds, and the exact build carries the solve to the root.
H = [1, 0; 0, 4];
z0 = [4; 1];
calls = 0;   % shared workspace between the nested functions below
    function J = jac_refresh(~) %#ok<NESTED>
        calls = calls + 1;
        if calls == 1
            J = [4, 0; 0, 1];          % poor first approximation
        else
            J = H;                     % exact afterwards
        end
    end
    function r = rfn(z) %#ok<NESTED>
        r = H * z;
    end
opt = struct('jacobian_reuse', true, 'jacobian_reuse_ratio', 0.5);

[z_sol, ~, converged, residual_norm, rc, ~, info] = stability.composite_newton( ...
    z0, @rfn, @jac_refresh, 1e-10, 50, false, opt);

testCase.verifyTrue(converged);
testCase.verifyLessThan(residual_norm, 1e-10);
testCase.verifyTrue(isfinite(rc));
testCase.verifyLessThan(norm(z_sol, inf), 1e-8);
% The forced fresh build happened and supplied the exact Jacobian: exactly
% two builds (the poor one, then the forced refresh) and no reuse.
testCase.verifyEqual(info.jacobian_evaluations, 2, 'AbsTol', 0);
testCase.verifyEqual(info.jacobian_rebuilds, 1, 'AbsTol', 0);
testCase.verifyEqual(info.jacobian_reused, 0, 'AbsTol', 0);
end

function test_reuse_counts_are_bounded_and_consistent(testCase)
% Off the root: every non-converged iteration consumes a Newton direction
% from some Jacobian, so evaluations + reused must equal the iteration count.
% The Jacobian is EXACT and fixed, so the reuse policy holds one build and
% admits no rebuild, no reject, no backtracking here. The solve starts
% OFF the root (b chosen away from z0).
z0 = [1; 1];
A = [3, 1; 1, 2];
b = A * [3; 7];       % root is [3;7], z0 is off it
residual_fn = @(z) A * z - b;
jacobian_fn = @(~) A;
opt = struct('jacobian_reuse', true);

[~, n, converged, ~, ~, ~, info] = stability.composite_newton( ...
    z0, residual_fn, jacobian_fn, 1e-12, 50, false, opt);
testCase.verifyTrue(converged);
% Exact Jacobian on a linear residual: the first full Newton step lands on
% the root, so the SECOND iteration is the convergence test that terminates.
% n == 2 is therefore deterministic, not implementation-dependent.
testCase.verifyEqual(n, 2, 'AbsTol', 0, ...
    ['Exact linear residual: the first full step reaches the root, the ' ...
     'second iteration is the convergence test.']);
testCase.verifyEqual(info.jacobian_evaluations, 1, 'AbsTol', 0);
testCase.verifyEqual(info.jacobian_reused, 0, 'AbsTol', 0);
testCase.verifyEqual(info.jacobian_rebuilds, 0, 'AbsTol', 0);
% Accounting invariant: a direction is consumed at every NON-terminal
% iteration only (the final convergence-test build is uncharged).
testCase.verifyEqual(info.jacobian_evaluations + info.jacobian_reused, ...
    n - 1, 'AbsTol', 0, ...
    'A direction is consumed at every non-terminal iteration.');
end

function test_reuse_invalid_option_values_rejected(testCase)
% jacobian_reuse must be a logical scalar; jacobian_reuse_ratio a finite
% scalar in (0,1). Anything else must error, not fall back silently.
z0 = [1; -2];
residual_fn = @(z) [2, 0; 0, 0.5] * z;
jacobian_fn = @(~) [2, 0; 0, 0.5];

for bad = {1, 'true', [true false]}
    opt = struct('jacobian_reuse', bad{1});
    testCase.verifyError(@() stability.composite_newton(z0, residual_fn, ...
        jacobian_fn, 1e-12, 5, false, opt), ...
        'stability:composite_newton:badJacobianReuse');
end
for bad = {0, -0.5, 1.0, 1.5, NaN, Inf, [0.25 0.75]}
    opt = struct('jacobian_reuse', true, 'jacobian_reuse_ratio', bad{1});
    testCase.verifyError(@() stability.composite_newton(z0, residual_fn, ...
        jacobian_fn, 1e-12, 5, false, opt), ...
        'stability:composite_newton:badJacobianReuseRatio');
end
end

function test_reuse_rejected_chord_falls_back_to_fresh(testCase)
% A chord direction whose FULL step is rejected by the true-residual line
% search must still converge via the unchanged backtracking, and the next
% iterate must rebuild (a backtracked step invalidates the held Jacobian).
z0 = [0; 0];
% Residual whose Newton direction from the (exact) Jacobian overshoots:
% the chord step is rejected by the strict-decrease gate on the FIRST
% attempts and only a damped trial is accepted.
residual_fn = @(z) overshoot_residual(z);
jacobian_fn = @(~) [1, 0; 0, 1];
opt = struct('jacobian_reuse', true);

[z_sol, ~, converged, residual_norm, ~, ~, info] = stability.composite_newton( ...
    z0, residual_fn, jacobian_fn, 1e-10, 50, false, opt);
testCase.verifyTrue(converged);
testCase.verifyLessThan(residual_norm, 1e-10);
% At least one rebuild: backtracking forces a fresh Jacobian.
testCase.verifyGreaterThan(info.jacobian_rebuilds, 0);
end

function r = overshoot_residual(z)
%OVERSHOOT_RESIDUAL  Nonlinear residual whose Newton chord step from z0 = 0
%   with J0 = I overshoots the region of decreasing residual: the full step
%   z = dz increases ||r|| so the line search backtracks, and the next
%   iterate must rebuild because a backtracked step invalidates the held
%   Jacobian. Component 1 is smooth with curvature away from 0; component 2
%   couples z1 so the chord direction is only approximate.
r = [sinh(2 * z(1)) - 0.25 * z(2)^2 - 0.1; z(2) + 0.25 * z(1)];
end

function vd = empty_violating_devices()
%EMPTY_VIOLATING_DEVICES  Reusable empty struct array template so the
%   trial_exception_diagnostic closure returns a stable violating_devices
%   shape without re-parsing a struct literal on every rejected trial.
vd = repmat(struct('device_id','','bus_id',0, ...
    'bus_position',0,'trial_voltage',NaN,'runtime_min_voltage',NaN), 0);
end
