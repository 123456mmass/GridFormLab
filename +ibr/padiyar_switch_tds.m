function out = padiyar_switch_tds(sys, opt)
%PADIYAR_SWITCH_TDS  Mixed SG + 3 switchable-IBR time-domain simulation on the
%   Padiyar two-area network, with an SG-trip event and per-IBR AGSI/AGSI++
%   mode switching (index-driven, no dwell by default).
%
%   OUT = ibr.padiyar_switch_tds(SYS, OPT), SYS from ibr.build_padiyar_switch_system.
%   Implicit-trapezoidal integration of z=[x_SG(5); x_IBR1(6); x_IBR2(6);
%   x_IBR3(6); y(2*nb)] coupled to the network KCL
%       0 = -Y(t) V + I_SG@sgbus (if online) + sum_j I_IBR_j@bus_j.
%   A damped modified-Newton (FD Jacobian rebuilt once per step) solves each step.
%   At OPT.sg_trip_time the SG breaker opens: its current injection is removed and
%   its states are frozen. After every accepted step the supervisor calls each
%   IBR's maybe_switch (AGSI++). Project code only; ASSUMED_DIAGNOSTIC driver.

arguments
    sys (1,1) struct
    opt.T (1,1) double = 8
    opt.dt (1,1) double = 2e-3
    opt.sg_trip_time (1,1) double = 1.0
    opt.sg_reclose_time (1,1) double = inf
    opt.fault_on (1,1) double = inf
    opt.fault_clear (1,1) double = inf
    opt.fault_bus (1,1) double = 3
    opt.fault_Zf (1,1) double = 0.5i
    opt.step_on (1,1) double = inf
    opt.step_bus (1,1) double = 13
    opt.step_factor (1,1) double = 0.10
    opt.newton_tol (1,1) double = 1e-8
    opt.newton_max_iter (1,1) double = 40
    opt.fd_eps (1,1) double = 1e-6
end

sg = sys.sg; devs = sys.devs; Y = sys.Y; nb = sys.nb;
Yt = Y;                                   % time-varying admittance (fault/step)
fault_bp = find(sys.bus_ids==opt.fault_bus,1);
step_bp  = find(sys.bus_ids==opt.step_bus,1);
% FAIL-CLOSED event location: an unknown bus id must NOT be silently relocated to
% network position 1 (that would apply the disturbance somewhere else and report
% the result as if it were the requested one). The check is applied only when the
% corresponding event is actually SCHEDULED (finite time), so a disabled event may
% keep its inapplicable default bus.
if isfinite(opt.fault_on) && isempty(fault_bp)
    error('ibr:padiyar_switch_tds:faultBus', ...
        'Scheduled fault bus %g is not in this system (bus ids: %s).', ...
        opt.fault_bus, mat2str(sys.bus_ids));
end
if isfinite(opt.step_on) && isempty(step_bp)
    error('ibr:padiyar_switch_tds:stepBus', ...
        'Scheduled load-step bus %g is not in this system (bus ids: %s).', ...
        opt.step_bus, mat2str(sys.bus_ids));
end
if isfinite(opt.step_on) && ~isempty(step_bp) && abs(sys.load_adm(step_bp)) == 0
    warning('ibr:padiyar_switch_tds:stepBusNoLoad', ...
        ['Load step scheduled at bus %g, which carries NO load in this case: the ' ...
         'step admittance is zero, so the disturbance has no effect.'], opt.step_bus);
end
if isempty(fault_bp), fault_bp = 1; end   % unused (event disabled)
if isempty(step_bp),  step_bp  = 1; end   % unused (event disabled)
nib = numel(devs); nsg = sg.nx; nxi = 6;
sg_bp = sys.sg_bus_position; ibr_bp = sys.ibr_bus_positions;
% state layout
isg = 1:nsg;
iib = cell(1,nib);
for j=1:nib, iib{j} = nsg + (j-1)*nxi + (1:nxi); end
iy  = nsg + nib*nxi + (1:2*nb);
nz  = nsg + nib*nxi + 2*nb;

nsteps = round(opt.T/opt.dt);
tg = (0:opt.dt:nsteps*opt.dt).';
Z = zeros(nz, nsteps+1);
z = [sys.x_sg0(:); vertcat(sys.x_ibr0{:}); sys.y0(:)];
Z(:,1) = z;

% histories
idx = zeros(nsteps+1, nib); md = zeros(nsteps+1, nib);
fib = zeros(nsteps+1, nib); Vb = zeros(nsteps+1, nib);
Pib = zeros(nsteps+1, nib); Qib = zeros(nsteps+1, nib);
fsgH = zeros(nsteps+1,1); omsgH = zeros(nsteps+1,1); Vmin = zeros(nsteps+1,1);
sg_online_H = true(nsteps+1,1);
id_ibr = zeros(nsteps+1,nib); iq_ibr = zeros(nsteps+1,nib); ang_ibr = zeros(nsteps+1,nib);
sg_delta = zeros(nsteps+1,1); sg_id = zeros(nsteps+1,1); sg_iq = zeros(nsteps+1,1);
sg_P = zeros(nsteps+1,1); sg_Q = zeros(nsteps+1,1);
ref_code = zeros(nsteps+1,1); ref_angle = zeros(nsteps+1,1);   % 0=SG slack, 1..nib=forming IBR, -1=none
switch_events = [];
conv_count = 0; maxres = zeros(nsteps,1);

sg_online = true;
set_scr(1);              % set IBR grid_scr for the current SG status
record(1, tg(1), true);

diverged = false; nvalid = nsteps+1;    % divergence truncation bookkeeping
nfail_run = 0; last_good = 1;            % consecutive non-converged run; last converged index
for k = 1:nsteps
    t1 = tg(k+1);
    was_online = sg_online;
    sg_online = (t1 < opt.sg_trip_time) || (t1 >= opt.sg_reclose_time);
    if sg_online && ~was_online
        % Synchronized reclose with a genuine reference HANDBACK to the SG:
        %   - the SG returns synchronized to the present bus voltage and carrying
        %     its scheduled (Pm,Q0), i.e. it re-takes the slack/reference role;
        %   - each IBR still forming (GFM) hands the reference back and reverts to
        %     its scheduled GFL dispatch (re-initialised at its present bus V).
        % The network voltages are NOT reset: the composite then transients from
        % the island state toward the restored SG-slack operating point. (Model
        % 1.1 has no governor, so the SG carries its fixed Pm on reclose.)
        y_prev = Z(iy,k);
        Vsg = complex(y_prev(2*sg_bp-1), y_prev(2*sg_bp));
        Z(isg,k) = sg.reinit(Vsg);
        for j=1:nib
            was_gfm = ~strcmp(devs{j}.mode,'gfl');
            if was_gfm
                Vbj = complex(y_prev(2*ibr_bp(j)-1), y_prev(2*ibr_bp(j)));
                Z(iib{j},k) = devs{j}.gfl_dev.equilibrium_initialize( ...
                    Vbj, devs{j}.P_ref0, devs{j}.Q_ref0, struct());
                devs{j}.restore_to_gfl(t1);
                switch_events = [switch_events; t1, j, NaN, 0]; %#ok<AGROW>
            end
        end
    end
    set_scr(k+1<=numel(tg));                % update SCR seen by the IBRs
    % time-varying admittance: temporary shunt fault + (permanent) load step
    Yt = Y;
    if t1 >= opt.fault_on && t1 < opt.fault_clear
        Yt(fault_bp,fault_bp) = Yt(fault_bp,fault_bp) + 1/opt.fault_Zf;
    end
    if t1 >= opt.step_on
        Yt(step_bp,step_bp) = Yt(step_bp,step_bp) + opt.step_factor*sys.load_adm(step_bp);
    end
    x_sg0 = Z(isg,k); y_0 = Z(iy,k);
    f_sg0 = sg.f(x_sg0, y_0);
    xib0 = cell(1,nib); fib0 = cell(1,nib);
    for j=1:nib, xib0{j}=Z(iib{j},k); fib0{j}=devs{j}.f(xib0{j}, y_0); end

    z = Z(:,k);
    [z, info] = solve_step(z);
    if ~all(isfinite(z)) || norm(z, inf) > 1e4
        % Numerical explosion: states left the models' validity domain (10^n).
        % Truncate at the last CONVERGED point (fail-closed). The 1e4 bound is a
        % NUMERICAL_METHOD divergence sentinel (>> any physical pu quantity).
        diverged = true; nvalid = last_good; break;
    end
    Z(:,k+1) = z;
    conv_count = conv_count + info.converged; maxres(k) = info.res;
    record(k+1, t1, sg_online);

    if info.converged
        nfail_run = 0; last_good = k+1;
        % supervisor: per-IBR index-driven switching, evaluated only on a
        % converged (trustworthy) state so decisions never use garbage.
        y1 = Z(iy,k+1);
        for j=1:nib
            [xn, did, i1] = devs{j}.maybe_switch(Z(iib{j},k+1), y1, t1);
            if did
                Z(iib{j},k+1) = xn;
                switch_events = [switch_events; t1, j, i1.J, double(i1.new_mode=="GFM")]; %#ok<AGROW>
            end
        end
    else
        % Sustained non-convergence => the trajectory is unreliable. After a run
        % of failed corrector steps, truncate back to the last converged point.
        nfail_run = nfail_run + 1;
        if nfail_run >= 20
            diverged = true; nvalid = last_good; break;
        end
    end
end

if diverged
    kp = 1:nvalid;      % keep only physical points up to the divergence step
    tg=tg(kp); Z=Z(:,kp);
    idx=idx(kp,:); md=md(kp,:); fib=fib(kp,:); Vb=Vb(kp,:); Pib=Pib(kp,:); Qib=Qib(kp,:);
    fsgH=fsgH(kp); omsgH=omsgH(kp); Vmin=Vmin(kp); sg_online_H=sg_online_H(kp);
    id_ibr=id_ibr(kp,:); iq_ibr=iq_ibr(kp,:); ang_ibr=ang_ibr(kp,:);
    sg_delta=sg_delta(kp); sg_id=sg_id(kp); sg_iq=sg_iq(kp);
    sg_P=sg_P(kp); sg_Q=sg_Q(kp);
    ref_code=ref_code(kp); ref_angle=ref_angle(kp);
end

out = struct();
out.classification = 'ASSUMED_DIAGNOSTIC_PADIYAR_1SG_3GFL_SWITCH_TDS';
out.tgrid = tg; out.Z = Z;
out.index = idx; out.mode = md; out.f_ibr = fib; out.Vbus = Vb;
out.P_ibr = Pib; out.Q_ibr = Qib;
out.f_sg = fsgH; out.omega_sg = omsgH; out.sg_online = sg_online_H;
out.Vmin = Vmin;
out.id_ibr = id_ibr; out.iq_ibr = iq_ibr; out.ang_ibr = ang_ibr;
out.sg_delta = sg_delta; out.sg_id = sg_id; out.sg_iq = sg_iq;
out.sg_P = sg_P; out.sg_Q = sg_Q;
out.ref_code = ref_code; out.ref_angle = ref_angle;
out.sg_reclose_time = opt.sg_reclose_time;
out.fault_on = opt.fault_on; out.fault_clear = opt.fault_clear; out.fault_bus = opt.fault_bus;
out.step_on = opt.step_on; out.step_bus = opt.step_bus; out.step_factor = opt.step_factor;
out.agsi_up = devs{1}.AGSI_up; out.agsi_down = devs{1}.AGSI_down;
out.switch_events = switch_events;
out.ibr_buses = sys.ibr_buses; out.sg_bus = sys.sg_bus;
out.sg_trip_time = opt.sg_trip_time;
out.newton_all_converged = (conv_count==nsteps) && ~diverged;
out.diverged = diverged;
out.max_resid = max(maxres);
if diverged
    warning('ibr:padiyar_switch_tds:diverged', ...
        ['Simulation DIVERGED near t=%.3fs and was truncated there: the disturbance is ' ...
         'too severe for this current-unlimited, governor-less model to ride through ' ...
         '(states exploded to non-physical magnitudes). Use a milder fault (larger Zf), ' ...
         'a smaller load step, or a shorter fault.'], tg(end));
elseif ~out.newton_all_converged
    nfail = nsteps - conv_count;
    kfail = find(maxres > opt.newton_tol, 1);
    tfail = tg(min(kfail+1, numel(tg)));
    warning('ibr:padiyar_switch_tds:notConverged', ...
        ['%d of %d Newton steps did not fully converge (first near t=%.3fs) - the ' ...
         'disturbance is too severe for this governor-less model to ride through; ' ...
         'results past that point are approximate. Use a milder fault (larger Zf) ' ...
         'or smaller load step.'], nfail, nsteps, tfail);
end
out.dev_n_switch = cellfun(@(d) d.n_switch, devs);
out.dev_mode = cellfun(@(d) string(d.mode), devs);

    % ================= nested helpers =================================
    function set_scr(~)
        for jj=1:nib
            if sg_online, devs{jj}.grid_scr = sys.scr_strong;
            else, devs{jj}.grid_scr = sys.scr_bus(jj); end
        end
    end

    function r = resid(zz)
        r = zeros(nz,1);
        y1 = zz(iy); V1 = complex(y1(1:2:end), y1(2:2:end));
        gc = -Yt*V1;
        % SG differential + injection
        xs1 = zz(isg);
        if sg_online
            fs1 = sg.f(xs1, y1);
            r(isg) = xs1 - x_sg0 - 0.5*opt.dt*(f_sg0 + fs1);
            gc(sg_bp) = gc(sg_bp) + sg.current_injection(xs1, y1);
        else
            r(isg) = xs1 - x_sg0;                 % frozen (breaker open)
        end
        % IBR differential + injection
        for jj=1:nib
            xj = zz(iib{jj});
            fj = devs{jj}.f(xj, y1);
            r(iib{jj}) = xj - xib0{jj} - 0.5*opt.dt*(fib0{jj} + fj);
            gc(ibr_bp(jj)) = gc(ibr_bp(jj)) + devs{jj}.current_injection(xj, y1);
        end
        r(iy(1:2:end)) = real(gc);
        r(iy(2:2:end)) = imag(gc);
    end

    function J = fd_jac(zz)
        try, r0 = resid(zz); catch, r0 = zeros(nz,1); end
        if ~all(isfinite(r0)), r0 = zeros(nz,1); end
        J = zeros(nz);
        h = opt.fd_eps;
        for i=1:nz
            zp = zz; zp(i) = zp(i) + h;
            try, rp = resid(zp); catch, rp = r0; end
            if ~all(isfinite(rp)), rp = r0; end
            J(:,i) = (rp - r0)/h;
        end
    end

    function n = rnorm(zz)
        % Safe residual infinity-norm for a TRIAL point: returns Inf if the
        % device RHS overflows or throws (SG/IBR models fail-closed on a
        % non-finite RHS). Lets the Newton line search reject the trial and
        % halve the step instead of crashing the whole run.
        try
            rr = resid(zz);
            if all(isfinite(rr)), n = norm(rr, inf); else, n = Inf; end
        catch
            n = Inf;
        end
    end

    function [z1, info] = solve_step(z1)
        J = fd_jac(z1); converged=false; rn=Inf; rebuilt=false;
        for it=1:opt.newton_max_iter
            try, r = resid(z1); catch, r = inf(nz,1); end
            if ~all(isfinite(r)), break; end        % non-physical iterate -> stop (not converged)
            rn = norm(r, inf);
            if rn <= opt.newton_tol, converged=true; break; end
            if rcond(J) <= 1e-15
                J = fd_jac(z1); rebuilt=true;
                if rcond(J) <= 1e-15, break; end     % singular -> stop (not converged)
            end
            dz = -J\r; a=1.0; ok=false;
            for ls=1:16
                zt = z1 + a*dz;
                if all(isfinite(zt)) && rnorm(zt) < rn
                    z1 = zt; ok=true; break;
                end
                a=a/2;
            end
            if ~ok
                if ~rebuilt, J=fd_jac(z1); rebuilt=true; zc = z1 - J\r;
                else, zc = z1 + dz; end
                if all(isfinite(zc)) && rnorm(zc) < 1e3*rn
                    z1 = zc;                          % cautious fallback
                else
                    break;                            % cannot progress -> keep last finite z1
                end
            end
        end
        info = struct('converged',converged,'res',rn);
    end

    function record(ix, tt, online)
        y1 = Z(iy,ix); Vc = complex(y1(1:2:end), y1(2:2:end));
        Vmin(ix) = min(abs(Vc));
        for jj=1:nib
            xj = Z(iib{jj},ix);
            idx(ix,jj) = devs{jj}.compute_index(xj, y1, tt);
            md(ix,jj)  = double(~strcmp(devs{jj}.mode,'gfl'));
            rj = devs{jj}.reconstruct(xj, y1);
            fib(ix,jj) = rj.f_hz; Pib(ix,jj)=rj.Pe; Qib(ix,jj)=rj.Qe;
            sc_i = sys.Mbase(jj)/100;                 % IBR dq current: inverter base -> 100 MVA system base
            id_ibr(ix,jj)=rj.i_d*sc_i; iq_ibr(ix,jj)=rj.i_q*sc_i;
            if isfield(rj,'delta_PLL'), ang_ibr(ix,jj)=rj.delta_PLL;
            elseif isfield(rj,'delta'), ang_ibr(ix,jj)=rj.delta; else, ang_ibr(ix,jj)=NaN; end
            Vb(ix,jj)  = abs(complex(y1(2*ibr_bp(jj)-1), y1(2*ibr_bp(jj))));
        end
        if online
            rs = sg.reconstruct(Z(isg,ix), y1);
            fsgH(ix)=rs.f_hz; omsgH(ix)=rs.omega;
            sg_delta(ix)=rs.delta; sg_id(ix)=rs.Id; sg_iq(ix)=rs.Iq;
            sg_P(ix)=rs.Pe; sg_Q(ix)=rs.Qe;
        else
            fsgH(ix)=NaN; omsgH(ix)=NaN; sg_delta(ix)=NaN; sg_id(ix)=NaN; sg_iq(ix)=NaN;
            sg_P(ix)=NaN; sg_Q(ix)=NaN;      % SG disconnected (breaker open)
        end
        sg_online_H(ix) = online;
        % reference / slack (angle-forming) device
        if online
            ref_code(ix)=0; ref_angle(ix)=sg_delta(ix);      % SG is the slack
        else
            gfm = find(md(ix,:)==1, 1);
            if isempty(gfm), ref_code(ix)=-1; ref_angle(ix)=NaN;   % unreferenced island
            else, ref_code(ix)=gfm; ref_angle(ix)=ang_ibr(ix,gfm); end
        end
    end
end
