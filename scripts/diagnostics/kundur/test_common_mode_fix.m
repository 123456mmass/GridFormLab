%% test_common_mode_fix.m — Test how to fix common mode (reference modes)
clear; clc;
addpath(genpath('.'));

fprintf('=== Testing common mode fix ===\n\n');

% Test 1: Vary D_load with D_machine = 0
fprintf('Test 1: Vary D_load (D_machine = 0)\n');
fprintf('%8s | %12s | %12s\n', 'D_load', 'ref mode 1', 'ref mode 2');
fprintf('---------|--------------|-------------\n');
for D_load = [0, 0.5, 1.0, 2.0, 5.0, 10.0]
    ssa = stability.kundur_ex126_kundur_ssa('options', struct('load_model','cc_p_cz_q','D_load',D_load));
    lam = ssa.eigenvalues;
    % Find 3 eigenvalues closest to 0
    [~, idx] = sort(abs(real(lam)));
    ref1 = lam(idx(1));
    ref2 = lam(idx(2));
    ref3 = lam(idx(3));
    fprintf('%8.1f | %8.4f%+7.4fj | %8.4f%+7.4fj\n', ...
        D_load, real(ref1), imag(ref1), real(ref2), imag(ref2));
end

fprintf('\nTest 2: Vary D_machine with D_load = 0\n');
fprintf('%8s | %12s | %12s\n', 'D_mach', 'ref mode 1', 'ref mode 2');
fprintf('---------|--------------|-------------\n');
c = cases.case_kundur_two_area_classical();
M = c.machines;
for D_val = [0, 0.5, 1.0, 2.0, 5.0, 10.0]
    for k=1:numel(M.units), M.units(k).D = D_val; end
    ssa = stability.kundur_ex126_kundur_ssa('options', struct('machine_override',M,'load_model','cc_p_cz_q','D_load',0));
    lam = ssa.eigenvalues;
    [~, idx] = sort(abs(real(lam)));
    ref1 = lam(idx(1));
    ref2 = lam(idx(2));
    fprintf('%8.1f | %8.4f%+7.4fj | %8.4f%+7.4fj\n', ...
        D_val, real(ref1), imag(ref1), real(ref2), imag(ref2));
end

fprintf('\nTest 3: Combine D_machine and D_load\n');
fprintf('%8s %8s | %12s | %12s\n', 'D_mach', 'D_load', 'ref mode 1', 'ref mode 2');
fprintf('---------|--------------|-------------\n');
for D_val = [0, 1.0, 2.0]
    for D_load = [0, 1.0, 2.0, 5.0]
        c = cases.case_kundur_two_area_classical();
        M = c.machines;
        for k=1:numel(M.units), M.units(k).D = D_val; end
        ssa = stability.kundur_ex126_kundur_ssa('options', struct('machine_override',M,'load_model','cc_p_cz_q','D_load',D_load));
        lam = ssa.eigenvalues;
        [~, idx] = sort(abs(real(lam)));
        ref1 = lam(idx(1));
        ref2 = lam(idx(2));
        fprintf('%8.1f %8.1f | %8.4f%+7.4fj | %8.4f%+7.4fj\n', ...
            D_val, D_load, real(ref1), imag(ref1), real(ref2), imag(ref2));
    end
end

fprintf('\n=== Conclusion ===\n');
fprintf('Kundur reference modes: -0.0008 +/- j0.0022\n');
fprintf('Need to find D_machine + D_load that makes reference modes near -0.0008 +/- j0.0022\n');
