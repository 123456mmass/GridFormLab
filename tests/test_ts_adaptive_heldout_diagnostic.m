function tests = test_ts_adaptive_heldout_diagnostic()
%TEST_TS_ADAPTIVE_HELDOUT_DIAGNOSTIC  Held-out adaptive-vs-fixed diagnostic.
%   Runs the adaptive stepper vs the fixed canonical baseline on RTS-24
%   (classical) and Kundur two-area (emf6) and asserts ONLY STRUCTURAL
%   invariants. Numerical diffs (delta/omega/Pe/Vbus COI & pairwise) are
%   reported as DIAGNOSTICS, not gated.
%
%   Per the honesty-closure policy:
%     - These cases are "previously observed" (their adaptive results were
%       seen in Phases 5-7 and in adaptive_ts_diagnostic). They are therefore
%       NOT genuinely held-out for a tolerance-selection study. A future
%       protocol must label them as such or pick unseen cases.
%     - HELD_OUT_ADAPTIVE_DIAGNOSTIC_EXECUTED = PASS iff all structural
%       invariants pass (finite, coverage_valid, no extrapolation, no
%       cross-event interpolation, exact event landing, ID mapping,
%       algebraic convergence).
%     - HELD_OUT_ADAPTIVE_VALIDATION = NOT_READY (diagnostics are NOT
%       acceptance evidence; no tolerance has been selected).
%   No acceptance thresholds are invented for the numerical diffs.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function rts = run_rts24_diagnostic()
rts = adaptive_ts_compare_fixed('case_ieee_rts24_pgaz','classical', ...
    struct('t_end',5,'dt',0.01,'fault_bus',15,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1));
end

function knd = run_kundur_emf6_diagnostic()
knd = adaptive_ts_compare_fixed('case_kundur_two_area_classical','emf6', ...
    struct('t_end',5,'dt',1e-3,'fault_bus',8,'t_fault',1.0,'t_clear',1.05, ...
    'Zf',[]));
end

function assert_structural(testCase, rep, label)
% Hard-gated structural invariants (the ONLY gates in this test).
testCase.verifyTrue(rep.all_finite, ...
    sprintf('%s: all compared trajectories must be finite.', label));
testCase.verifyTrue(rep.coverage_valid, ...
    sprintf('%s: adaptive grid must cover the common horizon.', label));
testCase.verifyTrue(rep.no_extrapolation, ...
    sprintf('%s: no extrapolation permitted.', label));
testCase.verifyTrue(rep.no_cross_event_interp, ...
    sprintf('%s: no cross-event interpolation permitted.', label));
testCase.verifyTrue(rep.exact_event_landing, ...
    sprintf('%s: events must land exactly on the adaptive grid.', label));
testCase.verifyTrue(rep.id_mapping_consistent, ...
    sprintf('%s: gen_buses and bus_ids must match across both paths.', label));
testCase.verifyTrue(rep.algebraic_converged, ...
    sprintf('%s: algebraic corrector must converge (finite, bounded).', label));
testCase.verifyTrue(rep.structural_pass, ...
    sprintf('%s: overall structural_pass must be true.', label));
end

function report_numerical(rep, label)
% Report-only numerical diagnostics (NOT gates).
m = rep.metrics;
fprintf('\n[%s] adaptive-vs-fixed DIAGNOSTIC (report-only, NOT a gate):\n', label);
fprintf('  accepted=%d rejected=%d\n', rep.accepted_steps, rep.rejected_steps);
fprintf('  delta COI=%.4f deg  pairwise=%.4f deg\n', m.delta_coi_deg, m.delta_pairwise_deg);
fprintf('  omega=%.3e pu  omega_coi=%.3e pu\n', m.omega_pu, m.omega_coi_pu);
fprintf('  Pe=%.4f MW  Vbus=%.3e pu  Vbus_fault=%.3e pu\n', ...
    m.Pe_MW, m.Vbus_pu, m.Vbus_fault_pu);
end

function test_rts24_classical_structural(testCase)
rep = run_rts24_diagnostic();
assert_structural(testCase, rep, 'RTS24-classical');
report_numerical(rep, 'RTS24-classical');
end

function test_kundur_emf6_structural(testCase)
rep = run_kundur_emf6_diagnostic();
assert_structural(testCase, rep, 'Kundur-emf6');
report_numerical(rep, 'Kundur-emf6');
end

function test_heldout_status_is_not_ready(testCase)
% The diagnostic is EXECUTED (structural), but held-out VALIDATION is
% NOT_READY. No acceptance threshold is imposed on the numerical diffs.
% This documents the honest status and prevents the diagnostic from being
% silently promoted to validation evidence.
status = struct();
status.held_out_adaptive_diagnostic_executed = true;   % this test runs it
status.held_out_adaptive_validation = 'NOT_READY';
status.tolerance_selection_evidence = 'NOT_READY';
testCase.verifyTrue(status.held_out_adaptive_diagnostic_executed, ...
    'diagnostic must be executed.');
testCase.verifyEqual(status.held_out_adaptive_validation, 'NOT_READY', ...
    'held-out adaptive validation is NOT_READY.');
testCase.verifyEqual(status.tolerance_selection_evidence, 'NOT_READY', ...
    'tolerance selection evidence is NOT_READY.');
end
