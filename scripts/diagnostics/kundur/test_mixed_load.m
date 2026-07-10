%% Test mixed load models to find optimal damping
pf_init_paths();
case_data = cases.case_kundur_two_area_classical();

pf_opts = struct('plot_results', false, 'verbose', false, ...
    'max_iter', 50, 'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);

% Test different P load models (Z = constant impedance, I = constant current, P = constant power)
% Q is always constant impedance (CZ)
p_models = {'cz', 'cc', 'cp'};
p_names = {'CZ-P', 'CC-P', 'CP-P'};

fprintf('=== Load Model Comparison (Q = Constant Impedance) ===\n');
fprintf('%-10s %-25s %-10s %-10s %-10s\n', 'P Model', 'Interarea Mode', 'Freq (Hz)', 'Zeta', 'Zeta Error');
fprintf('%-10s %-25s %-10s %-10s %-10s\n', '-------', '--------------', '---------', '----', '----------');

for i = 1:numel(p_models)
    load_model = [p_models{i}, '_p_cz_q'];
    opts = struct('load_model', load_model, 'use_saturation', false);
    
    try
        result = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);
        
        eig_all = result.eigenvalues;
        interarea = [];
        local1 = [];
        local2 = [];
        
        for j = 1:numel(eig_all)
            lam = eig_all(j);
            freq = abs(imag(lam)) / (2*pi);
            if freq > 0.4 && freq < 0.7 && imag(lam) > 0 && isempty(interarea)
                interarea = lam;
            elseif freq > 0.9 && freq < 1.3 && imag(lam) > 0
                if isempty(local1)
                    local1 = lam;
                elseif isempty(local2)
                    local2 = lam;
                end
            end
        end
        
        if ~isempty(interarea)
            freq = abs(imag(interarea)) / (2*pi);
            zeta = -real(interarea) / abs(interarea);
            zeta_err = abs(zeta - 0.032) / 0.032 * 100;
            fprintf('%-10s %9.4f %+9.4fi   %8.4f    %8.4f    %6.1f%%\n', ...
                p_names{i}, real(interarea), imag(interarea), freq, zeta, zeta_err);
        end
    catch ME
        fprintf('%-10s Error: %s\n', p_names{i}, ME.message);
    end
end

fprintf('\nKundur Reference: -0.111 + 3.43i  (f=0.545 Hz, zeta=0.032)\n');
fprintf('\nNote: CZ-P gives zeta too low, CP-P gives zeta too high.\n');
fprintf('Need to find intermediate load model that gives zeta ≈ 0.032\n');