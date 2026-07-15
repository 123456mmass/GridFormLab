function verify_stall_balance()
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
    config = struct('devices', devs);
    r = stability.mixed_equilibrium_solve(c, config, struct('verbose', false));

    % Rebuild DAE with same config
    vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
    dae = stability.composite_dae(c, devs, struct('load_model','cz_p_cz_q','vcon',vcon));

    % r.x0/r.y0 may be empty if not converged; use z_sol manually
    % Get z_sol from the solver via a small helper (we can't access internals)
    % Instead, manually run Newton to the stalled point using the same logic.
    frozen_x_indices = []; frozen_x_values = []; active_x_indices = 1:numel(dae.x0);
    for dk = 1:numel(dae.devices)
        dev = dae.devices(dk);
        if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
            off = dae.device_offsets(dk);
            frozen_x_indices = [frozen_x_indices, off + dev.frozen_state_indices(:)'];
            frozen_x_values  = [frozen_x_values, dev.frozen_state_values(:)'];
        end
    end
    active_x_indices = setdiff(active_x_indices, frozen_x_indices, 'stable');
    free_vars = setdiff(1:28, 2, 'stable');
    z0 = [dae.x0(active_x_indices); dae.y0(free_vars)];

    residual_fn = @(z) eq_res(z, active_x_indices, frozen_x_indices, frozen_x_values, free_vars, dae);
    J_fn = @(z) eq_jac(z, residual_fn);
    [z_sol, ~, ~, ~, ~] = stability.composite_newton(z0, residual_fn, J_fn, 1e-8, 50, false);

    % Build full x/y at stalled point
    nx_active = numel(active_x_indices);
    x_full = zeros(numel(dae.x0),1); x_full(active_x_indices) = z_sol(1:nx_active);
    for fi = 1:numel(frozen_x_indices), x_full(frozen_x_indices(fi)) = frozen_x_values(fi); end
    y_full = zeros(28,1); y_full(2) = 0; y_full(free_vars) = z_sol(nx_active+1:end);

    ec = struct();
    f = dae.dae_f(0, x_full, y_full, dae.u0, ec);
    g = dae.dae_g(0, x_full, y_full, dae.Ynet, dae.u0, ec);
    free_rows = setdiff(1:28, 2, 'stable');
    fa = f(active_x_indices); gr = g(free_rows);

    fprintf('Stalled |f_active|=%.6g, |g_free|=%.6g\n', norm(fa,inf), norm(gr,inf));

    fprintf('\nTop 10 active-state f residuals:\n');
    [~, idx] = sort(abs(fa), 'descend');
    for k = 1:min(10, numel(fa))
        gx = active_x_indices(idx(k));
        off = 0;
        for dk = 1:numel(dae.devices)
            if gx <= off + dae.devices(dk).nx
                fprintf('  f(%d)=%s[%d] = %.6g\n', gx, dae.devices(dk).device_id, gx-off, fa(idx(k)));
                break;
            end
            off = off + dae.devices(dk).nx;
        end
    end

    fprintf('\nTop 10 algebraic g residuals:\n');
    [~, idx] = sort(abs(gr), 'descend');
    for k = 1:min(10, numel(gr))
        row = free_rows(idx(k));
        fprintf('  g(%d) bus%d %s = %.6g\n', row, ceil(row/2), ternary(mod(row,2)==1,'real','imag'), gr(idx(k)));
    end

    % Per-device summary
    V = complex(y_full(1:2:end), y_full(2:2:end));
    fprintf('\nPer-device at stalled point:\n');
    for dk = 1:numel(dae.devices)
        dev = dae.devices(dk);
        off = dae.device_offsets(dk);
        x_dev = x_full(off+1:off+dev.nx);
        I = dev.current_injection(0, x_dev, y_full, [], ec);
        S = V(dev.bus_position) * conj(I);
        fprintf('  %s: |V|=%.4g |I|=%.4g P=%.4g Q=%.4g\n', ...
            dev.device_id, abs(V(dev.bus_position)), abs(I), real(S)*100, imag(S)*100);
    end

    % Network balance
    fprintf('\nNetwork KCL residual magnitude at each bus:\n');
    for b = 1:14
        row_r = 2*b-1; row_i = 2*b;
        fprintf('  bus %2d: |g|=%.4g (real=%.4g, imag=%.4g)\n', ...
            b, sqrt(g(row_r)^2+g(row_i)^2), g(row_r), g(row_i));
    end
end

function r = eq_res(z, active_x, frozen_x, frozen_xv, free_y, dae)
    nx = numel(active_x);
    x_full = zeros(numel(dae.x0), 1);
    x_full(active_x) = z(1:nx);
    for fi = 1:numel(frozen_x), x_full(frozen_x(fi)) = frozen_xv(fi); end
    y_full = zeros(28,1); y_full(2) = 0; y_full(free_y) = z(nx+1:end);
    ec = struct();
    f = dae.dae_f(0, x_full, y_full, dae.u0, ec);
    g = dae.dae_dae_g(0, x_full, y_full, dae.Ynet, dae.u0, ec);
    free_rows = setdiff(1:numel(g), dae.vcon.rows, 'stable');
    r = [f(active_x); g(free_rows)];
end

function J = eq_jac(z, residual_fn)
    nz = numel(z); r0 = residual_fn(z); J = zeros(nz,nz);
    for j = 1:nz
        zp = z; zp(j) = zp(j) + 3e-6;
        J(:,j) = (residual_fn(zp) - r0) / 3e-6;
    end
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
