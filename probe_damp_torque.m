function probe_damp_torque()
%PROBE_DAMP_TORQUE Measure the damping torque contribution of each damper
%winding by perturbing omega and observing the change in Te, with all other
%states and the network solved consistently.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
opts = struct('load_model','cc_p_cz_q');
ssa = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);
init = ssa.init;
M = case_data.machines; base = case_data.base_values; R = M.reactances;
g_d1 = (R.Xdpp - R.Xl)/(R.Xdp - R.Xl);
g_q1 = (R.Xqpp - R.Xl)/(R.Xqp - R.Xl);
g_d2 = (1-g_d1)/(R.Xdp - R.Xl);
g_q2 = (1-g_q1)/(R.Xqp - R.Xl);
gamma = struct('d1',g_d1,'q1',g_q1,'d2',g_d2,'q2',g_q2);
Ynet = ssa.Ynet;
zb = init.zb_scale;
ng = init.ng;
% For a small omega perturbation on machine k, re-solve the algebraic
% network (y) holding x fixed except omega (omega doesn't enter g or the
% stator eqs directly, so y stays the same).  Then Te changes only through
% the swing equation? No - Te depends on x (delta, Eqp, Edp, Psipd, Psipq)
% and y (V).  omega does NOT enter Te directly.  So the damper damping
% comes through the COUPLING: omega -> delta -> (via network) -> Id/Iq ->
% damper flux -> Te.  That's a dynamic effect, not a static one.
%
% Instead, measure the damping via the eigenvalue sensitivity.  The
% interarea mode is mostly delta/omega.  Look at the (omega, Te) block of
% the reduced A matrix: domega/dt = (Tm - Te - D*omega)/(2H).  The
% effective damping on the interarea mode is -Re(eig) and comes from
% dTe/domega (through the full dynamic chain).
%
% Direct approach: extract the Ared row for omega_1..omega_4 and the
% columns for delta_1..delta_4 (synchronizing) and omega_1..omega_4
% (damping).  The damping block Ared(omega_i, omega_j) tells us how each
% omega affects each omega_dot.
Ared = ssa.Ared;
% Full (un-reduced) Ared_full has 24 states: for machine k,
%   6*(k-1)+1 = delta, +2 = omega, +3 = Eqp, +4 = Edp, +5 = Psipd, +6 = Psipq
Afull = ssa.Afull;
fprintf('Afull(omega_i, omega_j) block (should be ~ -D/(2H) = 0 since D=0):\n');
fprintf('         ');
for j=1:ng; fprintf('  om_%d   ', j); end; fprintf('\n');
for i=1:ng
    fprintf('om_%d: ', i);
    for j=1:ng
        fprintf('%+8.4f ', Afull(6*(i-1)+2, 6*(j-1)+2));
    end
    fprintf('\n');
end
fprintf('\nAfull(omega_i, delta_j) block (synchronizing torque coefficients, /2H):\n');
fprintf('         ');
for j=1:ng; fprintf('  de_%d   ', j); end; fprintf('\n');
for i=1:ng
    fprintf('om_%d: ', i);
    for j=1:ng
        fprintf('%+8.4f ', Afull(6*(i-1)+2, 6*(j-1)+1));
    end
    fprintf('\n');
end
% The damping of the interarea mode comes from the FULL dynamic chain.
% Decompose: with damper, the effective damping = contribution from each
% state.  Use eigenvalue sensitivity: dlam/dA_ij = v_i * u_j (left/right
% eigenvectors).  Find the interarea mode.
lam = eig(Afull);
[~,idx] = sort(abs(imag(lam) - 3.0));
ia = lam(idx(1));
fprintf('\nInterarea candidate: %+6.4f %+6.4fj\n', real(ia), imag(ia));
[V,D] = eig(Afull); [~,k] = min(abs(diag(D)-ia));
v = V(:,k); [U,~] = eig(Afull'); [~,k2] = min(abs(diag(Afull')-ia));  % wrong
% Use proper left eigenvector: A*V=V*D => V\A = D*V\, left eigenvector rows of V\
VL = inv(V);
u = VL(k,:)';  % left eigenvector (column) for mode k
fprintf('Mode participation (|right eigvec| * |left eigvec|):\n');
for i=1:24
    p = abs(v(i))*abs(u(i));
    if p > 0.01
        fprintf('  state %2d (%s): %+8.4f %+8.4fj  particip=%.4f\n', ...
            i, init.state_names{i}, real(v(i)), imag(v(i)), p);
    end
end
end
