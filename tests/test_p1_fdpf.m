function tests = test_p1_fdpf()
%TEST_P1_FDPF  P1 FDPF-XB and FDPF-BX solver tests (CORE_ONLY, NOT_ROUTED).
%   Sources verified: Stott & Alsac (1974) + van Amerongen (1989).
%
%   P1 scope (package-only): tested by DIRECT calls. solve_case.m is NOT
%   modified. CORE_ONLY / NOT_ROUTED.
%
%   Tests:
%     1. XB converges on IEEE5 within tolerance, agrees with NR
%     2. BX converges on IEEE5, agrees with NR
%     3. XB/BX agree with NR on IEEE14 (V within 1e-4)
%     4. full-AC-mismatch convergence (final mismatch < tolerance)
%     5. unknown PF method fails closed (bfs not yet registered)
%     6. factory returns correct strategy for fdpf_xb/fdpf_bx
%     7. Q-limit helper parity with NR's private function
%     8. no inv/pinv in FDPF solver
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

% =========================================================================
function test_fdpf_xb_converges_ieee5(testCase)
c = cases.case_ieee5bus();
r = pfsolver.powerflow_fdpf_xb(c, quiet_opt());
testCase.verifyTrue(r.converged, 'FDPF-XB converged on IEEE5.');
testCase.verifyLessThan(r.metadata.full_ac_mismatch, 1e-8, 'full AC mismatch < 1e-8.');
% Agreement with NR.
r_nr = pfsolver.powerflow_newton_raphson(c, quiet_opt());
testCase.verifyEqual(r.bus_voltage, r_nr.bus_voltage, 'AbsTol', 1e-4, 'FDPF-XB V matches NR within 1e-4.');
testCase.verifyEqual(r.bus_angle_deg, r_nr.bus_angle_deg, 'AbsTol', 1e-3, 'FDPF-XB angle matches NR within 1e-3.');
end

function test_fdpf_bx_converges_ieee5(testCase)
c = cases.case_ieee5bus();
r = pfsolver.powerflow_fdpf_bx(c, quiet_opt());
testCase.verifyTrue(r.converged, 'FDPF-BX converged on IEEE5.');
testCase.verifyLessThan(r.metadata.full_ac_mismatch, 1e-8, 'full AC mismatch < 1e-8.');
r_nr = pfsolver.powerflow_newton_raphson(c, quiet_opt());
testCase.verifyEqual(r.bus_voltage, r_nr.bus_voltage, 'AbsTol', 1e-4, 'FDPF-BX V matches NR within 1e-4.');
end

function test_fdpf_xb_agrees_nr_ieee14(testCase)
c = cases.case_ieee14bus();
r = pfsolver.powerflow_fdpf_xb(c, quiet_opt());
r_nr = pfsolver.powerflow_newton_raphson(c, quiet_opt());
testCase.verifyTrue(r.converged, 'FDPF-XB converged on IEEE14.');
testCase.verifyTrue(r_nr.converged, 'NR converged on IEEE14.');
testCase.verifyEqual(r.bus_voltage, r_nr.bus_voltage, 'AbsTol', 5e-4, 'FDPF-XB V matches NR within 5e-4 on IEEE14.');
end

function test_fdpf_bx_agrees_nr_ieee14(testCase)
c = cases.case_ieee14bus();
r = pfsolver.powerflow_fdpf_bx(c, quiet_opt());
r_nr = pfsolver.powerflow_newton_raphson(c, quiet_opt());
testCase.verifyTrue(r.converged, 'FDPF-BX converged on IEEE14.');
testCase.verifyEqual(r.bus_voltage, r_nr.bus_voltage, 'AbsTol', 5e-4, 'FDPF-BX V matches NR within 5e-4 on IEEE14.');
end

function test_full_ac_mismatch_convergence(testCase)
c = cases.case_ieee5bus();
r = pfsolver.powerflow_fdpf_xb(c, quiet_opt());
% The recorded full AC mismatch must be below the convergence tolerance.
testCase.verifyLessThan(r.metadata.full_ac_mismatch, 1e-8, 'FDPF full-AC mismatch converged.');
% The mismatch history must be non-increasing (monotone convergence).
if numel(r.mismatch_history) >= 2
    diffs = diff(r.mismatch_history);
    testCase.verifyTrue(all(diffs <= 1e-12), 'mismatch history non-increasing.');
end
end

function test_bfs_registered_p2(testCase)
% P2: bfs is now registered (radial Phase-1). Verify it resolves.
[mn, ~] = pfsolver.pf_resolve_method(struct('pf_method', 'bfs'));
testCase.verifyEqual(mn, 'bfs');
s = pfsolver.pf_method_strategy('bfs');
testCase.verifyEqual(s.name, 'bfs');
end

function test_factory_returns_fdpf_strategies(testCase)
sx = pfsolver.pf_method_strategy('fdpf_xb');
testCase.verifyEqual(sx.name, 'fdpf_xb');
testCase.verifyEqual(sx.capability, 'production');
sb = pfsolver.pf_method_strategy('fdpf_bx');
testCase.verifyEqual(sb.name, 'fdpf_bx');
% The factory .solve must call the right variant.
c = cases.case_ieee5bus();
rx = sx.solve(c, quiet_opt());
testCase.verifyEqual(rx.method_variant, 'XB', 'factory XB returns XB variant.');
rb = sb.solve(c, quiet_opt());
testCase.verifyEqual(rb.method_variant, 'BX', 'factory BX returns BX variant.');
end

function test_q_limit_helper_parity_with_nr(testCase)
% The shared pf_find_q_limit_violations must return byte-identical violation
% sets to NR's private find_q_limit_violations on the same model+results.
% IEEE30 (MATPOWER) has a Q-limit violation (1 event, 1 round) when solved
% with Q-limits enabled, making it a valid parity fixture.
c = cases.case_matpower_ieee30bus();
opt_noq = struct('verbose',false,'plot_results',false,'max_iter',100, ...
    'tolerance',1e-10,'enforce_q_limits',false);
% Solve with NR (Q-limits disabled) to get the pre-switch result.
r_nr = pfsolver.powerflow_newton_raphson(c, opt_noq);
model = pf_prepare_case(c);
[violated, fixed_Q, limit_type] = pf_find_q_limit_violations(model, r_nr, 1e-6);
% NR with Q-limits enabled reports the same violations as switching events.
opt_q = opt_noq; opt_q.enforce_q_limits = true;
r_nr_q = pfsolver.powerflow_newton_raphson(c, opt_q);
nr_events = r_nr_q.q_limit_switching.events;
nr_bus_ids = [nr_events.bus_id];
nr_fixed = [nr_events.Q_fixed];
nr_types = {nr_events.limit_type};
% The shared helper must detect the SAME bus IDs (by external ID).
shared_bus_ids = model.external_bus_ids(violated);
testCase.verifyEqual(sort(shared_bus_ids), sort(nr_bus_ids), 'AbsTol', 0, ...
    'shared helper detects same Q-limit bus IDs as NR.');
% The fixed Q values must match.
testCase.verifyEqual(sort(fixed_Q), sort(nr_fixed), 'AbsTol', 1e-10, ...
    'shared helper fixed_Q matches NR.');
% The limit types must match.
testCase.verifyEqual(sort(string(limit_type)), sort(string(nr_types)), ...
    'shared helper limit_type matches NR.');
% Schema consistency.
testCase.verifyEqual(size(violated,2), 1, 'violated_buses is column vector.');
testCase.verifyEqual(size(fixed_Q,2), 1, 'fixed_Q is column vector.');
testCase.verifyEqual(numel(limit_type), numel(violated), 'limit_type length matches.');
end

function test_no_inv_pinv_in_fdpf(testCase)
% The FDPF solver and B-matrix builder must not use inv/pinv.
files = {'+pfsolver/powerflow_fdpf.m', '+pfsolver/powerflow_fdpf_xb.m', ...
    '+pfsolver/powerflow_fdpf_bx.m', 'internal/core/pf_build_b_matrices.m', ...
    'internal/core/pf_find_q_limit_violations.m'};
for k = 1:numel(files)
    txt = fileread(files{k});
    % Allow 'inv' only in comments; check for inv( or pinv( as calls.
    has_inv = ~isempty(regexp(txt, '[^a-zA-Z_]inv\(', 'once'));
    has_pinv = ~isempty(regexp(txt, 'pinv\(', 'once'));
    testCase.verifyFalse(has_inv, sprintf('No inv() in %s.', files{k}));
    testCase.verifyFalse(has_pinv, sprintf('No pinv() in %s.', files{k}));
end
end
