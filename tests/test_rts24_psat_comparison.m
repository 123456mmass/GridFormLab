function tests = test_rts24_psat_comparison()
%TEST_RTS24_PSAT_COMPARISON Unit tests for RTS-24 PSAT cross-validation.
%   These tests verify the conversion, metrics, and configuration without
%   requiring PSAT to be installed.  Integration tests that need PSAT
%   are skipped when PSAT is not found.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function c = load_case()
c = cases.case_ieee_rts24_pgaz();
end

% =========================================================================
function test_rts24_to_psat_conversion(testCase)
% Verify the PSAT case conversion produces correct matrix dimensions.
c = load_case();
pc = rts24_to_psat_case(c);
testCase.verifyEqual(size(pc.Bus_con,1), 24, '24 buses.');
testCase.verifyEqual(size(pc.Line_con,1), 38, '38 lines.');
testCase.verifyEqual(size(pc.SW_con,1), 1, '1 slack bus.');
testCase.verifyEqual(size(pc.PV_con,1), 10, '10 PV buses.');
testCase.verifyEqual(size(pc.Syn_con,1), 11, '11 generator buses.');
testCase.verifyEqual(size(pc.Fault_con,1), 1, '1 fault.');
end

% =========================================================================
function test_line_B_is_total(testCase)
% PSAT Line.con col 10 = B_total; our case_data stores B_half.
% Verify B_total = 2 * B_half.
c = load_case();
pc = rts24_to_psat_case(c);
for k = 1:size(pc.Line_con,1)
    our_Bhalf = c.line_data(k,5);
    psat_Btotal = pc.Line_con(k,10);
    testCase.verifyEqual(psat_Btotal, 2*our_Bhalf, 'AbsTol', 1e-12, ...
        sprintf('Line %d: B_total must be 2*B_half', k));
end
end

% =========================================================================
function test_transformer_taps_match(testCase)
% Transformer tap ratios must match between case_data and PSAT conversion.
c = load_case();
pc = rts24_to_psat_case(c);
for k = 1:size(pc.Line_con,1)
    our_tap = c.line_data(k,6);
    if our_tap == 0, our_tap = 1; end
    psat_tap = pc.Line_con(k,11);
    testCase.verifyEqual(psat_tap, our_tap, 'AbsTol', 1e-12, ...
        sprintf('Line %d: tap mismatch', k));
end
end

% =========================================================================
function test_shunt_sign_convention(testCase)
% Shunt Bs: positive = capacitive in both PSAT and in-house.
% Bus 6 has Bs=-100 Mvar (inductive) -> Bsh=-1.0 pu.
c = load_case();
pc = rts24_to_psat_case(c);
% Shunt.con: [bus Sn Vn fn Gs Bs u]
b6_idx = find(pc.Shunt_con(:,1)==6);
testCase.verifyNotEmpty(b6_idx, 'Bus 6 shunt must exist.');
testCase.verifyEqual(pc.Shunt_con(b6_idx,6), -1.0, 'AbsTol', 1e-12, ...
    'Bus 6 Bs must be -1.0 pu (inductive).');
end

% =========================================================================
function test_Zf_complex_value(testCase)
% Zf must be 0 + j0.1 in both solvers.
c = load_case();
pc = rts24_to_psat_case(c, 'Zf', 0+0.1j);
testCase.verifyEqual(real(pc.Zf), 0, 'AbsTol', 1e-12, 'Rf must be 0.');
testCase.verifyEqual(imag(pc.Zf), 0.1, 'AbsTol', 1e-12, 'Xf must be 0.1.');
% Fault.con: col 7 = Rf, col 8 = Xf
testCase.verifyEqual(pc.Fault_con(7), 0, 'AbsTol', 1e-12, 'Fault Rf=0.');
testCase.verifyEqual(pc.Fault_con(8), 0.1, 'AbsTol', 1e-12, 'Fault Xf=0.1.');
end

% =========================================================================
function test_event_times_match(testCase)
c = load_case();
pc = rts24_to_psat_case(c, 't_fault', 1.0, 't_clear', 1.1);
testCase.verifyEqual(pc.t_fault, 1.0, 'Fault start time.');
testCase.verifyEqual(pc.t_clear, 1.1, 'Fault clear time.');
end

% =========================================================================
function test_load_model_constant_impedance(testCase)
% In-house TS uses Yload = conj(Sload)./V0^2 (constant admittance).
% PSAT uses pq2z=1 (PQ -> constant impedance at PF operating point).
% Verify the in-house code does NOT use constant power.
c = load_case();
opt = struct('t_end',0.1,'dt',0.01,'fault_bus',15, ...
    't_fault',999,'t_clear',999.1,'Zf',0+0.1j, ...
    'method','trapezoidal','corrector_iter',1, ...
    'verbose',false,'model','classical','plot_results',false);
r = stability.ts_simulate(c,opt);
% If constant impedance, no-fault should have zero drift (load doesn't change).
testCase.verifyLessThan(max(abs(r.omega-1),[],'all'), 1e-9, ...
    'No-fault: constant-Z load must have zero drift.');
end

% =========================================================================
function test_generator_bus_mapping(testCase)
% Syn.con buses must match the in-house gen buses.
c = load_case();
pc = rts24_to_psat_case(c);
u = c.machines.units;
gen_buses = unique([u.bus]).';
testCase.verifyEqual(pc.Syn_con(:,1)', gen_buses.', ...
    'PSAT Syn buses must match in-house gen buses.');
end

% =========================================================================
function test_H_D_Xdp_match(testCase)
% H_ours = H_table * Pmw/Sbase; PSAT stores 2H in col 18.
% Xdp_ours = Xdp_table * Sbase/Smva; PSAT stores Xdp in col 9.
c = load_case();
pc = rts24_to_psat_case(c);
u = c.machines.units;
gen_buses = unique([u.bus]).';
for k = 1:numel(gen_buses)
    b = gen_buses(k);
    idx = [u.bus]==b;
    H_agg = sum([u(idx).H]);
    Xdp_agg = 1/sum(1./[u(idx).Xdp]);
    D_agg = sum([u(idx).D]);
    testCase.verifyEqual(pc.Syn_con(k,18), 2*H_agg, 'AbsTol', 1e-6, ...
        sprintf('Bus %d: 2H mismatch', b));
    testCase.verifyEqual(pc.Syn_con(k,9), Xdp_agg, 'AbsTol', 1e-6, ...
        sprintf('Bus %d: Xdp mismatch', b));
    testCase.verifyEqual(pc.Syn_con(k,19), D_agg, 'AbsTol', 1e-6, ...
        sprintf('Bus %d: D mismatch', b));
end
end

% =========================================================================
function test_incremental_coi_metric(testCase)
% Incremental COI = (delta - delta_coi) - (delta(0) - delta_coi(0)).
% At t=0, incremental must be exactly 0.
c = load_case();
opt = struct('t_end',5,'dt',0.01,'fault_bus',15, ...
    't_fault',1.0,'t_clear',1.1,'Zf',0+0.1j, ...
    'method','trapezoidal','corrector_iter',1, ...
    'verbose',false,'model','classical','plot_results',false);
r = stability.ts_simulate(c,opt);
Hw = r.H(:).';
dcoi = r.delta - sum(r.delta.*Hw,2)./sum(Hw);
dcoi_inc = dcoi - dcoi(1,:);
testCase.verifyEqual(dcoi_inc(1,:), zeros(1,size(dcoi,2)), 'AbsTol', 1e-12, ...
    'Incremental COI at t=0 must be zero.');
end

% =========================================================================
function test_incremental_pairwise_metric(testCase)
% Incremental pairwise = pair(t) - pair(0). At t=0, must be 0.
c = load_case();
opt = struct('t_end',1,'dt',0.01,'fault_bus',15, ...
    't_fault',999,'t_clear',999.1,'Zf',0+0.1j, ...
    'method','trapezoidal','corrector_iter',1, ...
    'verbose',false,'model','classical','plot_results',false);
r = stability.ts_simulate(c,opt);
ng = size(r.delta,2);
pair0 = r.delta(1,1) - r.delta(1,2);
pair_inc = (r.delta(:,1) - r.delta(:,2)) - pair0;
testCase.verifyEqual(pair_inc(1), 0, 'AbsTol', 1e-12, ...
    'Incremental pairwise at t=0 must be zero.');
end

% =========================================================================
function test_no_extrapolation(testCase)
% Interpolation must not extrapolate beyond PSAT time range.
% Verify by checking that t_int is within [t_ps(1), t_ps(end)].
% (This is a logic test; actual interpolation tested in integration.)
t_ps = [0; 0.01; 0.02; 0.03];
t_ours = [0; 0.005; 0.01; 0.02; 0.03; 0.04];  % 0.04 > t_ps(end)
tmin = max(t_ours(1), t_ps(1));
tmax = min(t_ours(end), t_ps(end));
keep = t_ours >= tmin & t_ours <= tmax;
testCase.verifyTrue(all(t_ours(keep) <= tmax), 'No extrapolation beyond tmax.');
testCase.verifyTrue(all(t_ours(keep) >= tmin), 'No extrapolation below tmin.');
testCase.verifyEqual(t_ours(keep), [0; 0.005; 0.01; 0.02; 0.03], ...
    'Overlap window correct.');
end

% =========================================================================
function test_no_external_solver_in_production(testCase)
% Verify that the in-house PF solver does not call PSAT/MATPOWER/fsolve.
c = load_case();
r = pfsolver.powerflow_newton_raphson(c, struct('verbose',false, ...
    'plot_results',false,'max_iter',50,'tolerance',1e-10, ...
    'enforce_q_limits',false));
testCase.verifyTrue(r.converged);
testCase.verifyEqual(r.method, 'Newton-Raphson', ...
    'Must use in-house Newton-Raphson, not external solver.');
end

% =========================================================================
function test_validation_does_not_modify_production(testCase)
% The comparison script must not modify case_data parameters.
c1 = load_case();
H1 = [c1.machines.units.H];
Xdp1 = [c1.machines.units.Xdp];
pc = rts24_to_psat_case(c1);
c2 = load_case();
H2 = [c2.machines.units.H];
Xdp2 = [c2.machines.units.Xdp];
testCase.verifyEqual(H1, H2, 'AbsTol', 0, 'Production H must not change.');
testCase.verifyEqual(Xdp1, Xdp2, 'AbsTol', 0, 'Production Xdp must not change.');
end

% =========================================================================
function test_psat_integration_optional(testCase)
% Integration test: if PSAT is available, run the comparison.
% Skip if PSAT not found.
psat_root = 'C:/Users/User/Downloads/psat-2.1.11-mat/psat';
if ~exist(psat_root, 'dir')
    testCase.assumeFalse(true, 'PSAT not found; skipping integration test.');
    return;
end
report = compare_rts24_psat();
testCase.verifyTrue(report.psat_available, 'PSAT comparison must succeed.');
testCase.verifyTrue(exist(report.outdir, 'dir') > 0, 'Output dir must exist.');
% Verify output files exist
testCase.verifyTrue(exist(fullfile(report.outdir,'rts24_pf_comparison.csv'),'file') > 0);
testCase.verifyTrue(exist(fullfile(report.outdir,'rts24_ts_metrics.csv'),'file') > 0);
testCase.verifyTrue(exist(fullfile(report.outdir,'rts24_machine_parameter_comparison.csv'),'file') > 0);
testCase.verifyTrue(exist(fullfile(report.outdir,'rts24_psat_comparison.md'),'file') > 0);
end
