function tests = test_pgaz_status_semantics()
%TEST_PGAZ_STATUS_SEMANTICS  Verify PGAz is reported as COMPLETED with a fixed
%   corrector and NO residual convergence check — never "converged". Guards the
%   bug where a fixed-3-iteration run was called "converged".

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_completed_not_converged(testCase)
% PGAz ran to completion with fixed corrector, no residual -> COMPLETED, not converged.
s = pgaz_status(true, true, 3, false);
testCase.verifyTrue(s.completed, 'PGAz completed');
testCase.verifyFalse(s.converged, 'PGAz must NOT be called converged (no residual check)');
testCase.verifyFalse(s.residual_available, 'residual not available');
testCase.verifyEqual(s.corrector_iter, 3);
testCase.verifyTrue(contains(s.status_text, 'COMPLETED'), 'status text says COMPLETED');
testCase.verifyFalse(contains(s.status_text, 'converged'), 'status text must not say converged');
end

function test_not_run_status(testCase)
s = pgaz_status(false, false, 3, false);
testCase.verifyFalse(s.ran, 'not run');
testCase.verifyEqual(s.status_text, 'NOT RUN');
end

function test_output_does_not_imply_convergence(testCase)
% Having output (completed) must NOT imply convergence when no residual.
s = pgaz_status(true, true, 8, false);
testCase.verifyTrue(s.completed);
testCase.verifyFalse(s.converged, 'output alone must not imply convergence');
end

function test_higher_corrector_still_not_converged(testCase)
% Even ci=12 (deep plateau) is COMPLETED, not converged (no residual check).
s = pgaz_status(true, true, 12, false);
testCase.verifyTrue(s.completed);
testCase.verifyFalse(s.converged, 'ci=12 still not converged (no residual check)');
end
