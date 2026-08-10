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

% Keep the complete active-state spectrum above for reporting.  A selector
% may additionally request a fixed-active-set physical decision spectrum.
% This is a coordinate/constraint reduction BEFORE eig: no root is deleted
% from sssa.eigenvalues, which remains the FULL STATE table contract.
sssa = attach_physical_decision_spectrum(sssa,dae,x0,y0,u_eq, ...
    event_context,opt,active,fd_eps);
end

% =========================================================================
function sssa = attach_physical_decision_spectrum(sssa,dae,x0,y0,u_eq, ...
    event_context,opt,active,fd_eps)
%ATTACH_PHYSICAL_DECISION_SPECTRUM Fixed-active-set and gauge quotient.
%   Active saturation equalities are differentiated on the exact KCL
%   manifold and eliminated before eig.  Full-KCL equations retain one rigid
%   network-angle coordinate whether the reference owner is an SG or a GFM.
%   That coordinate is quotiented before eig while every relative SG/VSG/PLL
%   angle remains in the physical decision spectrum.

sssa.physical_A = sssa.A;
sssa.physical_eigenvalues = sssa.eigenvalues;
sssa.physical_state_dimension = size(sssa.A,1);
sssa.physical_state_global_indices = active(:).';
sssa.active_bound_constraint_global_indices = zeros(1,0);
sssa.active_bound_constraint_names = cell(1,0);
sssa.active_bound_constraint_count = 0;
sssa.coordinate_gauge_global_index = [];
sssa.coordinate_gauge_state_name = '';
sssa.coordinate_mode_count = 0;
sssa.physical_reduction_method = 'none_full_state_decision';
sssa.physical_omega = max(real(sssa.physical_eigenvalues));
sssa.physical_stable = all(real(sssa.physical_eigenvalues) < 0);

locked = repmat(struct('dev_idx',0,'local_idx',0,'regime',''),0,1);
if isfield(opt,'active_bound_regimes') && ~isempty(opt.active_bound_regimes)
    locked = opt.active_bound_regimes;
end
if ~isstruct(locked)
    error('composite_sssa_model:badActiveBoundRegimes', ...
        'opt.active_bound_regimes must be the final locked regime struct array.');
end

all_specs = stability.active_bound_collect(dae,x0,y0,u_eq,event_context);
[locked_active,constrained_global,constraint_names] = ...
    active_constraint_entries(locked,all_specs,dae);

A_work = sssa.A;
coordinate_global = active(:).';
method_parts = {};
if ~isempty(locked_active)
    [C,h0] = active_constraint_jacobian(locked_active,all_specs,dae, ...
        x0,y0,u_eq,event_context,active,sssa.gx,sssa.gy,fd_eps);
    if any(~isfinite(C(:))) || any(~isfinite(h0(:)))
        error('composite_sssa_model:nonfiniteActiveConstraintJacobian', ...
            'Active-bound equality Jacobian contains NaN/Inf.');
    end
    bound_pos = zeros(1,numel(constrained_global));
    for k = 1:numel(constrained_global)
        bound_pos(k) = find(active == constrained_global(k),1,'first');
    end
    if any(bound_pos == 0) || numel(unique(bound_pos)) ~= numel(bound_pos)
        error('composite_sssa_model:activeConstraintStateMismatch', ...
            'Every active-bound equality must own one unique active state.');
    end
    free_pos = setdiff(1:numel(active),bound_pos,'stable');
    Cb = C(:,bound_pos);
    Cf = C(:,free_pos);
    cb_rcond = rcond(Cb);
    if ~isfinite(cb_rcond) || cb_rcond <= 1e-10
        error('composite_sssa_model:illConditionedActiveConstraints', ...
            'Active-bound pivot Jacobian rcond %.3e must exceed 1e-10.',cb_rcond);
    end
    Tbound = zeros(numel(active),numel(free_pos));
    Tbound(free_pos,:) = eye(numel(free_pos));
    Tbound(bound_pos,:) = -(Cb\Cf);
    Lbound = zeros(numel(free_pos),numel(active));
    for k = 1:numel(free_pos), Lbound(k,free_pos(k)) = 1; end
    A_work = Lbound*A_work*Tbound;
    coordinate_global = active(free_pos);
    sssa.active_bound_constraint_global_indices = constrained_global;
    sssa.active_bound_constraint_names = constraint_names;
    sssa.active_bound_constraint_count = numel(constrained_global);
    sssa.active_bound_constraint_jacobian = C;
    sssa.active_bound_constraint_residual = h0;
    sssa.active_bound_pivot_rcond = cb_rcond;
    sssa.active_bound_tangent_map = Tbound;
    method_parts{end+1} = 'fixed_active_bound_tangent_elimination'; %#ok<AGROW>
end

[A_work,coordinate_global,gauge_meta] = quotient_common_network_angle( ...
    A_work,coordinate_global,dae,event_context,opt);
if gauge_meta.applied
    sssa.coordinate_gauge_global_index = gauge_meta.global_index;
    sssa.coordinate_gauge_state_name = gauge_meta.state_name;
    sssa.coordinate_mode_count = 1;
    sssa.coordinate_quotient_left_map = gauge_meta.L;
    sssa.coordinate_quotient_right_map = gauge_meta.T;
    method_parts{end+1} = gauge_meta.method; %#ok<AGROW>
end

sssa.physical_A = A_work;
sssa.physical_eigenvalues = eig(A_work);
sssa.physical_state_dimension = size(A_work,1);
sssa.physical_state_global_indices = coordinate_global;
sssa.physical_omega = max(real(sssa.physical_eigenvalues));
sssa.physical_stable = all(real(sssa.physical_eigenvalues) < 0);
if isempty(method_parts)
    sssa.physical_reduction_method = 'none_full_state_decision';
else
    sssa.physical_reduction_method = strjoin(method_parts,'+');
end
end

% =========================================================================
function [entries,global_idx,names] = active_constraint_entries(locked,all_specs,dae)
entries = repmat(struct('dev_idx',0,'local_idx',0,'regime',''),0,1);
global_idx = zeros(1,0);
names = cell(1,0);
for k = 1:numel(locked)
    if ~all(isfield(locked(k),{'dev_idx','local_idx','regime'}))
        error('composite_sssa_model:badActiveBoundRegimes', ...
            'Each locked regime needs dev_idx, local_idx and regime.');
    end
    regime = lower(char(locked(k).regime));
    if strcmp(regime,'interior'), continue; end
    if ~ismember(regime,{'upper','lower'})
        error('composite_sssa_model:badActiveBoundRegimes', ...
            'Unsupported active-bound regime "%s".',regime);
    end
    dk = locked(k).dev_idx;
    li = locked(k).local_idx;
    if dk < 1 || dk > numel(all_specs) || isempty(all_specs{dk})
        error('composite_sssa_model:badActiveBoundRegimes', ...
            'Locked constraint dev=%d has no collected specification.',dk);
    end
    specs = all_specs{dk}.specs;
    pos = find([specs.local_idx] == li,1,'first');
    if isempty(pos)
        error('composite_sssa_model:badActiveBoundRegimes', ...
            'Locked constraint dev=%d local=%d has no specification.',dk,li);
    end
    e = struct('dev_idx',dk,'local_idx',li,'regime',regime);
    entries(end+1,1) = e; %#ok<AGROW>
    global_idx(end+1) = dae.device_offsets(dk)+li; %#ok<AGROW>
    if isfield(specs(pos),'description') && ~isempty(specs(pos).description)
        names{end+1} = char(specs(pos).description); %#ok<AGROW>
    else
        names{end+1} = sprintf('%s/state_%d',dae.devices(dk).device_id,li); %#ok<AGROW>
    end
end
if numel(unique(global_idx)) ~= numel(global_idx)
    error('composite_sssa_model:duplicateActiveConstraints', ...
        'Active-bound regimes contain duplicate constrained states.');
end
end

% =========================================================================
function [C,h0] = active_constraint_jacobian(entries,all_specs,dae, ...
    x0,y0,u_eq,event_context,active,gx,gy,h)
h0 = evaluate_active_constraints(entries,all_specs,dae,x0,y0,u_eq,event_context);
hx = zeros(numel(entries),numel(active));
for j = 1:numel(active)
    xp = x0; xp(active(j)) = xp(active(j))+h;
    hp = evaluate_active_constraints(entries,all_specs,dae,xp,y0,u_eq,event_context);
    hx(:,j) = (hp-h0)/h;
end
hy = zeros(numel(entries),numel(y0));
for j = 1:numel(y0)
    yp = y0; yp(j) = yp(j)+h;
    hp = evaluate_active_constraints(entries,all_specs,dae,x0,yp,u_eq,event_context);
    hy(:,j) = (hp-h0)/h;
end
% KCL tangent: dy/dx = -gy\gx.
C = hx-hy*(gy\gx(:,active));
end

% =========================================================================
function value = evaluate_active_constraints(entries,all_specs,dae,x,y,u,event_context)
value = zeros(numel(entries),1);
for k = 1:numel(entries)
    e = entries(k);
    meta = all_specs{e.dev_idx};
    specs = meta.specs;
    sp = find([specs.local_idx] == e.local_idx,1,'first');
    xdev = x(meta.offset+1:meta.offset+meta.dev_nx);
    udev = zeros(0,1);
    if meta.dev_nu > 0
        udev = u(meta.u_offset+1:meta.u_offset+meta.dev_nu);
    end
    value(k) = specs(sp).residual_fn(xdev,y,udev,event_context,e.regime);
end
end

% =========================================================================
function [Aq,global_out,meta] = quotient_common_network_angle(A,global_in,dae,event_context,opt)
meta = struct('applied',false,'global_index',[],'state_name','', ...
    'method','','L',[],'T',[]);
Aq = A;
global_out = global_in;

angle_global = zeros(1,0);
angle_dev = zeros(1,0);
for dk = 1:numel(dae.devices)
    dev = dae.devices(dk);
    if ~device_online(dev,event_context)
        continue;
    end
    % The rigid-rotation vector contains exactly one active electrical-angle
    % coordinate for each online angle-bearing device.  Resolve that state
    % from the active runtime mode, rather than accepting every name that
    % happens to contain "delta" (e.g. speed/controller-error states).
    local = network_angle_local_index(dev,device_mode(dev,event_context));
    if isempty(local), continue; end
    gi = dae.device_offsets(dk)+local;
    if ismember(gi,global_in)
        angle_global(end+1) = gi; %#ok<AGROW>
        angle_dev(end+1) = dk; %#ok<AGROW>
    end
end
if isempty(angle_global), return; end

ref_dev = [];
if isfield(opt,'reference_device_index') && ~isempty(opt.reference_device_index)
    ref_dev = opt.reference_device_index;
elseif isfield(event_context,'hybrid_state') && ...
        isfield(event_context.hybrid_state,'reference_resource_index')
    ref_dev = event_context.hybrid_state.reference_resource_index;
end
if isempty(ref_dev)
    sg_candidates = online_sg_indices(dae,event_context);
    if numel(sg_candidates) == 1
        % Backward-compatible SG_ON full-KCL callers may predate the explicit
        % owner field. A unique online synchronous machine is an unambiguous
        % physical owner; zero or multiple candidates remain fail-closed.
        ref_dev = sg_candidates(1);
    end
end
ref_pick = find(angle_dev == ref_dev,1,'first');
if isempty(ref_pick)
    error('composite_sssa_model:referenceAngleMissing', ...
        ['The declared reference device %s has no active network-angle ' ...
         'coordinate in the full-KCL state partition.'],mat2str(ref_dev));
end
ref_global = angle_global(ref_pick);
ref_pos = find(global_in == ref_global,1,'first');
angle_pos = arrayfun(@(g)find(global_in==g,1,'first'),angle_global);

n = numel(global_in);
retain = setdiff(1:n,ref_pos,'stable');
T = eye(n); T = T(:,retain);
L = zeros(numel(retain),n);
for r = 1:numel(retain)
    q = retain(r);
    L(r,q) = 1;
    if ismember(q,angle_pos)
        L(r,ref_pos) = -1;
    end
end
Aq = L*A*T;
global_out = global_in(retain);
meta.applied = true;
meta.global_index = ref_global;
meta.state_name = sprintf('%s/%s',dae.devices(angle_dev(ref_pick)).device_id, ...
    dae.devices(angle_dev(ref_pick)).state_names{ref_global-dae.device_offsets(angle_dev(ref_pick))});
if contains(lower(meta.state_name),'pll') && ~online_sg_present(dae,event_context)
    meta.method='common_gfm_pll_angle_quotient';
elseif online_sg_present(dae,event_context)
    meta.method='common_sg_ibr_network_angle_quotient';
else
    meta.method='common_gfm_vsg_angle_quotient';
end
meta.L = L;
meta.T = T;
end

function local = network_angle_local_index(dev,mode)
local = [];
names = cellstr(string(dev.state_names));
dtype = '';
if isfield(dev,'device_type') && ~isempty(dev.device_type)
    dtype = lower(char(dev.device_type));
end
is_sg = contains(dtype,'sg') || strcmp(dtype,'synchronous_generator');
if isfield(dev,'capabilities') && isfield(dev.capabilities,'resource_type')
    is_sg = is_sg || strcmpi(char(dev.capabilities.resource_type),'sg');
end
if is_sg
    candidates = {'delta'};
elseif strcmpi(mode,'gfm')
    candidates = {'gfm_delta_VSG','gfm_delta_PLL','delta_VSG', ...
        'delta_vsm','delta_PLL','delta'};
elseif strcmpi(mode,'gfl')
    candidates = {'gfl_delta_PLL','delta_PLL'};
else
    candidates = {};
end
for k = 1:numel(candidates)
    pos = find(strcmpi(names,candidates{k}),1,'first');
    if ~isempty(pos)
        local = pos;
        return;
    end
end
end

% =========================================================================
function tf = online_sg_present(dae,event_context)
tf = ~isempty(online_sg_indices(dae,event_context));
end

function indices = online_sg_indices(dae,event_context)
indices = [];
for k = 1:numel(dae.devices)
    d = dae.devices(k);
    dtype = '';
    if isfield(d,'device_type'), dtype = lower(char(d.device_type)); end
    is_sg = contains(dtype,'sg') || strcmp(dtype,'synchronous_generator');
    if isfield(d,'capabilities') && isfield(d.capabilities,'resource_type')
        is_sg = is_sg || strcmpi(char(d.capabilities.resource_type),'sg');
    end
    if is_sg && device_online(d,event_context)
        indices(end+1) = k; %#ok<AGROW>
    end
end
end

function tf = device_online(dev,event_context)
tf = true;
if isfield(dev,'initial_online') && ~isempty(dev.initial_online)
    tf = logical(dev.initial_online);
end
key = matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
if isfield(event_context,'hybrid_state') && ...
        isfield(event_context.hybrid_state,'device_online') && ...
        isfield(event_context.hybrid_state.device_online,key)
    tf = logical(event_context.hybrid_state.device_online.(key));
end
end

function mode = device_mode(dev,event_context)
mode = '';
if isfield(dev,'mode') && ~isempty(dev.mode), mode = char(dev.mode); end
key = matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
if isfield(event_context,'hybrid_state') && ...
        isfield(event_context.hybrid_state,'device_modes') && ...
        isfield(event_context.hybrid_state.device_modes,key)
    mode = char(event_context.hybrid_state.device_modes.(key));
end
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
