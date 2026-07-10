function probe_sync()
%PROBE_SYNC Measure synchronizing coefficient Ks = -dTe/delta for each machine
%and compare to analytical expectation.  Te on 100 MVA base, delta in rad.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results',false,'verbose',false,'max_iter',50,'tolerance',1e-8,'enforce_q_limits',false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
opts = struct('load_model','cc_p_cz_q');
ssa = stability.kundur_ex126_sauer_pai_ssa('pf',pf,'options',opts);
init = ssa.init;
M = case_data.machines; base = case_data.base_values; R=M.reactances;
g_d1=(R.Xdpp-R.Xl)/(R.Xdp-R.Xl); g_q1=(R.Xqpp-R.Xl)/(R.Xqp-R.Xl);
g_d2=(1-g_d1)/(R.Xdp-R.Xl); g_q2=(1-g_q1)/(R.Xqp-R.Xl);
gamma=struct('d1',g_d1,'q1',g_q1,'d2',g_d2,'q2',g_q2);
Ynet = ssa.Ynet; zb = init.zb_scale; ng = init.ng;
% Analytical Ks for classical (E'q behind X'd): Ks = E'*V*cos(delta0)/(X'd+xt)
% on machine base, then the SWING equation uses Te on the base it's on.
xt = 0.15*(100/900);
fprintf('Analytical classical Ks (E~1.3, V~1.0) per machine, Xdp+xt on 100MVA base:\n');
for k=1:ng
  Xdp_n = R.Xdp*zb;
  Eapprox = init.Eqpi(k);  % E'q at op
  Vt = abs(complex(init.y0(2*init.bus_idx(k)-1), init.y0(2*init.bus_idx(k))));
  Ks = Eapprox*Vt/(Xdp_n+xt);   % dP/delta at delta=0 reference approx
  fprintf('  G%d: E=%.3f V=%.3f Xdp+xt=%.4f  Ks=%.2f (on 100MVA), omega_classical=%.2f rad/s\n',...
    k, Eapprox, Vt, Xdp_n+xt, Ks, sqrt(Ks*377/(2*init.H_sys(k))));
end
% Numerical dTe/ddelta from the SSA Jacobian: Afull(omega_k, delta_k) = -dTe/ddelta / (2H)
% (since domega/dt = (Tm - Te - D omega)/(2H), and Tm, omega terms don't depend on delta).
Afull = ssa.Afull;
fprintf('\nFrom Afull: -dTe/ddelta_k = Afull(om_k,de_k)*2H (should match Ks):\n');
for k=1:ng
  H = init.H_sys(k);
  dTe_ddelta = -Afull(6*(k-1)+2, 6*(k-1)+1) * 2*H;
  fprintf('  G%d: -dTe/ddelta = %.2f  (Afull entry=%.5f, 2H=%.2f)\n', k, dTe_ddelta, Afull(6*(k-1)+2,6*(k-1)+1), 2*H);
end
% Also check cross terms dTe_i/ddelta_j
fprintf('\nFull -dTe_i/ddelta_j matrix (on 100MVA, from Afull*2H):\n');
fprintf('         ');
for j=1:ng; fprintf('  de_%d    ', j); end; fprintf('\n');
for i=1:ng
  fprintf('Te_%d: ', i);
  for j=1:ng
    dTe = -Afull(6*(i-1)+2, 6*(j-1)+1) * 2*init.H_sys(i);
    fprintf('%+8.3f ', dTe);
  end
  fprintf('\n');
end
end
