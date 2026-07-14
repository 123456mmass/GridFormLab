function [hybrid_state, event_log] = sg_event_handler(hybrid_state, event, devices, topology)
%SG_EVENT_HANDLER  Atomic SG trip and explicitly committed GFM selection.
%   A sg_trip_request must carry event.committed_selection with:
%     selected_gfm_indices, n_gfm_required, reference_resource_index.
%   The indices refer to DEVICES order. The complete trip and mode-selection
%   transaction is validated before any hybrid-state field is mutated.
%
%   On success, exactly the selected eligible IBRs are placed in GFM mode and
%   every other eligible dual-mode IBR is placed in GFL mode. The committed
%   reference index must be a selected GFM member. Invalid events fail closed:
%   the returned HYBRID_STATE is isequaln to the input state.
%
%   This handler commits discrete metadata only. The TS event driver remains
%   responsible for the single right-limit algebraic solve after the atomic
%   transaction; no left-state algebraic value is reused as a right-limit result.
%
%   Classification: index-selected transaction and rollback are PROJECT_DERIVED.

arguments
    hybrid_state struct
    event struct
    devices struct
    topology struct = struct()
end

event_type = '';
timestamp = NaN;
if isfield(event, 'type') && (ischar(event.type) || isstring(event.type))
    event_type = char(event.type);
end
if isfield(event, 't') && isnumeric(event.t) && isscalar(event.t)
    timestamp = event.t;
end
event_log = new_log(event_type, timestamp);

switch event_type
    case 'sg_trip_request'
        [hybrid_state, event_log] = process_sg_trip( ...
            hybrid_state, event, devices, event_log);
    case 'sg_reclose_request'
        [hybrid_state, event_log] = process_sg_reclose( ...
            hybrid_state, event, devices, event_log);
    otherwise
        event_log.failure_id = 'stability:sg_event_handler:unknownEventType';
        event_log.details = sprintf('Unknown SG event type: %s', event_type);
end

% TOPOLOGY is intentionally not interpreted here. No generic topology/island
% schema is established for this handler; the right-limit driver owns topology.
if ~isempty(fieldnames(topology))
    event_log.topology_deferred_to_right_limit_driver = true;
end
end

% =========================================================================
function [hs, log] = process_sg_trip(hs, event, devices, log)
original = hs;
[transaction, ok, failure_id, details] = validate_trip_transaction( ...
    original, event, devices);
if ~ok
    hs = original;
    log.failure_id = failure_id;
    log.details = details;
    return;
end

next = original;
for i = 1:numel(transaction.sg_indices)
    idx = transaction.sg_indices(i);
    key = transaction.device_keys{idx};
    next.device_online.(key) = false;
    next.device_modes.(key) = 'breaker_open';
end
for i = 1:numel(transaction.eligible_gfm_indices)
    idx = transaction.eligible_gfm_indices(i);
    key = transaction.device_keys{idx};
    if ismember(idx, transaction.selected_gfm_indices)
        next.device_modes.(key) = 'GFM';
    else
        next.device_modes.(key) = 'gfl';
    end
end

committed = struct( ...
    'selected_gfm_indices', transaction.selected_gfm_indices, ...
    'n_gfm_required', transaction.n_gfm_required, ...
    'reference_resource_index', transaction.reference_resource_index);
next.committed_selection = committed;
next.selected_gfm_indices = transaction.selected_gfm_indices;
next.n_gfm_required = transaction.n_gfm_required;
next.reference_resource_index = transaction.reference_resource_index;
next.active_configuration_id = sprintf('gfm_indices_%s', ...
    strjoin(string(transaction.selected_gfm_indices), '_'));
if ~isfield(next, 'selector_table_version') || ...
        ~isnumeric(next.selector_table_version) || ...
        ~isscalar(next.selector_table_version) || ...
        ~isfinite(next.selector_table_version)
    next.selector_table_version = 0;
end
next.selector_table_version = next.selector_table_version + 1;
next.selector_fingerprint = sprintf('event_commit|n=%d|selected=%s|ref=%d', ...
    transaction.n_gfm_required, ...
    strjoin(string(transaction.selected_gfm_indices), ','), ...
    transaction.reference_resource_index);

hs = next;
log.applied = true;
log.failure_id = '';
log.details = sprintf('Tripped %d SG(s); committed %d explicitly selected GFM resource(s).', ...
    numel(transaction.sg_indices), transaction.n_gfm_required);
log.selected_gfm_indices = transaction.selected_gfm_indices;
log.n_gfm_required = transaction.n_gfm_required;
log.reference_resource_index = transaction.reference_resource_index;
log.right_limit_required = true;
end

% =========================================================================
function [tx, ok, failure_id, details] = validate_trip_transaction(hs, event, devices)
tx = struct();
ok = false;
failure_id = '';
details = '';

if ~isfield(event, 't') || ~isnumeric(event.t) || ~isscalar(event.t) || ...
        ~isfinite(event.t)
    failure_id = 'stability:sg_event_handler:badEventTime';
    details = 'Trip event time must be a finite scalar.';
    return;
end
if isempty(devices) || ~isfield(devices, 'device_id')
    failure_id = 'stability:sg_event_handler:badDevices';
    details = 'Devices must be a nonempty indexed struct array with device_id.';
    return;
end

nd = numel(devices);
device_ids = cell(1, nd);
device_keys = cell(1, nd);
for k = 1:nd
    if ~(ischar(devices(k).device_id) || isstring(devices(k).device_id)) || ...
            strlength(string(devices(k).device_id)) == 0
        failure_id = 'stability:sg_event_handler:badDeviceId';
        details = sprintf('Device index %d has an invalid device_id.', k);
        return;
    end
    device_ids{k} = char(devices(k).device_id);
    device_keys{k} = matlab.lang.makeValidName(device_ids{k}, ...
        'ReplacementStyle', 'underscore');
end
if numel(unique(device_ids)) ~= nd || numel(unique(device_keys)) ~= nd
    failure_id = 'stability:sg_event_handler:deviceIdCollision';
    details = 'Device IDs or their hybrid-state keys are not unique.';
    return;
end
if ~isfield(hs, 'device_online') || ~isstruct(hs.device_online) || ...
        ~isfield(hs, 'device_modes') || ~isstruct(hs.device_modes)
    failure_id = 'stability:sg_event_handler:badHybridState';
    details = 'Hybrid state lacks device_online or device_modes.';
    return;
end
for k = 1:nd
    key = device_keys{k};
    if ~isfield(hs.device_online, key) || ...
            ~isscalar(hs.device_online.(key)) || ...
            ~islogical(hs.device_online.(key)) || ...
            ~isfield(hs.device_modes, key)
        failure_id = 'stability:sg_event_handler:hybridDeviceDrift';
        details = sprintf('Hybrid-state mapping is missing or invalid at device index %d.', k);
        return;
    end
end

if ~isfield(event, 'sg_ids')
    failure_id = 'stability:sg_event_handler:missingSgIds';
    details = 'Trip event lacks sg_ids.';
    return;
end
[sg_ids, valid_ids] = normalize_ids(event.sg_ids);
if ~valid_ids || isempty(sg_ids) || numel(unique(sg_ids)) ~= numel(sg_ids)
    failure_id = 'stability:sg_event_handler:badSgIds';
    details = 'sg_ids must be a nonempty list of unique device IDs.';
    return;
end
sg_indices = zeros(1, numel(sg_ids));
for i = 1:numel(sg_ids)
    matches = find(strcmp(device_ids, sg_ids{i}));
    if numel(matches) ~= 1
        failure_id = 'stability:sg_event_handler:unknownSgId';
        details = sprintf('SG ID %s does not map to exactly one device.', sg_ids{i});
        return;
    end
    idx = matches;
    if ~is_sg_device(devices(idx)) || ~can_switch_online(devices(idx))
        failure_id = 'stability:sg_event_handler:badSgCapability';
        details = sprintf('Device index %d is not a trippable SG.', idx);
        return;
    end
    key = device_keys{idx};
    if ~hs.device_online.(key)
        failure_id = 'stability:sg_event_handler:sgAlreadyOffline';
        details = sprintf('SG device index %d is already offline.', idx);
        return;
    end
    sg_indices(i) = idx;
end

if ~isfield(event, 'committed_selection') || ...
        ~isstruct(event.committed_selection) || ...
        ~isscalar(event.committed_selection)
    failure_id = 'stability:sg_event_handler:missingCommittedSelection';
    details = 'Trip event must carry one committed_selection struct.';
    return;
end
selection = event.committed_selection;
required = {'selected_gfm_indices','n_gfm_required','reference_resource_index'};
for i = 1:numel(required)
    if ~isfield(selection, required{i})
        failure_id = 'stability:sg_event_handler:incompleteCommittedSelection';
        details = sprintf('committed_selection lacks %s.', required{i});
        return;
    end
end

selected = selection.selected_gfm_indices;
n_required = selection.n_gfm_required;
reference_index = selection.reference_resource_index;
if ~isnumeric(selected) || isempty(selected) || any(~isfinite(selected(:))) || ...
        any(selected(:) ~= fix(selected(:))) || ...
        any(selected(:) < 1 | selected(:) > nd)
    failure_id = 'stability:sg_event_handler:badSelectedIndices';
    details = 'selected_gfm_indices must contain finite in-range integer indices.';
    return;
end
selected = reshape(selected, 1, []);
if numel(unique(selected)) ~= numel(selected)
    failure_id = 'stability:sg_event_handler:duplicateSelectedIndices';
    details = 'selected_gfm_indices contains duplicates.';
    return;
end
if ~is_scalar_integer(n_required) || n_required < 1 || ...
        numel(selected) ~= n_required
    failure_id = 'stability:sg_event_handler:selectionCountMismatch';
    details = 'n_gfm_required must equal the positive selected index count.';
    return;
end
if ~is_scalar_integer(reference_index) || ...
        ~ismember(reference_index, selected)
    failure_id = 'stability:sg_event_handler:referenceNotSelected';
    details = 'reference_resource_index must be exactly one selected GFM member.';
    return;
end

eligible = false(1, nd);
for k = 1:nd
    key = device_keys{k};
    eligible(k) = hs.device_online.(key) && is_dual_mode_gfm_device(devices(k));
end
eligible_indices = find(eligible);
if any(~ismember(selected, eligible_indices))
    failure_id = 'stability:sg_event_handler:selectedResourceIneligible';
    details = 'Every selected resource must be online and GFL/GFM-capable.';
    return;
end

for i = 1:numel(eligible_indices)
    idx = eligible_indices(i);
    key = device_keys{idx};
    current_mode = char(hs.device_modes.(key));
    if ismember(idx, selected)
        desired_mode = 'gfm';
    else
        desired_mode = 'gfl';
    end
    if ~strcmpi(current_mode, desired_mode) && ...
            transition_blocked(hs, key, event.t)
        failure_id = 'stability:sg_event_handler:modeTransitionBlocked';
        details = sprintf('Device index %d is held or locked against the committed mode change.', idx);
        return;
    end
end

tx.device_keys = device_keys;
tx.sg_indices = sg_indices;
tx.eligible_gfm_indices = eligible_indices;
tx.selected_gfm_indices = selected;
tx.n_gfm_required = n_required;
tx.reference_resource_index = reference_index;
ok = true;
end

% =========================================================================
function [hs, log] = process_sg_reclose(hs, event, devices, log)
original = hs;
if ~isfield(event, 't') || ~isnumeric(event.t) || ~isscalar(event.t) || ...
        ~isfinite(event.t) || ~isfield(event, 'sg_id') || ...
        ~(ischar(event.sg_id) || isstring(event.sg_id))
    log.failure_id = 'stability:sg_event_handler:badRecloseRequest';
    log.details = 'Reclose request requires finite t and scalar sg_id.';
    return;
end
ids = arrayfun(@(d) char(d.device_id), devices, 'UniformOutput', false);
idx = find(strcmp(ids, char(event.sg_id)));
if numel(idx) ~= 1 || ~is_sg_device(devices(idx)) || ...
        ~can_switch_online(devices(idx))
    log.failure_id = 'stability:sg_event_handler:badRecloseSg';
    log.details = 'Reclose target is not one uniquely mapped, switchable SG.';
    return;
end
key = matlab.lang.makeValidName(ids{idx}, 'ReplacementStyle', 'underscore');
if ~isfield(original, 'device_online') || ~isfield(original.device_online, key) || ...
        ~isfield(original, 'device_modes') || ~isfield(original.device_modes, key)
    log.failure_id = 'stability:sg_event_handler:hybridDeviceDrift';
    log.details = 'Reclose target is absent from hybrid state.';
    return;
end
if original.device_online.(key)
    log.failure_id = 'stability:sg_event_handler:sgAlreadyOnline';
    log.details = sprintf('SG %s already online.', ids{idx});
    return;
end
if transition_blocked(original, key, event.t)
    log.failure_id = 'stability:sg_event_handler:recloseBlocked';
    log.details = sprintf('SG %s is held or locked.', ids{idx});
    return;
end
next = original;
next.device_online.(key) = true;
next.device_modes.(key) = 'synchronous';
hs = next;
log.applied = true;
log.failure_id = '';
log.details = sprintf('SG %s reclosed at t=%.3f.', ids{idx}, event.t);
log.right_limit_required = true;
end

% =========================================================================
function log = new_log(event_type, timestamp)
log = struct('event_type', event_type, 'timestamp', timestamp, ...
    'applied', false, 'failure_id', '', 'details', '', ...
    'selected_gfm_indices', [], 'n_gfm_required', [], ...
    'reference_resource_index', [], 'right_limit_required', false, ...
    'topology_deferred_to_right_limit_driver', false);
end

function [ids, ok] = normalize_ids(value)
ok = true;
if ischar(value)
    ids = {value};
elseif isstring(value)
    if any(ismissing(value))
        ids = {};
        ok = false;
        return;
    end
    ids = cellstr(value(:).');
elseif iscell(value)
    ids = cell(size(value));
    for k = 1:numel(value)
        if ~(ischar(value{k}) || (isstring(value{k}) && isscalar(value{k}) && ...
                ~ismissing(value{k})))
            ids = {};
            ok = false;
            return;
        end
        ids{k} = char(value{k});
    end
    ids = reshape(ids, 1, []);
else
    ids = {};
    ok = false;
end
if ok && any(cellfun(@isempty, ids))
    ok = false;
end
end

function tf = is_sg_device(device)
tf = false;
if isfield(device, 'capabilities') && isstruct(device.capabilities) && ...
        isfield(device.capabilities, 'resource_type')
    tf = strcmpi(char(device.capabilities.resource_type), 'sg');
elseif isfield(device, 'device_type')
    tf = strcmpi(char(device.device_type), 'sg');
end
end

function tf = can_switch_online(device)
tf = isfield(device, 'capabilities') && isstruct(device.capabilities) && ...
    isfield(device.capabilities, 'can_switch_online') && ...
    islogical(device.capabilities.can_switch_online) && ...
    isscalar(device.capabilities.can_switch_online) && ...
    device.capabilities.can_switch_online;
end

function tf = is_dual_mode_gfm_device(device)
tf = false;
if ~isfield(device, 'capabilities') || ~isstruct(device.capabilities)
    return;
end
c = device.capabilities;
needed = {'resource_type','can_switch_mode','supported_modes','voltage_forming_modes'};
if ~all(isfield(c, needed)) || ~strcmpi(char(c.resource_type), 'ibr') || ...
        ~islogical(c.can_switch_mode) || ~isscalar(c.can_switch_mode) || ...
        ~c.can_switch_mode
    return;
end
tf = any(strcmpi(string(c.supported_modes), 'gfl')) && ...
    any(strcmpi(string(c.supported_modes), 'gfm')) && ...
    any(strcmpi(string(c.voltage_forming_modes), 'gfm'));
end

function blocked = transition_blocked(hs, key, timestamp)
blocked = false;
if isfield(hs, 'hold_timers') && isstruct(hs.hold_timers) && ...
        isfield(hs.hold_timers, key)
    value = hs.hold_timers.(key);
    blocked = blocked || (isnumeric(value) && isscalar(value) && ...
        isfinite(value) && value > 0);
end
if isfield(hs, 'lockouts') && isstruct(hs.lockouts) && ...
        isfield(hs.lockouts, key)
    value = hs.lockouts.(key);
    blocked = blocked || (isnumeric(value) && isscalar(value) && ...
        isfinite(value) && value > timestamp);
end
end

function tf = is_scalar_integer(value)
tf = isnumeric(value) && isscalar(value) && isfinite(value) && value == fix(value);
end
