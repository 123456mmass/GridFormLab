function hybrid_state = ts_hybrid_state_init(devices)
%TS_HYBRID_STATE_INIT  Initialize the persistent hybrid state (Phase 2).
%   hybrid_state = ts_hybrid_state_init(devices) builds the driver-owned
%   hybrid_state struct from a device list. The TS driver is the SOLE
%   owner and mutator; every RHS/current/reconstruct call receives an
%   IMMUTABLE snapshot through event_context.hybrid_state.
%
%   Per user correction 2, hybrid_state holds:
%     device_modes          per-device 'gfl'|'GFM'|'tripped'|'sg' (string)
%     device_online         per-device logical (true=connected)
%     pending_commands      per-device pending mode + timing metadata
%     dwell_timers          per-guard dwell accumulator (seconds)
%     hold_timers           per-device modal hold (T_down) remaining
%     lockouts               per-device mode-switch lockout-until
%     active_configuration_id  current selector configuration label
%     selector_table_version  selector table version counter
%     selector_fingerprint    fingerprint of last selection
%
%   Multi-island reference-ownership schema (F1/C1, canonical):
%     reference_owner_indices       owner resource index per island
%     gfm_reference_resource_indices GFM numerical reference per island
%                                    (empty entry where an SG owns)
%     reference_island_ids          island ID per entry, sorted ascending
%     selected_gfm_indices          complete physical online GFM set
%                                    (independent of reference ownership)
%     selector_table_fingerprint    immutable for the run; authenticates
%                                    topology/resources/models/dispatch/
%                                    selector policy/gamma_req/cached evidence
%     committed_config_fingerprint  changes atomically after each accepted
%                                    mode/online/reference configuration
%     pre_event_input_fingerprint   immutable; authenticates pre_event_input
%
%   Legacy read-only alias:
%     reference_resource_index      scalar; single-island only. SG_OFF:
%                                    equals gfm_reference_resource_indices(1).
%                                    SG_ON: must be [] (must NOT point to SG).
%                                    multi-island: unsupported/empty.
%   Normalization/validation is owned by stability.reference_owner_schema;
%   consumers read the normalized struct and never interpret the alias alone.
%
%   devices is a struct array (or struct with .device_id field). Each
%   device MAY carry:
%     .device_id      string, unique
%     .initial_mode   string ('gfl'|'GFM'|'tripped'|'sg'), default 'gfl'
%     .initial_online logical, default true
%
%   Source: project Phase 2 design (docs/project/IEEE14_IBR_FROZEN_CONTRACT.md,
%   user correction 2). No external source for the hybrid_state structure —
%   this is a PROJECT_DERIVED contract for the IEEE14 IBR mission's
%   mode-switching supervisor. Guard thresholds/dwell VALUES must be sourced
%   (or labeled ASSUMED_DIAGNOSTIC for synthetic tests); the STATE STRUCTURE
%   itself is project infrastructure.

arguments
    devices struct
end

device_modes = struct();
device_online = struct();
if isstruct(devices) && ~isempty(devices) && isfield(devices, 'device_id')
    % struct array (1xN) of devices with .device_id field.
    for k = 1:numel(devices)
        dev = devices(k);
        mid = matlab.lang.makeValidName(char(dev.device_id), ...
            'ReplacementStyle', 'underscore');
        if isfield(dev, 'initial_mode') && ~isempty(dev.initial_mode)
            device_modes.(mid) = char(dev.initial_mode);
        else
            device_modes.(mid) = 'gfl';
        end
        if isfield(dev, 'initial_online') && ~isempty(dev.initial_online)
            device_online.(mid) = logical(dev.initial_online);
        else
            device_online.(mid) = true;
        end
    end
end

hybrid_state = struct( ...
    'device_modes', device_modes, ...
    'device_online', device_online, ...
    'pending_commands', struct(), ...
    'dwell_timers', struct(), ...
    'hold_timers', struct(), ...
    'lockouts', struct(), ...
    'active_configuration_id', '', ...
    'selector_table_version', 0, ...
    'selector_fingerprint', '', ...
    'device_frozen_anchor', struct(), ...   % per-device frozen state anchor (Phase C)
    'reference_owner_indices', [], ...      % multi-island owner per island (F1/C1)
    'gfm_reference_resource_indices', [], ...% GFM numerical ref per island (empty if SG owns)
    'reference_island_ids', [], ...          % island ID per entry, sorted ascending
    'selected_gfm_indices', [], ...          % complete physical online GFM set
    'selector_table_fingerprint', '', ...    % immutable for the run (F1)
    'committed_config_fingerprint', '', ...  % atomic per accepted config (F1)
    'pre_event_input_fingerprint', '');      % immutable; authenticates pre_event_input
end
