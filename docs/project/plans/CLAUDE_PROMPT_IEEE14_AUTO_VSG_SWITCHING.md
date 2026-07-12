# Prompt for Claude — Plan the IEEE14 Automatic GFL/VSG Switching Mission

Copy the block below into Claude. This prompt requests a read-only audit and an
implementation plan first. It does not authorize immediate code changes.

---

```text
You are the planning agent for the Power-flow MATLAB repository.

Mission: produce an implementation-ready, evidence-backed plan for the IEEE
14-bus one-SG/four-IBR automatic GFL/VSG switching capability. Do NOT implement
or edit runtime code in your first response. Audit the repository and return a
detailed plan for user approval first.

This is a CLEAN-SLATE IBR mission. The historical Track B VSG prototype and the
old general VSG-first plan are not the implementation baseline. Start from the
verified Track A generic interfaces and primary sources. Preserve historical
Track B files read-only as evidence of earlier assumptions/source gaps. Do not
plan to cherry-pick or incrementally patch the old Track B runtime.

Repository:
  /home/birds/Documents/Power-flow

Canonical mission plan (read completely before acting):
  docs/project/plans/IEEE14_1SG_4IBR_AUTO_VSG_SWITCHING_PLAN.md

Repository policy (read completely):
  AGENTS.md

Required local evidence to read completely or inspect where relevant:
  docs/project/TRACK_COORDINATION.md
  docs/project/AGENT_HANDOFF.md
  docs/project/plans/PLAN_IBR_VSG_DEVELOPMENT.md (historical/rejected direction;
    inspect for conflicts only, never treat as design authority)
  docs/project/plans/ibr_interface_foundation.md, if present in the Track A worktree
  /home/birds/Documents/Power-flow-ibr-interface/docs/project/handoffs/TRACK_A_IBR_INTERFACE_FOUNDATION.md
  Historical Track B has NO worktree. Inspect these read-only with git show:
    git show feature/ibr-vsg-models:docs/ibr/IBR_VSG_SOURCE_AUDIT.md
    git show feature/ibr-vsg-models:docs/ibr/IBR_VSG_EQUATION_SOURCE_MATRIX.md
    git show feature/ibr-vsg-models:+ibr/vsg_model.m
    git show feature/ibr-vsg-models:+ibr/vsg_schema.m
  /home/birds/Documents/Power-flow-ibr-interface/+stability/composite_dae.m
  /home/birds/Documents/Power-flow-ibr-interface/+stability/ts_event_transition.m
  /home/birds/Documents/Power-flow-ibr-interface/+stability/ts_prevalidate_events.m
  /home/birds/Documents/Power-flow-ibr-interface/+stability/multimachine_ssa.m
  +cases/case_matpower6_case14.m

Binding user decisions:
  1. Primary case is IEEE MATPOWER 14-bus.
  2. Working resource mapping is SG bus 1; IBR buses 2, 3, 6, and 8, subject
     only to explicit confirmation rather than silent inference.
  3. The GFM implementation is VSG/VSM.
  4. Exact case-sensitive IBR runtime modes are:
       mode = 'gfl' | 'GFM' | 'tripped'
  5. Switchable IBRs must contain both GFL and VSG capabilities. A PF bus-type
     change alone is not a controller transition.
  6. SG loss/trip is the trigger. PF is the feasibility/equilibrium gate.
     SSSA supplies the configuration-selection index. TS verifies events.
  7. Selection index is the non-reference spectral abscissa:
       Omega_z(m) = max Re(lambda_i(A_z(m)))
     for topology/status z and IBR mode vector m.
  8. Candidate configurations must pass PF, P/Q/V/current/headroom/energy,
     square/full-rank Schur, and minimum stability-margin gates before use.
  9. Proposed selection policy is lexicographic: minimum number of GFM units
     satisfying the required margin, then most-negative Omega, then stable
     device-ID tie-break. Identify this as a project decision requiring explicit
     approval, not a verbatim literature rule.
 10. SG returns after a declared minimum off-time. Phase 1 interprets this as
     synchronism-checked breaker reclose of a still-represented/spinning SG,
     not a cold unit restart.
 11. After SG reconnects, do NOT hard-code the selected IBR to remain GFM and
     do NOT hard-code all IBRs to return to GFL. Re-evaluate/select the SG_ON
     target configuration using the index table.
 12. All mode changes require explicit delays. T_up comes from sourced
     protection/logic/controller timings. Post-reconnect T_down uses the
     declared modal-envelope derivation
       T_settle = ln(1/rho)/(-Omega_current)
       T_down   = max(T_minimum_hold, T_settle)
     plus sync/guard dwell and lockout. Do not invent numerical values.
 13. SG breaker reclose requires voltage, frequency/slip, and wrapped phase-angle
     synchronism checks, dwell, and timeout. Never force SG angle/speed to the bus.
 14. Fixed-step TS is canonical first. Current limiter/anti-windup follows the
     structural no-limiter path. Multiple GFM follows. Adaptive TS is last.
 15. Production PF/SSSA/TS must use in-house code only. PSAT/PGAz/MATPOWER
     routines are validation-only and never production dependencies.
 16. No parameter/tolerance/timestep/FD-step/event-time tuning to improve plots,
     eigenvalues, or reference agreement.
 17. Clean-slate implementation: do not cherry-pick Track B runtime. A historical
     helper may be proposed for reuse only after an independent line-by-line
     source/interface audit proves it fits the new contract.
 18. The obsolete `/home/birds/Documents/Power-flow-ibr` worktree was removed by
     explicit user request. Do not recreate it. The historical branch remains
     available only for read-only `git show` inspection.

Primary sources that must be inspected in full-text form before equation claims:
  - UNIFI/WECC REGFM_B1 VSM specification:
    https://www.nrel.gov/docs/fy24osti/90260.pdf
  - Ding et al., dynamically configurable GFM/GFL controls and SSSA margin:
    https://www.nrel.gov/docs/fy23osti/83340.pdf
  - WECC generic renewable model summary:
    https://www.wecc.org/sites/default/files/documents/meeting/2024/Summary%20of%202nd%20Generation%20Generic%20RES%20Models%20%20Rev5.pdf
  - IEEE PES TR-121 generator synchronizing practices:
    https://resourcecenter.ieee.org/publications/technical-reports/pes_tp_tr121_psrc_42924
  - NREL grid-connected/islanded GFM dispatch context:
    https://www.nrel.gov/docs/fy24osti/87959.pdf

Audit requirements before planning:
  A. Run read-only git status/worktree/branch/HEAD/race checks. The main, Track A,
     Track B, reporting, and launcher worktrees may contain user-owned dirty or
     untracked files. Do not stage, delete, reset, switch branches, rebase,
     cherry-pick, merge, or create a worktree during this planning turn.
  B. Trace actual call paths for PF initialization, composite DAE construction,
     SSSA Schur reduction, bundle TS fixed/adaptive routing, and event handling.
  C. Confirm which Track A B1-B9 capabilities really exist at the checked HEAD;
     do not plan against comments alone.
  D. Audit Track B only to identify source gaps and rejected assumptions. Compare
     it against REGFM_B1, but do not promote or use the old five-state custom VSG
     equations as the new runtime base even if individual concepts are similar.
  E. Confirm there is no production GFL model, dual-mode wrapper, SG trip/reclose
     manager, selection index, current limiter integration, or IEEE14 mixed case
     before listing them as new work.
  F. Recompute the IEEE14 load/generation/headroom facts from code. Highlight that
     the original remaining IBR schedule after bus-1 trip is insufficient even
     though aggregate remaining Pmax may be sufficient.

Your response must be a planning deliverable with these sections:
  1. Evidence-backed current status and exact checked Git/worktree state.
  2. Contradictions, gaps, and blockers in the canonical mission plan versus code.
  3. Decisions already frozen versus decisions still requiring user approval.
  4. Exact clean-slate source-closure plan for GFL, VSG, transfer maps, limiter, synchronism,
     delays, dispatch, and energy constraints.
  5. Proposed fixed state vector and device ABI, including inactive-state behavior
     and both bumpless transition maps.
  6. IEEE14 case schema, external bus/device mapping, pre/post-trip dispatch, and
     feasibility contract.
  7. PF -> SSSA -> index-table -> TS architecture, with equations, reference
     ownership, candidate enumeration, deterministic tie-break, and failure paths.
  8. Full event/state-machine chronology from fault through SG trip, GFM activation,
     fault clearing, reconnect enable, synch-check, breaker close, SG_ON index
     selection, delayed IBR mode commit, and optional later contingencies.
  9. Delay/dwell/hysteresis derivation and provenance; list every numerical value
     still unavailable. Do not propose tuned placeholder values as production.
 10. Exact proposed files to add/modify, ownership, allowlist, and forbidden files.
 11. Phase-by-phase implementation sequence with a test-first exit gate for every
     phase, continuing through current limiting, multi-GFM, adaptive TS, independent
     validation, reporting, and readiness derivation.
 12. Focused tests, full-regression gates, numerical convergence studies, negative
     tests, and stable error IDs.
 13. Reviewable commit sequence that separates mechanical ABI changes from new
     numerical behavior and never rewrites existing Track A/B history.
 14. Explicit stop conditions.
 15. A short list of only the genuinely blocking user questions.

Planning quality constraints:
  - Be skeptical. Trace implementation paths rather than trusting design comments.
  - Treat the canonical IEEE14 plan as the new design authority and the old IBR
    plan/Track B runtime as historical evidence only.
  - Base the new IBR implementation on Track A interfaces plus verified primary
    sources; do not propose a Track B runtime cherry-pick.
  - Prefer the smallest vertical slice that proves real mixed PF/SSSA/fixed TS.
  - Do not collapse PF slack, dynamic GFM mode, and algebraic reference ownership.
  - Do not run SSSA on a non-equilibrium fault snapshot and call it a valid margin.
  - Do not change state-vector dimension at an event.
  - Do not invent a temporary all-GFL island reference to keep the solver alive.
  - Do not use t+eps topology discovery or arbitrary event-time offsets.
  - Do not let PF slack absorb power beyond declared limits.
  - Do not infer production readiness from synthetic-only tests.
  - Label SOURCE_VERBATIM, SOURCE_TRANSFORMED, CASE_DEFINED, PROJECT_DERIVED,
    NUMERICAL_METHOD, ASSUMED_DIAGNOSTIC, UNSOURCED, and DECISION_REQUIRED honestly.
  - If a source or semantic decision is missing, stop that phase and ask; do not
    fill the gap from memory.

First response only: return the audited implementation plan and blocking questions.
Do not edit files or start implementation until the user explicitly approves it.
```
