function probe_fvec()
%PROBE_FVEC Dump the pre-refine f residual per state to find the inconsistency.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);

for use_sat = [false, true]
  for lm = {'cc_p_cz_q','cz'}
    opts = struct('load_model', lm{1}, 'use_saturation', use_sat);
    ssa = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);
    f = ssa.pre_refine_residual_f;
    names = ssa.state_names;
    fprintf('\n=== load=%s sat=%d  pre-refine ||f||=%.4e ===\n', lm{1}, use_sat, norm(f));
    [~,idx] = sort(abs(f),'descend');
    for j = 1:min(8,idx(end))
        i = idx(j);
        fprintf('  %-18s = %+.4e\n', names{i}, f(i));
    end
  end
end
end
