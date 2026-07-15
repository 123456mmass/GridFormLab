function verify_pinv_fix3()
    restoredefaultpath;
    addpath('C:\Users\User\Desktop\Power-flow');
    pf_init_paths();
    clear functions;

    c = cases.case_ieee14_1sg_4ibr_auto_vsg();
    modes = struct('device_id', {'IBR2','IBR3','IBR6','IBR8'}, ...
                   'mode', {'GFM','gfl','gfl','gfl'});
    disp_s = struct('IBR2', 109.7, 'IBR3', 49.8, 'IBR6', 49.8, 'IBR8', 49.8);
    devs = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
    for k = 1:numel(devs)
        if strcmp(devs(k).device_type, 'sg_emf6_composite')
            devs(k).initial_online = false;
            devs(k).mode = 'breaker_open';
            break;
        end
    end

    % Check frozen_state fields on each device BEFORE composite_dae
    fprintf('=== Pre-DAE frozen states ===\n');
    for k = 1:numel(devs)
        d = devs(k);
        fprintf('%s: frozen=%s, active=%s, nx=%d\n', ...
            d.device_id, mat2str(d.frozen_state_indices), mat2str(d.active_state_indices), d.nx);
    end

    % Build DAE
    vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
    dae = stability.composite_dae(c, devs, struct('load_model','cz_p_cz_q','vcon',vcon));

    % Check frozen_state fields AFTER composite_dae
    fprintf('\n=== Post-DAE frozen states ===\n');
    for k = 1:numel(dae.devices)
        d = dae.devices(k);
        fprintf('%s: frozen=%s, active=%s, nx=%d\n', ...
            d.device_id, mat2str(d.frozen_state_indices), mat2str(d.active_state_indices), d.nx);
    end

    % Count frozen states by the same logic as mixed_equilibrium_solve
    frozen_x_indices = [];
    active_x_indices = 1:numel(dae.x0);
    for dk = 1:numel(dae.devices)
        dev = dae.devices(dk);
        if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
            off = dae.device_offsets(dk);
            fsi = dev.frozen_state_indices(:)';
            frozen_x_indices = [frozen_x_indices, off + fsi];
        end
    end
    active_x_indices = setdiff(active_x_indices, frozen_x_indices, 'stable');
    fprintf('\n=== Newton system size ===\n');
    fprintf('nx_total=%d, nx_frozen=%d, nx_active=%d\n', ...
        numel(dae.x0), numel(frozen_x_indices), numel(active_x_indices));
    ny_free = 28 - 1;  % vcon fixes y(2), 27 free
    fprintf('nz = nx_active + ny_free = %d + %d = %d\n', ...
        numel(active_x_indices), ny_free, numel(active_x_indices)+ny_free);

    % Run the solver
    config = struct('devices', devs);
    fprintf('\n=== Running equilibrium ===\n');
    r = stability.mixed_equilibrium_solve(c, config, struct('verbose', true));
    fprintf('\nconverged=%d, residual=%.6g, rcond=%.6g, iter=%d\n', ...
        r.converged, r.residual_norm, r.rcond, r.iterations);
end
