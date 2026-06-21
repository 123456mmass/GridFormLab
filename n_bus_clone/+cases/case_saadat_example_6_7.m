function case_data = case_saadat_example_6_7()
%CASE_SAADAT_EXAMPLE_6_7 Hadi Saadat Power System Analysis, Example 6.7.
%   Three-bus Gauss-Seidel benchmark on a 100-MVA base.
%   Reference: Power System Analysis, Hadi Saadat, Chapter 6, Example 6.7,
%   printed pages 212-216.

case_data = struct();
case_data.system_name = 'Saadat Example 6.7 - Three-Bus PQ Load Flow';
case_data.reference = struct( ...
    'source', 'Power System Analysis, Hadi Saadat, Chapter 6, Example 6.7', ...
    'pdf_file', 'power system analysis - hadi saadat_320503100.pdf', ...
    'printed_pages', '212-216');
case_data.base_values = struct( ...
    'S_base_MVA', 100, ...
    'V_base_kV', 100, ...
    'frequency_Hz', 60);

% Columns: [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload]
case_data.bus_data = [
    1 1 1.05 0 0 0 0.000 0.000;
    2 3 1.00 0 0 0 2.566 1.102;
    3 3 1.00 0 0 0 1.386 0.452
];

% Columns: [From To R X B_half]
case_data.line_data = [
    1 2 0.0200 0.040 0;
    1 3 0.0100 0.030 0;
    2 3 0.0125 0.025 0
];

case_data.reference_solution = struct( ...
    'bus_voltage', [1.05; 0.98183; 1.00125], ...
    'bus_angle_deg', [0; -3.5035; -2.8624], ...
    'slack_P_generation', 4.095, ...
    'slack_Q_generation', 1.890);
end
