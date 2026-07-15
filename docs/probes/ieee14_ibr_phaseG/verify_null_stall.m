function verify_null_stall()
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
            devs(k).initial_online = false; devs(k).mode = 'breaker_open';
            break;
        end
    end
    vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
    dae = stability.composite_dae(c, devs, struct('load_model','cz_p_cz_q','vcon',vcon));

    % Build active/frozen indices as in mixed_equilibrium_solve
    frozen_x_indices = [];
    frozen_x_values = [];
    active_x_indices = 1:numel(dae.x0);
    for dk = 1:numel(dae.devices)
        dev = dae.devices(dk);
        if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
            off = dae.device_offsets(dk);
            frozen_x_indices = [frozen_x_indices, off + dev.frozen_state_indices(:)'];
            frozen_x_values  = [frozen_x_values,  dev.frozen_state_values(:)'];
        end
    end
    active_x_indices = setdiff(active_x_indices, frozen_x_indices, 'stable');
    vcon_vars = 2; vcon_ref = 0;
    free_vars = setdiff(1:28, vcon_vars, 'stable');

    % Residual and jacobian helpers
    residual_fn = @(z) eq_res(z, active_x_indices, frozen_x_indices, frozen_x_values, ...
        free_vars, vcon_vars, vcon_ref, dae);
    fd_eps = 3e-6;
    jacobian_fn = @(z) eq_jac(z, residual_fn, fd_eps);

    z0 = [dae.x0(active_x_indices); dae.y0(free_vars)];
    z = z0;
    for iter = 1:5
        r = residual_fn(z);
        rn = norm(r, inf);
        J = jacobian_fn(z);
        rc = rcond(J);
        fprintf('iter %d: |r|=%.6g, rcond=%.6g\n', iter, rn, rc);
        dz = -(J \ r);
        alpha = 1.0;
        for ls = 1:20
            zn = z + alpha*dz;
            rn_new = norm(residual_fn(zn), inf);
            if isfinite(rn_new) && rn_new < rn, break; end
            alpha = alpha*0.5;
        end
        z = z + alpha*dz;
        fprintf('  alpha=%.6g, |r_new|=%.6g\n', alpha, norm(residual_fn(z),inf));

        % Null vector of J
        if rc < 1e-6
            [~, S, V] = svd(J);
            v_min = V(:,end);
            [~, idx] = sort(abs(v_min), 'descend');
            fprintf('  Top 8 null-vector components:\n');
            for k = 1:8
                j = idx(k);
                if j <= numel(active_x_indices)
                    gx = active_x_indices(j);
                    off = 0;
                    for dk = 1:numel(dae.devices)
                        if gx <= off + dae.devices(dk).nx
                            fprintf('    x(%d)=%s[%d] v=%.4e\n', gx, dae.devices(dk).device_id, gx-off, v_min(j));
                            break;
                        end
                        off = off + dae.devices(dk).nx;
                    end
                else
                    jy = free_vars(j - numel(active_x_indices));
                    fprintf('    y(%d) v=%.4e\n', jy, v_min(j));
                end
            end
            break;
        end
    end
end

function r = eq_res(z, active_x, frozen_x, frozen_xv, free_y, vcon_vars, vcon_ref, dae)
    nx = numel(active_x);
    x_full = zeros(numel(dae.x0), 1);
    x_full(active_x) = z(1:nx);
    for fi = 1:numel(frozen_x), x_full(frozen_x(fi)) = frozen_xv(fi); end
    y_full = zeros(28,1);
    y_full(vcon_vars) = vcon_ref;
    y_full(free_y) = z(nx+1:end);
    ec = struct();
    f = dae.dae_f(0, x_full, y_full, dae.u0, ec);
    g = dae.dae_g(0, x_full, y_full, dae.Ynet, dae.u0, ec);
    free_rows = setdiff(1:numel(g), dae.vcon.rows, 'stable');
    r = [f(active_x); g(free_y)];
end

function J = eq_jac(z, residual_fn, fd_eps)
    nz = numel(z);
    r0 = residual_fn(z);
    J = zeros(nz, nz);
    for j = 1:nz
        zp = z; zp(j) = zp(j) + fd_eps;
        J(:,j) = (residual_fn(zp) - r0) / fd_eps;
    end
end
