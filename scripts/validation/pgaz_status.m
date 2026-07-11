function s = pgaz_status(ran, completed, corrector_iter, has_residual)
%PGAZ_STATUS  Classify PGAz execution status with correct completed-vs-
%   converged semantics. PGAz uses a FIXED corrector iteration count with NO
%   convergence residual check (pgaz_ts.m). Therefore a completed PGAz run is
%   COMPLETED, not "converged" in the residual sense. If the API exposes no
%   residual, residual_available=false and converged=false (never inferred
%   from mere output).
s = struct();
s.ran = ran;
s.completed = completed;
s.corrector_iter = corrector_iter;
s.residual_available = has_residual;
% converged is TRUE only if a residual was checked and met a tolerance.
% PGAz never checks a residual -> converged is always false (honest).
s.converged = false;
if has_residual
    % If a residual were available, convergence would require it below tol;
    % PGAz does not provide one, so this branch is unreachable for PGAz.
    s.converged = false;
end
s.status_text = 'COMPLETED (fixed corrector, no residual convergence check)';
if ~ran, s.status_text = 'NOT RUN'; end
end
