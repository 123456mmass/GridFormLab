function probe_sauer_jacobian_check()
% Check key Jacobian entries and coupling.
r=stability.sauer_pai_ex83_ssa();
A=r.Afull;
% State order: per machine [Eq', Ed', delta, omega, Efd, Rf, VR]
% Machine 1: states 1-7, Machine 2: 8-14, Machine 3: 15-21
fprintf('Diagonal of Asys:\n');
names={'Eq1','Ed1','d1','w1','Ef1','Rf1','VR1','Eq2','Ed2','d2','w2','Ef2','Rf2','VR2','Eq3','Ed3','d3','w3','Ef3','Rf3','VR3'};
for k=1:21
  fprintf('  %s: %.4f  (Afull diag)\n', names{k}, A(k,k));
end

% Check specific couplings
fprintf('\nKey off-diagonal entries:\n');
% Efd -> Eq' coupling (should be 1/Tdo)
fprintf('  A(Eq1,Ef1) = %.4f  (expect ~1/Tdo1=%.4f)\n', A(1,5), 1/8.96);
fprintf('  A(Eq2,Ef2) = %.4f  (expect ~1/Tdo2=%.4f)\n', A(8,12), 1/6.0);
% VR -> Efd coupling (should be 1/TE)
fprintf('  A(Ef1,VR1) = %.4f  (expect ~1/TE=%.4f)\n', A(5,7), 1/0.314);
% KA*Vm -> VR coupling (through network, check Jxy)
fprintf('\nJxy for VR equations (d VR/d V):\n');
for k=1:3
  vr_idx = (k-1)*7+7;
  vre_idx = (k-1)*2+1;
  vim_idx = (k-1)*2+2;
  fprintf('  Machine %d: dVR/dVre=%+.4f dVR/dVim=%+.4f\n', k, r.Jxy(vr_idx,vre_idx), r.Jxy(vr_idx,vim_idx));
end

% Check effective field time constant from Asys
fprintf('\nEffective field dynamics (A(Eq,Eq)):\n');
fprintf('  Machine 1: %.4f  (open-loop -1/Tdo=%.4f)\n', A(1,1), -1/8.96);
fprintf('  Machine 2: %.4f  (open-loop -1/Tdo=%.4f)\n', A(8,8), -1/6.0);
fprintf('  Machine 3: %.4f  (open-loop -1/Tdo=%.4f)\n', A(15,15), -1/5.89);

% Check effective exciter dynamics
fprintf('\nEffective exciter dynamics (A(VR,VR)):\n');
fprintf('  Machine 1: %.4f  (open-loop -1/TA=%.4f)\n', A(7,7), -1/0.2);
fprintf('  Machine 2: %.4f  (open-loop -1/TA=%.4f)\n', A(14,14), -1/0.2);
fprintf('  Machine 3: %.4f  (open-loop -1/TA=%.4f)\n', A(21,21), -1/0.2);

% Check coupling between Efd and Eq' through Asys
fprintf('\nCoupling A(Eq,Efd) and A(Efd,Eq):\n');
for k=1:3
  eq_idx=(k-1)*7+1; efd_idx=(k-1)*7+5;
  fprintf('  Machine %d: A(Eq,Efd)=%.4f  A(Efd,Eq)=%.4f\n', k, A(eq_idx,efd_idx), A(efd_idx,eq_idx));
end
end
