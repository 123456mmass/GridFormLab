function snapshot = state_inventory_snapshot(dae, active_state_indices, opt)
%STATE_INVENTORY_SNAPSHOT  IBR-owned Section H state/input/resource inventory.
%
%   snapshot = ibr.state_inventory_snapshot(dae, active_state_indices, opt)
%   builds the Section H index inventory for supported IBR devices in the
%   composite DAE. It is a PURE metadata/index processor: it does NOT call
%   any device differential RHS, current injection, equilibrium solver, SSSA
%   eigensolve, or external routine. It invents no equations, parameters,
%   page citations, or index identities.
%
%   Required:
%     dae                     composite DAE struct (dae.devices, dae.device_offsets)
%     active_state_indices    global active state set (defines Ared row/col order)
%   Optional (opt struct, defaults shown):
%     opt.event_context = struct()   authoritative runtime mode/online maps
%     opt.u_eq          = []         equilibrium input vector
%     opt.sssa          = []         composite SSSA struct (for reduced_index)
%     opt.resource_map  = []         resource->device map rows
%     opt.scope         = "IBR_ONLY" IBR_ONLY (default) | FULL_SYSTEM
%
%   The inventory retains EVERY IBR state (active, source-frozen,
%   inactive-mode anchor, offline) — never silently omits. SG devices are
%   not in IBR scope; nx_total_system is reported separately and FULL_SYSTEM
%   scope fails closed if any unsupported device exists.
%
%   resource_index is NOT assumed to equal device_index. If opt.resource_map
%   is absent, resource_index=NaN with resource_index_status='NOT_AVAILABLE'.
%
%   reduced_state_index (row/col in sssa.A) is available only when opt.sssa
%   is supplied and its active_state_indices exactly match the input set and
%   size(sssa.A,1)==numel(active_state_indices). Otherwise NaN with a status.
%
%   physical_coordinate_index (row in sssa.physical_A) is intentionally NOT
%   fabricated in Phase 1: physical coordinates are tangent/quotient
%   coordinates that need not map one-to-one to global states. Lift-map
%   composition is deferred to a later phase.
%
%   See: docs/project/IEEE14_IBR_DYNAMIC_EQUATION_CONTRACT.md (Section H).
%   Status: SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES. No production
%   numerical equation, state order, or ABI change.

arguments
    dae struct
    active_state_indices double
    opt struct = struct()
end

% --- Validate dae --------------------------------------------------------
if ~isfield(dae,'devices') || ~isfield(dae,'device_offsets')
    error('ibr:state_inventory_snapshot:badDae', ...
        'dae.devices and dae.device_offsets are required.');
end
nd = numel(dae.devices);
if numel(dae.device_offsets) ~= nd
    error('ibr:state_inventory_snapshot:offsetMismatch', ...
        'dae.device_offsets length (%d) must equal dae.devices length (%d).', ...
        numel(dae.device_offsets), nd);
end

% --- Validate active_state_indices ---------------------------------------
asi = active_state_indices(:)';
if isempty(asi) && nd > 0
    error('ibr:state_inventory_snapshot:emptyActive', ...
        'active_state_indices is empty but dae has %d devices.', nd);
end
if any(~isfinite(asi)) || any(asi ~= floor(asi)) || any(asi < 1)
    error('ibr:state_inventory_snapshot:badActiveIndices', ...
        'active_state_indices must be finite positive integers.');
end
total_nx = sum(arrayfun(@(d) d.nx, dae.devices));
if ~isempty(asi) && max(asi) > total_nx
    error('ibr:state_inventory_snapshot:activeOutOfRange', ...
        'max(active_state_indices)=%d exceeds total state count %d.', ...
        max(asi), total_nx);
end
if numel(unique(asi)) ~= numel(asi)
    error('ibr:state_inventory_snapshot:duplicateActive', ...
        'active_state_indices contains duplicates.');
end
% Preserve the supplied order — it defines Ared row/col order. Do NOT sort.
active_position_map = containers.Map(asi, 1:numel(asi));

% --- Optional SSSA validation --------------------------------------------
sssa = [];
if isfield(opt,'sssa') && ~isempty(opt.sssa)
    sssa = opt.sssa;
    if ~isstruct(sssa) || ~isfield(sssa,'A') || ~isfield(sssa,'active_state_indices')
        error('ibr:state_inventory_snapshot:badSssa', ...
            'opt.sssa must have A and active_state_indices.');
    end
    if ~isequal(sssa.active_state_indices, asi)
        error('ibr:state_inventory_snapshot:sssaActiveMismatch', ...
            'opt.sssa.active_state_indices must match active_state_indices exactly.');
    end
    if size(sssa.A,1) ~= numel(asi) || size(sssa.A,2) ~= numel(asi)
        error('ibr:state_inventory_snapshot:sssaDimMismatch', ...
            'size(sssa.A)=%dx%d must equal numel(active_state_indices)=%d.', ...
            size(sssa.A,1), size(sssa.A,2), numel(asi));
    end
end

% --- Optional resource_map ----------------------------------------------
resource_map = [];
if isfield(opt,'resource_map') && ~isempty(opt.resource_map)
    resource_map = validate_resource_map(opt.resource_map, dae);
end

% --- Optional equilibrium input ------------------------------------------
u_eq = [];
u_eq_status = 'NOT_AVAILABLE';
if isfield(opt,'u_eq') && ~isempty(opt.u_eq)
    u_eq = opt.u_eq(:);
    u_eq_status = 'AVAILABLE_OPT';
end
if ~isempty(sssa) && isfield(sssa,'u_eq') && ~isempty(sssa.u_eq)
    if ~isempty(u_eq)
        if ~isequal(u_eq, sssa.u_eq(:))
            error('ibr:state_inventory_snapshot:uEqConflict', ...
                'opt.u_eq and sssa.u_eq differ; resolve before inventory.');
        end
    else
        u_eq = sssa.u_eq(:);
        u_eq_status = 'AVAILABLE_SSSA';
    end
end

% --- Input offsets -------------------------------------------------------
u_offsets = input_offsets(dae);

% --- Event-context mode/online maps -------------------------------------
modes_map = struct();
online_map = struct();
if isfield(opt,'event_context') && ~isempty(opt.event_context) && ...
        isfield(opt.event_context,'hybrid_state')
    hs = opt.event_context.hybrid_state;
    if isfield(hs,'device_modes') && isfield(hs,'device_online')
        modes_map = hs.device_modes;
        online_map = hs.device_online;
    end
end

% --- Build per-state rows ------------------------------------------------
rows = repmat(state_row_template(), 0);
input_rows = repmat(input_row_template(), 0);
ibr_device_indices = [];
for k = 1:nd
    dev = dae.devices(k);
    [meta, ok] = safe_metadata(dev);
    if ~ok
        continue;   % non-IBR device: skip in IBR_ONLY scope
    end
    ibr_device_indices(end+1) = k; %#ok<AGROW>
    dev_offset = dae.device_offsets(k);
    key = matlab.lang.makeValidName(char(dev.device_id),'ReplacementStyle','underscore');
    [runtime_mode, runtime_online] = resolve_runtime_status(dev, key, modes_map, online_map);
    [r_idx, r_status] = resolve_resource_index(dev, k, resource_map);
    for li = 1:dev.nx
        gi = dev_offset + li;
        sm = meta.state_metadata(li);
        pos = lookup_active_position(active_position_map, gi);
        % Offline devices have no active participation regardless of asi membership.
        if ~runtime_online
            pos = NaN;
        end
        [red_idx, red_status, in_ared] = resolve_reduced(pos, sssa);
        status = resolve_state_status(runtime_online, runtime_mode, pos, ...
            sm.state_branch, dev, dev.mode);
        rows(end+1) = struct( ...
            'resource_index',r_idx, ...
            'resource_index_status',r_status, ...
            'device_index',k, ...
            'device_id',char(dev.device_id), ...
            'device_type',char(dev.device_type), ...
            'operating_mode',runtime_mode, ...
            'online',runtime_online, ...
            'bus_id',dev.bus_id, ...
            'bus_position',dev.bus_position, ...
            'local_state_index',li, ...
            'global_state_index',gi, ...
            'active_state_position',pos, ...
            'reduced_state_index',red_idx, ...
            'reduced_state_index_status',red_status, ...
            'physical_coordinate_index',NaN, ...
            'physical_coordinate_index_status','NOT_AVAILABLE_PHASE_1', ...
            'state_name',sm.state_name, ...
            'state_symbol',sm.state_symbol, ...
            'equation_source',sm.equation_source, ...
            'equation_classification',sm.equation_classification, ...
            'state_status',status, ...
            'unit',sm.unit, ...
            'frame',sm.frame, ...
            'in_Ared',in_ared, ...
            'state_branch',sm.state_branch, ...
            'citation_status',sm.citation_status, ...
            'source_doc',sm.source_doc); %#ok<AGROW>
    end
    % Input rows
    for ji = 1:dev.nu
        im = meta.input_metadata(ji);
        g_u = u_offsets(k) + ji;
        cur = NaN; eq = NaN;
        if isfield(dae,'u0') && numel(dae.u0) >= g_u
            cur = dae.u0(g_u);
        end
        if ~isempty(u_eq) && numel(u_eq) >= g_u
            eq = u_eq(g_u);
        end
        input_rows(end+1) = struct( ...
            'resource_index',r_idx, ...
            'resource_index_status',r_status, ...
            'device_index',k, ...
            'device_id',char(dev.device_id), ...
            'local_input_index',ji, ...
            'global_input_index',g_u, ...
            'input_name',im.input_name, ...
            'source',im.source, ...
            'equation_classification',im.equation_classification, ...
            'unit',im.unit, ...
            'current_value',cur, ...
            'equilibrium_value',eq, ...
            'equilibrium_value_status',ternary_(isnan(eq),'NOT_AVAILABLE',u_eq_status), ...
            'event_mutability',im.event_mutability, ...
            'source_doc',im.source_doc); %#ok<AGROW>
    end
end

% --- FULL_SYSTEM scope guard --------------------------------------------
scope = "IBR_ONLY";
if isfield(opt,'scope')
    scope = string(opt.scope);
end
if scope == "FULL_SYSTEM" && numel(ibr_device_indices) ~= nd
    error('ibr:state_inventory_snapshot:fullSystemScopeUnsupported', ...
        ['FULL_SYSTEM scope requires all devices IBR-supported; %d of %d ' ...
         'devices are non-IBR. Use IBR_ONLY scope.'], ...
        numel(ibr_device_indices), nd);
end

% --- Counts --------------------------------------------------------------
nx_total_ibr = numel(rows);
nx_active = sum(strcmp({rows.state_status},'ACTIVE_IN_ARED'));
nx_frozen = sum(strcmp({rows.state_status},'FROZEN_NOT_IN_ARED'));
nx_inactive_anchor = sum(strcmp({rows.state_status},'INACTIVE_MODE_NOT_IN_ARED'));
nx_offline = sum(strcmp({rows.state_status},'OFFLINE_NOT_IN_ARED'));

% --- Ared cardinality check (when sssa available) ------------------------
ared_check = struct('verified',false,'size_Ared',NaN,'numel_active',numel(asi));
if ~isempty(sssa)
    ared_check.size_Ared = size(sssa.A,1);
    ared_check.verified = (ared_check.size_Ared == numel(asi));
end

snapshot = struct( ...
    'scope',char(scope), ...
    'n_devices_total',nd, ...
    'n_ibr_devices',numel(ibr_device_indices), ...
    'ibr_device_indices',ibr_device_indices, ...
    'state_rows',rows, ...
    'input_rows',input_rows, ...
    'resource_map_status',ternary_(isempty(resource_map),'NOT_AVAILABLE','AVAILABLE'), ...
    'counts',struct( ...
        'nx_total_ibr',nx_total_ibr, ...
        'nx_total_system',total_nx, ...
        'nx_active',nx_active, ...
        'nx_frozen',nx_frozen, ...
        'nx_inactive_anchor',nx_inactive_anchor, ...
        'nx_offline',nx_offline), ...
    'active_state_indices',asi, ...
    'ared_cardinality_check',ared_check, ...
    'u_eq_status',u_eq_status);
end

% =========================================================================
function [meta, ok] = safe_metadata(dev)
ok = false;
meta = struct();
try
    meta = ibr.device_contract_metadata(dev);
    ok = true;
catch err
    if contains(err.identifier,'unknownContract')
        ok = false;   % non-IBR device: legitimate skip
    else
        rethrow(err);
    end
end
end

function [mode, online] = resolve_runtime_status(dev, key, modes_map, online_map)
mode = char(dev.mode);
online = true;
if isfield(modes_map, key)
    mode = char(modes_map.(key));
end
if isfield(online_map, key)
    online = logical(online_map.(key));
end
end

function [r_idx, r_status] = resolve_resource_index(dev, dev_idx, resource_map)
r_idx = NaN;
r_status = 'NOT_AVAILABLE';
if isempty(resource_map)
    return;
end
match = [];
for r = 1:numel(resource_map)
    row = resource_map(r);
    if strcmpi(row.device_id, char(dev.device_id)) || ...
            (isfield(row,'device_index') && row.device_index == dev_idx)
        match = row;
        break;
    end
end
if isempty(match)
    error('ibr:state_inventory_snapshot:resourceMapMissingDevice', ...
        'resource_map supplied but device %s (index %d) is not mapped.', ...
        char(dev.device_id), dev_idx);
end
r_idx = match.resource_index;
r_status = 'AVAILABLE';
end

function [red_idx, red_status, in_ared] = resolve_reduced(pos, sssa)
if isnan(pos)
    red_idx = NaN;
    red_status = 'NOT_IN_ARED';
    in_ared = false;
    return;
end
if isempty(sssa)
    red_idx = NaN;
    red_status = 'NOT_AVAILABLE_NO_SSSA';
    in_ared = true;   % active in the supplied set, but no A matrix to index
    return;
end
red_idx = pos;        % Ared row/col == active_state_position under no-deletion contract
red_status = 'AVAILABLE';
in_ared = true;
end

function status = resolve_state_status(online, mode, pos, branch, dev, ctor_mode)
if ~online
    status = 'OFFLINE_NOT_IN_ARED';
    return;
end
if ~isnan(pos)
    status = 'ACTIVE_IN_ARED';
    return;
end
% Not active. Distinguish inactive-mode anchor vs source-frozen.
if any(strcmp(char(dev.device_type),{'ibr_dual_mode','ibr_dual_mode_rms10', ...
        'ibr_eecon49_dual','ibr_decoupled_dual'}))
    % Dual-mode: the non-selected branch is an inactive-mode anchor.
    active_branch = branch_from_mode(mode);
    if strcmp(branch, active_branch)
        status = 'FROZEN_NOT_IN_ARED';
    else
        status = 'INACTIVE_MODE_NOT_IN_ARED';
    end
    return;
end
% Standalone device: a non-active state is source-frozen (e.g. delta_ITmin
% when ESFlag=0). Detect via active_state_indices membership already done.
status = 'FROZEN_NOT_IN_ARED';
% delta_ITmin-specific guard is handled by active set membership: if the
% device published active_state_indices and this state is not in it, it is
% source-frozen by construction.
end

function b = branch_from_mode(mode)
m = lower(char(mode));
if strcmp(m,'gfm')
    b = 'gfm';
elseif strcmp(m,'gfl')
    b = 'gfl';
else
    b = '';   % tripped: no branch active -> all states inactive-mode anchors
end
end

function pos = lookup_active_position(active_map, gi)
if isKey(active_map, gi)
    pos = active_map(gi);
else
    pos = NaN;
end
end

function offsets = input_offsets(dae)
if isfield(dae,'u_offsets') && ~isempty(dae.u_offsets)
    offsets = dae.u_offsets;
    return;
end
% Derive cumulatively and cross-check against per-device nu.
offsets = zeros(numel(dae.devices),1);
for k = 1:numel(dae.devices)
    if k > 1
        offsets(k) = offsets(k-1) + dae.devices(k-1).nu;
    end
end
if isfield(dae,'u0')
    total_u = sum(arrayfun(@(d) d.nu, dae.devices));
    if numel(dae.u0) ~= total_u
        error('ibr:state_inventory_snapshot:uOffsetMismatch', ...
            'numel(dae.u0)=%d does not equal sum(dev.nu)=%d.', ...
            numel(dae.u0), total_u);
    end
end
end

function rm = validate_resource_map(rm, dae)
if ~isstruct(rm)
    error('ibr:state_inventory_snapshot:badResourceMap', ...
        'opt.resource_map must be a struct array.');
end
for k = 1:numel(rm)
    r = rm(k);
    if ~isfield(r,'resource_index') || ~isfield(r,'device_id')
        error('ibr:state_inventory_snapshot:badResourceMapRow', ...
            'resource_map row %d must have resource_index and device_id.', k);
    end
end
idx = [rm.resource_index];
if any(~isfinite(idx)) || any(idx ~= floor(idx)) || any(idx < 1) ...
        || numel(unique(idx)) ~= numel(idx)
    error('ibr:state_inventory_snapshot:badResourceIndex', ...
        'resource_index must be unique finite positive integers.');
end
dids = {rm.device_id};
if numel(unique(dids)) ~= numel(dids)
    error('ibr:state_inventory_snapshot:duplicateResourceDevice', ...
        'resource_map device_id entries must be unique.');
end
% Every IBR device must be mapped exactly once (checked in resolve).
end

% --- Row templates -------------------------------------------------------
function r = state_row_template()
r = struct( ...
    'resource_index',0,'resource_index_status','', ...
    'device_index',0,'device_id','','device_type','','operating_mode','', ...
    'online',false,'bus_id',0,'bus_position',0,'local_state_index',0, ...
    'global_state_index',0,'active_state_position',NaN,'reduced_state_index',NaN, ...
    'reduced_state_index_status','','physical_coordinate_index',NaN, ...
    'physical_coordinate_index_status','','state_name','','state_symbol','', ...
    'equation_source','','equation_classification','','state_status','', ...
    'unit','','frame','','in_Ared',false,'state_branch','', ...
    'citation_status','','source_doc','');
end

function r = input_row_template()
r = struct( ...
    'resource_index',0,'resource_index_status','', ...
    'device_index',0,'device_id','','local_input_index',0, ...
    'global_input_index',0,'input_name','','source','', ...
    'equation_classification','','unit','','current_value',NaN, ...
    'equilibrium_value',NaN,'equilibrium_value_status','', ...
    'event_mutability','','source_doc','');
end

function out = ternary_(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
