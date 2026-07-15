function normalized = reference_owner_schema(hybrid_state, devices, opt)
%REFERENCE_OWNER_SCHEMA Canonical normalization of reference-ownership fields.
%   NORMALIZED = reference_owner_schema(HYBRID_STATE, DEVICES, OPT) is the
%   SINGLE normalization/validation point for the multi-island reference-
%   ownership schema. Every consumer reads the NORMALIZED struct; no consumer
%   interprets the legacy alias on its own.
%
%   Canonical fields (source of truth):
%     reference_owner_indices       (1xNi) owner resource index per island
%     gfm_reference_resource_indices (1xNi) GFM numerical reference per island
%                                    (empty entry where an SG owns that island)
%     reference_island_ids          (1xNi) island ID per entry, sorted ascending
%     selected_gfm_indices          (1xNf) complete physical online GFM set
%                                    (independent of reference ownership)
%
%   Legacy read-only compatibility alias:
%     reference_resource_index      scalar; permitted ONLY for single-island
%                                    cases. single-island + SG_OFF: equals
%                                    gfm_reference_resource_indices(1).
%                                    SG_ON: must be [] and must NOT point to
%                                    an SG. multi-island: unsupported/empty;
%                                    a consumer requiring a scalar fails
%                                    closed.
%
%   Migration contract (F1/C1, user-approved additive+alias):
%     - new fields are canonical; the legacy alias is read-only;
%     - if old and new fields coexist but disagree, fail closed;
%     - exactly one supervisory reference owner per energized island;
%     - no duplicate owner within an island;
%     - full-KCL TS formulation is unchanged: reference ownership is
%       supervisory/physical, NOT a KCL-row or per-step slack replacement.
%
%   Classification: multi-island reference-ownership schema PROJECT_DERIVED;
%   island detection via Ybus connected components NUMERICAL_METHOD
%   (off-diagonal connectivity, in-house BFS, no toolbox).

arguments
    hybrid_state struct
    devices struct
    opt struct = struct()
end

tol = 1e-12;
if isfield(opt,'connectivity_tol') && ~isempty(opt.connectivity_tol)
    tol = opt.connectivity_tol;
end

normalized = empty_normalized();

% --- Extract canonical fields (if present) -------------------------------
[owner_indices, gfm_ref_indices, island_ids, selected_gfm] = ...
    extract_canonical(hybrid_state);

% --- Extract legacy alias (if present) -----------------------------------
legacy_ref = [];
if isfield(hybrid_state,'reference_resource_index') && ...
        ~isempty(hybrid_state.reference_resource_index)
    legacy_ref = hybrid_state.reference_resource_index;
end

% --- Coalesce: canonical wins; legacy alias accepted only when canonical
%     is absent and the case is single-island -----------------------------
has_canonical = ~isempty(island_ids);
has_legacy = ~isempty(legacy_ref);

if ~has_canonical && ~has_legacy
    % No reference ownership declared. Callers that require one validate
    % separately; this helper returns an empty (uninitialized) schema.
    return;
end

if has_legacy
    legacy_idx = validate_scalar_index(legacy_ref, devices);
    if has_canonical
        % Both present: they must agree. The legacy alias is only valid for
        % single-island SG_OFF (alias == gfm reference of island 1) or SG_ON
        % (alias must be empty, which is already excluded by has_legacy).
        if numel(island_ids) ~= 1
            error('stability:reference_owner_schema:mixedSchemaMultiIsland', ...
                ['Legacy reference_resource_index is present alongside ' ...
                 'multi-island canonical fields; ambiguous mixed schema.']);
        end
        if ~isempty(gfm_ref_indices) && gfm_ref_indices(1) ~= legacy_idx
            error('stability:reference_owner_schema:aliasMismatch', ...
                ['Legacy reference_resource_index (%d) disagrees with ' ...
                 'gfm_reference_resource_indices(1) (%d).'], ...
                legacy_idx, gfm_ref_indices(1));
        end
        if ~isempty(owner_indices) && owner_indices(1) == legacy_idx && ...
                is_sg_device(devices(legacy_idx))
            error('stability:reference_owner_schema:aliasPointsToSg', ...
                ['Legacy reference_resource_index (%d) points to an SG; ' ...
                 'the SG_ON alias must be empty.'], legacy_idx);
        end
    else
        % Only legacy present: accept as single-island SG_OFF GFM reference.
        island_ids = 1;
        owner_indices = legacy_idx;
        gfm_ref_indices = legacy_idx;
    end
end

% --- Validate canonical arrays -------------------------------------------
if numel(owner_indices) ~= numel(island_ids) || ...
        numel(gfm_ref_indices) ~= numel(island_ids)
    error('stability:reference_owner_schema:cardinalityMismatch', ...
        ['reference_owner_indices, gfm_reference_resource_indices, and ' ...
         'reference_island_ids must have equal cardinality.']);
end

% Sort by island ID (stable) so consumers can index deterministically.
[island_ids_sorted, order] = sort(island_ids);
owner_indices = owner_indices(order);
gfm_ref_indices = gfm_ref_indices(order);

for k = 1:numel(island_ids_sorted)
    oi = owner_indices(k);
    gi = gfm_ref_indices(k);
    if isempty(oi) || ~isfinite(oi) || oi ~= fix(oi) || oi < 1 || oi > numel(devices)
        error('stability:reference_owner_schema:badOwnerIndex', ...
            'reference_owner_indices entry %d is not a valid device index.', k);
    end
    dev = devices(oi);
    key = device_key(dev);
    online = isfield(hybrid_state,'device_online') && ...
        isfield(hybrid_state.device_online,key) && ...
        logical(hybrid_state.device_online.(key));
    if ~online
        error('stability:reference_owner_schema:ownerOffline', ...
            'Reference owner index %d is not online.', oi);
    end
    mode = '';
    if isfield(hybrid_state,'device_modes') && isfield(hybrid_state.device_modes,key)
        mode = char(hybrid_state.device_modes.(key));
    end
    if ~is_voltage_forming_mode(dev, mode)
        error('stability:reference_owner_schema:ownerNotVoltageForming', ...
            'Reference owner index %d (mode %s) is not a voltage-forming mode.', ...
            oi, mode);
    end
    if ~can_own_reference(dev)
        error('stability:reference_owner_schema:ownerNotCapable', ...
            'Reference owner index %d capability metadata does not permit ownership.', oi);
    end
    % gfm_reference entry: empty (or NaN, used as array placeholder for "empty")
    % where an SG owns, else a selected GFM member.
    if ~isempty(gi) && ~(isnumeric(gi) && isnan(gi))
        gi_idx = validate_scalar_index(gi, devices);
        if ~is_gfm_capable_device(devices(gi_idx))
            error('stability:reference_owner_schema:gfmRefNotGfm', ...
                'gfm_reference_resource_indices entry %d is not GFM-capable.', k);
        end
    end
end

% No duplicate owner within an island (island_ids already unique-sorted;
% owner indices within the same island would require duplicate island IDs,
% which the sort/unique check below catches).
if numel(unique(island_ids_sorted)) ~= numel(island_ids_sorted)
    error('stability:reference_owner_schema:duplicateIsland', ...
        'reference_island_ids contains duplicate entries.');
end

normalized.reference_owner_indices = owner_indices;
normalized.gfm_reference_resource_indices = gfm_ref_indices;
normalized.reference_island_ids = island_ids_sorted;
normalized.selected_gfm_indices = selected_gfm;
normalized.is_single_island = (numel(island_ids_sorted) == 1);
% Read-only legacy alias: single-island only. NaN entries (SG owns the
% island) map to an empty alias (SG_ON: alias must be [], must NOT point to SG).
if normalized.is_single_island
    g1 = [];
    if ~isempty(gfm_ref_indices) && ~isempty(gfm_ref_indices(1)) && ...
            ~(isnumeric(gfm_ref_indices(1)) && isnan(gfm_ref_indices(1)))
        g1 = gfm_ref_indices(1);
    end
    normalized.reference_resource_index = g1;
else
    normalized.reference_resource_index = [];
end
end

% =========================================================================
function [owner_indices, gfm_ref_indices, island_ids, selected_gfm] = ...
    extract_canonical(hs)
owner_indices = [];
gfm_ref_indices = [];
island_ids = [];
selected_gfm = [];
if isfield(hs,'reference_owner_indices') && ~isempty(hs.reference_owner_indices)
    owner_indices = hs.reference_owner_indices;
end
if isfield(hs,'gfm_reference_resource_indices') && ...
        ~isempty(hs.gfm_reference_resource_indices)
    gfm_ref_indices = hs.gfm_reference_resource_indices;
end
if isfield(hs,'reference_island_ids') && ~isempty(hs.reference_island_ids)
    island_ids = hs.reference_island_ids;
end
if isfield(hs,'selected_gfm_indices') && ~isempty(hs.selected_gfm_indices)
    selected_gfm = hs.selected_gfm_indices;
end
% Equalize empty arrays: if one canonical array is present, the others must
% be sized consistently. Treat all-empty as "no canonical schema declared".
if isempty(island_ids)
    owner_indices = [];
    gfm_ref_indices = [];
end
end

function idx = validate_scalar_index(value, devices)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
        value ~= fix(value) || value < 1 || value > numel(devices)
    error('stability:reference_owner_schema:badScalarIndex', ...
        'A reference index must be one finite in-range integer device index.');
end
idx = value;
end

function key = device_key(dev)
key = matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
end

function tf = is_sg_device(dev)
tf = false;
if isfield(dev,'capabilities') && isstruct(dev.capabilities) && ...
        isfield(dev.capabilities,'resource_type')
    tf = strcmpi(char(dev.capabilities.resource_type),'sg');
elseif isfield(dev,'device_type')
    tf = strcmpi(char(dev.device_type),'sg');
end
end

function tf = is_voltage_forming_mode(dev, mode)
tf = false;
if isempty(mode)
    return;
end
if strcmpi(mode,'synchronous')
    tf = true;
    return;
end
if isfield(dev,'capabilities') && isstruct(dev.capabilities) && ...
        isfield(dev.capabilities,'voltage_forming_modes')
    vf = string(dev.capabilities.voltage_forming_modes);
    tf = any(strcmpi(vf, lower(mode)));
end
end

function tf = can_own_reference(dev)
tf = isfield(dev,'capabilities') && isstruct(dev.capabilities) && ...
    isfield(dev.capabilities,'can_switch_online') && ...
    islogical(dev.capabilities.can_switch_online) && ...
    isscalar(dev.capabilities.can_switch_online) && ...
    dev.capabilities.can_switch_online;
% SG devices can always own reference when online; the can_switch_online
% flag is the supervisory capability gate for IBRs. An online SG is a valid
% owner regardless of can_switch_online (it is not switching, it is owning).
if ~tf && is_sg_device(dev)
    tf = true;
end
end

function tf = is_gfm_capable_device(dev)
tf = false;
if ~isfield(dev,'capabilities') || ~isstruct(dev.capabilities)
    return;
end
c = dev.capabilities;
if ~all(isfield(c,{'resource_type','can_switch_mode','supported_modes', ...
        'voltage_forming_modes'}))
    return;
end
tf = strcmpi(char(c.resource_type),'ibr') && ...
    islogical(c.can_switch_mode) && isscalar(c.can_switch_mode) && ...
    c.can_switch_mode && any(strcmpi(string(c.supported_modes),'gfm')) && ...
    any(strcmpi(string(c.supported_modes),'gfl')) && ...
    any(strcmpi(string(c.voltage_forming_modes),'gfm'));
end

function n = empty_normalized()
n = struct( ...
    'reference_owner_indices', [], ...
    'gfm_reference_resource_indices', [], ...
    'reference_island_ids', [], ...
    'selected_gfm_indices', [], ...
    'is_single_island', false, ...
    'reference_resource_index', []);
end
