function tests = test_validation_gate_logic()
%TEST_VALIDATION_GATE_LOGIC  Unit tests for the three-way validation gate
%   semantics (evaluate_validation_gates). Verifies that missing PGAz,
%   execution errors, missing metrics, non-converged steps, and contract
%   failures all force the aggregate gate to FAIL — never a silent optional
%   pass. A fully-present, within-tolerance run passes.

tests = functiontests(localfunctions);
end

function functionSetup(testCase) %#ok<INUSD>
pf_init_paths;
end

function tol = default_tol()
tol.pf = struct('dV',1e-6,'dAng',1e-4);
tol.ts_conv = struct('dCOI',0.05,'domega',1e-4,'dPe',0.1,'dVm',1e-3);
tol.ts_pgaz = struct('dCOI',1.0,'domega',5e-4,'dPe',5.0,'dVm',5e-3);
end

function m = good_metrics()
% All within the converged tolerance (PSAT-Ours) and PGAz tolerance.
pf0 = struct('dV',1e-15,'dAng',1e-13);
ts_conv = struct('dCOI',0.0096,'domega',3.8e-6,'dPe',0.042,'dVm',3.2e-5);
ts_pgaz = struct('dCOI',0.61,'domega',2.9e-4,'dPe',2.44,'dVm',2.3e-3);
m.pf = struct('ps_ours',pf0,'pg_ours',pf0,'ps_pg',pf0);
m.ts = struct('ps_ours',ts_conv,'pg_ours',ts_pgaz,'ps_pg',ts_pgaz);
end

function ran = both_ran(), ran = struct('psat',true,'pgaz',true); end
function contract = good_contract(), contract = struct('ybus_pgaz',true,'ybus_psat',true); end
function mapping = good_mapping(), mapping = struct('psat',true,'pgaz',true); end

function test_all_present_within_tol_passes(testCase)
g = evaluate_validation_gates(both_ran(), good_contract(), good_mapping(), ...
    0, true, good_metrics(), default_tol());
testCase.verifyTrue(g.all_gates_pass, 'Fully-present within-tol run must pass.');
testCase.verifyTrue(g.pgaz_ran, 'PGAz ran flag must be true.');
testCase.verifyTrue(g.pg_metrics_ok, 'PGAz metrics gate must pass.');
end

function test_pgaz_missing_aggregate_fails(testCase)
% PGAz not installed / not run => aggregate FAIL (never optional pass).
g = evaluate_validation_gates(struct('psat',true,'pgaz',false), ...
    good_contract(), good_mapping(), 0, true, good_metrics(), default_tol());
testCase.verifyFalse(g.all_gates_pass, 'Missing PGAz must fail the aggregate.');
testCase.verifyFalse(g.pgaz_ran, 'pgaz_ran must be false.');
testCase.verifyFalse(g.pg_metrics_ok, 'PGAz metrics gate must fail when not run.');
end

function test_pgaz_execution_error_aggregate_fails(testCase)
% PGAz execution error => ran.pgaz=false => same as missing.
g = evaluate_validation_gates(struct('psat',true,'pgaz',false), ...
    good_contract(), good_mapping(), 0, true, good_metrics(), default_tol());
testCase.verifyFalse(g.all_gates_pass, 'PGAz execution error must fail the aggregate.');
end

function test_missing_metric_aggregate_fails(testCase)
m = good_metrics(); m.ts.pg_ours.dCOI = NaN;  % metric missing
g = evaluate_validation_gates(both_ran(), good_contract(), good_mapping(), ...
    0, true, m, default_tol());
testCase.verifyFalse(g.all_gates_pass, 'Missing metric must fail the aggregate.');
testCase.verifyFalse(g.pg_metrics_ok, 'PGAz metrics gate must fail on NaN metric.');
end

function test_nonconverged_step_fails(testCase)
g = evaluate_validation_gates(both_ran(), good_contract(), good_mapping(), ...
    3, true, good_metrics(), default_tol());  % 3 non-converged steps
testCase.verifyFalse(g.all_gates_pass, 'Non-converged steps must fail the aggregate.');
testCase.verifyFalse(g.ours_nonconv_zero, 'ours_nonconv_zero must be false.');
end

function test_contract_ybus_fail_fails(testCase)
c = struct('ybus_pgaz',false,'ybus_psat',true);  % PGAz Ybus mismatch
g = evaluate_validation_gates(both_ran(), c, good_mapping(), ...
    0, true, good_metrics(), default_tol());
testCase.verifyFalse(g.all_gates_pass, 'Ybus contract failure must fail the aggregate.');
end

function test_gen_mapping_fail_fails(testCase)
mp = struct('psat',true,'pgaz',false);  % PGAz gen mapping wrong
g = evaluate_validation_gates(both_ran(), good_contract(), mp, ...
    0, true, good_metrics(), default_tol());
testCase.verifyFalse(g.all_gates_pass, 'Gen mapping failure must fail the aggregate.');
end

function test_metric_exceeds_tolerance_fails(testCase)
m = good_metrics(); m.ts.pg_ours.dCOI = 1.5;  % exceeds ts_pgaz (1.0)
g = evaluate_validation_gates(both_ran(), good_contract(), good_mapping(), ...
    0, true, m, default_tol());
testCase.verifyFalse(g.all_gates_pass, 'Metric exceeding tolerance must fail.');
testCase.verifyFalse(g.pg_metrics_ok, 'PGAz metrics gate must fail when over tolerance.');
end

function test_timegrid_mismatch_fails(testCase)
g = evaluate_validation_gates(both_ran(), good_contract(), good_mapping(), ...
    0, false, good_metrics(), default_tol());
testCase.verifyFalse(g.all_gates_pass, 'Time-grid mismatch must fail the aggregate.');
end
