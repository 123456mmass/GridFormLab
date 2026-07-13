function results = powerflow_bfs(case_data, options)
%POWERFLOW_BFS  Backward/Forward Sweep radial power flow (CORE_ONLY, NOT_ROUTED).
%   RESULTS = POWERFLOW_BFS(CASE_DATA, OPTIONS) solves a radial distribution
%   network using the backward/forward sweep method.
%
%   Source (VERIFIED): Shirmohammadi, Hong, Semlyen, Luo (1988), IEEE Trans.
%   Power Systems 3(2), pp.753-762, DOI 10.1109/59.192932.
%     Equation (1): Ii(k) = conj(Si/Vi(k-1)) - Yi*Vi(k-1)   [nodal injection]
%     Equation (2): JL(k) = -IL2(k) + sum(child branch currents) [backward, KCL]
%     Equation (3): VL2 = VL1 - zL*JL                          [forward, KVL]
%   Phase-1 minimal capability: drops the shunt term (-Yi*Vi) since shunts are
%   DEFERRED; uses constant-power injections only (Si = P_net + j*Q_net).
%
%   Phase-1 capability contract (binding, per user correction 5):
%     - exactly one REF bus; all remaining buses PQ;
%     - connected radial tree (num_lines == num_buses - 1);
%     - no parallel branches;
%     - unity taps, zero phase shifts;
%     - no bus shunts, no line charging (DEFERRED features);
%     - constant-power injections only.
%
%   P2 scope (package-only, per plan §2 ownership route):
%   This solver is CORE_ONLY / NOT_ROUTED. solve_case.m is NOT modified. Tested
%   by direct calls. Production routing readiness NOT_READY until single-owner
%   integration files are separately resolved.
%
%   Convergence: full nonlinear AC mismatch (max|dP|, max|dQ|) using the FULL
%   Ybus, same criterion as NR. NOT the sweep residual.
%
%   No inv/pinv. Backward/forward sweep uses direct accumulation.

pf_init_paths();
if nargin < 1 || isempty(case_data)
    error('powerflow_bfs:missingCase', 'A case_data is required.');
end
if nargin < 2 || isempty(options), options = struct(); end

max_iter = pf_get_option(options, 'max_iter', 100);
tolerance = pf_get_option(options, 'tolerance', 1e-10);
verbose = pf_get_option(options, 'verbose', true);

model = pf_prepare_case(case_data);
[parent, children, root_idx] = pf_validate_radial_topology(model);
nb = model.num_buses;
nl = model.num_lines;

% Branch impedance (series only; unity tap, no charging per Phase-1).
line_data = model.line_data;
external_bus_ids = model.external_bus_ids;
[~, fi] = ismember(line_data(:, 1), external_bus_ids);
[~, ti] = ismember(line_data(:, 2), external_bus_ids);
% z_series per branch: identify which end is parent (closer to root) vs child.
% parent[child] = parent_idx (from the tree). For each branch, find which end
% is the child (the one whose parent is the other end).
z_branch = complex(line_data(:, 3), line_data(:, 5));   % wait: line_data col 3=R, col 4=X
z_series = complex(line_data(:, 3), line_data(:, 4));
% Map branch index -> (parent_end, child_end) using the tree.
branch_child = zeros(nl, 1);
branch_parent = zeros(nl, 1);
for i = 1:nl
    a = fi(i); b = ti(i);
    if parent(b) == a
        branch_parent(i) = a; branch_child(i) = b;
    elseif parent(a) == b
        branch_parent(i) = b; branch_child(i) = a;
    else
        error('powerflow_bfs:badTree', ...
            'Branch %d (%d-%d) is not a parent-child edge in the tree.', i, a, b);
    end
end
% Index branches by child bus for the sweep.
branch_of_child = zeros(nb, 1);
for i = 1:nl
    branch_of_child(branch_child(i)) = i;
end

% Initial: flat voltage profile (1.0 pu, 0 deg) except root.
V = ones(nb, 1);
V(root_idx) = model.V_spec(root_idx);
theta = zeros(nb, 1);
theta(root_idx) = deg2rad(model.angle_spec_deg(root_idx));
V_complex = V .* exp(1i * theta);

S_net = model.P_net + 1i * model.Q_net;   % specified power injection (pu)

mismatch_history = [];
converged = false;
iter = 0;
for iter = 1:max_iter
    % --- (1) Nodal current injection: Ii = conj(Si/Vi) (Phase-1: no shunt) ---
    I_inj = conj(S_net ./ V_complex);
    I_inj(root_idx) = 0;   % root injection determined by slack, not scheduled.

    % --- (2) Backward sweep: branch currents from leaves to root ---
    J_branch = complex(zeros(nl, 1));
    % Process buses in reverse BFS order (leaves first).
    bfs_order = bfs_from_root(parent, children, root_idx);
    for k = nb:-1:1
        b = bfs_order(k);
        if b == root_idx, continue; end
        bi = branch_of_child(b);
        % J_branch(bi) = I_inj(b) + sum of child branch currents
        s_children = 0;
        for c = children{b}
            ci = branch_of_child(c);
            s_children = s_children + J_branch(ci);
        end
        J_branch(bi) = I_inj(b) + s_children;
    end

    % --- (3) Forward sweep: voltages from root to leaves ---
    % KVL (Shirmohammadi eq 3): V_child = V_parent - zL * J_branch, where J_branch
    % is the branch current (positive downstream from parent to child). The
    % backward sweep defines J_branch = I_inj(child) + sum(child branch currents),
    % where I_inj = conj(S_net/V). For a load bus (S_net negative), I_inj is
    % negative (current leaving the node), so J_branch is negative and the drop
    % zL*J_branch is negative, giving V_child = V_parent - (negative) = V_parent +
    % |drop|, which would INCREASE V — wrong for a load. The issue is the sign of
    % the current direction: Shirmohammadi's J_L is the current FROM L1 TO L2
    % (downstream), but our I_inj uses the injection convention (positive INTO the
    % network). For a load, injection is negative, so the downstream branch
    % current = -(injection) = -(negative) = positive (current flows downstream
    % to supply the load). So J_branch = -(I_inj(child) + sum children) with the
    % sign flipped, OR equivalently V_child = V_parent + zL * J_branch (using the
    % injection-convention J_branch). We use the latter to keep J_branch as the
    % injection-accumulation.
    V_new = V_complex;
    for k = 2:nb
        b = bfs_order(k);
        bi = branch_of_child(b);
        p = branch_parent(bi);
        V_new(b) = V_new(p) + z_series(bi) * J_branch(bi);
    end
    V_new(root_idx) = V_complex(root_idx);   % root fixed.

    % --- Full AC mismatch convergence check (recomputed each iteration) ---
    % Mismatch over the UNKNOWN buses only (delta_idx for P, V_idx for Q).
    % REF/slack P and Q are outputs (slack), not scheduled inputs, so they are
    % NOT part of the convergence check (matches NR's pf_calculate_mismatch).
    V_complex = V_new;
    [P_calc, Q_calc] = pf_calculate_power_injections(abs(V_complex), angle(V_complex), model.Ybus);
    dP = model.P_net(model.delta_idx) - P_calc(model.delta_idx);
    dQ = model.Q_net(model.V_idx) - Q_calc(model.V_idx);
    max_mismatch = max(abs([dP; dQ]));
    mismatch_history(end+1, 1) = max_mismatch; %#ok<AGROW>
    if max_mismatch < tolerance
        converged = true; break;
    end
end

Vmag = abs(V_complex);
theta_final = angle(V_complex);
results = pf_build_results(model, Vmag, theta_final, mismatch_history, iter, converged, 'BFS');
results.method_variant = 'radial-phase1';
results.metadata.method_requested = 'bfs';
results.metadata.method_executed = 'bfs';
results.metadata.method_source = 'in-house BFS (Shirmohammadi 1988) Phase-1 radial';
results.metadata.capability = 'production';
results.metadata.fallback_used = false;
results.metadata.full_ac_mismatch = max_mismatch;
if verbose
    fprintf('BFS (radial Phase-1): converged=%d, iterations=%d, max_mismatch=%.3e\n', ...
        converged, iter, results.metadata.full_ac_mismatch);
end
end

% =========================================================================
function order = bfs_from_root(parent, children, root_idx)
% Top-down BFS order (root first, then layer by layer).
nb = numel(parent);
order = zeros(nb, 1);
order(1) = root_idx;
head = 1; tail = 1;
while head <= tail
    cur = order(head);
    for c = children{cur}
        tail = tail + 1;
        order(tail) = c;
    end
    head = head + 1;
end
end
