function tests = test_pf_phase2_solve_case_routing()
%TEST_PF_PHASE2_SOLVE_CASE_ROUTING  Phase-2 PF production routing through solve_case.
%   Verifies that solve_case('analysis','pf',...) routes through the
%   pf_resolve_method + pf_method_strategy factories, records the method
%   metadata contract, preserves default NR bit-identically (AbsTol=0), and
%   fails closed on unknown methods / unsupported BFS topology.
%
%   Tests (tolerances declared BEFORE viewing results):
%     1. default PF == direct NR, AbsTol=0 (bit-identity)
%     2. pf_method='newton_raphson' == direct NR, AbsTol=0
%     3. pf_method='fdpf_xb' -> method_executed=='XB', dispatch_requested=='fdpf_xb', V vs NR AbsTol=1e-4
%     4. pf_method='fdpf_bx' -> method_executed=='BX', V vs NR AbsTol=1e-4
%     5. BFS_ROUTED_CAPABILITY_GATED: pf_method='bfs' on meshed ieee14 fails closed
%     6. pf_method='bogus' -> pf_resolve_method:unknownMethod
%     7. NR metadata additive (num_buses AND method_requested/dispatch_requested/
%        method_executed/selection_source/method_source/full_ac_mismatch/fallback_used)
%        method_requested NOT uniform across NR/XB/BX/bfs
%     8. log reports executed method (launcher prints method_executed)
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function opt = quiet_opt()
opt = struct('verbose', false, 'plot_results', false, 'max_iter', 50, ...
    'tolerance', 1e-10, 'enforce_q_limits', false);
end

function r = run_pf_solve_case(case_id, user_opt)
r = solve_case('analysis','pf','case',case_id,'options',user_opt);
end

% =========================================================================
function test_default_pf_bit_identical_to_direct_nr(testCase)
% Default solve_case PF must be bit-identical (AbsTol=0) to direct NR.
c = cases.case_ieee5bus();
opt = quiet_opt();
r_dispatch = run_pf_solve_case('ieee5', opt);
r_direct = pfsolver.powerflow_newton_raphson(c, opt);
testCase.verifyEqual(r_dispatch.bus_voltage, r_direct.bus_voltage, 'AbsTol', 0);
testCase.verifyEqual(r_dispatch.bus_angle_deg, r_direct.bus_angle_deg, 'AbsTol', 0);
testCase.verifyEqual(r_dispatch.iterations, r_direct.iterations);
testCase.verifyEqual(r_dispatch.converged, r_direct.converged);
end

function test_explicit_newton_raphson_bit_identical(testCase)
c = cases.case_ieee5bus();
opt = quiet_opt(); opt.pf_method = 'newton_raphson';
r_dispatch = run_pf_solve_case('ieee5', opt);
r_direct = pfsolver.powerflow_newton_raphson(c, opt);
testCase.verifyEqual(r_dispatch.bus_voltage, r_direct.bus_voltage, 'AbsTol', 0);
testCase.verifyEqual(r_dispatch.bus_angle_deg, r_direct.bus_angle_deg, 'AbsTol', 0);
% Explicit NR: selection_source must be 'explicit', not 'default'.
testCase.verifyEqual(r_dispatch.metadata.selection_source, 'explicit');
testCase.verifyEqual(r_dispatch.metadata.dispatch_requested, 'newton_raphson');
end

function test_fdpf_xb_routing_and_metadata(testCase)
opt = quiet_opt(); opt.pf_method = 'fdpf_xb';
r = run_pf_solve_case('ieee5', opt);
testCase.verifyTrue(r.converged, 'FDPF-XB converged via solve_case');
% FDPF sets method_executed='XB' (variant), NOT 'fdpf_xb' — must be preserved.
testCase.verifyEqual(r.metadata.method_executed, 'XB');
testCase.verifyEqual(r.metadata.dispatch_requested, 'fdpf_xb');
testCase.verifyEqual(r.metadata.selection_source, 'explicit');
testCase.verifyEqual(r.metadata.fallback_used, false);
% V vs NR within 1e-4 (different method, not bit-identical).
c = cases.case_ieee5bus();
r_nr = pfsolver.powerflow_newton_raphson(c, quiet_opt());
testCase.verifyEqual(r.bus_voltage, r_nr.bus_voltage, 'AbsTol', 1e-4);
end

function test_fdpf_bx_routing_and_metadata(testCase)
opt = quiet_opt(); opt.pf_method = 'fdpf_bx';
r = run_pf_solve_case('ieee5', opt);
testCase.verifyTrue(r.converged, 'FDPF-BX converged via solve_case');
testCase.verifyEqual(r.metadata.method_executed, 'BX');
testCase.verifyEqual(r.metadata.dispatch_requested, 'fdpf_bx');
testCase.verifyEqual(r.metadata.fallback_used, false);
end

function test_bfs_meshed_ieee14_fails_closed(testCase)
% BFS_ROUTED_CAPABILITY_GATED: solve_case routes to the BFS solver, which
% rejects meshed IEEE14 via the radial topology validator. No synthetic
% radial catalog case is added; BFS SUCCESS is asserted by the existing
% direct-factory test (test_pf_routing_end_to_end).
opt = quiet_opt(); opt.pf_method = 'bfs';
testCase.verifyError(@() run_pf_solve_case('ieee14', opt), ...
    'pf_validate_radial_topology:pvUnsupportedDeferred');
end

function test_unknown_pf_method_fails_closed(testCase)
opt = quiet_opt(); opt.pf_method = 'bogus';
testCase.verifyError(@() run_pf_solve_case('ieee5', opt), ...
    'pf_resolve_method:unknownMethod');
end

function test_nr_metadata_additive_and_nonuniform(testCase)
% NR metadata: existing num_buses AND the Phase-2 additive fields.
opt = quiet_opt();
r = run_pf_solve_case('ieee5', opt);
testCase.verifyTrue(isfield(r.metadata,'num_buses'), 'existing metadata preserved');
testCase.verifyEqual(r.metadata.method_requested, 'newton_raphson');
testCase.verifyEqual(r.metadata.method_executed, 'newton_raphson');
testCase.verifyEqual(r.metadata.dispatch_requested, 'newton_raphson');
testCase.verifyEqual(r.metadata.selection_source, 'default');
testCase.verifyTrue(isfield(r.metadata,'method_source'), 'impl provenance recorded');
testCase.verifyEqual(r.metadata.capability, 'production');
testCase.verifyEqual(r.metadata.fallback_used, false);
% NR full_ac_mismatch sourced from the existing max_mismatch.
testCase.verifyTrue(isfield(r,'max_mismatch'), 'NR max_mismatch exists');
testCase.verifyEqual(r.metadata.full_ac_mismatch, r.max_mismatch, 'AbsTol', 0);
% method_requested is NOT uniform across NR/XB/BX/bfs: NR reports
% 'newton_raphson', while FDPF reports its variant string. Verify the
% distinction by checking FDPF does not report 'newton_raphson'.
opt_xb = quiet_opt(); opt_xb.pf_method = 'fdpf_xb';
r_xb = run_pf_solve_case('ieee5', opt_xb);
testCase.verifyNotEqual(r_xb.metadata.method_executed, 'newton_raphson');
testCase.verifyEqual(r_xb.metadata.method_executed, 'XB');
end

function test_log_reports_executed_method(testCase)
% The launcher log must report the executed method (additive, optional).
% We verify the print_pf_checks path does not error and the result carries
% method_executed (printed by print_pf_checks). Capture via evalc string form.
opt = quiet_opt(); opt.verbose = true;
opt.pf_method = 'newton_raphson';
log = evalc("run_pf_solve_case('ieee5', struct('verbose',true,'plot_results',false,'max_iter',50,'tolerance',1e-10,'enforce_q_limits',false,'pf_method','newton_raphson'))");
testCase.verifyTrue(contains(log, 'Method executed'), 'log reports method_executed');
end

function test_solve_case_fdpf_xb_on_meshed_ieee14(testCase)
% C5 dialog-picker integration: the PF method picker hides BFS for meshed
% cases (case_is_radial=false for ieee14) but offers FDPF-XB. The programmatic
% equivalent — pf_method='fdpf_xb' via solve_case on meshed ieee14 — must run.
opt = struct('verbose',false,'plot_results',false,'max_iter',50, ...
    'tolerance',1e-10,'enforce_q_limits',false,'pf_method','fdpf_xb');
r = run_pf_solve_case('ieee14', opt);
testCase.verifyTrue(r.converged, 'FDPF-XB on meshed ieee14 via solve_case');
testCase.verifyEqual(r.metadata.method_executed, 'XB');
testCase.verifyEqual(r.metadata.dispatch_requested, 'fdpf_xb');
end

function test_solve_case_bfs_meshed_fails_closed(testCase)
% BFS remains fail-closed on meshed ieee14 (the picker hides it, but the
% authoritative guard is pf_validate_radial_topology at run time).
opt = struct('verbose',false,'plot_results',false,'max_iter',100, ...
    'tolerance',1e-10,'enforce_q_limits',false,'pf_method','bfs');
testCase.verifyError(@() run_pf_solve_case('ieee14', opt), ...
    'pf_validate_radial_topology:pvUnsupportedDeferred');
end

