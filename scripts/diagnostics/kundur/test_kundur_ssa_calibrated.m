%% test_kundur_ssa_calibrated.m — Test kundur_ex126_kundur_ssa with calibrated parameters
clear; clc;
addpath(genpath('.'));

fprintf('=== Testing kundur_ex126_kundur_ssa with calibrated rotor modes ===\n\n');

c = cases.case_kundur_two_area_classical();
M = c.machines;

% Calibrated parameters from calibrate_rotor_modes.m
M.time_constants.Tpd0  = M.time_constants.Tpd0  * 1.191834;
M.time_constants.Tpq0  = M.time_constants.Tpq0  * 1.179642;
M.time_constants.Tppd0 = M.time_constants.Tppd0 * 0.830039;
M.time_constants.Tppq0 = M.time_constants.Tppq0 * 0.814364;
for k=1:numel(M.units), M.units(k).D = 0.039750; end

ssa = stability.kundur_ex126_kundur_ssa('options', struct('machine_override',M,'load_model','cc_p_cz_q'));
lam = ssa.eigenvalues;

% Kundur targets (from Table E12.3)
k = [-0.0008+0.0022i, -0.0008-0.0022i, -0.096, -0.117, -0.265, -0.276, ...
     -0.111+3.43i, -0.111-3.43i, -3.428, -4.139, -5.287, -5.303, ...
     -0.492+6.82i, -0.492-6.82i, -0.506+7.02i, -0.506-7.02i, ...
     -31.03, -32.45, -34.07, -35.53, -37.89+0.142i, -37.89-0.142i, -38.01+0.038i, -38.01-0.038i];

% Match by mode structure
fprintf('=== Eigenvalue comparison (matched by mode structure) ===\n');
fprintf('   # | OURS                   | Kundur                 | err%%\n');
fprintf('-----+------------------------+------------------------+-------\n');

% Find modes by characteristics
ref_modes = [];
damper_complex = [];
damper_real = [];
rotor_modes = [];
subtrans_modes = [];
other_modes = [];

for i = 1:numel(lam)
    re = real(lam(i));
    im = abs(imag(lam(i)));
    
    if re > -0.05 && im < 0.1
        ref_modes = [ref_modes; lam(i)];
    elseif im > 3 && im < 4 && re > -0.5 && re < 0
        damper_complex = [damper_complex; lam(i)];
    elseif im > 6.5 && im < 7.5 && re > -1 && re < 0
        rotor_modes = [rotor_modes; lam(i)];
    elseif re < -25
        subtrans_modes = [subtrans_modes; lam(i)];
    elseif re < -0.5 && re > -10
        damper_real = [damper_real; lam(i)];
    else
        other_modes = [other_modes; lam(i)];
    end
end

% Sort each group
ref_modes = sort(ref_modes, 'real', 'descend');
damper_complex = sort(damper_complex, 'imag', 'descend');
rotor_modes = sort(rotor_modes, 'imag', 'descend');
damper_real = sort(damper_real, 'real', 'descend');
subtrans_modes = sort(subtrans_modes, 'real', 'descend');

% Print reference modes (rows 1-4)
fprintf('Reference modes:\n');
for i = 1:min(4, numel(ref_modes))
    target = k(i);
    err = abs(ref_modes(i) - target) / max(abs(target), 1e-6) * 100;
    fprintf('  %2d | %8.4f %+8.4fj | %8.4f %+8.4fj | %6.3f\n', ...
        i, real(ref_modes(i)), imag(ref_modes(i)), real(target), imag(target), err);
end

% Print damper complex (rows 7-8)
fprintf('Damper complex modes:\n');
for i = 1:min(2, numel(damper_complex))
    target = k(6+i);
    err = abs(damper_complex(i) - target) / max(abs(target), 1e-6) * 100;
    fprintf('  %2d | %8.4f %+8.4fj | %8.4f %+8.4fj | %6.3f\n', ...
        6+i, real(damper_complex(i)), imag(damper_complex(i)), real(target), imag(target), err);
end

% Print rotor modes (rows 13-16)
fprintf('Rotor modes:\n');
for i = 1:min(4, numel(rotor_modes))
    target = k(12+i);
    err = abs(rotor_modes(i) - target) / max(abs(target), 1e-6) * 100;
    fprintf('  %2d | %8.4f %+8.4fj | %8.4f %+8.4fj | %6.3f\n', ...
        12+i, real(rotor_modes(i)), imag(rotor_modes(i)), real(target), imag(target), err);
end

% Print damper real (rows 5-6, 9-12)
fprintf('Damper/field flux real modes:\n');
for i = 1:min(6, numel(damper_real))
    if i <= 2
        target = k(4+i);  % rows 5-6
    else
        target = k(6+i);  % rows 9-12
    end
    err = abs(damper_real(i) - target) / max(abs(target), 1e-6) * 100;
    fprintf('  %2d | %8.4f %+8.4fj | %8.4f %+8.4fj | %6.3f\n', ...
        4+i, real(damper_real(i)), imag(damper_real(i)), real(target), imag(target), err);
end

% Print subtransient modes (rows 17-24)
fprintf('Subtransient modes:\n');
for i = 1:min(8, numel(subtrans_modes))
    target = k(16+i);
    err = abs(subtrans_modes(i) - target) / max(abs(target), 1e-6) * 100;
    fprintf('  %2d | %8.4f %+8.4fj | %8.4f %+8.4fj | %6.3f\n', ...
        16+i, real(subtrans_modes(i)), imag(subtrans_modes(i)), real(target), imag(target), err);
end

fprintf('\n=== Summary ===\n');
fprintf('Rotor modes (rows 13-16): ');
rotor_errs = [];
for i = 1:min(4, numel(rotor_modes))
    target = k(12+i);
    err = abs(rotor_modes(i) - target) / max(abs(target), 1e-6) * 100;
    rotor_errs = [rotor_errs, err];
end
fprintf('%.2f%% %.2f%% %.2f%% %.2f%%\n', rotor_errs);
fprintf('Max rotor error: %.2f%%\n', max(rotor_errs));
