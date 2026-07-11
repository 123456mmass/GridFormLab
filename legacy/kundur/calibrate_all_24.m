%% calibrate_all_24.m — Calibrate ALL 24 eigenvalues to match Kundur E12.3
% Uses cz load model (stable reference modes) + Canay formulation
clear; clc;
addpath(genpath('.'));

fprintf('=== Calibrating ALL 24 eigenvalues ===\n\n');

% Kundur Table E12.3 targets
kundur_targets = [
    -0.0008 + 0.0022i;  % Row 1 (reference)
    -0.0008 - 0.0022i;  % Row 2 (reference)
    -0.0960 + 0.0000i;  % Row 3
    -0.1170 + 0.0000i;  % Row 4
    -0.2650 + 0.0000i;  % Row 5 (field flux)
    -0.2760 + 0.0000i;  % Row 6 (field flux)
    -0.1110 + 3.4300i;  % Row 7 (damper)
    -0.1110 - 3.4300i;  % Row 8 (damper)
    -3.4280 + 0.0000i;  % Row 9 (damper)
    -4.1390 + 0.0000i;  % Row 10 (damper)
    -5.2870 + 0.0000i;  % Row 11
    -5.3030 + 0.0000i;  % Row 12
    -0.4920 + 6.8200i;  % Row 13 (rotor)
    -0.4920 - 6.8200i;  % Row 14 (rotor)
    -0.5060 + 7.0200i;  % Row 15 (rotor)
    -0.5060 - 7.0200i;  % Row 16 (rotor)
    -31.0300 + 0.0000i; % Row 17 (subtransient)
    -32.4500 + 0.0000i; % Row 18
    -34.0700 + 0.0000i; % Row 19
    -35.5300 + 0.0000i; % Row 20
    -37.8900 + 0.1420i; % Row 21
    -37.8900 - 0.1420i; % Row 22
    -38.0100 + 0.0380i; % Row 23
    -38.0100 - 0.0380i; % Row 24
];

c = cases.case_kundur_two_area_classical();
M0 = c.machines;

% Optimization variables: [D, Tpd0_s, Tpq0_s, Tppd0_s, Tppq0_s, Xl_s, Xd_s, Xdp_s, Xq_s, Xqp_s, Xpp_s]
x0 = [0.04, 1.19, 1.18, 0.83, 0.81, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0];
lb = [0.0,  0.5,  0.5,  0.5,  0.5,  0.5, 0.9, 0.9, 0.9, 0.9, 0.9];
ub = [2.0,  2.0,  2.0,  2.0,  2.0,  2.0, 1.1, 1.1, 1.1, 1.1, 1.1];

opts = optimoptions('lsqnonlin', 'Display', 'iter', 'MaxIterations', 300, ...
    'StepTolerance', 1e-12, 'FunctionTolerance', 1e-14);

x_opt = lsqnonlin(@(x) residual_all(x, M0, kundur_targets), x0, lb, ub, opts);

fprintf('\n=== Calibrated parameters ===\n');
fprintf('D = %.6f\n', x_opt(1));
fprintf('Tpd0 scale = %.6f\n', x_opt(2));
fprintf('Tpq0 scale = %.6f\n', x_opt(3));
fprintf('Tppd0 scale = %.6f\n', x_opt(4));
fprintf('Tppq0 scale = %.6f\n', x_opt(5));
fprintf('Xl scale = %.6f\n', x_opt(6));

% Compute final eigenvalues
M = M0;
M.time_constants.Tpd0  = M.time_constants.Tpd0  * x_opt(2);
M.time_constants.Tpq0  = M.time_constants.Tpq0  * x_opt(3);
M.time_constants.Tppd0 = M.time_constants.Tppd0 * x_opt(4);
M.time_constants.Tppq0 = M.time_constants.Tppq0 * x_opt(5);
M.reactances.Xl        = M.reactances.Xl        * x_opt(6);
for k=1:numel(M.units), M.units(k).D = x_opt(1); end

ssa = stability.kundur_ex126_kundur_ssa('options', struct('machine_override',M,'load_model','cz'));
lam = ssa.eigenvalues;

% Match nearest unique
[~, targets_matched, ~] = match_nearest_unique(lam, kundur_targets);

fprintf('\n=== Final comparison ===\n');
fprintf('   # | OURS                   | Kundur                 | err%%\n');
max_err = 0;
for i = 1:24
    err = abs(lam(i) - targets_matched(i)) / max(abs(targets_matched(i)), 1e-6) * 100;
    max_err = max(max_err, err);
    fprintf('%3d | %8.4f %+8.4fj | %8.4f %+8.4fj | %6.3f\n', ...
        i, real(lam(i)), imag(lam(i)), ...
        real(targets_matched(i)), imag(targets_matched(i)), err);
end
fprintf('\nMAX error = %.4f%%\n', max_err);

%% Functions
function r = residual_all(x, M, targets)
    M.time_constants.Tpd0  = M.time_constants.Tpd0  * x(2);
    M.time_constants.Tpq0  = M.time_constants.Tpq0  * x(3);
    M.time_constants.Tppd0 = M.time_constants.Tppd0 * x(4);
    M.time_constants.Tppq0 = M.time_constants.Tppq0 * x(5);
    M.reactances.Xl        = M.reactances.Xl        * x(6);
    for k=1:numel(M.units), M.units(k).D = x(1); end
    ssa = stability.kundur_ex126_kundur_ssa('options', struct('machine_override',M,'load_model','cz'));
    lam = ssa.eigenvalues;
    [~, targets_matched, ~] = match_nearest_unique(lam, targets);
    r = zeros(24, 1);
    for i = 1:24
        r(i) = (lam(i) - targets_matched(i)) / max(abs(targets_matched(i)), 1e-6);
    end
    r = [real(r); imag(r)];
end

function [ours_matched, targets_matched, perm] = match_nearest_unique(ours, targets)
    n = numel(ours);
    used = false(1, n);
    ours_matched = zeros(n, 1);
    targets_matched = zeros(n, 1);
    perm = zeros(n, 1);
    for i = 1:n
        dists = inf(1, n);
        for j = 1:n
            if ~used(j); dists(j) = abs(ours(i) - targets(j)); end
        end
        [~, jmin] = min(dists);
        used(jmin) = true;
        ours_matched(i) = ours(i);
        targets_matched(i) = targets(jmin);
        perm(i) = jmin;
    end
end
