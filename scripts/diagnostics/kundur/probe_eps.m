function probe_eps()
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, 'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
for ep = [1e-5, 1e-6, 1e-7, 1e-8]
  opts = struct('load_model','cc_p_cz_q','fd_eps',ep);
  ssa = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);
  lam = ssa.eigenvalues(:);
  % find the interarea (smallest |imag| with imag>0.5) and the fastest mode
  [~,idx]=sort(real(lam),'descend'); lam=lam(idx);
  inter = lam(find(imag(lam)>2 & imag(lam)<4,1));
  fast = lam(end);
  fprintf('eps=%.0e : interarea=%+.4f%+.4fj  fastest=%+.4f  resid=%.2e\n', ...
      ep, real(inter), imag(inter), real(fast), ssa.newton_residual);
end
