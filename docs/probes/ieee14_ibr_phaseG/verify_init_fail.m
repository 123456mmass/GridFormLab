function verify_init_fail()
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

    % Manually walk through mixed_equilibrium_solve
    config = struct('devices', devs);
    tol = 1e-8; max_iter = 300; fd_eps = 3e-6;
    vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);

    try
        dae = stability.composite_dae(c, devs, struct('load_model','cz_p_cz_q','vcon',vcon));
        fprintf('composite_dae OK\n');
    catch me
        fprintf('composite_dae FAILED: %s\n', me.message);
        return;
    end

    % initialize_device_states (line 129)
    try
        [x0_init, init_ok, init_msg] = stability.mixed_equilibrium_solve(c, config, struct('verbose',true));
        % This calls the whole function; instead let's directly test sub-functions
    catch me
        fprintf('mixed_equilibrium_solve FAILED: %s\n', me.message);
    end

    % Re-evaluate frozen-state validation manually
    fprintf('\nManual frozen-state validation:\n');
    x0_init = dae.x0;
    for dk = 1:numel(dae.devices)
        dev = dae.devices(dk);
        if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
            off = dae.device_offsets(dk);
            for fi = 1:numel(dev.frozen_state_indices)
                gidx = off + dev.frozen_state_indices(fi);
                expected_val = dev.frozen_state_values(fi);
                actual_val = x0_init(gidx);
                if abs(actual_val - expected_val) > 1e-12
                    fprintf('MISMATCH %s frozen[%d]: expected %.15g, got %.15g\n', ...
                        dev.device_id, dev.frozen_state_indices(fi), expected_val, actual_val);
                end
            end
        end
    end

    % Test direct Newton entry
    fprintf('\nDirect Newton test:\n');
    frozen_x_indices = [];
    frozen_x_values = [];
    active_x_indices = 1:numel(x0_init);
    for dk = 1:numel(dae.devices)
        dev = dae.devices(dk);
        if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
            off = dae.device_offsets(dk);
            fsi = dev.frozen_state_indices(:)';
            fsv = dev.frozen_state_values(:)';
            frozen_x_indices = [frozen_x_indices, off + fsi];
            frozen_x_values  = [frozen_x_values, fsv];
        end
    end
    active_x_indices = setdiff(active_x_indices, frozen_x_indices, 'stable');
    fprintf('nx_total=%d, nx_active=%d, nx_frozen=%d\n', numel(x0_init), numel(active_x_indices), numel(frozen_x_indices));

    y0 = dae.y0;
    ny_full = numel(y0);
    free_vars = setdiff(1:ny_full, 2, 'stable');
    y_full_init = y0;
    y_full_init(2) = 0;
    y_free_init = y_full_init(free_vars);
    z0 = [x0_init(active_x_indices); y_free_init(:)];
    fprintf('nz=%d, ||z0||=%g, finite=%d/%d\n', numel(z0), norm(z0), sum(isfinite(z0)), numel(z0));

    % Assemble residual fn
    residual_fn = @(z) coupled_residual(z, active_x_indices, frozen_x_indices, frozen_x_values, ...
        free_vars, 2, 0.0, ny_full, dae, dae.Ynet, dae.u0);
    r0 = residual_fn(z0);
    fprintf('||r0||=%g, finite=%d/%d\n', norm(r0,inf), sum(isfinite(r0)), numel(r0));

    J_fn = @(z) coupled_jacobian_fd(z, residual_fn, fd_eps);
    J0 = J_fn(z0);
    fprintf('rcond(J0)=%g, finite=%d/%d\n', rcond(J0), sum(isfinite(J0(:))), numel(J0));
end

function r = coupled_residual(z, active_x_indices, frozen_x_indices, frozen_x_values, ...
    free_vars, vcon_vars, vcon_ref, ny_full, dae, Y, u)
nx_active = numel(active_x_indices);
x_full = zeros(numel(dae.x0), 1);
x_full(active_x_indices) = z(1:nx_active);
for fi = 1:numel(frozen_x_indices)
    x_full(frozen_x_indices(fi)) = frozen_x_values(fi);
end
y_full = zeros(ny_full, 1);
y_full(vcon_vars) = vcon_ref;
y_full(free_vars) = z(nx_active+1:end);
ec = struct();
f = dae.dae_f(0, x_full, y_full, u, ec);
g = dae.dae_g(0, x_full, y_full, Y, u, ec);
free_rows = setdiff(1:numel(g), dae.vcon.rows, 'stable');
r = [f(active_x_indices); g(free_rows)];
end

function J = coupled_jacobian_fd(z, residual_fn, fd_eps)
nz = numel(z);
r0 = residual_fn(z);
J = zeros(nz, nz);
for j = 1:nz
    zp = z; zp(j) = zp(j) + fd_eps;
    rp = residual_fn(zp);
    J(:,j) = (rp - r0) / fd_eps;
end
end
