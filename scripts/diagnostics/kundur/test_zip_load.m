%% Test custom ZIP load models to find optimal damping
pf_init_paths();
case_data = cases.case_kundur_two_area_classical();

pf_opts = struct('plot_results', false, 'verbose', false, ...
    'max_iter', 50, 'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);

% Test different ZIP coefficients for P load
% ZIP: P = Z_p*(V/V0)^2 + I_p*(V/V0) + P_p
% We'll vary Z_p and I_p while keeping P_p = 0
% Q is always constant impedance (Z_q=1)

zip_tests = {
    % Z_p, I_p, name
    1.0, 0.0, 'Pure CZ';
    0.75, 0.25, '75%Z + 25%I';
    0.5, 0.5, '50%Z + 50%I';
    0.25, 0.75, '25%Z + 75%I';
    0.0, 1.0, 'Pure CC';
};

fprintf('=== Custom ZIP Load Model Tests ===\n');
fprintf('%-20s %-25s %-10s %-10s %-10s\n', 'Load Model', 'Interarea Mode', 'Freq (Hz)', 'Zeta', 'Zeta Error');
fprintf('%-20s %-25s %-10s %-10s %-10s\n', '----------', '--------------', '---------', '----', '----------');

for i = 1:size(zip_tests, 1)
    Z_p = zip_tests{i, 1};
    I_p = zip_tests{i, 2};
    name = zip_tests{i, 3};
    
    % We need to modify the SSA function to support custom ZIP
    % For now, let's just test the existing models and interpolate
    
    if Z_p == 1.0 && I_p == 0.0
        load_model = 'cz_p_cz_q';
    elseif Z_p == 0.0 && I_p == 1.0
        load_model = 'cc_p_cz_q';
    else
        % Skip custom ZIP for now - need to modify SSA function
        fprintf('%-20s (Custom ZIP not yet supported)\n', name);
        continue;
    end
    
    opts = struct('load_model', load_model, 'use_saturation', false);
    
    try
        result = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);
        
        eig_all = result.eigenvalues;
        interarea = [];
        
        for j = 1:numel(eig_all)
            lam = eig_all(j);
            freq = abs(imag(lam)) / (2*pi);
            if freq > 0.4 && freq < 0.7 && imag(lam) > 0 && isempty(interarea)
                interarea = lam;
                break;
            end
        end
        
        if ~isempty(interarea)
            freq = abs(imag(interarea)) / (2*pi);
            zeta = -real(interarea) / abs(interarea);
            zeta_err = abs(zeta - 0.032) / 0.032 * 100;
            fprintf('%-20s %9.4f %+9.4fi   %8.4f    %8.4f    %6.1f%%\n', ...
                name, real(interarea), imag(interarea), freq, zeta, zeta_err);
        end
    catch ME
        fprintf('%-20s Error: %s\n', name, ME.message);
    end
end

fprintf('\nKundur Reference: -0.111 + 3.43i  (f=0.545 Hz, zeta=0.032)\n');
fprintf('\nObservation: Need load model between CZ and CC to match Kundur damping.\n');
fprintf('This requires modifying the SSA function to support custom ZIP coefficients.\n');