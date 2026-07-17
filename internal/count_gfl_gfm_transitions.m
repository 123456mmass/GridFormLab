function [n, incompatible_mask] = count_gfl_gfm_transitions(baseline_modes, candidate_modes, eligible_mask)
%COUNT_GFL_GFM_TRANSITIONS  Canonical GFL<->GFM transition count (one tight definition).
%
%   [N, INCOMPATIBLE_MASK] = count_gfl_gfm_transitions(BASELINE_MODES,
%   CANDIDATE_MODES, ELIGIBLE_MASK) returns the number of eligible dual-mode
%   IBR resources whose baseline mode AND candidate mode are BOTH in
%   {gfl,gfm} and DIFFER.
%
%   This is the SINGLE shared transition-count primitive used by BOTH:
%     - build-time audit (baseline = declared scenario modes ->
%       build_n_mode_changes)
%     - runtime rerank (baseline = committed event-left hybrid_state modes ->
%       runtime_n_mode_changes)
%   Same formula, distinct baselines (values MAY differ legitimately).
%
%   Rules (advisor finding #2 + #8):
%     - Count ONLY GFL<->GFM transitions on eligible dual-mode IBRs.
%     - Do NOT count online/offline transitions, SG breaker transitions, or
%       mode changes on non-dual-mode / non-eligible devices.
%     - An expected dual-mode IBR whose baseline OR candidate mode is NOT in
%       {gfl,gfm} (e.g. tripped, breaker_open, '', unknown) is NOT counted as
%       a transition; instead it is flagged in INCOMPATIBLE_MASK so the caller
%       can reject the candidate / invalidate the runtime context. It NEVER
%       receives zero cost (advisor: unexpected modes must not look cheaper).
%
%   Inputs (positional, length N, identity-aligned by the caller BEFORE this
%   call -- this function is identity-blind and trusts the caller's alignment):
%     BASELINE_MODES   cell(1,N) of char mode strings
%     CANDIDATE_MODES  cell(1,N) of char mode strings
%     ELIGIBLE_MASK    logical(1,N) true for eligible dual-mode IBRs
%
%   Outputs:
%     N                 scalar nonneg integer transition count
%     INCOMPATIBLE_MASK logical(1,N) true where an eligible IBR has a
%                       baseline or candidate mode outside {gfl,gfm}
%
%   Classification: NUMERICAL_METHOD (canonical counting rule). No external
%   solver. Pure function of cached evidence.
%
%   Source: advisor review 2026-07-17 (Step 4 design); replaces the loose
%   all-resource count at ibr_config_selector.m:203-206.

arguments
    baseline_modes cell
    candidate_modes cell
    eligible_mask (1,:) logical
end

nb = numel(baseline_modes);
nc = numel(candidate_modes);
nem = numel(eligible_mask);
% Length consistency is the caller's responsibility; guard anyway (fail safe).
n = min([nb, nc, nem]);
if n == 0
    n = 0;
    incompatible_mask = logical([]);
    return;
end

count = 0;
incompat = false(1, n);
for k = 1:n
    if ~eligible_mask(k)
        continue;
    end
    bm = lower(strtrim(char(baseline_modes{k})));
    cm = lower(strtrim(char(candidate_modes{k})));
    bm_ok = any(strcmp(bm, {'gfl', 'gfm'}));
    cm_ok = any(strcmp(cm, {'gfl', 'gfm'}));
    if ~bm_ok || ~cm_ok
        % Unexpected mode on an eligible dual-mode IBR: flag, never zero-cost.
        incompat(k) = true;
        continue;
    end
    if ~strcmp(bm, cm)
        count = count + 1;
    end
end
n = count;
incompatible_mask = incompat;
end
