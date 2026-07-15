function verify_nan()
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
            devs(k).initial_online = false;
            devs(k).mode = 'breaker_open';
            break;
        end
    end
    vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
    dae = stability.composite_dae(c, devs, struct('load_model','cz_p_cz_q','vcon',vcon));

    % Check x0 has any NaN/Inf
    fprintf('x0 finite: %d/%d\n', sum(isfinite(dae.x0)), numel(dae.x0));
    fprintf('y0 finite: %d/%d\n', sum(isfinite(dae.y0)), numel(dae.y0));

    % Evaluate residual once
    ec = struct();
    f = dae.dae_f(0, dae.x0, dae.y0, dae.u0, ec);
    g = dae.dae_g(0, dae.x0, dae.y0, dae.Ynet, dae.u0, ec);
    fprintf('f finite: %d/%d, g finite: %d/%d\n', ...
        sum(isfinite(f)), numel(f), sum(isfinite(g)), numel(g));

    % Find non-finite f/g
    for k = 1:numel(f)
        if ~isfinite(f(k))
            fprintf('f(%d) = %g\n', k, f(k));
        end
    end
    for k = 1:numel(g)
        if ~isfinite(g(k))
            fprintf('g(%d) = %g\n', k, g(k));
        end
    end

    % Per-device current injection
    for dk = 1:numel(dae.devices)
        dev = dae.devices(dk);
        off = dae.device_offsets(dk);
        x_dev = dae.x0(off+1:off+dev.nx);
        fprintf('Device %s: x_dev finite=%d/%d\n', dev.device_id, sum(isfinite(x_dev)), numel(x_dev));
        try
            I = dev.current_injection(0, x_dev, dae.y0, [], struct());
            fprintf('  |I|=%.6g, finite=%d\n', abs(I), isfinite(I));
        catch me
            fprintf('  current_injection error: %s\n', me.message);
        end
        try
            dx = dev.f(0, x_dev, dae.y0, [], struct());
            fprintf('  dx finite=%d/%d\n', sum(isfinite(dx)), numel(dx));
        catch me
            fprintf('  f error: %s\n', me.message);
        end
    end
end
