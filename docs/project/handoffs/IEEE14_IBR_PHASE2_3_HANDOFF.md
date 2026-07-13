# IEEE14 1-SG + 4-IBR Mission — Phase 2-3 Handoff (autonomous)

**Status:** `IEEE14_IBR_EQUATION_CONTRACT_READY` = `PARTIAL`;
`IEEE14_AUTO_GFM_FIXED_TS_STRUCTURAL_READY` = `NOT_READY` (blocked by Phase 4
mixed-equilibrium source-gate, item 8: 219 MW dispatch deficit unsourced);
`IBR_PRODUCTION_INTEGRATION_READY` = `NOT_STARTED`.

**Branch:** `feature/ieee14-auto-vsg-switching`
**Worktree:** `/home/birds/Documents/Power-flow-ieee14-ibr`
**Base:** immutable Track A commit `31a211d`
**HEAD:** `69fcac3` (C0–C4 committed)
**Date:** 2026-07-13

## What was completed (autonomous, within authorized scope)

### Phase 0 — Preflight (C0 `e37a147`)
- Worktree `feature/ieee14-auto-vsg-switching` at `/home/birds/Documents/
  Power-flow-ieee14-ibr` from immutable `31a211d`.
- Canonical plan + prompt checkpointed (SHA-256 verified: PLAN
  `8823738a...`, PROMPT `87a2bac0...`).
- Fresh Track A baseline: 454/454/0/0.

### Phase 1 — Source audit + frozen contract (C1 `04fa068`)
- User-provided primary-source PDFs audited at equation level (REGFM_B1
  NREL 90260; Ding 83340; IEEE Std 1110-2002; Demetriou + Kodsi IEEE14
  dynamics; GFL/GFM ratio paper; PSRC minutes).
- Equation/source matrix + frozen contract documents written.
- 9-item source-closure checklist: 0/9 fully closed. Six genuine stop
  conditions remain (items 3, 5, 6, 7, 8, 9 — see source matrix).
- Autonomous selections applied (hierarchy b): VSG profile = REGFM_B1;
  SG model structure = IEEE 1110-2002 Model 2.2 (existing emf6_dae);
  KCL/sign/per-unit = Track A composite canonical.

### Phase 2 — Generic scheduled+guard event architecture (C2 `55c78b2`)
- 6 new `+stability/` helpers implementing user corrections 1-3:
  - `ts_hybrid_state_init` — persistent hybrid_state (device_modes, online,
    pending_commands, dwell_timers, hold_timers, lockouts, config id,
    selector version/fingerprint). TS driver is SOLE owner/mutator.
  - `ts_hybrid_state_snapshot` — immutable deep-copy snapshot for
    threading through extended event_context; rejects function_handle.
  - `ts_transitions_from_legacy` — bit-identical adapter wrapping old
    fault_on/fault_off into the generic transitions list + topologies map.
  - `ts_prevalidate_transitions` — generic prevalidator (coincident
    semantics: event_id globally unique, (time,order) unique, ambiguous
    order fails closed, missing topology fails closed, duplicate id fails).
  - `ts_apply_transition` — applies ONE transition (topology by
    transition.topology_id DIRECTLY, NO t+eps; atomic_updates transaction;
    hybrid_commit; algebraic re-solve replicates ts_event_transition B3
    exactly for bit-identical legacy-adapter path).
  - `ts_evaluate_guards` — guard evaluation from COMMITTED state only
    (NOT an input provider); sourced threshold+dwell (ASSUMED_DIAGNOSTIC
    for synthetic); dwell advances only on threshold met, resets on
    disarm; timeout fail-closed; deterministic priority; ambiguous
    priority fails closed.
- `tests/+fixtures/synthetic_guard_fixture.m` + `tests/test_ts_phase2_events.m`
  (21/21 PASS).
- Legacy AbsTol=0 gates verified green throughout.

### Phase 3 — Driver-loop integration (partial) (C3 `5363f47`, C4 `69fcac3`)
- `ts_event_transition` 10-arg overload (hybrid_state) delegates to
  `ts_apply_transition`; legacy 9-arg path UNCHANGED (bit-identical).
  `find_transition_by_id` local helper (fails closed `unknownEventId`).
- `event_id_at` (ts_simulate) + `event_id_lookup` (ts_adaptive_driver)
  generic-path branches: when `events.transitions` is present, look up
  by matching transition time; otherwise legacy fault_on/fault_off path
  UNCHANGED.
- End-to-end verified: legacy adapter → generic transitions → 10-arg
  transition → Y_right/event_id/hybrid_state all correct.

## Final regression

**Full regression: 475/475/0/0** (fresh). Includes the previously-flaky
`test_rts24_psat_comparison` (PSAT stateful false-positive under concurrent
load; PASSED here 22/22, proven not a Phase 2-3 regression by isolated
re-runs).

Legacy AbsTol=0 gates all green:
- `test_ts_strategy_equivalence` (2/2)
- `test_ts_classical_strategy_equivalence` (3/3)
- `test_ts_characterization_fixed` (3/3)
- `test_sssa_contract` (10/10)
- `test_ts_default_routing` (7/7)
- `test_ts_adaptive_rollback` (2/2)
- `test_ts_event_convention` (3/3)
- `test_event_transition` (8/8, B3)
- `test_no_external_solver_dependency` (12/12)
- `test_ts_phase2_events` (21/21, new)

## Genuine stop conditions remaining (per user directive)

| # | Item | Status | Blocks |
|---|------|--------|--------|
| 3 | GFL↔VSG transfer maps + inactive-state rule | UNSOURCED | Phase 6, 10-11 |
| 5 | SG synchronism thresholds/dwell/timeout | UNSOURCED | Phase 11 |
| 6 | Delays (T_up, T_sg_min_off, ρ, T_minimum_hold, T_guard, T_lockout) | UNSOURCED | Phase 10-11 |
| 7 | IEEE14 SG dynamic data (H, D, X'd/EMF6) | UNSOURCED (conflicting Demetriou/Kodsi) | Phase 3, 8 |
| 8 | 219 MW post-trip dispatch/energy contract | UNSOURCED | Phase 4, 8 |
| 9 | γ_req eigenvalue margin | UNSOURCED | Phase 8 |

See `docs/project/IEEE14_IBR_EQUATION_SOURCE_MATRIX.md` and
`docs/project/IEEE14_IBR_FROZEN_CONTRACT.md` for per-equation provenance.

## What was NOT done (and must not be done without sources)

- No `+ibr/**` production model code (blocked by items 1-3).
- No `+cases/case_ieee14_1sg_4ibr*` (blocked by item 8).
- No mixed-resource equilibrium solver (Phase 4, blocked by item 8).
- No full driver-loop hybrid_state ownership / guard-evaluation-after-accept
  integration in `ts_adaptive_driver` (the generic path is wired through
  the helpers + overloads + lookup branches; the remaining driver-loop
  sequencing of coincident-ordered events and guard firing is deferred to
  when a real device model exists to exercise it — implementing it now
  without a real model would add untested complexity).
- No push, merge, rebase, history rewrite, main mutation.
- No modification of dirty user-owned files (main worktree, Track A
  worktree, Padiyar/report/adaptive worktrees, stash `eae0bcd`).

## Smallest user decisions needed to unblock further phases

1. **IEEE14 SG dynamic dataset** (item 7): provide a sourced dataset OR
   explicitly approve one typical dataset (Demetriou 50 Hz or Kodsi 60 Hz)
   as CASE_DEFINED with documented limitations. Note: the project case is
   60 Hz, which favors Kodsi, but the bus-3 identity conflict (condenser
   vs generator) and MVA discrepancy need an explicit decision.
2. **GFL positive-sequence RMS reduction** (item 1): approve a specific
   reduced-order GFL state vector sourced from the standard utility
   representation, OR provide a source stating it explicitly. Ding's GFL
   is full EMT/LCL (14-state), not positive-sequence RMS.
3. **GFL↔VSG transfer map + inactive-state rule** (item 3): approve a
   sourced or derived policy (e.g., frozen inactive states with documented
   zero-eigenvalue handling per correction 6, or a shadow-controller rule).
4. **SG synchronism thresholds** (item 5): provide IEEE TR-121 OR approve
   sourced thresholds (ΔV, Δf/slip, Δθ, dwell, timeout).
5. **Delays** (item 6): provide sourced values OR approve a sourced
   protection/controller standard.
6. **Dispatch/energy contract** (item 8): provide a sourced post-trip
   reserve/participation/ramp/load-shed policy resolving the 219 MW
   deficit.
7. **γ_req** (item 9): provide a sourced eigenvalue-based margin OR
   approve converting PM ≥ 30° (from the GFL/GFM ratio paper) to an
   equivalent eigenvalue criterion with documented assumptions.

## Reproduce

```bash
git -C /home/birds/Documents/Power-flow fetch --all   # confirm no race
git -C /home/birds/Documents/Power-flow-ieee14-ibr log --oneline -6
git -C /home/birds/Documents/Power-flow-ieee14-ibr status --short --branch
```

```matlab
restoredefaultpath;
cd('/home/birds/Documents/Power-flow-ieee14-ibr');
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);   % 475/475/0/0
runtests('tests/test_ts_phase2_events.m');         % 21/21 (new generic event tests)
```

## Commit sequence

| Commit | Phase | Content |
|--------|-------|---------|
| `e37a147` | C0 | canonical plan/prompt checkpoint (SHA-256 verified) |
| `a55eed9` | C1 (superseded) | Phase 1 source-gate BLOCKED handoff (pre-source-PDFs) |
| `04fa068` | C1 | Phase 1 source audit — equation/source matrix + frozen contract (PARTIAL) |
| `55c78b2` | C2 | Phase 2 generic scheduled+guard event architecture (helpers + tests) |
| `5363f47` | C3 | Phase 3 — ts_event_transition 10-arg overload (hybrid_state) |
| `69fcac3` | C4 | Phase 3 — event_id_at / event_id_lookup generic-path branches |

No push/merge/history rewrite. All work local on
`feature/ieee14-auto-vsg-switching`.
