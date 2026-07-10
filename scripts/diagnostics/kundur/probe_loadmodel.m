function probe_loadmodel()
%PROBE_LOADMODEL Compare interarea mode across load models.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
models = {'cz','cc_p_cz_q','cc','cp'};
fprintf('%-12s | %-22s | %-22s | %-22s\n','load','interarea','area1','area2');
fprintf('%s\n', repmat('-',1,90));
for m = 1:numel(models)
    opts = struct('load_model',models{m});
    try
        ssa = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);
        lam = ssa.eigenvalues(:);
        osc = lam(imag(lam) > 1e-3); osc_f = abs(imag(osc))/(2*pi);
        targets = [-0.111+1i*3.43; -0.492+1i*6.82; -0.506+1i*7.02];
        used = false(numel(osc),1);
        line = sprintf('%-12s | ', models{m});
        for k = 1:3
            ref_f = abs(imag(targets(k)))/(2*pi);
            d = abs(osc_f - ref_f); d(used)=inf;
            [~,j]=min(d); used(j)=true; mm = osc(j);
            line = [line sprintf('%+7.3f%+6.2fj', real(mm), imag(mm))];
            if k<3; line=[line ' | ']; end
        end
        fprintf('%s\n', line);
    catch ME
        fprintf('%-12s | ERROR: %s\n', models{m}, ME.message);
    end
end
fprintf('\nKundur: interarea -0.111+3.43j | area1 -0.492+6.82j | area2 -0.506+7.02j\n');
end
