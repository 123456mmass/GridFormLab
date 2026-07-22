function out = smib_tds_oracle(dev,x_eq,V_eq,u_eq,V_inf,Z_line,opt)
%SMIB_TDS_ORACLE Independent one-IBR/infinite-bus event-free TDS oracle.
%   OUT = ibr.smib_tds_oracle(DEV,X_EQ,V_EQ,U_EQ,V_INF,Z_LINE,OPT) treats the
%   infinite bus as an algebraic voltage source (no SG states):
%
%       g(x,V) = I_dev(x,V) - (V - V_inf)/Z_line = 0.
%
%   It runs a project-owned implicit-trapezoidal integration of the device
%   differential states coupled to the algebraic KCL, using the production
%   device f/current_injection closures. At every step a damped Newton solve
%   on z = [x; V] enforces both the trapezoidal residual and KCL.
%
%   This is an ASSUMED_DIAGNOSTIC falsification oracle, NOT a production TS
%   solver. It is generic over any device that exposes the standard ABI
%   (nx, nu, bus_position=1, f, current_injection, state_names,
%   active_state_indices). It does not call stability.ts_simulate_composite
%   or any shared composite TS path.
%
%   Gates produced:
%     - event-free equilibrium drift over [0,T];
%     - small-perturbation nonlinear TDS vs linear SSSA response
%       (expm(A*t)*dx0) comparison;
%     - perturbation-halving convergence;
%     - optional timestep-halving to separate nonlinear vs O(dt^2) error.
%
%   The Schur matrix A must be supplied by the caller (from smib_sssa_oracle)
%   for the linear-response comparison; this oracle does not recompute SSSA.

arguments
    dev (1,1) struct
    x_eq (:,1) double
    V_eq (1,1) double {mustBeFinite}
    u_eq (:,1) double
    V_inf (1,1) double {mustBeFinite}
    Z_line (1,1) double {mustBeFinite}
    opt.T (1,1) double {mustBePositive} = 0.05
    opt.dt (1,1) double {mustBePositive} = 1e-3
    opt.perturb_state (1,1) double {mustBeInteger} = 1
    opt.perturb_amp (1,1) double {mustBePositive} = 1e-3
    opt.perturb_amp_half (1,1) double {mustBePositive} = 5e-4
    opt.newton_tol (1,1) double {mustBePositive} = 1e-9
    opt.newton_max_iter (1,1) double {mustBeInteger,mustBePositive} = 50
    opt.fd_eps (1,1) double {mustBePositive} = 1e-6
    opt.A_linear (:,:) double = []
    opt.fault_on (1,1) double {mustBeNonnegative} = 0
    opt.fault_clear (1,1) double {mustBeNonnegative} = 0
    opt.fault_Zf (1,1) double = 0.10i
    opt.step_on (1,1) double {mustBeNonnegative} = 0
    opt.step_dV (1,1) double = -0.10
    opt.step_dphase_deg (1,1) double = 20
end

required = {'nx','nu','bus_position','f','current_injection','state_names'};
for k = 1:numel(required)
    if ~isfield(dev,required{k})
        error('ibr:smib_tds_oracle:deviceContract', ...
            'Device is missing required field %s.',required{k});
    end
end
if dev.bus_position ~= 1
    error('ibr:smib_tds_oracle:busPosition', ...
        'The standalone SMIB device must use bus_position=1.');
end
if numel(x_eq) ~= dev.nx || numel(u_eq) ~= dev.nu
    error('ibr:smib_tds_oracle:dimension', ...
        'x_eq/u_eq dimensions must equal dev.nx/dev.nu.');
end
if any(~isfinite(x_eq)) || any(~isfinite(u_eq)) || abs(V_eq) == 0 || ...
        abs(V_inf) == 0 || abs(Z_line) == 0
    error('ibr:smib_tds_oracle:nonfiniteInput', ...
        'Operating point, infinite-bus voltage and line impedance must be finite and nonzero.');
end

ec = struct();
y_eq = [real(V_eq);imag(V_eq)];
nx = dev.nx;
ny = 2;
active = local_active_indices(dev,ec);

f_handle = @(x,y) dev.f(0,x,y,u_eq,ec);
g_handle = @(x,y) local_g(dev,x,y,u_eq,ec,V_inf,Z_line);

% --- Event-free drift run --------------------------------------------------
[x_drift,y_drift,info_drift] = integrate_trap(f_handle,g_handle,x_eq,y_eq, ...
    opt.T,opt.dt,opt.newton_tol,opt.newton_max_iter,opt.fd_eps);
drift = x_drift(:,end) - x_eq;
max_drift = max(abs(drift));

% --- Small-perturbation run (full amplitude) -------------------------------
xp0 = x_eq;
xp0(opt.perturb_state) = xp0(opt.perturb_state) + opt.perturb_amp;
yp0 = local_solve_y(g_handle,xp0,y_eq,opt);
[xp,yp,info_p] = integrate_trap(f_handle,g_handle,xp0,yp0, ...
    opt.T,opt.dt,opt.newton_tol,opt.newton_max_iter,opt.fd_eps);
dxp = xp - x_drift;   % perturbation response (nonlinear)

% --- Small-perturbation run (half amplitude) ------------------------------
xh0 = x_eq;
xh0(opt.perturb_state) = xh0(opt.perturb_state) + opt.perturb_amp_half;
yh0 = local_solve_y(g_handle,xh0,y_eq,opt);
[xh,yh,info_h] = integrate_trap(f_handle,g_handle,xh0,yh0, ...
    opt.T,opt.dt,opt.newton_tol,opt.newton_max_iter,opt.fd_eps);
dxh = xh - x_drift;

% --- Linear SSSA response (expm(A*t)*dx0) ----------------------------------
lin_available = ~isempty(opt.A_linear);
if lin_available
    A = opt.A_linear(active,active);
    dx0_lin = zeros(nx,1);
    dx0_lin(opt.perturb_state) = opt.perturb_amp;
    % Project to active ordering.
    dx0_act = dx0_lin(active);
    tgrid = (0:opt.dt:opt.T).';
    dx_lin_act = zeros(numel(active),numel(tgrid));
    overflow = false;
    for kk = 1:numel(tgrid)
        step = expm(A*tgrid(kk))*dx0_act;
        if any(~isfinite(step))
            overflow = true;
            step(:) = NaN;
        end
        dx_lin_act(:,kk) = step;
    end
    % dx_lin is the linear perturbation response (already a deviation), directly
    % comparable to dxp = xp - x_drift (nonlinear perturbation response).
    dx_lin = zeros(nx,numel(tgrid));
    dx_lin(active,:) = dx_lin_act;
    x_lin = x_eq(:,ones(1,numel(tgrid))) + dx_lin;   % absolute linear trajectory
    if overflow
        % The linear SSSA response overflowed (an unstable eigenvalue drove
        % expm(A*t) to infinity). Report Inf honestly; the nonlinear TDS may
        % still be bounded by device nonlinearities. This is an honest
        % stability outcome, not a gate failure.
        nl_err = Inf;
        linear_overflow = true;
    else
        nl_err = max(abs(dxp(active,:) - dx_lin(active,:)),[],'all');
        linear_overflow = false;
    end
    % Perturbation-halving: nonlinear discrepancy should decrease ~2x when amp halves.
    dxh_act = dxh(active,:);
    half_ratio = max(abs(dxp(active,:) - 2*dxh_act),[],'all') / ...
        max(1,max(abs(dxp(active,:)),[],'all'));
else
    x_lin = [];
    dx_lin = [];
    nl_err = NaN;
    half_ratio = NaN;
    linear_overflow = false;
end

% --- Fault run (shunt fault impedance Z_f to ground at the terminal bus) ------
% A three-phase-to-ground fault is modelled as a shunt admittance 1/Z_f applied
% at the device terminal bus during [fault_on,fault_clear]; the KCL becomes
%   I_dev = (V - V_inf)/Z_line + V/Z_f    (the shunt draws V/Z_f during the fault)
% so the terminal voltage sags to a depth set by Z_f, then recovers on clearing.
% The device starts at the exact equilibrium (NO artificial perturbation): it is
% flat until the fault, responds during/after it, and rings down to equilibrium.
fault_enabled = opt.fault_on >= 0 && opt.fault_clear > opt.fault_on && abs(opt.fault_Zf) > 0;
fault_failed = false; fault_message = '';
if fault_enabled
    Ysh_of = @(t) double(t>=opt.fault_on && t<opt.fault_clear)/opt.fault_Zf;
    try
        [x_fault,y_fault,info_fault] = integrate_trap_tv(f_handle,dev,u_eq,ec,@(t)V_inf,Z_line, ...
            x_eq,y_eq,opt.T,opt.dt,opt.newton_tol,opt.newton_max_iter,opt.fd_eps,Ysh_of);
        signals_fault = ibr.smib_tds_signal_history(dev,x_fault,y_fault,u_eq,ec);
    catch ME
        % A too-severe (near-bolted) fault drives the terminal voltage below the
        % device balanced-domain floor; the reduced study model has no LVRT /
        % current limiter, so it fails closed. Do NOT crash the whole run: warn,
        % report the failure, and fall back to the event-free response.
        fault_failed = true;
        fault_message = ME.message;
        x_fault = []; y_fault = []; info_fault = []; signals_fault = [];
        fault_enabled = false;
        warning('ibr:smib_tds_oracle:faultTooSevere', ...
            ['Fault run failed: %s\nThe fault Z_f=%.4g%+.4gj pu is likely too ' ...
             'severe (terminal voltage below the balanced-domain floor; the ' ...
             'reduced model has no LVRT/current limiter). Use a larger Z_f ' ...
             '(e.g. >= 0.1j pu). Showing the event-free response instead.'], ...
            ME.message, real(opt.fault_Zf), imag(opt.fault_Zf));
    end
else
    x_fault = []; y_fault = []; info_fault = []; signals_fault = [];
end

% --- Grid step disturbance (permanent V_inf magnitude + phase step) -----------
% At step_on the infinite-bus voltage steps: magnitude -> (1+step_dV)*|V_inf|
% and angle jumps by step_dphase_deg (a classic PLL re-lock / re-synchronisation
% test, cf. Teodorescu Fig 4.7). The device is FLAT until the step, then the GFL
% PLL re-locks and the GFM swing re-synchronises to the new grid vector.
step_enabled = opt.step_on > 0;
if step_enabled
    Vstep = V_inf*(1+opt.step_dV)*exp(1i*opt.step_dphase_deg*pi/180);
    Vinf_of = @(t) V_inf*double(t<opt.step_on) + Vstep*double(t>=opt.step_on);
    try
        [x_step,y_step,info_step_run] = integrate_trap_tv(f_handle,dev,u_eq,ec,Vinf_of,Z_line, ...
            x_eq,y_eq,opt.T,opt.dt,opt.newton_tol,opt.newton_max_iter,opt.fd_eps,@(t)0);
        signals_step = ibr.smib_tds_signal_history(dev,x_step,y_step,u_eq,ec);
    catch ME
        step_enabled = false; x_step=[]; y_step=[]; info_step_run=[]; signals_step=[];
        warning('ibr:smib_tds_oracle:stepFailed', ...
            'Step-disturbance run failed: %s (try a smaller step).',ME.message);
    end
else
    x_step=[]; y_step=[]; info_step_run=[]; signals_step=[];
end

out = struct();
out.classification = 'ASSUMED_DIAGNOSTIC_SMIB_TDS_ORACLE';
out.device_id = dev.device_id;
out.device_type = dev.device_type;
out.state_names = dev.state_names;
out.active_state_indices = active;
out.x_eq = x_eq;
out.y_eq = y_eq;
out.u_eq = u_eq;
out.V_inf = V_inf;
out.Z_line = Z_line;
out.T = opt.T;
out.dt = opt.dt;
out.tgrid = (0:opt.dt:opt.T).';
out.x_drift = x_drift;
out.y_drift = y_drift;
out.max_drift = max_drift;
out.drift = drift;
out.perturb_state = opt.perturb_state;
out.perturb_amp = opt.perturb_amp;
out.perturb_amp_half = opt.perturb_amp_half;
out.x_perturbed = xp;
out.y_perturbed = yp;
out.dx_perturbed = dxp;
out.dx_perturbed_half = dxh;
out.x_linear = x_lin;
out.dx_linear = dx_lin;
out.linear_available = lin_available;
out.nonlinear_vs_linear_error = nl_err;
out.perturbation_halving_ratio = half_ratio;
out.linear_overflow = linear_overflow;
out.newton_info_drift = info_drift;
out.newton_info_perturbed = info_p;
out.signals_perturbed = ibr.smib_tds_signal_history( ...
    dev,xp,yp,u_eq,ec);
out.signals_drift = ibr.smib_tds_signal_history( ...
    dev,x_drift,y_drift,u_eq,ec);
out.newton_info_half = info_h;
out.fault_enabled = fault_enabled;
out.fault_failed = fault_failed;
out.fault_message = fault_message;
out.fault_on = opt.fault_on;
out.fault_clear = opt.fault_clear;
out.fault_Zf = opt.fault_Zf;
out.x_fault = x_fault;
out.y_fault = y_fault;
out.signals_fault = signals_fault;
out.newton_info_fault = info_fault;
out.step_enabled = step_enabled;
out.step_on = opt.step_on;
out.step_dV = opt.step_dV;
out.step_dphase_deg = opt.step_dphase_deg;
out.x_step = x_step;
out.y_step = y_step;
out.signals_step = signals_step;
out.newton_info_step = info_step_run;
end

% =========================================================================
function active = local_active_indices(dev,ec)
active = dev.active_state_indices;
if isa(active,'function_handle'), active = active(ec); end
active = active(:).';
if isempty(active) || any(~isfinite(active)) || any(active ~= fix(active)) || ...
        any(active < 1) || any(active > dev.nx) || numel(unique(active)) ~= numel(active)
    error('ibr:smib_tds_oracle:activeStateIndices', ...
        'Device active-state indices must be unique integers in 1:dev.nx.');
end
end

% =========================================================================
function g = local_g(dev,x,y,u,ec,V_inf,Z_line,Y_sh)
if nargin < 8, Y_sh = 0; end
I_dev = dev.current_injection(0,x,y,u,ec);
V = complex(y(1),y(2));
I_line = (V-V_inf)/Z_line;
mis = I_dev - I_line - V*Y_sh;   % V*Y_sh = shunt fault current V/Z_f during fault
g = [real(mis);imag(mis)];
end

% =========================================================================
function y = local_solve_y(gh,x,y0,opt)
y = y0;
for it = 1:opt.newton_max_iter
    r = gh(x,y);
    if norm(r,inf) <= opt.newton_tol, return; end
    h = opt.fd_eps;
    J = zeros(2);
    for j = 1:2
        yp=y; ym=y; yp(j)=yp(j)+h; ym(j)=ym(j)-h;
        J(:,j)=(gh(x,yp)-gh(x,ym))/(2*h);
    end
    if rcond(J) <= 1e-12
        error('ibr:smib_tds_oracle:algebraicJacobian', ...
            'Perturbed algebraic solve has ill-conditioned Jacobian.');
    end
    y = y-J\r;
    if any(~isfinite(y))
        error('ibr:smib_tds_oracle:algebraicNonfinite', ...
            'Perturbed algebraic solve generated a non-finite voltage.');
    end
end
error('ibr:smib_tds_oracle:algebraicNoConverge', ...
    'Perturbed algebraic solve did not converge in %d iterations.', ...
    opt.newton_max_iter);
end

% =========================================================================
function [X,Y,info] = integrate_trap(fh,gh,x0,y0,T,dt,tol,max_iter,fd_eps)
% Coupled implicit-trapezoidal: differential states + algebraic KCL.
% z = [x; y]; residual
%   r = [ x1 - x0 - 0.5*dt*(f0 + f1) ;  g1 ]
% Jacobian by centered finite differences.
n = numel(x0); m = numel(y0);
nsteps = round(T/dt);
X = zeros(n,nsteps+1);
Y = zeros(m,nsteps+1);
X(:,1) = x0;
Y(:,1) = y0;
conv_count = 0;
max_resid = zeros(nsteps,1);
for k = 1:nsteps
    x0k = X(:,k);
    y0k = Y(:,k);
    f0 = fh(x0k,y0k);
    z = [x0k; y0k];
    [z1,info_step] = newton_step(z,x0k,y0k,f0,fh,gh,n,m,dt,tol,max_iter,fd_eps);
    X(:,k+1) = z1(1:n);
    Y(:,k+1) = z1(n+1:end);
    conv_count = conv_count + info_step.converged;
    max_resid(k) = info_step.max_resid;
end
info = struct('steps',nsteps,'converged_count',conv_count, ...
    'max_resid_history',max_resid,'all_converged',conv_count==nsteps);
end

% =========================================================================
function [X,Y,info] = integrate_trap_tv(fh,dev,u,ec,Vinf_of,Z_line,x0,y0,T,dt,tol,max_iter,fd_eps,Ysh_of)
% Implicit-trapezoidal integrator with a TIME-VARYING infinite-bus voltage
% Vinf_of(t) AND shunt admittance Ysh_of(t) at the terminal bus. Used for both
% the shunt fault (Vinf const, Ysh = 1/Zf during the window) and the grid step
% disturbance (Vinf stepped, Ysh = 0). f is unchanged; the disturbance enters g.
n = numel(x0); m = numel(y0);
nsteps = round(T/dt);
X = zeros(n,nsteps+1); Y = zeros(m,nsteps+1);
X(:,1) = x0; Y(:,1) = y0;
conv_count = 0; max_resid = zeros(nsteps,1);
for k = 1:nsteps
    t1 = k*dt;
    Vinf_k = Vinf_of(t1); Ysh_k = Ysh_of(t1);
    gh = @(x,y) local_g(dev,x,y,u,ec,Vinf_k,Z_line,Ysh_k);
    x0k = X(:,k); y0k = Y(:,k);
    f0 = fh(x0k,y0k);
    z = [x0k; y0k];
    [z1,info_step] = newton_step(z,x0k,y0k,f0,fh,gh,n,m,dt,tol,max_iter,fd_eps);
    X(:,k+1) = z1(1:n); Y(:,k+1) = z1(n+1:end);
    conv_count = conv_count + info_step.converged;
    max_resid(k) = info_step.max_resid;
end
info = struct('steps',nsteps,'converged_count',conv_count, ...
    'max_resid_history',max_resid,'all_converged',conv_count==nsteps);
end

% =========================================================================
function [z1,info] = newton_step(z,x0k,y0k,f0,fh,gh,n,m,dt,tol,max_iter,fd_eps)
% Damped Newton on r(z) = [ x1 - x0 - 0.5*dt*(f0 + f1) ; g1 ].
z1 = z;
alpha = 1.0;
converged = false;
max_resid = NaN;
for it = 1:max_iter
    x1 = z1(1:n);
    y1 = z1(n+1:end);
    f1 = fh(x1,y1);
    g1 = gh(x1,y1);
    r = [x1 - x0k - 0.5*dt*(f0 + f1); g1];
    nr = norm(r,inf);
    max_resid = max(max_resid,nr);
    if nr <= tol
        converged = true;
        info = struct('converged',converged,'max_resid',max_resid);
        return;
    end
    J = fd_jacobian(z1,fh,gh,n,m,dt,fd_eps);
    if rcond(J) <= 1e-12
        error('ibr:smib_tds_oracle:newtonIllConditioned', ...
            'Newton Jacobian ill-conditioned at step (rcond=%.3e).',rcond(J));
    end
    dz = -J\r;
    % Simple damped line search: accept the full step; if non-finite, halve.
    for ls = 1:10
        z_try = z1 + alpha*dz;
        if all(isfinite(z_try))
            z1 = z_try;
            break;
        end
        alpha = alpha/2;
    end
    if ~all(isfinite(z1))
        error('ibr:smib_tds_oracle:newtonNonfinite', ...
            'Newton step generated a non-finite iterate.');
    end
end
info = struct('converged',converged,'max_resid',max_resid);
end

% =========================================================================
function J = fd_jacobian(z,fh,gh,n,m,dt,fd_eps)
% Centered FD of r(z) = [ x1 - x0 - 0.5*dt*(f0+f1) ; g1 ] w.r.t. z=[x1;y1].
% Only f1 and g1 depend on z; the x0,f0 terms are constants.
nz = n+m;
J = zeros(nz);
for j = 1:nz
    zp = z; zm = z;
    zp(j) = zp(j) + fd_eps;
    zm(j) = zm(j) - fd_eps;
    xp = zp(1:n); yp = zp(n+1:end);
    xm = zm(1:n); ym = zm(n+1:end);
    fp = fh(xp,yp);
    gp = gh(xp,yp);
    fm = fh(xm,ym);
    gm = gh(xm,ym);
    % dr/dz: top block d(x1 - 0.5*dt*f1)/dz = [I - 0.5*dt*df1/dx, -0.5*dt*df1/dy]
    % bottom block dg1/dz = [dg1/dx, dg1/dy]
    if j <= n
        J(1:n,j)   = ( (xp-xm) - 0.5*dt*(fp-fm) )/(2*fd_eps);
        J(n+1:end,j) = (gp-gm)/(2*fd_eps);
    else
        J(1:n,j)   = ( -0.5*dt*(fp-fm) )/(2*fd_eps);
        J(n+1:end,j) = (gp-gm)/(2*fd_eps);
    end
end
end
