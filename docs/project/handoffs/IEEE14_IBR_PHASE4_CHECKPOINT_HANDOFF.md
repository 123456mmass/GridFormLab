# IEEE14 1-SG + 4-IBR Mission — Phase 4 completion handoff

**Status:** Phase 4 complete and regression-green. This does **not** claim
production IBR readiness; production GFL/VSG models begin in Phase 5.

## Integration state

- Source branch: `feature/ieee14-auto-vsg-switching`
- Integration base: consolidated `main` at `c109491`
- Base merge commit on the source branch: `0190667`
- The source branch contains C0–C8 plus the Phase 4 corrections documented
  here. No rebase, amend, reset, clean, or force-push was used.
- After this checkpoint is committed and verified remotely, the source branch
  is to be merged into `main` with a merge commit.
- **Progression rule:** Phase 5 through Phase 17 continue directly on `main`.
  Do not create another long-lived IBR implementation worktree unless a future
  ownership conflict requires one and `TRACK_COORDINATION.md` is updated first.

## Completed phases

| Phase | Result |
|---|---|
| 0 | Immutable Track A checkpoint, canonical plan/prompt preservation, clean baseline |
| 1 | Source audit, frozen contracts, and decision ledger |
| 2 | Generic scheduled/guard event helpers and synthetic tests |
| 3 | Hybrid-state transition overload and generic event lookup while preserving legacy behavior |
| 4 | IEEE14 mixed-resource case/dispatch contract and in-house mixed-equilibrium solver |

Phase 4 now provides:

- the IEEE14 1-SG + 4-IBR case contract;
- sourced SG1 dynamic data and the frozen post-trip dispatch contract;
- a project-owned coupled Newton equilibrium solver;
- one fixed numerical voltage gauge across SG-on and SG-off configurations;
- structural rejection of a pure-GFL island without a voltage-forming source;
- deterministic equilibrium fingerprints;
- no external nonlinear solver on the production path.

## Phase 4 defects corrected

Three independent defects were reproduced and corrected without changing
solver tolerances, finite-difference steps, iteration limits, physical case
values, or acceptance thresholds:

1. The test helper concatenated a zero-field empty struct with 13-field device
   structs. It now builds a cell array and vertically concatenates the completed
   device structs.
2. The coupled Newton residual retained the two KCL rows paired with fixed
   `vcon` variables. Those rows are now removed using the same stable
   `free_rows` pairing contract used by the SSSA Schur reduction. A fail-closed
   `mixed_equilibrium_solve:nonSquareResidual` dimension check guards the
   coupled Jacobian.
3. The synthetic IBR fixture gave every device an unconstrained state with
   `f=0`, producing structural zero Jacobian rows, and read bus-1 voltage for
   every device. GFL/tripped synthetic devices are now stateless algebraic
   injections; GFM retains two states with test-only PROJECT_DERIVED equilibrium
   residuals for dispatched active power and local voltage magnitude. Every
   mode now reads its mapped local-bus voltage. These remain diagnostic test
   scaffolds, not production GFL/VSG equations.

## Fresh verification evidence

Run from `/home/birds/Documents/Power-flow-ieee14-ibr` after merging
consolidated `main`:

```matlab
restoredefaultpath;
cd('/home/birds/Documents/Power-flow-ieee14-ibr');
pf_init_paths;
r = runtests('tests/test_ieee14_1sg_4ibr_phase4.m');
% 10 passed / 0 failed / 0 incomplete
```

Targeted legacy, event, external-solver, and Phase 4 gates:

```text
81 passed / 0 failed / 0 incomplete
```

Fresh full regression:

```matlab
r = runtests('tests','IncludeSubfolders',true);
% 561 passed / 0 failed / 0 incomplete
```

The targeted set included exact legacy routing/equivalence gates,
`test_sssa_contract`, adaptive rollback, event convention/transition tests,
Phase 2 generic-event tests, the external-solver scanner, and all Phase 4 tests.

## Readiness boundaries

- `IEEE14_MIXED_EQUILIBRIUM_STRUCTURAL_READY = PASS`
- `IEEE14_IBR_GFL_MODEL_READY = NOT_STARTED`
- `IEEE14_IBR_GFM_MODEL_READY = NOT_STARTED`
- `IEEE14_MIXED_PF_SSSA_READY = NOT_STARTED`
- `IEEE14_AUTO_GFM_FIXED_TS_STRUCTURAL_READY = NOT_STARTED`
- `IBR_PRODUCTION_INTEGRATION_READY = NOT_READY`

The synthetic Phase 4 fixture must never be registered as a production IBR
model or used to claim physical FRT, mode-transfer, synchronism, or stability
readiness.

## Main-line continuation: Phase 5–17

After the IBR branch is merged, continue on `main` in this order, observing
the frozen contracts and stop-on-new-semantic-decision rule:

1. Phase 5 — sourced GFL model.
2. Phase 6 — REGFM_B1-derived GFM/VSG model.
3. Phase 7 — fixed-layout dual-mode IBR and bumpless transfer.
4. Phase 8 — finalize IEEE14 dynamic case and dispatch/energy integration.
5. Phase 9 — mixed IEEE14 composite equilibrium using production devices.
6. Phase 10 — mixed SSSA and automatic configuration selector.
7. Phase 11 — fixed-step no-fault hybrid time-domain simulation.
8. Phase 12 — fault, SG trip, and automatic GFM activation.
9. Phase 13 — synchronism, SG reclose, and index-selected return modes.
10. Phase 14 — sourced current limiting, anti-windup, and physical FRT gates.
11. Phase 15 — multiple-GFM subset selection and sharing.
12. Phase 16 — adaptive hybrid time-domain simulation and rollback.
13. Phase 17 — independent validation, report, provenance audit, and separate
    readiness derivation for every milestone.

Before each implementation phase: inspect current `main`, trace the runtime
path, freeze the file allowlist and equations/data contract, declare numerical
acceptance criteria before viewing final results, and update this handoff or a
successor handoff with fresh test evidence.
