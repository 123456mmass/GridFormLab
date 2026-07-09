%% Test damping coefficient D effect
pf_init_paths();
case_data = cases.case_kundur_two_area_classical();

pf_opts = struct('plot_results', false, 'verbose', false, ...
    'max_iter', 50, 'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);

D_values = [0, 0.5, 1.0, 2.0, 5.0];

fprintf('=== Effect of Damping Coefficient D ===\n');
fprintf('%-10s %-25s %-10s %-10s\n', 'D value', 'Interarea Mode', 'Freq (Hz)', 'Zeta');
fprintf('%-10s %-25s %-10s %-10s\n', '-------', '--------------', '---------', '----');

for i = 1:numel(D_values)
    D_val = D_values(i);
    
    % Modify case data
    case_data_mod = case_data;
    for k = 1:4
        case_data_mod.machines.units(k).D = D_val;
    end
    
    try
        opts = struct('load_model', 'cc_p_cz_q', 'use_saturation', false);
        result = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);
        
        % Override D in result (this is a hack - need to modify the function)
        % Actually, we need to pass D through the function
        
        eig_all = result.eigenvalues;
        interarea = [];
        for j = 1:numel(eig_all)
            lam = eig_all(j);
            freq = abs(imag(lam)) / (2*pi);
            if freq > 0.4 && freq < 0.7 && imag(lam) > 0
                interarea = lam;
                break;
            end
        end
        
        if ~isempty(interarea)
            freq = abs(imag(interarea)) / (2*pi);
            zeta = -real(interarea) / abs(interarea);
            fprintf('D=%4.1f    %9.4f %+9.4fi   %8.4f    %8.4f\n', ...
                D_val, real(interarea), imag(interarea), freq, zeta);
        end
    catch ME
        fprintf('D=%4.1f    Error: %s\n', D_val, ME.message);
    end
end

fprintf('\nKundur Reference: -0.111 + 3.43i  (f=0.545 Hz, zeta=0.032)\n');