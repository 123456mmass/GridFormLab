function [M, tie_strings] = candidate_order_matrix(candidates, n_mode_changes, eligible_incompat)
%CANDIDATE_ORDER_MATRIX  Numeric ranking matrix for the frozen selector policy.
%
%   [M, TIE_STRINGS] = candidate_order_matrix(CANDIDATES, N_MODE_CHANGES,
%   ELIGIBLE_INCOMPAT) builds a NUMERIC ordering matrix for sortrows. This
%   is the single canonical ordering primitive shared by build-time audit
%   (build_audit_order) and runtime rerank (runtime_rerank_candidates).
%
%   Why numeric (not a sprintf string key): lexicographic sorting of a
%   formatted signed-decimal margin string is NOT numeric order. A negative
%   margin key '+0000.500000' sorts BEFORE a positive margin key
%   '-0000.300000' (because '-' < '+' in ASCII), so an UNSTABLE candidate
%   would wrongly outrank a STABLE one. Numeric sortrows on -margin fixes
%   this. (advisor finding #1, verified empirically 2026-07-17.)
%
%   Frozen policy (advisor finding #5, classified PROJECT_DERIVED operational
%   minimality -- NOT a physical-safety claim):
%     feasible (0 first) -> fewer mode changes -> fewer GFMs -> larger margin
%     (-margin ascending = margin descending) -> resource-ID tie-break ->
%     index tie-break.
%
%   Inputs:
%     CANDIDATES        struct array (1xN), each with fields:
%                       feasible, n_gfm_required, margin, tie_break,
%                       selected_gfm_indices
%     N_MODE_CHANGES    double(1xN) transition counts (build OR runtime -- the
%                       caller supplies the phase-appropriate count)
%     ELIGIBLE_INCOMPAT logical(1xN) true where the candidate has an
%                       eligible IBR with an unexpected (non gfl/gfm) mode
%                       -> that candidate sorts last (treated as incompatible).
%                       May be omitted (all false).
%
%   Outputs:
%     M                 double(N,5) numeric sortrows matrix:
%                       col1 feasible_flag (0 feasible first)
%                       col2 n_mode_changes (asc)
%                       col3 n_gfm_required (asc)
%                       col4 -margin (asc = margin desc); NaN/non-finite -> 1e12
%                       col5 tie_idx (stable original index, asc)
%     TIE_STRINGS       cell(1xN) resource-ID tie-break strings (for
%                       diagnostics only; numeric col5 is the actual tie-break)
%
%   Classification: NUMERICAL_METHOD (numeric ordering). No external solver.

arguments
    candidates struct
    n_mode_changes double
    eligible_incompat (1,:) logical = false
end

n = numel(candidates);
M = zeros(n, 5);
tie_strings = cell(1, n);
if n == 0
    return;
end
% Ensure incompat mask is length-matched.
if numel(eligible_incompat) ~= n
    eligible_incompat = false(1, n);
end
for i = 1:n
    c = candidates(i);
    feasible_flag = 1;   % 0 feasible sorts first
    if isfield(c, 'feasible') && ~isempty(c.feasible) && logical(c.feasible)
        feasible_flag = 0;
    end
    mg = NaN;
    if isfield(c, 'margin') && ~isempty(c.margin)
        mg = c.margin;
    end
    if isfinite(mg)
        margin_key = -mg;   % larger margin sorts first (ascending -margin)
    else
        margin_key = 1e12;  % NaN/non-finite sorts last
    end
    ngfm = 0;
    if isfield(c, 'n_gfm_required') && ~isempty(c.n_gfm_required)
        ngfm = c.n_gfm_required;
    end
    tb = '';
    if isfield(c, 'tie_break') && ~isempty(c.tie_break)
        tb = char(c.tie_break);
    end
    % Incompatible (unexpected mode) candidates sort absolutely last:
    % bump feasible_flag to a large value so no compatible candidate loses
    % to one with an unexpected-mode eligible IBR.
    if eligible_incompat(i)
        feasible_flag = 2;
    end
    M(i, 1) = feasible_flag;
    M(i, 2) = n_mode_changes(i);
    M(i, 3) = ngfm;
    M(i, 4) = margin_key;
    M(i, 5) = i;   % stable original-index tie-break
    tie_strings{i} = tb;
end
end
