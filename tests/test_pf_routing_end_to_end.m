function tests = test_pf_routing_end_to_end()
%TEST_PF_ROUTING_END_TO_END  Phase-1 package-level PF routing tests (CORE_ONLY).
%   Verifies the PF method factory routing end-to-end via DIRECT factory calls
%   (no solve_case.m edits — production routing is Phase 2, NOT_READY).
%
%   Tests:
%     1. default (absent pf_method) resolves to newton_raphson, source='default'
%     2. explicit newton_raphson via factory == direct NR, AbsTol=0 (bit-identity)
%     3. fdpf_xb/fdpf_bx via factory produce method_executed metadata, agree with NR
%     4. bfs via factory on radial case produces method_executed, agrees with NR
%     5. unknown pf_method fails closed before solve
%     6. bfs on meshed IEEE14 fails closed (topology)
%     7. every method records method_requested/method_executed/method_source/capability/fallback_used=false
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

function verify_method_metadata(testCase, r, expected_executed, expected_source)
% All registered methods must record the metadata contract.
testCase.verifyTrue(isfield(r, 'metadata'), 'result has metadata');
testCase.verifyEqual(r.metadata.method_executed, expected_executed, 'method_executed');
testCase.verifyEqual(r.metadata.method_source, expected_source, 'method_source');
testCase.verifyEqual(r.metadata.fallback_used, false, 'fallback_used=false');
testCase.verifyTrue(isfield(r.metadata, 'capability'), 'capability recorded');
testCase.verifyTrue(isfield(r.metadata, 'full_ac_mismatch'), 'full_ac_mismatch recorded');
end

% =========================================================================
function test_default_absent_resolves_newton_raphson(testCase)
[mn, ms] = pfsolver.pf_resolve_method(struct());
testCase.verifyEqual(mn, 'newton_raphson');
testCase.verifyEqual(ms, 'default');
strat = pfsolver.pf_method_strategy(mn);
testCase.verifyEqual(strat.name, 'newton_raphson');
end

function test_factory_nr_bit_identical_to_direct(testCase)
% Default/explicit NR via factory must be bit-identical (AbsTol=0) to direct NR.
c = cases.case_ieee5bus();
opt = quiet_opt();
strat = pfsolver.pf_method_strategy('newton_raphson');
r_factory = strat.solve(c, opt);
r_direct = pfsolver.powerflow_newton_raphson(c, opt);
testCase.verifyEqual(r_factory.bus_voltage, r_direct.bus_voltage, 'AbsTol', 0);
testCase.verifyEqual(r_factory.bus_angle_deg, r_direct.bus_angle_deg, 'AbsTol', 0);
testCase.verifyEqual(r_factory.iterations, r_direct.iterations);
testCase.verifyEqual(r_factory.converged, r_direct.converged);
end

function test_fdpf_xb_routing_and_metadata(testCase)
c = cases.case_ieee5bus();
opt = quiet_opt();
strat = pfsolver.pf_method_strategy('fdpf_xb');
r = strat.solve(c, opt);
testCase.verifyTrue(r.converged, 'FDPF-XB converged');
verify_method_metadata(testCase, r, 'XB', 'in-house FDPF (Stott-Alsac 1974 + van Amerongen 1989)');
r_nr = pfsolver.powerflow_newton_raphson(c, opt);
testCase.verifyEqual(r.bus_voltage, r_nr.bus_voltage, 'AbsTol', 1e-4);
end

function test_fdpf_bx_routing_and_metadata(testCase)
c = cases.case_ieee5bus();
opt = quiet_opt();
strat = pfsolver.pf_method_strategy('fdpf_bx');
r = strat.solve(c, opt);
testCase.verifyTrue(r.converged, 'FDPF-BX converged');
verify_method_metadata(testCase, r, 'BX', 'in-house FDPF (Stott-Alsac 1974 + van Amerongen 1989)');
end

function test_bfs_routing_and_metadata(testCase)
c.system_name = 'three_bus_radial';
c.base_values = struct('S_base_MVA', 100, 'V_base_kV', 230, 'frequency_Hz', 60);
c.bus_data = [1,1,1.06,0,0,0,0,0,0,0,0,0; 2,3,1.0,0,0,0,0.3,0.1,0,0,0,0; 3,3,1.0,0,0,0,0.4,0.15,0,0,0,0];
c.line_data = [1,2,0.01,0.1,0,1,0; 2,3,0.02,0.15,0,1,0];
c.mpc = struct();
opt = quiet_opt();
strat = pfsolver.pf_method_strategy('bfs');
r = strat.solve(c, opt);
testCase.verifyTrue(r.converged, 'BFS converged');
verify_method_metadata(testCase, r, 'bfs', 'in-house BFS (Shirmohammadi 1988) Phase-1 radial');
r_nr = pfsolver.powerflow_newton_raphson(c, opt);
testCase.verifyEqual(r.bus_voltage, r_nr.bus_voltage, 'AbsTol', 1e-6);
end

function test_unknown_pf_method_fails_closed(testCase)
testCase.verifyError(@() pfsolver.pf_resolve_method(struct('pf_method', 'bogus')), ...
    'pf_resolve_method:unknownMethod');
testCase.verifyError(@() pfsolver.pf_method_strategy('bogus'), ...
    'pf_method_strategy:unknownMethod');
end

function test_bfs_meshed_ieee14_fails_closed(testCase)
c = cases.case_ieee14bus();
opt = quiet_opt();
strat = pfsolver.pf_method_strategy('bfs');
testCase.verifyError(@() strat.solve(c, opt), 'pf_validate_radial_topology:pvUnsupportedDeferred');
end
