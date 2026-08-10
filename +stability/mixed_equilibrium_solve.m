function result = mixed_equilibrium_solve(case_data, config, opt)
%MIXED_EQUILIBRIUM_SOLVE  Solve f(x,y,u,mode)=0 + g(x,y,Y,u,mode)=0 for a candidate.
%   result = mixed_equilibrium_solve(case_data, config, opt) solves the
%   coupled dynamic + algebraic equilibrium for a candidate configuration
%   using the in-house composite DAE + a Newton layer on top.
%
%   Corrective plan (Phase G-1 binding):
%     - One configuration truth: event_context.hybrid_state is built once from
%       device initial_mode/initial_online via ts_hybrid_state_init, and the SAME
%       eq_context is passed to dae_f, dae_g, current injection, electrical
%       power, reconstruct and check_limits.
%     - Equilibrium-local active-state mask: offline/tripped devices contribute
%       zero differential residuals and zero network injection; only the active
%       subset of each device's states participates in Newton.  The complement
%       is held at the warm-start anchor dev.x0.
%     - The public state dimension nx_total is unchanged. For an SG-off IBR
%       island, exactly the committed GFM subset is active and one selected
%       GFM is the explicit P-balancing reference:
%         z = [x_active; y_except_ImVref; P_ref_reference]
%         R = [f_active; every physical KCL row].
%       Thus the angle gauge removes a coordinate, never a KCL equation.
%     - For an online SG REF, both rectangular reference-bus coordinates are
%       fixed to the case Vm/angle and the constant SG controls [Tm;Efd] are
%       solved as operating-point outputs while every physical KCL row is kept.
%       The returned u_eq is then held constant by TS/SSSA; no per-step slack
%       re-solve is permitted.
%     - Frozen physical states (e.g. SG Edp when Tpq0=0) remain excluded via
%       dev.frozen_state_indices as before.
%
%   Inputs:
%     case_data  - the IEEE14 1-SG/4-IBR case (case_ieee14_1sg_4ibr_auto_vsg)
%     config     - struct with:
%       .device_modes   struct array (.device_id, .mode)
%       .dispatch       optional override (default: case contract)
%       .devices        pre-built device struct array conforming to ABI
%       .selected_gfm_indices, .n_gfm_required, .reference_resource_index
%                       required atomically for an SG-off GFM island
%       .resource_ids   optional exact device-order guard for index selections
%     opt        - struct with tolerance, max_iter, fd_eps, verbose, load_model
%
%   Output: result struct with converged, x0, y0, u_eq, residual_norm, iterations,
%   rcond, fingerprint, failure_id, failure_reason, device_config, dispatch,
%   limit_checks, active_state_indices, dynamic_state_indices,
%   frozen_state_indices, vcon_vars, vcon_ref. active_state_indices is the
%   equilibrium/SSSA partition; dynamic_state_indices is the TS partition and
%   may additionally contain breaker-open SG coast/flux states.
%
%   Source: project Phase 4 design + Phase G-1 corrective plan. In-house Newton.
%   No external solver. The solver does NOT depend on test fixtures.

arguments
    case_data struct
    config struct
    opt struct = struct()
end

result = struct('converged', false, 'x0', [], 'y0', [], 'u_eq', [], ...
    'residual_norm', inf, 'iterations', 0, 'rcond', NaN, ...
    'fingerprint', struct(), 'failure_id', '', 'failure_reason', '', ...
    'device_config', config, 'dispatch', struct(), 'limit_checks', struct(), ...
    'active_state_indices', [], 'dynamic_state_indices', [], ...
    'frozen_state_indices', [], ...
    'vcon_vars', [], 'vcon_ref', 0.0, 'reference', struct(), ...
    'physical_kcl_norm', inf, 'devices', []);

% --- Defaults -------------------------------------------------------------
tol        = 1e-8;   if isfield(opt,'tolerance') && ~isempty(opt.tolerance), tol = opt.tolerance; end
max_iter   = 300;    if isfield(opt,'max_iter') && ~isempty(opt.max_iter), max_iter = opt.max_iter; end
fd_eps     = 3e-6;   if isfield(opt,'fd_eps') && ~isempty(opt.fd_eps), fd_eps = opt.fd_eps; end
verbose    = false;  if isfield(opt,'verbose') && ~isempty(opt.verbose), verbose = opt.verbose; end
load_model = 'cz_p_cz_q'; if isfield(opt,'load_model') && ~isempty(opt.load_model), load_model = opt.load_model; end

% --- Validate device list -------------------------------------------------
if ~isfield(config, 'devices') || isempty(config.devices)
    result.failure_id = 'mixed_equilibrium_solve:noDevices';
    result.failure_reason = 'config.devices must be supplied by the caller.';
    return;
end
devices = config.devices;

% --- One configuration truth: build or consume one immutable hybrid snapshot -
% Every device closure receives the SAME eq_context.  online/offline and mode
% are read from event_context.hybrid_state, never from stale dev.mode alone.
if isfield(config,'hybrid_state') && ~isempty(config.hybrid_state)
    if isfield(config,'device_modes') && ~isempty(config.device_modes)
        result.failure_id = 'mixed_equilibrium_solve:ambiguousConfiguration';
        result.failure_reason = ...
            'Supply either config.hybrid_state or config.device_modes, not both.';
        return;
    end
    [eq_hybrid_state,hs_reason] = validate_hybrid_snapshot( ...
        config.hybrid_state,devices);
    if ~isempty(hs_reason)
        result.failure_id = 'mixed_equilibrium_solve:badHybridState';
        result.failure_reason = hs_reason;
        return;
    end
else
    eq_hybrid_state = stability.ts_hybrid_state_init(devices);
end
% Explicit candidate modes, when supplied, override construction metadata.
% This keeps mask, equations, current injection, and reconstruction on one
% immutable configuration truth.
if isfield(config,'device_modes') && ~isempty(config.device_modes)
    for mk = 1:numel(config.device_modes)
        did = char(config.device_modes(mk).device_id);
        key = matlab.lang.makeValidName(did,'ReplacementStyle','underscore');
        if ~isfield(eq_hybrid_state.device_modes,key)
            result.failure_id = 'mixed_equilibrium_solve:unknownModeDevice';
            result.failure_reason = sprintf('device_modes references unknown device %s.',did);
            return;
        end
        eq_hybrid_state.device_modes.(key) = char(config.device_modes(mk).mode);
    end
end
[config, selection_context_error] = reconcile_selection_context( ...
    config, eq_hybrid_state);
if ~isempty(selection_context_error)
    result.failure_id = 'mixed_equilibrium_solve:selectionContextMismatch';
    result.failure_reason = selection_context_error;
    return;
end
result.device_config = config;
eq_context = struct('hybrid_state', eq_hybrid_state);

% --- Voltage-forming source and reference selection ------------------------
% IEEE14 is one energized island. The selected reference is a device index,
% never a hard-coded bus number or the first struct field name.
mpc = case_data.mpc;
online_count = 0;
vf_count = 0;
vf_indices = [];
online_sg_indices = [];
for dk = 1:numel(devices)
    dev = devices(dk);
    key = matlab.lang.makeValidName(char(dev.device_id), 'ReplacementStyle', 'underscore');
    is_online = true;
    if isfield(eq_hybrid_state.device_online, key)
        is_online = logical(eq_hybrid_state.device_online.(key));
    end
    if is_online
        online_count = online_count + 1;
        mode = '';
        if isfield(eq_hybrid_state.device_modes, key)
            mode = eq_hybrid_state.device_modes.(key);
        elseif isfield(dev, 'initial_mode'), mode = dev.initial_mode;
        elseif isfield(dev, 'mode'), mode = dev.mode;
        end
        if any(strcmpi(mode, {'sg','synchronous','gfm'}))
            vf_count = vf_count + 1;
            vf_indices(end+1) = dk; %#ok<AGROW>
        end
        if any(strcmpi(mode, {'sg','synchronous'}))
            online_sg_indices(end+1) = dk; %#ok<AGROW>
        end
    end
end
if online_count > 0 && vf_count < 1
    result.failure_id = 'mixed_equilibrium_solve:noVoltageFormingSource';
    result.failure_reason = sprintf( ...
        'No voltage-forming source per energized island (%d online, 0 VF).', ...
        online_count);
    return;
end

[reference_device_index, ref_error] = resolve_reference_index( ...
    devices, eq_hybrid_state, config, vf_indices, isempty(online_sg_indices));
if ~isempty(ref_error)
    result.failure_id = 'mixed_equilibrium_solve:badReference';
    result.failure_reason = ref_error;
    return;
end
% A committed GFM reference describes the SG_OFF right-limit configuration.
% While an SG is online, MATPOWER REF semantics require the unique online SG
% at the case REF bus to own the numerical reference. This prevents a mixed
% SG+GFM candidate from falling into row replacement with no balancing input.
if ~isempty(online_sg_indices)
    ref_bus_ids = mpc.bus(mpc.bus(:,2)==3,1);
    sg_ref_matches = [];
    for sk = online_sg_indices(:)'
        if any(devices(sk).bus_id == ref_bus_ids)
            sg_ref_matches(end+1) = sk; %#ok<AGROW>
        end
    end
    if numel(sg_ref_matches) ~= 1
        result.failure_id = 'mixed_equilibrium_solve:badSGReference';
        result.failure_reason = sprintf( ...
            'Expected exactly one online SG at the case REF bus; found %d.', ...
            numel(sg_ref_matches));
        return;
    end
    reference_device_index = sg_ref_matches(1);
end
reference_device = devices(reference_device_index);
reference_bus_position = reference_device.bus_position;
gauge_var = 2*reference_bus_position;   % eliminate Im(V_ref_bus)
gauge_row = gauge_var;
reference_mode = runtime_mode(reference_device,eq_hybrid_state);
use_gfm_slack = isempty(online_sg_indices) && strcmpi(reference_mode,'gfm');
use_sg_slack = any(strcmpi(reference_mode,{'sg','synchronous'}));
use_physical_slack = use_gfm_slack || use_sg_slack;

% --- Angle coordinate ------------------------------------------------------
vcon = struct();
if use_sg_slack
    bus_row = find(mpc.bus(:,1)==reference_device.bus_id,1);
    if isempty(bus_row) || size(mpc.bus,2)<8 || ...
            ~isfinite(mpc.bus(bus_row,8)) || mpc.bus(bus_row,8)<=0
        result.failure_id = 'mixed_equilibrium_solve:badReferenceVoltage';
        result.failure_reason = ...
            'The selected SG REF requires a finite positive case Vm setpoint.';
        return;
    end
    % MATPOWER REF contract: both |V| and angle are specified; P/Q are solved.
    % In rectangular coordinates at angle zero this fixes Re(V)=Vm, Im(V)=0.
    vcon.vars = [2*reference_bus_position-1, 2*reference_bus_position];
    vcon.rows = [];
    vcon.ref = [mpc.bus(bus_row,8); 0.0];
else
    vcon.vars = gauge_var;
    vcon.rows = gauge_row;
    vcon.ref = 0.0;
end

% composite_dae is assembled with pure KCL. The equilibrium layer eliminates
% the gauge variable directly; it never asks composite_dae to replace a KCL
% row with a coordinate constraint.
dae_opt = struct('load_model', load_model);

% --- Assemble the composite DAE (internal PF warm-start + closures) ----------
try
    dae = stability.composite_dae(case_data, devices, dae_opt);
catch me
    result.failure_id = 'mixed_equilibrium_solve:compositeAssembly';
    result.failure_reason = me.message;
    return;
end

% Reject an inconsistent caller-supplied frozen state before any mode-aware
% warm-start is allowed to replace dae.x0.  Otherwise an initializer can
% silently sanitize corrupted physical state input and bypass the existing
% post-initialization consistency gate below.
for dk=1:numel(dae.devices)
    dev=dae.devices(dk);
    if ~isfield(dev,'frozen_state_indices') || isempty(dev.frozen_state_indices)
        continue;
    end
    off=dae.device_offsets(dk);
    fsi=dev.frozen_state_indices(:)'; fsv=dev.frozen_state_values(:)';
    for fi=1:numel(fsi)
        gidx=off+fsi(fi);
        if abs(dae.x0(gidx)-fsv(fi))>1e-12
            result.failure_id='mixed_equilibrium_solve:frozenStateConsistency';
            result.failure_reason=sprintf( ...
                'Device "%s" frozen state index %d (global %d): expected %.15g, got %.15g.', ...
                dev.device_id,fsi(fi),gidx,fsv(fi),dae.x0(gidx));
            return;
        end
    end
end

% SG-on all-GFL uses P/Q-controlled buses, whereas the original network PF
% warm start retains the source PV labels.  Seed the coupled Newton with a
% project-owned mode-aware PQ PF and exact GFL branch states.  This is only an
% initializer; the full DAE/KCL residual below remains the acceptance test.
sg_on_gfl_init = struct('applicable',false,'converged',false, ...
    'failure_id','','failure_reason','');
if use_sg_slack
    sg_on_gfl_init = stability.mixed_ibr_sg_on_gfl_initialize( ...
        case_data, dae, eq_context, struct());
    if sg_on_gfl_init.applicable
        if ~sg_on_gfl_init.converged
            result.failure_id = sg_on_gfl_init.failure_id;
            result.failure_reason = sg_on_gfl_init.failure_reason;
            return;
        end
        dae.x0 = sg_on_gfl_init.x0;
        dae.y0 = sg_on_gfl_init.y0;
        dae.u0 = sg_on_gfl_init.u0;
    end
end

% --- Equilibrium-local active/frozen partition ------------------------------
% Physical frozen states (e.g. SG Edp at Tpq0=0) are excluded first.
frozen_x_indices = [];   % global indices into x vector
frozen_x_values  = [];
active_x_indices = 1:numel(dae.x0);
for dk = 1:numel(dae.devices)
    dev = dae.devices(dk);
    if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
        off = dae.device_offsets(dk);
        [fsi,frozen_error] = validate_local_indices( ...
            dev.frozen_state_indices,dev.nx,dev.device_id);
        if ~isempty(frozen_error) || ~isfield(dev,'frozen_state_values') || ...
                numel(dev.frozen_state_values)~=numel(fsi)
            result.failure_id = 'mixed_equilibrium_solve:badFrozenStateMetadata';
            if isempty(frozen_error)
                frozen_error = sprintf('Device %s frozen indices/values cardinality differs.', ...
                    dev.device_id);
            end
            result.failure_reason = frozen_error;
            return;
        end
        fsv = dev.frozen_state_values(:)';
        frozen_x_indices = [frozen_x_indices, off + fsi]; %#ok<AGROW>
        frozen_x_values  = [frozen_x_values, fsv]; %#ok<AGROW>
    end
end
active_x_indices = setdiff(active_x_indices, frozen_x_indices, 'stable');

% Mode/local-anchor partition: a device's active subset is the intersection of
% its declared active_state_indices with the ONLINE status.  Offline devices
% contribute no differential residuals and zero network injection, so all their
% non-physically-frozen states are held at the warm-start anchor.
local_frozen_indices = [];   % indices held at warm-start anchor
local_frozen_anchors = [];
dynamic_x_indices = [];      % physical TS states under the same context
for dk = 1:numel(dae.devices)
    dev = dae.devices(dk);
    off = dae.device_offsets(dk);
    key = matlab.lang.makeValidName(char(dev.device_id), 'ReplacementStyle', 'underscore');
    is_online = true;
    if isfield(eq_hybrid_state.device_online, key)
        is_online = logical(eq_hybrid_state.device_online.(key));
    end

    % TS and equilibrium use different partitions for a breaker-open SG:
    % equilibrium excludes it because no stationary root exists with retained
    % mechanical torque, while TS must integrate its sourced coast/open-circuit
    % equations. Dual-mode IBRs expose their mode/online dynamic subset through
    % active_state_indices_for_context and return [] when offline.
    if isfield(dev,'dynamic_state_indices_for_context') && ...
            isa(dev.dynamic_state_indices_for_context,'function_handle')
        dev_dynamic = dev.dynamic_state_indices_for_context(eq_context);
    elseif isfield(dev,'active_state_indices_for_context') && ...
            isa(dev.active_state_indices_for_context,'function_handle')
        dev_dynamic = dev.active_state_indices_for_context(eq_context);
    elseif is_online && isfield(dev,'active_state_indices')
        dev_dynamic = dev.active_state_indices;
    elseif is_online
        dev_dynamic = 1:dev.nx;
    else
        dev_dynamic = [];
    end
    [dev_dynamic,dynamic_error] = validate_local_indices( ...
        dev_dynamic,dev.nx,dev.device_id);
    if ~isempty(dynamic_error)
        result.failure_id = 'mixed_equilibrium_solve:badDynamicStateMetadata';
        result.failure_reason = dynamic_error;
        return;
    end
    if isfield(dev,'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
        dev_dynamic = setdiff(dev_dynamic,dev.frozen_state_indices(:)','stable');
    end
    dynamic_x_indices = [dynamic_x_indices,off + dev_dynamic]; %#ok<AGROW>

    if ~is_online
        % Offline device: all non-physically-frozen states held at anchor.
        dev_all = 1:dev.nx;
        dev_local_frozen = dev_all;
        if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
            dev_local_frozen = setdiff(dev_local_frozen, dev.frozen_state_indices(:)', 'stable');
        end
        local_frozen_indices = [local_frozen_indices, off + dev_local_frozen]; %#ok<AGROW>
        local_frozen_anchors = [local_frozen_anchors, dev.x0(dev_local_frozen)']; %#ok<AGROW>
    elseif isfield(dev,'active_state_indices_for_context') && ...
            isa(dev.active_state_indices_for_context,'function_handle')
        dev_active = dev.active_state_indices_for_context(eq_context);
        [dev_active, active_error] = validate_local_indices(dev_active,dev.nx,dev.device_id);
        if ~isempty(active_error)
            result.failure_id = 'mixed_equilibrium_solve:badActiveStateMetadata';
            result.failure_reason = active_error;
            return;
        end
        dev_all = 1:dev.nx;
        dev_local_frozen = setdiff(dev_all, dev_active, 'stable');
        if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
            dev_local_frozen = setdiff(dev_local_frozen, dev.frozen_state_indices(:)', 'stable');
        end
        local_frozen_indices = [local_frozen_indices, off + dev_local_frozen]; %#ok<AGROW>
        local_frozen_anchors = [local_frozen_anchors, dev.x0(dev_local_frozen)']; %#ok<AGROW>
    elseif isfield(dev, 'active_state_indices')
        % An explicitly empty set is meaningful (e.g. tripped mode).
        [dev_active, active_error] = validate_local_indices( ...
            dev.active_state_indices,dev.nx,dev.device_id);
        if ~isempty(active_error)
            result.failure_id = 'mixed_equilibrium_solve:badActiveStateMetadata';
            result.failure_reason = active_error;
            return;
        end
        % local complement = device states not active and not already physically frozen
        dev_all = 1:dev.nx;
        dev_local_frozen = setdiff(dev_all, dev_active, 'stable');
        if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
            dev_local_frozen = setdiff(dev_local_frozen, dev.frozen_state_indices(:)', 'stable');
        end
        local_frozen_indices = [local_frozen_indices, off + dev_local_frozen]; %#ok<AGROW>
        local_frozen_anchors = [local_frozen_anchors, dev.x0(dev_local_frozen)']; %#ok<AGROW>
    end
end
% Final active set: remove local frozen states from active_x_indices.
active_x_indices = setdiff(active_x_indices, local_frozen_indices, 'stable');
% Combined frozen set for reconstruction.
all_frozen_indices = [frozen_x_indices, local_frozen_indices];
all_frozen_values  = [frozen_x_values, local_frozen_anchors];

% --- Fail-closed validation of the partition --------------------------------
if ~isempty(intersect(active_x_indices, all_frozen_indices))
    result.failure_id = 'mixed_equilibrium_solve:partitionOverlap';
    result.failure_reason = 'Active and frozen state indices overlap.';
    return;
end
if ~isequal(sort([active_x_indices(:); all_frozen_indices(:)]), (1:numel(dae.x0))')
    result.failure_id = 'mixed_equilibrium_solve:partitionIncomplete';
    result.failure_reason = 'Active/frozen partition does not cover 1:nx_total.';
    return;
end
if ~all(isfinite(all_frozen_values))
    result.failure_id = 'mixed_equilibrium_solve:nonFiniteAnchor';
    result.failure_reason = 'A frozen-state anchor is non-finite.';
    return;
end

% --- Equation-consistent initialization ------------------------------------
u_eq_init = dae.u0;
devices_eq = devices;
reduced_init = struct();
if use_gfm_slack
    try
        reduced_opt=struct('tolerance',tol,'max_iter',max_iter, ...
            'fd_eps',fd_eps,'verbose',verbose);
        if isfield(case_data,'dispatch_contract') && ...
                isfield(case_data.dispatch_contract,'post_trip') && ...
                isfield(case_data.dispatch_contract.post_trip,'participation')
            reduced_opt.p_participation= ...
                case_data.dispatch_contract.post_trip.participation;
        end
        reduced_init = stability.mixed_ibr_reduced_initialize( ...
            dae,eq_context,reference_device_index,reduced_opt);
    catch me
        result.failure_id = 'mixed_equilibrium_solve:initializerFailure';
        result.failure_reason = sprintf( ...
            'Reduced SG_OFF initializer failed closed: %s',me.message);
        return;
    end
    if ~reduced_init.applicable || ~reduced_init.converged
        result.failure_id = reduced_init.failure_id;
        result.failure_reason = reduced_init.failure_reason;
        return;
    end
    x0_init = reduced_init.x0;
    y0 = reduced_init.y0;
    u_eq_init = reduced_init.u_eq;
    devices_eq = reduced_init.devices;
else
    x0_init = dae.x0;
    y0 = dae.y0;
end
devices_eq = apply_context_to_devices(devices_eq,eq_hybrid_state);

% Physical frozen-state consistency check.
for dk = 1:numel(dae.devices)
    dev = dae.devices(dk);
    if isfield(dev, 'frozen_state_indices') && ~isempty(dev.frozen_state_indices)
        off = dae.device_offsets(dk);
        for fi = 1:numel(dev.frozen_state_indices)
            gidx = off + dev.frozen_state_indices(fi);
            expected_val = dev.frozen_state_values(fi);
            actual_val = x0_init(gidx);
            if abs(actual_val - expected_val) > 1e-12
                result.failure_id = 'mixed_equilibrium_solve:frozenStateConsistency';
                result.failure_reason = sprintf( ...
                    'Device "%s" frozen state index %d (global %d): expected %.15g, got %.15g.', ...
                    dev.device_id, dev.frozen_state_indices(fi), gidx, ...
                    expected_val, actual_val);
                return;
            end
        end
    end
end
% Enforce local anchors.
for fi = 1:numel(local_frozen_indices)
    x0_init(local_frozen_indices(fi)) = local_frozen_anchors(fi);
end
% Enforce physical frozen values.
for fi = 1:numel(frozen_x_indices)
    x0_init(frozen_x_indices(fi)) = frozen_x_values(fi);
end

% --- Newton layer on the coupled physical system ---------------------------
vcon_vars = vcon.vars;
vcon_ref = vcon.ref;
ny_full = numel(y0);
free_vars = setdiff(1:ny_full, vcon_vars, 'stable');   % free y indices
y_full_init = y0;
y_full_init(vcon_vars) = vcon_ref;          % enforce the angle gauge
y_free_init = y_full_init(free_vars);
nx_total = numel(x0_init);
nx_active = numel(active_x_indices);
ny_free = numel(y_free_init);

Ynet = dae.Ynet;
u_base = u_eq_init;
slack_u_index = [];
slack_slots = [];
if use_gfm_slack
    slack_slot = find(strcmpi(string(reference_device.input_names),'P_ref'),1);
    if isempty(slack_slot)
        result.failure_id = 'mixed_equilibrium_solve:referenceMissingPInput';
        result.failure_reason = 'Reference GFM does not declare P_ref.';
        return;
    end
    slack_slots = slack_slot;
    slack_u_index = dae.u_offsets(reference_device_index) + slack_slot;
elseif use_sg_slack
    tm_slot = find(strcmpi(string(reference_device.input_names),'Tm'),1);
    efd_slot = find(strcmpi(string(reference_device.input_names),'Efd'),1);
    if isempty(tm_slot) || isempty(efd_slot) || tm_slot==efd_slot
        result.failure_id = 'mixed_equilibrium_solve:referenceMissingSGInputs';
        result.failure_reason = ...
            'Reference SG must declare distinct Tm and Efd equilibrium inputs.';
        return;
    end
    slack_slots = [tm_slot,efd_slot];
    slack_u_index = dae.u_offsets(reference_device_index) + slack_slots;
end
if use_physical_slack
    z0 = [x0_init(active_x_indices); y_free_init(:); u_base(slack_u_index)];
    algebraic_rows = 1:ny_full;   % every physical KCL row
else
    z0 = [x0_init(active_x_indices); y_free_init(:)];
    algebraic_rows = setdiff(1:ny_full,gauge_row,'stable');
end

residual_fn = @(z) coupled_residual( ...
    z, active_x_indices, all_frozen_indices, all_frozen_values, ...
    free_vars, vcon_vars, vcon_ref, ny_full, dae, Ynet, u_base, ...
    slack_u_index, algebraic_rows, eq_context);

% Actual residual/unknown cardinality, not a counting tautology.
r_initial = residual_fn(z0);
if numel(r_initial) ~= numel(z0)
    result.failure_id = 'mixed_equilibrium_solve:nonSquarePartition';
    result.failure_reason = sprintf( ...
        'Physical residual has %d rows for %d unknowns.',numel(r_initial),numel(z0));
    return;
end

J_fn = @(z) coupled_jacobian_fd(z, residual_fn, fd_eps);

    % --- Active-bound constraint collection ----------------------------------
    all_con_specs = stability.active_bound_collect(...
        dae, x0_init, y_full_init, u_eq_init, eq_context);

    if isempty(all_con_specs)
        % G1 fast path: direct Newton (no constraints)
        [z_sol, niter, converged, residual_norm, rcond_val] = ...
            stability.composite_newton(z0, residual_fn, J_fn, tol, max_iter, verbose);
        ab_fail_id = ''; ab_fail_reason = ''; ab_outer = 0;
        ab_regime_hist = [];
    else
        % G2 path: active-bound outer loop
        [z_sol, niter, converged, residual_norm, rcond_val, ...
         ab_fail_id, ab_fail_reason, ab_outer, ab_regime_hist] = ...
            stability.active_bound_run(z0, residual_fn, fd_eps, ...
            active_x_indices, all_frozen_indices, all_frozen_values, ...
            free_vars, vcon_vars, vcon_ref, ny_full, u_base, slack_u_index, ...
            all_con_specs, eq_context, tol, max_iter, verbose);
    end

result.iterations = niter;
result.rcond = rcond_val;
result.residual_norm = residual_norm;
result.converged = converged;
result.active_state_indices = active_x_indices;
result.dynamic_state_indices = dynamic_x_indices;
result.frozen_state_indices = all_frozen_indices;
result.partition = struct('nx_total',nx_total,'nx_active',nx_active, ...
    'nx_frozen',numel(all_frozen_indices),'ny_total',ny_full, ...
    'ny_free',ny_free,'slack_input_unknowns',numel(slack_u_index), ...
    'newton_dimension',numel(z0),'residual_rows',numel(r_initial));
result.equilibrium_context = eq_context;
result.initialization = struct('sg_on_all_gfl',sg_on_gfl_init);
result.active_bound_outer_iterations = ab_outer;
result.active_bound_regime_history   = ab_regime_hist;

if ~converged
    if ~isempty(ab_fail_id)
        result.failure_id = ab_fail_id;
        result.failure_reason = ab_fail_reason;
    else
        result.failure_id = 'mixed_equilibrium_solve:noConverge';
        result.failure_reason = sprintf( ...
            'Coupled Newton did not converge: residual=%.3e after %d iters (tol=%.2e).', ...
            residual_norm, niter, tol);
    end
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
x_active_sol = z_sol(1:nx_active);
y_free_sol = z_sol(nx_active+1:nx_active+ny_free);
u_sol = u_base;
if use_physical_slack
    solved_controls = z_sol(end-numel(slack_u_index)+1:end);
    u_sol(slack_u_index) = solved_controls;
    devices_eq(reference_device_index).u0(slack_slots) = solved_controls;
end
x_sol = zeros(nx_total, 1);
x_sol(active_x_indices) = x_active_sol;
for fi = 1:numel(all_frozen_indices)
    x_sol(all_frozen_indices(fi)) = all_frozen_values(fi);
end
y_sol = zeros(ny_full, 1);
y_sol(vcon_vars) = vcon_ref;
y_sol(free_vars) = y_free_sol;
result.x0 = x_sol;
result.y0 = y_sol;
result.u_eq = u_sol;
result.devices = devices_eq;

% --- Physical KCL gate: no coordinate constraint may hide a network row ---
try
    [physical_kcl, Ibus] = physical_kcl_residual(dae,x_sol,y_sol,u_sol,eq_context);
catch me
    result.converged = false;
    result.failure_id = 'mixed_equilibrium_solve:physicalKCLFailure';
    result.failure_reason = me.message;
    return;
end
result.physical_kcl_norm = norm(physical_kcl,inf);
if result.physical_kcl_norm >= 1e-6
    result.converged = false;
    result.failure_id = 'mixed_equilibrium_solve:physicalKCL';
    result.failure_reason = sprintf( ...
        'Physical all-row KCL residual %.3e exceeds 1e-6.', ...
        result.physical_kcl_norm);
    return;
end

% Reference slack is an explicit solved operating-point quantity.
result.reference = struct( ...
    'device_index',reference_device_index, ...
    'device_id',reference_device.device_id, ...
    'bus_position',reference_bus_position, ...
    'gauge_variable_index',gauge_var, ...
    'mode',reference_mode, ...
    'balances_active_power',use_physical_slack, ...
    'physical_kcl_enforced',true, ...
    'slack_input_names',{cellstr(string(reference_device.input_names(slack_slots)))}, ...
    'P_scheduled_pu',NaN,'P_scheduled_MW',NaN, ...
    'P_solved_pu',NaN,'P_solved_MW',NaN,'P_deviation_MW',NaN, ...
    'Tm_scheduled_pu',NaN,'Tm_solved_pu',NaN, ...
    'Efd_scheduled_pu',NaN,'Efd_solved_pu',NaN);
if use_gfm_slack
    result.reference.P_scheduled_pu = reduced_init.reference_p_scheduled_pu;
    result.reference.P_scheduled_MW = ...
        reduced_init.reference_p_scheduled_pu*mpc.baseMVA;
    result.reference.P_solved_pu = u_sol(slack_u_index);
    result.reference.P_solved_MW = u_sol(slack_u_index)*mpc.baseMVA;
    result.reference.P_deviation_MW = result.reference.P_solved_MW - ...
        result.reference.P_scheduled_MW;
    [p_ok,p_reason] = check_reference_p_limit(case_data,reference_device, ...
        result.reference.P_solved_MW);
    if ~p_ok
        result.converged = false;
        result.failure_id = 'mixed_equilibrium_solve:referencePLimit';
        result.failure_reason = p_reason;
        return;
    end
elseif use_sg_slack
    result.reference.Tm_scheduled_pu = u_base(slack_u_index(1));
    result.reference.Efd_scheduled_pu = u_base(slack_u_index(2));
    result.reference.Tm_solved_pu = u_sol(slack_u_index(1));
    result.reference.Efd_solved_pu = u_sol(slack_u_index(2));
end

% --- Limit checks ---------------------------------------------------------
result.limit_checks = check_limits(x_sol, y_sol, u_sol, case_data, ...
    dae, eq_context, Ibus);
if use_physical_slack
    limit_names = fieldnames(result.limit_checks.devices);
    for lk = 1:numel(limit_names)
        if ~result.limit_checks.devices.(limit_names{lk}).within_limits
            result.converged = false;
            result.failure_id = 'mixed_equilibrium_solve:deviceLimit';
            result.failure_reason = sprintf( ...
                'Device %s violates an equilibrium operating limit.',limit_names{lk});
            return;
        end
    end
end

% --- Fingerprint ----------------------------------------------------------
result.fingerprint = compute_fingerprint(x_sol, y_sol, u_sol, config);
result.vcon_vars = vcon.vars;
result.vcon_ref = vcon.ref;
if use_physical_slack
    result.vcon_type = 'coordinate_elimination_all_kcl';
else
    result.vcon_type = 'legacy_row_replacement';
end
result.dispatch = struct();
if isfield(config, 'dispatch')
    result.dispatch = config.dispatch;
end
if use_gfm_slack
    result.dispatch.reference_device_id = reference_device.device_id;
    result.dispatch.reference_P_solved_MW = result.reference.P_solved_MW;
end
end

% =========================================================================
function r = coupled_residual(z, active_x_indices, frozen_x_indices, ...
    frozen_x_values, free_vars, vcon_vars, vcon_ref, ny_full, dae, Y, ...
    u_base, slack_u_index, algebraic_rows, eq_context)
% z = [x_active; y_free]. Frozen x states are excluded from Newton unknowns
% and held at their algebraic/anchor values. The RHS is evaluated on the full
% x,y with the SAME eq_context passed to all device closures.
nx_active = numel(active_x_indices);
x_active = z(1:nx_active);
y_free = z(nx_active+(1:numel(free_vars)));
% Reconstruct full x.
nx_total = numel(active_x_indices) + numel(frozen_x_indices);
x_full = zeros(nx_total, 1);
x_full(active_x_indices) = x_active;
for fi = 1:numel(frozen_x_indices)
    x_full(frozen_x_indices(fi)) = frozen_x_values(fi);
end
% Scatter y.
y_full = zeros(ny_full, 1);
y_full(vcon_vars) = vcon_ref;
y_full(free_vars) = y_free;
u = u_base;
if ~isempty(slack_u_index)
    n_slack = numel(slack_u_index);
    u(slack_u_index) = z(end-n_slack+1:end);
end
% Evaluate composite RHS with the unified equilibrium context.
f = dae.dae_f(0, x_full, y_full, u, eq_context);
g = dae.dae_g(0, x_full, y_full, Y, u, eq_context);
% Active differential rows plus the declared physical KCL rows. In either
% physical reference formulation algebraic_rows contains every KCL row.
f_active = f(active_x_indices);
r = [f_active(:); g(algebraic_rows)];
end

% =========================================================================
function J = coupled_jacobian_fd(z, residual_fn, fd_eps)
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
function [config,reason] = reconcile_selection_context(config,hs)
%RECONCILE_SELECTION_CONTEXT  One atomic owner for GFM commitment metadata.
%   Event snapshots carry the committed tuple. A duplicate caller tuple is
%   accepted only when identical; otherwise the solve fails closed.
reason = '';
[cfg_tuple,cfg_has,cfg_reason] = selection_tuple_from_config(config);
if ~isempty(cfg_reason), reason = cfg_reason; return; end
[hs_tuple,hs_has,hs_reason] = selection_tuple_from_hybrid_state(hs);
if ~isempty(hs_reason), reason = hs_reason; return; end
if cfg_has && hs_has && ~selection_tuples_equal(cfg_tuple,hs_tuple)
    reason = ['config selection conflicts with the immutable hybrid-state ' ...
        'commitment.'];
    return;
end
if hs_has
    tuple = hs_tuple;
elseif cfg_has
    tuple = cfg_tuple;
else
    return;
end
config.selected_gfm_indices = tuple.selected_gfm_indices;
config.n_gfm_required = tuple.n_gfm_required;
config.reference_resource_index = tuple.reference_resource_index;
if isfield(config,'selected_config')
    config = rmfield(config,'selected_config');
end
end

function [tuple,has,reason] = selection_tuple_from_config(config)
tuple = struct('selected_gfm_indices',[],'n_gfm_required',[], ...
    'reference_resource_index',[]);
has = false; reason = '';
[top,top_has,top_reason] = selection_tuple_from_owner(config,'config');
if ~isempty(top_reason), reason = top_reason; return; end
nested = tuple; nested_has = false;
if isfield(config,'selected_config') && ~isempty(config.selected_config)
    if ~isstruct(config.selected_config) || ~isscalar(config.selected_config)
        reason = 'config.selected_config must be one scalar struct.';
        return;
    end
    [nested,nested_has,nested_reason] = selection_tuple_from_owner( ...
        config.selected_config,'config.selected_config');
    if ~isempty(nested_reason), reason = nested_reason; return; end
end
if top_has && nested_has
    reason = ['Selection commitment must have one owner: use either the ' ...
        'top-level config fields or config.selected_config, not both.'];
    return;
elseif top_has
    tuple = top; has = true;
elseif nested_has
    tuple = nested; has = true;
end
end

function [tuple,has,reason] = selection_tuple_from_hybrid_state(hs)
tuple = struct('selected_gfm_indices',[],'n_gfm_required',[], ...
    'reference_resource_index',[]);
has = false; reason = '';
[direct,direct_has,direct_reason] = selection_tuple_from_owner(hs,'hybrid_state');
if ~isempty(direct_reason), reason = direct_reason; return; end
nested = tuple; nested_has = false;
if isfield(hs,'committed_selection') && ~isempty(hs.committed_selection)
    if ~isstruct(hs.committed_selection) || ~isscalar(hs.committed_selection)
        reason = 'hybrid_state.committed_selection must be one scalar struct.';
        return;
    end
    [nested,nested_has,nested_reason] = selection_tuple_from_owner( ...
        hs.committed_selection,'hybrid_state.committed_selection');
    if ~isempty(nested_reason), reason = nested_reason; return; end
end
if direct_has && nested_has && ~selection_tuples_equal(direct,nested)
    reason = 'Hybrid-state direct and nested commitment tuples conflict.';
    return;
elseif direct_has
    tuple = direct; has = true;
elseif nested_has
    tuple = nested; has = true;
end
end

function [tuple,has,reason] = selection_tuple_from_owner(owner,label)
tuple = struct('selected_gfm_indices',[],'n_gfm_required',[], ...
    'reference_resource_index',[]);
reason = '';
names = {'selected_gfm_indices','n_gfm_required','reference_resource_index'};
present = false(1,3);
for k = 1:3
    present(k) = isfield(owner,names{k}) && ~isempty(owner.(names{k}));
end
has = any(present);
if has && ~all(present)
    reason = sprintf('%s must carry the three selection fields atomically.',label);
    return;
end
if has
    for k = 1:3, tuple.(names{k}) = owner.(names{k}); end
end
end

function tf = selection_tuples_equal(a,b)
tf = isequal(sort(a.selected_gfm_indices(:)'), ...
    sort(b.selected_gfm_indices(:)')) && ...
    isequal(a.n_gfm_required,b.n_gfm_required) && ...
    isequal(a.reference_resource_index,b.reference_resource_index);
end

% =========================================================================
function [reference_index, reason] = resolve_reference_index( ...
    devices, hs, config, vf_indices, require_explicit_gfm_selection)
reference_index = [];
reason = '';
if isempty(vf_indices)
    reason = 'No online voltage-forming resource is available.';
    return;
end

% Resource/device indices are meaningful only against one declared ordering.
% When the caller supplies the resource IDs, require exact alignment with the
% device array before interpreting any selected index.
if isfield(config,'resource_ids') && ~isempty(config.resource_ids)
    declared_ids = reshape(cellstr(string(config.resource_ids)),1,[]);
    actual_ids = reshape({devices.device_id},1,[]);
    if numel(declared_ids) ~= numel(actual_ids) || ...
            ~all(strcmp(declared_ids,actual_ids))
        reason = 'config.resource_ids do not align exactly with config.devices order.';
        return;
    end
end

top_selection_present = (isfield(config,'selected_gfm_indices') && ...
    ~isempty(config.selected_gfm_indices)) || ...
    (isfield(config,'n_gfm_required') && ~isempty(config.n_gfm_required)) || ...
    (isfield(config,'reference_resource_index') && ...
    ~isempty(config.reference_resource_index));
nested_selection_present = false;
if isfield(config,'selected_config') && isstruct(config.selected_config)
    sc_check = config.selected_config;
    nested_selection_present = ...
        (isfield(sc_check,'selected_gfm_indices') && ...
        ~isempty(sc_check.selected_gfm_indices)) || ...
        (isfield(sc_check,'n_gfm_required') && ...
        ~isempty(sc_check.n_gfm_required)) || ...
        (isfield(sc_check,'reference_resource_index') && ...
        ~isempty(sc_check.reference_resource_index));
end
if top_selection_present && nested_selection_present
    reason = ['Selection commitment must have one owner: use either the ' ...
        'top-level fields or config.selected_config, not both.'];
    return;
end

has_selected = isfield(config,'selected_gfm_indices') && ...
    ~isempty(config.selected_gfm_indices);
has_required = isfield(config,'n_gfm_required') && ...
    ~isempty(config.n_gfm_required);
has_reference = isfield(config,'reference_resource_index') && ...
    ~isempty(config.reference_resource_index);
if isfield(config,'selected_config') && isstruct(config.selected_config)
    sc = config.selected_config;
    has_selected = has_selected || (isfield(sc,'selected_gfm_indices') && ...
        ~isempty(sc.selected_gfm_indices));
    has_required = has_required || (isfield(sc,'n_gfm_required') && ...
        ~isempty(sc.n_gfm_required));
    has_reference = has_reference || (isfield(sc,'reference_resource_index') && ...
        ~isempty(sc.reference_resource_index));
end
if (has_selected || has_required || has_reference) && ...
        ~(has_selected && has_required && has_reference)
    reason = ['selected_gfm_indices, n_gfm_required, and ' ...
        'reference_resource_index must be supplied atomically.'];
    return;
end
if require_explicit_gfm_selection && ...
        ~(has_selected && has_required && has_reference)
    reason = ['An SG_OFF GFM island requires an explicit selected GFM set, ' ...
        'exact count, and one selected reference index.'];
    return;
end

candidate = [];
if isfield(config,'reference_resource_index') && ~isempty(config.reference_resource_index)
    candidate = config.reference_resource_index;
elseif isfield(config,'selected_config') && isstruct(config.selected_config) && ...
        isfield(config.selected_config,'reference_resource_index')
    candidate = config.selected_config.reference_resource_index;
elseif isfield(config,'reference_resource_id') && ~isempty(config.reference_resource_id)
    candidate = find(strcmp({devices.device_id},char(config.reference_resource_id)),1);
end
if isempty(candidate)
    % Legacy SG-online candidates retain stable device order. SG_OFF GFM
    % islands were rejected above unless the reference was explicit.
    candidate = vf_indices(1);
end
if ~isscalar(candidate) || ~isfinite(candidate) || candidate ~= fix(candidate) || ...
        candidate < 1 || candidate > numel(devices)
    reason = 'reference_resource_index must be one valid scalar device index.';
    return;
end
if ~any(vf_indices==candidate)
    reason = sprintf('Reference index %d is not an online voltage-forming resource.',candidate);
    return;
end

% If a selected GFM set is supplied, validate its cardinality and membership.
selected = [];
required = [];
if isfield(config,'selected_gfm_indices'), selected = config.selected_gfm_indices; end
if isfield(config,'n_gfm_required'), required = config.n_gfm_required; end
if isfield(config,'selected_config') && isstruct(config.selected_config)
    sc = config.selected_config;
    if isfield(sc,'selected_gfm_indices'), selected = sc.selected_gfm_indices; end
    if isfield(sc,'n_gfm_required'), required = sc.n_gfm_required; end
end
if ~isempty(selected)
    if any(~isfinite(selected)) || any(selected~=fix(selected)) || ...
            any(selected<1) || any(selected>numel(devices)) || ...
            numel(unique(selected))~=numel(selected)
        reason = 'selected_gfm_indices must contain unique valid device indices.';
        return;
    end
    if isempty(required) || ~isscalar(required) || ~isfinite(required) || ...
            required ~= fix(required) || required < 1 || ...
            required~=numel(selected)
        reason = 'n_gfm_required must equal numel(selected_gfm_indices).';
        return;
    end
    if ~any(selected==candidate)
        reason = 'reference_resource_index must belong to selected_gfm_indices.';
        return;
    end
    runtime_gfm = [];
    for k = 1:numel(devices)
        key = matlab.lang.makeValidName(char(devices(k).device_id), ...
            'ReplacementStyle','underscore');
        is_online = isfield(hs,'device_online') && ...
            isfield(hs.device_online,key) && logical(hs.device_online.(key));
        if is_online && strcmpi(runtime_mode(devices(k),hs),'gfm')
            runtime_gfm(end+1) = k; %#ok<AGROW>
        end
    end
    if ~isequal(sort(selected(:)'),sort(runtime_gfm(:)'))
        reason = ['selected_gfm_indices must equal the complete online ' ...
            'runtime GFM index set.'];
        return;
    end
    for k = selected(:)'
        if ~is_gfm_capable_device(devices(k))
            reason = sprintf( ...
                'Selected index %d is not a dual-mode GFM-capable IBR.',k);
            return;
        end
    end
end
reference_index = candidate;
end

% =========================================================================
function tf = is_gfm_capable_device(dev)
tf = false;
if ~isfield(dev,'capabilities') || ~isstruct(dev.capabilities)
    return;
end
c = dev.capabilities;
needed = {'resource_type','can_switch_mode','supported_modes', ...
    'voltage_forming_modes'};
if ~all(isfield(c,needed))
    return;
end
tf = strcmpi(char(c.resource_type),'ibr') && ...
    islogical(c.can_switch_mode) && isscalar(c.can_switch_mode) && ...
    c.can_switch_mode && any(strcmpi(string(c.supported_modes),'gfm')) && ...
    any(strcmpi(string(c.supported_modes),'gfl')) && ...
    any(strcmpi(string(c.voltage_forming_modes),'gfm'));
end

% =========================================================================
function mode = runtime_mode(dev,hs)
if isfield(dev,'initial_mode') && ~isempty(dev.initial_mode)
    mode = char(dev.initial_mode);
elseif isfield(dev,'mode') && ~isempty(dev.mode)
    mode = char(dev.mode);
else
    mode = '';
end
key = matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
if isstruct(hs) && isfield(hs,'device_modes') && isfield(hs.device_modes,key)
    mode = char(hs.device_modes.(key));
end
end

% =========================================================================
function [hs,reason] = validate_hybrid_snapshot(value,devices)
hs = value;
reason = '';
if ~isstruct(value) || ~isscalar(value) || ...
        ~isfield(value,'device_online') || ~isstruct(value.device_online) || ...
        ~isfield(value,'device_modes') || ~isstruct(value.device_modes)
    reason = 'config.hybrid_state must be a scalar snapshot with device_online/device_modes structs.';
    return;
end
for k = 1:numel(devices)
    key = matlab.lang.makeValidName(char(devices(k).device_id), ...
        'ReplacementStyle','underscore');
    if ~isfield(value.device_online,key) || ...
            ~islogical(value.device_online.(key)) || ...
            ~isscalar(value.device_online.(key))
        reason = sprintf('Hybrid snapshot has no valid logical online flag for device %s.', ...
            devices(k).device_id);
        return;
    end
    if ~isfield(value.device_modes,key) || ...
            ~(ischar(value.device_modes.(key)) || ...
            (isstring(value.device_modes.(key)) && isscalar(value.device_modes.(key))))
        reason = sprintf('Hybrid snapshot has no valid mode for device %s.', ...
            devices(k).device_id);
        return;
    end
end
end

% =========================================================================
function devices = apply_context_to_devices(devices,hs)
for k = 1:numel(devices)
    key = matlab.lang.makeValidName(char(devices(k).device_id), ...
        'ReplacementStyle','underscore');
    if isfield(hs,'device_modes') && isfield(hs.device_modes,key)
        devices(k).mode = lower(char(hs.device_modes.(key)));
        devices(k).initial_mode = char(hs.device_modes.(key));
    end
    if isfield(hs,'device_online') && isfield(hs.device_online,key)
        devices(k).initial_online = logical(hs.device_online.(key));
    end
end
end

% =========================================================================
function [idx,reason] = validate_local_indices(idx,nx,device_id)
reason = '';
idx = idx(:)';
if any(~isfinite(idx)) || any(idx~=fix(idx)) || any(idx<1) || any(idx>nx) || ...
        numel(unique(idx))~=numel(idx)
    reason = sprintf( ...
        'Device %s active-state indices must be unique finite integers in 1:%d.', ...
        device_id,nx);
end
end

% =========================================================================
function [kcl_rect,Ibus] = physical_kcl_residual(dae,x,y,u,eq_context)
V = y(1:2:end) + 1i*y(2:2:end);
Ibus = zeros(dae.nb,1);
for k = 1:numel(dae.devices)
    dev = dae.devices(k);
    xr = dae.device_offsets(k)+1 : dae.device_offsets(k)+dev.nx;
    if dev.nu == 0
        u_dev = [];
    else
        ur = dae.u_offsets(k)+1 : dae.u_offsets(k)+dev.nu;
        u_dev = u(ur);
    end
    I = dev.current_injection(0,x(xr),y,u_dev,eq_context);
    if ~isscalar(I) || ~isfinite(I)
        error('mixed_equilibrium_solve:nonFiniteInjection', ...
            'Device %s returned a non-finite current.',dev.device_id);
    end
    Ibus(dae.bus_map(k)) = Ibus(dae.bus_map(k)) + I;
end
gc = dae.Ynet*V-Ibus;
kcl_rect = zeros(2*dae.nb,1);
kcl_rect(1:2:end) = real(gc);
kcl_rect(2:2:end) = imag(gc);
end

% =========================================================================
function [ok,reason] = check_reference_p_limit(case_data,dev,P_MW)
ok = isfinite(P_MW);
reason = '';
if ~ok
    reason = sprintf('Reference %s solved a non-finite active power.',dev.device_id);
    return;
end
pmax = NaN;
if isfield(case_data,'dispatch_contract') && ...
        isfield(case_data.dispatch_contract,'pmax_MW') && ...
        isfield(case_data.dispatch_contract.pmax_MW,dev.device_id)
    pmax = case_data.dispatch_contract.pmax_MW.(dev.device_id);
end
p_scale = max(1.0,abs(P_MW));
if isfinite(pmax), p_scale = max(p_scale,abs(pmax)); end
p_tol = 64*eps(p_scale);
if P_MW < -p_tol
    ok = false;
    reason = sprintf('Reference %s solved P=%.6g MW < 0.',dev.device_id,P_MW);
    return;
end
if isfinite(pmax)
    if P_MW > pmax + p_tol
        ok = false;
        reason = sprintf('Reference %s solved P=%.6g MW > Pmax=%.6g MW.', ...
            dev.device_id,P_MW,pmax);
    end
end
end

% =========================================================================
function lc = check_limits(x, y, u_eq, case_data, dae, eq_context, Ibus)
lc = struct('devices', struct());
nb = dae.nb;
V = zeros(nb, 1);
for b = 1:nb
    V(b) = y(2*b-1) + 1i*y(2*b);
end
for k = 1:numel(dae.devices)
    dev = dae.devices(k);
    xr = dae.device_offsets(k)+1 : dae.device_offsets(k)+dev.nx;
    x_dev = x(xr);
    % Slice the exact solved equilibrium input; never silently rebuild u0.
    if dev.nu == 0
        u_dev = [];
    else
        ur = dae.u_offsets(k)+1 : dae.u_offsets(k)+dev.nu;
        u_dev = u_eq(ur);
    end
    Iinj = dev.current_injection(0, x_dev, y, u_dev, eq_context);
    Vbus = V(dae.bus_map(k));
    S = Vbus * conj(Iinj);
    P = real(S) * case_data.mpc.baseMVA;
    Q = imag(S) * case_data.mpc.baseMVA;
    Imax = abs(Iinj);
    % Reconstruct limiter metadata if available.
    rec = dev.reconstruct(0, x_dev, y, u_dev, eq_context);
    transient_current_ok = true;
    if isstruct(rec) && isfield(rec,'ImaxF_sys') && isfinite(rec.ImaxF_sys)
        transient_current_ok = Imax <= rec.ImaxF_sys + ...
            64*eps(max(1.0,rec.ImaxF_sys));
    end
    active_power_ok = true;
    if isfield(case_data,'dispatch_contract') && ...
            isfield(case_data.dispatch_contract,'pmax_MW') && ...
            isfield(case_data.dispatch_contract.pmax_MW,dev.device_id)
        pmax = case_data.dispatch_contract.pmax_MW.(dev.device_id);
        p_tol = 64*eps(max([1.0,abs(P),abs(pmax)]));
        active_power_ok = P >= -p_tol && P <= pmax + p_tol;
    end
    lc.devices.(dev.device_id) = struct( ...
        'P_MW', P, 'Q_MVAr', Q, 'I_pu', Imax, 'Vbus_pu', abs(Vbus), ...
        'within_transient_current_limit',transient_current_ok, ...
        'within_active_power_limit',active_power_ok, ...
        'within_limits', all(isfinite([P,Q,Imax,abs(Vbus)])) && ...
            transient_current_ok && active_power_ok, ...
        'reconstruct', rec);
end

% Boundary-consistent terminal balance. Ynet contains load admittance and
% network elements, so V*conj(YV) is total network absorption. Never label a
% KCL residual as load or losses.
S_device = sum(V .* conj(Ibus));
S_network = sum(V .* conj(dae.Ynet*V));
lc.power_balance = struct( ...
    'device_terminal_injection_pu',S_device, ...
    'network_absorption_pu',S_network, ...
    'complex_mismatch_pu',S_device-S_network, ...
    'mismatch_norm_pu',abs(S_device-S_network), ...
    'baseMVA',case_data.mpc.baseMVA);
end

% =========================================================================
function fp = compute_fingerprint(x, y, u, config)
fp.config_hash = config_hash(config);
fp.x0_hash = sprintf('%.15e', x(:)');
fp.y0_hash = sprintf('%.15e', y(:)');
fp.u_eq_hash = sprintf('%.15e',u(:)');
end

% =========================================================================
function h = config_hash(config)
h = 'modes=';
if isfield(config, 'device_modes')
    for k = 1:numel(config.device_modes)
        h = [h config.device_modes(k).device_id ':' config.device_modes(k).mode ';']; %#ok<AGROW>
    end
end
if isfield(config, 'devices') && ~isempty(config.devices)
    h = [h '|devs='];
    for k = 1:numel(config.devices)
        h = [h config.devices(k).device_id ':'];
        if isfield(config.devices(k), 'mode')
            h = [h config.devices(k).mode]; %#ok<AGROW>
        end
        h = [h ';']; %#ok<AGROW>
    end
end
if isfield(config,'selected_gfm_indices')
    h = [h '|selected=' sprintf('%d,',config.selected_gfm_indices)]; %#ok<AGROW>
end
if isfield(config,'n_gfm_required')
    h = [h '|n=' num2str(config.n_gfm_required)]; %#ok<AGROW>
end
if isfield(config,'reference_resource_index')
    h = [h '|ref=' num2str(config.reference_resource_index)]; %#ok<AGROW>
end
end
