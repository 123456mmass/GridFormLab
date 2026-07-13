# IEEE14 1-SG + 4-IBR Mission — Phase 4 WIP/CHECKPOINT (machine transfer)

**This is a machine-transfer CHECKPOINT, NOT a release. No production-readiness claim.**

**Branch:** `feature/ieee14-auto-vsg-switching`
**Worktree:** `/home/birds/Documents/Power-flow-ieee14-ibr`
**Base / merge-base:** `f59076f` (= `main` = `origin/main`; 0 behind, 25+ ahead)
**Parent of this checkpoint:** `46954d1` (C7)
**Prior handoff:** `docs/project/handoffs/IEEE14_IBR_PHASE2_3_HANDOFF.md` (C0–C5).

## Commit list (main..HEAD)

| Commit | Phase | Content |
|--------|-------|---------|
| `e37a147` | C0 | canonical plan/prompt checkpoint (SHA-256 verified) |
| `04fa068` | C1 | Phase 1 source audit — equation/source matrix + frozen contract |
| `55c78b2` | C2 | Phase 2 generic scheduled+guard event architecture (6 helpers + 21 tests) |
| `5363f47` | C3 | Phase 3 — ts_event_transition 10-arg overload (hybrid_state) |
| `69fcac3` | C4 | Phase 3 — event_id_at / event_id_lookup generic-path branches |
| `dff4dd4` | C5 | Phase 2-3 handoff (475/475/0/0) |
| `ccb160d` | C6 | Phase 1B decision ledger — 6 blockers resolved as design contracts |
| `46954d1` | C7 | Phase 4 — IEEE14 case contract (Kodsi SG1 + dispatch) |
| `<C8>`   | C8 | **WIP/CHECKPOINT — Phase 4 solver + test scaffolding (this commit)** |

## Last observed test counts (the key facts)

- **Last recorded GREEN full regression: 475/475/0/0** at C5 (`dff4dd4`), per the
  Phase 2-3 handoff.
- HEAD `46954d1` (before C8) adds only a case data file (C7) + docs (C6);
  **expected inert to tests**. Full regression NOT rerun for this checkpoint
  per transfer directive (only `git status`, `git diff --check`, staged-file
  inspection were run).
- **C8 adds a Phase 4 test with KNOWN ERRORS.** Isolated
  `runtests('tests/test_ieee14_1sg_4ibr_phase4.m')` observed:
  **5 passed / 5 errored (failed+incomplete)**.
- After C8, a full `runtests('tests',...)` is therefore expected to show
  **5 failures / 5 incomplete** in addition to the 475 green baseline. This is
  the known WIP state, not a regression of prior work.

## Phase 4 test errors — root cause (diagnosed, fix DEFERRED to Agent B)

Root cause (verified in isolation): the test helper `build_synthetic_devices`
in `tests/test_ieee14_1sg_4ibr_phase4.m` initializes with
`devs = repmat(struct(), 0, 1)`, which creates a **0-field empty struct**.
Concatenating it with the 13-field device structs (`[devs; dev]`) raises
"Number of fields in structure arrays being concatenated do not match." This
is the **MATLAB empty-struct trap, NOT a path / fixture-resolution issue**
(confirmed: `fixtures.synthetic_ibr_equilibrium` resolves and returns a
13-field struct once `tests/` is on the path; all three modes share the same
13 fields).

- 5 PASSING: SG1 data sourced (Kodsi), dispatch Pmax-proportional, no-load-shed,
  current-within-ImaxSS, no-external-solver grep guard.
- 5 ERRORING (all blocked by the concat trap before reaching the solver):
  `test_mixed_equilibrium_sg_on`, `test_mixed_equilibrium_sg_off_gfm`,
  `test_pure_gfl_island_rejected`, `test_equilibrium_fingerprint_deterministic`,
  `test_reference_gauge_fixed`.

**Why deferred:** the 1-line idiom fix (seed `devs` with the first device
rather than a 0-field empty) is trivial, but applying it uncovers the next
layer — `mixed_equilibrium_solve` against `composite_dae` + the synthetic
stubs — which needs its own debugging pass and re-verification. Committing an
unverified fix would violate the no-unverified-change rule; the checkpoint
directive forbids rerunning. So the honest WIP state is committed as-is.

## Phase 4 scope added in C8

- `+stability/mixed_equilibrium_solve.m` — in-house coupled Newton equilibrium
  solver. Fixed bus-1 angle-gauge (`vcon.vars=[1,2]`, `vcon.rows=[1,2]`,
  `ref=[V1_mag;0]`) present in ALL configs (correction 4). Pure-GFL SG_OFF
  rejected structurally (`noVoltageFormingSource`). Caller-supplied
  `config.devices` (scope separation: production `+stability` does not depend
  on `tests/+fixtures`). No external solver — grep-guard verified in the
  isolated Phase 4 run: no fsolve/optimoptions/fmincon/fminsearch/lsqnonlin/
  optimset.
- `tests/+fixtures/synthetic_ibr_equilibrium.m` — test-only IBR stubs
  (gfl/GFM/tripped), `ASSUMED_DIAGNOSTIC` scaffolding (f=0 equilibrium stubs,
  NOT the full REGFM_B1 dynamics — those are Phase 5-6).
- `tests/test_ieee14_1sg_4ibr_phase4.m` — 10 tests (5 pass / 5 error).

## Equations / source-closure status

Six Phase 1 blockers resolved as CASE_DEFINED / PROJECT_DERIVED engineering-
design contracts in `docs/project/IEEE14_IBR_DECISION_LEDGER.md` (C6): SG1
dynamics (Kodsi TR 2003-3 Table A.2, 60 Hz, 615 MVA, 6th-order EMF6, no dataset
mixing); dispatch (Pmax-proportional, 219 MW deficit, no load-shed); GFL↔VSG
transfer + inactive-state rule (PROJECT_DERIVED); current limits (REGFM_B1
Table 1 example); synchronism thresholds/dwell/timeout (verified standard
ranges, frozen before results); delays (verified standard ranges); gamma_req
= 0.1 rad/s (a-priori 5% damping at 1 Hz). Per-equation provenance in
`IEEE14_IBR_EQUATION_SOURCE_MATRIX.md` and `IEEE14_IBR_FROZEN_CONTRACT.md`.

## Shared `+stability` files changed (committed in C2–C4, NOT this checkpoint)

- `+stability/ts_simulate.m` — `event_id_at` generic-path branch (C4).
- `+stability/ts_adaptive_driver.m` — `event_id_lookup` generic-path branch
  (C4). **Full driver-loop hybrid_state ownership + guard-evaluation-after-
  accept + coincident-ordered sequencing NOT yet implemented** (deferred —
  needs a real device model to exercise).
- `+stability/ts_event_transition.m` — 10-arg overload (hybrid_state); legacy
  9-arg path bit-identical (C3).
- New event helpers (C2): `ts_hybrid_state_init`, `ts_hybrid_state_snapshot`,
  `ts_transitions_from_legacy`, `ts_prevalidate_transitions`,
  `ts_apply_transition`, `ts_evaluate_guards`.
- Track A legacy AbsTol=0 gates preserved (verified green at C5).

C8 adds NO shared Track A file changes. The only `+stability` file added in C8
is `mixed_equilibrium_solve.m`, which is mission-owned (not a Track A kernel).

## Single-owner status

This branch is the SOLE integration owner for the IEEE14 IBR mission. No other
agent is writing `feature/ieee14-auto-vsg-switching` (origin does not yet have
it; verified `git ls-remote` returns empty before push).

## Exact continuation point for Agent B

1. Fix the empty-struct trap in
   `tests/test_ieee14_1sg_4ibr_phase4.m` > `build_synthetic_devices` (seed
   `devs` with the first device instead of `repmat(struct(),0,1)`).
2. Run `runtests('tests/test_ieee14_1sg_4ibr_phase4.m')` — the 5 solver tests
   will then exercise `mixed_equilibrium_solve` against `composite_dae` + the
   synthetic stubs. Debug convergence / Jacobian / `config_hash` as needed.
3. Once Phase 4 tests pass (0 fail / 0 incomplete), run the FULL regression and
   record the fresh count (must be 475+5 = 480/0/0 or better).
4. Proceed to Phase 5 (sourced GFL model) per the canonical plan
   `docs/project/plans/IEEE14_1SG_4IBR_AUTO_VSG_SWITCHING_PLAN.md`.

## Files Agent B must NOT modify before synchronization

- `main` (no merge / rebase / force-push / main modification).
- Other worktrees: `Power-flow-adaptive`, `Power-flow-ibr-interface` (dirty,
  Track A), Padiyar/report worktrees.
- Stash `eae0bcd` (Track B preservation).
- User-owned dirty files in the main worktree: `+stability/ts_simulate.m`,
  `run_ts.m`, `solve_case.m`, `scripts/plot_ts_result.m`,
  `docs/project/AGENT_HANDOFF.md`, plus the untracked Padiyar two-area work.
- Track A legacy AbsTol=0 gates, equations, tolerances, FD steps, timestep /
  event values, iteration caps.

## Reproduce / checkout

```bash
git clone https://github.com/123456mmass/Power-flow.git
cd Power-flow
git fetch origin
git switch --track origin/feature/ieee14-auto-vsg-switching
```

```matlab
restoredefaultpath;
cd('<worktree>');
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);   % last green 475/475/0/0 at C5; C8 adds 5 known errors
runtests('tests/test_ieee14_1sg_4ibr_phase4.m');   % 5 pass / 5 error (concat trap, see above)
```

No merge, rebase, force-push, or main modification occurred. No dirty user-
owned file was touched. Stash `eae0bcd` intact.
