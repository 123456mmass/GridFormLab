function sssa = composite_sssa_model(devices, x0, y0, case_data, opt)
%COMPOSITE_SSSA_MODEL  Small-signal stability model for mixed SG+IBR system.
%   SSSA = composite_sssa_model(DEVICES, X0, Y0, CASE_DATA, OPT) builds a
%   2-arg binding for multimachine_ssa from an operating point + device list.
%
%   Correction 8 (active-state reduction before eig): frozen states (e.g. Edp
%   for Tpq0=0 round-rotor SG) are EXCLUDED through Galerkin projection BEFORE
%   eig, NOT deleted from the spectrum afterward. The active-state indices are
%   derived from per-device frozen_state_indices metadata — NEVER hard-coded.
%
%   The model returns:
%     sssa.A  = reduced active-state state matrix (nx_active x nx_active)
%     sssa.x0 = equilibrium operating point
%     sssa.eigenvalues = eig(A)
%     sssa.active_state_indices (from device metadata)
%     sssa.frozen_state_indices
%
%   STATUS: STRUCTURAL_ONLY (Phase D). No production-readiness claim.
%
%   Full-KCL opt-in contract:
%     opt.full_kcl=true requires opt.u_eq, opt.event_context and
%     opt.active_state_indices. It differentiates pure physical KCL (no vcon),
%     forms fx/fy/gx/gy with the existing fd_eps, applies the in-house Schur
%     complement, and projects to the supplied active set before eig.
%   Source: execution plan §D; correction 8.

arguments
    devices struct
    x0 (:,1) double
    y0 (:,1) double
    case_data struct
    opt struct = struct()
end

fd_eps = 3e-6;
if isfield(opt, 'fd_eps') && ~isempty(opt.fd_eps), fd_eps = opt.fd_eps; end

% Opt-in exact full-KCL path. Legacy/default callers continue through the
% original vcon + dfdx-only implementation below without behavior changes.
full_kcl = false;
if isfield(opt,'full_kcl') && ~isempty(opt.full_kcl)
    if ~isscalar(opt.full_kcl) || ...
            ~(islogical(opt.full_kcl) || isnumeric(opt.full_kcl)) || ...
            ~isfinite(double(opt.full_kcl)) || ...
            ~ismember(double(opt.full_kcl),[0 1])
        error('composite_sssa_model:badFullKcl', ...
            'opt.full_kcl must be a finite scalar logical or numeric 0/1.');
    end
    full_kcl = logical(opt.full_kcl);
end
if full_kcl
    sssa = full_kcl_sssa(devices,x0,y0,case_data,opt,fd_eps);
    return;
end

% --- Build composite DAE for Jacobian evaluation --------------------------
vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
dae_opt = struct('load_model','cz_p_cz_q','vcon',vcon);
dae = stability.composite_dae(case_data, devices, dae_opt);

% --- Detect frozen states from device metadata ----------------------------
frozen_x_indices = [];
active_x_indices = 1:numel(x0);
for dk = 1:numel(dae.devices)
    dev = dae.devices(dk);
    if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
        off = dae.device_offsets(dk);
        fsi = dev.frozen_state_indices(:)';
        frozen_x_indices = [frozen_x_indices, off + fsi]; %#ok<AGROW>
    end
end
active_x_indices = setdiff(active_x_indices, frozen_x_indices, 'stable');
nx_active = numel(active_x_indices);

% --- Evaluate df/dx at operating point via central FD ---------------------
nx = numel(x0);
u = dae.u0;
ec = struct();

% Evaluate RHS at op point
f0 = dae.dae_f(0, x0, y0, u, ec);
dfdx = zeros(nx, nx);
x_op = x0;
for j = 1:nx
    xp = x_op; xp(j) = xp(j) + fd_eps;
    fp = dae.dae_f(0, xp, y0, u, ec);
    dfdx(:, j) = (fp - f0) / fd_eps;
end

% --- Active-state reduction (Galerkin) before eig -------------------------
% A = df/dx restricted to active state indices
A_full = dfdx;
A = A_full(active_x_indices, active_x_indices);

% --- Compute eigenvalues --------------------------------------------------
eig_vals = eig(A);

% --- Assemble output ------------------------------------------------------
sssa = struct();
sssa.A = A;
sssa.A_full = A_full;
sssa.x0 = x0;
sssa.y0 = y0;
sssa.eigenvalues = eig_vals;
sssa.active_state_indices = active_x_indices;
sssa.frozen_state_indices = frozen_x_indices;
sssa.nx_total = nx;
sssa.nx_active = nx_active;
sssa.omega = sort(real(eig_vals));    % damping constants (negative = stable)
sssa.frequencies = sort(abs(imag(eig_vals)));
sssa.stable = all(real(eig_vals) < 0);
sssa.reduction_method = 'active_state_galerkin_before_eig';
sssa.no_eig_delete = true;
end

% =========================================================================
function sssa = full_kcl_sssa(devices,x0,y0,case_data,opt,fd_eps)
%FULL_KCL_SSSA  Exact-equilibrium, pure-KCL Schur linearization.
%   Required opt fields are u_eq, event_context and active_state_indices.
%   The same production f/g closures are differentiated at fixed u/context.
required = {'u_eq','event_context','active_state_indices'};
for k = 1:numel(required)
    if ~isfield(opt,required{k})
        error('composite_sssa_model:missingFullKclOption', ...
            'opt.%s is required when opt.full_kcl=true.',required{k});
    end
end

% Pure KCL: deliberately omit vcon so no physical algebraic row is replaced.
dae_opt = struct('load_model','cz_p_cz_q');
dae = stability.composite_dae(case_data,devices,dae_opt);
nx = numel(dae.x0);
ny = 2*dae.nb;
if numel(x0) ~= nx || numel(y0) ~= ny
    error('composite_sssa_model:operatingPointDimension', ...
        'x0/y0 dimensions (%d/%d) must match the composite DAE (%d/%d).', ...
        numel(x0),numel(y0),nx,ny);
end
if ~isempty(dae.vcon.rows)
    error('composite_sssa_model:fullKclVcon', ...
        'The full-KCL SSSA path must not replace any physical KCL row.');
end

u_eq = opt.u_eq(:);
if ~isnumeric(opt.u_eq) || ~isreal(opt.u_eq) || ...
        numel(u_eq) ~= numel(dae.u0) || any(~isfinite(u_eq))
    error('composite_sssa_model:badEquilibriumInput', ...
        'opt.u_eq must be a finite real vector with %d elements.',numel(dae.u0));
end
event_context = opt.event_context;
if ~isstruct(event_context) || ~isscalar(event_context)
    error('composite_sssa_model:badEventContext', ...
        'opt.event_context must be the scalar equilibrium context struct.');
end
active = validate_active_indices(opt.active_state_indices,nx);
expected_active = expected_equilibrium_active_indices(dae,event_context);
if ~isequal(active(:)',expected_active(:)')
    error('composite_sssa_model:activeStateMismatch', ...
        ['opt.active_state_indices must exactly match the device/runtime ' ...
         'equilibrium partition for opt.event_context.']);
end

% Exact production closures, fixed at the solved u/context/topology.
Y = dae.Ynet;
f0 = dae.dae_f(0,x0,y0,u_eq,event_context);
g0 = dae.dae_g(0,x0,y0,Y,u_eq,event_context);
if numel(f0) ~= nx || numel(g0) ~= ny || ...
        any(~isfinite(f0)) || any(~isfinite(g0))
    error('composite_sssa_model:nonfiniteOperatingResidual', ...
        'Exact equilibrium closures returned invalid/non-finite f or KCL g.');
end

% Existing NUMERICAL_METHOD: one-sided forward FD with fd_eps=3e-6 default.
% No tolerance, smoothing or perturbation-size change is introduced here.
fx = zeros(nx,nx);
gx = zeros(ny,nx);
for j = 1:nx
    xp = x0;
    xp(j) = xp(j) + fd_eps;
    fp = dae.dae_f(0,xp,y0,u_eq,event_context);
    gp = dae.dae_g(0,xp,y0,Y,u_eq,event_context);
    fx(:,j) = (fp-f0)/fd_eps;
    gx(:,j) = (gp-g0)/fd_eps;
end
fy = zeros(nx,ny);
gy = zeros(ny,ny);
for j = 1:ny
    yp = y0;
    yp(j) = yp(j) + fd_eps;
    fp = dae.dae_f(0,x0,yp,u_eq,event_context);
    gp = dae.dae_g(0,x0,yp,Y,u_eq,event_context);
    fy(:,j) = (fp-f0)/fd_eps;
    gy(:,j) = (gp-g0)/fd_eps;
end
if any(~isfinite(fx(:))) || any(~isfinite(fy(:))) || ...
        any(~isfinite(gx(:))) || any(~isfinite(gy(:)))
    error('composite_sssa_model:nonfiniteJacobian', ...
        'Full-KCL finite-difference Jacobian contains NaN/Inf.');
end
if size(gy,1) ~= size(gy,2)
    error('composite_sssa_model:nonSquareGy', ...
        'Full-KCL gy must be square; received %d-by-%d.',size(gy,1),size(gy,2));
end
gy_rcond = rcond(gy);
gy_rcond_min = 1e-10;
if ~isfinite(gy_rcond) || gy_rcond <= gy_rcond_min
    error('composite_sssa_model:illConditionedGy', ...
        'Full-KCL gy rcond %.3e must exceed %.3e.',gy_rcond,gy_rcond_min);
end

% In-house Schur elimination, then active-state projection before eig.
A_full = fx - fy*(gy\gx);
A = A_full(active,active);
eig_vals = eig(A);

sssa = struct();
sssa.A = A;
sssa.A_full = A_full;
sssa.fx = fx;
sssa.fy = fy;
sssa.gx = gx;
sssa.gy = gy;
sssa.f0 = f0;
sssa.g0 = g0;
sssa.x0 = x0;
sssa.y0 = y0;
sssa.u_eq = u_eq;
sssa.event_context = event_context;
sssa.eigenvalues = eig_vals;
sssa.active_state_indices = active;
sssa.frozen_state_indices = setdiff(1:nx,active,'stable');
sssa.nx_total = nx;
sssa.nx_active = numel(active);
sssa.omega = sort(real(eig_vals));
sssa.frequencies = sort(abs(imag(eig_vals)));
sssa.stable = all(real(eig_vals) < 0);
sssa.reduction_method = 'full_kcl_schur_active_state_galerkin_before_eig';
sssa.linearization_method = 'forward_fd_exact_composite_f_g';
sssa.no_eig_delete = true;
sssa.full_kcl = true;
sssa.kcl_rows_replaced = dae.vcon.rows;
sssa.gy_rcond = gy_rcond;
sssa.gy_rcond_min = gy_rcond_min;
sssa.fd_eps = fd_eps;
sssa.active_f_residual_norm = norm(f0(active),inf);
sssa.physical_kcl_residual_norm = norm(g0,inf);
end

% =========================================================================
function indices = expected_equilibrium_active_indices(dae,event_context)
%EXPECTED_EQUILIBRIUM_ACTIVE_INDICES  Authenticate SSSA projection metadata.
indices = [];
for k = 1:numel(dae.devices)
    dev = dae.devices(k);
    is_online = true;
    key = matlab.lang.makeValidName(char(dev.device_id), ...
        'ReplacementStyle','underscore');
    if isfield(dev,'initial_online') && ~isempty(dev.initial_online)
        is_online = logical(dev.initial_online);
    end
    if isfield(event_context,'hybrid_state') && ...
            isstruct(event_context.hybrid_state) && ...
            isfield(event_context.hybrid_state,'device_online') && ...
            isfield(event_context.hybrid_state.device_online,key)
        is_online = logical(event_context.hybrid_state.device_online.(key));
    end
    if ~is_online
        local = [];
    elseif isfield(dev,'active_state_indices_for_context') && ...
            isa(dev.active_state_indices_for_context,'function_handle')
        local = dev.active_state_indices_for_context(event_context);
    elseif isfield(dev,'active_state_indices')
        local = dev.active_state_indices;
    else
        local = 1:dev.nx;
    end
    local = validate_active_indices(local,dev.nx);
    if isfield(dev,'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
        local = setdiff(local,dev.frozen_state_indices(:)','stable');
    end
    indices = [indices,dae.device_offsets(k)+local]; %#ok<AGROW>
end
end

% =========================================================================
function idx = validate_active_indices(raw,nx)
%VALIDATE_ACTIVE_INDICES  Fail-closed global state partition validation.
if isempty(raw)
    idx = zeros(1,0);
    return;
end
if ~isnumeric(raw) || ~isreal(raw) || any(~isfinite(raw(:)))
    error('composite_sssa_model:badActiveStateIndices', ...
        'opt.active_state_indices must contain finite real numeric indices.');
end
idx = raw(:)';
if any(idx ~= fix(idx)) || any(idx < 1) || any(idx > nx) || ...
        numel(unique(idx)) ~= numel(idx)
    error('composite_sssa_model:badActiveStateIndices', ...
        'opt.active_state_indices must be unique integers in 1:%d.',nx);
end
end
