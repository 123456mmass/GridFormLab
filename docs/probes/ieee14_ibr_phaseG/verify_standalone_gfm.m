function verify_standalone_gfm()
    restoredefaultpath;
    addpath('C:\Users\User\Desktop\Power-flow');
    pf_init_paths();
    clear functions;

    c = cases.case_ieee14_1sg_4ibr_auto_vsg();
    bus_ids = c.mpc.bus(:,1)';
    V0 = 1.04 + 0i;

    % Build standalone GFM devices (no dual-mode wrapper)
    devs = struct('name',{},'device_id',{},'bus_id',{},'bus_position',{}, ...
                  'bus_ids',{},'device_type',{},'mode',{},'initial_mode',{}, ...
                  'initial_online',{},'nx',{},'nu',{},'state_names',{}, ...
                  'input_names',{},'x0',{},'u0',{},'f',{}, ...
                  'current_injection',{},'electrical_power',{},'reconstruct',{}, ...
                  'frozen_state_indices',{},'frozen_state_values',{}, ...
                  'frozen_state_source',{},'active_state_indices',{}, ...
                  'frozen_state_classification',{},'provenance',{});

    % SG1 offline (tripped)
    sg = stability.sg_composite_device('SG1', 1, 1, bus_ids, V0, c.machines);
    sg.initial_online = false;
    sg.mode = 'breaker_open';
    devs(1) = sg;

    % IBR2 as standalone GFM
    devs(2) = ibr.regfm_b1_vsg_model('IBR2', 2, 2, bus_ids, V0, struct('Mbase',140), 1.097, 1.045);
    % IBR3/6/8 as standalone GFL
    devs(3) = ibr.gfl_model('IBR3', 3, 3, bus_ids, V0, struct(), 0.498, 0);
    devs(4) = ibr.gfl_model('IBR6', 6, 6, bus_ids, V0, struct(), 0.498, 0);
    devs(5) = ibr.gfl_model('IBR8', 8, 8, bus_ids, V0, struct(), 0.498, 0);

    config = struct('devices', devs);
    r = stability.mixed_equilibrium_solve(c, config, struct('verbose', true));
    fprintf('\nStandalone GFM: conv=%d, res=%.6g, rcond=%.6g, iter=%d\n', ...
        r.converged, r.residual_norm, r.rcond, r.iterations);
end
