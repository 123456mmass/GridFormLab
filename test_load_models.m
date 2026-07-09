%% Test different load models for Kundur 2-area system
pf_init_paths();
case_data = cases.case_kundur_two_area_classical();

% Run power flow
pf_opts = struct('plot_results', false, 'verbose', false, ...
    'max_iter', 50, 'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);

fprintf('=== Power Flow Results ===\n');
fprintf('Converged: %d, Iterations: %d\n', pf.converged, pf.iterations);
fprintf('\nGenerator outputs:\n');
for k = 1:4
    bidx = find(pf.external_bus_ids == case_data.machines.units(k).bus, 1);
    fprintf('  G%d (Bus %d): P=%.4f pu, Q=%.4f pu, V=%.4f pu, angle=%.2f deg\n', ...
        k, case_data.machines.units(k).bus, pf.P_generation(bidx), pf.Q_generation(bidx), ...
        pf.bus_voltage(bidx), pf.bus_angle_deg(bidx));
end

% Test different load models
load_models = {'cz', 'cc', 'cp', 'cc_p_cz_q', 'cz_p_cz_q'};
model_names = {'Const Z (CZ)', 'Const I (CC)', 'Const P (CP)', 'CC-P + CZ-Q', 'CZ-P + CZ-Q'};

fprintf('\n=== Load Model Comparison ===\n');
fprintf('%-15s %-25s %-10s %-10s\n', 'Load Model', 'Interarea Mode', 'Freq (Hz)', 'Zeta');
fprintf('%-15s %-25s %-10s %-10s\n', '----------', '--------------', '---------', '----');

for i = 1:numel(load_models)
    try
        opts = struct('load_model', load_models{i}, 'use_saturation', false);
        result = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);
        
        % Find interarea mode (~0.55 Hz)
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
            fprintf('%-15s %9.4f %+9.4fi   %8.4f    %8.4f\n', ...
                model_names{i}, real(interarea), imag(interarea), freq, zeta);
        else
            fprintf('%-15s Interarea mode not found\n', model_names{i});
        end
    catch ME
        fprintf('%-15s Error: %s\n', model_names{i}, ME.message);
    end
end

fprintf('\n=== Kundur Reference (Table E12.3) ===\n');
fprintf('Interarea: -0.111 + 3.43i  (f=0.545 Hz, zeta=0.032)\n');