function verify_deep_eq()
    restoredefaultpath;
    addpath('C:\Users\User\Desktop\Power-flow');
    pf_init_paths();

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
    vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
    dae = stability.composite_dae(c, devs, struct('load_model','cz_p_cz_q','vcon',vcon));

    % Active-only Newton system (matching mixed_equilibrium_solve)
    frozen_x_indices = [];
    for dk = 1:numel(dae.devices)
        dev = dae.devices(dk);
        if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
            off = dae.device_offsets(dk);
            frozen_x_indices = [frozen_x_indices, off + dev.frozen_state_indices(:)'];
        end
    end
    active_x_indices = setdiff(1:numel(dae.x0), frozen_x_indices, 'stable');
    vcon_vars = 2; vcon_ref = 0;
    free_vars = setdiff(1:28, vcon_vars, 'stable');

    nx_active = numel(active_x_indices);
    ny_free = numel(free_vars);
    z0 = [dae.x0(active_x_indices); dae.y0(free_vars)];
    nz = numel(z0);

    % Residual
    r0 = eq_res(z0, active_x_indices, frozen_x_indices, free_vars, vcon_vars, vcon_ref, dae);
    fprintf('||r0||_inf = %.6g, nz=%d\n', norm(r0, inf), nz);

    % Top f residuals
    fprintf('\nTop 10 |fa|:\n');
    [~, idx] = sort(abs(r0(1:nx_active)), 'descend');
    for k = 1:min(10, nx_active)
        gx = active_x_indices(idx(k));
        off = 0;
        for dk = 1:numel(dae.devices)
            if gx <= off + dae.devices(dk).nx
                fprintf('  f(%d)=%s[%d] = %.6g\n', gx, dae.devices(dk).device_id, gx-off, r0(idx(k)));
                break;
            end
            off = off + dae.devices(dk).nx;
        end
    end

    % Top g residuals
    fprintf('\nTop 10 |g|:\n');
    [~, idx] = sort(abs(r0(nx_active+1:end)), 'descend');
    for k = 1:min(10, ny_free)
        fprintf('  g(%d) = %.6g\n', free_vars(idx(k)), r0(nx_active+idx(k)));
    end

    % FD Jacobian
    fd_eps = 3e-6;
    J = zeros(nz, nz);
    for j = 1:nz
        zp = z0; zp(j) = zp(j) + fd_eps;
        rp = eq_res(zp, active_x_indices, frozen_x_indices, free_vars, vcon_vars, vcon_ref, dae);
        J(:,j) = (rp - r0) / fd_eps;
    end
    fprintf('\nFD Jacobian: rcond=%.6g, NaN/Inf=%d/%d\n', rcond(J), sum(~isfinite(J(:))), numel(J));
    [~, S, ~] = svd(J); s = diag(S);
    fprintf('Smallest 5 singular values: %s\n', mat2str(s(end-4:end), 3));
    fprintf('s_max=%.3g, s_min=%.3g, kappa=%.3g\n', s(1), s(end), s(1)/s(end));

    % Newton step test
    dz = -(J \ r0);
    z1 = z0 + dz;
    r1 = eq_res(z1, active_x_indices, frozen_x_indices, free_vars, vcon_vars, vcon_ref, dae);
    fprintf('\nFull Newton step: ||r1||=%.6g (was %.6g)\n', norm(r1,inf), norm(r0,inf));
    if norm(r1,inf) >= norm(r0,inf)
        fprintf('FULL STEP INCREASES RESIDUAL (needs damping)\n');
    end

    % Damped step
    alpha = 1.0;
    for ls = 1:20
        zt = z0 + alpha*dz;
        rt = eq_res(zt, active_x_indices, frozen_x_indices, free_vars, vcon_vars, vcon_ref, dae);
        if all(isfinite(rt)) && norm(rt,inf) < norm(r0,inf)
            fprintf('Damped step: alpha=%.6f, ||rt||=%.6g\n', alpha, norm(rt,inf));
            break;
        end
        alpha = alpha * 0.5;
    end

    % SVD analysis of Newton direction
    fprintf('\nNewton direction projection onto singular vectors:\n');
    z_mag = zeros(min(nz,5), 1);
    for k = 1:min(nz,5)
        z_mag(k) = abs(dz' * (J' * J) * V(:,end-k+1)) / s(end-k+1);
    end
    fprintf('%s\n', mat2str(z_mag, 3));

    % Check clamp state at initial point
    fprintf('\n=== Clamp state at x0 ===\n');
    for dk = 1:numel(dae.devices)
        dev = dae.devices(dk);
        if ~strcmp(dev.device_type, 'ibr_dual_mode'), continue; end
        off = dae.device_offsets(dk);
        x_dev = dae.x0(off+1:off+dev.nx);
        u_dev = dev.u0;
        Iinj = dev.current_injection(0, x_dev, dae.y0, u_dev, struct());
        fprintf('%s: |I_inj|=%.6g\n', dev.device_id, abs(Iinj));
    end
end

function r = eq_res(z, active_x, frozen_x, free_y, vcon_vars, vcon_ref, dae)
    nx_total = numel(dae.x0);
    x_full = zeros(nx_total,1);
    x_full(active_x) = z(1:numel(active_x));
    for fi = 1:numel(frozen_x)
        x_full(frozen_x(fi)) = 0;  % SG1 Edp, etc
    end
    y_full = zeros(28,1);
    y_full(vcon_vars) = vcon_ref;
    y_full(free_y) = z(numel(active_x)+1:end);
    ec = struct();
    f = dae.dae_f(0, x_full, y_full, dae.u0, ec);
    g = dae.dae_g(0, x_full, y_full, dae.Ynet, dae.u0, ec);
    r = [f(active_x); g(free_y)];
end
