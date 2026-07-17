function [ranked, order_key] = build_audit_order(configurations)
%BUILD_AUDIT_ORDER  Build-time audit ranking (NOT runtime commit authority).
%
%   [RANKED, ORDER_KEY] = build_audit_order(CONFIGURATIONS) ranks the flat
%   candidate array by the frozen policy using each candidate's STORED
%   build-time fields (n_mode_changes, n_gfm_required, margin). No
%   runtime_context, no transition recompute, no identity alignment.
%
%   Used by ibr_selector_table.build_context to set selected_config (the
%   BUILD-TIME AUDIT result). The runtime path MUST instead call
%   stability.runtime_rerank_candidates (which recomputes transition counts
%   against committed event-left modes and identity-aligns first) -- that is
%   runtime commit authority.
%
%   Frozen policy (feasible first; then fewer mode changes; then fewer GFMs;
%   then larger stability margin; then deterministic resource-ID tie-break;
%   then resource-table-index). Classified PROJECT_DERIVED operational
%   minimality -- NOT a physical-safety claim (fewer GFMs may reduce
%   voltage-forming coverage / inertia in SG_OFF).
%
%   Numeric ordering via internal/candidate_order_matrix (sortrows on a
%   numeric matrix). This KILLS the margin-string-sort bug that the original
%   sprintf '%+012.6f' key had: lexicographic sort of signed-decimal strings
%   is NOT numeric order -- a negative-margin key '+0000.500000' sorts before
%   a positive-margin key '-0000.300000' ('-' < '+' in ASCII), so an UNSTABLE
%   candidate would wrongly outrank a STABLE one. (advisor finding #1,
%   verified empirically 2026-07-17.)
%
%   Classification: NUMERICAL_METHOD (numeric ordering). No external solver.

arguments
    configurations struct
end

n = numel(configurations);
if n == 0
    ranked = configurations;
    order_key = {};
    return;
end
nchanges = zeros(n, 1);
for i = 1:n
    nc = Inf;
    if isfield(configurations(i), 'n_mode_changes') && ...
            ~isempty(configurations(i).n_mode_changes)
        nc = configurations(i).n_mode_changes;
    end
    nchanges(i) = nc;
end
[M, ~] = candidate_order_matrix(configurations, nchanges);
[~, order] = sortrows(M, [1 2 3 4 5]);
ranked = configurations(order);
order_key = arrayfun(@(k) sprintf('feas=%d|nc=%d|ngfm=%d|m=%g|idx=%d', ...
    M(order(k), 1), M(order(k), 2), M(order(k), 3), -M(order(k), 4), ...
    M(order(k), 5)), 1:n, 'UniformOutput', false);
end
