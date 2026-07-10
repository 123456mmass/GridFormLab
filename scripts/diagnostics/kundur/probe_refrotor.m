function probe_refrotor()
%PROBE_REFROTOR Test fixing a rotor angle (not slack bus) as reference.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results',false,'verbose',false,'max_iter',50,'tolerance',1e-8,'enforce_q_limits',false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
m=case_data.machines; m.time_constants=struct('Tpd0',1e4,'Tppd0',1e4,'Tpq0',1e4,'Tppq0',1e4);
opts=struct('load_model','cc_p_cz_q','machine_override',m);
r=stability.kundur_ex126_sauer_pai_ssa('pf',pf,'options',opts);
Jxx=r.Jxx; Jxy=r.Jxy; Jyx=r.Jyx; Jyy=r.Jyy;
nx=size(Jxx,1); ny=size(Jyy,1);
% Strategy: fix delta_1 (state 1) as rotor reference, leave ALL bus voltages
% free (network angle redundancy resolved by pinning a rotor).  But Jyy is
% singular (1D nullspace = uniform angle).  We pin that nullspace via the
% rotor: use the augmented system [Jyy Jyx; (rotor row)].
% Simpler: pin one bus angle to remove network singularity, AND pin delta_1
% to the SAME bus via the stator eq.  But that's what we have.
%
% Cleanest: COI reduction.  Build the (nx+1) x (nx+1) augmented A by adding
% the COI angle constraint sum(H_i delta_i)=0 as an algebraic equation, with
% the COI angle as a new state.  Equivalently, project onto the subspace
% orthogonal to uniform delta.
%
% Test: remove the slack bus entirely from the network (it becomes a
% "floating" reference) by using pinv on Jyy, then do COI on the rotors.
A_pinv = Jxx - Jxy * (pinv(Jyy) * Jyx);   % 24x24, no slack fix
% Now COI-reduce: the uniform-rotor mode should be ~0 already (pinv killed it).
% Apply the standard COI transform on rotors.
ng=4;
% Build COI transform: keep delta_i - delta_coi for all i, omega_i - omega_coi.
% delta_coi = sum(H_i delta_i)/sum(H_i).  T maps reduced->full.
H = [6.5 6.5 6.175 6.175];
Hn = H/sum(H);
% Reduced states (22): for each machine, (delta_i-delta_coi, omega_i-omega_coi)
% + all 4 non-angle/omega states (Eqp,Edp,Psipd,Psipq) = 4*2 + 4*4 = 8+16=24...
% that's 24.  COI removes 2 (delta_coi, omega_coi) -> 22.
T = zeros(nx, 22);
keep_idx = 1;
for k=1:ng
  % delta_i - delta_coi: column gets +1 at (k-1)*6+1, and -Hn(k) at all delta rows
  T((k-1)*6+1, keep_idx) = T((k-1)*6+1, keep_idx) + 1;
  for kk=1:ng; T((kk-1)*6+1, keep_idx) = T((kk-1)*6+1, keep_idx) - Hn(kk); end
  keep_idx = keep_idx+1;
  % omega_i - omega_coi
  T((k-1)*6+2, keep_idx) = T((k-1)*6+2, keep_idx) + 1;
  for kk=1:ng; T((kk-1)*6+2, keep_idx) = T((kk-1)*6+2, keep_idx) - Hn(kk); end
  keep_idx = keep_idx+1;
  % Eqp, Edp, Psipd, Psipq (unchanged)
  for s=3:6
    T((k-1)*6+s, keep_idx) = 1; keep_idx=keep_idx+1;
  end
end
% L = pinv(T) (since T is not square; T maps reduced->full, L maps full->reduced)
L = pinv(T);
A_coi = L * A_pinv * T;
lam=sortrows([real(eig(A_coi)),imag(eig(A_coi))],2);
fprintf('COI-reduced (22-state) classical eigenvalues:\n');
for i=1:size(lam,1); fprintf('  %+10.4f %+10.4fj  f=%.3fHz\n',lam(i,1),lam(i,2),abs(lam(i,2))/(2*pi)); end
fprintf('\nKundur classical: interarea j3.43 (0.545Hz), area1 j6.82, area2 j7.02\n');
end
