function [parent, children, root_idx] = pf_validate_radial_topology(model)
%PF_VALIDATE_RADIAL_TOPOLOGY  Validate Phase-1 radial topology (fail-closed).
%   [PARENT, CHILDREN, ROOT_IDX] = PF_VALIDATE_RADIAL_TOPOLOGY(MODEL) validates
%   that the network satisfies the Phase-1 minimal radial capability contract and
%   returns the tree structure for the backward/forward sweep.
%
%   Source (VERIFIED): Shirmohammadi, Hong, Semlyen, Luo (1988), IEEE Trans.
%   Power Systems 3(2), pp.753-762, DOI 10.1109/59.192932. The radial sweep
%   (Solution Method p.754) requires a single voltage source at the root node
%   and a tree topology (n nodes, b=n-1 branches).
%
%   Phase-1 minimal capability contract (binding, per user correction 5):
%     - exactly one REF bus (type 1);
%     - ALL remaining buses are PQ (type 3) — any PV bus fails closed;
%     - connected radial tree: num_lines == num_buses - 1 (no mesh);
%     - no parallel branches (same from-to pair);
%     - all taps unity and all phase shifts zero (non-unity/complex taps DEFERRED);
%     - no bus shunts and no line charging (DEFERRED_SOURCE_REQUIRED).
%
%   DEFERRED features are rejected with clear error identifiers so they cannot
%   be mistaken for supported behavior. These are fail-closed REJECTION tests,
%   NOT supported-feature tests (per user correction 4).
%
%   Outputs:
%     PARENT   : (num_buses x 1) parent bus index for each bus (root = 0)
%     CHILDREN : cell array (num_buses x 1) of child bus index lists per bus
%     ROOT_IDX : the root (REF) bus index

bus_data = model.bus_data;
line_data = model.line_data;
nb = model.num_buses;
nl = model.num_lines;
bus_type = model.bus_type;

% --- exactly one REF bus ---
ref_idx = find(bus_type == 1);
if numel(ref_idx) ~= 1
    error('pf_validate_radial_topology:multiRef', ...
        'Phase-1 BFS requires exactly one REF bus; found %d.', numel(ref_idx));
end
root_idx = ref_idx(1);

% --- all remaining buses must be PQ (type 3); PV buses deferred ---
pv_idx = find(bus_type == 2);
if ~isempty(pv_idx)
    error('pf_validate_radial_topology:pvUnsupportedDeferred', ...
        ['Phase-1 BFS supports PQ buses only. PV buses (internal idx: %s, ' ...
        'external IDs: %s) are DEFERRED_SOURCE_REQUIRED until their exact ' ...
        'sweep equations are sourced and tested. Use newton_raphson or ' ...
        'fdpf_xb/fdpf_bx for PV buses.'], mat2str(pv_idx.'), ...
        mat2str(model.external_bus_ids(pv_idx).'));
end

% --- tree: num_lines == num_buses - 1 ---
if nl ~= nb - 1
    error('pf_validate_radial_topology:meshedUnsupported', ...
        ['Phase-1 BFS requires a radial tree: num_lines == num_buses - 1. ' ...
        'Got num_lines=%d, num_buses=%d (meshed). IEEE14 and similar meshed ' ...
        'transmission cases are UNSUPPORTED_FAIL_CLOSED. Use newton_raphson ' ...
        'or fdpf_xb/fdpf_bx.'], nl, nb);
end

% --- no parallel branches (same from-to pair, either direction) ---
external_bus_ids = bus_data(:, 1);
[~, fi] = ismember(line_data(:, 1), external_bus_ids);
[~, ti] = ismember(line_data(:, 2), external_bus_ids);
edge_key = sort([fi, ti], 2);   % canonical undirected key
[uniq_key, ~, ic] = unique(edge_key, 'rows');
if size(uniq_key, 1) ~= nl
    error('pf_validate_radial_topology:parallelBranchUnsupported', ...
        'Phase-1 BFS rejects parallel branches (same from-to pair). Found duplicate edges.');
end

% --- unity taps and zero phase shifts ---
tap_ratios = line_data(:, 6);
tap_ratios(tap_ratios == 0) = 1;   % normalize zero -> unity
if any(abs(tap_ratios - 1) > 1e-12)
    nonunity = find(abs(tap_ratios - 1) > 1e-12);
    error('pf_validate_radial_topology:complexTapDeferred', ...
        ['Phase-1 BFS supports unity taps only. Non-unity/complex taps on ' ...
        'lines %s are DEFERRED_SOURCE_REQUIRED until their exact sweep ' ...
        'equations are sourced and tested.'], mat2str(nonunity.'));
end
phase_shifts = line_data(:, 7);
if any(abs(phase_shifts) > 1e-12)
    ps_viol = find(abs(phase_shifts) > 1e-12);
    error('pf_validate_radial_topology:phaseShifterDeferred', ...
        ['Phase-1 BFS supports zero phase shifts only. Phase shifters on ' ...
        'lines %s are DEFERRED_SOURCE_REQUIRED.'], mat2str(ps_viol.'));
end

% --- no bus shunts, no line charging (Phase-1) ---
if any(model.G_shunt ~= 0) || any(model.B_shunt ~= 0)
    error('pf_validate_radial_topology:shuntDeferred', ...
        'Phase-1 BFS rejects bus shunts (G_shunt/B_shunt). DEFERRED_SOURCE_REQUIRED.');
end
if any(line_data(:, 5) ~= 0)
    b_half_viol = find(line_data(:, 5) ~= 0);
    error('pf_validate_radial_topology:lineChargingDeferred', ...
        ['Phase-1 BFS rejects line charging (B_half). Lines %s have B_half != 0; ' ...
        'DEFERRED_SOURCE_REQUIRED.'], mat2str(b_half_viol.'));
end

% --- build tree via BFS from root, verify connectivity + no cycles ---
parent = zeros(nb, 1);
children = cell(nb, 1);
% adjacency
adj = cell(nb, 1);
for i = 1:nl
    a = fi(i); b = ti(i);
    adj{a} = [adj{a}, b];
    adj{b} = [adj{b}, a];
end
visited = false(nb, 1);
queue = root_idx;
visited(root_idx) = true;
parent(root_idx) = 0;
order = root_idx;
while ~isempty(queue)
    cur = queue(1);
    queue(1) = [];
    for nb_child = adj{cur}
        if ~visited(nb_child)
            visited(nb_child) = true;
            parent(nb_child) = cur;
            children{cur} = [children{cur}, nb_child];
            queue = [queue, nb_child]; %#ok<AGROW>
            order = [order, nb_child]; %#ok<AGROW>
        end
    end
end
if ~all(visited)
    disc = find(~visited);
    error('pf_validate_radial_topology:disconnectedNetwork', ...
        ['Phase-1 BFS requires a connected network. Disconnected buses ' ...
        '(internal idx: %s) found.'], mat2str(disc.'));
end
% No cycles: a connected graph with n-1 edges is a tree (verified by tree count
% + connectivity; the BFS would have detected a back edge only if a cycle
% existed in a graph with >= n edges, which we already rejected).
end
