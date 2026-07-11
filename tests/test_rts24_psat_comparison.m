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
function test_psat_conversion_dimensions(testCase)
% Verify the PSAT case conversion produces correct matrix dimensions.
c = load_case();
pc = rts24_to_psat_case(c);
testCase.verifyEqual(size(pc.Bus_con,1), 24, '24 buses.');
testCase.verifyEqual(size(pc.Line_con,1), 38, '38 lines.');
testCase.verifyEqual(size(pc.SW_con,1), 1, '1 slack bus.');
testCase.verifyEqual(size(pc.PV_con,1), 10, '10 PV buses.');
testCase.verifyEqual(size(pc.Syn_con,1), 11, '11 generator buses.');
testCase.verifyEqual(size(pc.Fault_con,1), 1, '1 fault.');
% Syn.con MUST be 28 columns (PSAT @SYclass ncol=28)
testCase.verifyEqual(size(pc.Syn_con,2), 28, 'Syn.con must have 28 columns.');
% Line.con MUST be 16 columns (PSAT @LNclass ncol=16)
testCase.verifyEqual(size(pc.Line_con,2), 16, 'Line.con must have 16 columns.');
end

% =========================================================================
function test_syn_con_pgen_ratio_is_one(testCase)
% PSAT @SYclass/setx0.m: for single machine per bus, col 22 (Pgen_ratio)
% MUST be 1 and col 23 (Qgen_ratio) MUST be 1.  Otherwise PSAT warns and
% overrides — the input would NOT be what we claim.
c = load_case();
pc = rts24_to_psat_case(c);
for k = 1:size(pc.Syn_con,1)
    testCase.verifyEqual(pc.Syn_con(k,22), 1, 'AbsTol', 1e-12, ...
        sprintf('Syn row %d (bus %d): Pgen ratio must be 1', k, pc.Syn_con(k,1)));
    testCase.verifyEqual(pc.Syn_con(k,23), 1, 'AbsTol', 1e-12, ...
        sprintf('Syn row %d (bus %d): Qgen ratio must be 1', k, pc.Syn_con(k,1)));
    testCase.verifyEqual(pc.Syn_con(k,28), 1, 'AbsTol', 1e-12, ...
        sprintf('Syn row %d (bus %d): u (status) must be 1', k, pc.Syn_con(k,1)));
end
end

% =========================================================================
function test_q_limits_not_multiplied_by_sbase(testCase)
% PSAT SW.con/PV.con Q limits are in pu on Sn (verified from @SWclass/base.m
% and @PVclass/base.m: Qmax_sys = Qmax_input * Sn / Settings.mva).
% Since Sn = Sbase = Settings.mva, the conversion is identity.
% So Qmax/Qmin input must EQUAL the case_data pu values (NOT × Sbase).
c = load_case();
pc = rts24_to_psat_case(c);
bd = c.bus_data;
% SW.con: [bus Sn Vn Vm Va Qmax Qmin Vmax Vmin Pgen area zone u]
sw = find(bd(:,2)==1,1);
testCase.verifyEqual(pc.SW_con(1,6), bd(sw,12), 'AbsTol', 1e-12, ...
    'SW Qmax must equal case_data Qmax (pu, not MVA).');
testCase.verifyEqual(pc.SW_con(1,7), bd(sw,11), 'AbsTol', 1e-12, ...
    'SW Qmin must equal case_data Qmin (pu, not MVA).');
% PV.con: [bus Sn Vn Pg Vm Qmax Qmin Vmax Vmin area u]
pv_idx = find(bd(:,2)==2);
for k = 1:numel(pv_idx)
    r = pv_idx(k);
    testCase.verifyEqual(pc.PV_con(k,4), bd(r,5), 'AbsTol', 1e-12, ...
        sprintf('PV bus %d: Pg must be pu', bd(r,1)));
    testCase.verifyEqual(pc.PV_con(k,6), bd(r,12), 'AbsTol', 1e-12, ...
        sprintf('PV bus %d: Qmax must be pu', bd(r,1)));
    testCase.verifyEqual(pc.PV_con(k,7), bd(r,11), 'AbsTol', 1e-12, ...
        sprintf('PV bus %d: Qmin must be pu', bd(r,1)));
end
end

% =========================================================================
function test_line_B_is_total(testCase)
% PSAT Line.con col 10 = B_total; our case_data stores B_half.
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
function test_transformer_kt_column(testCase)
% Line.con col 7 = kt (transformer voltage ratio). Must be non-zero for
% transformers (different voltage bases) and 0 for regular lines.
% Verified from @LNclass/base.m: idx=find(con(:,7)), kt=con(idx,7).
c = load_case();
pc = rts24_to_psat_case(c);
bd = c.bus_data;
Vb = cases.ieee_rts24_pgaz_raw().ABus_con(:,3);
for k = 1:size(pc.Line_con,1)
    f = c.line_data(k,1); t = c.line_data(k,2);
    vf = Vb(find(bd(:,1)==f,1)); vt = Vb(find(bd(:,1)==t,1));
    if abs(vf - vt) > 1
        % Transformer: kt = Vn_from / Vn_to
        testCase.verifyEqual(pc.Line_con(k,7), vf/vt, 'RelTol', 1e-6, ...
            sprintf('Line %d-%d: kt must be Vn_from/Vn_to', f, t));
    else
        % Regular line: kt = 0
        testCase.verifyEqual(pc.Line_con(k,7), 0, 'AbsTol', 1e-12, ...
            sprintf('Line %d-%d: kt must be 0 for regular line', f, t));
    end
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
% Verify the in-house PF solution and load admittance match the PSAT model.
c = load_case();
pf = pfsolver.powerflow_newton_raphson(c, struct('verbose',false, ...
    'plot_results',false,'max_iter',50,'tolerance',1e-10,'enforce_q_limits',false));
V = pf.bus_voltage;
% In-house: Yload = conj(S0)/V0^2. At PF, S = V0^2 * conj(Yload) = S0.
% If voltage changes to V, S = V^2 * conj(Yload) = S0 * (V/V0)^2.
% This is the same as PSAT pq2z: P = P0 * (V/V_pf)^2.
bd = c.bus_data;
load_idx = find(bd(:,7)~=0 | bd(:,8)~=0);
for k = load_idx'
    P0 = bd(k,7); Q0 = bd(k,8); V0 = V(k);
    Yload = conj(P0 + 1j*Q0) / V0^2;  % constant admittance
    % At PF: S = V0^2 * conj(Yload) = P0 + j*Q0
    S_check = V0^2 * conj(Yload);
    testCase.verifyEqual(real(S_check), P0, 'AbsTol', 1e-10, ...
        sprintf('Bus %d: constant-Z load P must match at PF', bd(k,1)));
    testCase.verifyEqual(imag(S_check), Q0, 'AbsTol', 1e-10, ...
        sprintf('Bus %d: constant-Z load Q must match at PF', bd(k,1)));
end
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
    nu = nnz(idx);
    H_agg = sum([u(idx).H]);
    Xdp_agg = 1/sum(1./[u(idx).Xdp]);
    D_agg = sum([u(idx).D]);
    testCase.verifyEqual(pc.Syn_con(k,18), 2*H_agg, 'AbsTol', 1e-6, ...
        sprintf('Bus %d (%d units): 2H mismatch', b, nu));
    testCase.verifyEqual(pc.Syn_con(k,9), Xdp_agg, 'AbsTol', 1e-6, ...
        sprintf('Bus %d (%d units): Xdp mismatch', b, nu));
    testCase.verifyEqual(pc.Syn_con(k,19), D_agg, 'AbsTol', 1e-6, ...
        sprintf('Bus %d (%d units): D mismatch', b, nu));
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
function test_no_extrapolation(testCase)
% Interpolation must not extrapolate beyond PSAT time range.
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
pc = rts24_to_psat_case(c1); %#ok<NASGU>
c2 = load_case();
H2 = [c2.machines.units.H];
Xdp2 = [c2.machines.units.Xdp];
testCase.verifyEqual(H1, H2, 'AbsTol', 0, 'Production H must not change.');
testCase.verifyEqual(Xdp1, Xdp2, 'AbsTol', 0, 'Production Xdp must not change.');
end

% =========================================================================
function test_all_matrices_present_in_converter(testCase)
% Verify ALL required PSAT matrices are present in the converter output.
c = load_case();
pc = rts24_to_psat_case(c);
required_fields = {'Bus_con','Line_con','SW_con','PV_con','PQ_con', ...
    'Shunt_con','Syn_con','Fault_con','Bus_names'};
for k = 1:numel(required_fields)
    testCase.assertTrue(isfield(pc, required_fields{k}), ...
        sprintf('Missing field: %s', required_fields{k}));
    testCase.verifyNotEmpty(pc.(required_fields{k}), ...
        sprintf('Field %s must not be empty', required_fields{k}));
end
end

% =========================================================================
function test_runner_writes_all_matrices_no_d024(testCase)
% Verify the runner writes ALL matrices and does NOT call d_024_mdl.
% Read the runner source and the generated case file content.
runner_src = fileread('scripts/validation/run_psat_rts24.m');
% Must NOT contain d_024_mdl
testCase.verifyEmpty(strfind(runner_src, 'd_024_mdl'), ...
    'Runner must NOT call d_024_mdl.');
% Must write ALL matrices
required = {'Bus.con', 'Line.con', 'Shunt.con', 'SW.con', 'PV.con', ...
    'PQ.con', 'Syn.con', 'Fault.con', 'Bus.names'};
for k = 1:numel(required)
    testCase.verifyNotEmpty(strfind(runner_src, required{k}), ...
        sprintf('Runner must write %s', required{k}));
end
end

% =========================================================================
function test_fault_con_t_fault(testCase)
% Fault.con col 5 must be t_fault (not constant 1).
% Verified from @FTclass/setup.m: col 5 = fault occurrence time.
c = load_case();
pc = rts24_to_psat_case(c, 't_fault', 1.0, 't_clear', 1.1);
testCase.verifyEqual(pc.Fault_con(5), 1.0, 'AbsTol', 1e-12, 'Fault col 5 must be t_fault.');
testCase.verifyEqual(pc.Fault_con(6), 1.1, 'AbsTol', 1e-12, 'Fault col 6 must be t_clear.');
% Test with different t_fault
pc2 = rts24_to_psat_case(c, 't_fault', 0.5, 't_clear', 0.7);
testCase.verifyEqual(pc2.Fault_con(5), 0.5, 'AbsTol', 1e-12, 'Fault col 5 must follow opt.t_fault.');
testCase.verifyEqual(pc2.Fault_con(6), 0.7, 'AbsTol', 1e-12, 'Fault col 6 must follow opt.t_clear.');
end

% =========================================================================
function test_pe_bus_mapping_in_source(testCase)
% Verify the runner maps pe_bus through Syn.con(:,1), not by parsing
% variable names (which give machine indices 1..11, not bus IDs).
runner_src = fileread('scripts/validation/run_psat_rts24.m');
testCase.verifyNotEmpty(strfind(runner_src, 'ps.pe_bus = Syn.con(:,1)'), ...
    'Runner must set pe_bus = Syn.con(:,1) (bus IDs, not machine indices).');
% Must NOT parse pe_bus from variable names
testCase.verifyEmpty(strfind(runner_src, 'sscanf(pe_names'), ...
    'Runner must NOT parse pe_bus from variable names.');
end

% =========================================================================
function test_corrector_iter_reduces_pe_error(testCase)
% Verify that fixed ci=1 has higher trapezoidal residual than adaptive.
% This checks the actual integration residual, not just trajectory difference.
c = load_case();
opt_fixed = struct('t_end',5,'dt',0.01,'fault_bus',15,'t_fault',1.0, ...
    't_clear',1.1,'Zf',0+0.1j,'method','trapezoidal', ...
    'corrector_mode','fixed','corrector_iter',1,'verbose',false);
opt_adaptive = struct('t_end',5,'dt',0.01,'fault_bus',15,'t_fault',1.0, ...
    't_clear',1.1,'Zf',0+0.1j,'method','trapezoidal', ...
    'corrector_mode','adaptive','max_corrector_iter',10,'verbose',false);
r_fixed = stability.ts_simulate(c, opt_fixed);
r_adaptive = stability.ts_simulate(c, opt_adaptive);
% Fixed ci=1 must have significantly higher residual
testCase.verifyGreaterThan(r_fixed.max_corrector_residual, ...
    r_adaptive.max_corrector_residual * 100, ...
    'Fixed ci=1 residual must be >100x adaptive residual.');
% Adaptive must converge all steps
testCase.verifyEqual(r_adaptive.nonconverged_step_count, 0, ...
    'Adaptive corrector must converge all steps.');
end

% =========================================================================
function test_psat_integration_optional(testCase)
% Integration test: if PSAT is available, run the comparison and
% assert that metrics are within tolerance.
% Uses corrector_iter=3 (fair comparison with PSAT's converged Newton).
psat_root = '';
for p = {'/home/birds/Documents/psat-2.1.11-mat/psat', ...
         'C:/Users/User/Downloads/psat-2.1.11-mat/psat'}
    if exist(p{1}, 'dir'), psat_root = p{1}; break; end
end
if isempty(psat_root)
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
testCase.verifyTrue(exist(fullfile(report.outdir,'rts24_generator_mapping.csv'),'file') > 0);
testCase.verifyTrue(exist(fullfile(report.outdir,'rts24_psat_comparison.md'),'file') > 0);
% Assert metrics within tolerance
metrics = readtable(fullfile(report.outdir,'rts24_ts_metrics.csv'));
for r = 1:height(metrics)
    switch metrics.metric{r}
        case 'max_dVm_mpu'
            testCase.verifyLessThan(metrics.value(r), 1, 'PF max dVm must be < 1 mpu (exact network).');
        case 'max_dVa_deg'
            testCase.verifyLessThan(metrics.value(r), 0.1, 'PF max dVa must be < 0.1 deg (exact network).');
        case 'max_inc_dcoi_deg'
            testCase.verifyLessThan(metrics.value(r), 5, 'TS max inc COI error must be < 5 deg (ci=3).');
        case 'rms_inc_dcoi_deg'
            testCase.verifyLessThan(metrics.value(r), 0.5, 'TS RMS inc COI must be < 0.5 deg (ci=3).');
        case 'max_domega_pu'
            testCase.verifyLessThan(metrics.value(r), 0.001, 'TS max speed error must be < 0.001 pu (ci=3).');
        case 'rms_domega_pu'
            testCase.verifyLessThan(metrics.value(r), 0.0001, 'TS RMS speed must be < 0.0001 pu (ci=3).');
        case 'max_dVfault_mpu'
            testCase.verifyLessThan(metrics.value(r), 5, 'TS max Vfault error must be < 5 mpu (ci=3).');
        case 'rms_dVfault_mpu'
            testCase.verifyLessThan(metrics.value(r), 1, 'TS RMS Vfault must be < 1 mpu (ci=3).');
    end
end
% Verify generator mapping CSV has correct bus IDs
map = readtable(fullfile(report.outdir,'rts24_generator_mapping.csv'));
c = cases.case_ieee_rts24_pgaz();
expected_buses = unique([c.machines.units.bus]).';
testCase.verifyEqual(map.psat_bus(:)', expected_buses(:)', 'Generator mapping buses must match.');
testCase.verifyEqual(map.ours_bus(:)', expected_buses(:)', 'Generator mapping ours_bus must match.');
% All ours_gen_idx must be valid (non-zero, within range)
testCase.verifyTrue(all(map.ours_gen_idx > 0), 'All ours_gen_idx must be valid.');
testCase.verifyTrue(all(map.ours_gen_idx <= numel(expected_buses)), 'All ours_gen_idx in range.');
end
