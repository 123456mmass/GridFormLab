function [devices, dev_meta] = build_mixed_resource_devices(case_data, resources, scenario_opt)
%BUILD_MIXED_RESOURCE_DEVICES  Generic device builder from an indexed resource table.
%   [DEVICES, DEV_META] = build_mixed_resource_devices(CASE_DATA, RESOURCES,
%       SCENARIO_OPT) iterates the validated RESOURCES table (from
%   stability.resource_table) and dispatches a device factory by each
%   resource's model_id, emitting a UNIFORM device-struct schema so SG and IBR
%   devices stack cleanly into a single struct array.
%
%   This is the single generic entry point that replaces IEEE14-hard-coded
%   builders. IEEE14 IDs and buses live ONLY inside the IEEE14 scenario profile
%   that builds the RESOURCES table; the engine never sees them as literals.
%
%   Uniform device schema (every factory emits these fields):
%     REQUIRED (consumed by composite_dae):
%       name, device_id, bus_id, bus_position, bus_ids, nx, nu,
%       state_names, input_names, x0, u0, f, current_injection,
%       electrical_power, reconstruct
%     OPTIONAL (normalized on every device; [] means unsupported):
%       equilibrium_initialize(V_bus,P_terminal_pu,Q_terminal_pu,event_context)
%       active_state_indices_for_context(event_context)
%       equilibrium_constraint_specs(x_dev,y,u_dev,event_context)
%       mode_transfer_state / transfer_state / mode_transfer
%     ENGINE (capability + identity):
%       device_type, mode, initial_mode, initial_online, capabilities,
%       provenance (uniform: model, source, classification, details)
%
%   The uniform provenance (model, source, classification, details) is what
%   FIXES the Phase B singular-Jacobian root cause: previously SG devices had
%   8 provenance fields and IBR devices had 10 different fields, so struct-array
%   stacking [sg_dev, ibr_devices] corrupted fields or errored, propagating NaN
%   into the FD Jacobian. Now both emit the same 4-field provenance.
%
%   Factory dispatch (model_id -> factory):
%     "sg_emf6"        -> stability.sg_composite_device (single EMF6 machine)
%     "regfm_b1_dual"  -> ibr.dual_mode_ibr_model (20-state GFL/GFM/tripped)
%     "eecon49_dual"    -> ibr.eecon49_dual_mode_model (16-state shared-plant dual)
%     "decoupled_dual"  -> ibr.decoupled_dual_mode_model (17-state dual, decoupled
%                          GFM swing: independent droop/damping/inertia)
%   Future single-mode IBR factories are added here ONLY (no engine change).
%
%   SCENARIO_OPT may carry:
%     .initial_modes  - struct array (.device_id, .mode) overriding initial mode
%     .initial_online - struct array (.device_id, .online) overriding online
%     .dispatch       - struct with per-resource_id active-power dispatch
%                       (MW, system base), required for IBR P_ref. Reactive
%                       dispatch is case/resource owned by ratings.default_Q_MVAr;
%                       absence preserves the historical unity-PF default.
%
%   Output:
%     devices  - 1xN struct array conforming to composite_dae ABI + uniform schema
%     dev_meta - struct with bus_ids, V0_per_bus, Sbase, resource_ids, device_order
%
%   No IEEE14 bus IDs or device names appear in this function. Order is the
%   resource-table order (caller-controlled; deterministic).
%
%   Source: plan agent-a-atomic-lagoon.md (Layer 1 generic builder).

arguments
    case_data struct
    resources struct
    scenario_opt struct = struct()
end

Sbase = 100.0;   % MVA, system base (frozen across the engine)

nr = numel(resources);
if nr == 0
    error('stability:build_mixed_resource_devices:noResources', ...
        'Resource table is empty — cannot build devices.');
end

% --- Shared PF warm-start (complex V0 per bus) -----------------------------
% Run the in-house Newton PF once; every factory receives its bus's complex V0.
% This mirrors composite_dae's internal PF so device constructors initialize
% from the SAME warm-start the composite will use.
pf = pfsolver.powerflow_newton_raphson(case_data, struct('verbose',false, ...
    'plot_results',false,'max_iter',50,'tolerance',1e-10,'enforce_q_limits',true));
if ~pf.converged
    error('stability:build_mixed_resource_devices:powerFlow', ...
        'In-house Newton PF did not converge for the warm-start.');
end
bus_ids = pf.external_bus_ids(:);
V0_complex = pf.bus_voltage(:) .* exp(1i * deg2rad(pf.bus_angle_deg(:)));

% --- Dispatch factories by model_id, emit uniform schema -------------------
device_cells = cell(nr, 1);
device_order = cell(nr, 1);
for k = 1:nr
    r = resources(k);
    rid = char(r.resource_id);
    bus = r.bus_id;
    bp = find(bus_ids == bus, 1);
    if isempty(bp)
        error('stability:build_mixed_resource_devices:badBus', ...
            'Resource "%s" bus_id %d not found in network bus_ids.', rid, bus);
    end
    V0 = V0_complex(bp);
    mode = r.initial_mode;
    mid = r.model_id;
    switch mid
        case 'sg_emf6'
            dev = stability.sg_composite_device(case_data, string(rid), ...
                bus, bp, bus_ids(:)', V0, r.dynamic_params);
            % SG mode is "synchronous" in the resource vocabulary; map the
            % device.mode from the factory's 'sg' to the resource vocabulary
            % only for the engine field (factory keeps its internal mode).
            dev.mode = 'synchronous';
            dev.initial_mode = 'synchronous';
        case {'regfm_b1_dual','eecon49_dual','decoupled_dual'}
            % Dispatch + P_ref from scenario_opt.dispatch (system-base MW -> pu).
            P_ref_MW = 0.0;
            if isfield(scenario_opt,'dispatch') && isfield(scenario_opt.dispatch, rid)
                P_ref_MW = scenario_opt.dispatch.(rid);
            elseif isfield(r,'ratings') && isfield(r.ratings,'default_P_MW')
                P_ref_MW = r.ratings.default_P_MW;
            end
            P_ref_pu = P_ref_MW / Sbase;
            % Initial GFL Q is a PQ-resource schedule, not a PV-voltage
            % controller output.  Consume the case-owned value when declared;
            % legacy resources without the additive field remain unity PF.
            Q_ref_MVAr = 0.0;
            if isfield(scenario_opt,'reactive_dispatch') && ...
                    isstruct(scenario_opt.reactive_dispatch) && ...
                    isfield(scenario_opt.reactive_dispatch,rid)
                Q_ref_MVAr=scenario_opt.reactive_dispatch.(rid);
            elseif isfield(r,'ratings') && isfield(r.ratings,'default_Q_MVAr') && ...
                    ~isempty(r.ratings.default_Q_MVAr)
                Q_ref_MVAr = r.ratings.default_Q_MVAr;
            end
            if ~isnumeric(Q_ref_MVAr) || ~isscalar(Q_ref_MVAr) || ...
                    ~isfinite(Q_ref_MVAr)
                error('stability:build_mixed_resource_devices:badReactiveDispatch', ...
                    'Resource "%s" default_Q_MVAr must be one finite scalar.',rid);
            end
            Q_ref_pu = Q_ref_MVAr / Sbase;
            V_ref_pu = abs(V0);
            params = r.dynamic_params;
            if ~isfield(params,'Mbase') && isfield(r,'ratings') && isfield(r.ratings,'Mbase')
                params.Mbase = r.ratings.Mbase;
            end
            % dual_mode_ibr_model expects mode in {"gfl","GFM","tripped"}.
            ibr_mode = mode;
            if strcmp(ibr_mode, "gfm"), ibr_mode = "GFM"; end
            % Opt-in diagnostic factory override (ASSUMED_DIAGNOSTIC): when
            % scenario_opt.ibr_factory_override.(rid) declares a factory, that
            % factory builds the resource instead of the model_id dispatch.
            % Absent (the default) every production build is byte-identical.
            if isfield(scenario_opt,'ibr_factory_override') && ...
                    isstruct(scenario_opt.ibr_factory_override) && ...
                    isfield(scenario_opt.ibr_factory_override,char(rid)) && ...
                    ~isempty(scenario_opt.ibr_factory_override.(char(rid)))
                factory_fn = scenario_opt.ibr_factory_override.(char(rid));
                dev = factory_fn(string(rid), bus, bp, bus_ids(:)', ...
                    V0, params, P_ref_pu, Q_ref_pu, V_ref_pu, string(ibr_mode));
            elseif strcmp(mid,'eecon49_dual')
                dev = ibr.eecon49_dual_mode_model(string(rid), bus, bp, bus_ids(:)', ...
                    V0, params, P_ref_pu, Q_ref_pu, V_ref_pu, string(ibr_mode));
            elseif strcmp(mid,'decoupled_dual')
                dev = ibr.decoupled_dual_mode_model(string(rid), bus, bp, bus_ids(:)', ...
                    V0, params, P_ref_pu, Q_ref_pu, V_ref_pu, string(ibr_mode));
            else
                dev = ibr.dual_mode_ibr_model(string(rid), bus, bp, bus_ids(:)', ...
                    V0, params, P_ref_pu, Q_ref_pu, V_ref_pu, string(ibr_mode));
            end
            dev.mode = lower(ibr_mode);
            dev.initial_mode = lower(ibr_mode);
        otherwise
            error('stability:build_mixed_resource_devices:unknownModelId', ...
                'Resource "%s" model_id "%s" has no registered factory.', rid, mid);
    end

    % --- Normalize to uniform schema (add engine fields if absent) ---------
    if ~isfield(dev,'device_type') || isempty(dev.device_type)
        dev.device_type = r.resource_type;
    end
    if ~isfield(dev,'mode') || isempty(dev.mode)
        dev.mode = mode;
    end
    if ~isfield(dev,'initial_mode') || isempty(dev.initial_mode)
        dev.initial_mode = mode;
    end
    % Resource-table online status is authoritative. Factory defaults must not
    % silently override an explicitly offline resource.
    dev.initial_online = logical(r.initial_online);
    % Uniform capabilities struct (serializable, engine-facing).
    dev.capabilities = struct( ...
        'resource_type', r.resource_type, ...
        'supported_modes', r.supported_modes, ...
        'voltage_forming_modes', r.voltage_forming_modes, ...
        'can_switch_mode', r.can_switch_mode, ...
        'can_switch_online', r.can_switch_online, ...
        'has_current_limiter', r.has_current_limiter, ...
        'has_frt', r.has_frt, ...
        'can_black_start', r.can_black_start);
    % Uniform frozen-state metadata (SG may have frozen Edp; IBRs default empty).
    if ~isfield(dev, 'frozen_state_indices')
        dev.frozen_state_indices = [];
        dev.frozen_state_values  = [];
        dev.frozen_state_source  = '';
        dev.active_state_indices = 1:dev.nx;
        dev.frozen_state_classification = '';
    end
    % Uniform optional exact-equilibrium API. IBR factories implement it;
    % SG currently has no stationary breaker-open/device-local initializer, so
    % the empty value is an explicit unsupported marker rather than a fallback.
    if ~isfield(dev, 'equilibrium_initialize')
        dev.equilibrium_initialize = [];
    end
    % Runtime mode-dependent partition is device-owned. Dual-mode IBRs expose
    % a resolver; fixed-layout SG advertises explicit unsupported ([]).
    if ~isfield(dev, 'active_state_indices_for_context')
        dev.active_state_indices_for_context = [];
    end
    if ~isfield(dev, 'dynamic_state_indices_for_context')
        dev.dynamic_state_indices_for_context = [];
    end
    % Optional active-bound equilibrium contract.  Devices without bounded
    % controller states advertise unsupported ([]); normalizing here is
    % required because MATLAB struct-array concatenation requires identical
    % field sets across heterogeneous SG/IBR factories.
    if ~isfield(dev, 'equilibrium_constraint_specs')
        dev.equilibrium_constraint_specs = [];
    end
    % Optional physical mode-transfer ABI.  Dual-mode resources provide these
    % aliases; fixed-mode SG resources explicitly advertise unsupported so
    % heterogeneous factory structs retain an identical field set.
    transfer_fields = {'mode_transfer_state','transfer_state','mode_transfer'};
    for tf = 1:numel(transfer_fields)
        if ~isfield(dev,transfer_fields{tf})
            dev.(transfer_fields{tf}) = [];
        end
    end
    % Uniform provenance: {model, source, classification, details}.
    p = r.provenance;
    dev.provenance = struct( ...
        'model', p.model, ...
        'source', p.source, ...
        'classification', p.classification, ...
        'details', p.details);

    device_cells{k} = dev;
    device_order{k} = rid;
end

% --- Stack into a struct array (uniform schema => clean concatenation) -----
% All devices now share identical field names (required + engine + uniform
% provenance), so vertcat/direct concatenation cannot corrupt fields.
devices = vertcat(device_cells{:});

% --- Provenance metadata ---------------------------------------------------
dev_meta = struct();
dev_meta.bus_ids = bus_ids(:)';
dev_meta.V0_per_bus = V0_complex;
dev_meta.Sbase = Sbase;
dev_meta.resource_ids = device_order;
dev_meta.device_order = device_order;
dev_meta.model_ids = arrayfun(@(k) resources(k).model_id, (1:nr).', ...
    'UniformOutput', false).';
dev_meta.source = 'Generic build_mixed_resource_devices from indexed resource table';
dev_meta.no_synthetic = true;
end
