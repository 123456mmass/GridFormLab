function islands = island_components(Ybus, mpc, opt)
%ISLAND_COMPONENTS Detect energized islands from Ybus connected components.
%   ISLANDS = island_components(YBUS, MPC, OPT) computes connected components
%   of the network using OFF-DIAGONAL Ybus connectivity only (diagonal shunt
%   admittance is never counted as a branch), then classifies each component
%   as energized or de-energized.
%
%   A component is ENERGIZED if it contains at least one of:
%     - an online voltage-forming resource (SG online, or IBR in a
%       voltage-forming mode), supplied via opt.online_vf_buses;
%     - a nonzero load (Pd or Qd) from mpc.bus;
%     - a nonzero shunt (Gd or Bd) from mpc.bus.
%   An isolated bus with no load/shunt/resource is its own component and is
%   de-energized.
%
%   Connectivity edge rule (NUMERICAL_METHOD):
%     - an undirected edge (i,j) exists when abs(Ybus(i,j)) >= connectivity_tol;
%     - only off-diagonal entries are examined; diagonal entries (shunt) are
%       never counted as branches;
%     - in-house BFS (no toolbox dependency);
%     - cross-check against mpc.branch status: if a branch row connects two
%       buses that the Ybus connectivity test did NOT join, the Ybus assembly
%       is inconsistent and the helper fails closed.
%
%   Output struct array ISLANDS, one per connected component, sorted by the
%   minimum internal bus position:
%     .island_id            (1-based, ascending by min bus position)
%     .bus_positions        (1xN internal positions into Ybus)
%     .bus_ids              (1xN external bus IDs)
%     .energized            (logical)
%     .has_online_vf_source (logical)
%     .has_load             (logical)
%     .has_shunt            (logical)
%
%   Classification: connected-component detection NUMERICAL_METHOD
%   (in-house BFS, off-diagonal Ybus connectivity); energized classification
%   PROJECT_DERIVED (load/shunt/resource presence). No external solver.
%
%   Source: F3 multi-island reference-owner eligibility (user-approved).

arguments
    Ybus (:,:) double
    mpc struct
    opt struct = struct()
end

tol = 1e-12;
if isfield(opt,'connectivity_tol') && ~isempty(opt.connectivity_tol) && ...
        isnumeric(opt.connectivity_tol) && isscalar(opt.connectivity_tol) && ...
        isfinite(opt.connectivity_tol) && opt.connectivity_tol > 0
    tol = opt.connectivity_tol;
end

nb = size(Ybus, 1);
if nb == 0
    islands = repmat(empty_island(), 0, 1);
    return;
end

% External bus IDs from mpc.bus (column 1). Internal position == row order.
bus_ids = mpc.bus(:, 1);
if numel(bus_ids) ~= nb
    error('stability:island_components:busIdMismatch', ...
        'mpc.bus row count (%d) does not match Ybus size (%d).', ...
        numel(bus_ids), nb);
end

% --- Build adjacency from off-diagonal Ybus connectivity -----------------
adj = false(nb);
for i = 1:nb
    for j = i+1:nb
        if abs(Ybus(i, j)) >= tol
            adj(i, j) = true;
            adj(j, i) = true;
        end
    end
end

% --- Cross-check against mpc.branch connectivity ------------------------
if isfield(mpc, 'branch') && ~isempty(mpc.branch)
    br = mpc.branch;
    for k = 1:size(br, 1)
        f = br(k, 1);
        t = br(k, 2);
        pf = find(bus_ids == f, 1);
        pt = find(bus_ids == t, 1);
        if isempty(pf) || isempty(pt)
            error('stability:island_components:branchBusMissing', ...
                'Branch %d references bus %d or %d not in mpc.bus.', k, f, t);
        end
        if pf ~= pt && ~adj(pf, pt)
            error('stability:island_components:ybusBranchInconsistent', ...
                ['Branch %d (%d->%d) is in mpc.branch but Ybus(%d,%d) is ' ...
                 'below connectivity tol; Ybus assembly inconsistent.'], ...
                k, f, t, pf, pt);
        end
    end
end

% --- BFS connected components -------------------------------------------
visited = false(1, nb);
comp_cells = {};
for start = 1:nb
    if visited(start)
        continue;
    end
    [comp, visited] = bfs_component(start, adj, visited);
    comp_cells{end+1} = comp; %#ok<AGROW>
end

% --- Classify each component --------------------------------------------
online_vf_positions = [];
if isfield(opt, 'online_vf_positions') && ~isempty(opt.online_vf_positions)
    online_vf_positions = opt.online_vf_positions(:).';
end

islands = repmat(empty_island(), numel(comp_cells), 1);
for c = 1:numel(comp_cells)
    comp = sort(comp_cells{c});
    islands(c).bus_positions = comp;
    islands(c).bus_ids = bus_ids(comp).';
    islands(c).has_online_vf_source = false;
    if ~isempty(online_vf_positions)
        islands(c).has_online_vf_source = any(ismember(comp, online_vf_positions));
    end
    islands(c).has_load = false;
    islands(c).has_shunt = false;
    for b = comp
        % mpc.bus columns: 1=ID, 2=type, 3=Pd, 4=Qd, 5=Gs, 6=Bs
        Pd = mpc.bus(b, 3);
        Qd = mpc.bus(b, 4);
        Gs = mpc.bus(b, 5);
        Bs = mpc.bus(b, 6);
        if isfinite(Pd) && Pd ~= 0
            islands(c).has_load = true;
        end
        if isfinite(Qd) && Qd ~= 0
            islands(c).has_load = true;
        end
        if isfinite(Gs) && Gs ~= 0
            islands(c).has_shunt = true;
        end
        if isfinite(Bs) && Bs ~= 0
            islands(c).has_shunt = true;
        end
    end
    islands(c).energized = islands(c).has_online_vf_source || ...
        islands(c).has_load || islands(c).has_shunt;
end

% Sort by minimum internal bus position and assign 1-based island IDs.
min_pos = arrayfun(@(s) min(s.bus_positions), islands);
[~, order] = sort(min_pos);
islands = islands(order);
for k = 1:numel(islands)
    islands(k).island_id = k;
end
end

% =========================================================================
function [comp, visited] = bfs_component(start, adj, visited)
comp = start;
visited(start) = true;
head = 1;
while head <= numel(comp)
    node = comp(head);
    neighbors = find(adj(node, :));
    for n = neighbors
        if ~visited(n)
            visited(n) = true;
            comp(end+1) = n; %#ok<AGROW>
        end
    end
    head = head + 1;
end
end

function s = empty_island()
s = struct('island_id', 0, 'bus_positions', [], 'bus_ids', [], ...
    'energized', false, 'has_online_vf_source', false, ...
    'has_load', false, 'has_shunt', false);
end
