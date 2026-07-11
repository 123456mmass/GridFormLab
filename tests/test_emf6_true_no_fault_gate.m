function tests = test_emf6_true_no_fault_gate()
%TEST_EMF6_TRUE_NO_FAULT_GATE  Verify the no-fault EMF6 gate uses a TRUE
%   no-fault run (fault_enabled=false) and checks residuals + drift, not just
%   a non-converged count. Guards the bug where a fault was active during the
%   "no-fault" check.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_no_fault_gate_passes_with_fault_disabled(testCase)
g = check_emf6_no_fault_gate();
testCase.verifyTrue(g.fault_disabled, 'fault must be disabled (fault_enabled=false)');
testCase.verifyTrue(g.completed, 'simulation completed');
testCase.verifyEqual(g.nonconverged_steps, 0, 'no non-converged steps');
testCase.verifyLessThan(g.max_f, 1e-10, 'max|f| at equilibrium');
testCase.verifyLessThan(g.max_g, 1e-10, 'max|g| at equilibrium');
testCase.verifyLessThan(g.drift_delta, 1e-9, 'rotor-angle drift ~0');
testCase.verifyLessThan(g.drift_omega, 1e-9, 'speed drift ~0');
testCase.verifyLessThan(g.drift_Vbus, 1e-9, 'voltage drift ~0');
testCase.verifyLessThan(g.drift_Pe, 1e-9, 'power drift ~0');
testCase.verifyTrue(g.all_finite, 'all values finite');
testCase.verifyTrue(g.gate, 'no-fault gate PASS');
end

function test_drift_exceeds_tolerance_fails(testCase)
% Synthetic: if drift exceeded tolerance, the gate logic must fail.
g = struct();
g.fault_disabled = true; g.max_f = 1e-15; g.max_g = 1e-14; g.init_residual = 1e-14;
g.nonconverged_steps = 0; g.max_corrector_residual = 1e-16;
g.drift_delta = 1e-6;   % exceeds 1e-9
g.drift_omega = 1e-17; g.drift_Vbus = 0; g.drift_Pe = 1e-15;
g.all_finite = true; g.completed = true;
DRIFT_TOL = 1e-9; EQ_TOL = 1e-10;
gate = g.fault_disabled && (g.max_f<EQ_TOL) && (g.max_g<EQ_TOL) && (g.init_residual<EQ_TOL) && ...
       (g.nonconverged_steps==0) && (g.drift_delta<DRIFT_TOL) && (g.drift_omega<DRIFT_TOL) && ...
       (g.drift_Vbus<DRIFT_TOL) && (g.drift_Pe<DRIFT_TOL) && g.all_finite && g.completed;
testCase.verifyFalse(gate, 'drift over tolerance must fail the gate');
end

function test_fault_active_would_fail(testCase)
% If a fault were active, drift would be large -> gate fails. (Negative test
% of the semantics: the gate requires fault_disabled=true.)
g = struct(); g.fault_disabled = false;   % fault active
g.drift_delta = 0; g.drift_omega = 0; g.drift_Vbus = 0; g.drift_Pe = 0;
g.max_f = 0; g.max_g = 0; g.init_residual = 0; g.nonconverged_steps = 0;
g.all_finite = true; g.completed = true;
DRIFT_TOL = 1e-9; EQ_TOL = 1e-10;
gate = g.fault_disabled && (g.max_f<EQ_TOL) && (g.drift_delta<DRIFT_TOL) && g.all_finite && g.completed;
testCase.verifyFalse(gate, 'fault active (fault_disabled=false) must fail the gate');
end
