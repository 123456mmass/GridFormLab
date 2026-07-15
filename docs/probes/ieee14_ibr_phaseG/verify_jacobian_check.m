function verify_jacobian_check()
    restoredefaultpath;
    addpath('C:\Users\User\Desktop\Power-flow');
    pf_init_paths();
    clear functions;

    c = cases.case_ieee14_1sg_4ibr_auto_vsg();
    modes = struct('device_id', {'IBR2','IBR3','IBR6','IBR8'}, ...
                   'mode', {'GFM','gfl','gfl','gfl'});
    disp_s = struct('IBR2', 40.0, 'IBR3', 0.0, 'IBR6', 0.0, 'IBR8', 0.0);
    devs = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
    for k = 1:numel(devs)
        if strcmp(devs(k).device_type, 'sg_emf6_composite')
            devs(k).initial_online = false; devs(k).mode = 'breaker_open';
            break;
        end
    end

    % Replicate mixed_equilibrium_solve partition
    devices = devs;
    eq_hybrid_state = stability.ts_hybrid_state_init(devices);
    eq_context = struct('hybrid_state', eq_hybrid_state);
    vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
    dae = stability.composite_dae(c, devices, struct('load_model','cz_p_cz_q','vcon',vcon));

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
    local_frozen = []; local_anchor = [];
    for dk = 1:numel(dae.devices)
        dev = dae.devices(dk);
        off = dae.device_offsets(dk);
        if isfield(dev, 'active_state_indices') && ~isempty(dev.active_state_indices)
            dev_active = dev.active_state_indices(:)';
            dev_all = 1:dev.nx;
            dev_local = setdiff(dev_all, dev_active, 'stable');
            if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
                dev_local = setdiff(dev_local, dev.frozen_state_indices(:)', 'stable');
            end
            local_frozen = [local_frozen, off + dev_local];
            local_anchor = [local_anchor, dev.x0(dev_local)'];
        end
    end
    active_x = setdiff(active_x, local_frozen, 'stable');
    all_frozen = [frozen_x, local_frozen];
    all_values = [frozen_xv, local_anchor];

    x0_init = dae.x0;
    for fi = 1:numel(local_frozen), x0_init(local_frozen(fi)) = local_anchor(fi); end
    for fi = 1:numel(frozen_x), x0_init(frozen_x(fi)) = frozen_xv(fi); end
    free_vars = setdiff(1:28, 2, 'stable');
    y_full = dae.y0; y_full(2) = 0; y_free = y_full(free_vars);
    z0 = [x0_init(active_x); y_free(:)];

    res_fn = @(z) coupled_res(z, active_x, all_frozen, all_values, free_vars, dae, eq_context);
    r0 = res_fn(z0);
    fprintf('nz=%d, |r0|=%g\n', numel(z0), norm(r0,inf));

    fd_eps = 3e-6;
    J = zeros(numel(z0));
    for j = 1:numel(z0)
        zp = z0; zp(j) = zp(j) + fd_eps;
        J(:,j) = (res_fn(zp) - r0) / fd_eps;
    end
    fprintf('rcond=%g, rank=%d/%d, NaN/Inf=%d/%d\n', rcond(J), rank(J), size(J,1), sum(~isfinite(J(:))), numel(J));
    s = svd(J);
    fprintf('Smallest 5 s: %s\n', mat2str(s(end-4:end), 3));

    % Find zero rows/cols
    row_norm = sum(abs(J), 2);
    col_norm = sum(abs(J), 1);
    fprintf('zero rows: %d, zero cols: %d\n', sum(row_norm<1e-12), sum(col_norm<1e-12));
    for j = find(col_norm < 1e-12)
        if j <= numel(active_x)
            gx = active_x(j);
            off = 0;
            for dk = 1:numel(dae.devices)
                if gx <= off + dae.devices(dk).nx
                    fprintf('  zero col x(%d)=%s[%d]\n', gx, dae.devices(dk).device_id, gx-off);
                    break;
                end
                off = off + dae.devices(dk).nx;
            end
        else
            fprintf('  zero col y(%d)\n', free_vars(j - numel(active_x)));
        end
    end
    for j = find(row_norm < 1e-12)
        fprintf('  zero row %d (residual index)\n', j);
    end
end

function r = coupled_res(z, active_x, frozen_x, frozen_xv, free_vars, dae, eq_context)
    nx = numel(active_x);
    x_full = zeros(numel(dae.x0),1);
    x_full(active_x) = z(1:nx);
    for fi = 1:numel(frozen_x), x_full(frozen_x(fi)) = frozen_xv(fi); end
    y_full = zeros(28,1); y_full(2)=0; y_full(free_vars) = z(nx+1:end);
    f = dae.dae_f(0, x_full, y_full, dae.u0, eq_context);
    g = dae.dae_g(0, x_full, y_full, dae.Ynet, dae.u0, eq_context);
    free_rows = setdiff(1:numel(g), dae.vcon.rows, 'stable');
    r = [f(active_x); g(free_rows)];
end
