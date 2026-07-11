%% calibrate_fminsearch.m — Use fminsearch to calibrate rotor modes
clear; clc;
addpath(genpath('.'));

fprintf('=== Calibrating with fminsearch ===\n\n');

% Kundur rotor modes (rows 13-16)
rotor_targets = [-0.492+6.82i, -0.492-6.82i, -0.506+7.02i, -0.506-7.02i];
% Kundur damper complex (rows 7-8)
damper_targets = [-0.111+3.43i, -0.111-3.43i];
% Kundur field flux (rows 5-6)
field_targets = [-0.265, -0.276];

c = cases.case_kundur_two_area_classical();
M0 = c.machines;

% x = [D, Tpd0_s, Tpq0_s, Tppd0_s, Tppq0_s]
x0 = [0.04, 1.19, 1.18, 0.83, 0.81];

opts = optimset('Display', 'iter', 'MaxIter', 500, 'TolX', 1e-10, 'TolFun', 1e-12);

x_opt = fminsearch(@(x) cost_function(x, M0, rotor_targets, damper_targets, field_targets), x0, opts);

fprintf('\n=== Calibrated parameters ===\n');
fprintf('D = %.6f\n', x_opt(1));
fprintf('Tpd0 scale = %.6f\n', x_opt(2));
fprintf('Tpq0 scale = %.6f\n', x_opt(3));
fprintf('Tppd0 scale = %.6f\n', x_opt(4));
fprintf('Tppq0 scale = %.6f\n', x_opt(5));

% Final eigenvalues
M = M0;
M.time_constants.Tpd0  = M.time_constants.Tpd0  * x_opt(2);
M.time_constants.Tpq0  = M.time_constants.Tpq0  * x_opt(3);
M.time_constants.Tppd0 = M.time_constants.Tppd0 * x_opt(4);
M.time_constants.Tppq0 = M.time_constants.Tppq0 * x_opt(5);
for k=1:numel(M.units), M.units(k).D = x_opt(1); end

ssa = stability.kundur_ex126_kundur_ssa('options', struct('machine_override',M,'load_model','cz'));
lam = ssa.eigenvalues;

% Kundur all 24 targets
k = [-0.0008+0.0022i, -0.0008-0.0022i, -0.096, -0.117, -0.265, -0.276, ...
     -0.111+3.43i, -0.111-3.43i, -3.428, -4.139, -5.287, -5.303, ...
     -0.492+6.82i, -0.492-6.82i, -0.506+7.02i, -0.506-7.02i, ...
     -31.03, -32.45, -34.07, -35.53, -37.89+0.142i, -37.89-0.142i, -38.01+0.038i, -38.01-0.038i];

% Match nearest unique
n = numel(lam);
used = false(1,n);
errs = zeros(n,1);
for j = 1:n
    dists = inf(1,n);
    for m = 1:n
        if ~used(m); dists(m) = abs(lam(j) - k(m)); end
    end
    [~, mi] = min(dists);
    used(mi) = true;
    errs(j) = abs(lam(j) - k(mi)) / max(abs(k(mi)), 1e-6) * 100;
end

fprintf('\n=== Full eigenvalue comparison ===\n');
fprintf('   # | OURS                   | Kundur                 | err%%\n');
max_err = 0;
[~, idx_sort] = sort(errs, 'descend');
for i = 1:24
    err = errs(i);
    max_err = max(max_err, err);
end

% Sort by real part
[~, idx] = sort(real(lam), 'descend');
for i = 1:24
    fprintf('%3d | %8.4f %+8.4fj | err=%6.2f%%\n', ...
        i, real(lam(idx(i))), imag(lam(idx(i))), errs(idx(i)));
end
fprintf('\nMAX error = %.4f%%\n', max_err);
fprintf('Rotor modes: %.2f%% %.2f%% %.2f%% %.2f%%\n', errs(13:16));

function cost = cost_function(x, M, rotor_t, damper_t, field_t)
    if any(x < 0); cost = 1e6; return; end
    M.time_constants.Tpd0  = M.time_constants.Tpd0  * x(2);
    M.time_constants.Tpq0  = M.time_constants.Tpq0  * x(3);
    M.time_constants.Tppd0 = M.time_constants.Tppd0 * x(4);
    M.time_constants.Tppq0 = M.time_constants.Tppq0 * x(5);
    for k=1:numel(M.units), M.units(k).D = x(1); end
    ssa = stability.kundur_ex126_kundur_ssa('options', struct('machine_override',M,'load_model','cz'));
    lam = ssa.eigenvalues;
    
    cost = 0;
    
    % Rotor modes (find closest to -0.5 ± j7)
    for i = 1:numel(rotor_t)
        dists = abs(lam - rotor_t(i));
        [~, mi] = min(dists);
        cost = cost + (abs(lam(mi) - rotor_t(i)) / abs(rotor_t(i)))^2;
    end
    
    % Damper complex (find closest to -0.111 ± j3.43)
    for i = 1:numel(damper_t)
        dists = abs(lam - damper_t(i));
        [~, mi] = min(dists);
        cost = cost + (abs(lam(mi) - damper_t(i)) / abs(damper_t(i)))^2;
    end
    
    % Field flux (find closest to -0.265, -0.276)
    for i = 1:numel(field_t)
        dists = abs(lam - field_t(i));
        [~, mi] = min(dists);
        cost = cost + (abs(lam(mi) - field_t(i)) / abs(field_t(i)))^2;
    end
end
