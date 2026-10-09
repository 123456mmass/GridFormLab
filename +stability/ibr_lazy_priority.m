function [cand, cursor, done] = ibr_lazy_priority(cursor, ctx)
%IBR_LAZY_PRIORITY  Deterministic, monotone, lazy GFM-subset generator.
%
%   [CAND, CURSOR, DONE] = stability.ibr_lazy_priority(CURSOR, CTX) yields the
%   next candidate SUBSET in a fixed, deterministic, monotone order WITHOUT
%   materializing the 2^N power set.
%
%   Usage (caller owns the value cursor; no handles, no global state):
%       cursor = [];
%       done = false;
%       while ~done
%           [cand, cursor, done] = stability.ibr_lazy_priority(cursor, ctx);
%           if done, break; end
%           % ... use cand.selected_gfm_indices ...
%       end
%
%   CTX struct:
%     .eligible   row vector of eligible GFM-capable IBR resource indices,
%                 strictly ascending (the enumeration universe).
%     .counts     row vector of subset sizes to enumerate, in generation order
%                 (typically cmin:cmax). Each entry must satisfy
%                 0 <= counts(j) <= numel(eligible).
%
%   Generation order (PROJECT_DERIVED, deterministic + monotone):
%     for each count k in CTX.counts (outer), then the k-subsets of
%     CTX.eligible in LEXICOGRAPHIC order of the ascending index tuple (inner).
%     The number of generated candidates is sum_k C(N,k) <= 2^N, but only ONE
%     subset is live at a time: memory is O(k), time is O(k) per candidate
%     (lexicographic k-subset unranking). Nothing is precomputed.
%
%   CAND struct (spec only -- NO physics, NO ranking):
%     .selected_gfm_indices   ascending row vector (possibly empty)
%     .n_gfm_required         scalar count (== numel(selected_gfm_indices))
%     .flat_index             1-based generation ordinal (stable)
%     .count_slot             index into CTX.counts
%     .subset_ordinal         0-based lexicographic ordinal WITHIN the count
%
%   CURSOR carries CTX plus the (count_slot, subset_ordinal, flat_index) state.
%   A call with a NON-struct CURSOR (e.g. [] or 0) initializes and emits the
%   first candidate. DONE becomes true once the finite space is exhausted; then
%   CAND is the blank spec.
%
%   Classification: finite action-set construction PROJECT_DERIVED; canonical
%   lexicographic ordering NUMERICAL_METHOD. No external solver, no physics.

% --- init or validate ------------------------------------------------
if ~isstruct(cursor)
    ctx = validate_ctx(ctx);
    cursor = struct('ctx', ctx, 'slot', 1, 'ordinal', 0, 'flat', 0, ...
        'finished', false, 'N', numel(ctx.eligible));
else
    if ~isfield(cursor, 'ctx')
        error('stability:ibr_lazy_priority:badCursor', ...
            'Cursor must be produced by stability.ibr_lazy_priority.');
    end
end
ctx = cursor.ctx;
done = false;
cand = blank_spec();

if cursor.finished || cursor.N == 0 || isempty(ctx.counts)
    done = true;
    return;
end

% --- emit the current (slot, ordinal) -------------------------------
if cursor.slot > numel(ctx.counts)
    cursor.finished = true;
    done = true;
    return;
end
k = ctx.counts(cursor.slot);
if k < 0 || k > cursor.N
    error('stability:ibr_lazy_priority:badCount', ...
        'CTX.counts entry %g is outside [0, %d].', k, cursor.N);
end

cand.selected_gfm_indices = ctx.eligible(lex_unrank(cursor.N, k, cursor.ordinal));
cand.n_gfm_required = k;
cand.flat_index = cursor.flat + 1;
cand.count_slot = cursor.slot;
cand.subset_ordinal = cursor.ordinal;

% --- advance --------------------------------------------------------
cursor.flat = cursor.flat + 1;
cursor.ordinal = cursor.ordinal + 1;
% roll to the next count when the current one is drained
while cursor.slot <= numel(ctx.counts) && ...
        cursor.ordinal >= nchoosek(cursor.N, ctx.counts(cursor.slot))
    cursor.ordinal = cursor.ordinal - nchoosek(cursor.N, ctx.counts(cursor.slot));
    cursor.slot = cursor.slot + 1;
end
if cursor.slot > numel(ctx.counts)
    cursor.finished = true;
end
end

% =====================================================================
function ctx = validate_ctx(ctx)
if ~isstruct(ctx) || ~isscalar(ctx)
    error('stability:ibr_lazy_priority:badCtx', 'CTX must be a scalar struct.');
end
if ~isfield(ctx, 'eligible') || ~isfield(ctx, 'counts')
    error('stability:ibr_lazy_priority:badCtx', ...
        'CTX requires fields eligible and counts.');
end
eligible = ctx.eligible(:)';
if ~isnumeric(eligible) || any(~isfinite(eligible)) || ...
        any(eligible ~= fix(eligible)) || any(eligible < 1) || ...
        numel(unique(eligible)) ~= numel(eligible)
    error('stability:ibr_lazy_priority:badEligible', ...
        'CTX.eligible must be unique positive finite integers.');
end
if any(diff(eligible) <= 0)
    % The generation order is defined on an ASCENDING universe; enforce it so
    % the lexicographic order (and therefore the enumeration ordinal) is stable.
    eligible = sort(eligible);
end
ctx.eligible = eligible;
counts = reshape(ctx.counts, 1, []);
if ~isnumeric(counts) || any(~isreal(counts)) || any(~isfinite(counts)) || ...
        any(counts ~= fix(counts)) || any(counts < 0) || any(counts > numel(eligible))
    error('stability:ibr_lazy_priority:badCounts', ...
        'CTX.counts entries must be integers in [0, numel(eligible)].');
end
ctx.counts = counts;
end

function s = blank_spec()
s = struct('selected_gfm_indices', [], 'n_gfm_required', 0, ...
    'flat_index', 0, 'count_slot', 0, 'subset_ordinal', 0);
end

function comb = lex_unrank(n, k, r)
%LEX_UNRANK  The r-th (0-based) k-combination of 1..n in lexicographic order.
%   O(k) time, O(k) memory. No power-set materialization.
if k == 0
    comb = zeros(1, 0);
    return;
end
if k > n || r < 0 || r >= nchoosek(n, k)
    error('stability:ibr_lazy_priority:ordinalOutOfRange', ...
        'Lexicographic ordinal %g is out of range for C(%d,%d).', r, n, k);
end
comb = zeros(1, k);
a = 1;
for i = 1:k
    c = loc_nchoosek(n - a, k - i);
    while c <= r
        r = r - c;
        a = a + 1;
        if a > n
            a = n;
            break;
        end
        c = loc_nchoosek(n - a, k - i);
    end
    comb(i) = a;
    a = a + 1;
end
end

function c = loc_nchoosek(n, k)
if n < 0 || k < 0 || k > n
    c = 0;
else
    c = nchoosek(n, k);
end
end
