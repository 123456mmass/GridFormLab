%% calibrate_kundur_e123_nearest.m — Calibrate to match Kundur Table E12.3 using nearest+unique matching
% Goal: find parameters that make our eigenvalues match Kundur E12.3 within <0.5%
% Uses nearest+unique matching instead of sorted matching

clear; clc;
addpath(genpath('.'));

%% Kundur Table E12.3 target eigenvalues (from scanned book)
% Sorted by real part descending (as in book)
kundur_targets = [
    -0.0008 + 0.0022i;  % Row 1 (reference mode)
    -0.0008 - 0.0022i;  % Row 2 (reference mode)
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
    -32.4500 + 0.0000i; % Row 18 (subtransient)
    -34.0700 + 0.0000i; % Row 19 (subtransient)
    -35.5300 + 0.0000i; % Row 20 (subtransient)
    -37.8900 + 0.1420i; % Row 21 (subtransient)
    -37.8900 - 0.1420i; % Row 22 (subtransient)
    -38.0100 + 0.0380i; % Row 23 (subtransient)
    -38.0100 - 0.0380i; % Row 24 (subtransient)
];

%% Get base machine parameters
c = cases.case_kundur_two_area_classical();
M0 = c.machines;

%% Optimization variables: [D, Tpd0_scale, Tpq0_scale, Tppd0_scale, Tppq0_scale, Xl_scale]
% Start from base values
x0 = [0.5, 1.0, 1.0, 1.0, 1.0, 1.0];

% Bounds: allow wide range
lb = [0.0, 0.5, 0.5, 0.5, 0.5, 0.5];
ub = [10.0, 2.0, 2.0, 2.0, 2.0, 2.0];

%% Objective: sum of squared distances to nearest target
options = optimoptions('lsqnonlin', 'Display', 'iter', 'MaxIterations', 200, 'StepTolerance', 1e-12);

x_opt = lsqnonlin(@(x) residual_nearest(x, M0, kundur_targets), x0, lb, ub, options);

%% Print results
fprintf('\n=== Calibrated parameters (nearest+unique matching) ===\n');
fprintf('D            = %.6f\n', x_opt(1));
fprintf('Tpd0 scale   = %.6f\n', x_opt(2));
fprintf('Tpq0 scale   = %.6f\n', x_opt(3));
fprintf('Tppd0 scale  = %.6f\n', x_opt(4));
fprintf('Tppq0 scale  = %.6f\n', x_opt(5));
fprintf('Xl scale     = %.6f\n', x_opt(6));

%% Compute final eigenvalues with matched pairs
M = M0;
M.time_constants.Tpd0  = M.time_constants.Tpd0  * x_opt(2);
M.time_constants.Tpq0  = M.time_constants.Tpq0  * x_opt(3);
M.time_constants.Tppd0 = M.time_constants.Tppd0 * x_opt(4);
M.time_constants.Tppq0 = M.time_constants.Tppq0 * x_opt(5);
M.reactances.Xl        = M.reactances.Xl        * x_opt(6);
for k=1:numel(M.units), M.units(k).D = x_opt(1); end

ssa = stability.kundur_ex126_kundur_ssa('options', struct('machine_override',M,'load_model','cc_p_cz_q'));
lam_ours = ssa.eigenvalues;

% Match each of our eigenvalues to nearest unused target
[ours_matched, kundur_matched, perm] = match_nearest_unique(lam_ours, kundur_targets);

fprintf('\n=== Final eigenvalue comparison (nearest+unique matching) ===\n');
fprintf('   # | OURS                   | Kundur                 | err%%\n');
max_err = 0;
for i = 1:numel(ours_matched)
    err = abs(ours_matched(i) - kundur_matched(i)) / max(abs(kundur_matched(i)), 1e-6) * 100;
    max_err = max(max_err, err);
    fprintf('%3d | %8.4f %+8.4fj | %8.4f %+8.4fj | %6.3f\n', ...
        i, real(ours_matched(i)), imag(ours_matched(i)), ...
        real(kundur_matched(i)), imag(kundur_matched(i)), err);
end
fprintf('\nMAX error = %.4f%%\n', max_err);

%% Functions
function r = residual_nearest(x, M, targets)
    M.time_constants.Tpd0  = M.time_constants.Tpd0  * x(2);
    M.time_constants.Tpq0  = M.time_constants.Tpq0  * x(3);
    M.time_constants.Tppd0 = M.time_constants.Tppd0 * x(4);
    M.time_constants.Tppq0 = M.time_constants.Tppq0 * x(5);
    M.reactances.Xl        = M.reactances.Xl        * x(6);
    for k=1:numel(M.units), M.units(k).D = x(1); end
    ssa = stability.kundur_ex126_kundur_ssa('options', struct('machine_override',M,'load_model','cc_p_cz_q'));
    lam = ssa.eigenvalues;
    
    % Match each of our eigenvalues to nearest unused target
    [~, targets_matched, ~] = match_nearest_unique(lam, targets);
    
    % Residual: difference between matched pairs
    r = zeros(numel(targets), 1);
    for i = 1:numel(targets)
        r(i) = (lam(i) - targets_matched(i)) / max(abs(targets_matched(i)), 1e-6);
    end
    r = [real(r); imag(r)];
end

function [ours_matched, targets_matched, perm] = match_nearest_unique(ours, targets)
    % For each of our eigenvalues, find nearest unused target
    n = numel(ours);
    used = false(1, n);
    ours_matched = zeros(n, 1);
    targets_matched = zeros(n, 1);
    perm = zeros(n, 1);
    
    for i = 1:n
        % Find nearest unused target
        dists = inf(1, n);
        for j = 1:n
            if ~used(j)
                dists(j) = abs(ours(i) - targets(j));
            end
        end
        [~, jmin] = min(dists);
        used(jmin) = true;
        ours_matched(i) = ours(i);
        targets_matched(i) = targets(jmin);
        perm(i) = jmin;
    end
end
