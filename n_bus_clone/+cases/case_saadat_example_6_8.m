function case_data = case_saadat_example_6_8()
%CASE_SAADAT_EXAMPLE_6_8 Hadi Saadat Power System Analysis, Example 6.8.
%   Three-bus Gauss-Seidel benchmark with one PV generator bus on a 100-MVA
%   base. Reference: Power System Analysis, Hadi Saadat, Chapter 6,
%   Example 6.8, printed pages 216-219.

case_data = struct();
case_data.system_name = 'Saadat Example 6.8 - Three-Bus PV Load Flow';
case_data.reference = struct( ...
    'source', 'Power System Analysis, Hadi Saadat, Chapter 6, Example 6.8', ...
    'pdf_file', 'power system analysis - hadi saadat_320503100.pdf', ...
    'printed_pages', '216-219');
case_data.base_values = struct( ...
    'S_base_MVA', 100, ...
    'V_base_kV', 100, ...
    'frequency_Hz', 60);

% Columns: [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload]
case_data.bus_data = [
    1 1 1.05 0 0.0 0 0.0 0.0;
    2 3 1.00 0 0.0 0 4.0 2.5;
    3 2 1.04 0 2.0 0 0.0 0.0
];

% Columns: [From To R X B_half]
case_data.line_data = [
    1 2 0.0200 0.040 0;
    1 3 0.0100 0.030 0;
    2 3 0.0125 0.025 0
];

case_data.reference_solution = struct( ...
    'bus_voltage', [1.05; 0.97168; 1.04], ...
    'bus_angle_deg', [0; -2.6948; -0.4980], ...
    'slack_P_generation', 2.1842, ...
    'slack_Q_generation', 1.4085, ...
    'pv_Q_generation', 1.4617);
end
