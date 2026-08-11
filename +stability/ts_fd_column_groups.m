function [groups, rowsets, info] = ts_fd_column_groups(dae, active_indices, ny, full_kcl)
%TS_FD_COLUMN_GROUPS  Structurally disjoint FD column groups for the composite
%   coupled residual solved by stability.ts_step_composite:
%
%       r(z) = [ (x1 - x0 - h/2*(f0+f1))(active) ;  g(x1,y1,Ynet) ]
%
%   [GROUPS,ROWSETS,INFO] = ts_fd_column_groups(DAE,ACTIVE_INDICES,NY,FULL_KCL)
%   returns a partition of the unknown columns 1:(numel(ACTIVE_INDICES)+NY)
%   such that every column of one group may be perturbed simultaneously and
%   still yield, for each of those columns, exactly the forward difference
%   quotient that perturbing it alone would yield.
%
%   WHY THE STATE COLUMNS ARE EXACTLY SEPARABLE (bit-for-bit, not to rounding):
%   stability.composite_dae owns both device dispatch loops.
%     - composite_f writes device k's differential rows from x(xr_k) ONLY;
%     - composite_Ibus adds device k's current injection to row bus_map(k) ONLY;
%     - the network term Y*V does not involve x at all.
%   So one state column of device k can change exactly two row blocks: device
%   k's own differential rows, and the two KCL rows of its mapped bus. Two state
%   columns whose owning device AND mapped bus both differ therefore have
%   disjoint row sets. Stronger than disjointness: because each device is handed
%   only its own x slice, the code that produces device k's rows never reads the
%   other perturbed entries, so those rows are computed from bit-identical
%   inputs. No admittance pattern is involved, which is why this derivation does
%   not depend on which topology (Ypre/Yfault/Ypost) the step is using.
%
%   ALGEBRAIC (y) COLUMNS ARE NEVER GROUPED. The frozen device ABI hands every
%   device the whole y vector, so composite_dae alone cannot bound which bus
%   voltages a device reads. Grouping them would need a per-device y-locality
%   proof, which is deliberately out of scope here; they stay one per group and
%   are therefore evaluated exactly as before.
%
%   FAIL CLOSED: if any structural precondition cannot be established, the
%   return is one column per group, i.e. the historical per-column FD, and
%   INFO.fallback_reason records why. A violated internal invariant (incomplete
%   cover, or two columns of one group sharing a device or a bus) is a defect in
%   this derivation and raises an error rather than degrading silently.
%
%   Source: PROJECT_DERIVED structural analysis of stability.composite_dae.
%   The grouping changes only how many residual evaluations build the same dense
%   Jacobian; it changes no residual, tolerance, or state-order contract.

na = numel(active_indices);
nz = na + ny;
groups = num2cell(1:nz);
rowsets = repmat({{}},1,nz);
info = struct('grouped',false,'n_groups',nz,'n_state_groups',na, ...
    'n_state_columns',na,'fallback_reason','');

if ~full_kcl
    info.fallback_reason = 'reduced_kcl_rows';
    return;
end
required = {'device_offsets','devices','bus_map','nb'};
for k = 1:numel(required)
    if ~isfield(dae,required{k})
        info.fallback_reason = ['missing_' required{k}];
        return;
    end
end
if isfield(dae,'vcon') && isstruct(dae.vcon) && isfield(dae.vcon,'rows') && ...
        ~isempty(dae.vcon.rows)
    info.fallback_reason = 'vcon_rows_declared';
    return;
end
if ~isnumeric(dae.nb) || ~isscalar(dae.nb) || ny ~= 2*dae.nb
    info.fallback_reason = 'ny_not_two_per_bus';
    return;
end
if ~isstruct(dae.devices) || ~isfield(dae.devices,'nx')
    info.fallback_reason = 'devices_without_nx';
    return;
end
offsets = double(dae.device_offsets(:)');
nxd = double([dae.devices.nx]);
bmap = double(dae.bus_map(:)');
nd = numel(nxd);
if numel(offsets) ~= nd || numel(bmap) ~= nd || nd < 1
    info.fallback_reason = 'device_table_length_mismatch';
    return;
end
if any(~isfinite(offsets)) || any(~isfinite(nxd)) || any(~isfinite(bmap)) || ...
        any(nxd < 0) || any(bmap < 1) || any(bmap > dae.nb)
    info.fallback_reason = 'device_table_out_of_range';
    return;
end

% Owning device of every active state column. Device k owns the composite state
% indices offsets(k)+1 .. offsets(k)+nx(k); composite_dae assigns those ranges
% contiguously and disjointly.
owner = zeros(1,na);
for c = 1:na
    s = active_indices(c);
    hit = find(s > offsets & s <= offsets + nxd);
    if numel(hit) ~= 1
        info.fallback_reason = 'active_state_not_owned_by_one_device';
        groups = num2cell(1:nz);
        rowsets = repmat({{}},1,nz);
        return;
    end
    owner(c) = hit;
end

% Row set of every device: its own differential rows (rx rows are numbered in
% the order of active_indices) plus the two KCL rows of its mapped bus.
dev_rows = cell(1,nd);
for k = 1:nd
    b = bmap(k);
    dev_rows{k} = [find(owner == k), na + (2*b-1), na + 2*b];
end

% Greedy grouping: a column joins the first group that holds neither its device
% nor its bus. Deterministic, and the resulting group count equals the largest
% number of active states hosted on any single bus.
gcols = {}; gdev = {}; gbus = {};
for c = 1:na
    k = owner(c); b = bmap(k);
    placed = false;
    for gi = 1:numel(gcols)
        if ~any(gdev{gi} == k) && ~any(gbus{gi} == b)
            gcols{gi}(end+1) = c;
            gdev{gi}(end+1) = k;
            gbus{gi}(end+1) = b;
            placed = true;
            break;
        end
    end
    if ~placed
        gcols{end+1} = c;   %#ok<AGROW>
        gdev{end+1} = k;    %#ok<AGROW>
        gbus{end+1} = b;    %#ok<AGROW>
    end
end

% Invariants. A failure here is a defect in this function, not a property of
% the caller's model, so it must be loud.
for gi = 1:numel(gcols)
    if numel(unique(gdev{gi})) ~= numel(gdev{gi}) || ...
            numel(unique(gbus{gi})) ~= numel(gbus{gi})
        error('ts_fd_column_groups:conflictingGroup', ...
            ['Group %d holds two columns that share a device or a bus, so ' ...
             'their residual rows are not disjoint.'],gi);
    end
end

groups = [gcols, num2cell(na + (1:ny))];
rowsets = cell(1,numel(groups));
for gi = 1:numel(gcols)
    rowsets{gi} = arrayfun(@(c) dev_rows{owner(c)},gcols{gi}, ...
        'UniformOutput',false);
end
for gi = numel(gcols)+1 : numel(groups)
    rowsets{gi} = {};
end

covered = sort([groups{:}]);
if ~isequal(covered(:)',1:nz)
    error('ts_fd_column_groups:incompleteCover', ...
        'Column groups must cover 1:%d exactly once.',nz);
end

info.grouped = true;
info.n_groups = numel(groups);
info.n_state_groups = numel(gcols);
info.n_state_columns = na;
end
