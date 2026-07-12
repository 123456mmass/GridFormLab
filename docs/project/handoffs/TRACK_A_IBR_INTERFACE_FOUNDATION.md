# Track A Handoff — IBR Integration Interface Foundation (R1–R4)

**Branch:** `feature/ibr-interface-foundation`
**Worktree:** `/home/birds/Documents/Power-flow-ibr-interface`
**Base:** `origin/main` (`f59076f`)
**Last updated:** 2026-07-12

## Purpose and status

This handoff documents the generic IBR integration interface foundation
(R1–R4) that prepares the SG/shared numerical core to receive a future IBR
model through generic, equation-first interfaces **without importing,
registering, or executing Track B runtime code**.

- `TRACK_A_IBR_INTERFACE_FOUNDATION_READY` = **PASS**
- `IBR_PRODUCTION_INTEGRATION_READY` = **NOT_STARTED**

Track B (`feature/ibr-vsg-models`, HEAD `a684cd0`) stays PAUSED and READ-ONLY.
The 8 unsourced VSG equations (5 differential + 3 current-limit) remain
fenced in `+ibr/` and are NOT promoted.

## Commits (8 phases, separate commits)

| Phase | Commit | Content |
|-------|--------|---------|
| 1 | `af1b088` | Design document (R1–R4) |
| 2 | `9854a78` | R1 mechanical — provider-aware path (legacy untouched) |
| 3 | `b512bde` | R1 behavior — input provider + synthetic Duhamel oracle |
| 4 | `3aa4ad9` | R2 mechanical — bundle dispatch precedence |
| 5 | (in 3aa4ad9+behavior) | R2 behavior — validators + synthetic plugin + tests |
| 6 | `a8ce4b3` | R3 — composite DAE assembler (single owner) |
| 7 | `9207269` | R4 — paired vcon Schur elimination |
| 8 | (this commit) | Regression + scope audit + handoff |

## R1 — Exogenous typed input provider

- `make_input_provider` / `eval_input_provider`: immutable, side-effect-free.
  Exogenous `fn(t, event_context)` (NO state dependence). Endpoint evaluation
  at t, t+h/2, t+h. Absent provider = EXACT legacy path (no `u` argument,
  FP-identical). Provider-aware path is SEPARATE from legacy.
- `ts_algebraic_solve_u`: thin wrapper binding `u` into closures, delegates
  to `ts_algebraic_solve` (one Newton owner).
- Tests: 7/7 (constant/callback/immutable/finite-validation/Duhamel oracle/
  rejected-trial consistency/absent=legacy).

## R2 — Model bundle dispatch

- Precedence: `opt.model_bundle` > `opt.model_fn` > built-in string.
  `model_bundle`/`model_fn` mutually exclusive (fail-closed). Provenance
  metadata (`built_in_string` | `explicit_model_fn` | `explicit_model_bundle`);
  function handles NEVER serialized.
- `validate_ts_bundle` (top-level), `validate_ts_strategy` (internal step
  layer), `validate_sssa_model` (SSSA capability) — SEPARATE validators.
- Bundle: `bundle.ts` = strategy+x0+y0+topology+mapping+metadata;
  `bundle.sssa.model`. `ts_strategy` stays internal to the step layer.
- Tests: 10/10 (string unchanged, model_fn, model_bundle, mutual-exclusion,
  missing-field, linear-mismatch, missing-ts, sssa-missing, free_y/vcon
  exclusive, no-+ibr grep guard).

## R3 — Composite DAE (single owner)

- `composite_dae`: single owner of shared y, topology, mapping, KCL
  `g = Y*V - Ibus` (canonical YV-I), slack/reference constraint replacement,
  state/input offsets. Devices return POSITIVE current injection only; NO
  production sign adapter (sign conversion `g_composite = -g_sg` is test-only).
- Frozen device signatures: `f`/`current_injection`/`reconstruct`
  `(t, x_dev, y, u_dev, event_context)`. Slicing uses `nx` (ns optional).
- Deterministic device-contiguous offsets via cumulative sums.
- Tests: 10/10 (two-device KCL structure, KCL at every bus, shuffled IDs,
  multi-device/bus, empty fail-closed, invalid bus fail-closed, sign-flip
  exact, deterministic ordering, duplicate device_id fail-closed, composite
  TS finite). Synthetic one-device equivalence, NOT real-engine reproduction.

## R4 — Paired vcon Schur elimination

- `multimachine_ssa`: `vcon_vars`/`vcon_rows`/`vcon_eq` with `nr=size(Jyy,1)`,
  `ny=size(Jyy,2)`. `free_rows=setdiff(1:nr,vcon_rows)`,
  `free_vars=setdiff(1:ny,vcon_vars)`. Paired Schur:
  `A = Jxx - Jxy(:,free_vars)*(Jyy(free_rows,free_vars)\Jyx(free_rows,:))`.
- FIXED y-only: `vcon_eq(y, constant_reference)`, `Jcon_x==0` FD-verified
  (state-dependent => `stateDependentConstraintUnsupported` fail-closed).
  `Jcon_y` full-rank (rcond check). free_y and vcon STRICTLY field-level
  mutually exclusive; complete vcon set required. No inv/pinv.
- Tests: 11/11 (no-constraints SG unchanged, one slack square, KCL row
  replacement, state-dependent fail-closed, rank-deficient fail-closed,
  mismatched cardinality fail-closed, free_y+vcon conflict, partial vcon,
  two constraints, no-inv grep guard, bit-identical when absent).

## Verification gates (all PASS, fresh)

- Full regression: **389 passed / 0 failed / 0 incomplete** (was 351 on
  baseline; +38 new R1–R4 tests).
- SG fixed paths bit-identical (AbsTol=0): `test_ts_strategy_equivalence`
  (2/2), `test_ts_classical_strategy_equivalence` (3/3),
  `test_ts_characterization_fixed` (3/3).
- SSSA contract: `test_sssa_contract` (10/10) — R4 does NOT break Schur.
- Default routing: `test_ts_default_routing` (7/7) — default stays FIXED.
- Adaptive rollback: `test_ts_adaptive_rollback` (2/2).
- No external solver: `test_no_external_solver_dependency`.
- R1 7/7, R2 10/10, R3 10/10, R4 11/11.

## Scope audit (clean)

- No production reference to `+ibr`/`@ibr`/`register_model`/`model_fn`
  (pre-existing) in `+stability/`, `+cases/`, `solve_case.m`, `run_ts.m`,
  `pf_init_paths.m`.
- No `inv(Jyy)`/`pinv(Jyy)` in production `+stability/`.
- No test-only synthetic files in `+stability/` or production `+cases/`
  (they live in `tests/+fixtures/`, called as `fixtures.*`).
- No Track B/policy files modified (`+ibr/**`, `docs/ibr/**`, `AGENTS.md`,
  `CLAUDE.md`, `TRACK_COORDINATION.md`, `AGENT_HANDOFF.md` untouched).

## Files (new + modified vs `f59076f`)

**New (15):**
- `+stability/`: `make_input_provider.m`, `eval_input_provider.m`,
  `ts_algebraic_solve_u.m`, `validate_ts_bundle.m`, `validate_ts_strategy.m`,
  `validate_sssa_model.m`, `composite_dae.m` (7).
- `tests/+fixtures/`: `synthetic_linear_generator.m`,
  `synthetic_composite_cases.m`, `synthetic_slack_case.m` (3).
- `tests/`: `test_r1_input_provider.m`, `test_r2_model_dispatch.m`,
  `test_r3_composite_dae.m`, `test_r4_voltage_constraints.m` (4).
- `docs/project/plans/ibr_interface_foundation.md` (design doc).
- `docs/project/handoffs/TRACK_A_IBR_INTERFACE_FOUNDATION.md` (this file).

**Modified (mechanical, legacy bit-identical):**
- `+stability/ts_step_kernel.m` (provider path separate from legacy).
- `+stability/ts_model_strategy.m` (optional provider field + otherwise).
- `+stability/ts_adaptive_driver.m` (thread t/event_context on provider path).
- `+stability/ts_simulate.m` (bundle dispatch precedence + run_model_bundle).
- `+stability/multimachine_ssa.m` (vcon paired Schur, mutually exclusive).

## Reproduce (tracked files only)

```matlab
restoredefaultpath; cd('/home/birds/Documents/Power-flow-ibr-interface');
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);   % 389/389/0/0
runtests('tests/test_r1_input_provider.m');         % 7/7
runtests('tests/test_r2_model_dispatch.m');        % 10/10
runtests('tests/test_r3_composite_dae.m');         % 10/10
runtests('tests/test_r4_voltage_constraints.m');   % 11/11
```

## Limitations (honest)

- `IBR_PRODUCTION_INTEGRATION_READY = NOT_STARTED`. No IBR model is
  registered, imported, or executed.
- R3 composite equivalence is synthetic-vs-synthetic (composite path vs
  direct-call of the same fixture), NOT a claim of reproducing the real SG
  classical engine. Real SG behavior preserved by separate AbsTol=0 legacy
  regressions (unchanged legacy path).
- R4 supports only FIXED y-only voltage constraints (`Jcon_x==0`).
  State-dependent constraints are out of scope (different Schur derivation).
- The 8 unsourced VSG equations remain fenced in `+ibr/` (Track B).
- No push/merge of main; branch stays local until user-approved merge.

## When IBR production integration may proceed

ONLY after: (a) Track B sources the 8 unsourced VSG equations (or a
separately approved derivation), (b) a mixed SG/IBR integration owner is
assigned (TRACK_COORDINATION §9 Sync point 3), (c) the composite DAE is
exercised with a REAL IBR device adapter (not synthetic), and (d) every
gate passes on the integrated system. Any FAIL/NOT_READY => integration
stays NOT_STARTED.
