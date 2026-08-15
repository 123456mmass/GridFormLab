# Codex advisor handoff — IEEE14 1-SG + 4-IBR mission

## Purpose

Continue as the scientific/architecture advisor while Agent A implements and
Agent B independently reviews the remaining IEEE14 IBR phases. The advisor is
read-only unless the user explicitly transfers file ownership.

## Repository state

- Repository: `https://github.com/123456mmass/GridFormLab.git`
- Canonical branch: `main`
- Required baseline ancestor: `2c2cd6e4a28872efb9f09fc62d823d6208bc05c1`
- Merge commit: `2c2cd6e` (`Merge IEEE14 IBR Phases 0-4`).
- IBR Phase 4 source checkpoint: `7f7a12b`.
- Fresh post-merge regression: 561 passed / 0 failed / 0 incomplete.
- Phase 4 targeted suite: 10 passed / 0 failed / 0 incomplete.
- Targeted legacy/event/external-solver/Phase-4 gates: 81/0/0.

On a new machine, fetch `origin/main`, verify that `2c2cd6e` is an ancestor of
the checked-out HEAD, and treat the current `origin/main` tip as canonical.

## Binding continuation decision

Phases 5–17 continue directly on `main`. Do not create another long-lived IBR
implementation branch/worktree unless a real ownership conflict appears and
the coordination document is updated first.

Agent roles:

- Agent A: sole production writer on `main`.
- Agent B: independent read-only reviewer/validator.
- Codex: read-only scientific/architecture/debugging advisor.

No two agents may edit the same production files concurrently. Codex may edit
only after Agent A commits/pushes and the user explicitly transfers ownership.

## Read first

Read these files completely; do not duplicate them in the response:

1. `AGENTS.md`
2. `docs/project/TRACK_COORDINATION.md`
3. `docs/project/handoffs/MAIN_CONSOLIDATION_HANDOFF.md`
4. `docs/project/handoffs/IEEE14_IBR_PHASE4_CHECKPOINT_HANDOFF.md`
5. `docs/project/plans/IEEE14_1SG_4IBR_AUTO_VSG_SWITCHING_PLAN.md`
6. `docs/project/IEEE14_IBR_DECISION_LEDGER.md`
7. `docs/project/IEEE14_IBR_EQUATION_SOURCE_MATRIX.md`
8. `docs/project/IEEE14_IBR_FROZEN_CONTRACT.md`

Then verify Git HEAD/status/origin and trace the actual runtime path relevant to
the phase under review.

## Completed work

Phases 0–4 are merged. Phase 4 includes the case/dispatch contract, fixed-gauge
mixed equilibrium solver, generic event/hybrid-state foundation, structural
pure-GFL-island rejection, and deterministic fingerprints.

The Phase 4 synthetic IBR fixture is diagnostic scaffolding only. It must never
be registered as a production device or support physical readiness claims.
Production GFL/GFM equations have not started.

## Remaining sequence

1. Phase 5: sourced GFL model.
2. Phase 6: REGFM_B1-derived GFM/VSG model.
3. Phase 7: fixed-layout dual-mode IBR and bumpless transfer.
4. Phase 8: production IEEE14 dynamic case/dispatch integration.
5. Phase 9: mixed equilibrium using production devices.
6. Phase 10: mixed SSSA and automatic configuration selector.
7. Phase 11: fixed-step no-fault hybrid time-domain simulation.
8. Phase 12: fault, SG trip, and automatic GFM activation.
9. Phase 13: synchronism, reclose, and index-selected return.
10. Phase 14: sourced limiter, anti-windup, and physical FRT.
11. Phase 15: multiple-GFM selection/sharing.
12. Phase 16: adaptive hybrid simulation and rollback.
13. Phase 17: independent validation, report, provenance audit, and separate
    readiness derivation.

## Advisor review contract

For each Agent A phase plan or implementation:

1. Question whether the intended outcome can be achieved more simply.
2. Trace launcher -> dispatch -> model -> residual/Jacobian -> solver -> output.
3. Verify source -> equation -> convention -> code -> falsification-test chain.
4. Check states, algebraic variables, input ordering, signs, dq frames,
   per-unit bases, current/power direction, bus/device mapping, initialization,
   stopping criteria, and fail-closed semantics.
5. Confirm numerical criteria were frozen before final results were inspected.
6. Reject hidden external solvers, silent fallbacks, synthetic production
   paths, tuning, plot-only equivalence, or readiness overclaims.
7. Classify every nontrivial value/equation as SOURCE_DEFINED, CASE_DEFINED,
   PROJECT_DERIVED, NUMERICAL_METHOD, or DIAGNOSTIC_ONLY.
8. Return blocking findings with file:line, mechanism, consequence, and the
   smallest correction.
9. End with `READY_TO_IMPLEMENT`, `REVISE_PLAN`, `APPROVED_FOR_NEXT_PHASE`, or
   `CHANGES_REQUIRED` as appropriate.

## Scientific constraints

- Production PF/SSSA/TDS/IBR is project-owned base MATLAB only.
- External programs are validation-only and unreachable from production.
- Never adjust physical values, tolerances, FD steps, timesteps, iteration
  limits, scaling, events, or acceptance criteria merely to improve agreement.
- Source-specified benchmark values must match their source.
- Unspecified required values may be CASE_DEFINED or PROJECT_DERIVED only when
  declared and frozen before results; document their derivation.
- New semantic/equation/schema decisions require user approval.

## Workspace caution

At handoff time, canonical `main` was checked out in
`/tmp/Power-flow-main-integration`. The original
`/home/birds/Documents/Power-flow` worktree remained on
`checkpoint/dialog-system` because it still contained preserved local/untracked
files. Do not delete or clean those files. On another machine, simply clone and
checkout the current `origin/main`.

## Suggested skills

- `scrutinize` for every plan/diff review.
- `debug-mantra` and `diagnose` when a test or numerical gate fails.
- `handoff` before changing machines or ending a long session.

## First action in the new session

Ask for Agent A's Phase 5 plan. Perform a read-only review against the files and
contracts above. Do not implement Phase 5 and do not mutate Git or repository
files unless the user explicitly transfers ownership.
