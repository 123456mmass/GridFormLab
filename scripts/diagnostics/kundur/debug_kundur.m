%% Compare Sauer-Pai vs GENROU models
pf_init_paths();
case_data = cases.case_kundur_two_area_classical();

% Run power flow
pf_opts = struct('plot_results', false, 'verbose', false, ...
    'max_iter', 50, 'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);

fprintf('=== Power Flow: Converged=%d, Iterations=%d ===\n', pf.converged, pf.iterations);

% Test Sauer-Pai model
fprintf('\n=== Testing Sauer-Pai Model ===\n');
try
    opts_sp = struct('load_model', 'cc_p_cz_q', 'use_saturation', false);
    result_sp = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts_sp);
    
    fprintf('Sauer-Pai eigenvalues (electromechanical modes):\n');
    eig_sp = result_sp.eigenvalues;
    [~, idx] = sort(imag(eig_sp), 'descend');
    eig_sorted = eig_sp(idx);
    
    % Find modes with significant imaginary part (electromechanical)
    count = 0;
    for i = 1:numel(eig_sorted)
        lam = eig_sorted(i);
        if abs(imag(lam)) > 0.5 && imag(lam) > 0 && count < 5
            freq = abs(imag(lam)) / (2*pi);
            zeta = -real(lam) / abs(lam);
            fprintf('  Mode: %10.4f %+10.4fi  f=%.3f Hz, zeta=%.4f\n', ...
                real(lam), imag(lam), freq, zeta);
            count = count + 1;
        end
    end
catch ME
    fprintf('Sauer-Pai failed: %s\n', ME.message);
end

% Test GENROU model
fprintf('\n=== Testing GENROU Model ===\n');
try
    opts_gr = struct('load_model', 'cc_p_cz_q', 'use_saturation', false);
    result_gr = stability.kundur_ex126_genrou_ssa('pf', pf, 'options', opts_gr);
    
    fprintf('GENROU eigenvalues (electromechanical modes):\n');
    eig_gr = result_gr.eigenvalues;
    [~, idx] = sort(imag(eig_gr), 'descend');
    eig_sorted = eig_gr(idx);
    
    count = 0;
    for i = 1:numel(eig_sorted)
        lam = eig_sorted(i);
        if abs(imag(lam)) > 0.5 && imag(lam) > 0 && count < 5
            freq = abs(imag(lam)) / (2*pi);
            zeta = -real(lam) / abs(lam);
            fprintf('  Mode: %10.4f %+10.4fi  f=%.3f Hz, zeta=%.4f\n', ...
                real(lam), imag(lam), freq, zeta);
            count = count + 1;
        end
    end
catch ME
    fprintf('GENROU failed: %s\n', ME.message);
end

fprintf('\n=== Kundur Table E12.3 Reference (Manual Excitation) ===\n');
fprintf('Interarea mode: -0.111 +/- 3.43i (f=0.545 Hz, zeta=0.032)\n');
fprintf('Area 1 local:   -0.492 +/- 6.82i (f=1.087 Hz, zeta=0.072)\n');
fprintf('Area 2 local:   -0.506 +/- 7.02i (f=1.117 Hz, zeta=0.072)\n');