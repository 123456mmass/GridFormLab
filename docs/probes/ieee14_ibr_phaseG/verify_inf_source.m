function verify_inf_source()
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

    % Manual replicate mixed_equilibrium_solve
    devices = devs;
    eq_hybrid_state = stability.ts_hybrid_state_init(devices);
    eq_context = struct('hybrid_state', eq_hybrid_state);
    vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
    dae = stability.composite_dae(c, devices, struct('load_model','cz_p_cz_q','vcon',vcon));

    % Build active/frozen
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

    fprintf('nx_total=%d, active=%d, frozen=%d, local_frozen=%d\n', ...
        numel(dae.x0), numel(active_x), numel(frozen_x), numel(local_frozen));

    x0_init = dae.x0;
    for fi = 1:numel(local_frozen), x0_init(local_frozen(fi)) = local_anchor(fi); end
    for fi = 1:numel(frozen_x), x0_init(frozen_x(fi)) = frozen_xv(fi); end
    free_vars = setdiff(1:28, 2, 'stable');
    y_full = dae.y0; y_full(2) = 0; y_free = y_full(free_vars);
    z0 = [x0_init(active_x); y_free(:)];
    fprintf('nz=%d, finite z0=%d/%d\n', numel(z0), sum(isfinite(z0)), numel(z0));

    % Build residual manually
    nx = numel(active_x);
    x_full = zeros(numel(dae.x0),1);
    x_full(active_x) = z0(1:nx);
    for fi = 1:numel(all_frozen), x_full(all_frozen(fi)) = all_values(fi); end
    y_full2 = zeros(28,1); y_full2(2)=0; y_full2(free_vars) = z0(nx+1:end);

    fprintf('x_full finite=%d/%d, y_full finite=%d/%d\n', ...
        sum(isfinite(x_full)), numel(x_full), sum(isfinite(y_full2)), numel(y_full2));

    f = dae.dae_f(0, x_full, y_full2, dae.u0, eq_context);
    g = dae.dae_g(0, x_full, y_full2, dae.Ynet, dae.u0, eq_context);
    fprintf('|f|=%g, |g|=%g\n', norm(f,inf), norm(g,inf));
    fprintf('f finite=%d/%d, g finite=%d/%d\n', sum(isfinite(f)), numel(f), sum(isfinite(g)), numel(g));

    [~, idx] = sort(abs(f), 'descend');
    for k = 1:min(10, numel(f))
        if ~isfinite(f(idx(k)))
            gx = idx(k); off=0;
            for dk=1:numel(dae.devices)
                if gx <= off + dae.devices(dk).nx
                    fprintf('  non-finite f(%d)=%s[%d]=%g\n', gx, dae.devices(dk).device_id, gx-off, f(gx));
                    break;
                end
                off = off + dae.devices(dk).nx;
            end
        end
    end
    for k = 1:numel(g)
        if ~isfinite(g(k))
            fprintf('  non-finite g(%d)=%g\n', k, g(k));
        end
    end

    % Per-device current with context
    V = complex(y_full2(1:2:end), y_full2(2:2:end));
    for dk = 1:numel(dae.devices)
        dev = dae.devices(dk);
        off = dae.device_offsets(dk);
        x_dev = x_full(off+1:off+dev.nx);
        if dev.nu==0, u_dev=[]; else u_dev = dae.u0(dae.u_offsets(dk)+1:dae.u_offsets(dk)+dev.nu); end
        try
            I = dev.current_injection(0, x_dev, y_full2, u_dev, eq_context);
            fprintf('%s: |I|=%g, finite=%d\n', dev.device_id, abs(I), isfinite(I));
        catch me
            fprintf('%s: current_injection ERROR: %s\n', dev.device_id, me.message);
        end
        try
            dx = dev.f(0, x_dev, y_full2, u_dev, eq_context);
            fprintf('  |dx|=%g, finite=%d/%d\n', norm(dx,inf), sum(isfinite(dx)), numel(dx));
        catch me
            fprintf('  f ERROR: %s\n', me.message);
        end
    end
end
