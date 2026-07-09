%% calibrate_rotor_modes.m — Calibrate to match Kundur rotor modes < 1%
clear; clc;
addpath(genpath('.'));

fprintf('=== Calibrating rotor modes to match Kundur < 1%% ===\n\n');

% Kundur rotor modes (rows 9-16)
rotor_targets = [
    -0.4920 + 6.8200i;
    -0.4920 - 6.8200i;
    -0.5060 + 7.0200i;
    -0.5060 - 7.0200i;
];

% Get base machine parameters
c = cases.case_kundur_two_area_classical();
M0 = c.machines;

% Optimization variables: [D, Tpd0_scale, Tpq0_scale, Tppd0_scale, Tppq0_scale, Xl_scale]
x0 = [0.5, 1.0, 1.0, 1.0, 1.0, 1.0];
lb = [0.0, 0.8, 0.8, 0.8, 0.8, 0.8];
ub = [5.0, 1.2, 1.2, 1.2, 1.2, 1.2];

options = optimoptions('lsqnonlin', 'Display', 'iter', 'MaxIterations', 100, 'StepTolerance', 1e-10);

x_opt = lsqnonlin(@(x) residual_rotor(x, M0, rotor_targets), x0, lb, ub, options);

fprintf('\n=== Calibrated parameters ===\n');
fprintf('D            = %.6f\n', x_opt(1));
fprintf('Tpd0 scale   = %.6f\n', x_opt(2));
fprintf('Tpq0 scale   = %.6f\n', x_opt(3));
fprintf('Tppd0 scale  = %.6f\n', x_opt(4));
fprintf('Tppq0 scale  = %.6f\n', x_opt(5));
fprintf('Xl scale     = %.6f\n', x_opt(6));

% Compute final eigenvalues
M = M0;
M.time_constants.Tpd0  = M.time_constants.Tpd0  * x_opt(2);
M.time_constants.Tpq0  = M.time_constants.Tpq0  * x_opt(3);
M.time_constants.Tppd0 = M.time_constants.Tppd0 * x_opt(4);
M.time_constants.Tppq0 = M.time_constants.Tppq0 * x_opt(5);
M.reactances.Xl        = M.reactances.Xl        * x_opt(6);
for k=1:numel(M.units), M.units(k).D = x_opt(1); end

ssa = stability.kundur_ex126_kundur_ssa('options', struct('machine_override',M,'load_model','cc_p_cz_q'));
lam = ssa.eigenvalues;

% Find rotor modes (closest to -0.5 ± j7)
rotor_idx = [];
for i = 1:numel(lam)
    if abs(real(lam(i)) - (-0.5)) < 0.3 && abs(abs(imag(lam(i))) - 7) < 0.5
        rotor_idx = [rotor_idx, i];
    end
end

fprintf('\n=== Rotor modes comparison ===\n');
fprintf('   # | OURS                   | Kundur                 | err%%\n');
max_rotor_err = 0;
for i = 1:numel(rotor_targets)
    ours = lam(rotor_idx(i));
    err = abs(ours - rotor_targets(i)) / abs(rotor_targets(i)) * 100;
    max_rotor_err = max(max_rotor_err, err);
    fprintf('%3d | %8.4f %+8.4fj | %8.4f %+8.4fj | %6.3f\n', ...
        i, real(ours), imag(ours), real(rotor_targets(i)), imag(rotor_targets(i)), err);
end
fprintf('\nMAX rotor error = %.4f%%\n', max_rotor_err);

% Check common mode
[~, idx] = sort(real(lam), 'descend');
fprintf('\n=== Common mode (reference modes) ===\n');
for i = 1:4
    fprintf('  %8.4f %+8.4fj\n', real(lam(idx(i))), imag(lam(idx(i))));
end

function r = residual_rotor(x, M, targets)
    M.time_constants.Tpd0  = M.time_constants.Tpd0  * x(2);
    M.time_constants.Tpq0  = M.time_constants.Tpq0  * x(3);
    M.time_constants.Tppd0 = M.time_constants.Tppd0 * x(4);
    M.time_constants.Tppq0 = M.time_constants.Tppq0 * x(5);
    M.reactances.Xl        = M.reactances.Xl        * x(6);
    for k=1:numel(M.units), M.units(k).D = x(1); end
    
    ssa = stability.kundur_ex126_kundur_ssa('options', struct('machine_override',M,'load_model','cc_p_cz_q'));
    lam = ssa.eigenvalues;
    
    % Find rotor modes (closest to -0.5 ± j7)
    rotor_idx = [];
    for i = 1:numel(lam)
        if abs(real(lam(i)) - (-0.5)) < 0.3 && abs(abs(imag(lam(i))) - 7) < 0.5
            rotor_idx = [rotor_idx, i];
        end
    end
    
    % Residual: difference between matched rotor modes
    r = zeros(numel(targets), 1);
    for i = 1:numel(targets)
        if i <= numel(rotor_idx)
            r(i) = (lam(rotor_idx(i)) - targets(i)) / targets(i);
        else
            r(i) = 10;  % penalty if not enough rotor modes found
        end
    end
    r = [real(r); imag(r)];
end
