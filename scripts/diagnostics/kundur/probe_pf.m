function probe_pf()
%PROBE_PF Dump the power-flow solution to compare with Kundur Ex12.6.
pf_init_paths;
case_data = cases.case_kundur_two_area_classical();
pf_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
fprintf('converged=%d iters=%d Ploss=%.4f\n', pf.converged, pf.iterations, pf.P_loss_total);
fprintf('\n%-4s %9s %9s %9s %9s %9s\n','bus','Vmag','Vang','Pgen','Qgen','Pline');
for b = 1:numel(pf.external_bus_ids)
    fprintf('%-4d %9.4f %9.3f %9.4f %9.4f\n', pf.external_bus_ids(b), ...
        pf.bus_voltage(b), pf.bus_angle_deg(b), pf.P_generation(b), pf.Q_generation(b));
end
fprintf('\nLine flows (P from->to):\n');
for l = 1:size(pf.line_endpoints,1)
    fprintf('  %d->%d  P=%.4f\n', pf.line_endpoints(l,1), pf.line_endpoints(l,2), pf.line_flow_P(l,1));
end
% Kundur published: bus voltages ~ 1.03,1.01,1.03,1.01 at gen buses;
% angles roughly 0 (bus5 ref). Tie flow ~400 MW.
fprintf('\nTotal gen P = %.4f, total load P = %.4f\n', ...
    sum(pf.P_generation), sum(case_data.bus_data(:,7)));
end
