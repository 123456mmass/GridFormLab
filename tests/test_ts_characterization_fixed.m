function tests = test_ts_characterization_fixed()
%TEST_TS_CHARACTERIZATION_FIXED  Fixed-step trajectory characterization.
%   Captures the CURRENT fixed-step TS trajectory on canonical cases so that
%   the Phase 2 mechanical refactor (routing the fixed-step path through the
%   shared strategy / ts_step_kernel) can be proven equivalent to this baseline.
%
%   This is NOT a numerical-acceptance gate against an external reference. It is
%   a bit-identity characterization for the mechanical refactor only:
%     Phase 2a: old inline + new strategy coexist -> direct array comparison.
%     Phase 2b: switch fixed runtime to new strategy -> rerun equivalence.
%     Phase 2c: remove old inline -> this test still passes against the new path.
%
%   Per the approved plan (Phase 0/2, dual-path comparison):
%     - Bit-identical is the target ONLY for the mechanical refactor.
%     - If results differ: trace root cause (FP ordering vs baseline bug);
%       never raise tolerance after viewing results; a behavior bug fix must be
%       a separate commit/test with a deterministic failing reproduction.
%
%   Phase 0 status: this test pins the CURRENT (pre-refactor) trajectory. The
%   comparison half (old-vs-new) is activated in Phase 2 when the new strategy
%   path exists. Until then, the recorded values below are the characterization
%   reference produced FRESH on commit 0534132.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function r = run_case14_classical(opt_overrides)
% Canonical Case14 classical fixed-step run used as the characterization basis.
c = cases.case_matpower6_case14();
opt = struct('t_end',4,'dt',0.01,'fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'method','trapezoidal', ...
    'corrector_mode','adaptive','max_corrector_iter',10, ...
    'pm_mode','pgaz','verbose',false);
if nargin >= 1 && ~isempty(opt_overrides)
    fn = fieldnames(opt_overrides);
    for k = 1:numel(fn), opt.(fn{k}) = opt_overrides.(fn{k}); end
end
r = stability.ts_simulate(c, opt);
end

function test_case14_adaptive_trajectory_finite(testCase)
% Characterization: the canonical Case14 adaptive-corrector fixed-step run
% completes with a finite, bounded trajectory and zero non-converged steps.
r = run_case14_classical();
testCase.verifyEqual(r.pf.converged, true);
testCase.verifyEqual(r.nonconverged_step_count, 0);
testCase.verifyTrue(all(isfinite(r.delta(:))));
testCase.verifyTrue(all(isfinite(r.omega(:))));
testCase.verifyTrue(all(isfinite(r.Pe_pu(:))));
testCase.verifyTrue(all(isfinite(r.Vbus(:))));
% Event times exactly on the grid.
testCase.verifyEqual(min(abs(r.t - r.t_fault)), 0, 'AbsTol', 1e-14);
testCase.verifyEqual(min(abs(r.t - r.t_clear)), 0, 'AbsTol', 1e-14);
end

function test_case14_fixed_ci10_trajectory_finite(testCase)
% Characterization of the fixed-iteration (ci=10) path used for the
% old-vs-new engine comparison in test_ts_simulate_general.
r = run_case14_classical(struct('corrector_mode','fixed','corrector_iter',10));
testCase.verifyEqual(r.pf.converged, true);
testCase.verifyTrue(all(isfinite(r.delta(:))));
testCase.verifyTrue(all(isfinite(r.omega(:))));
testCase.verifyEqual(min(abs(r.t - r.t_fault)), 0, 'AbsTol', 1e-14);
testCase.verifyEqual(min(abs(r.t - r.t_clear)), 0, 'AbsTol', 1e-14);
end

function test_case14_no_fault_drift(testCase)
% Characterization: no-fault equilibrium drift is at machine precision.
r = run_case14_classical(struct('t_fault',99,'t_clear',99.1,'fault_enabled',false));
testCase.verifyLessThan(max(abs(r.delta(end,:) - r.delta(1,:)),[],'all'), 1e-10);
testCase.verifyLessThan(max(abs(r.omega(:) - 1),[],'all'), 1e-10);
end
