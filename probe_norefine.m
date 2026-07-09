function probe_norefine()
%PROBE_NOREFINE Linearize directly from the power-flow initialization without
%re-solving the operating point, to see if the generator power stays at Pgen.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);

% Build the SSA object but reach in and skip refine by replicating the
% initialization + linearization with the cz load model.
M = case_data.machines; R = M.reactances;
g_d1 = (R.Xdpp - R.Xl)/(R.Xdp - R.Xl);
g_q1 = (R.Xqpp - R.Xl)/(R.Xqp - R.Xl);
g_d2 = (1-g_d1)/(R.Xdp - R.Xl);
g_q2 = (1-g_q1)/(R.Xqp - R.Xl);
gamma = struct('d1',g_d1,'q1',g_q1,'d2',g_d2,'q2',g_q2);
opts = struct('load_model','cz','use_saturation',true);

% Use the public function but capture pre-refine residual.
ssa = stability.kundur_ex126_sauer_pai_ssa('pf', pf, 'options', opts);
fprintf('Pre-refine residual: f=%.3e g=%.3e\n', ...
    norm(ssa.pre_refine_residual_f), norm(ssa.pre_refine_residual_g));
fprintf('Post-refine residual: %.3e\n', ssa.newton_residual);
fprintf('Tm = '); fprintf('%.4f ', ssa.init.Tm); fprintf('\n');
fprintf('Pgen(pf) = '); fprintf('%.4f ', pf.P_generation(ssa.init.bus_idx).'); fprintf('\n');

% Now manually skip refine: re-init and build Jacobian at the pf operating point.
end
