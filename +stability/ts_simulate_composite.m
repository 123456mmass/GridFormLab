function [ts_result, ts_meta] = ts_simulate_composite(case_data, devices, x0, y0, opt)
%TS_SIMULATE_COMPOSITE  Fixed-step composite TS driver (trapezoidal, no events).
%   [TS_RESULT, TS_META] = ts_simulate_composite(CASE_DATA, DEVICES, X0, Y0, OPT)
%   runs a fixed-step trapezoidal time-domain simulation for a mixed SG+IBR
%   system using the composite DAE ABI (5-arg closures).
%
%   Coupled trapezoidal residual (correction 7):
%     R_x = x1 - x0 - h/2*(f(x1,y1,u) + f(x0,y0,u))
%     R_g = g_free(x1, y1, Y, u)
%   Solved simultaneously by composite_newton (NOT Picard iteration).
%
%   STATUS: STRUCTURAL_ONLY (Phase B2 vertical slice). No events, no mode
%   switching, no limiter, no fault. Fixed-step only.
%
%   Audited physical-operating-point path (opt-in):
%     opt.full_kcl=true requires opt.u_eq, opt.event_context, and
%     opt.dynamic_state_indices from mixed_equilibrium_solve. The solved
%     operating-point input is held constant throughout TS; reference P is
%     never re-solved per step. All physical KCL rows participate and the
%     complement of dynamic_state_indices is held at the supplied x0 anchor.
%     This map may include breaker-open SG coast/flux states that were excluded
%     from the stationary equilibrium active set.
%   The default path retains the original angle-vcon/reduced-KCL behavior.
%
%   Source: execution plan §B2; correction 7 (coupled trapezoidal).

arguments
    case_data struct
    devices struct
    x0 (:,1) double
    y0 (:,1) double
    opt struct = struct()
end

t_end   = 5.0;   if isfield(opt,'t_end') && ~isempty(opt.t_end), t_end = opt.t_end; end
dt      = 0.01;  if isfield(opt,'dt') && ~isempty(opt.dt), dt = opt.dt; end
verbose = false; if isfield(opt,'verbose') && ~isempty(opt.verbose), verbose = opt.verbose; end
newton_tol = 1e-8;
max_iter   = 50;
fd_eps     = 3e-6;
load_model = 'cz_p_cz_q';
if isfield(opt,'load_model') && ~isempty(opt.load_model), load_model = opt.load_model; end
full_kcl = false;
if isfield(opt,'full_kcl') && ~isempty(opt.full_kcl)
    full_kcl = opt.full_kcl;
    if ~isscalar(full_kcl) || ...
            ~(islogical(full_kcl) || (isnumeric(full_kcl) && isreal(full_kcl) && ...
            isfinite(full_kcl) && any(full_kcl == [0,1])))
        error('ts_simulate_composite:badFullKcl', ...
            'opt.full_kcl must be one finite logical scalar.');
    end
    full_kcl = logical(full_kcl);
end

% --- Build composite DAE --------------------------------------------------
if full_kcl
    % During TS, the differential-state history anchors the frame; no
    % physical KCL row is replaced by a coordinate equation.
    dae_opt = struct('load_model', load_model);
else
    vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
    dae_opt = struct('load_model', load_model, 'vcon', vcon);
end
dae = stability.composite_dae(case_data, devices, dae_opt);

% --- Detect frozen state indices (metadata from devices) -------------------
if full_kcl
    if numel(x0) ~= numel(dae.x0) || numel(y0) ~= numel(dae.y0)
        error('ts_simulate_composite:badOperatingPointSize', ...
            'x0/y0 dimensions must match the assembled composite DAE.');
    end
    if ~isfield(opt,'dynamic_state_indices') || isempty(opt.dynamic_state_indices)
        error('ts_simulate_composite:missingDynamicStates', ...
            'opt.dynamic_state_indices is required when opt.full_kcl=true.');
    end
    active_x_indices = opt.dynamic_state_indices(:)';
    if ~isnumeric(active_x_indices) || ~isreal(active_x_indices) || ...
            any(~isfinite(active_x_indices)) || ...
            any(active_x_indices ~= fix(active_x_indices)) || ...
            any(active_x_indices < 1) || any(active_x_indices > numel(x0)) || ...
            numel(unique(active_x_indices)) ~= numel(active_x_indices)
        error('ts_simulate_composite:badDynamicStates', ...
            'opt.dynamic_state_indices must contain unique in-range integers.');
    end
    frozen_x_indices = setdiff(1:numel(x0),active_x_indices,'stable');
    frozen_x_values = x0(frozen_x_indices).';
else
    frozen_x_indices = [];
    frozen_x_values  = [];
    active_x_indices = 1:numel(x0);
    for dk = 1:numel(dae.devices)
        dev = dae.devices(dk);
        if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
            off = dae.device_offsets(dk);
            fsi = dev.frozen_state_indices(:)';
            fsv = dev.frozen_state_values(:)';
            frozen_x_indices = [frozen_x_indices, off + fsi]; %#ok<AGROW>
            frozen_x_values  = [frozen_x_values, fsv]; %#ok<AGROW>
        end
    end
    active_x_indices = setdiff(active_x_indices, frozen_x_indices, 'stable');
end

% --- y indices: vcon-constrained vs free ----------------------------------
ny_full = numel(y0);
if full_kcl
    vcon_vars = [];
    vcon_ref = [];
    free_vars = 1:ny_full;
    y0_full = y0;
else
    vcon_vars = dae.vcon.vars;
    vcon_ref  = dae.vcon.ref;
    free_vars = setdiff(1:ny_full, vcon_vars, 'stable');
    y0_full = y0;
    y0_full(vcon_vars) = vcon_ref;
end

% --- Operating-point inputs/context ---------------------------------------
if full_kcl
    if ~isfield(opt,'u_eq') || isempty(opt.u_eq)
        error('ts_simulate_composite:missingEquilibriumInput', ...
            'opt.u_eq is required when opt.full_kcl=true.');
    end
    u = opt.u_eq(:);
    if ~isnumeric(u) || ~isreal(u) || numel(u) ~= numel(dae.u0) || ...
            any(~isfinite(u))
        error('ts_simulate_composite:badEquilibriumInput', ...
            'opt.u_eq must be a finite vector matching the composite input dimension.');
    end
    if ~isfield(opt,'event_context') || ~isstruct(opt.event_context) || ...
            ~isscalar(opt.event_context)
        error('ts_simulate_composite:badEventContext', ...
            'opt.event_context must be the scalar equilibrium context when opt.full_kcl=true.');
    end
    ec = opt.event_context;
    expected_dynamic = expected_dynamic_indices(dae,ec);
    if ~isequal(active_x_indices(:)',expected_dynamic(:)')
        error('ts_simulate_composite:dynamicStateMismatch', ...
            ['opt.dynamic_state_indices must exactly match the device/runtime ' ...
             'dynamic partition for opt.event_context.']);
    end
else
    u = dae.u0;
    ec = struct();
end

% --- Time loop -------------------------------------------------------------
n_steps = ceil(t_end / dt);
t_vals = (0:n_steps) * dt;
nx_total = numel(x0);
nx_active = numel(active_x_indices);
ny_free = numel(free_vars);

x_traj = zeros(nx_total, n_steps+1);
y_traj = zeros(ny_full, n_steps+1);
x_traj(:,1) = x0(:);
y_traj(:,1) = y0_full(:);

x_curr = x0(:);
y_curr = y0_full(:);
Ynet = dae.Ynet;
converged = true;

for step = 1:n_steps
    t_now = (step-1)*dt;
    % Evaluate f0 at state start
    f0 = dae.dae_f(t_now, x_curr, y_curr, u, ec);

    % --- Coupled trapezoidal Newton: solve z = [x1_active; y1_free] --------
    % z = [x1(active); y1(free)]
    z0 = [x_curr(active_x_indices); y_curr(free_vars)];

    residual_fn = @(z) trapezoidal_residual(z, x_curr, f0, dt, ...
        active_x_indices, frozen_x_indices, frozen_x_values, ...
        free_vars, vcon_vars, vcon_ref, ny_full, dae, Ynet, u, ec, full_kcl);
    J_fn = @(z) trapezoidal_jacobian_fd(z, residual_fn, fd_eps, ...
        nx_active, ny_free);

    [z_sol, niter, step_ok, res_norm, rcond_val] = stability.composite_newton( ...
        z0, residual_fn, J_fn, newton_tol, max_iter, verbose);

    if ~step_ok
        if verbose
            fprintf('ts_simulate_composite: step %d did not converge (res=%.3e, iter=%d).\n', ...
                step, res_norm, niter);
        end
        converged = false;
        break;
    end

    % --- Extract solution -------------------------------------------------
    x1_active = z_sol(1:nx_active);
    y1_free = z_sol(nx_active+1:nx_active+ny_free);

    x1_full = zeros(nx_total, 1);
    x1_full(active_x_indices) = x1_active;
    for fi = 1:numel(frozen_x_indices)
        x1_full(frozen_x_indices(fi)) = frozen_x_values(fi);
    end

    y1_full = zeros(ny_full, 1);
    y1_full(vcon_vars) = vcon_ref;
    y1_full(free_vars) = y1_free;

    x_traj(:, step+1) = x1_full;
    y_traj(:, step+1) = y1_full;
    x_curr = x1_full;
    y_curr = y1_full;
end

ts_result = struct();
ts_result.x_traj = x_traj;
ts_result.y_traj = y_traj;
ts_result.t = t_vals;
ts_result.converged = converged;
ts_result.n_steps = step;   % last completed step

ts_meta = struct();
ts_meta.nx_total = nx_total; ts_meta.nx_active = nx_active;
ts_meta.ny_free = ny_free;
ts_meta.frozen_state_count = numel(frozen_x_indices);
ts_meta.dt = dt; ts_meta.t_end = t_end;
ts_meta.method = 'trapezoidal_coupled_newton';
if full_kcl
    ts_meta.full_kcl = true;
    ts_meta.input_source = 'opt.u_eq_constant';
    ts_meta.active_state_source = 'opt.dynamic_state_indices';
    ts_meta.dynamic_state_indices = active_x_indices;
    ts_meta.complement_anchor = 'supplied_x0';
end
end

% =========================================================================
function indices = expected_dynamic_indices(dae,ec)
%EXPECTED_DYNAMIC_INDICES  Authenticate the TS map against device metadata.
indices = [];
for k = 1:numel(dae.devices)
    dev = dae.devices(k);
    if isfield(dev,'dynamic_state_indices_for_context') && ...
            isa(dev.dynamic_state_indices_for_context,'function_handle')
        local = dev.dynamic_state_indices_for_context(ec);
    elseif isfield(dev,'active_state_indices_for_context') && ...
            isa(dev.active_state_indices_for_context,'function_handle')
        local = dev.active_state_indices_for_context(ec);
    else
        is_online = true;
        if isstruct(ec) && isfield(ec,'hybrid_state') && ...
                isstruct(ec.hybrid_state) && ...
                isfield(ec.hybrid_state,'device_online')
            key = matlab.lang.makeValidName(char(dev.device_id), ...
                'ReplacementStyle','underscore');
            if isfield(ec.hybrid_state.device_online,key)
                is_online = logical(ec.hybrid_state.device_online.(key));
            end
        end
        if ~is_online
            local = [];
        elseif isfield(dev,'active_state_indices')
            local = dev.active_state_indices;
        else
            local = 1:dev.nx;
        end
    end
    local = local(:)';
    if any(~isfinite(local)) || any(local~=fix(local)) || ...
            any(local<1) || any(local>dev.nx) || ...
            numel(unique(local))~=numel(local)
        error('ts_simulate_composite:badDeviceDynamicStates', ...
            'Device %s returned invalid dynamic-state indices.',dev.device_id);
    end
    if isfield(dev,'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
        local = setdiff(local,dev.frozen_state_indices(:)','stable');
    end
    indices = [indices,dae.device_offsets(k)+local]; %#ok<AGROW>
end
end

% =========================================================================
function r = trapezoidal_residual(z, x0_full, f0, h, ...
    active_idx, frozen_idx, frozen_val, ...
    free_vars, vcon_vars, vcon_ref, ny_full, dae, Y, u, ec, full_kcl)
% z = [x1_active; y1_free]
nx_active = numel(active_idx);
nx_total = numel(active_idx) + numel(frozen_idx);
x1_active = z(1:nx_active);
y1_free = z(nx_active+1:end);

% Reconstruct full x1
x1_full = zeros(nx_total, 1);
x1_full(active_idx) = x1_active;
for fi = 1:numel(frozen_idx)
    x1_full(frozen_idx(fi)) = frozen_val(fi);
end

% Reconstruct full y1
y1_full = zeros(ny_full, 1);
y1_full(vcon_vars) = vcon_ref;
y1_full(free_vars) = y1_free;

f1 = dae.dae_f(0, x1_full, y1_full, u, ec);
g1 = dae.dae_g(0, x1_full, y1_full, Y, u, ec);

% Trapezoidal residual: R_x = x1 - x0 - h/2*(f0 + f1)
R_x_full = x1_full - x0_full - 0.5*h*(f0 + f1);
R_x = R_x_full(active_idx);   % only active states

if full_kcl
    R_g = g1;
else
    % Legacy algebraic residual: g_free (exclude replaced vcon rows).
    free_rows = setdiff(1:numel(g1), dae.vcon.rows, 'stable');
    R_g = g1(free_rows);
end

r = [R_x(:); R_g(:)];
end

% =========================================================================
function J = trapezoidal_jacobian_fd(z, residual_fn, fd_eps, nx_active, ny_free)
nz = numel(z);
r0 = residual_fn(z);
nr = nx_active + ny_free;
J = zeros(nr, nz);
for j = 1:nz
    zp = z; zp(j) = zp(j) + fd_eps;
    rp = residual_fn(zp);
    J(:,j) = (rp - r0) / fd_eps;
end
end
