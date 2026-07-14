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
