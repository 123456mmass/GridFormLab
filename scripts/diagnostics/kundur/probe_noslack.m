function probe_noslack()
%PROBE_NOSLACK Test: include ALL algebraic vars (don't fix slack) in Schur.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results',false,'verbose',false,'max_iter',50,'tolerance',1e-8,'enforce_q_limits',false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
m=case_data.machines; m.time_constants=struct('Tpd0',1e4,'Tppd0',1e4,'Tpq0',1e4,'Tppq0',1e4);
opts=struct('load_model','cc_p_cz_q','machine_override',m);
r=stability.kundur_ex126_sauer_pai_ssa('pf',pf,'options',opts);
Jxx=r.Jxx; Jxy=r.Jxy; Jyx=r.Jyx; Jyy=r.Jyy;
% Test 1: standard (remove y(2))
A1 = Jxx - Jxy(:,setdiff(1:22,2)) * (Jyy(setdiff(1:22,2),setdiff(1:22,2)) \ Jyx(setdiff(1:22,2),:));
% Test 2: remove y(1) (slack Vre) instead
A2 = Jxx - Jxy(:,setdiff(1:22,1)) * (Jyy(setdiff(1:22,1),setdiff(1:22,1)) \ Jyx(setdiff(1:22,1),:));
% Test 3: remove nothing -- but Jyy is singular (angle redundancy), so use pinv
A3 = Jxx - Jxy * (pinv(Jyy) * Jyx);
for t=1:3
  if t==1; A=A1; name='remove y(2) (standard)'; end
  if t==2; A=A2; name='remove y(1)'; end
  if t==3; A=A3; name='pinv (remove nothing)'; end
  lam=sortrows([real(eig(A)),imag(eig(A))],2);
  fprintf('\n=== %s ===\n', name);
  for i=1:size(lam,1); fprintf('  %+10.4f %+10.4fj\n',lam(i,1),lam(i,2)); end
end
end
