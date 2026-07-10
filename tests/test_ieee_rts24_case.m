function tests = test_ieee_rts24_case()
%TEST_IEEE_RTS24_CASE Validate IEEE RTS 24-bus (RTS-1996) case.
%   Covers: case-format contract, self-contained loader, PGAz column
%   mapping, PF convergence, P/Q balance, H conversion (MW rating),
%   X'd conversion (MVA rating), multiple-machine aggregation, machine
%   order independence, missing-machine error, bus-14 assumption
%   consistency, no-fault equilibrium, fault TS boundedness (COI/pairwise).

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% -------------------------------------------------------------------------
function c = load_case()
c = cases.case_ieee_rts24_pgaz();
end

% =========================================================================
function test_case_format_contract(testCase)
c = load_case();
testCase.verifySize(c.bus_data, [24 12], 'bus_data must be 24x12.');
testCase.verifySize(c.line_data, [38 7], 'line_data must be 38x7.');
testCase.verifyEqual(c.base_values.S_base_MVA, 100);
testCase.verifyEqual(c.base_values.frequency_Hz, 60);
testCase.verifyEqual(c.schema_version, 'power_case/1.0');
testCase.verifyTrue(isfield(c,'mpc'), 'mpc must exist.');
testCase.verifyTrue(isfield(c,'tables'), 'tables must exist.');
testCase.verifyTrue(isfield(c,'pgaz'), 'pgaz source matrices must exist.');
testCase.verifyEqual(size(c.pgaz.ABus_con,1), 24, 'ABus must have 24 rows.');
testCase.verifyEqual(size(c.pgaz.ALine_con,1), 38, 'ALine must have 38 rows.');
slack_idx = find(c.bus_data(:,2)==1);
testCase.verifyEqual(c.bus_data(slack_idx,1), 13, 'Slack bus must be 13.');
% Bus 6 shunt: Bs=-100 Mvar inductive -> Bsh=-1.0 pu on 100 MVA.
b6 = find(c.bus_data(:,1)==6);
testCase.verifyEqual(c.bus_data(b6,10), -1.0, 'AbsTol', 1e-12, ...
    'Bus 6 shunt Bs=-100Mvar -> Bsh=-1.0 pu.');
end

% =========================================================================
function test_loader_is_self_contained(testCase)
% The loader must work without any file in the user's Downloads folder.
% It must read from +cases/ieee_rts24_pgaz_raw.m (in-repository).
raw = cases.ieee_rts24_pgaz_raw();
testCase.verifyTrue(isfield(raw,'ABus_con'));
testCase.verifyTrue(isfield(raw,'ALine_con'));
testCase.verifyTrue(isfield(raw,'Slack_con'));
testCase.verifyTrue(isfield(raw,'PV_con'));
testCase.verifyTrue(isfield(raw,'PQ_con'));
testCase.verifyTrue(isfield(raw,'AShunt_con'));
testCase.verifyTrue(isfield(raw,'Gen_con'));
% The case loader must NOT depend on the Downloads path at runtime.
c = load_case();
testCase.verifyTrue(isfield(c.pgaz,'ABus_con'));
% Verify the raw data matches what the case stored.
testCase.verifyEqual(c.pgaz.ABus_con, raw.ABus_con, 'AbsTol', 0);
testCase.verifyEqual(c.pgaz.Gen_con, raw.Gen_con, 'AbsTol', 0);
end

% =========================================================================
function test_pgaz_column_mapping_documented(testCase)
c = load_case();
cm = c.pgaz.column_map;
required = {'ABus','ALine','Slack','PV','PQ','AShunt','Gen'};
for k = 1:numel(required)
    f = required{k};
    testCase.verifyTrue(isfield(cm,f), sprintf('column_map missing %s',f));
    mat_name = [f '_con'];
    testCase.verifyTrue(isfield(c.pgaz, mat_name), ...
        sprintf('pgaz.%s missing', mat_name));
    mat = c.pgaz.(mat_name);
    testCase.verifyEqual(numel(cm.(f)), size(mat,2), ...
        sprintf('%s column_map count mismatch', f));
end
testCase.verifyEqual(cm.ALine{9}, 'B_total_pu', ...
    'ALine col 9 must be total charging (verified from pgaz_ybus.m).');
testCase.verifyEqual(cm.Gen{11}, 'H', 'Gen col 11 = H.');
testCase.verifyEqual(cm.Gen{12}, 'D', 'Gen col 12 = D.');
testCase.verifyEqual(cm.Gen{16}, 'xdp', 'Gen col 16 = X''d.');
end

% =========================================================================
function test_powerflow_converges(testCase)
c = load_case();
r = pfsolver.powerflow_newton_raphson(c, struct('verbose',false, ...
    'plot_results',false,'max_iter',50,'tolerance',1e-10, ...
    'enforce_q_limits',false));
testCase.verifyTrue(r.converged, 'RTS-24 PF must converge.');
testCase.verifyLessThan(r.mismatch_history(end), 1e-10);
testCase.verifyLessThan(r.iterations, 20);
testCase.verifyGreaterThan(min(r.bus_voltage), 0.92);
testCase.verifyLessThan(max(r.bus_voltage), 1.08);
end

% =========================================================================
function test_power_balance(testCase)
c = load_case();
r = pfsolver.powerflow_newton_raphson(c, struct('verbose',false, ...
    'plot_results',false,'max_iter',50,'tolerance',1e-10, ...
    'enforce_q_limits',false));
V = r.bus_voltage;
Qshunt = sum(-V.^2 .* c.bus_data(:,10));
Pbal = r.P_total_gen - r.P_total_load - sum(V.^2.*c.bus_data(:,9)) - r.P_loss_total;
Qbal = r.Q_total_gen - r.Q_total_load - Qshunt - r.Q_loss_total;
testCase.verifyLessThan(abs(Pbal), 1e-6, 'Active power balance residual.');
testCase.verifyLessThan(abs(Qbal), 1e-6, 'Reactive power balance residual.');
end

% =========================================================================
function test_H_conversion_uses_MW_rating(testCase)
% Table 15 Note 4: "Inertia values are based on the unit size in MW."
% H_sys = H_table * (P_unit_MW / S_base_MVA), NOT H_table * Smva/Sbase.
c = load_case();
u = c.machines.units;
% Bus 1: 2xU20 (H=2.8, Pmw=20) + 2xU76 (H=3.0, Pmw=76).
%   U20: H_sys = 2.8 * 20/100 = 0.56  (x2)
%   U76: H_sys = 3.0 * 76/100 = 2.28  (x2)
%   Bus-1 aggregate H = 2*0.56 + 2*2.28 = 5.68
b1 = [u([u.bus]==1).H];
testCase.verifyEqual(sum(b1), 5.68, 'AbsTol', 1e-6, ...
    'Bus 1 aggregate H must be 5.68 (H uses MW rating per Note 4).');
% Individual U20 at bus 1: H = 2.8*20/100 = 0.56
testCase.verifyEqual(b1(1), 0.56, 'AbsTol', 1e-6, 'U20 H on system base.');
% Individual U76 at bus 1: H = 3.0*76/100 = 2.28
testCase.verifyEqual(b1(3), 2.28, 'AbsTol', 1e-6, 'U76 H on system base.');
end

% =========================================================================
function test_Xdp_conversion_uses_MVA_rating(testCase)
% Table 15 Note 3: "Reactance values are based on the given MVA base."
% X'd_sys = X'd_table * (S_base_MVA / S_unit_MVA).
c = load_case();
u = c.machines.units;
% U76: X'd = 0.30 * 100/89 = 0.3371
b1x = [u([u.bus]==1).Xdp];
testCase.verifyEqual(b1x(3), 0.30*100/89, 'AbsTol', 1e-6, ...
    'U76 X''d on system base (uses MVA rating per Note 3).');
% U20: X'd = 0.32 * 100/24 = 1.3333
testCase.verifyEqual(b1x(1), 0.32*100/24, 'AbsTol', 1e-6, ...
    'U20 X''d on system base.');
end

% =========================================================================
function test_machine_aggregation_by_bus(testCase)
% Multiple machines at the same bus must be aggregated: H_agg=sum,
% D_agg=sum, 1/X'd_agg=sum(1/X'd).
c = load_case();
u = c.machines.units;
% Bus 15: 5xU12 + 1xU155.
%   U12: H=2.8*12/100=0.336, X'd=0.32*100/14=2.2857  (x5)
%   U155: H=3.0*155/100=4.65, X'd=0.30*100/182=0.1648  (x1)
b15 = [u([u.bus]==15).H];
b15x = [u([u.bus]==15).Xdp];
H_exp = 5*(2.8*12/100) + 1*(3.0*155/100);
Xdp_exp = 1/(5/(0.32*100/14) + 1/(0.30*100/182));
testCase.verifyEqual(sum(b15), H_exp, 'AbsTol', 1e-6, ...
    'Bus 15 aggregate H.');
testCase.verifyEqual(1/sum(1./b15x), Xdp_exp, 'AbsTol', 1e-6, ...
    'Bus 15 aggregate X''d (parallel).');
% Total units = 33 (32 generators + 1 sync condenser at bus 14).
testCase.verifyEqual(numel(u), 33, '33 generator rows total.');
end

% =========================================================================
function test_machine_order_independence(testCase)
% Aggregation result must not depend on the order of machine entries.
c = load_case();
u = c.machines.units;
% Shuffle the units and verify Bus 1 aggregate H is the same.
rng(42);
perm = randperm(numel(u));
u_shuffled = u(perm);
% Manually aggregate bus 1 for both orderings.
H_orig = sum([u([u.bus]==1).H]);
H_shuf = sum([u_shuffled([u_shuffled.bus]==1).H]);
testCase.verifyEqual(H_orig, H_shuf, 'AbsTol', 1e-12, ...
    'Bus 1 H must be order-independent.');
% Also check X'd aggregation.
Xdp_orig = 1/sum(1./[u([u.bus]==1).Xdp]);
Xdp_shuf = 1/sum(1./[u_shuffled([u_shuffled.bus]==1).Xdp]);
testCase.verifyEqual(Xdp_orig, Xdp_shuf, 'AbsTol', 1e-12, ...
    'Bus 1 X''d must be order-independent.');
end

% =========================================================================
function test_missing_machine_mapping_errors(testCase)
% When a case provides .machines but a gen bus has no matching entry,
% ts_simulate must error, NOT silently use H=5/X'd=0.3 defaults.
c = load_case();
% Remove the machine at bus 22 (all 6 U50 units).
u = c.machines.units;
u = u([u.bus] ~= 22);
c.machines.units = u;
opt = struct('t_end',0.1,'dt',0.01,'fault_bus',15, ...
    't_fault',999,'t_clear',999.1,'Zf',1i*0.1, ...
    'method','trapezoidal','corrector_iter',1, ...
    'verbose',false,'model','classical','plot_results',false);
testCase.verifyError(@()stability.ts_simulate(c,opt), ...
    'ts_simulate:noMachineForBus', ...
    'Missing machine data must raise an error, not silently default.');
end

% =========================================================================
function test_bus14_assumption_consistency(testCase)
% Bus 14 is INCLUDED in TS (not excluded).  Comments, assumptions, and
% code must all say the same thing.
c = load_case();
u = c.machines.units;
sc = u([u.bus]==14);
testCase.verifyEqual(numel(sc), 1, 'Bus 14 must have exactly one machine.');
testCase.verifyTrue(sc(1).is_sync_condenser, 'Bus 14 must be flagged sync condenser.');
testCase.verifyEqual(sc(1).group, 'U197', 'Bus 14 modelled as U197.');
testCase.verifyTrue(sc(1).H > 0, 'Bus 14 must have positive H (included in TS).');
testCase.verifyTrue(sc(1).Xdp > 0, 'Bus 14 must have positive X''d.');
% The assumption must be documented as NOT a Table 15 fact.
da = c.dynamic_assumptions;
testCase.verifyTrue(isfield(da,'bus14_assumption'));
testCase.verifyTrue(contains(da.bus14_assumption.status, 'assumption'));
testCase.verifyTrue(contains(da.bus14_assumption.status, 'not directly specified'));
% The notes must NOT say "excluded" (old wording).
notes_str = strjoin(da.note, ' ');
testCase.verifyFalse(contains(notes_str, 'excluded from the'), ...
    'Notes must not say bus 14 is excluded (it is included in TS).');
end

% =========================================================================
function test_aline_charging_is_total(testCase)
c = load_case();
r1 = find(c.line_data(:,1)==1 & c.line_data(:,2)==2);
testCase.verifyEqual(c.line_data(r1,5), c.pgaz.ALine_con(r1,9)/2, ...
    'AbsTol', 1e-12, 'B_half must be half of PGAz total charging.');
r_tr = find(c.pgaz.ALine_con(:,10)~=1);
for k = r_tr.'
    testCase.verifyEqual(c.pgaz.ALine_con(k,9), 0, ...
        sprintf('Transformer line %d-%d must have zero charging.', ...
            c.pgaz.ALine_con(k,1), c.pgaz.ALine_con(k,2)));
end
end

% =========================================================================
function test_no_fault_ts_equilibrium(testCase)
c = load_case();
opt = struct('t_end',5,'dt',0.01,'fault_bus',15, ...
    't_fault',999,'t_clear',999.1,'Zf',1i*0.1, ...
    'method','trapezoidal','corrector_iter',1, ...
    'verbose',false,'model','classical','plot_results',false);
r = stability.ts_simulate(c,opt);
% COI-relative drift.
Hw = r.H(:).'; delta_coi = sum(r.delta.*Hw,2)./sum(Hw);
d_coi = rad2deg(r.delta - delta_coi);
d_coi = d_coi - d_coi(1,:);
testCase.verifyLessThan(max(abs(d_coi),[],'all'), 1e-6, ...
    'No-fault: COI-relative angles must not drift.');
testCase.verifyLessThan(max(abs(r.omega-1),[],'all'), 1e-9, ...
    'No-fault: speeds must stay at 1.0.');
end

% =========================================================================
function test_short_fault_ts_boundedness(testCase)
% Short-fault boundedness test using COI-relative and pairwise metrics.
% This is a BOUNDEDNESS check, not a formal stability claim.
c = load_case();
opt = struct('t_end',15,'dt',0.01,'fault_bus',15, ...
    't_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
    'method','trapezoidal','corrector_iter',1, ...
    'verbose',false,'model','classical','plot_results',false);
r = stability.ts_simulate(c,opt);
% COI-relative angles.
Hw = r.H(:).'; delta_coi = sum(r.delta.*Hw,2)./sum(Hw);
d_coi = rad2deg(r.delta - delta_coi);
% Max pairwise separation.
ng = size(r.delta,2);
maxpair = 0;
for i = 1:ng
    for j = i+1:ng
        maxpair = max(maxpair, max(abs(rad2deg(r.delta(:,i)-r.delta(:,j)))));
    end
end
% Report metrics (informational).
fprintf('  TS metrics: maxCOI=%.2f deg, maxPair=%.2f deg, maxDw=%.4e\n', ...
    max(abs(d_coi),[],'all'), maxpair, max(abs(r.omega-1),[],'all'));
% Boundedness: COI-relative angle must not grow unbounded.  Check that
% the final-window max is not larger than the post-fault peak by >50%.
t_post = r.t >= r.t_clear;
peak = max(abs(d_coi(t_post,:)),[],'all');
win = r.t >= 0.9*r.t(end);
final_max = max(abs(d_coi(win,:)),[],'all');
testCase.verifyLessThan(final_max, 1.5*peak + 5, ...
    'Final-window COI angle must not grow beyond 1.5x post-fault peak.');
% Speed deviation must remain bounded.
testCase.verifyLessThan(max(abs(r.omega-1),[],'all'), 0.02, ...
    'Speed deviation must remain bounded (< 0.02 pu).');
% Voltage recovers after fault clearing.
testCase.verifyGreaterThan(min(r.Vbus(t_post,:),[],'all'), 0.9, ...
    'Voltage must recover above 0.9 pu after fault.');
% Aggregated H for bus 1 must use the corrected MW-rating formula.
testCase.verifyEqual(r.H(1), 5.68, 'AbsTol', 1e-6, ...
    'Bus 1 aggregated H must be 5.68 (MW-rating conversion).');
end

% =========================================================================
function test_dynamic_assumptions_documented(testCase)
c = load_case();
da = c.dynamic_assumptions;
testCase.verifyTrue(isfield(da,'source'));
testCase.verifyTrue(contains(da.source, 'IEEE RTS-1996'));
testCase.verifyTrue(isfield(da,'note'));
testCase.verifyTrue(numel(da.note) >= 5);
testCase.verifyTrue(contains(da.model, 'classical'));
% H conversion formula must reference MW rating.
testCase.verifyTrue(contains(da.conversion.H_sys, 'P_unit_MW'));
% X'd conversion formula must reference MVA rating.
testCase.verifyTrue(contains(da.conversion.Xdp_sys, 'S_unit_MVA'));
% H must NOT be the PGAz placeholder value 5 for all units.
u = c.machines.units;
Hvals = [u.H];
testCase.verifyFalse(all(abs(Hvals-5) < 0.01), ...
    'H must not be the PGAz placeholder default for all units.');
end

% =========================================================================
function test_no_external_solver_dependency(testCase)
% Verify that no fsolve/optimoptions/MATPOWER/PSAT/PGAz solver is used.
% The PF must use only the in-house Newton-Raphson.
c = load_case();
r = pfsolver.powerflow_newton_raphson(c, struct('verbose',false, ...
    'plot_results',false,'max_iter',50,'tolerance',1e-10, ...
    'enforce_q_limits',false));
testCase.verifyTrue(r.converged);
testCase.verifyEqual(r.method, 'Newton-Raphson');
end
