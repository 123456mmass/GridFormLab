function [plateau_ci, info] = detect_pgaz_plateau(ci_pairs, dCOI, domega, dPe, dVm, tol)
%DETECT_PGAZ_PLATEAU  Pure plateau-detection logic for the PGAz corrector
%   study. plateau_ci = the first ci_k such that the successive difference
%   ci_k vs ci_{k+1} is below tol on ALL four metrics. Returns NaN if no
%   plateau is reached (PGAz numerical solution not converged -> gate fails).
%   The criterion is declared a priori (tol), not tuned to the result.
if nargin < 5 || isempty(tol)
    tol = struct('dCOI',0.05,'domega',1e-4,'dPe',0.1,'dVm',1e-3);
end
plateau_ci = NaN;
reached = false(numel(dCOI),1);
for p = 1:numel(dCOI)
    reached(p) = dCOI(p)<=tol.dCOI && domega(p)<=tol.domega && ...
                 dPe(p)<=tol.dPe && dVm(p)<=tol.dVm;
    if reached(p) && isnan(plateau_ci)
        plateau_ci = ci_pairs(p,1);
    end
end
info = struct('reached', reached, 'plateau_ci', plateau_ci);
end
