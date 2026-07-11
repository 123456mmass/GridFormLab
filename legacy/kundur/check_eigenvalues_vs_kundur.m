%% check_eigenvalues_vs_kundur.m — Check all eigenvalues vs Kundur E12.3
clear; clc;
addpath(genpath('.'));

fprintf('=== Checking eigenvalues vs Kundur Table E12.3 ===\n\n');

% Kundur Table E12.3 targets (from scanned book)
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

% Run with current model (cc_p_cz_q, D_load=0)
ssa = stability.kundur_ex126_kundur_ssa('options', struct('load_model','cc_p_cz_q','D_load',0));
lam_ours = ssa.eigenvalues;

% Sort both by real part descending
[~, idx_k] = sort(real(kundur_targets), 'descend');
kundur_sorted = kundur_targets(idx_k);
[~, idx_o] = sort(real(lam_ours), 'descend');
ours_sorted = lam_ours(idx_o);

fprintf('   # | OURS                   | Kundur                 | err%%\n');
fprintf('-----+------------------------+------------------------+-------\n');
max_err = 0;
for i = 1:24
    err = abs(ours_sorted(i) - kundur_sorted(i)) / max(abs(kundur_sorted(i)), 1e-6) * 100;
    max_err = max(max_err, err);
    fprintf('%3d | %8.4f %+8.4fj | %8.4f %+8.4fj | %6.3f\n', ...
        i, real(ours_sorted(i)), imag(ours_sorted(i)), ...
        real(kundur_sorted(i)), imag(kundur_sorted(i)), err);
end
fprintf('\nMAX error = %.4f%%\n', max_err);

% Check rotor modes specifically
fprintf('\n=== Rotor modes (rows 13-16) ===\n');
rotor_ours = ours_sorted(13:16);
rotor_kundur = kundur_sorted(13:16);
for i = 1:4
    err = abs(rotor_ours(i) - rotor_kundur(i)) / max(abs(rotor_kundur(i)), 1e-6) * 100;
    fprintf('Row %2d: ours=%8.4f%+8.4fj, kundur=%8.4f%+8.4fj, err=%.3f%%\n', ...
        12+i, real(rotor_ours(i)), imag(rotor_ours(i)), ...
        real(rotor_kundur(i)), imag(rotor_kundur(i)), err);
end
