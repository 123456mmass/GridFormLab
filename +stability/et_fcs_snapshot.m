function snapshot = et_fcs_snapshot(state, event)
%ET_FCS_SNAPSHOT  Validate and fingerprint an accepted ET-FCSPS input state.
%   SNAPSHOT = stability.et_fcs_snapshot(STATE, EVENT) creates the immutable
%   value-struct used by every candidate trial. It accepts primitive value
%   data only; handle objects and function handles fail closed.
%
%   This function does not solve, predict, select, or mutate production state.
%   Classification: snapshot schema PROJECT_DERIVED; canonical fingerprint
%   NUMERICAL_METHOD (shared in-repo serializer).

arguments
    state struct
    event struct
end

required = {'accepted','t','x','y','topology_payload','resource_ids', ...
    'resource_types','device_modes','device_online','eligible_mask', ...
    'reference_capable','resource_island_ids','energized_island_ids', ...
    'hold_timers','lockout_until','limits','reserve'};
for k = 1:numel(required)
    require_field(state, required{k}, 'stability:et_fcs_snapshot:missingStateField');
end
require_field(event, 'event_id', 'stability:et_fcs_snapshot:missingEventField');
require_field(event, 'type', 'stability:et_fcs_snapshot:missingEventField');
require_field(event, 'authenticated', 'stability:et_fcs_snapshot:missingEventField');
require_field(event, 'local_request', 'stability:et_fcs_snapshot:missingEventField');
if ~isfield(state,'reference_owner_indices')
    error('stability:et_fcs_snapshot:missingStateField', ...
        'Required field "reference_owner_indices" is missing.');
end

if ~islogical(state.accepted) || ~isscalar(state.accepted) || ~state.accepted
    error('stability:et_fcs_snapshot:notAccepted', ...
        'ET-FCSPS snapshots must come from an accepted production state.');
end
if ~isnumeric(state.t) || ~isscalar(state.t) || ~isfinite(state.t)
    error('stability:et_fcs_snapshot:badTime', 'state.t must be a finite scalar.');
end
if ~isnumeric(state.x) || ~isnumeric(state.y) || ...
        any(~isfinite(state.x(:))) || any(~isfinite(state.y(:)))
    error('stability:et_fcs_snapshot:nonFiniteState', ...
        'Accepted differential and algebraic states must be numeric and finite.');
end
if ~isnumeric(state.topology_payload) || any(~isfinite(state.topology_payload(:)))
    error('stability:et_fcs_snapshot:badTopology', ...
        'topology_payload must be a finite project-owned numeric topology representation.');
end

ids = normalize_text_row(state.resource_ids, 'resource_ids');
types = normalize_text_row(state.resource_types, 'resource_types');
modes = normalize_text_row(state.device_modes, 'device_modes');
n = numel(ids);
if n == 0 || numel(unique(ids)) ~= n
    error('stability:et_fcs_snapshot:badResourceIds', ...
        'resource_ids must be nonempty and unique.');
end
if numel(types) ~= n || numel(modes) ~= n
    error('stability:et_fcs_snapshot:resourceAlignment', ...
        'resource_types and device_modes must align with resource_ids.');
end

online = logical_row(state.device_online, n, 'device_online');
eligible = logical_row(state.eligible_mask, n, 'eligible_mask');
refcap = logical_row(state.reference_capable, n, 'reference_capable');
island = numeric_row(state.resource_island_ids, n, 'resource_island_ids');
hold = numeric_row(state.hold_timers, n, 'hold_timers');
lockout = numeric_row(state.lockout_until, n, 'lockout_until');
if any(~isfinite(island)) || any(island ~= fix(island)) || any(island < 0)
    error('stability:et_fcs_snapshot:badIslandMap', ...
        'resource_island_ids must contain finite nonnegative integers.');
end
if any(~isfinite(hold)) || any(hold < 0) || any(isnan(lockout))
    error('stability:et_fcs_snapshot:badTimers', ...
        'hold_timers must be finite/nonnegative and lockout_until must not contain NaN.');
end

energized = reshape(state.energized_island_ids, 1, []);
if ~isnumeric(energized) || isempty(energized) || any(~isfinite(energized)) || ...
        any(energized ~= fix(energized)) || numel(unique(energized)) ~= numel(energized)
    error('stability:et_fcs_snapshot:badEnergizedIslands', ...
        'energized_island_ids must be unique finite integer IDs.');
end
if numel(energized) ~= 1
    error('stability:et_fcs_snapshot:multiIslandNotValidated', ...
        'Initial ET-FCSPS implementation is validated for one energized island only.');
end
owners = reshape(state.reference_owner_indices, 1, []);
if ~isnumeric(owners) || any(~isfinite(owners)) || any(owners ~= fix(owners)) || ...
        any(owners < 1 | owners > n)
    error('stability:et_fcs_snapshot:badReferenceOwners', ...
        'reference_owner_indices must contain valid resource indices.');
end
if ~isstruct(state.limits) || ~isscalar(state.limits) || ...
        ~isstruct(state.reserve) || ~isscalar(state.reserve)
    error('stability:et_fcs_snapshot:badContracts', ...
        'limits and reserve must be scalar structs with case/source provenance.');
end
if contains_unsupported(state.limits) || contains_unsupported(state.reserve)
    error('stability:et_fcs_snapshot:unsupportedValueType', ...
        'Snapshot contracts may not contain handles or unsupported value types.');
end

event_id = scalar_text(event.event_id, 'event_id');
event_type = scalar_text(event.type, 'type');
if ~islogical(event.authenticated) || ~isscalar(event.authenticated) || ...
        ~islogical(event.local_request) || ~isscalar(event.local_request)
    error('stability:et_fcs_snapshot:badEventFlags', ...
        'event.authenticated and event.local_request must be logical scalars.');
end

snapshot = struct();
snapshot.schema = 'et_fcs_snapshot/1.0';
snapshot.accepted = true;
snapshot.t = state.t;
snapshot.x = state.x;
snapshot.y = state.y;
snapshot.topology_payload = state.topology_payload;
snapshot.resource_ids = ids;
snapshot.resource_types = lower(types);
snapshot.device_modes = lower(modes);
snapshot.device_online = online;
if isfield(state,'decision_device_online') && ~isempty(state.decision_device_online)
    snapshot.decision_device_online = logical_row( ...
        state.decision_device_online,n,'decision_device_online');
else
    snapshot.decision_device_online = online;
end
snapshot.eligible_mask = eligible;
snapshot.reference_capable = refcap;
snapshot.resource_island_ids = island;
snapshot.energized_island_ids = energized;
snapshot.reference_owner_indices = owners;
if isfield(state,'decision_reference_owner_indices')
    decision_owners = reshape(state.decision_reference_owner_indices,1,[]);
    if ~isnumeric(decision_owners) || any(~isfinite(decision_owners)) || ...
            any(decision_owners ~= fix(decision_owners)) || ...
            any(decision_owners < 1 | decision_owners > n)
        error('stability:et_fcs_snapshot:badReferenceOwners', ...
            'decision_reference_owner_indices must contain valid resource indices.');
    end
    snapshot.decision_reference_owner_indices = decision_owners;
else
    snapshot.decision_reference_owner_indices = owners;
end
snapshot.hold_timers = hold;
snapshot.lockout_until = lockout;
snapshot.limits = state.limits;
snapshot.reserve = state.reserve;
snapshot.event = struct('event_id', event_id, 'type', event_type, ...
    'authenticated', event.authenticated, 'local_request', event.local_request);
if isfield(state, 'agsi')
    agsi = numeric_row(state.agsi, n, 'agsi');
    if any(~isfinite(agsi)) || any(agsi < 0 | agsi > 1)
        error('stability:et_fcs_snapshot:badAgsi', ...
            'Accepted bounded AGSI++ values must lie in [0,1].');
    end
    snapshot.agsi = agsi;
else
    snapshot.agsi = NaN(1, n);
end
if isfield(state,'trial_table') && ~isempty(state.trial_table)
    if ~isstruct(state.trial_table) || contains_unsupported(state.trial_table)
        error('stability:et_fcs_snapshot:badTrialTable', ...
            'trial_table must contain primitive, immutable project-owned evidence.');
    end
    snapshot.trial_table = state.trial_table;
else
    snapshot.trial_table = repmat(struct(),0,1);
end

auth = struct('base_values', snapshot, ...
    'topology_payload', snapshot.topology_payload);
[~, input_fp] = compute_selector_table_fingerprint(auth, struct());
snapshot.fingerprint = ['et_fcs_snapshot_v1:' input_fp];
end

function require_field(s, name, id)
if ~isfield(s, name) || isempty(s.(name))
    error(id, 'Required field "%s" is missing or empty.', name);
end
end

function c = normalize_text_row(v, name)
if isstring(v), v = cellstr(v); end
if ischar(v), v = {v}; end
if ~iscell(v)
    error('stability:et_fcs_snapshot:badTextVector', '%s must be a text cell/string vector.', name);
end
c = reshape(v, 1, []);
for i = 1:numel(c)
    c{i} = scalar_text(c{i}, name);
end
end

function s = scalar_text(v, name)
if isstring(v) && isscalar(v), v = char(v); end
if ~ischar(v) || isempty(strtrim(v))
    error('stability:et_fcs_snapshot:badText', '%s entries must be nonempty text scalars.', name);
end
s = char(v);
end

function v = logical_row(v, n, name)
if ~islogical(v) || numel(v) ~= n
    error('stability:et_fcs_snapshot:resourceAlignment', '%s must be a logical vector of length %d.', name, n);
end
v = reshape(v, 1, []);
end

function v = numeric_row(v, n, name)
if ~isnumeric(v) || numel(v) ~= n
    error('stability:et_fcs_snapshot:resourceAlignment', '%s must be a numeric vector of length %d.', name, n);
end
v = reshape(v, 1, []);
end

function tf = contains_unsupported(v)
tf = isa(v, 'function_handle') || isa(v, 'handle');
if tf, return; end
if isstruct(v)
    f = fieldnames(v);
    for i = 1:numel(v)
        for k = 1:numel(f)
            if contains_unsupported(v(i).(f{k})), tf = true; return; end
        end
    end
elseif iscell(v)
    for k = 1:numel(v)
        if contains_unsupported(v{k}), tf = true; return; end
    end
elseif ~(isnumeric(v) || islogical(v) || ischar(v) || isstring(v) || isempty(v))
    tf = true;
end
end
