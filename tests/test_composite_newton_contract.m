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

function vd = empty_violating_devices()
%EMPTY_VIOLATING_DEVICES  Reusable empty struct array template so the
%   trial_exception_diagnostic closure returns a stable violating_devices
%   shape without re-parsing a struct literal on every rejected trial.
vd = repmat(struct('device_id','','bus_id',0, ...
    'bus_position',0,'trial_voltage',NaN,'runtime_min_voltage',NaN), 0);
end
