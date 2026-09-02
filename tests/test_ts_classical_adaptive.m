function tests = test_ts_classical_adaptive()
%TEST_TS_CLASSICAL_ADAPTIVE  Classical adaptive-step (variable dt) TS gate tests.
%   Phase 6: the classical model wired through ts_adaptive_driver must complete
%   a fault scenario with finite bounded trajectory, exact event landing, and the
%   frozen adaptive result schema. Fixed-vs-adaptive common-grid equivalence is
%   within pre-declared tolerances.
%
% --- 1.0 deg threshold provenance (honest) -------------------------------
% The 1.0 deg fixed-vs-adaptive threshold below is an ASSUMED_DIAGNOSTIC
% regression guard, NOT an a-priori-justified production tolerance.
%   - First appeared: this file, introduced in Phase 6 commit c4fd2e8.
%   - Commit c4fd2e8 was authored AFTER adaptive results were already
%     observed (Phases 3-5); the threshold was chosen while viewing results.
%   - No recorded executable selection study exists for it.
%   - Therefore it CANNOT honestly be called "selected" or "a-priori
%     justified". Status:
%       FIXED_VS_ADAPTIVE_1DEG_REGRESSION_GUARD = PASS/FAIL (non-regression
%         guard only, kept unchanged per honesty-closure policy: do NOT
%         relax/increase/remove/tune).
%       FIXED_VS_ADAPTIVE_PRODUCTION_TOLERANCE_JUSTIFIED = NOT_READY.
%   - A future separately-approved prospective tolerance study
%     (docs/project/plans/adaptive_tolerance_study_proposal.md) may produce
%     justified thresholds; until then this guard is diagnostic-only.
%   - The comparison is expanded to REPORT delta/omega/Pe/Vbus with COI,
%     bus-ID, and gen-ID mapping (via adaptive_ts_compare_fixed), but NO new
%     acceptance thresholds are invented for Pe/Vbus.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function r = run_classical_adaptive(t_end, overrides)
c = cases.case_matpower6_case14();
opt = struct('stepper','adaptive','t_end',t_end,'dt',0.01, ...
    'fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
    'pm_mode','pgaz','corrector_mode','adaptive','verbose',false);
if nargin >= 2
    fn = fieldnames(overrides);
    for k = 1:numel(fn), opt.(fn{k}) = overrides.(fn{k}); end
end
r = stability.ts_simulate(c, opt);
end

function test_adaptive_completes_and_schema(testCase)
r = run_classical_adaptive(5);
testCase.verifyEqual(r.stepper, 'adaptive');
testCase.verifyEqual(r.model, 'classical');
testCase.verifyTrue(all(isfinite(r.delta(:))));
testCase.verifyTrue(all(isfinite(r.omega(:))));
testCase.verifyTrue(all(isfinite(r.Vbus(:))));
testCase.verifyGreaterThan(r.accepted_steps, 0);
testCase.verifyEqual(numel(r.dt_history), numel(r.t)-1);
testCase.verifyEqual(numel(r.lte_history), numel(r.t)-1);
testCase.verifyTrue(all(diff(r.t) > 0), 'strictly increasing r.t');
testCase.verifyEqual(numel(r.t), r.accepted_steps + 1);
testCase.verifyEqual(r.dt, 0.01, 'r.dt is scalar nominal');
end

function test_adaptive_exact_event_landing(testCase)
r = run_classical_adaptive(5);
testCase.verifyEqual(min(abs(r.t - 1.0)), 0, 'AbsTol', 1e-14, 't_fault on grid');
testCase.verifyEqual(min(abs(r.t - 1.1)), 0, 'AbsTol', 1e-14, 't_clear on grid');
testCase.verifyGreaterThan(numel(r.event_diagnostics), 0);
end

function test_adaptive_no_fault_drift(testCase)
r = run_classical_adaptive(3, struct('t_fault',99,'t_clear',99.1,'fault_enabled',false));
testCase.verifyLessThan(max(abs(r.delta(end,:) - r.delta(1,:))), 1e-6, ...
    'No-fault delta drift < 1e-6 rad');
testCase.verifyLessThan(max(abs(r.omega(:) - 1)), 1e-6, 'No-fault omega drift');
end

function test_adaptive_fault_depresses_voltage(testCase)
% Use a fault on a generator bus (bus 1) so the Vbus drop is directly
% observable on a gen-bus column, avoiding the fault_bus-not-a-gen-bus filter.
r = run_classical_adaptive(5, struct('fault_bus',1));
tf = find(abs(r.t - 1.0) < 1e-14, 1);
% Classical result does not carry bus_ids; the fault bus is column 1 by
% construction (gbus(1)). Verify gen-bus-1 voltage drops at the fault.
testCase.verifyLessThan(r.Vbus(tf,1), r.Vbus(tf-1,1)*0.95, ...
    'Fault-bus voltage must drop at fault application.');
end

function test_fixed_vs_adaptive_common_grid(testCase)
% Phase 6: fixed-vs-adaptive common-grid equivalence for Case14 classical.
% Uses the shared helper adaptive_ts_compare_fixed, which ALONE owns ID
% mapping, event-segmented interp_no_extrapolate, the COI frame, and the
% structural checks. The comparison REPORTS delta/omega/Pe/Vbus (COI, gen-ID
% mapped, bus-ID mapped); the 1.0 deg / 1e-3 pu bounds below are the ONLY
% acceptance assertions, kept as the historical ASSUMED_DIAGNOSTIC regression
% guard (see file header provenance). NO new acceptance thresholds are imposed
% on Pe/Vbus; those are reported as diagnostics only.
rep = adaptive_ts_compare_fixed('case_matpower6_case14','classical', ...
    struct('t_end',5,'dt',0.01,'fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'pm_mode','pgaz','corrector_mode','adaptive', ...
    'corrector_iter',10,'max_corrector_iter',10));
m = rep.metrics;
% Structural invariants must hold (hard gate, same as the helper asserts).
testCase.verifyTrue(rep.structural_pass, 'structural invariants must hold.');
% Historical ASSUMED_DIAGNOSTIC regression guard (NOT a justified tolerance).
% Rationale (declared when introduced, NOT borrowed from PSAT): the fixed path
% uses exact ci=10 Picard iterations while the adaptive path uses a
% residual-checked corrector that may converge in fewer iterations; the
% resulting trajectory difference is bounded by the corrector tolerance, not
% by the LTE budget. 1.0 deg / 1e-3 pu.
testCase.verifyLessThan(m.delta_coi_deg, 1.0, ...
    'Fixed-vs-adaptive COI angle < 1.0 deg (ASSUMED_DIAGNOSTIC guard).');
testCase.verifyLessThan(m.omega_pu, 1e-3, ...
    'Fixed-vs-adaptive speed < 1e-3 pu (ASSUMED_DIAGNOSTIC guard).');
% Pe and Vbus are REPORTED as diagnostics only (no acceptance threshold).
fprintf('[Case14 classical] Pe diff=%.4f MW  Vbus diff=%.3e pu  Vbus_fault diff=%.3e pu (diagnostics, NOT gates)\n', ...
    m.Pe_MW, m.Vbus_pu, m.Vbus_fault_pu);
end
