clc; clear;
global Ybus nbus sys_base bus line mac_con pss_con exc_con
sys_base=100;
run d9bus;
nbus=9;
Ybus=ybus;
[Vg,thg,Pg,Qg,Pl,Ql,PV,PQ,Vbus,theta]=loadflow;
[A, B] = linearization(Pg,Qg,Vg,thg,Vbus,theta,PV,PQ,Pl,Ql);
lam=eig(A);
[~,idx]=sort(real(lam),'descend');
lam=lam(idx);
fprintf('Reference eigenvalues:\n');
for k=1:numel(lam)
  if abs(imag(lam(k)))<1e-8
    fprintf('  %+10.4f\n', real(lam(k)));
  else
    fprintf('  %+10.4f %+10.4fj\n', real(lam(k)), imag(lam(k)));
  end
end
