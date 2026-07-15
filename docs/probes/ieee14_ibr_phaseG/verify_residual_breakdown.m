function verify_residual_breakdown()
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
    config = struct('devices', devs);
    r = stability.mixed_equilibrium_solve(c, config, struct('verbose', false));

    fprintf('Converged=%d, residual=%.6g, rcond=%.6g, iter=%d\n', ...
        r.converged, r.residual_norm, r.rcond, r.iterations);

    if ~r.converged
        % Rebuild DAE and evaluate residual at final x/y
        vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
        dae = stability.composite_dae(c, devs, struct('load_model','cz_p_cz_q','vcon',vcon));
        ec = struct();
        fprintf('r.x0 size=%d, dae nx_total=%d; r.y0 size=%d, dae ny=%d\n', ...
            numel(r.x0), numel(dae.x0), numel(r.y0), numel(dae.y0));
        f = dae.dae_f(0, r.x0, r.y0, dae.u0, ec);
        g = dae.dae_g(0, r.x0, r.y0, dae.Ynet, dae.u0, ec);

        % Active vs frozen
        frozen_x = []; active_x = 1:numel(r.x0);
        for dk = 1:numel(dae.devices)
            dev = dae.devices(dk);
            if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
                frozen_x = [frozen_x, dae.device_offsets(dk) + dev.frozen_state_indices(:)'];
            end
        end
        active_x = setdiff(active_x, frozen_x, 'stable');

        fprintf('\nActive-state f residuals at final state:\n');
        [~, idx] = sort(abs(f(active_x)), 'descend');
        for k = 1:min(15, numel(active_x))
            gx = active_x(idx(k));
            off = 0;
            for dk = 1:numel(dae.devices)
                if gx <= off + dae.devices(dk).nx
                    fprintf('  f(%d)=%s[%d] = %.6g\n', gx, dae.devices(dk).device_id, gx-off, f(gx));
                    break;
                end
                off = off + dae.devices(dk).nx;
            end
        end

        fprintf('\nAlgebraic g residuals at final state (free rows):\n');
        free_rows = setdiff(1:28, 2, 'stable');
        [~, idx] = sort(abs(g(free_rows)), 'descend');
        for k = 1:min(15, numel(free_rows))
            row = free_rows(idx(k));
            bus = ceil(row/2);
            type = 'real'; if mod(row,2)==0, type='imag'; end
            fprintf('  g(%d) bus%d %s = %.6g\n', row, bus, type, g(row));
        end

        % Per-device power and current
        fprintf('\nPer-device injection at final state:\n');
        V = complex(r.y0(1:2:end), r.y0(2:2:end));
        for dk = 1:numel(dae.devices)
            dev = dae.devices(dk);
            off = dae.device_offsets(dk);
            x_dev = r.x0(off+1:off+dev.nx);
            I = dev.current_injection(0, x_dev, r.y0, [], ec);
            S = V(dev.bus_position) * conj(I);
            fprintf('  %s: |V|=%.4g, |I|=%.4g, P=%.4g, Q=%.4g\n', ...
                dev.device_id, abs(V(dev.bus_position)), abs(I), real(S)*100, imag(S)*100);
        end
    end
end
