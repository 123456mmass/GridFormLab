%AB_MATRIX_PROBE  Controlled old-Z/new-Z × no-clamp/clamp matrix (DIAGNOSTIC_ONLY).
%   Uses the corrected equilibrium residual (event_context + local active-state
%   mask) and the ORIGINAL damped Newton.  Reports row-block residuals,
%   singular values, power balance and limiter state.  Does not feed any
%   solution back into production.
function ab_matrix_probe()
    restoredefaultpath;
    addpath('C:\Users\User\Desktop\Power-flow');
    pf_init_paths();
    clear functions;

    c = cases.case_ieee14_1sg_4ibr_auto_vsg();
    modes = struct('device_id', {'IBR2','IBR3','IBR6','IBR8'}, ...
                   'mode', {'GFM','gfl','gfl','gfl'});
    disp_s = struct('IBR2', 109.7, 'IBR3', 49.8, 'IBR6', 49.8, 'IBR8', 49.8);

    scenarios = {
        'oldZ_noclamps', struct('use_kappa', false, 'use_clamp', false);
        'oldZ_clamps',   struct('use_kappa', false, 'use_clamp', true);
        'newZ_noclamps', struct('use_kappa', true,  'use_clamp', false);
        'newZ_clamps',   struct('use_kappa', true,  'use_clamp', true);
    };

    for s = 1:size(scenarios,1)
        label = scenarios{s,1};
        p = scenarios{s,2};
        fprintf('\n=== %s ===\n', label);
        devs = build_devices_ab(c, modes, disp_s, p);
        for k = 1:numel(devs)
            if strcmp(devs(k).device_type, 'sg_emf6_composite')
                devs(k).initial_online = false; devs(k).mode = 'breaker_open';
                break;
            end
        end
        r = stability.mixed_equilibrium_solve(c, struct('devices', devs), struct('verbose', false));
        fprintf('conv=%d, res=%.6g, rcond=%.6g, iter=%d\n', ...
            r.converged, r.residual_norm, r.rcond, r.iterations);
        if r.converged
            pb = r.limit_checks.power_balance;
            fprintf('  online gen=%.4g pu, load+losses=%.4g pu\n', ...
                pb.total_online_gen_pu, pb.load_plus_losses_pu);
            if isfield(r.limit_checks.devices, 'IBR2')
                rec = r.limit_checks.devices.IBR2.reconstruct;
                if isfield(rec, 'I_limited')
                    fprintf('  IBR2 I_limited=%d, |I_unc|=%.4g, ImaxF_sys=%.4g\n', ...
                        rec.I_limited, abs(rec.I_unc_sys), rec.ImaxF_sys);
                end
            end
        end
    end
end

function devs = build_devices_ab(c, modes, disp_s, p)
    % Build with toggled GFM variants by wrapping regfm_b1_vsg_model closures.
    devs = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_s);
    for k = 1:numel(devs)
        dev = devs(k);
        if ~strcmp(dev.device_type, 'ibr_dual_mode'), continue; end
        % Rebuild only GFM-mode IBRs with A/B toggles.
        if strcmp(dev.initial_mode, 'GFM')
            bus_id = dev.bus_id;
            bus_pos = dev.bus_position;
            bus_ids = dev.bus_ids;
            V0 = c.mpc.bus(c.mpc.bus(:,1)==bus_id, 8) * exp(1i*c.mpc.bus(c.mpc.bus(:,1)==bus_id, 9)*pi/180);
            params = struct('Mbase', dev.provenance.params.Mbase);
            devs(k) = build_gfm_ab(devs(k).device_id, bus_id, bus_pos, bus_ids, V0, params, ...
                disp_s.(char(devs(k).device_id)) / 100, 1.04, p);
        end
    end
end

function dev = build_gfm_ab(device_id, bus_id, bus_pos, bus_ids, V0, params, P_ref, V_ref, p)
    % Base GFM device.
    dev = ibr.regfm_b1_vsg_model(device_id, bus_id, bus_pos, bus_ids, V0, params, P_ref, V_ref);
    if p.use_kappa && p.use_clamp
        return;  % already corrected-Z + clamp
    end
    % Else wrap closures to toggle behavior.
    kappa = 100 / params.Mbase;
    if ~p.use_kappa
        kappa_eff = 1.0;  % old wrong base conversion
    else
        kappa_eff = kappa;
    end
    ImaxF = 1.5;
    Re = dev.provenance.params.Re;
    XL = dev.provenance.params.XL;

    old_ci = dev.current_injection;
    old_f = dev.f;
    old_pe = dev.electrical_power;
    old_rec = dev.reconstruct;

    if ~p.use_clamp
        % Replace current injection with linear (no clamp) using effective kappa.
        dev.current_injection = @(t,x,y,u,ec) linear_current(x,y,u,bus_pos,kappa_eff,Re,XL);
        dev.electrical_power = @(t,x,y,u,ec) linear_pe(x,y,u,bus_pos,kappa_eff,Re,XL);
        dev.f = @(t,x,y,u,ec) linear_f(x,y,u,bus_pos,kappa_eff,Re,XL, old_f, t, ec);
        dev.reconstruct = @(t,x,y,u,ec) linear_reconstruct(x,y,u,bus_pos,kappa_eff,Re,XL, old_rec, t, ec);
    elseif ~p.use_kappa
        % Keep clamp but use old base conversion.
        dev.current_injection = @(t,x,y,u,ec) clamped_current_oldZ(x,y,u,bus_pos,kappa_eff,Re,XL,ImaxF);
        dev.electrical_power = @(t,x,y,u,ec) clamped_pe_oldZ(x,y,u,bus_pos,kappa_eff,Re,XL,ImaxF);
        dev.f = @(t,x,y,u,ec) clamped_f_oldZ(x,y,u,bus_pos,kappa_eff,Re,XL,ImaxF, old_f, t, ec);
        dev.reconstruct = @(t,x,y,u,ec) clamped_rec_oldZ(x,y,u,bus_pos,kappa_eff,Re,XL,ImaxF, old_rec, t, ec);
    end
end

% Linear helpers (no clamp).
function I = linear_current(x, y, u, bp, kappa_eff, Re, XL)
    V_ref = u(2); Qinv_f = x(9); Vinv_f = x(10); x_Eint = x(4); delta_VSM = x(2);
    EVSM = V_ref - 0.05*Qinv_f + 0*(V_ref - Vinv_f) + 5*x_Eint;
    V_bus = complex(y(2*bp-1), y(2*bp));
    Z_sys = kappa_eff * (Re + 1i*XL);
    I = (EVSM*exp(1i*delta_VSM) - V_bus) / Z_sys;
end
function Pe = linear_pe(x, y, u, bp, kappa_eff, Re, XL)
    V_bus = complex(y(2*bp-1), y(2*bp));
    I = linear_current(x, y, u, bp, kappa_eff, Re, XL);
    Pe = real(V_bus * conj(I));
end
function dx = linear_f(x, y, u, bp, kappa_eff, Re, XL, old_f, t, ec)
    dx = old_f(t, x, y, u, ec);
    % Replace only the current-dependent filter RHS by re-deriving from linear I.
    V_bus = complex(y(2*bp-1), y(2*bp));
    I = linear_current(x, y, u, bp, kappa_eff, Re, XL);
    delta_PLL = x(5);
    Ix = real(I); Iy = imag(I);
    Id =  Ix*cos(delta_PLL) + Iy*sin(delta_PLL);
    Iq = -Ix*sin(delta_PLL) + Iy*cos(delta_PLL);
    S = V_bus * conj(I); P_meas = real(S); Q_meas = imag(S);
    dx(7) = (kappa_eff*P_meas - x(7)) / 0.02;
    dx(8) = (kappa_eff*Id  - x(8)) / 0.02;
    dx(9) = (kappa_eff*Q_meas - x(9)) / 0.02;
    dx(11) = (kappa_eff*Iq - x(11)) / 0.02;
end
function out = linear_reconstruct(x, y, u, bp, kappa_eff, Re, XL, old_rec, t, ec)
    out = old_rec(t, x, y, u, ec);
    out.I_limited = false;
    out.I_unc_sys = linear_current(x, y, u, bp, kappa_eff, Re, XL);
    out.I_gfm = out.I_unc_sys;
end

% Old-Z clamped helpers (reusing limited_current logic with kappa_eff=1).
function I = clamped_current_oldZ(x, y, u, bp, kappa_eff, Re, XL, ImaxF)
    V_ref = u(2); Qinv_f = x(9); Vinv_f = x(10); x_Eint = x(4); delta_VSM = x(2);
    EVSM = V_ref - 0.05*Qinv_f + 0*(V_ref - Vinv_f) + 5*x_Eint;
    V_bus = complex(y(2*bp-1), y(2*bp));
    Z_sys = kappa_eff * (Re + 1i*XL);
    ImaxF_sys = ImaxF / kappa_eff;
    I_unc = (EVSM*exp(1i*delta_VSM) - V_bus) / Z_sys;
    m = abs(I_unc);
    if m < ImaxF_sys, I = I_unc; else, I = ImaxF_sys * (I_unc/m); end
end
function Pe = clamped_pe_oldZ(x, y, u, bp, kappa_eff, Re, XL, ImaxF)
    V_bus = complex(y(2*bp-1), y(2*bp));
    I = clamped_current_oldZ(x, y, u, bp, kappa_eff, Re, XL, ImaxF);
    Pe = real(V_bus * conj(I));
end
function dx = clamped_f_oldZ(x, y, u, bp, kappa_eff, Re, XL, ImaxF, old_f, t, ec)
    dx = old_f(t, x, y, u, ec);
    V_bus = complex(y(2*bp-1), y(2*bp));
    I = clamped_current_oldZ(x, y, u, bp, kappa_eff, Re, XL, ImaxF);
    delta_PLL = x(5);
    Ix = real(I); Iy = imag(I);
    Id =  Ix*cos(delta_PLL) + Iy*sin(delta_PLL);
    Iq = -Ix*sin(delta_PLL) + Iy*cos(delta_PLL);
    S = V_bus * conj(I); P_meas = real(S); Q_meas = imag(S);
    dx(7) = (kappa_eff*P_meas - x(7)) / 0.02;
    dx(8) = (kappa_eff*Id  - x(8)) / 0.02;
    dx(9) = (kappa_eff*Q_meas - x(9)) / 0.02;
    dx(11) = (kappa_eff*Iq - x(11)) / 0.02;
end
function out = clamped_rec_oldZ(x, y, u, bp, kappa_eff, Re, XL, ImaxF, old_rec, t, ec)
    out = old_rec(t, x, y, u, ec);
    out.I_unc_sys = (out.EVSM*exp(1i*out.delta_VSM) - out.Vbus) / (kappa_eff*(Re+1i*XL));
    out.I_gfm = clamped_current_oldZ(x, y, u, bp, kappa_eff, Re, XL, ImaxF);
    out.I_limited = abs(out.I_unc_sys) >= (ImaxF/kappa_eff);
end
