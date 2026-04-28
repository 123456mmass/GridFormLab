function case_data = case_template_nbus()
%CASE_TEMPLATE_NBUS Template for creating a new n-bus system case.
% Copy this file, rename it, and replace the sample data below.

case_data = struct();
case_data.system_name = 'My N-Bus System';
case_data.base_values = struct( ...
    'S_base_MVA', 100, ...
    'V_base_kV', 230, ...
    'frequency_Hz', 50);

% bus_data columns:
% [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload]
% Optional:
% [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload Gsh Bsh]
% [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload Gsh Bsh Qmin Qmax]
% Type: 1 = Slack, 2 = PV, 3 = PQ
case_data.bus_data = [
    101 1 1.05 0 0.00 0.00 0.00 0.00;
    205 2 1.01 0 0.50 0.00 0.20 0.10;
    309 3 1.00 0 0.00 0.00 0.40 0.15
];

% line_data columns:
% [From To R X] or [From To R X B_half]
case_data.line_data = [
    101 205 0.02 0.06 0.03;
    205 309 0.05 0.20 0.02;
    101 309 0.08 0.24 0.01
];
end
