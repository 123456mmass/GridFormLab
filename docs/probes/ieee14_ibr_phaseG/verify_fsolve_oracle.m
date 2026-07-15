function verify_fsolve_oracle()
    restoredefaultpath;
    addpath('C:\Users\User\Desktop\Power-flow');
    pf_init_paths();
    clear functions;

    c = cases.case_ieee14_1sg_4ibr_auto_vsg();
    modes = struct('device_id', {'IBR2','IBR3','IBR6','IBR8'}, ...
                   'mode', {'GFM','gfl','gfl','gfl'});
    disp_s = struct('IBR2', 109.7, 'IBR3', 49.8, 'IBR6', 49.8, 'IBR8', 49.8);
    devs = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
    for k = 1:numel(devs)
        if strcmp(devs(k).device_type, 'sg_emf6_composite')
            devs(k).initial_online = false; devs(k).mode = 'breaker_open';
            break;
        end
    end
    vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
    dae = stability.composite_dae(c, devs, struct('load_model','cz_p_cz_q','vcon',vcon));

    frozen_x = []; frozen_xv = []; active_x = 1:numel(dae.x0);
    for dk = 1:numel(dae.devices)
        dev = dae.devices(dk);
        if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
            off = dae.device_offsets(dk);
            frozen_x = [frozen_x, off + dev.frozen_state_indices(:)'];
            frozen_xv = [frozen_xv, dev.frozen_state_values(:)'];
        end
    end
    active_x = setdiff(active_x, frozen_x, 'stable');
    free_y = setdiff(1:28, 2, 'stable');

    res_fn = @(z) eq_res(z, active_x, frozen_x, frozen_xv, free_y, vcon, dae);
    z0 = [dae.x0(active_x); dae.y0(free_y)];

    opts = optimoptions('fsolve', 'Display','iter-detailed', 'MaxIterations', 200, ...
        'MaxFunctionEvaluations', 10000, 'Algorithm','trust-region-dogleg', ...
        'FunctionTolerance', 1e-8, 'StepTolerance', 1e-8);
    try
        [z_sol, fval, exitflag, output] = fsolve(res_fn, z0, opts);
        fprintf('fsolve exitflag=%d, |res|=%.6g, iter=%d\n', exitflag, norm(fval,inf), output.iterations);
    catch me
        fprintf('fsolve error: %s\n', me.message);
    end
end

function r = eq_res(z, active_x, frozen_x, frozen_xv, free_y, vcon, dae)
    nx = numel(active_x);
    x_full = zeros(numel(dae.x0), 1);
    x_full(active_x) = z(1:nx);
    for fi = 1:numel(frozen_x), x_full(frozen_x(fi)) = frozen_xv(fi); end
    y_full = zeros(28,1); y_full(vcon.vars) = vcon.ref; y_full(free_y) = z(nx+1:end);
    ec = struct();
    f = dae.dae_f(0, x_full, y_full, dae.u0, ec);
    g = dae.dae_g(0, x_full, y_full, dae.Ynet, dae.u0, ec);
    free_rows = setdiff(1:numel(g), dae.vcon.rows, 'stable');
    r = [f(active_x); g(free_rows)];
end
