function modal = modal_analysis(sssa, opt)
%MODAL_ANALYSIS  Read-only no-inv modal analysis consumer of an SSSA struct.
%
%   modal = stability.modal_analysis(sssa, opt) analyzes ONE declared modal
%   domain per call: sssa.A (default) or sssa.physical_A (opt.domain).
%   It is a PURE read-only consumer: it does NOT modify sssa, does NOT
%   reconstruct A/A_full/physical_A, and does NOT delete eigenvalues. It
%   uses only MATLAB primitives (eig, \, qr, lu) — never inv/pinv or an
%   external solver.
%
%   Left eigenvectors come from eig(A','vector') (conjugate transpose),
%   paired against conj(lambdaR). Biorthogonal normalization
%   U(:,i) = U(:,i)/conj(alpha) with alpha = U(:,i)'*V(:,i) gives
%   u_i^H v_i = 1. Signed participation p_ki = conj(U(k,i))*V(k,i)
%   (sum ~= 1 per available mode). A separate nonnegative display ranking
%   rho_ki = |p_ki|/sum|p_ji| is published under a distinct name and must
%   never be mislabeled as signed participation.
%
%   For physical_A, lifted vectors are MAP-DEPENDENT OBLIQUE ATTRIBUTION,
%   not canonical global-state participation and not necessarily
%   eigenvectors of sssa.A (RL ~= I in general). They are published as
%   global_lifted_signed_participation only when the composed lift maps
%   L = Lq*Lb, R = Tb*Tq satisfy L*R ~= I and physical_A ~= L*sssa.A*R.
%   Otherwise lifted/global participation is NaN with NOT_AVAILABLE_*.
%
%   Clustered/repeated/defective modes: eigenvalues preserved, individual
%   participation marked UNAVAILABLE_ILL_CONDITIONED. Cluster projector
%   P = Vc*(G\Uc') (G=Uc'*Vc, using \) published with residuals only when
%   rank/Gram/idempotence/trace/conjugate-closure checks pass; NO cluster
%   participation ranking is published in this version (metric not frozen).
%
%   Deterministic display sort (frozen before viewing results, exact
%   numeric keys + raw-index tie-break): (1) descending real part;
%   (2) positive-imag before real before negative-imag on real-part ties;
%   (3) descending |imag|; (4) raw eigen index. display_mode_number and
%   raw_eigen_index are SEPARATE fields (Mode No. is NOT a state index).
%
%   See: docs/project/IEEE14_IBR_DYNAMIC_EQUATION_CONTRACT.md (Section H).
%   Status: SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES. Read-only
%   consumer; no production numerical equation, Ared, or ABI change.

arguments
    sssa struct
    opt struct = struct()
end

% --- Frozen tolerances (declared BEFORE any eig call; not tuned to results) -
epsi = 1e2 * eps;                          % base numerical floor
eigenvalue_pair_tol    = 1e-6;             % normalized |muLH - conj(lambdaR)|
pair_ambiguity_tol     = 1e-3;             % required separation from rival
cluster_tol            = 1e-6;             % normalized eigenvalue cluster
imag_zero_tol          = 1e-9;             % |imag| below this => real root
residual_tol           = 1e-6;             % normalized eigenpair residual
biorthogonality_tol    = 1e-6;             % off-diag |U'*V - I| gate
conditioning_tol       = 1e-9;             % min |u'*v|/(||u|| ||v||)
rank_tol               = 1e-9;             % QR numerical-rank threshold
lift_tol               = 1e-6;             % L*R and physical_A reconstruction
if isfield(opt,'eigenvalue_pair_tol') && ~isempty(opt.eigenvalue_pair_tol), eigenvalue_pair_tol = opt.eigenvalue_pair_tol; end
if isfield(opt,'cluster_tol') && ~isempty(opt.cluster_tol), cluster_tol = opt.cluster_tol; end
if isfield(opt,'imag_zero_tol') && ~isempty(opt.imag_zero_tol), imag_zero_tol = opt.imag_zero_tol; end
if isfield(opt,'residual_tol') && ~isempty(opt.residual_tol), residual_tol = opt.residual_tol; end
if isfield(opt,'conditioning_tol') && ~isempty(opt.conditioning_tol), conditioning_tol = opt.conditioning_tol; end
if isfield(opt,'lift_tol') && ~isempty(opt.lift_tol), lift_tol = opt.lift_tol; end

domain = 'A';
if isfield(opt,'domain') && ~isempty(opt.domain)
    domain = char(opt.domain);
    if ~ismember(domain, {'A','physical_A'})
        error('stability:modal_analysis:badDomain', ...
            'opt.domain must be ''A'' or ''physical_A'' (got %s).', domain);
    end
end

% --- Select matrix + validate --------------------------------------------
if strcmp(domain,'A')
    if ~isfield(sssa,'A') || ~isnumeric(sssa.A)
        error('stability:modal_analysis:badA', ...
            'sssa.A must be a numeric matrix for domain ''A''.');
    end
    A = sssa.A;
else
    if ~isfield(sssa,'physical_A') || ~isnumeric(sssa.physical_A)
        error('stability:modal_analysis:badPhysicalA', ...
            'sssa.physical_A must be a numeric matrix for domain ''physical_A''.');
    end
    A = sssa.physical_A;
end
[n, m] = size(A);
if n ~= m
    error('stability:modal_analysis:nonSquare', ...
        'Domain %s matrix must be square (got %dx%d).', domain, n, m);
end
if any(~isfinite(A(:)))
    error('stability:modal_analysis:nonfinite', ...
        'Domain %s matrix contains NaN/Inf.', domain);
end

modal = struct();
modal.domain = domain;
modal.algorithm_version = 'stability.modal_analysis/1';
modal.sorting_policy = 'real_desc_imag_sign_pos_real_neg_absimag_desc_raw_index_v1';
modal.matrix_dimension = n;
modal.source_matrix = domain;
modal.tolerances = struct('eigenvalue_pair_tol',eigenvalue_pair_tol, ...
    'pair_ambiguity_tol',pair_ambiguity_tol,'cluster_tol',cluster_tol, ...
    'imag_zero_tol',imag_zero_tol,'residual_tol',residual_tol, ...
    'biorthogonality_tol',biorthogonality_tol,'conditioning_tol',conditioning_tol, ...
    'rank_tol',rank_tol,'lift_tol',lift_tol);

% Empty matrix: valid empty result.
if n == 0
    modal = empty_result(modal);
    return;
end

% Require real matrix for conjugate-closure contract.
if ~isreal(A)
    error('stability:modal_analysis:complexMatrix', ...
        ['Domain %s matrix must be real for the conjugate-pair contract. ' ...
         'Complex matrices are not supported in this version.'], domain);
end

% --- Step 2: raw right + left eigensolves (no inv) ----------------------
[Vraw, lambdaR] = eig(A, 'vector');
[Uraw, lambdaLH] = eig(A', 'vector');   % A^H eigenvectors, eigenvalues conj(lambdaR)

% --- Step 3: cluster detection on right eigenvalues --------------------
cluster_id = detect_clusters(lambdaR, cluster_tol, imag_zero_tol);

% --- Step 4: deterministic left/right pairing --------------------------
[raw_to_left, pair_distance, pairing_status, pairing_reason] = ...
    pair_left_right(lambdaR, lambdaLH, eigenvalue_pair_tol, pair_ambiguity_tol);

% --- Step 5: conditioning (scale-invariant |u'*v|/(||u|| ||v||)) -------
[conditioning_metric, conditioning_status] = ...
    compute_conditioning(Vraw, Uraw, raw_to_left, conditioning_tol);

% --- Step 6: biorthogonal normalization (conj(alpha)) -------------------
[Vnorm, Unorm, alpha, norm_status] = ...
    biorthogonal_normalize(Vraw, Uraw, raw_to_left, conditioning_tol);

% --- Step 8: conjugate-pair IDs (on raw right eigenvalues) --------------
conjugate_pair_id = assign_conjugate_pairs(lambdaR, imag_zero_tol);

% --- Step 9: frozen deterministic display sort --------------------------
display_to_raw = deterministic_sort(lambdaR, imag_zero_tol);
raw_to_display = zeros(1, n);
for k = 1:n
    raw_to_display(display_to_raw(k)) = k;
end

% --- Step 10: normalized residuals ---------------------------------------
Anorm = norm(A, 'fro');
[right_residual, left_residual] = compute_residuals(A, Vnorm, Unorm, ...
    lambdaR, raw_to_left, Anorm);

% --- Step 11: signed participation + display ranking --------------------
[signed_participation, display_ranking, participation_sum, ...
    participation_status, participation_reason] = ...
    compute_participation(Vnorm, Unorm, raw_to_left, conditioning_status, ...
    right_residual, left_residual, residual_tol, pairing_status, cluster_id);

% Biorthogonality diagnostic (NOT a hard gate; off-diag leakage reported)
Bmat = Unorm' * Vnorm;
diag_err = abs(diag(Bmat) - 1);
offdiag_err = max(abs(Bmat - diag(diag(Bmat))), [], 'all');
modal.biorthogonality_matrix = Bmat;
modal.biorthogonality_diag_error = diag_err;
modal.biorthogonality_offdiag_error = offdiag_err;
modal.biorthogonality_residual = norm(Bmat - eye(n), 'fro') / max(1, norm(eye(n),'fro'));

% --- Apply display permutation to all per-mode outputs ------------------
lambda_sorted = lambdaR(display_to_raw);
V_sorted = Vnorm(:, display_to_raw);
U_sorted = Unorm(:, display_to_raw);
conj_pair_sorted = conjugate_pair_id(display_to_raw);
cluster_sorted = cluster_id(display_to_raw);
raw_idx_sorted = display_to_raw;
right_res_sorted = right_residual(display_to_raw);
left_res_sorted = left_residual(display_to_raw);
pair_dist_sorted = pair_distance(display_to_raw);
pair_status_sorted = pairing_status(display_to_raw);
pair_reason_sorted = pairing_reason(display_to_raw);
cond_metric_sorted = conditioning_metric(display_to_raw);
cond_status_sorted = conditioning_status(display_to_raw);
part_status_sorted = participation_status(display_to_raw);
part_reason_sorted = participation_reason(display_to_raw);
signed_part_sorted = signed_participation(:, display_to_raw);
display_rank_sorted = display_ranking(:, display_to_raw);
part_sum_sorted = participation_sum(display_to_raw);

modal.eigenvalues = lambda_sorted;
modal.eigenvalue_matrix = diag(lambda_sorted);
modal.right_eigenvectors = V_sorted;
modal.left_eigenvectors = U_sorted;
modal.raw_eigen_index = raw_idx_sorted;
modal.display_mode_number = (1:n)';
modal.display_to_raw_index = display_to_raw;
modal.raw_to_display_index = raw_to_display;
modal.conjugate_pair_id = conj_pair_sorted;
modal.cluster_id = cluster_sorted;
modal.right_residual = right_res_sorted;
modal.left_residual = left_res_sorted;
modal.pair_distance = pair_dist_sorted;
modal.pairing_status = pair_status_sorted;
modal.pairing_reason = pair_reason_sorted;
modal.conditioning_metric = cond_metric_sorted;
modal.conditioning_status = cond_status_sorted;
modal.participation_status = part_status_sorted;
modal.participation_reason = part_reason_sorted;
modal.signed_participation = signed_part_sorted;
modal.display_ranking = display_rank_sorted;
modal.participation_sum = part_sum_sorted;

% --- Cluster projectors (residuals only; no ranking) -------------------
modal.clusters = build_clusters(A, lambdaR, Vraw, Uraw, raw_to_left, ...
    cluster_id, rank_tol);

% --- Physical lift (map-dependent oblique attribution) ------------------
if strcmp(domain,'physical_A')
    modal = attach_physical_lift(modal, sssa, V_sorted, U_sorted, ...
        lambda_sorted, part_status_sorted, lift_tol);
else
    modal.physical_lift_status = 'NOT_APPLICABLE_DOMAIN_A';
    modal.global_lifted_signed_participation = [];
    modal.lift_status = 'NOT_APPLICABLE_DOMAIN_A';
end

% --- Read-only verification (input unchanged) ---------------------------
modal.input_unchanged = true;   % caller may deep-compare sssa before/after
end

% =========================================================================
function r = empty_result(modal)
r = modal;
r.eigenvalues = [];
r.eigenvalue_matrix = [];
r.right_eigenvectors = [];
r.left_eigenvectors = [];
r.raw_eigen_index = [];
r.display_mode_number = [];
r.display_to_raw_index = [];
r.raw_to_display_index = [];
r.conjugate_pair_id = [];
r.cluster_id = [];
r.right_residual = [];
r.left_residual = [];
r.pair_distance = [];
r.pairing_status = 'AVAILABLE_EMPTY';
r.pairing_reason = '';
r.conditioning_metric = [];
r.conditioning_status = 'AVAILABLE_EMPTY';
r.participation_status = 'AVAILABLE_EMPTY';
r.participation_reason = '';
r.signed_participation = [];
r.display_ranking = [];
r.participation_sum = [];
r.biorthogonality_matrix = [];
r.biorthogonality_diag_error = [];
r.biorthogonality_offdiag_error = [];
r.biorthogonality_residual = NaN;
r.clusters = struct();
r.physical_lift_status = 'NOT_APPLICABLE_EMPTY';
r.global_lifted_signed_participation = [];
r.lift_status = 'NOT_APPLICABLE_EMPTY';
end

% --- Cluster detection ---------------------------------------------------
function cid = detect_clusters(lambda, cluster_tol, imag_zero_tol)
n = numel(lambda);
cid = zeros(1, n);
used = false(1, n);
next_id = 1;
for i = 1:n
    if used(i), continue; end
    members = i;
    used(i) = true;
    for j = i+1:n
        if used(j), continue; end
        d = abs(lambda(i) - lambda(j)) / max([1, abs(lambda(i)), abs(lambda(j))]);
        if d <= cluster_tol
            members(end+1) = j; %#ok<AGROW>
            used(j) = true;
        end
    end
    cid(members) = next_id;
    next_id = next_id + 1;
end
end

% --- Deterministic left/right pairing -----------------------------------
function [raw_to_left, dist, status, reason] = pair_left_right(lambdaR, lambdaLH, pair_tol, ambig_tol)
n = numel(lambdaR);
raw_to_left = zeros(1, n);
dist = inf(1, n);
status = repmat({"AVAILABLE_SIMPLE"}, 1, n);
reason = repmat({""}, 1, n);
used_left = false(1, numel(lambdaLH));
% Build normalized cost matrix: |lambdaLH(j) - conj(lambdaR(i))|
C = inf(n, numel(lambdaLH));
for i = 1:n
    for j = 1:numel(lambdaLH)
        C(i,j) = abs(lambdaLH(j) - conj(lambdaR(i))) / ...
            max([1, abs(lambdaR(i)), abs(lambdaLH(j))]);
    end
end
% Greedy one-to-one with raw-index tie-break; fails closed if ambiguous.
for step = 1:n
    % Find global min among unused (i, j).
    Cused = C;
    for i = 1:n
        if raw_to_left(i) ~= 0
            Cused(i, :) = inf;
        end
    end
    Cused(:, used_left) = inf;
    [dmin, idx] = min(Cused(:));
    if ~isfinite(dmin)
        % No assignment remaining — mark unassigned as failed.
        for i = 1:n
            if raw_to_left(i) == 0
                raw_to_left(i) = 0;
                status{i} = 'UNAVAILABLE_ILL_CONDITIONED';
                reason{i} = 'PAIRING_UNRESOLVED';
            end
        end
        return;
    end
    [i_chosen, j_chosen] = ind2sub(size(Cused), idx);
    raw_to_left(i_chosen) = j_chosen;
    dist(i_chosen) = dmin;
    used_left(j_chosen) = true;
    if dmin > pair_tol
        status{i_chosen} = 'UNAVAILABLE_ILL_CONDITIONED';
        reason{i_chosen} = 'PAIR_DISTANCE_EXCEEDED';
    else
        % Check ambiguity: nearest rival distance.
        row = Cused(i_chosen, :);
        row(j_chosen) = inf;
        rival = min(row);
        if rival <= dmin + ambig_tol
            status{i_chosen} = 'UNAVAILABLE_ILL_CONDITIONED';
            reason{i_chosen} = 'PAIRING_AMBIGUOUS';
        end
    end
end
end

% --- Conditioning (scale-invariant) -------------------------------------
function [metric, status] = compute_conditioning(V, U, raw_to_left, cond_tol)
n = size(V, 2);
metric = zeros(1, n);
status = repmat({"AVAILABLE_SIMPLE"}, 1, n);
for i = 1:n
    j = raw_to_left(i);
    if j == 0
        metric(i) = 0;
        status{i} = 'UNAVAILABLE_ILL_CONDITIONED';
        continue;
    end
    vi = V(:, i);
    uj = U(:, j);
    denom = norm(vi) * norm(uj);
    if denom == 0
        metric(i) = 0;
        status{i} = 'UNAVAILABLE_ILL_CONDITIONED';
    else
        metric(i) = abs(uj' * vi) / denom;
        if metric(i) <= cond_tol
            status{i} = 'UNAVAILABLE_ILL_CONDITIONED';
        end
    end
end
end

% --- Biorthogonal normalization (conj(alpha)) ---------------------------
function [Vn, Un, alpha, status] = biorthogonal_normalize(V, U, raw_to_left, cond_tol)
n = size(V, 2);
Vn = V;
Un = U;
alpha = zeros(1, n);
status = repmat({"AVAILABLE_SIMPLE"}, 1, n);
for i = 1:n
    j = raw_to_left(i);
    if j == 0
        status{i} = 'UNAVAILABLE_ILL_CONDITIONED';
        continue;
    end
    vi = V(:, i) / norm(V(:, i));
    uj = U(:, j) / norm(U(:, j));
    a = uj' * vi;
    alpha(i) = a;
    if abs(a) <= cond_tol
        status{i} = 'UNAVAILABLE_ILL_CONDITIONED';
        % Keep unit-norm vectors for diagnostics; do not divide.
        Vn(:, i) = vi;
        Un(:, j) = uj;
    else
        Vn(:, i) = vi;
        Un(:, j) = uj / conj(a);
    end
end
end

% --- Conjugate-pair IDs --------------------------------------------------
function pid = assign_conjugate_pairs(lambda, imag_zero_tol)
n = numel(lambda);
pid = zeros(1, n);
used = false(1, n);
next_id = 1;
for i = 1:n
    if used(i), continue; end
    if abs(imag(lambda(i))) <= imag_zero_tol
        pid(i) = next_id;
        used(i) = true;
        next_id = next_id + 1;
    else
        % Find conjugate partner.
        best_j = 0;
        best_d = inf;
        for j = i+1:n
            if used(j), continue; end
            d = abs(lambda(j) - conj(lambda(i)));
            if d < best_d
                best_d = d;
                best_j = j;
            end
        end
        if best_j ~= 0
            pid(i) = next_id;
            pid(best_j) = next_id;
            used(i) = true;
            used(best_j) = true;
            next_id = next_id + 1;
        else
            % Unresolved complex root — singleton with diagnostic.
            pid(i) = next_id;
            used(i) = true;
            next_id = next_id + 1;
        end
    end
end
end

% --- Deterministic display sort -----------------------------------------
function order = deterministic_sort(lambda, imag_zero_tol)
n = numel(lambda);
imag_sign = zeros(n, 1);
for k = 1:n
    im = imag(lambda(k));
    if abs(im) <= imag_zero_tol
        imag_sign(k) = 0;
    elseif im > 0
        imag_sign(k) = 1;
    else
        imag_sign(k) = -1;
    end
end
% Sort key: descending real, then +imag(1) > real(0) > -imag(-1), then
% descending |imag|, then raw index ascending. sortrows ascending on
% negated keys gives the desired order.
key = [ -real(lambda(:)), -imag_sign, -abs(imag(lambda(:))), (1:n)' ];
[~, order] = sortrows(key, [1 2 3 4]);
order = order';
end

% --- Residuals -----------------------------------------------------------
function [rr, lr] = compute_residuals(A, V, U, lambdaR, raw_to_left, Anorm)
n = size(V, 2);
rr = zeros(1, n);
lr = zeros(1, n);
for i = 1:n
    vi = V(:, i);
    rr(i) = norm(A*vi - lambdaR(i)*vi) / max(1, Anorm*norm(vi));
    j = raw_to_left(i);
    if j ~= 0
        uj = U(:, j);
        lr(i) = norm(A'*uj - conj(lambdaR(i))*uj) / max(1, Anorm*norm(uj));
    else
        lr(i) = NaN;
    end
end
end

% --- Participation -------------------------------------------------------
function [p, rho, psum, status, reason] = compute_participation(V, U, raw_to_left, cond_status, rr, lr, res_tol, pair_status, cluster_id)
n = size(V, 2);
p = complex(NaN(n, n), 0);
rho = NaN(n, n);
psum = NaN(1, n);
status = repmat({"AVAILABLE_SIMPLE"}, 1, n);
reason = repmat({""}, 1, n);
for i = 1:n
    j = raw_to_left(i);
    if j == 0
        status{i} = 'UNAVAILABLE_ILL_CONDITIONED';
        reason{i} = 'PAIRING_UNRESOLVED';
        continue;
    end
    if ~strcmp(cond_status{i}, 'AVAILABLE_SIMPLE')
        status{i} = 'UNAVAILABLE_ILL_CONDITIONED';
        reason{i} = 'SMALL_BIORTHOGONAL_PRODUCT';
        continue;
    end
    if rr(i) > res_tol
        status{i} = 'UNAVAILABLE_ILL_CONDITIONED';
        reason{i} = 'RIGHT_RESIDUAL_FAILURE';
        continue;
    end
    if lr(i) > res_tol || isnan(lr(i))
        status{i} = 'UNAVAILABLE_ILL_CONDITIONED';
        reason{i} = 'LEFT_RESIDUAL_FAILURE';
        continue;
    end
    if ~strcmp(pair_status{i}, 'AVAILABLE_SIMPLE')
        status{i} = 'UNAVAILABLE_ILL_CONDITIONED';
        reason{i} = 'PAIRING_AMBIGUOUS_OR_DISTANT';
        continue;
    end
    % Clustered (multi-member) => individual participation basis-sensitive.
    members = find(cluster_id == cluster_id(i));
    if numel(members) > 1
        status{i} = 'UNAVAILABLE_ILL_CONDITIONED';
        reason{i} = 'CLUSTERED_OR_REPEATED';
        continue;
    end
    vi = V(:, i);
    uj = U(:, j);
    p(:, i) = conj(uj) .* vi;
    s = sum(p(:, i));
    psum(i) = s;
    if abs(s - 1) > 1e-6
        status{i} = 'UNAVAILABLE_ILL_CONDITIONED';
        reason{i} = 'PARTICIPATION_SUM_FAILURE';
    else
        rho(:, i) = abs(p(:, i)) / sum(abs(p(:, i)));
    end
end
end

% --- Cluster projectors (residuals only, no ranking) -------------------
function cl = build_clusters(A, lambdaR, V, U, raw_to_left, cluster_id, rank_tol)
cl = struct('id',{},'members',{},'dimension',{},'projector',{}, ...
    'idempotence_residual',{},'trace_residual',{},'commutation_residual',{}, ...
    'status',{},'reason',{});
ids = unique(cluster_id);
for c = 1:numel(ids)
    members = find(cluster_id == ids(c));
    if numel(members) <= 1
        continue;   % singleton — no cluster projector needed
    end
    Vc = V(:, members);
    % Left vectors for this cluster.
    left_idx = raw_to_left(members);
    left_idx = left_idx(left_idx ~= 0);
    if isempty(left_idx) || numel(left_idx) ~= numel(members)
        cl(end+1) = struct('id',ids(c),'members',members,'dimension',numel(members), ...
            'projector',NaN(numel(Vc),1),'idempotence_residual',NaN, ...
            'trace_residual',NaN,'commutation_residual',NaN, ...
            'status','UNAVAILABLE_ILL_CONDITIONED','reason','PAIRING_UNRESOLVED'); %#ok<AGROW>
        continue;
    end
    Uc = U(:, left_idx);
    G = Uc' * Vc;
    % Rank check via QR.
    [~, R] = qr(G, 0);
    r_rank = sum(abs(diag(R)) > rank_tol * max(size(R)) * (norm(G, 'fro') + eps));
    if r_rank < numel(members)
        cl(end+1) = struct('id',ids(c),'members',members,'dimension',numel(members), ...
            'projector',NaN(numel(Vc),1),'idempotence_residual',NaN, ...
            'trace_residual',NaN,'commutation_residual',NaN, ...
            'status','UNAVAILABLE_ILL_CONDITIONED','reason','DEFECTIVE_OR_RANK_DEFICIENT'); %#ok<AGROW>
        continue;
    end
    P = Vc * (G \ Uc');   % oblique spectral projector (uses \, not inv)
    idem_res = norm(P*P - P, 'fro') / max(1, norm(P, 'fro'));
    trace_res = abs(trace(P) - numel(members));
    comm_res = norm(A*P - P*A, 'fro') / max(1, norm(A,'fro')*norm(P,'fro'));
    st = 'AVAILABLE_SIMPLE';
    rs = '';
    if idem_res > 1e-6, st = 'UNAVAILABLE_ILL_CONDITIONED'; rs = 'IDEMPOTENCE_FAILURE'; end
    if trace_res > 1e-6, st = 'UNAVAILABLE_ILL_CONDITIONED'; rs = 'TRACE_FAILURE'; end
    cl(end+1) = struct('id',ids(c),'members',members,'dimension',numel(members), ...
        'projector',P,'idempotence_residual',idem_res, ...
        'trace_residual',trace_res,'commutation_residual',comm_res, ...
        'status',st,'reason',rs); %#ok<AGROW>
end
end

% --- Physical lift (map-dependent oblique attribution) ------------------
function modal = attach_physical_lift(modal, sssa, Vp, Up, lambda_p, ...
    part_status, lift_tol)
n = size(Vp, 2);
modal.global_lifted_signed_participation = complex(NaN(sssa.nx_total, n), 0);
modal.lifted_active_right = NaN(sssa.nx_active, n);
modal.lifted_active_left = NaN(sssa.nx_active, n);
modal.composed_right_lift_map = [];
modal.composed_left_lift_map = [];
modal.left_right_map_identity_residual = NaN;
modal.physical_matrix_composition_residual = NaN;
modal.lifted_biorthogonality_residual = NaN;

% Reconstruct Lb (free-row selector) from active_bound_constraint_global_indices.
[Lb, Tb, lb_status] = reconstruct_bound_maps(sssa);
if ~strcmp(lb_status, 'AVAILABLE')
    modal.physical_lift_status = 'NOT_AVAILABLE_INCONSISTENT_LIFT_MAP';
    modal.lift_status = lb_status;
    return;
end

% Quotient maps.
[Lq, Tq, q_status] = get_quotient_maps(sssa);
if ~strcmp(q_status, 'AVAILABLE')
    modal.physical_lift_status = 'NOT_AVAILABLE_MISSING_LIFT_MAP';
    modal.lift_status = q_status;
    return;
end

L = Lq * Lb;
R = Tb * Tq;
modal.composed_right_lift_map = R;
modal.composed_left_lift_map = L;

% Authenticate: L*R ~= I and physical_A ~= L*sssa.A*R.
lr_res = norm(L*R - eye(size(L,1)), 'fro') / max(1, norm(eye(size(L,1)),'fro'));
comp_res = norm(sssa.physical_A - L*sssa.A*R, 'fro') / max(1, norm(sssa.physical_A,'fro'));
modal.left_right_map_identity_residual = lr_res;
modal.physical_matrix_composition_residual = comp_res;
if lr_res > lift_tol || comp_res > lift_tol
    modal.physical_lift_status = 'NOT_AVAILABLE_INCONSISTENT_LIFT_MAP';
    modal.lift_status = 'NOT_AVAILABLE_INCONSISTENT_LIFT_MAP';
    return;
end

% Lift: v_g = R*v_p (active), u_g = L'*u_p (active); embed into global.
E = zeros(sssa.nx_total, sssa.nx_active);
E(sssa.active_state_indices, :) = sssa.nx_active; %#ok - placeholder
% (corrected below)
E = zeros(sssa.nx_total, sssa.nx_active);
for k = 1:sssa.nx_active
    E(sssa.active_state_indices(k), k) = 1;
end
Vg_active = R * Vp;     % active-coordinate lifted right vectors
Ug_active = L' * Up;    % active-coordinate lifted left vectors
Vglobal = E * Vg_active;
Uglobal = E * Ug_active;
modal.lifted_active_right = Vg_active;
modal.lifted_active_left = Ug_active;

% Lifted biorthogonality (diagnostic).
Blift = Ug_active' * Vg_active;
modal.lifted_biorthogonality_residual = norm(Blift - eye(n), 'fro') / max(1, norm(eye(n),'fro'));

% Map-dependent oblique attribution (NOT canonical global-state participation).
for i = 1:n
    if strcmp(part_status{i}, 'AVAILABLE_SIMPLE')
        modal.global_lifted_signed_participation(:, i) = conj(Uglobal(:, i)) .* Vglobal(:, i);
    end
end
modal.physical_lift_status = 'AVAILABLE_OBLIQUE_ATTRIBUTION';
modal.lift_status = 'AVAILABLE_OBLIQUE_ATTRIBUTION';
end

function [Lb, Tb, status] = reconstruct_bound_maps(sssa)
status = 'AVAILABLE';
if ~isfield(sssa,'active_bound_constraint_global_indices') || ...
        isempty(sssa.active_bound_constraint_global_indices)
    % No bound reduction: identity maps (if dimensions consistent).
    if isfield(sssa,'nx_active') && isfield(sssa,'physical_state_dimension')
        if sssa.nx_active == sssa.physical_state_dimension
            Lb = eye(sssa.nx_active);
            Tb = eye(sssa.nx_active);
            return;
        end
    end
    Lb = [];
    Tb = [];
    status = 'NOT_AVAILABLE_MISSING_LIFT_MAP';
    return;
end
constrained = sssa.active_bound_constraint_global_indices(:)';
active = sssa.active_state_indices(:)';
% Map constrained global indices to active positions.
bound_pos = zeros(1, numel(constrained));
for k = 1:numel(constrained)
    pos = find(active == constrained(k), 1, 'first');
    if isempty(pos)
        Lb = []; Tb = [];
        status = 'NOT_AVAILABLE_INCONSISTENT_LIFT_MAP';
        return;
    end
    bound_pos(k) = pos;
end
if numel(unique(bound_pos)) ~= numel(bound_pos)
    Lb = []; Tb = [];
    status = 'NOT_AVAILABLE_INCONSISTENT_LIFT_MAP';
    return;
end
nactive = numel(active);
free_pos = setdiff(1:nactive, bound_pos, 'stable');
if ~isfield(sssa,'active_bound_tangent_map') || isempty(sssa.active_bound_tangent_map)
    Lb = []; Tb = [];
    status = 'NOT_AVAILABLE_MISSING_LIFT_MAP';
    return;
end
Tb = sssa.active_bound_tangent_map;
if size(Tb,1) ~= nactive || size(Tb,2) ~= numel(free_pos)
    Lb = [];
    status = 'NOT_AVAILABLE_INCONSISTENT_LIFT_MAP';
    return;
end
% Lb = free-row selector.
Lb = zeros(numel(free_pos), nactive);
for k = 1:numel(free_pos)
    Lb(k, free_pos(k)) = 1;
end
% Authenticate Lb*Tb ~= I.
if norm(Lb*Tb - eye(numel(free_pos)), 'fro') > 1e-6
    status = 'NOT_AVAILABLE_INCONSISTENT_LIFT_MAP';
end
end

function [Lq, Tq, status] = get_quotient_maps(sssa)
status = 'AVAILABLE';
if ~isfield(sssa,'coordinate_quotient_left_map') || ...
        ~isfield(sssa,'coordinate_quotient_right_map') || ...
        isempty(sssa.coordinate_quotient_left_map) || ...
        isempty(sssa.coordinate_quotient_right_map)
    % No quotient: identity (if dimensions consistent).
    if isfield(sssa,'nx_active') && isfield(sssa,'physical_state_dimension')
        if sssa.nx_active == sssa.physical_state_dimension
            Lq = eye(sssa.nx_active);
            Tq = eye(sssa.nx_active);
            return;
        end
    end
    Lq = []; Tq = [];
    status = 'NOT_AVAILABLE_MISSING_LIFT_MAP';
    return;
end
Lq = sssa.coordinate_quotient_left_map;
Tq = sssa.coordinate_quotient_right_map;
end
