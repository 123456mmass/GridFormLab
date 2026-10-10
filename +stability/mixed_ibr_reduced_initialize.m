function init = mixed_ibr_reduced_initialize(dae, eq_context, reference_device_index, opt)
%MIXED_IBR_REDUCED_INITIALIZE  Physical SG-off IBR equilibrium warm start.
%   INIT = mixed_ibr_reduced_initialize(DAE, EQ_CONTEXT, SLACK_INDEX, OPT)
%   solves a project-owned reduced network problem for an island containing
%   online GFL/GFM IBRs and no online synchronous machine.  It is an
%   initializer only: mixed_equilibrium_solve subsequently verifies the full
%   device-state residual and physical KCL with the production closures.
%
%   Unknowns (single energized island):
%     y except Im(V_ref_bus), plus P_ref for exactly one selected reference
%     GFM.  Legacy voltage-reference devices additionally solve one terminal
%     Q per GFM. Im(V_ref_bus)=0 is coordinate elimination; no physical KCL
%     row is removed and no second device becomes SLACK.
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
%
%   Terminal-phase state alignment (opt-in by declared state name):
%     the solved island voltage fixes every synchronous machine's rotor angle
%     through its own classical port (delta_local = sg_delta*X'd), and the same
%     solved voltage is the stationary value of any device-local terminal
%     estimator whose plant equations are driven by angle(V_bus).  A device that
%     DECLARES state names theta_hat and nu_hat therefore gets that exact
%     stationary seed at the post-gauge solved voltage:
%         theta_hat = angle(V(bus)), nu_hat = 0
%     (the same convention its own equilibrium initializer uses).  This is a
%     seed, not a dynamics change: the device closures are untouched and the
%     full residual remains the acceptance test.  The pair is all-or-nothing
%     and must be declared exactly once each: a device declaring only one of
%     the two names, or a name twice, fails closed.  A device that does not
%     declare either name (the legacy two-state classical machine) is
%     bit-for-bit unaffected.

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
% The P/Q-reference EECON49 contract is the only supported one.  The
% voltage-reference ABI families ('ibr_dual_mode', 'ibr_dual_mode_rms10') were
% retired on 2026-09-26 with ibr.dual_mode_ibr_model, so no buildable
% configuration can carry those device_types and the former voltage-reference
% branch is unreachable (the online list is non-empty by construction above).
% Keep the allowlist explicit so an unknown future device still fails closed
% rather than entering this initializer by name similarity.
online_types = lower(string({dae.devices(online_idx).device_type}));
allowed = ismember(online_types,["ibr_eecon49_dual","sg_classical"]);
if ~all(allowed)
    init.failure_id = 'mixed_ibr_reduced_initialize:notPureIBRIsland';
    init.failure_reason = ['Reduced initializer requires eecon49_dual IBRs ' ...
        'and optional scheduled classical SG.'];
    return;
end
uses_pq_ref = true;
sg_idx = online_idx(online_types=="sg_classical");
ibr_idx = online_idx(online_types=="ibr_eecon49_dual");
if any(~ismember(lower(modes(ibr_idx)), ["gfl","gfm"])) || ...
        any(~ismember(lower(modes(sg_idx)), ["sg","synchronous"]))
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
for k = ibr_idx(:)'
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
    % หมุนแรงดันและมุม rotor ของ SG ที่เหลือด้วยมุมเดียวกัน
    % เพื่อให้ gauge Im(V_ref)=0 ไม่เปลี่ยนมุมสัมพัทธ์ของ PF.
    angle_shift=angle(Vpf(ref_dev.bus_position));
    Vseed=Vpf*exp(-1i*angle_shift);
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
    % The one scalar active-power mismatch settles on the selected reference
    % GFM alone; every other device keeps its scheduled P_ref.
    p_participation=resolve_p_participation(opt,dae,reference_device_index);
    q0=Q_sched(gfm_idx);
    sg_delta0=zeros(numel(sg_idx),1);
    for isg=1:numel(sg_idx)
        devk=dae.devices(sg_idx(isg));
        rec=devk.reconstruct(0,dae.x0(dae.device_offsets(sg_idx(isg))+(1:devk.nx)), ...
            dae.y0,dae.u0(dae.u_offsets(sg_idx(isg))+(1:devk.nu)),eq_context);
        sg_delta0(isg)=(dae.x0(dae.device_offsets(sg_idx(isg))+1)-angle_shift) ...
            /max(rec.Xdp,1e-6);
    end
    z0=[y_flat(free_y);q0;sg_delta0;0.0];
    residual_fn=@(z) pq_reference_residual(z,dae,online_idx,gfm_idx,sg_idx, ...
        reference_device_index,free_y,gauge_var,P_sched,Q_sched, ...
        p_participation,eq_context,Vpf(ref_dev.bus_position));
else
    p_participation=zeros(nd,1);
    p_participation(reference_device_index)=1;
    q0=zeros(numel(gfm_idx),1);
    z0=[y_flat(free_y);q0;p0];
    residual_fn=@(z) reduced_residual(z,dae,online_idx,gfm_idx, ...
        reference_device_index,free_y,gauge_var,P_sched,Q_sched,V_ref);
end
J_fn = @(z) fd_jacobian(z, residual_fn, fd_eps);
[z, niter, ok, rnorm, rc, ~, newton_info] = stability.composite_newton( ...
    z0, residual_fn, J_fn, tol, max_iter, verbose);

init.applicable = true;
init.iterations = niter;
init.residual_norm = rnorm;
init.rcond = rc;
init.newton_info = newton_info;
if ~ok
    init.failure_id = 'mixed_ibr_reduced_initialize:noConverge';
    init.failure_reason = sprintf( ...
        ['Reduced all-KCL slack solve failed: residual=%.3e after %d iterations; ' ...
         'rcond=%.3e, line_search_exhausted=%d, final_alpha=%.3e.'], ...
        rnorm, niter, rc, newton_info.line_search_exhausted, ...
        newton_info.final_tested_alpha);
    return;
end
if ~isfinite(rc) || rc < 1e-10
    init.failure_id = 'mixed_ibr_reduced_initialize:illConditioned';
    init.failure_reason = sprintf('Reduced initializer Jacobian rcond=%.3e.',rc);
    return;
end

if uses_pq_ref
    [~,y,q_gfm,p_ref,kcl,p_eq,sg_delta]=pq_reference_residual( ...
        z,dae,online_idx,gfm_idx,sg_idx,reference_device_index,free_y, ...
        gauge_var,P_sched,Q_sched,p_participation,eq_context, ...
        Vpf(ref_dev.bus_position));
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
for isg = 1:numel(sg_idx)
    k = sg_idx(isg);
    devk = dae.devices(k);
    xr = dae.device_offsets(k)+(1:devk.nx);
    ur = dae.u_offsets(k)+(1:devk.nu);
    % The FULL device state is passed to reconstruct: the opt-in reclose plant
    % has nx=7 and validates all seven coordinates.  The solved rotor angle
    % (local 1, scaled by X'd exactly as in the reduced residual) and omega
    % (local 2) are overwritten here; Psv/Pm/Emag keep their x0 values, and the
    % terminal-phase pair is seeded immediately below when the device declares
    % it.  The legacy nx==2 classical machine behaves exactly as before.
    rec=devk.reconstruct(0,x(xr),y,dae.u0(ur),eq_context);
    x(dae.device_offsets(k)+1) = sg_delta(isg)*max(rec.Xdp,1e-6);
    x(dae.device_offsets(k)+2) = 1;
end
% Stationary terminal-phase estimator seed at the SOLVED (post-gauge) voltage.
% The SG state rewrite above fixes the rotor angle, so a device-local phase
% estimator must be re-seeded from the same solved voltage or it keeps a
% pre-gauge value unrelated to the solved terminal phasor.  Applied only to
% devices that declare BOTH estimator state names; the legacy nx==2 machine
% declares neither, so its warm start is unchanged.  The pair is all-or-nothing:
% a device declaring only one of them, or declaring a name ambiguously more than
% once, fails closed rather than silently leaving one estimator state stale.
for k = sg_idx(:)'
    devk = dae.devices(k);
    theta_local = find(strcmpi(string(devk.state_names),'theta_hat'));
    nu_local = find(strcmpi(string(devk.state_names),'nu_hat'));
    if isempty(theta_local) && isempty(nu_local)
        continue;
    end
    if numel(theta_local) ~= 1 || numel(nu_local) ~= 1
        error('mixed_ibr_reduced_initialize:ambiguousPLLStates', ...
            ['Device %s must declare exactly one theta_hat and exactly one ' ...
             'nu_hat to receive the stationary terminal-phase seed (found %d ' ...
             'and %d).'], devk.device_id, numel(theta_local), numel(nu_local));
    end
    V_terminal = y(2*devk.bus_position-1) + 1i*y(2*devk.bus_position);
    x(dae.device_offsets(k)+theta_local) = angle(V_terminal);
    x(dae.device_offsets(k)+nu_local) = 0;
end
u_eq = dae.u0;
devices_eq = dae.devices;
if ~uses_pq_ref
    p_eq=P_sched;
    p_eq(reference_device_index)=p_ref;
end
q_by_device = NaN(nd,1);
for iq = 1:numel(gfm_idx), q_by_device(gfm_idx(iq)) = q_gfm(iq); end
for k = ibr_idx(:)'
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
    for k=ibr_idx(:)'
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
function [r,y,q_gfm,p_ref,kcl_rect,p_eq,sg_delta] = pq_reference_residual( ...
    z,dae,online_idx,gfm_idx,sg_idx,reference_device_index,free_y,gauge_var, ...
    P_sched,Q_sched,p_participation,eq_context,Vpf_ref)
ny=numel(dae.y0);
nq=numel(gfm_idx);
nsg=numel(sg_idx);
y=zeros(ny,1);
y(free_y)=z(1:numel(free_y));
y(gauge_var)=0;
q_gfm=z(numel(free_y)+(1:nq));
sg_delta=z(numel(free_y)+nq+(1:nsg));
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
    b=dae.devices(k).bus_position;
    if strcmpi(char(dae.devices(k).device_type),'sg_classical')
        ur=dae.u_offsets(k)+(1:dae.devices(k).nu);
        xr=dae.device_offsets(k)+(1:dae.devices(k).nx);
        xg=dae.x0(xr);
        rec=dae.devices(k).reconstruct(0,xg,y,dae.u0(ur),eq_context);
    xg(1)=sg_delta(find(sg_idx==k,1))*max(rec.Xdp,1e-6);
        xg(2)=1;
        Ibus(b)=Ibus(b)+dae.devices(k).current_injection( ...
            0,xg,y,dae.u0(ur),eq_context);
        continue;
    end
    P=p_eq(k);
    Q=Q_sched(k);
    if any(gfm_idx==k), Q=q_by_device(k); end
    Ibus(b)=Ibus(b)+conj(complex(P,Q)/V(b));
end
kcl_complex=dae.Ynet*V-Ibus;
kcl_rect=zeros(ny,1);
kcl_rect(1:2:end)=real(kcl_complex);
kcl_rect(2:2:end)=imag(kcl_complex);
e_res=zeros(nq,1);
sg_res=zeros(nsg,1);
for isg=1:nsg
    k=sg_idx(isg);
    dev=dae.devices(k);
    ur=dae.u_offsets(k)+(1:dev.nu);
    xr=dae.device_offsets(k)+(1:dev.nx);
    xg=dae.x0(xr);
    xg(1)=sg_delta(isg);
    xg(2)=1;
    xg(1)=sg_delta(isg)*max(dev.reconstruct(0,xg,y,dae.u0(ur),eq_context).Xdp,1e-6);
    sg_res(isg)=dev.electrical_power(0,xg,y,dae.u0(ur),eq_context)-dae.u0(ur(1));
end
for iq=1:nq
    k=gfm_idx(iq);
    dev=dae.devices(k);
    b=dev.bus_position;
    ur=dae.u_offsets(k)+(1:dev.nu);
    if isfield(dev.provenance,'branch_params') && ...
            isfield(dev.provenance.branch_params.gfm.dc_source,'fixed_plant') && ...
            dev.provenance.branch_params.gfm.dc_source.fixed_plant
        % reduced AC Newton ไม่ต้องแก้ DC ระหว่าง trial ที่ P/Q ยังไม่สมดุล.
        % ใช้ amplitude RHS เดียวกับ GFM closure; final initializer ด้านบน
        % ยังคงแก้ DC high branch และ full residual ตรวจทุก state ตามเดิม.
        gp=dev.provenance.branch_params.gfm;
        qs=find_input_slot(string(dev.input_names),"Q_ref",dev.device_id);
        es=find_input_slot(string(dev.input_names),"E_ref",dev.device_id);
        e_res(iq)=(gp.kQ*gp.kappa*(dae.u0(ur(qs))-q_gfm(iq)) ...
            -gp.kE*(abs(V(b))-dae.u0(ur(es))))/gp.tauE;
        continue;
    end
    xk=dev.equilibrium_initialize(V(b),p_eq(k),q_gfm(iq),eq_context);
    dx=dev.f(0,xk,y,dae.u0(ur),eq_context);
    e_local=find(strcmpi(string(dev.state_names),'gfm_E'),1);
    if isempty(e_local)
        error('mixed_ibr_reduced_initialize:missingEState', ...
            'P/Q-reference GFM %s does not declare gfm_E.',dev.device_id);
    end
    e_res(iq)=dx(e_local);
end
r=[kcl_rect;e_res;sg_res];
end

% =========================================================================
function p=resolve_p_participation(opt,dae,reference_device_index)
%RESOLVE_P_PARTICIPATION  One participant: the selected reference GFM.
%   The decision ledger (IEEE14_IBR_DECISION_LEDGER.md, item 8 / D12) and this
%   file's own header both state the balance contract: non-reference devices
%   retain their scheduled active-power inputs and the reference GFM P_ref is
%   the equilibrium unknown that balances load and losses.  The historical
%   participant set setdiff(online_idx,gfm_idx) did the opposite -- it pinned
%   the reference GFM and floated the GFL power controllers, which rewrote
%   their case/event-scheduled P_ref through p_eq=P_sched+w*delta_p and left
%   the measured post-trip terminal P off the approved schedule.
%
%   opt.p_participation remains accepted for ABI compatibility but no longer
%   distributes the mismatch: any supplied weights are collapsed onto the
%   reference device.  The function is therefore total -- no caller input can
%   move a non-reference P_ref off its schedule.
p=zeros(numel(dae.devices),1);
p(reference_device_index)=1;
if isfield(opt,'p_participation')
    % Weights are accepted and ignored by design (see header comment).  Keep
    % the shape checks so a caller passing garbage still fails closed.
    if isnumeric(opt.p_participation) && ~isscalar(opt.p_participation) && ...
            numel(opt.p_participation)~=numel(dae.devices)
        error('mixed_ibr_reduced_initialize:badParticipation', ...
            'A numeric p_participation must have one entry per device.');
    end
end
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
function [x_sg,ok] = classical_power_state(dev,x_sg,y,u_sg,eq_context)
%CLASSICAL_POWER_STATE มุม rotor ที่ Pe=Pm โดยคง Emag และ omega=1.
ok = true;
rec = dev.reconstruct(0,x_sg,y,u_sg,eq_context);
b = dev.bus_position;
V = complex(y(2*b-1),y(2*b));
arg = rec.Xdp*u_sg(1)/(rec.Emag*abs(V));
if ~isfinite(arg) || abs(arg) > 1 || ~(rec.Emag>0) || abs(V)<=0
    ok = false;
    return;
end
base = angle(V);
% สาขาของ asin ต้องคงที่ตลอด Newton ไม่งั้น Jacobian กระโดดที่จุดตัด.
% เลือกจากมุม PF เดิมซึ่งทำให้ Pe=Pm อยู่แล้ว ไม่เลือกสาขาที่ใกล้ trial ล่าสุด.
pf_rel = mod(x_sg(1)-base+pi,2*pi)-pi;
if abs(pf_rel-asin(arg)) <= abs(pf_rel-(pi-asin(arg)))
    x_sg(1) = base+asin(arg);
else
    x_sg(1) = base+pi-asin(arg);
end
x_sg(2) = 1;
end

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
