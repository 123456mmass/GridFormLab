function line_data = LINE_DATA()

% Reference IEEE 5-bus line data for cross-checking.
% The script expects one-half total line charging susceptance in the last
% column, so values below are the per-end B/2 values.
%
% Format:
% [From_bus, To_bus, R, X, B_half]

line_data = [
    % From  To    R       X       B/2
    1      2     0.02    0.06    0.06;
    1      3     0.08    0.24    0.05;
    2      3     0.06    0.18    0.04;
    2      4     0.06    0.18    0.04;
    2      5     0.04    0.12    0.03;
    3      4     0.01    0.03    0.02;
    4      5     0.08    0.24    0.025
];

end
