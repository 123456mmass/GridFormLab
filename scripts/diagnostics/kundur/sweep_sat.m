function sweep_sat()
%SWEEP_SAT Sweep saturation configurations with the cc_p_cz_q load model.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
targets = [-0.111+1i*3.43; -0.492+1i*6.82; -0.506+1i*7.02];

configs = {
    false, true,  1.0;   % no sat (baseline)
    true,  false, 1.0;   % sat, d-axis only
    true,  true,  1.0;   % sat, both axes
    true,  false, 0.5;   % sat d-only, half strength
    true,  true,  0.5;   % sat both, half strength
    true,  false, 0.25;
    true,  true,  0.25;
};
fprintf('%-5s %-6s %-6s | %-22s | %-22s | %-22s | resid\n', ...
    'sat','qaxis','scale','interarea','area1','area2');
fprintf('%s\n', repmat('-',1,108));
for c = 1:size(configs,1)
    use_sat = configs{c,1}; sat_q = configs{c,2}; sc = configs{c,3};
    opts = struct('load_model','cc_p_cz_q','use_saturation',use_sat, ...
        'sat_q_axis',sat_q,'sat_scale',sc);
    try
        ssa = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);
        lam = ssa.eigenvalues(:);
        osc = lam(imag(lam) > 1e-3); osc_f = abs(imag(osc))/(2*pi);
        used = false(numel(osc),1);
        line = sprintf('%-5s %-6s %-6.2f | ', ternary(use_sat,'on','off'), ...
            ternary(sat_q,'on','off'), sc);
        for k = 1:3
            ref_f = abs(imag(targets(k)))/(2*pi);
            d = abs(osc_f - ref_f); d(used)=inf;
            [~,j]=min(d); used(j)=true; m = osc(j);
            line = [line sprintf('%+7.3f%+6.2fj', real(m), imag(m))];
            if k<3; line=[line ' | ']; end
        end
        fprintf('%s | %.2e\n', line, ssa.newton_residual);
    catch ME
        fprintf('%-5s %-6s %-6.2f | ERROR: %s\n', ternary(use_sat,'on','off'), ...
            ternary(sat_q,'on','off'), sc, ME.message);
    end
end
fprintf('\nKundur: interarea -0.111+3.43j | area1 -0.492+6.82j | area2 -0.506+7.02j\n');
end

function s = ternary(c,a,b)
if c; s=a; else; s=b; end
end
