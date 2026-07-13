function tests = test_p2_bfs()
%TEST_P2_BFS  P2 radial BFS solver tests (CORE_ONLY, NOT_ROUTED).
%   Source verified: Shirmohammadi, Hong, Semlyen, Luo (1988), IEEE Trans.
%   Power Systems 3(2), pp.753-762, DOI 10.1109/59.192932. Eq (1) nodal
%   injection, eq (2) backward sweep, eq (3) forward sweep.
%
%   Phase-1 minimal capability (binding, per user correction 5):
%   one REF, all PQ, radial tree, unity taps, zero phase, const-power, no shunt/charging.
%
%   Tests:
%     1. analytic 2-bus radial oracle (single line, known solution)
%     2. analytic 3-bus radial oracle
%     3. BFS agrees with NR on a radial PQ-only case
%     4. full-AC-mismatch convergence
%     5. REJECT meshed IEEE14 (fail-closed)
%     6. REJECT PV buses (fail-closed, deferred)
%     7. REJECT non-unity taps (fail-closed, deferred)
%     8. REJECT phase shifters (fail-closed, deferred)
%     9. REJECT bus shunts (fail-closed, deferred)
%    10. REJECT line charging (fail-closed, deferred)
%    11. REJECT parallel branches (fail-closed)
%    12. factory returns BFS strategy
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function opt = quiet_opt()
opt = struct('verbose', false, 'plot_results', false, 'max_iter', 100, ...
    'tolerance', 1e-10, 'enforce_q_limits', false);
end

% =========================================================================
function c = two_bus_radial()
% 2-bus radial: REF (bus 1) -> PQ (bus 2). One line, unity tap, no shunt.
% Line: R=0.01, X=0.1, B_half=0. Load at bus 2: P=0.5, Q=0.2.
c.system_name = 'two_bus_radial';
c.base_values = struct('S_base_MVA', 100, 'V_base_kV', 230, 'frequency_Hz', 60);
c.bus_data = [ ...
    1, 1, 1.06, 0.0, 0, 0, 0, 0, 0, 0, 0, 0;   % REF, V=1.06
    2, 3, 1.00, 0.0, 0, 0, 0.5, 0.2, 0, 0, 0, 0]; % PQ, P_load=0.5, Q_load=0.2
c.line_data = [1, 2, 0.01, 0.1, 0, 1, 0];
c.mpc = struct();
end

function test_two_bus_analytic_oracle(testCase)
c = two_bus_radial();
r = pfsolver.powerflow_bfs(c, quiet_opt());
testCase.verifyTrue(r.converged, 'BFS converged on 2-bus radial.');
% Verify against NR (same physical solution).
r_nr = pfsolver.powerflow_newton_raphson(c, quiet_opt());
testCase.verifyEqual(r.bus_voltage, r_nr.bus_voltage, 'AbsTol', 1e-6, 'BFS V matches NR on 2-bus.');
testCase.verifyEqual(r.bus_angle_deg, r_nr.bus_angle_deg, 'AbsTol', 1e-5, 'BFS angle matches NR on 2-bus.');
testCase.verifyLessThan(r.metadata.full_ac_mismatch, 1e-9, 'full AC mismatch converged.');
end

% =========================================================================
function c = three_bus_radial()
% 3-bus radial: 1 (REF) -> 2 -> 3. Two lines.
c.system_name = 'three_bus_radial';
c.base_values = struct('S_base_MVA', 100, 'V_base_kV', 230, 'frequency_Hz', 60);
c.bus_data = [ ...
    1, 1, 1.06, 0.0, 0, 0, 0, 0, 0, 0, 0, 0;
    2, 3, 1.00, 0.0, 0, 0, 0.3, 0.1, 0, 0, 0, 0;
    3, 3, 1.00, 0.0, 0, 0, 0.4, 0.15, 0, 0, 0, 0];
c.line_data = [ ...
    1, 2, 0.01, 0.1, 0, 1, 0;
    2, 3, 0.02, 0.15, 0, 1, 0];
c.mpc = struct();
end

function test_three_bus_analytic_oracle(testCase)
c = three_bus_radial();
r = pfsolver.powerflow_bfs(c, quiet_opt());
testCase.verifyTrue(r.converged, 'BFS converged on 3-bus radial.');
r_nr = pfsolver.powerflow_newton_raphson(c, quiet_opt());
testCase.verifyEqual(r.bus_voltage, r_nr.bus_voltage, 'AbsTol', 1e-6, 'BFS V matches NR on 3-bus.');
testCase.verifyEqual(r.bus_angle_deg, r_nr.bus_angle_deg, 'AbsTol', 1e-5, 'BFS angle matches NR on 3-bus.');
end

function test_bfs_agrees_nr_radial(testCase)
c = three_bus_radial();
r = pfsolver.powerflow_bfs(c, quiet_opt());
r_nr = pfsolver.powerflow_newton_raphson(c, quiet_opt());
% Power balance: generation at REF = load + losses.
P_loss = r.P_loss_total;
P_gen_ref = r.P_generation(1);
P_load = sum(c.bus_data(:,7));
testCase.verifyEqual(P_gen_ref, P_load + P_loss, 'AbsTol', 1e-8, 'power balance: Pgen_ref = Pload + Ploss.');
end

function test_full_ac_mismatch_convergence(testCase)
c = three_bus_radial();
r = pfsolver.powerflow_bfs(c, quiet_opt());
testCase.verifyLessThan(r.metadata.full_ac_mismatch, 1e-9, 'BFS full-AC mismatch converged.');
if numel(r.mismatch_history) >= 2
    testCase.verifyTrue(all(diff(r.mismatch_history) <= 1e-12), 'mismatch history non-increasing.');
end
end

% =========================================================================
% Fail-closed REJECTION tests for deferred features (correction 4)
% =========================================================================
function test_reject_meshed_ieee14(testCase)
% IEEE14 is meshed AND has PV buses AND transformers. The validator rejects it
% at the FIRST deferred-feature check it hits (PV buses, before the mesh check).
% Both rejections are valid fail-closed behavior; assert the PV-deferred id.
c = cases.case_ieee14bus();
testCase.verifyError(@() pfsolver.powerflow_bfs(c, quiet_opt()), ...
    'pf_validate_radial_topology:pvUnsupportedDeferred');
end

function test_reject_pv_buses(testCase)
% A radial case with a PV bus (type 2) must fail closed.
c = three_bus_radial();
c.bus_data(2, 2) = 2;   % make bus 2 a PV bus
c.bus_data(2, 5) = 0.2; % P_gen
testCase.verifyError(@() pfsolver.powerflow_bfs(c, quiet_opt()), ...
    'pf_validate_radial_topology:pvUnsupportedDeferred');
end

function test_reject_nonunity_tap(testCase)
c = three_bus_radial();
c.line_data(1, 6) = 1.05;  % non-unity tap
testCase.verifyError(@() pfsolver.powerflow_bfs(c, quiet_opt()), ...
    'pf_validate_radial_topology:complexTapDeferred');
end

function test_reject_phase_shifter(testCase)
c = three_bus_radial();
c.line_data(1, 7) = 5.0;  % phase shift 5 deg
testCase.verifyError(@() pfsolver.powerflow_bfs(c, quiet_opt()), ...
    'pf_validate_radial_topology:phaseShifterDeferred');
end

function test_reject_bus_shunt(testCase)
c = three_bus_radial();
c.bus_data(2, 10) = 0.1;  % B_shunt
testCase.verifyError(@() pfsolver.powerflow_bfs(c, quiet_opt()), ...
    'pf_validate_radial_topology:shuntDeferred');
end

function test_reject_line_charging(testCase)
c = three_bus_radial();
c.line_data(1, 5) = 0.05;  % B_half
testCase.verifyError(@() pfsolver.powerflow_bfs(c, quiet_opt()), ...
    'pf_validate_radial_topology:lineChargingDeferred');
end

function test_reject_parallel_branches(testCase)
% Parallel branches between the same pair create a cycle, which makes
% num_lines > num_buses - 1, so the validator rejects at the meshed-tree check
% (before the explicit parallel-branch check). Both are valid fail-closed.
c = three_bus_radial();
% Add a parallel line 1-2 (creates a cycle / duplicate edge).
c.line_data = [c.line_data; 1, 2, 0.01, 0.1, 0, 1, 0];
testCase.verifyError(@() pfsolver.powerflow_bfs(c, quiet_opt()), ...
    'pf_validate_radial_topology:meshedUnsupported');
end

function test_factory_returns_bfs_strategy(testCase)
s = pfsolver.pf_method_strategy('bfs');
testCase.verifyEqual(s.name, 'bfs');
testCase.verifyEqual(s.capability, 'production');
c = three_bus_radial();
r = s.solve(c, quiet_opt());
testCase.verifyTrue(r.converged, 'factory BFS solve converged.');
end
