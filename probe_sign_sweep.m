function probe_sign_sweep()
%PROBE_SIGN_SWEEP Empirically test sign flips using existing debug options.
%For each configuration, let refine find the equilibrium and report the
%three oscillatory modes.  This isolates which sign configuration best
%matches Kundur.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results',false,'verbose',false,'max_iter',50,'tolerance',1e-8,'enforce_q_limits',false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
% Baseline (no flips)
configs = {
 'baseline (sdd=+1,sdq=+1)', struct('load_model','cc_p_cz_q');
 'sdd=-1 (d-damper Id flip)', struct('load_model','cc_p_cz_q','dbg_damp_d_sign',-1);
 'sdq=-1 (q-damper Iq flip)', struct('load_model','cc_p_cz_q','dbg_damp_q_sign',-1);
 'both -1',                   struct('load_model','cc_p_cz_q','dbg_damp_d_sign',-1,'dbg_damp_q_sign',-1);
};
fprintf('%-30s | %-9s | %-9s | %-9s | %-9s\n','config','resid','IA','A1','A2');
fprintf('%s\n', repmat('-',1,90));
for c=1:size(configs,1)
  try
    r=stability.kundur_ex126_sauer_pai_ssa('pf',pf,'options',configs{c,2});
    resid=norm(r.debug_residual_f);
    if resid<1e-6
      lam=r.eigenvalues; osc=lam(abs(imag(lam))>1); osc=osc(imag(osc)>0);
      [~,i1]=min(abs(imag(osc)-3.43)); [~,i2]=min(abs(imag(osc)-6.82)); [~,i3]=min(abs(imag(osc)-7.02));
      fprintf('%-30s | %8.1e | %+6.3f%+5.2f | %+6.3f%+5.2f | %+6.3f%+5.2f\n', ...
        configs{c,1}, resid, real(osc(i1)),imag(osc(i1)), real(osc(i2)),imag(osc(i2)), real(osc(i3)),imag(osc(i3)));
    else
      fprintf('%-30s | %8.1e | NOT CONVERGED\n', configs{c,1}, resid);
    end
  catch ME
    fprintf('%-30s | ERROR: %s\n', configs{c,1}, ME.message);
  end
end
fprintf('\nKundur: IA=-0.111+3.43j  A1=-0.492+6.82j  A2=-0.506+7.02j\n');
end
