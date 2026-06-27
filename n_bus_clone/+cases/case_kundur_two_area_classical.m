function case_data = case_kundur_two_area_classical()
%CASE_KUNDUR_TWO_AREA_CLASSICAL Kundur Example 12.6 two-area system.
%   Power-flow data for the 11-bus, 4-machine, two-area benchmark from
%   Kundur, Power System Stability and Control, Chapter 12, Example 12.6.
%   The dynamic study associated with this case is the manual-excitation
%   (classical) small-signal stability table E12.3.
%
%   Bus data columns:
%     [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload Gsh Bsh]
%   Line data columns:
%     [From To R X B_half]
%
%   Base: 100 MVA, 230 kV network. Generator terminal voltages, MW/MVAr,
%   loads, shunt capacitors, line lengths, and line constants follow the
%   printed Example 12.6 values.

case_data = struct();
case_data.system_name = 'Kundur Two-Area 4-Machine Classical System (Example 12.6)';
case_data.base_values = struct( ...
    'S_base_MVA', 100, ...
    'V_base_kV', 230, ...
    'frequency_Hz', 60);

% Bus types: 1=slack, 2=PV, 3=PQ. G1 is the angular reference.
% P/Q values are per unit on 100 MVA base. Shunt capacitors are represented
% as positive Bsh injection at buses 7 and 9.
case_data.bus_data = [ ...
    1   1   1.03   20.2    7.00   1.85   0       0       0   0; ...
    2   2   1.01   10.5    7.00   2.35   0       0       0   0; ...
    3   2   1.03   -6.8    7.19   1.76   0       0       0   0; ...
    4   2   1.01   -17.0   7.00   2.02   0       0       0   0; ...
    5   3   1.00   0       0      0      0       0       0   0; ...
    6   3   1.00   0       0      0      0       0       0   0; ...
    7   3   1.00   0       0      0      9.67    1.00    0   2.00; ...
    8   3   1.00   0       0      0      0       0       0   0; ...
    9   3   1.00   0       0      0      17.67   1.00    0   3.50; ...
    10  3   1.00   0       0      0      0       0       0   0; ...
    11  3   1.00   0       0      0      0       0       0   0];

% Network branches. Transformer reactance: j0.15 pu on 900 MVA base,
% converted to 100 MVA base = 0.15*(100/900) = 0.0166667 pu.
xt = 0.15 * (100/900);

% Line constants on 100 MVA, 230 kV base, per km.
r_per_km = 0.0001;
x_per_km = 0.0010;
b_per_km = 0.00175;
line = @(from, to, km) [from, to, r_per_km*km, x_per_km*km, b_per_km*km/2];

case_data.line_data = [ ...
    1   5   0       xt      0; ...
    2   6   0       xt      0; ...
    3   11  0       xt      0; ...
    4   10  0       xt      0; ...
    line(5, 6, 25); ...
    line(6, 7, 10); ...
    line(7, 8, 110); ...
    line(7, 8, 110); ... % double-circuit tie section
    line(8, 9, 110); ...
    line(8, 9, 110); ... % double-circuit tie section
    line(9, 10, 10); ...
    line(10, 11, 25)];

case_data.reference = struct( ...
    'source', 'Kundur, Power System Stability and Control, Chapter 12, Example 12.6', ...
    'book_table', 'Table E12.3 - System modes with manual excitation control');

% ---------------------------------------------------------------------
% Synchronous-machine dynamic data (6th-order subtransient model).
% Parameters per unit on the machine base (900 MVA, 20 kV, 60 Hz), taken
% from Kundur Example 12.6 / Table E12.2 and confirmed against the public
% test-case repositories (colib.net, CloudPSS, fglongatt.org).
%
% State vector per machine (manual/constant excitation, E_fd held fixed):
%   x_i = [ delta_i; omega_i; E'_qi; E'_di; E''_qi; E''_di ]
%
% Reactances:
%   Xd=1.8  X'd=0.3  X''d=0.25  Xq=1.7  X'q=0.55  X''q=0.25  Xl=0.2
% Time constants (s):
%   T'd0=8.0  T''d0=0.03  T'q0=0.4  T''q0=0.05
% Inertia / damping:
%   H1=H2=6.5 s, H3=H4=6.175 s, D=0 (manual excitation).
% Stator resistance: Ra = 0.0025 pu.
machine_base = struct('S_MVA', 900, 'V_kV', 20, 'f_Hz', 60);
machine_reactances = struct( ...
    'Xd', 1.8, 'Xdp', 0.3, 'Xdpp', 0.25, ...
    'Xq', 1.7, 'Xqp', 0.55, 'Xqpp', 0.25, ...
    'Xl', 0.2, 'Ra', 0.0025);
machine_time_constants = struct( ...
    'Tpd0', 8.0, 'Tppd0', 0.03, 'Tpq0', 0.4, 'Tppq0', 0.05);
case_data.machines = struct();
case_data.machines.base = machine_base;
case_data.machines.reactances = machine_reactances;
case_data.machines.time_constants = machine_time_constants;
% Per-generator inertia/damping. G1 and G2 (Area 1) have H = 6.5 s; G3 and
% G4 (Area 2) have H = 6.175 s. Damping D is zero for the manual-excitation
% (classical) benchmark, matching Kundur Table E12.3.
case_data.machines.units = struct();
case_data.machines.units(1).gen_id = 'G1';
case_data.machines.units(1).bus = 1;
case_data.machines.units(1).H = 6.5;
case_data.machines.units(1).D = 0;
case_data.machines.units(2).gen_id = 'G2';
case_data.machines.units(2).bus = 2;
case_data.machines.units(2).H = 6.5;
case_data.machines.units(2).D = 0;
case_data.machines.units(3).gen_id = 'G3';
case_data.machines.units(3).bus = 3;
case_data.machines.units(3).H = 6.175;
case_data.machines.units(3).D = 0;
case_data.machines.units(4).gen_id = 'G4';
case_data.machines.units(4).bus = 4;
case_data.machines.units(4).H = 6.175;
case_data.machines.units(4).D = 0;
end
