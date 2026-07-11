function tests = test_pgaz_corrector_plateau_logic()
%TEST_PGAZ_CORRECTOR_PLATEAU_LOGIC  Verify the plateau detection: a plateau
%   is reached only when ALL metrics drop below the predeclared tolerance.
%   No plateau -> NaN (gate fails). Guards against declaring convergence
%   without a plateau on every metric.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function tol = tol()
tol = struct('dCOI',0.05,'domega',1e-4,'dPe',0.1,'dVm',1e-3);
end

function test_plateau_reached_when_all_metrics_below_tol(testCase)
% ci3-ci5 all below tol -> plateau at ci=3.
ci_pairs = [1 2; 2 3; 3 5; 5 8];
dCOI   = [2.8; 0.2; 0.006; 1e-5];
domega = [1e-3; 8e-5; 2e-6; 6e-9];
dPe    = [11; 0.7; 0.03; 7e-5];
dVm    = [8e-3; 6e-4; 1.6e-5; 3e-8];
[pc,info] = detect_pgaz_plateau(ci_pairs, dCOI, domega, dPe, dVm, tol());
testCase.verifyEqual(pc, 3, 'plateau at ci=3 (all metrics below tol)');
testCase.verifyTrue(info.reached(3), 'ci3-ci5 reached');
end

function test_no_plateau_when_one_metric_above_tol(testCase)
% dCOI at ci3-ci5 is 0.06 (>0.05) -> no plateau at ci=3; check ci=5.
ci_pairs = [1 2; 2 3; 3 5; 5 8];
dCOI   = [2.8; 0.2; 0.06; 1e-5];   % ci3-ci5 dCOI above tol
domega = [1e-3; 8e-5; 2e-6; 6e-9];
dPe    = [11; 0.7; 0.03; 7e-5];
dVm    = [8e-3; 6e-4; 1.6e-5; 3e-8];
[pc,info] = detect_pgaz_plateau(ci_pairs, dCOI, domega, dPe, dVm, tol());
testCase.verifyEqual(pc, 5, 'plateau skipped ci=3 (dCOI over tol), reached at ci=5');
testCase.verifyFalse(info.reached(3), 'ci3-ci5 not reached (dCOI)');
testCase.verifyTrue(info.reached(4), 'ci5-ci8 reached');
end

function test_no_plateau_returns_nan(testCase)
% If no successive pair is below tol on all metrics -> NaN (gate fails).
ci_pairs = [1 2; 2 3];
dCOI   = [2.8; 0.2];
domega = [1e-3; 8e-5];
dPe    = [11; 0.7];
dVm    = [8e-3; 6e-4];
[pc,~] = detect_pgaz_plateau(ci_pairs, dCOI, domega, dPe, dVm, tol());
testCase.verifyTrue(isnan(pc), 'no plateau -> NaN (gate must fail)');
end

function test_all_metrics_required(testCase)
% Plateau requires ALL four metrics below tol, not just angle.
ci_pairs = [3 5];
dCOI=0.001; domega=2e-3; dPe=0.01; dVm=1e-5;  % domega above tol
[pc,info] = detect_pgaz_plateau(ci_pairs, dCOI, domega, dPe, dVm, tol());
testCase.verifyFalse(info.reached(1), 'domega above tol -> not reached');
testCase.verifyTrue(isnan(pc), 'no plateau when any metric over tol');
end
