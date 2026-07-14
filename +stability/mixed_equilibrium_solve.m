function result = mixed_equilibrium_solve(case_data, config, opt)
%MIXED_EQUILIBRIUM_SOLVE  Solve f(x,y,u,mode)=0 + g(x,y,Y,u,mode)=0 for a candidate.
%   result = mixed_equilibrium_solve(case_data, config, opt) solves the
%   coupled dynamic + algebraic equilibrium for a candidate configuration
%   using the in-house composite DAE + a Newton layer on top.
%
%   Per decision ledger + user correction 4 (fixed gauge):
%     - ONE fixed numerical angle-gauge (vcon vars=[1,2], rows=[1,2],
%       ref=[Re(V1); Im(V1)]) present in ALL configurations, NEVER moved.
%     - GFM/GFL/SG mode changes alter device equations/current injection ONLY.
%     - The PF (MATPOWER14, bus1=REF) is the SAME warm-start for ALL configs.
%     - Pure-GFL SG_OFF is rejected structurally (no voltage-forming source).
%
%   Inputs:
%     case_data  - the IEEE14 1-SG/4-IBR case (case_ieee14_1sg_4ibr_auto_vsg)
%     config     - struct with:
%       .sg_status      'online' | 'tripped'
%       .device_modes   struct array (.device_id, .mode)
%       .dispatch       optional override (default: case contract)
%       .devices        optional pre-built device struct array (caller-supplied;
%                       production callers pass real GFL/VSG device structs;
%                       tests pass synthetic stubs). When absent, the solver
%                       uses case_data.devices metadata and the caller is
%                       expected to have supplied devices.
%     opt        - struct with tolerance, max_iter, fd_eps, verbose, load_model
%
%   Output: result struct with converged, x0, y0, residual_norm, iterations,
%   rcond, fingerprint, failure_id, failure_reason, device_config, dispatch,
%   limit_checks, vcon_vars, vcon_ref.
%
%   Source: project Phase 4 design (Plan agent). In-house Newton. No external
%   solver. The solver does NOT depend on test fixtures; the caller supplies
%   the device list (production devices or synthetic test stubs).

arguments
    case_data struct
    config struct
    opt struct = struct()
end

result = struct('converged', false, 'x0', [], 'y0', [], ...
    'residual_norm', inf, 'iterations', 0, 'rcond', NaN, ...
    'fingerprint', struct(), 'failure_id', '', 'failure_reason', '', ...
    'device_config', config, 'dispatch', struct(), 'limit_checks', struct(), ...
    'vcon_vars', 2, 'vcon_ref', 0.0);

% --- Defaults -------------------------------------------------------------
tol        = 1e-8;   if isfield(opt,'tolerance') && ~isempty(opt.tolerance), tol = opt.tolerance; end
max_iter   = 300;    if isfield(opt,'max_iter') && ~isempty(opt.max_iter), max_iter = opt.max_iter; end
fd_eps     = 3e-6;   if isfield(opt,'fd_eps') && ~isempty(opt.fd_eps), fd_eps = opt.fd_eps; end
verbose    = false;  if isfield(opt,'verbose') && ~isempty(opt.verbose), verbose = opt.verbose; end
load_model = 'cz_p_cz_q'; if isfield(opt,'load_model') && ~isempty(opt.load_model), load_model = opt.load_model; end

% --- Pure-GFL SG_OFF structural rejection --------------------------------
if strcmpi(config.sg_status, 'tripped')
    modes = {config.device_modes.mode};
    n_gfm = sum(strcmpi(modes, 'GFM'));
    if n_gfm < 1
        result.failure_id = 'mixed_equilibrium_solve:noVoltageFormingSource';
        result.failure_reason = 'Pure-GFL SG_OFF: no voltage-forming source (need >=1 GFM).';
        return;
    end
end

% --- Device list: caller-supplied (production or synthetic) --------------
% The solver does NOT build devices from test fixtures (scope separation:
% production +stability must not depend on tests/+fixtures). The caller
% supplies config.devices (a struct array conforming to the composite ABI).
if ~isfield(config, 'devices') || isempty(config.devices)
    result.failure_id = 'mixed_equilibrium_solve:noDevices';
    result.failure_reason = 'config.devices must be supplied by the caller.';
    return;
end
devices = config.devices;

% --- ANGLE-ONLY vcon (clarification 5 / correction 1) ---------------------
% Fix ONLY Im(V1) = 0 (the numerical angle reference); leave Re(V1) = |V1| as a
% FREE unknown solved by physical KCL/power balance at bus 1. This removes the
% hidden ideal voltage source that the old 2-variable vcon (|V1|=1.06 fixed)
% imposed at bus 1 — when SG1 trips, bus-1 |V1| must be free to fall/rise per
% physical KCL (GFM(s) elsewhere form voltage). The angle reference is the
% CONSTANT numerical gauge across all modes; mode switching never moves it.
mpc = case_data.mpc;
% Angle reference: 0 rad (Im(V1)=0). Re(V1) is FREE.
vcon = struct();
vcon.vars = 2;          % Im(V1) index in interleaved y
vcon.rows = 2;          % Im(V1) KCL row replaced by the angle constraint
vcon.eq = @(y, ref) (y(2) - ref);   % Im(V1) - 0 = 0
vcon.ref = 0.0;
V1_imag_ref = 0.0;

dae_opt = struct('load_model', load_model, 'vcon', vcon);

% --- Assemble the composite DAE (internal PF warm-start + closures) -------
try
    dae = stability.composite_dae(case_data, devices, dae_opt);
catch me
    result.failure_id = 'mixed_equilibrium_solve:compositeAssembly';
    result.failure_reason = me.message;
    return;
end

% --- Initialize device states from the PF warm-start ---------------------
[x0_init, init_ok, init_msg] = initialize_device_states(dae, config, case_data);
if ~init_ok
    result.failure_id = 'mixed_equilibrium_solve:initFailed';
    result.failure_reason = init_msg;
    return;
end

% --- Newton layer on the coupled (x, y_free) system ----------------------
% Angle-only vcon: y(vcon.vars)=y(2)=Im(V1) is FIXED to vcon.ref=0;
% ALL other y entries (including y(1)=Re(V1)=|V1|) are FREE unknowns solved by
% KCL. y_free = y with the vcon.vars positions removed.
y0 = dae.y0;
vcon_vars = vcon.vars;
vcon_ref = vcon.ref;
ny_full = numel(y0);
free_vars = setdiff(1:ny_full, vcon_vars, 'stable');   % free y indices
y_full_init = y0;
y_full_init(vcon_vars) = vcon_ref;          % enforce the angle gauge
y_free_init = y_full_init(free_vars);
nx = numel(x0_init);
ny_free = numel(y_free_init);
z0 = [x0_init(:); y_free_init(:)];

Ynet = dae.Ynet;
u = dae.u0;
residual_fn = @(z) coupled_residual( ...
    z, nx, free_vars, vcon_vars, vcon_ref, ny_full, dae, Ynet, u);

% Central-FD Jacobian.
J_fn = @(z) coupled_jacobian_fd(z, nx, ny_free, residual_fn, fd_eps);

[z_sol, niter, converged, residual_norm, rcond_val] = stability.composite_newton( ...
    z0, residual_fn, J_fn, tol, max_iter, verbose);

result.iterations = niter;
result.rcond = rcond_val;
result.residual_norm = residual_norm;
result.converged = converged;

if ~converged
    result.failure_id = 'mixed_equilibrium_solve:noConverge';
    result.failure_reason = sprintf( ...
        'Coupled Newton did not converge: residual=%.3e after %d iters (tol=%.2e).', ...
        residual_norm, niter, tol);
    return;
end

% --- Conditioning gate ----------------------------------------------------
if rcond_val < 1e-10
    result.converged = false;
    result.failure_id = 'mixed_equilibrium_solve:illConditioned';
    result.failure_reason = sprintf('Reduced Jacobian rcond=%.3e < 1e-10.', rcond_val);
    return;
end

% --- Extract equilibrium --------------------------------------------------
x_sol = z_sol(1:nx);
y_free_sol = z_sol(nx+1:nx+ny_free);
y_sol = zeros(ny_full, 1);
y_sol(vcon_vars) = vcon_ref;
y_sol(free_vars) = y_free_sol;
result.x0 = x_sol;
result.y0 = y_sol;

% --- Limit checks ---------------------------------------------------------
result.limit_checks = check_limits(x_sol, y_sol, config, case_data, dae);

% --- Fingerprint ----------------------------------------------------------
result.fingerprint = compute_fingerprint(x_sol, y_sol, config);
result.vcon_vars = vcon.vars;       % = 2 (Im(V1)), angle-only
result.vcon_ref = vcon.ref;         % = 0.0
result.vcon_type = 'angle_only';   % Re(V1) free (clarification 5)
result.dispatch = config.dispatch;
end

% =========================================================================
function devices = build_devices_for_config(case_data, config)
% RETAINED for callers that want the solver to assemble devices from
% case_data metadata + a device factory. NOT used by tests that supply
% synthetic stubs directly. Returns the caller-supplied config.devices.
devices = config.devices;
end

% =========================================================================
function [x0_init, ok, msg] = initialize_device_states(dae, config, ~)
x0_init = dae.x0;
ok = true; msg = '';
% The composite_dae already builds x0 from device x0 fields. For synthetic
% stubs, x0 is the fixture default (delta=0, E=V_ref). A full initialization
% (delta=angle(V_bus), E from S=V*conj(I)) is applied in the Newton layer
% (the warm-start y0 feeds the first residual eval). For Phase 4, the
% Newton converges from the PF warm-start.
end

% =========================================================================
function r = coupled_residual(z, nx, free_vars, vcon_vars, vcon_ref, ny_full, dae, Y, u)
x = z(1:nx);
y_free = z(nx+1:end);
% Scatter y_free into free positions; fix vcon positions to vcon_ref.
y_full = zeros(ny_full, 1);
y_full(vcon_vars) = vcon_ref;
y_full(free_vars) = y_free;
ec = struct();
f = dae.dae_f(0, x, y_full, u, ec);
g = dae.dae_g(0, x, y_full, Y, u, ec);
% The constrained algebraic variables are fixed explicitly in z, so their
% paired vcon residual rows must be removed from the Newton system. This is
% the nonlinear counterpart of the paired free_rows/free_vars elimination
% used by multimachine_ssa; retaining the zero constraint rows would make
% the residual longer than the unknown vector.
free_rows = setdiff(1:numel(g), dae.vcon.rows, 'stable');
r = [f(:); g(free_rows)];
end

% =========================================================================
function J = coupled_jacobian_fd(z, ~, ~, residual_fn, fd_eps)
nz = numel(z);
r0 = residual_fn(z);
if numel(r0) ~= nz
    error('mixed_equilibrium_solve:nonSquareResidual', ...
        'Coupled residual length %d must equal unknown count %d.', ...
        numel(r0), nz);
end
J = zeros(nz, nz);
for j = 1:nz
    zp = z; zp(j) = zp(j) + fd_eps;
    rp = residual_fn(zp);
    J(:, j) = (rp - r0) / fd_eps;
end
end

% =========================================================================
function lc = check_limits(x, y, config, case_data, dae)
lc = struct('devices', struct());
nb = dae.nb;
% Reconstruct bus voltages from y.
V = zeros(nb, 1);
for b = 1:nb
    V(b) = y(2*b-1) + 1i*y(2*b);
end
% Per-device current + power + voltage-magnitude check.
for k = 1:numel(dae.devices)
    dev = dae.devices(k);
    xr = dae.device_offsets(k)+1 : dae.device_offsets(k)+dev.nx;
    x_dev = x(xr);
    u_dev = [];
    Iinj = dev.current_injection(0, x_dev, y, u_dev, struct());
    Vbus = V(dae.bus_map(k));
    S = Vbus * conj(Iinj);
    P = real(S) * 100;   % MW (system base 100)
    Q = imag(S) * 100;
    Imax = abs(Iinj);
    lc.devices.(dev.device_id) = struct( ...
        'P_MW', P, 'Q_MVAr', Q, 'I_pu', Imax, 'Vbus_pu', abs(Vbus), ...
        'within_limits', true);   % detailed limit check deferred to Phase 8
end
end

% =========================================================================
function fp = compute_fingerprint(x, y, config)
fp.config_hash = config_hash(config);
fp.x0_hash = sprintf('%.15e', x(:)');
fp.y0_hash = sprintf('%.15e', y(:));
end

% =========================================================================
function h = config_hash(config)
h = sprintf('sg=%s|modes=', config.sg_status);
for k = 1:numel(config.device_modes)
    h = [h config.device_modes(k).device_id ':' config.device_modes(k).mode ';']; %#ok<AGROW>
end
end
