function probe_sign()
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, 'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
targets = [-0.111+1i*3.43; -0.492+1i*6.82; -0.506+1i*7.02];
for cfg = {'+1,+1','+1,-1','-1,+1','-1,-1'}
  parts = strsplit(cfg{1},',');
  sdd = str2double(parts{1}); sdq = str2double(parts{2});
  opts = struct('load_model','cc_p_cz_q','dbg_damp_d_sign',sdd,'dbg_damp_q_sign',sdq);
  ssa = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);
  lam = ssa.eigenvalues(:);
  osc = lam(imag(lam) > 1e-3); osc_f = abs(imag(osc))/(2*pi);
  used = false(numel(osc),1);
  line = sprintf('d=%+d q=%+d | ', sdd, sdq);
  for k = 1:3
    ref_f = abs(imag(targets(k)))/(2*pi);
    d = abs(osc_f - ref_f); d(used)=inf;
    [~,j]=min(d); used(j)=true; m = osc(j);
    line = [line sprintf('%+7.3f%+6.2fj', real(m), imag(m))];
    if k<3; line=[line ' | ']; end
  end
  fprintf('%s\n', line);
end
fprintf('Kundur:    interarea -0.111+3.43j | area1 -0.492+6.82j | area2 -0.506+7.02j\n');
