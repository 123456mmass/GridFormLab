function verify_continuation()
    restoredefaultpath;
    addpath('C:\Users\User\Desktop\Power-flow');
    pf_init_paths();
    clear functions;

    c = cases.case_ieee14_1sg_4ibr_auto_vsg();
    modes = struct('device_id', {'IBR2','IBR3','IBR6','IBR8'}, ...
                   'mode', {'GFM','gfl','gfl','gfl'});

    % Try to find ANY converged SG_OFF+GFM case
    target = 109.7;
    best = [];
    for P_gfm = [1, 2, 5, 10, 15, 20, 25, 30]
        disp_s = struct('IBR2', P_gfm, 'IBR3', 49.8, 'IBR6', 49.8, 'IBR8', 49.8);
        devs = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
        for k = 1:numel(devs)
            if strcmp(devs(k).device_type, 'sg_emf6_composite')
                devs(k).initial_online = false; devs(k).mode = 'breaker_open';
                break;
            end
        end
        r = stability.mixed_equilibrium_solve(c, struct('devices', devs), struct('verbose', false));
        fprintf('P=%5.1f -> conv=%d, res=%.6g, rcond=%.6g, iter=%d\n', ...
            P_gfm, r.converged, r.residual_norm, r.rcond, r.iterations);
        if r.converged && (isempty(best) || r.residual_norm < best.residual_norm)
            best = r; best.P = P_gfm; best.devs = devs;
        end
    end

    if isempty(best)
        fprintf('No converged SG_OFF+GFM case found at low dispatch.\n');
        return;
    end

    % Continuation: ramp P_gfm from best.P to target using converged (x0,y0) as warm-start
    fprintf('\nContinuation from P=%.1f to %.1f\n', best.P, target);
    disp_s = struct('IBR2', best.P, 'IBR3', 49.8, 'IBR6', 49.8, 'IBR8', 49.8);
    devs = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
    for k = 1:numel(devs)
        if strcmp(devs(k).device_type, 'sg_emf6_composite')
            devs(k).initial_online = false; devs(k).mode = 'breaker_open';
            break;
        end
    end
    dae = stability.composite_dae(c, devs, struct('load_model','cz_p_cz_q'));
    x0 = best.x0; y0 = best.y0;

    Pvals = [best.P:5:target, target];
    for P_gfm = Pvals
        disp_s = struct('IBR2', P_gfm, 'IBR3', 49.8, 'IBR6', 49.8, 'IBR8', 49.8);
        devs = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
        for k = 1:numel(devs)
            if strcmp(devs(k).device_type, 'sg_emf6_composite')
                devs(k).initial_online = false; devs(k).mode = 'breaker_open';
                break;
            end
        end
        % Rebuild DAE with new devices and use previous (x0,y0) as warm-start
        dae = stability.composite_dae(c, devs, struct('load_model','cz_p_cz_q'));
        % Need to map x0/y0 to new device ordering (same here) and sizes
        if numel(x0) == numel(dae.x0) && numel(y0) == numel(dae.y0)
            dae.x0 = x0; dae.y0 = y0;
        end
        r = stability.mixed_equilibrium_solve(c, struct('devices', devs), struct('verbose', false));
        fprintf('  P=%6.1f -> conv=%d, res=%.6g, rcond=%.6g, iter=%d\n', ...
            P_gfm, r.converged, r.residual_norm, r.rcond, r.iterations);
        if ~r.converged, break; end
        x0 = r.x0; y0 = r.y0;
    end
end
