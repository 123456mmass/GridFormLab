function init = mixed_ibr_reduced_initialize(dae, eq_context, reference_device_index, opt)
%MIXED_IBR_REDUCED_INITIALIZE  Physical SG-off IBR equilibrium warm start.
%   INIT = mixed_ibr_reduced_initialize(DAE, EQ_CONTEXT, REF_INDEX, OPT)
%   solves a project-owned reduced network problem for an island containing
%   online GFL/GFM IBRs and no online synchronous machine.  It is an
%   initializer only: mixed_equilibrium_solve subsequently verifies the full
%   device-state residual and physical KCL with the production closures.
%
%   Unknowns (single energized island):
%     y except Im(V_ref_bus), plus P_ref for exactly one selected reference
%     GFM.  Legacy voltage-reference devices additionally solve one terminal
%     Q per GFM. Im(V_ref_bus)=0 is coordinate elimination; no physical KCL
%     row is removed and no second device becomes REF.
%
%   Residuals:
%     every rectangular network KCL row. Legacy voltage-reference devices
%     also contribute |V_bus|-V_ref regulation per GFM. P/Q-reference devices
%     retain every case/event Q_ref unchanged. The selected reference GFM P
%     alone balances load and losses; this does not make another GFM an
%     angle/slack reference.
%
%   Classification:
%     device equations/base/signs: SOURCE_TRANSFORMED by their factories;
%     reduced PV/PQ initialization and one balancing P input: PROJECT_DERIVED;
%     damped Newton/FD: NUMERICAL_METHOD.  No external solver is used.

arguments
    dae struct
    eq_context struct
    reference_device_index (1,1) double
    opt struct = struct()
end

tol = 1e-8;
max_iter = 300;
fd_eps = 3e-6;
verbose = false;
if isfield(opt,'tolerance') && ~isempty(opt.tolerance), tol = opt.tolerance; end
if isfield(opt,'max_iter') && ~isempty(opt.max_iter), max_iter = opt.max_iter; end
if isfield(opt,'fd_eps') && ~isempty(opt.fd_eps), fd_eps = opt.fd_eps; end
if isfield(opt,'verbose') && ~isempty(opt.verbose), verbose = opt.verbose; end

init = struct( ...
    'applicable', false, 'converged', false, 'failure_id', '', ...
    'failure_reason', '', 'x0', dae.x0, 'y0', dae.y0, 'u_eq', dae.u0, ...
    'devices', dae.devices, 'iterations', 0, 'residual_norm', inf, ...
    'rcond', NaN, 'reference_device_index', reference_device_index, ...
    'reference_device_id', '', 'reference_bus_position', NaN, ...
    'reference_p_scheduled_pu', NaN, 'reference_p_solved_pu', NaN, ...
    'gfm_device_indices', [], 'gfm_q_solved_pu', [], ...
    'physical_kcl_norm', inf);

nd = numel(dae.devices);
if reference_device_index < 1 || reference_device_index > nd || ...
        ~isfinite(reference_device_index) || reference_device_index ~= fix(reference_device_index)
    init.failure_id = 'mixed_ibr_reduced_initialize:badReferenceIndex';
    init.failure_reason = 'reference_device_index must be a valid integer device index.';
    return;
end

online = false(nd,1);
modes = strings(nd,1);
for k = 1:nd
    [online(k), modes(k)] = runtime_status(dae.devices(k), eq_context);
end

online_idx = find(online);
if isempty(online_idx)
    init.failure_id = 'mixed_ibr_reduced_initialize:noOnlineDevices';
    init.failure_reason = 'The reduced initializer requires online IBR devices.';
    return;
end
% The registered REGFM dual layouts implement the voltage-reference ABI.
% The RMS10 family differs only in its GFL branch/state count; rejecting its
% device_type here made the otherwise generic SG-off initializer silently
% legacy-only.  Keep the allowlist explicit so an unknown future device still
% fails closed rather than entering this initializer by name similarity.
online_types = lower(string({dae.devices(online_idx).device_type}));
voltage_ref_types = ["ibr_dual_mode","ibr_dual_mode_rms10"];
pq_ref_types = ["ibr_eecon49_dual","ibr_decoupled_dual"];
uses_voltage_ref = all(ismember(online_types,voltage_ref_types));
uses_pq_ref = all(ismember(online_types,pq_ref_types));
if ~(uses_voltage_ref || uses_pq_ref)
    % This helper is deliberately not a fallback for an online SG or an
    % unknown future device. The caller retains its ordinary warm start.
    init.failure_id = 'mixed_ibr_reduced_initialize:notPureIBRIsland';
    init.failure_reason = ['Reduced initializer requires one homogeneous supported ' ...
        'dual-mode equilibrium contract (voltage-reference or P/Q-reference).'];
    return;
end
if any(~ismember(lower(modes(online_idx)), ["gfl","gfm"]))
    init.failure_id = 'mixed_ibr_reduced_initialize:unsupportedMode';
    init.failure_reason = 'Every online IBR must be in GFL or GFM mode.';
    return;
end

gfm_idx = online_idx(strcmpi(modes(online_idx),"gfm"));
if isempty(gfm_idx)
    init.failure_id = 'mixed_ibr_reduced_initialize:noVoltageFormingSource';
    init.failure_reason = 'At least one online GFM is required.';
    return;
end
if ~online(reference_device_index) || ~strcmpi(modes(reference_device_index),"gfm")
    init.failure_id = 'mixed_ibr_reduced_initialize:referenceNotGFM';
    init.failure_reason = 'The selected balancing reference must be an online GFM.';
    return;
end

for k = online_idx(:)'
    if ~isfield(dae.devices(k),'equilibrium_initialize') || ...
            isempty(dae.devices(k).equilibrium_initialize) || ...
            ~isa(dae.devices(k).equilibrium_initialize,'function_handle')
        init.failure_id = 'mixed_ibr_reduced_initialize:missingDeviceInitializer';
        init.failure_reason = sprintf( ...
            'Online device %s has no exact equilibrium initializer.', ...
            dae.devices(k).device_id);
        return;
    end
end

ref_dev = dae.devices(reference_device_index);
gauge_var = 2*ref_dev.bus_position;
ny = numel(dae.y0);
free_y = setdiff(1:ny, gauge_var, 'stable');

% Resolve input positions by name rather than assuming the dual-mode ABI slots.
p_slot = zeros(nd,1);
q_slot = zeros(nd,1);
v_slot = zeros(nd,1);
P_sched = zeros(nd,1);
Q_sched = zeros(nd,1);
V_ref = NaN(nd,1);
for k = online_idx(:)'
    names = string(dae.devices(k).input_names);
    p_slot(k) = find_input_slot(names,"P_ref",dae.devices(k).device_id);
    P_sched(k) = dae.devices(k).u0(p_slot(k));
    if strcmpi(modes(k),"gfl") || uses_pq_ref
        q_slot(k) = find_input_slot(names,"Q_ref",dae.devices(k).device_id);
        Q_sched(k) = dae.devices(k).u0(q_slot(k));
        if uses_pq_ref && strcmpi(modes(k),"gfm")
            v_slot(k)=find_input_slot(names,"E_ref",dae.devices(k).device_id);
            V_ref(k)=dae.devices(k).u0(v_slot(k));
        end
    else
        v_slot(k) = find_input_slot(names,"V_ref",dae.devices(k).device_id);
        V_ref(k) = dae.devices(k).u0(v_slot(k));
    end
end

% Start from the in-house PF phasors and remove only the selected island's
% common angle.  Discarding every PF angle creates an artificial high-voltage
% basin for the P/Q-reference solve and can drive its balancing GFM into the
% current limiter before the full-DAE acceptance test.
Vpf = dae.y0(1:2:end) + 1i*dae.y0(2:2:end);
if any(~isfinite(Vpf)) || any(abs(Vpf) <= 0)
    init.failure_id = 'mixed_ibr_reduced_initialize:badPFWarmStart';
    init.failure_reason = 'PF voltage warm start must be finite and nonzero.';
    return;
end
if uses_pq_ref
    Vseed=Vpf*exp(-1i*angle(Vpf(ref_dev.bus_position)));
    y_flat=zeros(ny,1);
    y_flat(1:2:end)=real(Vseed);
    y_flat(2:2:end)=imag(Vseed);
else
    y_flat=zeros(ny,1);
    y_flat(1:2:end)=abs(Vpf);
end
y_flat(gauge_var)=0;
p0 = P_sched(reference_device_index);
if uses_pq_ref
    % Q_ref and E_ref remain immutable case/event inputs. Terminal Q is an
    % equilibrium output constrained by the source GFM E-state equation.
    % One scalar active-power mismatch is shared by selected GFMs.
    p_participation=resolve_p_participation(opt,dae,online_idx,gfm_idx,reference_device_index);
    q0=Q_sched(gfm_idx);
    z0=[y_flat(free_y);q0;0.0];
    residual_fn=@(z) pq_reference_residual(z,dae,online_idx,gfm_idx, ...
        reference_device_index,free_y,gauge_var,P_sched,Q_sched, ...
        p_participation,eq_context);
else
    p_participation=zeros(nd,1);
    p_participation(reference_device_index)=1;
    q0=zeros(numel(gfm_idx),1);
    z0=[y_flat(free_y);q0;p0];
    residual_fn=@(z) reduced_residual(z,dae,online_idx,gfm_idx, ...
        reference_device_index,free_y,gauge_var,P_sched,Q_sched,V_ref);
end
J_fn = @(z) fd_jacobian(z, residual_fn, fd_eps);
[z, niter, ok, rnorm, rc] = stability.composite_newton( ...
    z0, residual_fn, J_fn, tol, max_iter, verbose);

init.applicable = true;
init.iterations = niter;
init.residual_norm = rnorm;
init.rcond = rc;
if ~ok
    init.failure_id = 'mixed_ibr_reduced_initialize:noConverge';
    init.failure_reason = sprintf( ...
        'Reduced all-KCL slack solve failed: residual=%.3e after %d iterations.', ...
        rnorm, niter);
    return;
end
if ~isfinite(rc) || rc < 1e-10
    init.failure_id = 'mixed_ibr_reduced_initialize:illConditioned';
    init.failure_reason = sprintf('Reduced initializer Jacobian rcond=%.3e.',rc);
    return;
end

if uses_pq_ref
    [~,y,q_gfm,p_ref,kcl,p_eq]=pq_reference_residual(z,dae,online_idx,gfm_idx, ...
        reference_device_index,free_y,gauge_var,P_sched,Q_sched, ...
        p_participation,eq_context);
else
    [~,y,q_gfm,p_ref,kcl]=reduced_residual(z,dae,online_idx,gfm_idx, ...
        reference_device_index,free_y,gauge_var,P_sched,Q_sched,V_ref);
end
if real(y(2*ref_dev.bus_position-1)) <= 0
    init.failure_id = 'mixed_ibr_reduced_initialize:negativeReferenceVoltage';
    init.failure_reason = 'The gauge branch requires Re(V_reference)>0.';
    return;
end
if norm(kcl,inf) >= 1e-6
    init.failure_id = 'mixed_ibr_reduced_initialize:physicalKCL';
    init.failure_reason = sprintf('Physical KCL residual %.3e exceeds 1e-6.',norm(kcl,inf));
    return;
end

V = y(1:2:end) + 1i*y(2:2:end);
x = dae.x0;
u_eq = dae.u0;
devices_eq = dae.devices;
if ~uses_pq_ref
    p_eq=P_sched;
    p_eq(reference_device_index)=p_ref;
end
q_by_device = NaN(nd,1);
for iq = 1:numel(gfm_idx), q_by_device(gfm_idx(iq)) = q_gfm(iq); end
for k = online_idx(:)'
    P = p_eq(k);
    Q = Q_sched(k);
    if strcmpi(modes(k),"gfm")
        Q = q_by_device(k);
    end
    if k == reference_device_index, P = p_ref; end
    try
        xk = dae.devices(k).equilibrium_initialize( ...
            V(dae.devices(k).bus_position), P, Q, eq_context);
    catch me
        init.failure_id = 'mixed_ibr_reduced_initialize:deviceInitializer';
        init.failure_reason = sprintf('Initializer for %s failed: %s', ...
            dae.devices(k).device_id,me.message);
        return;
    end
    if numel(xk) ~= dae.devices(k).nx || any(~isfinite(xk))
        init.failure_id = 'mixed_ibr_reduced_initialize:badDeviceState';
        init.failure_reason = sprintf('Initializer for %s returned an invalid state.', ...
            dae.devices(k).device_id);
        return;
    end
    xr = dae.device_offsets(k)+1 : dae.device_offsets(k)+dae.devices(k).nx;
    x(xr) = xk(:);
end

if uses_pq_ref
    for k=online_idx(:)'
        p_global=dae.u_offsets(k)+p_slot(k);
        u_eq(p_global)=p_eq(k);
        devices_eq(k).u0(p_slot(k))=p_eq(k);
    end
else
    ref_u_global = dae.u_offsets(reference_device_index) + p_slot(reference_device_index);
    u_eq(ref_u_global) = p_ref;
    devices_eq(reference_device_index).u0(p_slot(reference_device_index)) = p_ref;
end

init.converged = true;
init.x0 = x;
init.y0 = y;
init.u_eq = u_eq;
init.devices = devices_eq;
init.reference_device_id = ref_dev.device_id;
init.reference_bus_position = ref_dev.bus_position;
init.reference_p_scheduled_pu = p0;
init.reference_p_solved_pu = p_ref;
init.gfm_device_indices = gfm_idx(:)';
init.gfm_q_solved_pu = q_gfm(:)';
init.p_participation = p_participation(:)';
init.p_solved_pu = p_eq(:)';
init.physical_kcl_norm = norm(kcl,inf);
end

% =========================================================================
function [r,y,q_gfm,p_ref,kcl_rect,p_eq] = pq_reference_residual(z,dae,online_idx, ...
    gfm_idx,reference_device_index,free_y,gauge_var,P_sched,Q_sched, ...
    p_participation,eq_context)
ny=numel(dae.y0);
nq=numel(gfm_idx);
y=zeros(ny,1);
y(free_y)=z(1:numel(free_y));
y(gauge_var)=0;
q_gfm=z(numel(free_y)+(1:nq));
delta_p=z(end);
p_eq=P_sched+p_participation*delta_p;
p_ref=p_eq(reference_device_index);
V=y(1:2:end)+1i*y(2:2:end);
if any(~isfinite(V)) || any(abs(V)<=sqrt(eps)) || ...
        ~isfinite(delta_p) || any(~isfinite(p_eq)) || any(~isfinite(q_gfm))
    r=NaN(ny+nq,1); kcl_rect=NaN(ny,1); return;
end
Ibus=zeros(dae.nb,1);
q_by_device=NaN(numel(dae.devices),1);
for iq=1:nq, q_by_device(gfm_idx(iq))=q_gfm(iq); end
for k=online_idx(:)'
    P=p_eq(k);
    Q=Q_sched(k);
    if any(gfm_idx==k), Q=q_by_device(k); end
    b=dae.devices(k).bus_position;
    Ibus(b)=Ibus(b)+conj(complex(P,Q)/V(b));
end
kcl_complex=dae.Ynet*V-Ibus;
kcl_rect=zeros(ny,1);
kcl_rect(1:2:end)=real(kcl_complex);
kcl_rect(2:2:end)=imag(kcl_complex);
e_res=zeros(nq,1);
for iq=1:nq
    k=gfm_idx(iq);
    dev=dae.devices(k);
    b=dev.bus_position;
    xk=dev.equilibrium_initialize(V(b),p_eq(k),q_gfm(iq),eq_context);
    ur=dae.u_offsets(k)+(1:dev.nu);
    dx=dev.f(0,xk,y,dae.u0(ur),eq_context);
    e_local=find(strcmpi(string(dev.state_names),'gfm_E'),1);
    if isempty(e_local)
        error('mixed_ibr_reduced_initialize:missingEState', ...
            'P/Q-reference GFM %s does not declare gfm_E.',dev.device_id);
    end
    e_res(iq)=dx(e_local);
end
r=[kcl_rect;e_res];
end

% =========================================================================
function p=resolve_p_participation(opt,dae,online_idx,gfm_idx,reference_device_index)
p=zeros(numel(dae.devices),1);
participants=setdiff(online_idx,gfm_idx,'stable');
if isempty(participants), participants=gfm_idx; end
if isfield(opt,'p_participation') && isstruct(opt.p_participation) && ...
        isscalar(opt.p_participation)
    for k=participants(:)'
        id=char(dae.devices(k).device_id);
        if isfield(opt.p_participation,id)
            p(k)=opt.p_participation.(id);
        end
    end
elseif isfield(opt,'p_participation') && isnumeric(opt.p_participation) && ...
        numel(opt.p_participation)==numel(dae.devices)
    p=opt.p_participation(:);
else
    p(participants(1))=1;
end
if any(~isfinite(p)) || any(p<0) || ...
        any(p(setdiff(1:numel(p),participants))~=0)
    error('mixed_ibr_reduced_initialize:badParticipation', ...
        'Active-power participation must be finite, nonnegative and participant-only.');
end
total=sum(p(participants));
if total<=0
    error('mixed_ibr_reduced_initialize:badParticipation', ...
        'At least one active-power participant must have positive participation.');
end
p=p/total;
end

% =========================================================================
function [r,y,q_gfm,p_ref,kcl_rect] = reduced_residual(z, dae, online_idx, ...
    gfm_idx, reference_device_index, free_y, gauge_var, P_sched, Q_sched, V_ref)
ny = numel(dae.y0);
nq = numel(gfm_idx);
y = zeros(ny,1);
y(free_y) = z(1:numel(free_y));
y(gauge_var) = 0;
q_gfm = z(numel(free_y)+(1:nq));
p_ref = z(end);
V = y(1:2:end) + 1i*y(2:2:end);

if any(~isfinite(V)) || any(abs(V) <= sqrt(eps)) || ...
        any(~isfinite(q_gfm)) || ~isfinite(p_ref)
    r = NaN(ny+nq,1);
    kcl_rect = NaN(ny,1);
    return;
end

Ibus = zeros(dae.nb,1);
q_by_device = NaN(numel(dae.devices),1);
for iq = 1:nq, q_by_device(gfm_idx(iq)) = q_gfm(iq); end
for k = online_idx(:)'
    P = P_sched(k);
    Q = Q_sched(k);
    if any(gfm_idx==k)
        Q = q_by_device(k);
        if k == reference_device_index, P = p_ref; end
    end
    b = dae.devices(k).bus_position;
    Ibus(b) = Ibus(b) + conj(complex(P,Q)/V(b));
end

kcl_complex = dae.Ynet*V - Ibus;
kcl_rect = zeros(ny,1);
kcl_rect(1:2:end) = real(kcl_complex);
kcl_rect(2:2:end) = imag(kcl_complex);
vreg = zeros(nq,1);
for iq = 1:nq
    k = gfm_idx(iq);
    b = dae.devices(k).bus_position;
    % Squared magnitude avoids a derivative singularity at |V|=0, which is
    % already rejected above, and is exactly equivalent for positive V_ref.
    vreg(iq) = abs(V(b))^2 - V_ref(k)^2;
end
r = [kcl_rect; vreg];
end

% =========================================================================
function J = fd_jacobian(z, residual_fn, fd_eps)
r0 = residual_fn(z);
J = zeros(numel(r0),numel(z));
for j = 1:numel(z)
    zp = z;
    zp(j) = zp(j) + fd_eps;
    J(:,j) = (residual_fn(zp)-r0)/fd_eps;
end
end

% =========================================================================
function slot = find_input_slot(names, wanted, device_id)
slot = find(strcmpi(names,wanted),1);
if isempty(slot)
    error('mixed_ibr_reduced_initialize:missingInput', ...
        'Device %s does not declare input %s.',device_id,wanted);
end
end

% =========================================================================
function [is_online, mode] = runtime_status(dev, eq_context)
is_online = true;
if isfield(dev,'initial_online') && ~isempty(dev.initial_online)
    is_online = logical(dev.initial_online);
end
if isfield(dev,'initial_mode') && ~isempty(dev.initial_mode)
    mode = string(dev.initial_mode);
elseif isfield(dev,'mode') && ~isempty(dev.mode)
    mode = string(dev.mode);
else
    mode = "";
end
if isstruct(eq_context) && isfield(eq_context,'hybrid_state') && ...
        isstruct(eq_context.hybrid_state)
    hs = eq_context.hybrid_state;
    key = matlab.lang.makeValidName(char(dev.device_id), ...
        'ReplacementStyle','underscore');
    if isfield(hs,'device_online') && isfield(hs.device_online,key)
        is_online = logical(hs.device_online.(key));
    end
    if isfield(hs,'device_modes') && isfield(hs.device_modes,key)
        mode = string(hs.device_modes.(key));
    end
end
mode = lower(strtrim(mode));
end
