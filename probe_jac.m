function probe_jac()
%PROBE_JAC Examine the DAE Jacobian conditioning and Schur complement.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
opts = struct('load_model','cc_p_cz_q');
ssa = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);

% Rebuild Jacobians by reaching into the init.
init = ssa.init;
M = case_data.machines; base = case_data.base_values;
R = M.reactances;
g_d1 = (R.Xdpp - R.Xl)/(R.Xdp - R.Xl);
g_q1 = (R.Xqpp - R.Xl)/(R.Xqp - R.Xl);
g_d2 = (1-g_d1)/(R.Xdp - R.Xl);
g_q2 = (1-g_q1)/(R.Xqp - R.Xl);
gamma = struct('d1',g_d1,'q1',g_q1,'d2',g_d2,'q2',g_q2);
Ynet = ssa.init;  % placeholder
% We can't easily rebuild Ynet here, but ssa already has Afull.  Examine it.
A = ssa.Afull;
fprintf('Afull size: %dx%d\n', size(A,1), size(A,2));
fprintf('cond(Afull) = %.4e\n', cond(A));
fprintf('norm(Afull) = %.4e\n', norm(A));
% Eigenvalues of Afull (already have) - check the spurious fast mode.
lam = ssa.eigenvalues(:);
[~,idx] = sort(real(lam)); lam = lam(idx);
fprintf('\nFastest (most negative) modes:\n');
for k = max(1,numel(lam)-5):numel(lam)
    fprintf('  %12.4f %+12.4fj\n', real(lam(k)), imag(lam(k)));
end
% Check symmetry of A (real eigenvalues should be real).
fprintf('\nAfull symmetric? ||A-A''|| = %.4e\n', norm(A-A'));
% Look at the swing-block (first 8 rows/cols = delta,omega for 4 machines).
fprintf('\nSwing block (rows 1-8, cols 1-8) real parts:\n');
disp(real(A(1:8,1:8)));
end
