function sweep_kundur_ssa()
%SWEEP_KUNDUR_SSA Try several model configurations and report the 3 key modes.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);

targets = [-0.111+1i*3.43; -0.492+1i*6.82; -0.506+1i*7.02];
tnames = {'interarea','area1','area2'};

configs = {
    'cc_p_cz_q', false;   % current baseline (Kundur Example a stated model)
    'cz',         false;   % full constant-impedance
    'cp',         false;   % full constant-power
    'cc',         false;   % full constant-current (P and Q)
    'cc_p_cz_q',  true;    % Kundur load + saturation
    'cz',         true;    % CZ load + saturation
};

fprintf('%-18s %-5s | %-22s | %-22s | %-22s | resid\n', ...
    'load_model','sat','interarea','area1','area2');
fprintf('%s\n', repmat('-',1,108));
for c = 1:size(configs,1)
    lm = configs{c,1}; sat = configs{c,2};
    try
        ssa_opts = struct('load_model', lm, 'use_saturation', sat);
        ssa = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', ssa_opts);
        lam = ssa.eigenvalues(:);
        osc = lam(imag(lam) > 1e-3);
        osc_f = abs(imag(osc))/(2*pi);
        used = false(numel(osc),1);
        line = sprintf('%-18s %-5s | ', lm, ternary(sat,'on','off'));
        for k = 1:3
            ref_f = abs(imag(targets(k)))/(2*pi);
            d = abs(osc_f - ref_f); d(used)=inf;
            [~,j]=min(d); used(j)=true;
            m = osc(j);
            line = [line sprintf('%+7.3f%+6.2fj ', real(m), imag(m))];
            if k<3; line=[line '| ']; end
        end
        fprintf('%s | %.2e\n', line, ssa.newton_residual);
    catch ME
        fprintf('%-18s %-5s | ERROR: %s\n', lm, ternary(sat,'on','off'), ME.message);
    end
end
fprintf('\nKundur targets:  interarea -0.111+3.43j | area1 -0.492+6.82j | area2 -0.506+7.02j\n');
end

function s = ternary(c,a,b)
if c; s=a; else; s=b; end
end
