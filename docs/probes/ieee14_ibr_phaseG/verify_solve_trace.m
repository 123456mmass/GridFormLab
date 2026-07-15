function verify_solve_trace()
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

    try
        r = stability.mixed_equilibrium_solve(c, config, struct('verbose', true));
        fprintf('Result: conv=%d, res=%g, rcond=%g, iter=%d\n', ...
            r.converged, r.residual_norm, r.rcond, r.iterations);
        fprintf('failure_id=%s\n', r.failure_id);
        fprintf('failure_reason=%s\n', r.failure_reason);
    catch me
        fprintf('ERROR: %s\n', me.message);
        fprintf('Stack:\n');
        for k = 1:numel(me.stack)
            fprintf('  %s:%d %s\n', me.stack(k).file, me.stack(k).line, me.stack(k).name);
        end
    end
end
