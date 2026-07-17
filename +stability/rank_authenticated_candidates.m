function [ranked, order_key] = rank_authenticated_candidates(configurations, mode)
%RANK_AUTHENTICATED_CANDIDATES  Legacy wrapper -> build_audit_order (build-time audit).
%
%   [RANKED, ORDER_KEY] = rank_authenticated_candidates(CONFIGURATIONS, MODE)
%   is a BACKWARD-COMPATIBLE WRAPPER around stability.build_audit_order. It
%   applies the frozen ranking policy to cached evidence in-memory only --
%   no physical re-evaluation (hard rule: no equilibrium/SSSA in the TS
%   loop). Pure function of cached evidence.
%
%   This entry point uses each candidate's STORED build-time fields
%   (n_mode_changes, n_gfm_required, margin). It is the BUILD-TIME AUDIT
%   path only -- it is NOT runtime commit authority. Runtime authenticated
%   selection MUST use stability.runtime_rerank_candidates (which recomputes
%   transition counts against committed event-left modes and identity-aligns
%   first).
%
%   Advisor revision (2026-07-17): the original single overloaded ranker used
%   an `isempty(runtime_context)` behavior switch (hidden dual-behavior trap)
%   and a sprintf string sort key that is mathematically WRONG for margins
%   (lexicographic != numeric for signed decimals: a negative-margin key
%   '+0000.500000' sorts before a positive-margin key '-0000.300000', so an
%   UNSTABLE candidate would wrongly win). Both fixed: separate explicit
%   entry points (build_audit_order / runtime_rerank_candidates) + numeric
%   sortrows via internal/candidate_order_matrix.
%
%   MODE = 'automatic' (default) or 'manual_override' -- both rank by policy;
%   manual_override callers must still enforce exact-match uniqueness via
%   validate_runtime_candidate_compatibility (this ranker does not enforce
%   uniqueness, it only orders).
%
%   Classification: NUMERICAL_METHOD (numeric ordering). No external solver.

arguments
    configurations struct
    mode char = 'automatic'
end

[ranked, order_key] = stability.build_audit_order(configurations);
end
