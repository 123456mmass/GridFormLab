function bus_data = case_ieee5bus_bus_data()
%CASE_IEEE5BUS_BUS_DATA Example 5-bus bus data in generic n-bus format.
% Columns: [BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload]

bus_data = [
    1 1 1.06 0 0.00 0.00 0.00 0.00;
    2 2 1.00 0 0.40 0.00 0.20 0.10;
    3 3 1.00 0 0.00 0.00 0.45 0.15;
    4 3 1.00 0 0.00 0.00 0.40 0.05;
    5 3 1.00 0 0.00 0.00 0.60 0.10
];
end
