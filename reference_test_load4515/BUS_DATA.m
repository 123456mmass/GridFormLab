function bus_data = BUS_DATA()

% Reference IEEE 5-bus dataset used for cross-checking against
% published Newton-Raphson examples found online.
%
% Format:
% [Bus_no, Type, V_mag, V_angle, P_gen, Q_gen, P_load, Q_load]
%
% Bus type:
%   1 = Slack
%   2 = PV
%   3 = PQ

bus_data = [
    % Bus  Type  |V|   angle   Pgen   Qgen   Pload   Qload
    1     1      1.06  0       0      0      0.00    0.00;
    2     2      1.00  0       0.40   0      0.20    0.10;
    3     3      1.00  0       0      0      0.45    0.15;
    4     3      1.00  0       0      0      0.40    0.05;
    5     3      1.00  0       0      0      0.60    0.10
];

end
