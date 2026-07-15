function verify_pinv_fix2()
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

    % Inspect initial conditions
    fprintf('=== Initial conditions ===\n');
    fprintf('nx=%d, ny=%d\n', numel(dae.x0), numel(dae.y0));

    % Find GFM device (IBR2)
    for k = 1:numel(dae.devices)
        d = dae.devices(k);
        fprintf('Device %d: %s, nx=%d, online=%d\n', k, d.device_id, d.nx, d.initial_online);
        if strcmp(d.device_id, 'IBR2')
            fprintf('  IBR2 x0: ');
            fprintf('%.4g ', d.x0);
            fprintf('\n');
            fprintf('  IBR2 u0: ');
            fprintf('%.4g ', d.u0);
            fprintf('\n');
            % Check clamp at initial conditions
            x = d.x0; u = d.u0;
            delta_VSM = x(2); x_Eint = x(4); Qinv_f = x(9); Vinv_f = x(10);
            if numel(u) >= 2
                V_ref = u(2); P_ref_sys = u(1);
            else
                V_ref = 1.04; P_ref_sys = 1.097;
            end
            V_bus = complex(dae.y0(3), dae.y0(4)); % bus 2
            EVSM = V_ref - 0.05*Qinv_f + 0*(V_ref-Vinv_f) + 5*x_Eint;
            fprintf('  V_bus=%.6g%+.6gj, EVSM=%.6g, delta_VSM=%.6g\n', real(V_bus), imag(V_bus), EVSM, delta_VSM);
            % Check current
            kappa_val = 100/140;
            Z_sys = kappa_val * (0 + 0.1i);
            I_unc = (EVSM*exp(1i*delta_VSM) - V_bus) / Z_sys;
            ImaxF_sys = 1.5 / kappa_val;
            fprintf('  |I_unc|=%.6g, ImaxF_sys=%.6g, clamped=%d\n', abs(I_unc), ImaxF_sys, abs(I_unc) >= ImaxF_sys);
        end
    end

    % Check residual at initial condition
    x0 = dae.x0; y0 = dae.y0; u = dae.u0; Y = dae.Ynet;
    ec = struct();
    active_x = [1:5 7:66];
    free_y = setdiff(1:28, 2, 'stable');

    x = zeros(66,1); x(active_x) = x0(active_x);
    yf = zeros(28,1); yf(2) = 0; yf(free_y) = y0(free_y);
    f = dae.dae_f(0, x, yf, u, ec);
    g = dae.dae_g(0, x, yf, Y, u, ec);

    fprintf('\n=== Initial residual ===\n');
    fprintf('|f|=%.6g, |g_free|=%.6g\n', norm(f(active_x),inf), norm(g(free_y),inf));

    % Check f components
    fprintf('Top 10 |f| components:\n');
    [~, idx] = sort(abs(f(active_x)), 'descend');
    for k = 1:min(10, numel(active_x))
        ax = active_x(idx(k));
        % Find which device
        off = 0;
        for dk = 1:numel(dae.devices)
            if ax <= off + dae.devices(dk).nx
                fprintf('  f(%d)=%s[%d] = %.6g\n', ax, dae.devices(dk).device_id, ax-off, f(ax));
                break;
            end
            off = off + dae.devices(dk).nx;
        end
    end

    % Check g components
    fprintf('Top 10 |g| components (free rows):\n');
    [~, idx] = sort(abs(g(free_y)), 'descend');
    for k = 1:min(10, numel(free_y))
        fprintf('  g(%d) = %.6g\n', free_y(idx(k)), g(free_y(idx(k))));
    end

    % FD Jacobian at initial condition
    z0 = [x0(active_x); y0(free_y)];
    nz = numel(z0);
    r0 = [f(active_x); g(free_y)];
    fd_eps = 3e-6;
    J = zeros(nz, nz);
    for j = 1:nz
        zp = z0; zp(j) = zp(j) + fd_eps;
        xp = zeros(66,1); xp(active_x) = zp(1:65);
        yp = zeros(28,1); yp(2) = 0; yp(free_y) = zp(66:end);
        fp = dae.dae_f(0, xp, yp, u, ec);
        gp = dae.dae_g(0, xp, yp, Y, u, ec);
        J(:,j) = ([fp(active_x); gp(free_y)] - r0) / fd_eps;
    end
    fprintf('\n=== FD Jacobian at initial ===\n');
    fprintf('rcond(J)=%.6g, NaN/Inf=%d/%d\n', rcond(J), sum(~isfinite(J(:))), numel(J));
    [~, S, ~] = svd(J); s = diag(S);
    fprintf('Smallest 5 singular values: %s\n', mat2str(s(end-4:end), 3));
end
