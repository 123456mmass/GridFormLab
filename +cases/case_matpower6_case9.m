function case_data = case_matpower6_case9()
%CASE_MATPOWER6_CASE9 WSCC 3-machine 9-bus test case (MATPOWER6 case9).
%   Self-contained loader: embeds the MATPOWER6 case9.m data and converts it
%   to the project case format via the shared cases.mpc_to_case converter.
%   This demonstrates that adding a new case in +cases/ lets the general
%   engine stability.ts_simulate run it with no engine changes.

mpc = struct();
mpc.version = '2';
mpc.baseMVA = 100;
mpc.bus = [
    1  3   0    0   0   0   1   1.0   0   345   1   1.1   0.9;
    2  2   0    0   0   0   1   1.0   0   345   1   1.1   0.9;
    3  2   0    0   0   0   1   1.0   0   345   1   1.1   0.9;
    4  1   0    0   0   0   1   1.0   0   345   1   1.1   0.9;
    5  1  90   30   0   0   1   1.0   0   345   1   1.1   0.9;
    6  1   0    0   0   0   1   1.0   0   345   1   1.1   0.9;
    7  1 100   35   0   0   1   1.0   0   345   1   1.1   0.9;
    8  1   0    0   0   0   1   1.0   0   345   1   1.1   0.9;
    9  1 125   50   0   0   1   1.0   0   345   1   1.1   0.9;
];
mpc.gen = [
    1   0   0   300  -300   1.0   100   1   250   10;
    2 163   0   300  -300   1.0   100   1   300   10;
    3  85   0   300  -300   1.0   100   1   270   10;
];
mpc.branch = [
    1 4 0      0.0576  0      250 250 250 0 0 1;
    4 5 0.017  0.092   0.158  250 250 250 0 0 1;
    5 6 0.039  0.17    0.358  150 150 150 0 0 1;
    3 6 0      0.0586  0      300 300 300 0 0 1;
    6 7 0.0119 0.1008  0.209  150 150 150 0 0 1;
    7 8 0.0085 0.072   0.149  250 250 250 0 0 1;
    8 2 0      0.0625  0      250 250 250 0 0 1;
    8 9 0.032  0.161   0.306  250 250 250 0 0 1;
    9 4 0.01   0.085   0.176  250 250 250 0 0 1;
];
mpc.gencost = [];
mpc.bus_name = {};

case_data = cases.mpc_to_case(mpc, 'system_name', 'MATPOWER6 WSCC 9-bus (case9)');
end
