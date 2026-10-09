function [groups, rowsets, info] = ts_fd_column_groups(dae, active_indices, ny, full_kcl, opts)
%TS_FD_COLUMN_GROUPS  Structurally disjoint FD column groups for the composite
%   coupled residual solved by stability.ts_step_composite:
%
%       r(z) = [ (x1 - x0 - h/2*(f0+f1))(active) ;  g(x1,y1,Ynet) ]
%
%   [GROUPS,ROWSETS,INFO] = TS_FD_COLUMN_GROUPS(DAE,ACTIVE_INDICES,NY,FULL_KCL)
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
%   ALGEBRAIC (y) COLUMN GROUPING (opt-in via OPTS.y_grouping): the frozen
%   device ABI hands every device the whole y vector, so bounding which bus
%   voltages a device reads needs a per-device y-locality PROOF. That proof is
%   supplied by stability.ts_fd_y_locality, which perturbs each foreign bus in
%   the real callbacks. When (and only when) that proof holds, y columns whose
%   owned rows are disjoint may share a group. The owned rows of y column
%   (bus b, part p) are the two KCL rows of the closed network neighbourhood
%   {i : Ynet(i,b)~=0} (an exact, topology-only dependency) plus the active
%   differential rows of any device mapped to b (which read V_b only, by the
%   proof). Two y columns are therefore combinable iff their closed
%   neighbourhoods do not intersect; the greedy colouring below uses that.
%   Because the grouped quotient is the same expression as the per-column one
%   for every row (the residual is evaluated from bit-identical inputs on the
%   rows it keeps), the grouped Jacobian equals the per-column Jacobian
%   BIT-FOR-BIT; the caller verifies this with fd_structure_check. When the
%   proof fails, or OPTS is absent/off, y columns stay one per group, i.e. the
%   historical per-column FD.
%
%   The net y-grouping is validated by the events/topology of each call: the
%   closed-neighbourhood row sets are recomputed from the CURRENT Ynet, so a
%   fault/outage that changes the branch sparsity cannot be served a stale row
%   set; and a changed device set / mode / freeze context forces a re-probe of
%   the locality (see the signature in y_locality_cached).
%
%   FAIL CLOSED: if any structural precondition cannot be established, the
%   return is one column per group, i.e. the historical per-column FD, and
%   INFO.fallback_reason records why. A violated internal invariant (incomplete
%   cover, or two columns of one group sharing a residual row) is a defect in
%   this derivation and raises an error rather than degrading silently.
%
%   OPTS fields (all optional; absent -> historical behaviour):
%     y_grouping    - logical; attempt algebraic-column grouping
%     Ynet          - the step's network admittance (closed neighbourhoods)
%     x             - composite state  (y-locality probe)
%     u             - composite inputs (y-locality probe)
%     event_context - device context   (y-locality probe)
%     t             - probe time (default 0)
%
%   Source: PROJECT_DERIVED structural analysis of stability.composite_dae.
%   The grouping changes only how many residual evaluations build the same dense
%   Jacobian; it changes no residual, tolerance, or state-order contract.

if nargin < 5 || ~isstruct(opts), opts = struct(); end
na = numel(active_indices);
nz = na + ny;
groups = num2cell(1:nz);
rowsets = repmat({{}},1,nz);
info = struct('grouped',false,'n_groups',nz,'n_state_groups',na, ...
    'n_state_columns',na,'fallback_reason','', ...
    'n_y_groups',ny,'n_y_columns',ny,'y_grouping',false,'y_locality_reason','');

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

% --- Algebraic (y) column grouping -----------------------------------------
% Default: one y column per group (historical). Upgraded to the disjoint
% closed-neighbourhood grouping only when the wrapper asks for it AND the
% per-device y-locality proof holds for the CURRENT device set and context.
ygcols = cell(1,ny);
for j = 1:ny, ygcols{j} = na + j; end
ycrows = repmat({{}},1,ny);
y_local = false;
if isfield(opts,'y_grouping') && logical(opts.y_grouping) && ...
        isstruct(opts) && all(isfield(opts,{'Ynet','x','u','event_context'}))
    Ynet = opts.Ynet;
    if isequal(size(Ynet),[dae.nb dae.nb])
        loc = y_locality_cached(dae,opts);
        info.y_locality_reason = loc.reason;
        if loc.local
            y_local = true;
            cnb = false(dae.nb,dae.nb);
            for b = 1:dae.nb
                nb_idx = find(Ynet(:,b) ~= 0);
                cnb(b,[b; nb_idx(:)]) = true;
            end
            % Owned rows of every y column.
            for b = 1:dae.nb
                devs_b = find(bmap == b);
                devrows_b = [];
                for k = devs_b
                    devrows_b = [devrows_b, dev_rows{k}]; %#ok<AGROW>
                end
                idx = find(cnb(b,:));
                kclrows = sort([na + 2*idx - 1, na + 2*idx]);
                rows_b = unique([devrows_b, kclrows]);
                ycrows{2*(b-1)+1} = rows_b;
                ycrows{2*(b-1)+2} = rows_b;
            end
            % Greedy colouring: two y columns share a group iff their closed
            % neighbourhoods are disjoint (their owned row sets then are too).
            ygcols = {}; gcn = {};
            for j = 1:ny
                b = floor((j-1)/2) + 1;
                placed = false;
                for gi = 1:numel(ygcols)
                    if ~any(cnb(b,:) & gcn{gi})
                        ygcols{gi}(end+1) = na + j;
                        gcn{gi} = gcn{gi} | cnb(b,:);
                        placed = true;
                        break;
                    end
                end
                if ~placed
                    ygcols{end+1} = na + j;   %#ok<AGROW>
                    gcn{end+1} = cnb(b,:);    %#ok<AGROW>
                end
            end
            % Invariant: no group holds two y columns with intersecting closed
            % neighbourhoods (i.e. sharing a residual row).
            for gi = 1:numel(ygcols)
                seen = false(1,dae.nb);
                for c = ygcols{gi}
                    b = floor((c-na-1)/2) + 1;
                    if any(seen & cnb(b,:))
                        error('ts_fd_column_groups:conflictingYGroup', ...
                            'y group %d holds buses with intersecting closed neighbourhoods.',gi);
                    end
                    seen = seen | cnb(b,:);
                end
            end
        end
    else
        info.y_locality_reason = 'Ynet_shape_mismatch';
    end
elseif isfield(opts,'y_grouping') && logical(opts.y_grouping)
    info.y_locality_reason = 'missing_probe_inputs';
end

groups = [gcols, ygcols];
rowsets = cell(1,numel(groups));
for gi = 1:numel(gcols)
    rowsets{gi} = arrayfun(@(c) dev_rows{owner(c)},gcols{gi}, ...
        'UniformOutput',false);
end
for gi = 1:numel(ygcols)
    cols = ygcols{gi};
    if y_local && numel(cols) > 1
        rs = cell(1,numel(cols));
        for m = 1:numel(cols)
            rs{m} = ycrows{cols(m)-na};
        end
        rowsets{numel(gcols)+gi} = rs;
    else
        rowsets{numel(gcols)+gi} = {};
    end
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
info.n_y_groups = numel(ygcols);
info.n_y_columns = ny;
info.y_grouping = y_local && numel(ygcols) < ny;
end

% =========================================================================
function loc = y_locality_cached(dae, opts)
%Y_LOCALITY_CACHED เทียบ device/context จริง ไม่ hash สรุป captured workspace.
% เก็บเพียง entry ล่าสุด; closure ใหม่ต้อง re-probe แม้ข้อความ function เหมือนกัน.
persistent previous_key previous_loc
key=struct('devices',dae.devices,'nb',dae.nb,'bus_map',dae.bus_map, ...
    'device_offsets',dae.device_offsets,'u_offsets',dae.u_offsets, ...
    'event_context',opts.event_context);
if ~isempty(previous_key) && isequaln(key,previous_key)
    loc=previous_loc;
    return;
end
t=0;
if isfield(opts,'t') && isnumeric(opts.t) && isscalar(opts.t) && isfinite(opts.t)
    t=double(opts.t);
end
loc=stability.ts_fd_y_locality(dae,opts.x,opts.u,opts.event_context,t);
previous_key=key;
previous_loc=loc;
end
