function verify_baseline()
    restoredefaultpath;
    addpath('C:\Users\User\Desktop\Power-flow');
    pf_init_paths();
    clear functions;

    % Test 1: SG online + 4 GFL at 40/0/0/0 (known-passing Phase4 baseline)
    c = cases.case_ieee14_1sg_4ibr_auto_vsg();
    modes = struct('device_id', {'IBR2','IBR3','IBR6','IBR8'}, ...
                   'mode', {'gfl','gfl','gfl','gfl'});
    disp_s = struct('IBR2', 40.0, 'IBR3', 0.0, 'IBR6', 0.0, 'IBR8', 0.0);
    devs = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
    r = stability.mixed_equilibrium_solve(c, struct('devices', devs), struct('verbose', true));
    fprintf('SG_ON+4GFL: conv=%d, res=%.6g, rcond=%.6g, iter=%d\n', ...
        r.converged, r.residual_norm, r.rcond, r.iterations);

    % Test 2: SG off + GFM at 40/0/0/0 (low GFM dispatch)
    devs2 = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
    for k = 1:numel(devs2)
        if strcmp(devs2(k).device_type, 'sg_emf6_composite')
            devs2(k).initial_online = false;
            devs2(k).mode = 'breaker_open';
            break;
        end
    end
    r2 = stability.mixed_equilibrium_solve(c, struct('devices', devs2), struct('verbose', true));
    fprintf('SG_OFF+GFM(40): conv=%d, res=%.6g, rcond=%.6g, iter=%d\n', ...
        r2.converged, r2.residual_norm, r2.rcond, r2.iterations);
end
