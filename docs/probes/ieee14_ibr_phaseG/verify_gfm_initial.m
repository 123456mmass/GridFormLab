function verify_gfm_initial()
    restoredefaultpath;
    addpath('C:\Users\User\Desktop\Power-flow');
    pf_init_paths();
    clear functions;

    c = cases.case_ieee14_1sg_4ibr_auto_vsg();
    modes = struct('device_id', {'IBR2','IBR3','IBR6','IBR8'}, ...
                   'mode', {'GFM','tripped','tripped','tripped'});
    disp_s = struct('IBR2', 109.7, 'IBR3', 0, 'IBR6', 0, 'IBR8', 0);
    devs = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
    for k = 1:numel(devs)
        if strcmp(devs(k).device_type, 'sg_emf6_composite')
            devs(k).initial_online = false; devs(k).mode = 'breaker_open';
            break;
        end
    end
    vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
    dae = stability.composite_dae(c, devs, struct('load_model','cz_p_cz_q','vcon',vcon));

    x0 = dae.x0; y0 = dae.y0; u = dae.u0; Y = dae.Ynet;
    ec = struct();
    f = dae.dae_f(0, x0, y0, u, ec);
    g = dae.dae_g(0, x0, y0, Y, u, ec);

    fprintf('Initial residual magnitudes:\n');
    fprintf('|f|_inf=%.6g, |g|_inf=%.6g\n', norm(f,inf), norm(g,inf));

    fprintf('\nPer-device initial state and injection:\n');
    V = complex(y0(1:2:end), y0(2:2:end));
    for dk = 1:numel(dae.devices)
        dev = dae.devices(dk);
        off = dae.device_offsets(dk);
        x_dev = x0(off+1:off+dev.nx);
        fprintf('\n%s: online=%d, mode=%s, nx=%d\n', dev.device_id, dev.initial_online, dev.mode, dev.nx);
        fprintf('  x0 = ['); fprintf('%.4g ', x_dev); fprintf(']\n');
        if dev.initial_online
            I = dev.current_injection(0, x_dev, y0, [], ec);
            S = V(dev.bus_position) * conj(I);
            fprintf('  |V|=%.4g, |I|=%.4g, P=%.4g MW, Q=%.4g MVAr\n', ...
                abs(V(dev.bus_position)), abs(I), real(S)*100, imag(S)*100);
        end
    end

    fprintf('\nBus voltages from warm-start PF:\n');
    for b = 1:14
        fprintf('  bus %2d: |V|=%.4g, ang=%.4g deg\n', b, abs(V(b)), angle(V(b))*180/pi);
    end

    fprintf('\nTop f residuals:\n');
    [~, idx] = sort(abs(f), 'descend');
    for k = 1:min(10, numel(f))
        gx = idx(k);
        off = 0;
        for dk = 1:numel(dae.devices)
            if gx <= off + dae.devices(dk).nx
                fprintf('  f(%d)=%s[%d] = %.6g\n', gx, dae.devices(dk).device_id, gx-off, f(gx));
                break;
            end
            off = off + dae.devices(dk).nx;
        end
    end
end
