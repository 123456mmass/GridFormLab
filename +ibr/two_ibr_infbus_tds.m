function out = two_ibr_infbus_tds(dev1, dev2, x1_0, x2_0, y0, V_inf, Z_line0, opt)
%TWO_IBR_INFBUS_TDS  Event-driven implicit-trapezoidal TDS for two switchable
%   6-state IBRs sharing a common PCC behind one line to an infinite bus.
%
%   OUT = ibr.two_ibr_infbus_tds(DEV1, DEV2, X1_0, X2_0, Y0, V_INF, Z_LINE0, OPT)
%   integrates
%       dx_k/dt = f_k(x_k, V)      (active branch of each ibr.SwitchableIbr6)
%       0       = I_1(x_1,V) + I_2(x_2,V) - (V - V_inf(t))/Z_line(t)   (PCC KCL)
%   with a project-owned damped-Newton implicit-trapezoidal step on
%   z = [x_1; x_2; y], y = [Re(V_pcc); Im(V_pcc)]. The Newton Jacobian is a
%   centred finite difference of the coupled residual.
%
%   This is an ASSUMED_DIAGNOSTIC study driver (not a production TS kernel). It
%   is self-contained and does not call any shared composite TS path.
%
%   DEV1, DEV2 are ibr.SwitchableIbr6 handles. Both must share bus_position=1
%   (common PCC, one network node). After every accepted step the supervisor
%   calls DEV.maybe_switch(x,y,t); a triggered device latches GFL->GFM with a
%   current-continuous state reset, so the state dimension never changes.
%
%   Disturbance (weak-grid event) at OPT.event_time:
%     - the line impedance is scaled by OPT.Zline_factor (>=1 weakens the grid),
%     - the infinite-bus voltage steps by magnitude OPT.step_dV and phase
%       OPT.step_dphase_deg (a grid phase/voltage jump).
%   Both are permanent step changes entering only the algebraic KCL.

arguments
    dev1 (1,1) ibr.SwitchableIbr6
    dev2 (1,1) ibr.SwitchableIbr6
    x1_0 (6,1) double
    x2_0 (6,1) double
    y0 (2,1) double
    V_inf (1,1) double {mustBeFinite}
    Z_line0 (1,1) double {mustBeFinite}
    opt.T (1,1) double {mustBePositive} = 6
    opt.dt (1,1) double {mustBePositive} = 1e-3
    opt.event_time (1,1) double = inf
    opt.recover_time (1,1) double = inf
    opt.step_ramp (1,1) double {mustBeNonnegative} = 0.05
    opt.Zline_factor (1,1) double {mustBePositive} = 1
    opt.step_dphase_deg (1,1) double = 0
    opt.step_dV (1,1) double = 0
    opt.newton_tol (1,1) double {mustBePositive} = 1e-9
    opt.newton_max_iter (1,1) double {mustBeInteger,mustBePositive} = 50
    opt.fd_eps (1,1) double {mustBePositive} = 1e-6
end

if dev1.bus_position ~= 1 || dev2.bus_position ~= 1
    error('ibr:two_ibr_infbus_tds:busPosition', ...
        'Both IBRs must share the common PCC (bus_position=1).');
end
if any(~isfinite(x1_0)) || any(~isfinite(x2_0)) || any(~isfinite(y0)) || abs(Z_line0)==0
    error('ibr:two_ibr_infbus_tds:badInput','Non-finite state or zero line impedance.');
end

% --- Time-varying grid (event enters only the algebraic KCL) ---------------
% The disturbance is a temporary window [event_time, recover_time): the line is
% weakened (x Zline_factor) and the infinite-bus voltage steps (magnitude
% step_dV, phase step_dphase_deg); outside the window the grid is nominal, so
% the device can resume grid-following after recovery.
Vstep = V_inf*(1+opt.step_dV)*exp(1i*opt.step_dphase_deg*pi/180);
sfun = @(t) ramp_weight(t, opt.event_time, opt.recover_time, opt.step_ramp);
Vinf_of = @(t) V_inf + (Vstep - V_inf)*sfun(t);
Zline_of = @(t) Z_line0*(1 + (opt.Zline_factor-1)*sfun(t));

n1 = 6; n2 = 6; m = 2; nz = n1+n2+m;
nsteps = round(opt.T/opt.dt);
tgrid = (0:opt.dt:nsteps*opt.dt).';

X1 = zeros(n1, nsteps+1);
X2 = zeros(n2, nsteps+1);
Y  = zeros(m,  nsteps+1);
X1(:,1) = x1_0; X2(:,1) = x2_0; Y(:,1) = y0;

% Signal histories (recorded at every sample, using the mode active on arrival).
f1 = zeros(nsteps+1,1); f2 = zeros(nsteps+1,1);
J1 = zeros(nsteps+1,1); J2 = zeros(nsteps+1,1);
Jr1 = zeros(nsteps+1,1); Jr2 = zeros(nsteps+1,1);   % up-line reference equation
mode1 = zeros(nsteps+1,1); mode2 = zeros(nsteps+1,1);   % 0=gfl, 1=GFM
P1 = zeros(nsteps+1,1); P2 = zeros(nsteps+1,1);
Q1 = zeros(nsteps+1,1); Q2 = zeros(nsteps+1,1);
id1 = zeros(nsteps+1,1); iq1 = zeros(nsteps+1,1);
id2 = zeros(nsteps+1,1); iq2 = zeros(nsteps+1,1);
Vmag = zeros(nsteps+1,1);
conv_count = 0; max_resid = zeros(nsteps,1);
switch_events = [];   % rows [t, device, J]

% Local short-circuit ratio seen by the IBRs (aggregate rating), used by the
% AGSI++ grid-strength sub-index J_SCR: SCR = |V_inf|^2 / (|Z_line|*S_agg). This
% is a DIAGNOSTIC value computed from the known network (a real device would
% estimate it from terminal dV/dI); consumed only when w_SCR>0.
S_agg = abs(dev1.P_ref0) + abs(dev2.P_ref0) + 1e-9;
scr0 = abs(V_inf)^2/(abs(Z_line0)*S_agg);
dev1.grid_scr = scr0; dev2.grid_scr = scr0;

% Record the initial sample.
record_sample(1, tgrid(1));

for k = 1:nsteps
    t1 = tgrid(k+1);
    Vinf_k = Vinf_of(t1);
    Zline_k = Zline_of(t1);
    scr_k = abs(Vinf_k)^2/(abs(Zline_k)*S_agg);
    dev1.grid_scr = scr_k; dev2.grid_scr = scr_k;
    x1k = X1(:,k); x2k = X2(:,k); yk = Y(:,k);
    f1_0 = dev1.f(x1k, yk);
    f2_0 = dev2.f(x2k, yk);
    z = [x1k; x2k; yk];
    [z1, info_step] = newton_step(z, x1k, x2k, yk, f1_0, f2_0, ...
        dev1, dev2, Vinf_k, Zline_k, n1, n2, m, opt.dt, ...
        opt.newton_tol, opt.newton_max_iter, opt.fd_eps);
    x1n = z1(1:n1);
    x2n = z1(n1+1:n1+n2);
    yn  = z1(n1+n2+1:end);
    conv_count = conv_count + info_step.converged;
    max_resid(k) = info_step.max_resid;

    % Store the pre-switch solution, then let the supervisor act at the boundary.
    X1(:,k+1) = x1n; X2(:,k+1) = x2n; Y(:,k+1) = yn;
    record_sample(k+1, t1);   % records with the mode active DURING the step

    [x1s, did1, i1] = dev1.maybe_switch(x1n, yn, t1);
    if did1
        X1(:,k+1) = x1s;
        switch_events = [switch_events; t1, 1, i1.J, double(i1.new_mode=="GFM")]; %#ok<AGROW>
    end
    [x2s, did2, i2] = dev2.maybe_switch(x2n, yn, t1);
    if did2
        X2(:,k+1) = x2s;
        switch_events = [switch_events; t1, 2, i2.J, double(i2.new_mode=="GFM")]; %#ok<AGROW>
    end
end

out = struct();
out.classification = 'ASSUMED_DIAGNOSTIC_TWO_IBR_INFBUS_SWITCH_TDS';
out.tgrid = tgrid;
out.X1 = X1; out.X2 = X2; out.Y = Y;
out.V_pcc = complex(Y(1,:), Y(2,:)).';
out.Vmag = Vmag;
out.f1 = f1; out.f2 = f2;
out.index1 = J1; out.index2 = J2;
out.ref1 = Jr1; out.ref2 = Jr2;   % up-line (Gamma_on) reference, time series
out.agsi_up = dev1.AGSI_up; out.agsi_down = dev1.AGSI_down;
out.mode1 = mode1; out.mode2 = mode2;
out.P1 = P1; out.P2 = P2; out.Q1 = Q1; out.Q2 = Q2;
out.id1 = id1; out.iq1 = iq1; out.id2 = id2; out.iq2 = iq2;
out.switch_events = switch_events;
out.dev1_switched = dev1.switched; out.dev2_switched = dev2.switched;
out.dev1_switch_time = dev1.last_switch_time; out.dev2_switch_time = dev2.last_switch_time;
out.dev1_n_switch = dev1.n_switch; out.dev2_n_switch = dev2.n_switch;
out.dev1_mode = dev1.mode; out.dev2_mode = dev2.mode;
out.V_inf = V_inf; out.Z_line0 = Z_line0;
out.event_time = opt.event_time; out.recover_time = opt.recover_time;
out.Zline_factor = opt.Zline_factor;
out.step_dphase_deg = opt.step_dphase_deg; out.step_dV = opt.step_dV;
out.newton_all_converged = (conv_count == nsteps);
out.newton_converged_count = conv_count;
out.max_resid_history = max_resid;

    % --- nested recorder (captures mode active on arrival at sample idx) ----
    function record_sample(idx, tt)
        yy = Y(:,idx);
        Vc = complex(yy(1), yy(2));
        Vmag(idx) = abs(Vc);
        r1 = dev1.reconstruct(X1(:,idx), yy);
        r2 = dev2.reconstruct(X2(:,idx), yy);
        f1(idx) = r1.f_hz; f2(idx) = r2.f_hz;
        J1(idx) = dev1.compute_index(X1(:,idx), yy, tt);
        J2(idx) = dev2.compute_index(X2(:,idx), yy, tt);
        Jr1(idx) = dev1.reference_up(X1(:,idx), yy, tt);
        Jr2(idx) = dev2.reference_up(X2(:,idx), yy, tt);
        mode1(idx) = double(~strcmp(dev1.mode,'gfl'));
        mode2(idx) = double(~strcmp(dev2.mode,'gfl'));
        P1(idx) = r1.Pe; Q1(idx) = r1.Qe;
        P2(idx) = r2.Pe; Q2(idx) = r2.Qe;
        id1(idx) = r1.i_d; iq1(idx) = r1.i_q;
        id2(idx) = r2.i_d; iq2(idx) = r2.i_q;
    end
end

% =========================================================================
function [z1, info] = newton_step(z, x1_0, x2_0, y_0, f1_0, f2_0, ...
    dev1, dev2, Vinf_k, Zline_k, n1, n2, m, dt, tol, max_iter, fd_eps)
% Damped Newton on the coupled implicit-trapezoidal + KCL residual.
z1 = z;
converged = false;
max_resid = NaN;
for it = 1:max_iter
    r = resid(z1);
    nr = norm(r, inf);
    max_resid = max(max_resid, nr);
    if nr <= tol
        converged = true;
        info = struct('converged', converged, 'max_resid', max_resid);
        return;
    end
    J = fd_jac(z1);
    if rcond(J) <= 1e-14
        error('ibr:two_ibr_infbus_tds:illConditioned', ...
            'Newton Jacobian ill-conditioned (rcond<=1e-14) at a TDS step.');
    end
    dz = -J\r;
    alpha = 1.0;
    for ls = 1:12
        z_try = z1 + alpha*dz;
        if all(isfinite(z_try))
            z1 = z_try;
            break;
        end
        alpha = alpha/2;
    end
    if ~all(isfinite(z1))
        error('ibr:two_ibr_infbus_tds:nonfinite','Newton step produced a non-finite iterate.');
    end
end
info = struct('converged', converged, 'max_resid', max_resid);

    function r = resid(zz)
        x1 = zz(1:n1);
        x2 = zz(n1+1:n1+n2);
        yy = zz(n1+n2+1:end);
        f1v = dev1.f(x1, yy);
        f2v = dev2.f(x2, yy);
        rx1 = x1 - x1_0 - 0.5*dt*(f1_0 + f1v);
        rx2 = x2 - x2_0 - 0.5*dt*(f2_0 + f2v);
        I1 = dev1.current_injection(x1, yy);
        I2 = dev2.current_injection(x2, yy);
        Vc = complex(yy(1), yy(2));
        mis = I1 + I2 - (Vc - Vinf_k)/Zline_k;
        r = [rx1; rx2; real(mis); imag(mis)];
    end

    function Jm = fd_jac(zz)
        nz = n1+n2+m;
        Jm = zeros(nz);
        r0 = resid(zz);
        for j = 1:nz
            zp = zz; zp(j) = zp(j) + fd_eps;
            Jm(:,j) = (resid(zp) - r0)/fd_eps;
        end
    end
end


% =========================================================================
function w = ramp_weight(t, t_on, t_off, ramp)
% Smooth (smoothstep) 0->1 weight rising over [t_on, t_on+ramp], held at 1 to
% t_off, then falling 1->0 over [t_off, t_off+ramp]. ramp=0 gives a hard step.
if ~(t >= t_on)
    w = 0; return;
end
if ramp <= 0
    w = double(t >= t_on && t < t_off); return;
end
if t < t_on + ramp
    u = (t - t_on)/ramp;
    w = 3*u^2 - 2*u^3;            % rise
elseif t < t_off
    w = 1;                        % held
elseif t < t_off + ramp
    u = (t - t_off)/ramp;
    w = 1 - (3*u^2 - 2*u^3);      % fall back to nominal
else
    w = 0;
end
end
