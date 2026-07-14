function [resources, schema] = resource_table(case_data, resource_spec, scenario_opt)
%RESOURCE_TABLE  Build + validate the serializable indexed resource table.
%   [RESOURCES, SCHEMA] = resource_table(CASE_DATA, RESOURCE_SPEC, SCENARIO_OPT)
%   returns a validated resource table (one entry per physical resource) plus
%   the uniform device-struct schema contract used by build_mixed_resource_devices.
%
%   This is the SINGLE source of truth for the generic engine's resource index.
%   Every selector / equilibrium / transfer / event decision derives indices
%   from this table — NEVER from bus IDs or device names baked into the engine.
%   IEEE14-specific resource IDs and buses live only inside an IEEE14 scenario
%   profile (+cases/scenario_ieee14_1sg_4ibr.m), which supplies RESOURCE_SPEC.
%
%   RESOURCE_SPEC is a struct array (or cell->struct) with one entry per
%   declared physical resource. Each entry carries the Layer-1 contract:
%     resource_id        - unique string ID (e.g. "SG1", "IBR2")
%     bus_id             - external network bus ID (network mapping ONLY;
%                          never used as selector identity)
%     resource_type      - "sg" | "ibr"
%     model_id           - device factory key: "sg_emf6" | "regfm_b1_dual" |
%                          future single-mode factory keys
%     supported_modes    - string vector the resource may take:
%                          sg:   ["synchronous","breaker_open"]
%                          ibr:  subset of ["gfl","gfm","tripped"]
%     voltage_forming_modes - string vector of supported modes that FORM voltage
%                          (sg "synchronous" is voltage-forming; ibr "gfm" is)
%     initial_mode      - one of supported_modes (committed at t0)
%     initial_online    - logical (committed at t0)
%     can_switch_mode   - logical (may change mode at runtime)
%     can_switch_online - logical (may trip/reclose at runtime)
%     has_current_limiter - logical (IBR only; SG has no inverter limiter)
%     has_frt           - logical (IBR only)
%     can_black_start   - logical
%     limits            - struct (ImaxSS/ImaxF/Pmax/Qmax/Emax/Emin, per model)
%     ratings           - struct (Mbase, Sbase)
%     dynamic_params    - struct (model_id-dependent; e.g. IBR REGFM_B1 params)
%     provenance        - struct with UNIFORM field names:
%                          model, source, classification, details
%                          (model-specific prose goes in `details`, a string, so
%                          SG and IBR provenance struct-array stack cleanly)
%
%   SCENARIO_OPT (optional) may override initial_mode/initial_online per
%   resource_id (runtime choices — case_data is NEVER mutated). When absent,
%   initial values come from RESOURCE_SPEC.
%
%   SCHEMA is the uniform device-struct schema contract emitted by every
%   factory, as a struct with field names (for documentation/validation):
%     REQUIRED (consumed by composite_dae):
%       name, device_id, bus_id, bus_position, bus_ids, nx, nu,
%       state_names, input_names, x0, u0, f, current_injection,
%       electrical_power, reconstruct
%     ENGINE (capability + identity for selector/hybrid_state):
%       device_type, mode, initial_mode, initial_online, capabilities,
%       provenance (uniform: model, source, classification, details)
%
%   STATUS: STRUCTURAL_ONLY (Phase B0 foundation). No production-readiness claim.
%
%   Source: plan agent-a-atomic-lagoon.md (Layer 1 generic engine contract).

arguments
    case_data struct
    resource_spec struct
    scenario_opt struct = struct()
end

% --- Normalize resource_spec into a struct array ----------------------------
if isstruct(resource_spec) && isscalar(resource_spec) && ...
        ~isfield(resource_spec, 'resource_id')
    % Caller passed a single scalar struct that is itself an array container —
    % uncommon; treat empty as zero resources.
    resources = repmat(empty_resource(), 0, 1);
elseif isstruct(resource_spec)
    resources = resource_spec(:).';
    if isempty(resources)
        resources = repmat(empty_resource(), 0, 1);
    end
else
    error('stability:resource_table:badSpec', ...
        'resource_spec must be a struct array.');
end

nr = numel(resources);

% --- Validate + freeze each entry against the contract ----------------------
required_fields = {'resource_id','bus_id','resource_type','model_id', ...
    'supported_modes','voltage_forming_modes','initial_mode','initial_online', ...
    'can_switch_mode','can_switch_online','has_current_limiter','has_frt', ...
    'can_black_start','limits','ratings','dynamic_params','provenance'};
ids = cell(nr,1);
for k = 1:nr
    r = resources(k);
    for f = 1:numel(required_fields)
        if ~isfield(r, required_fields{f})
            error('stability:resource_table:missingField', ...
                'Resource entry %d missing required field "%s".', k, required_fields{f});
        end
    end
    % resource_id: non-empty unique string.
    if ~ischar(r.resource_id) && ~isstring(r.resource_id)
        error('stability:resource_table:badId', ...
            'Resource %d resource_id must be a string/char.', k);
    end
    rid = char(r.resource_id);
    if isempty(rid)
        error('stability:resource_table:emptyId', ...
            'Resource %d resource_id is empty.', k);
    end
    if any(strcmp(ids, rid))
        error('stability:resource_table:dupId', ...
            'Duplicate resource_id "%s" (entry %d).', rid, k);
    end
    ids{k} = rid;
    resources(k).resource_id = rid;   % freeze as char
    % resource_type in {"sg","ibr"}.
    rt = lower(char(r.resource_type));
    if ~ismember(rt, ["sg","ibr"])
        error('stability:resource_table:badType', ...
            'Resource "%s" resource_type must be "sg" or "ibr" (got "%s").', ...
            rid, rt);
    end
    resources(k).resource_type = rt;
    % model_id non-empty.
    mid = char(r.model_id);
    if isempty(mid)
        error('stability:resource_table:emptyModelId', ...
            'Resource "%s" model_id is empty.', rid);
    end
    resources(k).model_id = mid;
    % supported_modes: string vector, non-empty.
    sm = string(r.supported_modes);
    if isempty(sm)
        error('stability:resource_table:emptyModes', ...
            'Resource "%s" supported_modes is empty.', rid);
    end
    resources(k).supported_modes = sm;
    % initial_mode must be a supported mode.
    im = char(r.initial_mode);
    if ~any(string(im) == sm)
        error('stability:resource_table:badInitialMode', ...
            'Resource "%s" initial_mode "%s" not in supported_modes [%s].', ...
            rid, im, strjoin(sm,','));
    end
    resources(k).initial_mode = im;
    % voltage_forming_modes must be a subset of supported_modes.
    vfm = string(r.voltage_forming_modes);
    if ~all(ismember(vfm, sm))
        error('stability:resource_table:badVfModes', ...
            'Resource "%s" voltage_forming_modes not a subset of supported_modes.', rid);
    end
    resources(k).voltage_forming_modes = vfm;
    % bus_id finite scalar.
    if ~isscalar(r.bus_id) || ~isfinite(r.bus_id)
        error('stability:resource_table:badBusId', ...
            'Resource "%s" bus_id must be a finite scalar.', rid);
    end
    % Logical capability flags -> scalar logical.
    for lf = {'initial_online','can_switch_mode','can_switch_online', ...
               'has_current_limiter','has_frt','can_black_start'}
        v = r.(lf{1});
        if ~isscalar(v) || ~islogical(v)
            error('stability:resource_table:badFlag', ...
                'Resource "%s" %s must be a scalar logical.', rid, lf{1});
        end
        resources(k).(lf{1}) = logical(v);
    end
    % Consistency: SG resources cannot have current_limiter/frt (inverter-only).
    if strcmp(rt, "sg") && (r.has_current_limiter || r.has_frt)
        error('stability:resource_table:sgIbrFlag', ...
            'Resource "%s" is type sg but has inverter-only flags set.', rid);
    end
    % Uniform provenance: {model, source, classification, details}.
    p = r.provenance;
    if ~isstruct(p) || ~isfield(p,'model') || ~isfield(p,'source') || ...
            ~isfield(p,'classification') || ~isfield(p,'details')
        error('stability:resource_table:badProvenance', ...
            'Resource "%s" provenance must have uniform fields: model, source, classification, details.', rid);
    end
    resources(k).provenance = struct( ...
        'model', char(p.model), ...
        'source', char(p.source), ...
        'classification', char(p.classification), ...
        'details', char(p.details));
end

% --- Apply runtime scenario_opt overrides (initial_mode / initial_online) ----
% case_data is NEVER mutated. Overrides are applied to the returned table copy.
if ~isempty(scenario_opt)
    override_ids = {};
    if isfield(scenario_opt,'initial_modes') && ~isempty(scenario_opt.initial_modes)
        om = scenario_opt.initial_modes;
        for j = 1:numel(om)
            did = char(om(j).device_id);
            m = lower(char(om(j).mode));
            idx = find(strcmp(ids, did), 1);
            if isempty(idx)
                error('stability:resource_table:unknownOverrideId', ...
                    'scenario_opt.initial_modes references unknown resource "%s".', did);
            end
            if ~any(string(m) == resources(idx).supported_modes)
                error('stability:resource_table:overrideBadMode', ...
                    'Override mode "%s" for "%s" not in supported_modes.', m, did);
            end
            resources(idx).initial_mode = m;
            override_ids{end+1} = did; %#ok<AGROW>
        end
    end
    if isfield(scenario_opt,'initial_online') && ~isempty(scenario_opt.initial_online)
        oo = scenario_opt.initial_online;
        for j = 1:numel(oo)
            did = char(oo(j).device_id);
            on = logical(oo(j).online);
            idx = find(strcmp(ids, did), 1);
            if isempty(idx)
                error('stability:resource_table:unknownOverrideOnline', ...
                    'scenario_opt.initial_online references unknown resource "%s".', did);
            end
            resources(idx).initial_online = on;
        end
    end
end

% --- Emit the uniform device-struct schema contract -------------------------
schema = struct();
schema.required_fields = {'name','device_id','bus_id','bus_position','bus_ids', ...
    'nx','nu','state_names','input_names','x0','u0','f','current_injection', ...
    'electrical_power','reconstruct'};
schema.engine_fields = {'device_type','mode','initial_mode','initial_online', ...
    'capabilities','provenance'};
schema.provenance_fields = {'model','source','classification','details'};
schema.capability_fields = {'resource_type','supported_modes', ...
    'voltage_forming_modes','can_switch_mode','can_switch_online', ...
    'has_current_limiter','has_frt','can_black_start'};
schema.note = ['Uniform across SG and IBR so struct-array stacking is clean ' ...
    '(fixes the Phase B provenance-mismatch singular-Jacobian root cause).'];

end

% =========================================================================
function r = empty_resource()
r = struct('resource_id','','bus_id',0,'resource_type','','model_id','', ...
    'supported_modes',string(''),'voltage_forming_modes',string(''), ...
    'initial_mode','','initial_online',false,'can_switch_mode',false, ...
    'can_switch_online',false,'has_current_limiter',false,'has_frt',false, ...
    'can_black_start',false,'limits',struct(),'ratings',struct(), ...
    'dynamic_params',struct(),'provenance',struct('model','','source','', ...
    'classification','','details',''));
end
