function eq = smib_loaded_equilibrium(dev, V_inf, Z_line, P_load, Q_load, P_ibr_ref, Q_ibr_ref, opt)
%SMIB_LOADED_EQUILIBRIUM  Newton equilibrium for one loaded IBR to infinite bus.
%   EQ = ibr.smib_loaded_equilibrium(DEV, V_INF, Z_LINE, P_LOAD, Q_LOAD, ...
%   P_IBR_REF, Q_IBR_REF, OPT) solves the coupled device/network equilibrium
%   for a single IBR connected to an ideal infinite bus through Z_LINE with a
%   constant-power shunt load (P_LOAD, Q_LOAD) at the IBR terminal bus.
%
%   Dispatch policy (ASSUMED_DIAGNOSTIC): the IBR receives the incremental
%   load. Its active/reactive references P_IBR_REF, Q_IBR_REF track the load
%   level set by the sweep. The infinite bus absorbs the change in line flow.
%
%   Residuals (the IBR device closures are used UNCHANGED):
%       f(x, V, u) = dev.f(0, x, y, u, ec)              = 0   (device differential)
%       g(x, V, u) = I_ibr(x,V,u) - (V - V_inf)/Z_line
%                                 - conj((P_load + j Q_load)/V) = 0   (terminal KCL)
%   where y = [real(V); imag(V)].
%
%   Unknowns: x (dev.nx states) and y (2 terminal-voltage components). The
%   device inputs u are held fixed at [P_IBR_REF; Q_IBR_REF] (GFL) or
%   [P_IBR_REF; V_REF] (GFM), with V_REF taken from dev.u0(2). No PF
%   redispatch policy is claimed; this is an ASSUMED_DIAGNOSTIC equilibrium.
%
%   No inv/pinv; audited Newton with FD Jacobian and backtracking line search.
%   Fail-closed on non-convergence, ill-conditioned Jacobian, or non-finite
%   iterates. Tm/Efd are not applicable (IBR, no SG).

arguments
    dev (1,1) struct
    V_inf (1,1) double {mustBeFinite}
    Z_line (1,1) double {mustBeFinite}
    P_load (1,1) double {mustBeReal,mustBeFinite}
    Q_load (1,1) double {mustBeReal,mustBeFinite}
    P_ibr_ref (1,1) double {mustBeReal,mustBeFinite}
    Q_ibr_ref (1,1) double {mustBeReal,mustBeFinite}
    opt struct = struct()
end

tol = 1e-10;
if isfield(opt,'tolerance') && ~isempty(opt.tolerance), tol = opt.tolerance; end
max_iter = 100;
if isfield(opt,'max_iter') && ~isempty(opt.max_iter), max_iter = opt.max_iter; end
fd_eps = 1e-6;
if isfield(opt,'fd_eps') && ~isempty(opt.fd_eps), fd_eps = opt.fd_eps; end
verbose = false;
if isfield(opt,'verbose') && ~isempty(opt.verbose), verbose = logical(opt.verbose); end

required = {'nx','nu','bus_position','f','current_injection','equilibrium_initialize'};
for k = 1:numel(required)
    if ~isfield(dev,required{k})
        error('ibr:smib_loaded_equilibrium:deviceContract', ...
            'Device is missing required field %s.',required{k});
    end
end
if dev.bus_position ~= 1
    error('ibr:smib_loaded_equilibrium:busPosition', ...
        'The standalone SMIB device must use bus_position=1.');
end

% Device input u: IBR-receives-incremental-load dispatch.
% GFL: u = [P_ref; Q_ref] (both track load).
% GFM: u = [P_ref; V_ref] (P tracks load; V_ref from dev.u0(2) held fixed).
u = dev.u0;
u(1) = P_ibr_ref;
if numel(u) >= 2 && isfield(dev,'device_type') && ...
        strcmp(char(dev.device_type),'ibr_gfm_vsg_no_pll')
    % GFM: V_ref held at the device's frozen V_ref (u0(2)).
    u(2) = dev.u0(2);
else
    % GFL: Q_ref tracks load.
    u(2) = Q_ibr_ref;
end

ec = struct();
% 2-stage initialization:
%   Stage 1: solve terminal voltage V from KCL using an approximate IBR
%   current I_ibr ~ conj((P_ibr_ref + j Q_ibr_ref)/V). With this
%   approximation the KCL becomes a scalar quadratic in V that has a
%   well-conditioned solution near V_inf.
%   Stage 2: initialize device states at the Stage-1 V via the device's own
%   equilibrium_initialize, then run a coupled Newton refinement on [x; V].
%
%   GFM special case: the device equilibrium_initialize requires (V,P,Q,V_ref)
%   consistent with the Q-V droop voltage law. Q is an OUTPUT of the droop,
%   not a fixed setpoint. Solve Q at Stage-1 V via the same voltage-law
%   bisection the device uses, then initialize. GFL has no such law (Q is a
%   setpoint), so it uses Q_ibr_ref directly.
V_guess = solve_voltage_stage1(V_inf, Z_line, P_load, Q_load, P_ibr_ref, Q_ibr_ref);
is_gfm = isfield(dev,'device_type') && strcmp(char(dev.device_type),'ibr_gfm_vsg_no_pll');
if is_gfm
    Q_init = solve_gfm_consistent_Q(V_guess, P_ibr_ref, dev, Q_ibr_ref);
else
    Q_init = Q_ibr_ref;
end
x0 = dev.equilibrium_initialize(V_guess, P_ibr_ref, Q_init, ec);
y0 = [real(V_guess); imag(V_guess)];

f_handle = @(x,y) dev.f(0,x,y,u,ec);
g_handle = @(x,y) local_g(dev,x,y,u,ec,V_inf,Z_line,P_load,Q_load);

z = [x0(:); y0(:)];
f0 = f_handle(z(1:dev.nx), z(dev.nx+1:dev.nx+2));
g0 = g_handle(z(1:dev.nx), z(dev.nx+1:dev.nx+2));
r0 = [f0(:); g0(:)];
residual_norm = norm(r0,inf);
converged = residual_norm <= tol;
iterations = 0;
rcond_val = NaN;

while ~converged && iterations < max_iter
    iterations = iterations + 1;
    x = z(1:dev.nx);
    y = z(dev.nx+1:dev.nx+2);
    J = fd_jacobian(f_handle, g_handle, x, y, fd_eps, dev.nx);
    rcond_val = rcond(J);
    if ~isfinite(rcond_val) || rcond_val <= 1e-12
        eq = struct('converged',false,'failure_id', ...
            'smib_loaded_equilibrium:illConditioned', ...
            'failure_reason',sprintf('Jacobian rcond %.3e <= 1e-12.',rcond_val), ...
            'iterations',iterations,'residual_norm',residual_norm, ...
            'rcond',rcond_val);
        return;
    end
    dz = -(J \ r0);
    % Backtracking line search (no trust-region; simple Armijo-style backtrack).
    step = 1.0;
    accepted = false;
    for bt = 1:20
        z_new = z + step*dz;
        if any(~isfinite(z_new)), step = step/2; continue; end
        x_new = z_new(1:dev.nx);
        y_new = z_new(dev.nx+1:dev.nx+2);
        f_new = f_handle(x_new, y_new);
        g_new = g_handle(x_new, y_new);
        r_new = [f_new(:); g_new(:)];
        if norm(r_new,inf) < (1 - 1e-4*step)*norm(r0,inf)
            z = z_new; r0 = r_new;
            accepted = true; break;
        end
        step = step/2;
    end
    if ~accepted
        eq = struct('converged',false,'failure_id', ...
            'smib_loaded_equilibrium:noProgress', ...
            'failure_reason','Newton line search made no progress.', ...
            'iterations',iterations,'residual_norm',residual_norm, ...
            'rcond',rcond_val);
        return;
    end
    residual_norm = norm(r0,inf);
    converged = residual_norm <= tol;
    if verbose
        fprintf('  smib_loaded_equilibrium iter %d: ||r||=%.4e rcond=%.3e\n', ...
            iterations, residual_norm, rcond_val);
    end
end

x_eq = z(1:dev.nx);
y_eq = z(dev.nx+1:dev.nx+2);
V_eq = complex(y_eq(1), y_eq(2));
f_eq = f_handle(x_eq, y_eq);
g_eq = g_handle(x_eq, y_eq);

eq = struct();
eq.converged = converged;
eq.failure_id = '';
eq.failure_reason = '';
eq.x0 = x_eq;
eq.y0 = y_eq;
eq.u_eq = u;
eq.V_terminal = V_eq;
eq.V_inf = V_inf;
eq.Z_line = Z_line;
eq.P_load = P_load;
eq.Q_load = Q_load;
eq.P_ibr_ref = P_ibr_ref;
eq.Q_ibr_ref = Q_ibr_ref;
eq.f0 = f_eq;
eq.g0 = g_eq;
eq.residual_norm = residual_norm;
eq.iterations = iterations;
eq.rcond = rcond_val;
eq.device = dev;
eq.classification = 'ASSUMED_DIAGNOSTIC_SMIB_LOADED_EQUILIBRIUM';
if ~converged
    eq.failure_id = 'smib_loaded_equilibrium:noConverge';
    eq.failure_reason = sprintf( ...
        'Coupled Newton did not converge: residual=%.3e after %d iters (tol=%.2e).', ...
        residual_norm, iterations, tol);
end
end

% =========================================================================
function Q0 = solve_gfm_consistent_Q(V, P_ibr, dev, Q_guess)
% Solve the GFM Q-V droop voltage law for the reactive power Q that makes
%   V_ref - m_q*(kappa*Q - Q_ref) = |V + jX_L*kappa*conj((P_ibr + jQ)/V)|
% consistent at the given (V, P_ibr, V_ref). This is the SAME bisection the
% GFM device uses internally (ibr.gfm_vsg_no_pll_model/solve_consistent_Q);
% re-implemented here because the device does not expose it. The device
% params come from dev.provenance.params; V_ref comes from dev.u0(2).
if ~isfield(dev,'provenance') || ~isfield(dev.provenance,'params')
    error('ibr:smib_loaded_equilibrium:gfmParams', ...
        'GFM device must expose provenance.params for Q-consistency solve.');
end
p = dev.provenance.params;
kappa = p.kappa; X_L = p.X_L; m_q = p.m_q; Q_ref = p.Q_ref;
eq_tol = p.eq_tol;
V_ref = dev.u0(2);
r_handle = @(Q) voltage_law_residual(Q, V, P_ibr, kappa, X_L, m_q, Q_ref, V_ref);
Qspan = 2.0;
Qlo = -Qspan; Qhi = Qspan;
flo = r_handle(Qlo); fhi = r_handle(Qhi);
if flo == 0, Q0 = Qlo; return; end
if fhi == 0, Q0 = Qhi; return; end
if flo*fhi > 0
    % No sign change: use the Q_guess (base value) as a fallback; the coupled
    % Newton refinement will correct it. (This happens when V is far from the
    % voltage-law feasibility region; the device equilibrium_initialize will
    % fail closed if the guess is truly infeasible.)
    Q0 = Q_guess;
    return;
end
for it = 1:200
    Qmid = 0.5*(Qlo+Qhi);
    fmid = r_handle(Qmid);
    if abs(fmid) <= eq_tol*max(1.0,abs(V_ref))
        Q0 = Qmid; return;
    end
    if flo*fmid < 0
        Qhi = Qmid; fhi = fmid;
    else
        Qlo = Qmid; flo = fmid;
    end
    if abs(Qhi-Qlo) <= eq_tol*max(1.0,abs(Qlo))
        Q0 = 0.5*(Qlo+Qhi); return;
    end
end
Q0 = 0.5*(Qlo+Qhi);
end

% =========================================================================
function r = voltage_law_residual(Q,V,P,kappa,X_L,m_q,Q_ref,V_ref)
I_sys = conj((P+1i*Q)/V);
I_inv = kappa*I_sys;
E_internal = V + 1i*X_L*I_inv;
E_vsm_law = V_ref - m_q*(kappa*Q - Q_ref);
r = E_vsm_law - abs(E_internal);
end

% =========================================================================
function V = solve_voltage_stage1(V_inf, Z_line, P_load, Q_load, P_ibr, Q_ibr)
% Stage-1 voltage solve: assume IBR current is approximately its setpoint
% current at the terminal voltage, I_ibr ~ conj((P_ibr + j Q_ibr)/V). Then KCL
%   conj((P_ibr+jQ_ibr)/V) - (V-V_inf)/Z - conj((P_load+jQ_load)/V) = 0
% Multiply through by V and solve the resulting quadratic for V.
% This is an APPROXIMATE initial guess for the coupled Newton refinement;
% it is not the final equilibrium.
S_ibr = complex(P_ibr, Q_ibr);
S_load = complex(P_load, Q_load);
% V*conj((S_ibr-S_load)/V) = (V - V_inf)/Z * V
% => conj(S_ibr - S_load) = (V^2 - V_inf*V)/Z   (treat V as complex scalar)
% Rearrange: V^2 - V_inf*V - Z*conj(S_ibr - S_load) = 0
c = -Z_line * conj(S_ibr - S_load);
% V^2 - V_inf*V + c = 0 -> V = (V_inf +/- sqrt(V_inf^2 - 4c))/2
disc = V_inf^2 - 4*c;
sq = sqrt(disc);
% Two roots; pick the one closer to V_inf (physical terminal voltage near
% the infinite bus for a short line).
V_plus = (V_inf + sq)/2;
V_minus = (V_inf - sq)/2;
if abs(V_plus - V_inf) <= abs(V_minus - V_inf)
    V = V_plus;
else
    V = V_minus;
end
if abs(V) < 1e-6 || ~isfinite(V)
    V = V_inf;
end
end

% =========================================================================
function g = local_g(dev,x,y,u,ec,V_inf,Z_line,P_load,Q_load)
I_ibr = dev.current_injection(0,x,y,u,ec);
V = complex(y(1),y(2));
I_line = (V-V_inf)/Z_line;
I_load = conj((complex(P_load,Q_load))/V);   % constant-power load current
mis = I_ibr - I_line - I_load;
g = [real(mis);imag(mis)];
end

% =========================================================================
function J = fd_jacobian(fh,gh,x,y,h,nx)
nx_total = numel(x) + numel(y);
f0x = fh(x,y); g0x = gh(x,y);
r0 = [f0x(:); g0x(:)];
J = zeros(nx_total, nx_total);
for j = 1:numel(x)
    xp = x; xp(j) = xp(j) + h;
    fp = fh(xp,y); gp = gh(xp,y);
    J(:,j) = ([fp(:); gp(:)] - r0) / h;
end
for j = 1:numel(y)
    yp = y; yp(j) = yp(j) + h;
    fp = fh(x,yp); gp = gh(x,yp);
    J(:,numel(x)+j) = ([fp(:); gp(:)] - r0) / h;
end
end
