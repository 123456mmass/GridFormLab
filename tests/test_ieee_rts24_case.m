function tests = test_ieee_rts24_case()
%TEST_IEEE_RTS24_CASE Validate IEEE RTS 24-bus (RTS-1996) case.
%   Covers: case-format contract, PF convergence, generator aggregation /
%   base conversion, no-fault TS equilibrium, short-fault TS smoke test.

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
% Case-format contract: 12-col bus_data, 7-col line_data, mpc, tables, pgaz.
c = load_case();
testCase.verifySize(c.bus_data, [24 12], 'bus_data must be 24x12.');
testCase.verifySize(c.line_data, [38 7], 'line_data must be 38x7.');
testCase.verifyEqual(c.base_values.S_base_MVA, 100);
testCase.verifyEqual(c.base_values.frequency_Hz, 60);
testCase.verifyEqual(c.schema_version, 'power_case/1.0');
testCase.verifyTrue(isfield(c,'mpc'), 'mpc must exist.');
testCase.verifyTrue(isfield(c,'tables'), 'tables must exist.');
testCase.verifyTrue(isfield(c,'pgaz'), 'pgaz source matrices must exist.');
testCase.verifyEqual(numel(c.pgaz.ABus_con), 24*6, 'ABus must have 24x6 entries.');
testCase.verifyEqual(size(c.pgaz.ALine_con,1), 38, 'ALine must have 38 rows.');
% Slack bus is bus 13 (type 1).
slack_idx = find(c.bus_data(:,2)==1);
testCase.verifyEqual(c.bus_data(slack_idx,1), 13, 'Slack bus must be 13.');
% Bus 6 shunt: Bs=-100 Mvar inductive -> Bsh=-1.0 pu on 100 MVA.
b6 = find(c.bus_data(:,1)==6);
testCase.verifyEqual(c.bus_data(b6,10), -1.0, 'AbsTol', 1e-12, ...
    'Bus 6 shunt Bs=-100Mvar -> Bsh=-1.0 pu.');
end

% =========================================================================
function test_pgaz_column_mapping_documented(testCase)
% Every PGAz matrix must have a documented column_map entry.
c = load_case();
cm = c.pgaz.column_map;
required = {'ABus','ALine','Slack','PV','PQ','AShunt','Gen'};
pgaz_fields = fieldnames(c.pgaz);
for k = 1:numel(required)
    f = required{k};
    testCase.verifyTrue(isfield(cm,f), sprintf('column_map missing %s',f));
    % Cross-check column count against the actual matrix.
    mat_name = [f '_con'];
    testCase.verifyTrue(isfield(c.pgaz, mat_name), ...
        sprintf('pgaz.%s missing', mat_name));
    mat = c.pgaz.(mat_name);
    testCase.verifyEqual(numel(cm.(f)), size(mat,2), ...
        sprintf('%s column_map count mismatch', f));
end
% Spot-check critical mappings (cm.<matrix> is a direct cell array).
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
% Voltage limits: allow margin for PV buses near limits.
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
Qshunt = sum(-V.^2 .* c.bus_data(:,10));   % absorbed by bus shunts
% P: gen - load - shunt_G - line_loss ~= 0
Pbal = r.P_total_gen - r.P_total_load - sum(V.^2.*c.bus_data(:,9)) - r.P_loss_total;
% Q: gen - load - shunt_absorbed - line_loss ~= 0
Qbal = r.Q_total_gen - r.Q_total_load - Qshunt - r.Q_loss_total;
testCase.verifyLessThan(abs(Pbal), 1e-6, 'Active power balance residual.');
testCase.verifyLessThan(abs(Qbal), 1e-6, 'Reactive power balance residual.');
end

% =========================================================================
function test_generator_aggregation_and_base_conversion(testCase)
% Each gen bus must aggregate all machines at that bus; H and X'd must be
% converted to the 100 MVA system base.
c = load_case();
u = c.machines.units;
% Bus 1: 2xU20 + 2xU76.
%   H_table: U20 H=2.8@24MVA, U76 H=3.0@89MVA.
%   H_sys per unit = H_table * Sunit/Ssys.
%   U20: 2.8 * 24/100 = 0.672 (x2 units)
%   U76: 3.0 * 89/100 = 2.67  (x2 units)
%   Bus-1 aggregate H = 2*0.672 + 2*2.67 = 6.684
b1 = [u([u.bus]==1).H];
testCase.verifyEqual(sum(b1), 6.684, 'AbsTol', 1e-6, ...
    'Bus 1 aggregate H must be 6.684.');
% X'd for U76: 0.30 * 100/89 = 0.3371 on system base.
b1x = [u([u.bus]==1).Xdp];
testCase.verifyEqual(b1x(3), 0.30*100/89, 'AbsTol', 1e-6, ...
    'U76 X''d on system base.');
% X'd for U20: 0.32 * 100/24 = 1.3333.
testCase.verifyEqual(b1x(1), 0.32*100/24, 'AbsTol', 1e-6, ...
    'U20 X''d on system base.');
% Bus 14 is a synchronous condenser modelled as U197 with Pmax=0.
sc = u([u.bus]==14);
testCase.verifyEqual(numel(sc), 1);
testCase.verifyTrue(sc(1).is_sync_condenser, 'Bus 14 must be sync condenser.');
testCase.verifyEqual(sc(1).group, 'U197');
% Total online (non-condenser-excluded) units including the condenser.
testCase.verifyEqual(numel(u), 33, '33 generator rows total.');
end

% =========================================================================
function test_aline_charging_is_total(testCase)
% PGAz ALine col 9 is TOTAL charging; B_half in line_data = col9/2.
c = load_case();
% Take a line with non-zero charging, e.g. line 1-2 (B_total=0.4611).
r1 = find(c.line_data(:,1)==1 & c.line_data(:,2)==2);
testCase.verifyEqual(c.line_data(r1,5), c.pgaz.ALine_con(r1,9)/2, ...
    'AbsTol', 1e-12, 'B_half must be half of PGAz total charging.');
% Transformer lines (tap!=1) must have B_half=0 (RTS has no charging on xfmrs).
r_tr = find(c.pgaz.ALine_con(:,10)~=1);
for k = r_tr.'
    testCase.verifyEqual(c.pgaz.ALine_con(k,9), 0, ...
        sprintf('Transformer line %d-%d must have zero charging.', ...
            c.pgaz.ALine_con(k,1), c.pgaz.ALine_con(k,2)));
end
end

% =========================================================================
function test_no_fault_ts_equilibrium(testCase)
% No-fault simulation: delta and omega must not drift.
c = load_case();
opt = struct('t_end',5,'dt',0.01,'fault_bus',15, ...
    't_fault',999,'t_clear',999.1,'Zf',1i*0.1, ...
    'method','trapezoidal','corrector_iter',1, ...
    'verbose',false,'model','classical','plot_results',false);
r = stability.ts_simulate(c,opt);
dd = r.delta - r.delta(1,:);
testCase.verifyLessThan(max(abs(rad2deg(dd)),[],'all'), 1e-6, ...
    'No-fault: rotor angles must not drift.');
testCase.verifyLessThan(max(abs(r.omega-1),[],'all'), 1e-9, ...
    'No-fault: speeds must stay at 1.0.');
end

% =========================================================================
function test_short_fault_ts_smoke(testCase)
% Short fault: system must remain stable (bounded angles, V recovers).
c = load_case();
opt = struct('t_end',10,'dt',0.01,'fault_bus',15, ...
    't_fault',1.0,'t_clear',1.1,'Zf',1i*0.1, ...
    'method','trapezoidal','corrector_iter',1, ...
    'verbose',false,'model','classical','plot_results',false);
r = stability.ts_simulate(c,opt);
% Stable: relative angles bounded (< 180 deg), speed deviation bounded.
dd = r.delta - r.delta(1,:);
testCase.verifyLessThan(max(abs(rad2deg(dd)),[],'all'), 360, ...
    'Short-fault: relative angles must remain bounded (< 360 deg).');
testCase.verifyLessThan(max(abs(r.omega-1),[],'all'), 0.01, ...
    'Short-fault: speed deviation must remain small (< 0.01 pu).');
% Voltage recovers after fault clearing.
t_post = find(r.t >= 1.2);
testCase.verifyGreaterThan(min(r.Vbus(t_post,:),[],'all'), 0.9, ...
    'Voltage must recover above 0.9 pu after fault clearing.');
% Aggregated H for bus 1 must be correct (not the single-unit value).
testCase.verifyEqual(r.H(1), 6.684, 'AbsTol', 1e-6, ...
    'Bus 1 aggregated H must be 6.684.');
end

% =========================================================================
function test_dynamic_assumptions_documented(testCase)
% Dynamic data must NOT be claimed as PGAz file values.
c = load_case();
da = c.dynamic_assumptions;
testCase.verifyTrue(isfield(da,'source'));
testCase.verifyTrue(contains(da.source, 'IEEE RTS-1996'));
testCase.verifyTrue(isfield(da,'note'));
testCase.verifyTrue(numel(da.note) >= 3, ...
    'Assumptions must be documented with multiple notes.');
testCase.verifyTrue(contains(da.model, 'classical'));
% H must NOT be the PGAz placeholder value 5 for all units.
u = c.machines.units;
Hvals = [u.H];
testCase.verifyFalse(all(abs(Hvals-5) < 0.01) || all(abs(Hvals-5*0.24)<0.01), ...
    'H must not be the PGAz placeholder default for all units.');
end
