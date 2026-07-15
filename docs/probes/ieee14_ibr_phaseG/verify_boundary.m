function verify_boundary()
    restoredefaultpath;
    addpath('C:\Users\User\Desktop\Power-flow');
    pf_init_paths();
    clear functions;

    for P_gfm = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 109.7]
        c = cases.case_ieee14_1sg_4ibr_auto_vsg();
        modes = struct('device_id', {'IBR2','IBR3','IBR6','IBR8'}, ...
                       'mode', {'GFM','gfl','gfl','gfl'});
        disp_s = struct('IBR2', P_gfm, 'IBR3', 49.8, 'IBR6', 49.8, 'IBR8', 49.8);
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
        fprintf('P_gfm=%6.2f -> conv=%d, res=%.6g, rcond=%.6g, iter=%d, %s\n', ...
            P_gfm, r.converged, r.residual_norm, r.rcond, r.iterations, r.failure_reason);
    end
end
