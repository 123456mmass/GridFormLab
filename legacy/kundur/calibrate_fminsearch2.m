%% calibrate_fminsearch2.m — Calibrate with more parameters
clear; clc;
addpath(genpath('.'));

fprintf('=== Calibrating with fminsearch (extended) ===\n\n');

% Kundur targets (key modes)
rotor_targets = [-0.492+6.82i, -0.492-6.82i, -0.506+7.02i, -0.506-7.02i];
damper_targets = [-0.111+3.43i, -0.111-3.43i];
field_targets = [-0.265, -0.276];
damper_real_targets = [-3.428, -4.139, -5.287, -5.303];
subtrans_targets = [-31.03, -32.45, -34.07, -35.53, -37.89+0.142i, -37.89-0.142i, -38.01+0.038i, -38.01-0.038i];

c = cases.case_kundur_two_area_classical();
M0 = c.machines;

% x = [D, Tpd0_s, Tpq0_s, Tppd0_s, Tppq0_s, Xl_s, Xd_s, Xdp_s, Xq_s, Xqp_s, Xpp_s, H12_s, H34_s]
x0 = [0.0, 0.88, 1.02, 0.98, 1.0, 0.97, 0.94, 1.09, 1.21, 1.35, 0.93, 0.95, 0.96];

opts = optimset('Display', 'iter', 'MaxIter', 5000, 'MaxFunEvals', 10000, 'TolX', 1e-12, 'TolFun', 1e-16);

x_opt = fminsearch(@(x) cost_function(x, M0, rotor_targets, damper_targets, field_targets, damper_real_targets, subtrans_targets), x0, opts);

fprintf('\n=== Calibrated parameters ===\n');
fprintf('D = %.6f\n', x_opt(1));
fprintf('Tpd0 scale = %.6f\n', x_opt(2));
fprintf('Tpq0 scale = %.6f\n', x_opt(3));
fprintf('Tppd0 scale = %.6f\n', x_opt(4));
fprintf('Tppq0 scale = %.6f\n', x_opt(5));
fprintf('Xl scale = %.6f\n', x_opt(6));
fprintf('Xd scale = %.6f\n', x_opt(7));
fprintf('Xdp scale = %.6f\n', x_opt(8));
fprintf('Xq scale = %.6f\n', x_opt(9));
fprintf('Xqp scale = %.6f\n', x_opt(10));
fprintf('Xpp scale = %.6f\n', x_opt(11));
fprintf('H12 scale = %.6f\n', x_opt(12));
fprintf('H34 scale = %.6f\n', x_opt(13));

% Final eigenvalues
M = M0;
M.time_constants.Tpd0  = M.time_constants.Tpd0  * x_opt(2);
M.time_constants.Tpq0  = M.time_constants.Tpq0  * x_opt(3);
M.time_constants.Tppd0 = M.time_constants.Tppd0 * x_opt(4);
M.time_constants.Tppq0 = M.time_constants.Tppq0 * x_opt(5);
M.reactances.Xl  = M.reactances.Xl  * x_opt(6);
M.reactances.Xd  = M.reactances.Xd  * x_opt(7);
M.reactances.Xdp = M.reactances.Xdp * x_opt(8);
M.reactances.Xq  = M.reactances.Xq  * x_opt(9);
M.reactances.Xqp = M.reactances.Xqp * x_opt(10);
M.reactances.Xdpp = M.reactances.Xdpp * x_opt(11);
M.reactances.Xqpp = M.reactances.Xqpp * x_opt(11);
M.units(1).H = M.units(1).H * x_opt(12);
M.units(2).H = M.units(2).H * x_opt(12);
M.units(3).H = M.units(3).H * x_opt(13);
M.units(4).H = M.units(4).H * x_opt(13);
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

fprintf('\n=== Full eigenvalue comparison (sorted by real desc) ===\n');
fprintf('   # | OURS                   | err%%\n');
[~, idx] = sort(real(lam), 'descend');
for i = 1:24
    fprintf('%3d | %8.4f %+8.4fj | %6.2f%%\n', ...
        i, real(lam(idx(i))), imag(lam(idx(i))), errs(idx(i)));
end
fprintf('\nMAX error = %.4f%%\n', max(errs));

function cost = cost_function(x, M, rotor_t, damper_t, field_t, damper_real_t, subtrans_t)
    if any(x < 0); cost = 1e6; return; end
    if x(6) < 0.15; cost = 1e6; return; end  % Xl must be > 0.15
    if abs(x(4) - 1.0) > 0.02; cost = 1e6; return; end  % Tppd0 ~ 1.0
    if abs(x(5) - 1.0) > 0.02; cost = 1e6; return; end  % Tppq0 ~ 1.0
    M.time_constants.Tpd0  = M.time_constants.Tpd0  * x(2);
    M.time_constants.Tpq0  = M.time_constants.Tpq0  * x(3);
    M.time_constants.Tppd0 = M.time_constants.Tppd0 * x(4);
    M.time_constants.Tppq0 = M.time_constants.Tppq0 * x(5);
    M.reactances.Xl  = M.reactances.Xl  * x(6);
    M.reactances.Xd  = M.reactances.Xd  * x(7);
    M.reactances.Xdp = M.reactances.Xdp * x(8);
    M.reactances.Xq  = M.reactances.Xq  * x(9);
    M.reactances.Xqp = M.reactances.Xqp * x(10);
    M.reactances.Xdpp = M.reactances.Xdpp * x(11);
    M.reactances.Xqpp = M.reactances.Xqpp * x(11);
    M.units(1).H = M.units(1).H * x(12);
    M.units(2).H = M.units(2).H * x(12);
    M.units(3).H = M.units(3).H * x(13);
    M.units(4).H = M.units(4).H * x(13);
    for k=1:numel(M.units), M.units(k).D = x(1); end
    ssa = stability.kundur_ex126_kundur_ssa('options', struct('machine_override',M,'load_model','cz'));
    lam = ssa.eigenvalues;
    
    cost = 0;
    w_rotor = 100;  % high weight
    w_damper = 50;
    w_field = 30;
    w_damper_real = 20;
    w_subtrans = 10;
    
    for i = 1:numel(rotor_t)
        dists = abs(lam - rotor_t(i));
        [~, mi] = min(dists);
        cost = cost + w_rotor * (abs(lam(mi) - rotor_t(i)) / abs(rotor_t(i)))^2;
    end
    for i = 1:numel(damper_t)
        dists = abs(lam - damper_t(i));
        [~, mi] = min(dists);
        cost = cost + w_damper * (abs(lam(mi) - damper_t(i)) / abs(damper_t(i)))^2;
    end
    for i = 1:numel(field_t)
        dists = abs(lam - field_t(i));
        [~, mi] = min(dists);
        cost = cost + w_field * (abs(lam(mi) - field_t(i)) / abs(field_t(i)))^2;
    end
    for i = 1:numel(damper_real_t)
        dists = abs(lam - damper_real_t(i));
        [~, mi] = min(dists);
        cost = cost + w_damper_real * (abs(lam(mi) - damper_real_t(i)) / abs(damper_real_t(i)))^2;
    end
    for i = 1:numel(subtrans_t)
        dists = abs(lam - subtrans_t(i));
        [~, mi] = min(dists);
        cost = cost + w_subtrans * (abs(lam(mi) - subtrans_t(i)) / abs(subtrans_t(i)))^2;
    end
end
