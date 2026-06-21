function line_data = case_ieee5bus_line_data()
%CASE_IEEE5BUS_LINE_DATA Example 5-bus line data in generic n-bus format.
% Columns: [From To R X B_half]

line_data = [
    1 2 0.02 0.06 0.000;
    1 3 0.08 0.24 0.025;
    2 3 0.06 0.25 0.020;
    2 4 0.06 0.18 0.020;
    2 5 0.04 0.12 0.015;
    3 4 0.01 0.03 0.010;
    4 5 0.08 0.24 0.025
];
end
