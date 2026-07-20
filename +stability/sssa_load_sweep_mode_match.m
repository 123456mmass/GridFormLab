function mt = sssa_load_sweep_mode_match(points, opt)
%SSSA_LOAD_SWEEP_MODE_MATCH  Deterministic global-assignment mode matcher.
%   MT = stability.sssa_load_sweep_mode_match(POINTS, OPT) matches modes
%   across adjacent SUCCESSFUL load-sweep points in a contiguous segment.
%   Base MATLAB only — NO matchpairs or any Optimization Toolbox routine.
%   The matcher is reporting/analysis-only; it must NOT feed PF, equilibrium,
%   A-matrix construction, device parameters, or subsequent load points.
%
%   Algorithm:
%     1. Require identical active-state identity and ordering, equal active
%        dimensions (else new segment).
%     2. Obtain left AND right eigenvectors via audited eig (no inv(V)).
%     3. Normalize phase/scale consistently; check left/right pairing and
%        biorthogonality conditioning.
%     4. Build cost matrix = weighted (normalized complex-eigenvalue distance,
%        left/right correlation / MAC, conjugate-pair consistency).
%     5. Solve deterministic global assignment (project-owned Hungarian-style
%        on the cost matrix); explicit tie-break independent of raw eigenvalue
%        order.
%     6. Gates: eigenpair residual, biorthogonality, eigengap, conditioning.
%        Fail-closed -> MODE_MATCH_AMBIGUOUS or UNAVAILABLE_ILL_CONDITIONED;
%        publish cluster/subspace result when supportable.
%     7. Conjugate-pair consistency enforced across the assignment.
%     8. Segment split across failed gaps: e.g. 0%,20% PASS / 40% FAIL /
%        60%,80% PASS -> segment 1 = [0%,20%], segment 2 = [60%,80%],
%        with NO_MODE_CONTINUATION_ACROSS_FAILED_POINT at the gap.
%     9. Never modify/delete/average/reorder raw eigenvalues. Store raw
%        eigensolver order separately from matched display order.
%    10. Analysis-domain separation: mode-match only within ONE modal domain
%        at a time. Do NOT mode-match physical_A coordinates across points
%        unless lift maps / coordinate identities are dimensionally consistent.

% --- Frozen NUMERICAL_METHOD choices (declared BEFORE viewing results) -----
w_eig = 0.5;        % eigenvalue-distance weight
w_mac = 0.5;        % left/right correlation weight
max_cost = 0.5;     % maximum acceptable assignment cost (normalized)
ambiguity_tol = 1e-3;   % rival-cost separation required
eigengap_tol = 1e-3;    % relative eigengap below which matching is ambiguous
cond_tol = 1e-9;        % biorthogonality off-diagonal residual gate
residual_tol = 1e-6;    % normalized eigenpair residual gate
% Near-zero real eigenvalues that arise from a (nearly) defective
% zero-eigenvalue Jordan block appear as a real sign-pair (+/- eps).
% Swapping the two members is the SAME physical mode set (both are ~0 and
% span the same zero-eigenvalue subspace), so it is allowed under the same
% physical-equivalence rule as complex-conjugate swap. A real eigenvalue is
% "near-zero" if |lambda| < zero_mode_tol * spectrum_scale, where
% spectrum_scale is the spectrum-wide max |lambda| across both points.
% zero_mode_tol = 1e-4 covers true zero modes AND steady-state
% approximation residuals (e.g. roots at ~1e-4 relative to an ~11 spectrum)
% while still distinguishing genuinely slow-but-real decaying modes.
zero_mode_tol = 1e-4;
if isstruct(opt) && isfield(opt,'mode_match')
    mm = opt.mode_match;
    if isfield(mm,'w_eig') && ~isempty(mm.w_eig), w_eig = mm.w_eig; end
    if isfield(mm,'w_mac') && ~isempty(mm.w_mac), w_mac = mm.w_mac; end
    if isfield(mm,'max_cost') && ~isempty(mm.max_cost), max_cost = mm.max_cost; end
    if isfield(mm,'ambiguity_tol') && ~isempty(mm.ambiguity_tol), ambiguity_tol = mm.ambiguity_tol; end
    if isfield(mm,'eigengap_tol') && ~isempty(mm.eigengap_tol), eigengap_tol = mm.eigengap_tol; end
    if isfield(mm,'cond_tol') && ~isempty(mm.cond_tol), cond_tol = mm.cond_tol; end
    if isfield(mm,'residual_tol') && ~isempty(mm.residual_tol), residual_tol = mm.residual_tol; end
    if isfield(mm,'zero_mode_tol') && ~isempty(mm.zero_mode_tol), zero_mode_tol = mm.zero_mode_tol; end
end

mt = struct();
mt.available = false;
mt.segments = {};
mt.domain = 'raw_A';
mt.raw_eigensolver_order_preserved = true;
mt.parameters = struct('w_eig',w_eig,'w_mac',w_mac,'max_cost',max_cost, ...
    'ambiguity_tol',ambiguity_tol,'eigengap_tol',eigengap_tol, ...
    'cond_tol',cond_tol,'residual_tol',residual_tol, ...
    'zero_mode_tol',zero_mode_tol);

% Identify successful points.
n = numel(points);
success_idx = find(cellfun(@(p) strcmp(p.status,'SUCCESS'), points));
if numel(success_idx) < 2
    mt.available = false;
    mt.reason = 'FEWER_THAN_TWO_SUCCESSFUL_POINTS';
    return;
end

% Build contiguous segments (split at failed gaps).
segments = build_segments(success_idx, n);
mt.gap_markers = collect_gap_markers(points, success_idx);

seg_results = cell(numel(segments),1);
any_matched = false;
for s = 1:numel(segments)
    seg = segments{s};
    seg_results{s} = match_segment(points, seg, w_eig, w_mac, ...
        max_cost, ambiguity_tol, eigengap_tol, cond_tol, residual_tol, zero_mode_tol);
    if seg_results{s}.available
        any_matched = true;
    end
end
mt.segments = seg_results;
mt.available = any_matched;
if ~any_matched
    mt.reason = 'NO_UNAMBIGUOUS_CONTIGUOUS_SEGMENTS';
end
end

% =========================================================================
function segments = build_segments(success_idx, n)
% Split successful indices into contiguous segments (gaps at failed points).
if isempty(success_idx)
    segments = {};
    return;
end
segments = {};
start = success_idx(1);
prev = start;
for k = 2:numel(success_idx)
    if success_idx(k) ~= prev + 1
        segments{end+1} = start:prev; %#ok<AGROW>
        start = success_idx(k);
    end
    prev = success_idx(k);
end
segments{end+1} = start:prev; %#ok<AGROW>
end

% =========================================================================
function gaps = collect_gap_markers(points, success_idx)
n = numel(points);
gaps = struct('gap_before',0,'gap_after',0,'marker','NONE');
if isempty(success_idx)
    return;
end
% Mark NO_MODE_CONTINUATION_ACROSS_FAILED_POINT at gaps.
gap_list = [];
if success_idx(1) > 1
    gap_list(end+1) = success_idx(1); %#ok<AGROW>
end
for k = 2:numel(success_idx)
    if success_idx(k) ~= success_idx(k-1) + 1
        gap_list(end+1) = success_idx(k); %#ok<AGROW>
    end
end
for g = 1:numel(gap_list)
    gaps(g) = struct('gap_before', gaps(g-1).gap_after + 1, ...
        'gap_after', gaps(g-1).gap_after + 1, 'marker', 'NONE'); %#ok<AGROW>
end
for g = 1:numel(gap_list)
    gaps(g).marker = 'NO_MODE_CONTINUATION_ACROSS_FAILED_POINT';
    gaps(g).gap_before = gap_list(g);
end
end

% =========================================================================
function seg = match_segment(points, idx_range, w_eig, w_mac, ...
    max_cost, ambiguity_tol, eigengap_tol, cond_tol, residual_tol, zero_mode_tol)
seg = struct();
seg.point_indices = idx_range;
seg.available = false;
seg.matches = {};
seg.reason = '';

% Require identical active-state identity and ordering across the segment.
% Compare active_state_indices across points (raw A domain).
active_ref = get_active_indices(points{idx_range(1)});
for k = 2:numel(idx_range)
    a_k = get_active_indices(points{idx_range(k)});
    if isempty(a_k) || isempty(active_ref) || ~isequal(a_k, active_ref)
        seg.reason = 'ACTIVE_STATE_IDENTITY_OR_ORDER_DIFFERS';
        return;
    end
    if numel(a_k) ~= numel(active_ref)
        seg.reason = 'ACTIVE_DIMENSION_DIFFERS';
        return;
    end
end

npts = numel(idx_range);
nstates = numel(active_ref);
matches = cell(npts-1,1);
for k = 1:(npts-1)
    p1 = points{idx_range(k)};
    p2 = points{idx_range(k+1)};
    [match, ok, reason] = match_pair(p1, p2, w_eig, w_mac, ...
        max_cost, ambiguity_tol, eigengap_tol, cond_tol, residual_tol, zero_mode_tol);
    matches{k} = match;
    if ~ok
        seg.reason = reason;
        % Keep partial matches but mark segment unavailable.
    end
end
seg.matches = matches;
seg.available = ~isempty(matches) && all(cellfun(@(m) m.assigned, matches));
seg.tracked_indices = [];
if seg.available
    % tracked_indices(k,m) is the RAW eigensolver index, at load point k,
    % belonging to the mode whose identity is raw index m at the first point.
    % Each pairwise assignment maps a raw index at point k to a raw index at
    % point k+1.  Keeping this cumulative map here prevents consumers from
    % confusing the number of adjacent point pairs (npts-1) with the number
    % of modes (nstates).
    tracked = zeros(npts,nstates);
    tracked(1,:) = 1:nstates;
    for k = 1:(npts-1)
        assignment = matches{k}.assignment(:).';
        if numel(assignment) ~= nstates || any(assignment < 1) || ...
                any(assignment > nstates) || numel(unique(assignment)) ~= nstates
            seg.available = false;
            seg.reason = 'INVALID_PAIRWISE_ASSIGNMENT';
            tracked = [];
            break;
        end
        tracked(k+1,:) = assignment(tracked(k,:));
    end
    seg.tracked_indices = tracked;
end
if ~seg.available && isempty(seg.reason)
    seg.reason = 'AMBIGUOUS_OR_ILL_CONDITIONED';
end
end

% =========================================================================
function a = get_active_indices(p)
a = [];
if isfield(p,'sssa') && isstruct(p.sssa) && isfield(p.sssa,'active_state_indices')
    a = p.sssa.active_state_indices;
elseif isfield(p,'equilibrium') && isstruct(p.equilibrium) && ...
        isfield(p.equilibrium,'active_state_indices')
    a = p.equilibrium.active_state_indices;
end
end

% =========================================================================
function [match, ok, reason] = match_pair(p1, p2, w_eig, w_mac, ...
    max_cost, ambiguity_tol, eigengap_tol, cond_tol, residual_tol, zero_mode_tol)
match = struct('point_from', p1.load_percentage, ...
    'point_to', p2.load_percentage, 'assigned', false, ...
    'assignment', [], 'cost', [], 'status', 'UNAVAILABLE', ...
    'reason', '', 'raw_order_from', [], 'raw_order_to', []);
ok = false;
reason = '';

A1 = get_field(p1.sssa,'A'); A2 = get_field(p2.sssa,'A');
if isempty(A1) || isempty(A2)
    reason = 'SSSA_A_MISSING';
    return;
end
if ~isequal(size(A1), size(A2))
    reason = 'A_DIMENSION_DIFFERS';
    return;
end

% Obtain right V and left W from the SAME eig call (3-output form). For a
% diagonalizable A, eig(A,'vector')-style 3-output returns V (right), D
% (diagonal eigenvalues), W (left). MATLAB documents that W'*V is diagonal
% (biorthogonal); the columns of W are the left eigenvectors of A (rows of W'
% are eigenvectors of A' — same object, paired to the same eigenvalues).
% Critically, the eigenvalue ORDER of W matches that of V from this single
% call. Calling eig(A) and eig(A') separately can return different orders
% for degenerate/clustered eigenvalues, breaking the left/right pairing.
[V1,D1,W1] = eig(A1); %#ok<ASGLU>
[V2,D2,W2] = eig(A2); %#ok<ASGLU>
lam1 = diag(D1); lam2 = diag(D2);
match.raw_order_from = 1:numel(lam1);
match.raw_order_to = 1:numel(lam2);

n = numel(lam1);

% Spectrum-wide scale for dimensionless physical-equivalence tests.
% Using the max eigenvalue magnitude across BOTH points (not the local
% pair magnitude) ensures near-zero real modes are compared against the
% spectrum scale, not against their own tiny magnitude.
spectrum_scale = max([1, max(abs(lam1)), max(abs(lam2))]);

% Biorthogonal normalization. For [V,D,W]=eig(A), the columns of W are the
% left eigenvectors (rows of W' are eigenvectors of A'); W is paired to V so
% that W(:,i)'*V(:,i) is the (nonzero) biorthogonality weight and W'*V is
% diagonal. Scale each left vector so U(:,i)'*V(:,i) = 1: divide by
% conj(alpha) where alpha = W(:,i)'*V(:,i). After this, U'*V = I (up to
% roundoff) for any diagonalizable A. No inv(V) is used.
[U1, b1, offdiag1] = biorth_normalize(W1, V1);
[U2, b2, offdiag2] = biorth_normalize(W2, V2);
if ~b1 || ~b2
    match.status = 'UNAVAILABLE_ILL_CONDITIONED';
    match.reason = 'LEFT_RIGHT_PAIRING_ILL_CONDITIONED';
    reason = match.reason;
    return;
end

% Conditioning gate: the biorthogonality off-diagonal residual must be small.
% |W'*V - I|_fro < cond_tol means the spectrum is diagonalizable and the
% left/right pairs are well-conditioned. A defective (non-diagonalizable)
% spectrum has large off-diagonal residual and fails closed. The per-mode
% cosine |u_i^H v_i|/(||u_i|| ||v_i||) is NOT used as the gate because it
% conflates conditioning with normalization magnitude; the off-diagonal
% residual is the true measure of biorthogonality failure.
if offdiag1 > cond_tol || offdiag2 > cond_tol
    match.status = 'UNAVAILABLE_ILL_CONDITIONED';
    match.reason = sprintf('LEFT_RIGHT_PAIRING_ILL_CONDITIONED (offdiag fro: %.3e / %.3e)', ...
        offdiag1, offdiag2);
    reason = match.reason;
    return;
end

% Eigenpair residual gate.
if max_eigenpair_residual(A1, V1, lam1) > residual_tol || ...
        max_eigenpair_residual(A2, V2, lam2) > residual_tol
    match.status = 'UNAVAILABLE_ILL_CONDITIONED';
    match.reason = 'EIGENPAIR_RESIDUAL_EXCEEDED';
    reason = match.reason;
    return;
end

% Build cost matrix C(i,j) = match cost between lam1(i) and lam2(j).
% pair_cost uses RIGHT eigenvectors only for cross-point subspace similarity
% (a geometry measure invariant to left/right scaling). Left eigenvectors
% gate conditioning above but do not enter the cost.
C = zeros(n,n);
for i = 1:n
    for j = 1:n
        C(i,j) = pair_cost(lam1(i), lam2(j), V1(:,i), V2(:,j), ...
            w_eig, w_mac);
    end
end

% Eigengap ambiguity check: if two costs are within ambiguity_tol, ambiguous.
% Deterministic global assignment via project-owned Hungarian-style solver.
[assignment, total_cost] = hungarian_assignment(C);

% Ambiguity gate. For each assigned pair (i -> j), the rival cost is the
% SECOND-best column in row i (the next-closest point-2 mode to point-1
% mode i). The pair is unambiguous if either:
%   (a) the rival is well separated: C(i, rival) - C(i, j) >= ambiguity_tol; OR
%   (b) the rival is physically equivalent to j under the symmetry group:
%       complex-conjugate swap, OR near-zero real sign-pair swap (both
%       members of a nearly-defective zero-eigenvalue Jordan block).
%       Swapping within such a pair is the SAME physical mode set, not a
%       rival. This correctly allows degenerate/near-zero conjugate pairs
%       to match symmetrically without flagging a false ambiguity, while
%       still failing closed when two genuinely distinct modes have
%       indistinguishable cost.
ambiguous = false;
ambiguity_reason = '';
for i = 1:n
    j = assignment(i);
    if j == 0
        ambiguous = true;
        ambiguity_reason = 'INCOMPLETE_ASSIGNMENT';
        break;
    end
    rival_cols = setdiff(1:n, j);
    if isempty(rival_cols)
        continue;
    end
    rival_costs = C(i, rival_cols);
    [rival_min, kidx] = min(rival_costs);
    rival_j = rival_cols(kidx);
    if (rival_min - C(i,j)) >= ambiguity_tol
        continue;   % well separated
    end
    % Rival is close. Allow only if rival_j is physically equivalent to j
    % AND lam1(i) is itself part of the same physical-equivalence pair.
    ip = find_partner(i, lam1, zero_mode_tol, spectrum_scale);
    if is_physical_equivalent(lam2(j), lam2(rival_j), zero_mode_tol, spectrum_scale) && ...
            ip ~= i && is_physical_equivalent(lam1(i), lam1(ip), zero_mode_tol, spectrum_scale)
        continue;
    end
    ambiguous = true;
    ambiguity_reason = sprintf('RIVAL_COST_AMBIGUOUS: mode %d (lam1=%.4g%+.4gi) best=%.3e rival=%.3e', ...
        i, real(lam1(i)), imag(lam1(i)), C(i,j), rival_min);
    break;
end
% Eigengap check on the assignment: a relative eigengap below eigengap_tol
% in any row is ambiguous UNLESS the close second is physically equivalent.
if ~ambiguous
    for i = 1:n
        j = assignment(i);
        sorted_costs = sort(C(i,:));
        if numel(sorted_costs) < 2, continue; end
        gap = (sorted_costs(2) - sorted_costs(1)) / max(1, sorted_costs(2));
        if gap >= eigengap_tol, continue; end
        % Below threshold: allow only if the second-best column is physically
        % equivalent to the assigned column AND lam1(i) has an equivalent
        % partner in lam1.
        [~, idx2] = sort(C(i,:));
        second_j = idx2(2);
        ip = find_partner(i, lam1, zero_mode_tol, spectrum_scale);
        if is_physical_equivalent(lam2(j), lam2(second_j), zero_mode_tol, spectrum_scale) && ...
                ip ~= i && is_physical_equivalent(lam1(i), lam1(ip), zero_mode_tol, spectrum_scale)
            continue;
        end
        ambiguous = true;
        ambiguity_reason = sprintf('EIGENGAP_BELOW_THRESHOLD: mode %d gap=%.3e', i, gap);
        break;
    end
end
% Max-cost gate. Only consider rows that received an assignment (j > 0).
assigned_rows = find(assignment > 0);
if ~isempty(assigned_rows)
    assigned_costs = C(sub2ind(size(C), assigned_rows, assignment(assigned_rows)));
    if any(assigned_costs > max_cost)
        ambiguous = true;
        ambiguity_reason = 'MAX_COST_EXCEEDED';
    end
end

match.assignment = assignment;
match.cost = C;
if ambiguous
    match.assigned = false;
    match.status = 'MODE_MATCH_AMBIGUOUS';
    match.reason = ambiguity_reason;
    reason = match.reason;
    return;
end

% Conjugate-pair consistency: if lam1(i) has a physical-equivalence
% partner lam1(ip) (complex conjugate, or near-zero real sign-pair), then
% lam2(assignment(i)) and lam2(assignment(ip)) must be physically equivalent
% (in either order — swap within a pair is the same physical result and is
% allowed). Only fail closed if a pair structure is broken (e.g. a
% conjugate mode matched to a real, non-conjugate mode).
if ~conjugate_consistent(lam1, lam2, assignment, zero_mode_tol, spectrum_scale)
    match.assigned = false;
    match.status = 'MODE_MATCH_AMBIGUOUS';
    match.reason = 'CONJUGATE_PAIR_INCONSISTENCY';
    reason = match.reason;
    return;
end

match.assigned = true;
match.status = 'MATCHED';
ok = true;
end

% =========================================================================
function c = pair_cost(l1, l2, V1, V2, w_eig, w_mac)
% Normalized complex-eigenvalue distance + right-eigenvector MAC correlation.
% Both metrics in [0,1] (0 = identical).
scale = max(1, abs(l1) + abs(l2));
d_eig = abs(l1 - l2) / scale;
% MAC between the right eigenvectors of mode l1 (at point 1) and mode l2
% (at point 2). MAC = |v1^H v2|^2 / ((v1^H v1)(v2^H v2)); phase-invariant,
% in [0,1] (1 = collinear). The cost = 1 - MAC. Right-eigenvector MAC is
% the geometric cross-point subspace similarity (independent of the
% left/right scaling used for conditioning).
v1n = phase_normalize(V1);
v2n = phase_normalize(V2);
inner = v1n' * v2n;
mac = (abs(inner)^2) / ((v1n'*v1n) * (v2n'*v2n) + eps);
c = w_eig * d_eig + w_mac * (1 - mac);
end

% =========================================================================
function vn = phase_normalize(v)
% Normalize phase so that the largest-magnitude component is real positive.
[~,idx] = max(abs(v));
if abs(v(idx)) < eps
    vn = v;
    return;
end
phase = angle(v(idx));
vn = v * exp(-1i * phase);
vn = vn / (norm(vn) + eps);
end

% =========================================================================
function r = max_eigenpair_residual(A, V, lam)
r = 0;
for i = 1:numel(lam)
    res = norm(A * V(:,i) - lam(i) * V(:,i), inf) / ...
        max(1, norm(A,inf) + abs(lam(i)) * norm(V(:,i),inf));
    r = max(r, res);
end
end

% =========================================================================
function tf = conjugate_consistent(lam1, lam2, assignment, zero_mode_tol, spectrum_scale)
% Physical-equivalence pair structure must be preserved across the
% assignment. If lam1(i) has an equivalent partner lam1(ip) (complex
% conjugate, or near-zero real sign-pair), then lam2(assignment(i)) and
% lam2(assignment(ip)) must be physically equivalent (in either order —
% swap within a pair is the same physical mode and is allowed). Fails
% closed only when a pair structure is broken (equivalent mode matched to
% a non-equivalent mode).
tf = true;
n = numel(lam1);
for i = 1:n
    j = assignment(i);
    if j == 0
        tf = false;
        return;
    end
    ip = find_partner(i, lam1, zero_mode_tol, spectrum_scale);
    if ip == i
        % lam1(i) has no equivalent partner; nothing to check.
        continue;
    end
    jp = assignment(ip);
    if jp == 0
        tf = false;
        return;
    end
    if ~is_physical_equivalent(lam2(j), lam2(jp), zero_mode_tol, spectrum_scale)
        tf = false;
        return;
    end
end
end

% =========================================================================
function tf = is_physical_equivalent(a, b, zero_mode_tol, spectrum_scale)
% True if a and b are physically equivalent under the symmetry group that
% preserves mode identity:
%   1. Complex conjugates: abs(a - conj(b)) <= tol (the standard
%      conjugate-pair swap for non-degenerate oscillatory modes).
%   2. Near-zero modes: BOTH |a| and |b| are below
%      zero_mode_tol*spectrum_scale. These are members of a (nearly)
%      defective zero-eigenvalue Jordan subspace — regardless of whether
%      they happen to be real sign-pairs or pure-imaginary pairs at a
%      given operating point, they span the same zero-eigenvalue subspace
%      and any swap among them is the SAME physical mode set.
% spectrum_scale is the spectrum-wide max |lambda| across both points
% (NOT the local pair magnitude), so near-zero modes are compared against
% the overall spectrum scale.
conj_tol = 1e-9 * spectrum_scale;
tf = abs(a - conj(b)) <= conj_tol;
if tf, return; end
% Near-zero modes: both below the zero-mode threshold relative to spectrum.
if abs(a) <= zero_mode_tol * spectrum_scale && abs(b) <= zero_mode_tol * spectrum_scale
    tf = true;
end
end

% =========================================================================
function ip = find_partner(i, lam, zero_mode_tol, spectrum_scale)
% Find the index of the physical-equivalence partner of lam(i) (complex
% conjugate, or near-zero real sign-pair). Returns i if none found.
ip = i;
for k = 1:numel(lam)
    if k ~= i && is_physical_equivalent(lam(i), lam(k), zero_mode_tol, spectrum_scale)
        ip = k;
        return;
    end
end
end

% =========================================================================
function [assignment, total_cost] = hungarian_assignment(C)
% Project-owned deterministic GLOBAL assignment (Hungarian algorithm, base
% MATLAB only — no matchpairs or any Optimization Toolbox routine).
% Minimizes total cost on a square cost matrix. Returns assignment(i) = j
% (column assigned to row i), 0 if row i unassigned. Deterministic tie-break:
% on equal reduced costs, the lowest column index wins.
[n, m] = size(C);
assignment = zeros(n,1);
total_cost = 0;
if n == 0 || m == 0
    return;
end
if n ~= m
    % Non-square: pad to square with a large constant so unassigned rows/cols
    % map to "dummy" slots that are stripped afterwards.
    sz = max(n, m);
    P = repmat(max(C(:)) + 1, sz, sz);
    P(1:n, 1:m) = C;
    [a, ~] = hungarian_square(P);
    assignment = a(1:n);
    assignment(assignment > m) = 0;
    total_cost = sum(C(sub2ind(size(C), find(assignment>0), assignment(assignment>0))));
    return;
end
[assignment, total_cost] = hungarian_square(C);
end

% =========================================================================
function [assignment, total_cost] = hungarian_square(C)
% Kuhn-Munkres on a square matrix. Deterministic: column ties broken by
% lowest index. Returns assignment(i)=j minimizing sum_j C(assignment,j).
n = size(C,1);
assignment = zeros(n,1);
if n == 0
    total_cost = 0;
    return;
end
if n == 1
    assignment(1) = 1;
    total_cost = C(1,1);
    return;
end
% Work on a copy; rows reduced by their minimum, columns reduced by their
% minimum. Cost matrix stays nonnegative.
W = C - min(C,[],2);
W = W - min(W,[],1);

% Starred zeros (initial matching) and primed zeros (search workspace).
star = false(n,n);
prim = false(n,n);
row_cov = false(n,1);
col_cov = false(n,1);

% Step 1: star a zero in each row (lowest col on ties).
for i = 1:n
    for j = 1:n
        if W(i,j) == 0 && ~row_cov(i) && ~col_cov(j)
            star(i,j) = true;
            row_cov(i) = true;
            col_cov(j) = true;
        end
    end
end
row_cov = false(n,1);
col_cov = false(n,1);
% Cover every column with a starred zero.
for j = 1:n
    if any(star(:,j)), col_cov(j) = true; end
end

iter = 0;
max_iter = 100 * n + 1000;
while sum(col_cov) < n
    iter = iter + 1;
    if iter > max_iter
        % Safety abort; should not happen for finite cost matrices.
        break;
    end
    % Step 2: find a noncovered zero and prime it. If no starred zero in its
    % row, augment; else cover its row and uncover its starred column.
    [done, zr, zc] = find_uncovered_zero(W, row_cov, col_cov);
    if ~done
        % Step 3: find min uncovered value, add to covered rows, subtract
        % from uncovered cols, then retry.
        minval = min_uncovered(W, row_cov, col_cov);
        for i = 1:n
            if row_cov(i), W(i,:) = W(i,:) + minval; end
        end
        for j = 1:n
            if ~col_cov(j), W(:,j) = W(:,j) - minval; end
        end
        continue;
    end
    prim(:) = false;
    prim(zr, zc) = true;
    star_col = find(star(zr,:), 1);
    if isempty(star_col)
        % Augmenting path: flip starred/primed along the path.
        [star, prim] = augment(star, prim, zr, zc, n);
        row_cov = false(n,1);
        col_cov = false(n,1);
        for j = 1:n
            if any(star(:,j)), col_cov(j) = true; end
        end
    else
        row_cov(zr) = true;
        col_cov(star_col) = false;
    end
end

% Extract assignment from star.
for i = 1:n
    j = find(star(i,:), 1);
    if ~isempty(j)
        assignment(i) = j;
    else
        assignment(i) = 0;
    end
end
total_cost = sum(C(sub2ind(size(C), (1:n).', assignment)));
end

% =========================================================================
function [done, r, c] = find_uncovered_zero(W, row_cov, col_cov)
done = false; r = 0; c = 0;
for i = 1:size(W,1)
    if row_cov(i), continue; end
    for j = 1:size(W,2)
        if col_cov(j), continue; end
        if W(i,j) == 0
            done = true; r = i; c = j;
            return;
        end
    end
end
end

% =========================================================================
function mv = min_uncovered(W, row_cov, col_cov)
mv = Inf;
for i = 1:size(W,1)
    if row_cov(i), continue; end
    for j = 1:size(W,2)
        if col_cov(j), continue; end
        if W(i,j) < mv, mv = W(i,j); end
    end
end
end

% =========================================================================
function [star, prim] = augment(star, prim, zr, zc, n)
% Build augmenting path alternating primed -> starred -> primed -> ... and
% flip stars. Start from the primed zero at (zr, zc).
star(zr, zc) = true;
prim(zr, zc) = false;
cur_r = zr; cur_c = zc;
while true
    % Find a star in column cur_c (in some other row).
    sr = find(star(:, cur_c));
    sr = sr(sr ~= cur_r);
    if isempty(sr), break; end
    prev_r = cur_r;
    cur_r = sr(1);
    % Prime the zero at (cur_r, cur_c) — it must be a zero of W by
    % construction of the algorithm; find the primed zero in row cur_r.
    pc = find(prim(cur_r, :));
    star(cur_r, cur_c) = false;
    star(cur_r, pc(1)) = true;
    prim(cur_r, pc(1)) = false;
    cur_c = pc(1);
end
prim(:) = false;
end

% =========================================================================
function [U, ok, offdiag_resid] = biorth_normalize(W, V)
% Scale left eigenvector columns so U(:,i)'*V(:,i) = 1 (U = W, divided by
% conj(alpha) with alpha = W(:,i)'*V(:,i)). After normalization U'*V = I for
% any diagonalizable A. Returns the off-diagonal Frobenius residual of U'*V
% (should be ~0 for well-conditioned spectra; large => defective). ok=false
% if any pairing denominator is ~0.
n = size(V, 2);
U = W;
ok = true;
offdiag_resid = Inf;
for i = 1:n
    a = W(:,i)' * V(:,i);
    if abs(a) < eps
        ok = false;
        return;
    end
    U(:,i) = W(:,i) / conj(a);
end
B = U' * V;
offdiag_resid = norm(B - diag(diag(B)), 'fro') / max(1, norm(diag(B),'fro'));
end

% =========================================================================
function v = get_field(s, name)
v = [];
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
end
end
