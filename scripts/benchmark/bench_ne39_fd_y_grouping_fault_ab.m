function bench_ne39_fd_y_grouping_fault_ab()
%BENCH_NE39_FD_Y_GROUPING_FAULT_AB  Fault/clear option-pinned A/B.
%   Fixed-step trapezoidal loop that switches the stamped network
%   Ypre -> Yfault -> Ypost at the same instants for both arms; the ONLY
%   pinned difference is opt.fd_y_grouping ('off' vs 'auto'). This forces the
%   FD Jacobian y-grouping to be rebuilt under a changed topology at every
%   step of the fault window, not just once. Trajectories must be bit-identical.
pf_init_paths();
s = cases.scenario_ne39_5sg_5ibr();
[devices,~] = stability.build_mixed_resource_devices( ...
    s.case_data, s.resources, s.scenario_opt);
eq = stability.mixed_equilibrium_solve(s.case_data, ...
    struct('devices',devices), struct('verbose',false));
fault_bus = 16; Zf = 1i*0.10;
dopt = struct('full_kcl',true,'u_eq',eq.u_eq, ...
    'event_context',eq.equilibrium_context, ...
    'dynamic_state_indices',eq.dynamic_state_indices, ...
    'fault_bus',fault_bus,'Zf',Zf);
dae = stability.composite_dae(s.case_data, devices, dopt);
asi = eq.dynamic_state_indices(:)';

t_end = 0.5; dt = 0.004; t_fault = 0.10; t_clear = 0.20;
n_step = round(t_end/dt);

[t_off, X_off, Y_off, r_off] = run_arm(dae, eq, asi, dt, n_step, t_fault, t_clear, 'off');
[t_auto, X_auto, Y_auto, r_auto] = run_arm(dae, eq, asi, dt, n_step, t_fault, t_clear, 'auto');

fprintf('FAULT steps=%d t_fault=%.3f t_clear=%.3f\n', n_step, t_fault, t_clear);
fprintf('FAULT x_maxdiff=%.3e y_maxdiff=%.3e\n', ...
    max(abs(X_off(:)-X_auto(:))), max(abs(Y_off(:)-Y_auto(:))));
fprintf('FAULT max_resid off=%.3e auto=%.3e\n', max(r_off), max(r_auto));
fprintf('FAULT time off=%.3f auto=%.3f speedup=%.3fx\n', ...
    t_off, t_auto, t_off/t_auto);
end

function [elapsed, X, Y, resid] = run_arm(dae, eq, asi, dt, n_step, t_fault, t_clear, y_grp)
x = eq.x0(:); y = dae.y0(:);
X = zeros(numel(x), n_step+1); Y = zeros(numel(y), n_step+1);
X(:,1) = x; Y(:,1) = y; resid = zeros(1,n_step);
a = tic;
for k = 1:n_step
    t_now = (k-1)*dt;
    if t_now < t_fault
        Yn = dae.topology.Ypre;
    elseif t_now < t_clear
        Yn = dae.topology.Yfault;
    else
        Yn = dae.topology.Ypost;
    end
    so = struct('newton_tol',1e-8,'max_iter',50,'fd_eps',3e-6, ...
        'verbose',false,'full_kcl',true,'t_now',t_now, ...
        'fd_grouping','auto','fd_y_grouping',y_grp,'fd_structure_check',false, ...
        'fd_perturbation','absolute','vcon_vars',[],'vcon_ref',[], ...
        'free_vars',1:numel(y),'free_rows',1:numel(y));
    st = stability.ts_step_composite(x, y, dt, dae, Yn, eq.u_eq, ...
        eq.equilibrium_context, asi, so);
    x = st.x_full; y = st.y_full;
    X(:,k+1) = x; Y(:,k+1) = y; resid(k) = st.residual_norm;
end
elapsed = toc(a);
end
