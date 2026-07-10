function probe_coi_full()
%PROBE_COI_FULL Apply COI reduction to the full 6th-order model.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results',false,'verbose',false,'max_iter',50,'tolerance',1e-8,'enforce_q_limits',false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
opts=struct('load_model','cc_p_cz_q');
r=stability.kundur_ex126_sauer_pai_ssa('pf',pf,'options',opts);
Jxx=r.Jxx; Jxy=r.Jxy; Jyx=r.Jyx; Jyy=r.Jyy;
nx=size(Jxx,1); ng=4;
A_pinv = Jxx - Jxy * (pinv(Jyy) * Jyx);
H = [6.5 6.5 6.175 6.175]; Hn = H/sum(H);
nred = 6*ng - 2;   % remove COI angle + COI speed
T = zeros(nx, nred);
c = 1;
for k=1:ng
  T((k-1)*6+1, c) = 1; for kk=1:ng; T((kk-1)*6+1, c) = T((kk-1)*6+1, c) - Hn(kk); end; c=c+1;
  T((k-1)*6+2, c) = 1; for kk=1:ng; T((kk-1)*6+2, c) = T((kk-1)*6+2, c) - Hn(kk); end; c=c+1;
  for s=3:6; T((k-1)*6+s, c) = 1; c=c+1; end
end
L = pinv(T);
A_coi = L * A_pinv * T;
lam=sortrows([real(eig(A_coi)),imag(eig(A_coi))],2);
fprintf('Full 6th-order COI-reduced (22-state) eigenvalues:\n');
fprintf('  %10s %12s %10s %10s\n','Re','Im','f(Hz)','zeta');
for i=1:size(lam,1)
  f=abs(lam(i,2))/(2*pi); z=-lam(i,1)/(abs(lam(i,2))+1e-12);
  fprintf('  %+10.4f %+12.4f %9.4f %9.4f\n', lam(i,1), lam(i,2), f, z);
end
fprintf('\nKundur Table E12.3 targets:\n');
fprintf('  interarea -0.111 +/-3.43  (0.545Hz, zeta 0.032)\n');
fprintf('  area1     -0.492 +/-6.82  (1.087Hz, zeta 0.072)\n');
fprintf('  area2     -0.506 +/-7.02  (1.117Hz, zeta 0.072)\n');
end
