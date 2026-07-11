%% test_dload_effect.m — Test if load frequency damping fixes common mode
clear; clc;
addpath(genpath('.'));

fprintf('=== Testing load frequency damping (D_load) effect on common mode ===\n\n');

D_load_values = [0, 0.5, 1.0, 2.0, 5.0, 10.0];

for i = 1:numel(D_load_values)
    D_load = D_load_values(i);
    ssa = stability.kundur_ex126_kundur_ssa('options', struct('load_model','cc_p_cz_q','D_load',D_load));
    lam = ssa.eigenvalues;
    
    % Find common mode (smallest |real|)
    [~, idx] = min(abs(real(lam)));
    common_mode = lam(idx);
    
    fprintf('D_load = %5.1f: common mode = %8.4f %+8.4fj\n', ...
        D_load, real(common_mode), imag(common_mode));
end

fprintf('\n=== Conclusion ===\n');
fprintf('If D_load > 0 makes common mode negative, load frequency damping helps.\n');
fprintf('If common mode stays positive, need to reformulate flux equations.\n');
