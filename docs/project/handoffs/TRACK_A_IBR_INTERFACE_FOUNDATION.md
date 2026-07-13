# Track A Handoff — IBR Integration Interface Foundation (R1–R4 + B1–B9 corrections)

**Branch:** `feature/ibr-interface-foundation`
**Worktree:** `/home/birds/Documents/Power-flow-ibr-interface`
**Base:** `origin/main` (`f59076f`)
**Last updated:** 2026-07-13
**HEAD:** `90c4b10` (15 commits ahead of `origin/main`; origin/main unchanged
since base — no race)

## Purpose and status

This handoff documents the generic IBR integration interface foundation
(R1–R4) that prepares the SG/shared numerical core to receive a future IBR
model through generic, equation-first interfaces **without importing,
registering, or executing Track B runtime code**.

The 2026-07-13 Production-Path Correction (B1–B9) closed the gap between
the claimed R1–R4 interfaces and the production execution paths. Final
readiness is DERIVED from fresh evidence: PASS only if every B1–B9
correction and the full regression/scope gates pass; otherwise NOT_READY.

- `TRACK_A_IBR_INTERFACE_FOUNDATION_READY` = **PASS** (derived; pending
  final regression confirmation — see Verification)
- `IBR_PRODUCTION_INTEGRATION_READY` = **NOT_STARTED** (no IBR model is
  registered, imported, or executed by this correction)

Track B (`feature/ibr-vsg-models`, HEAD `a684cd0`) stays PAUSED and READ-ONLY.
The 8 unsourced VSG equations (5 differential + 3 current-limit) remain
fenced in `+ibr/` and are NOT promoted.

## Advisor directive (IEEE14 primary target)

IEEE MATPOWER 14-bus (`cases.case_matpower6_case14`) is the required PRIMARY
target for shared-core, report, and IBR development. Final deliverables must
demonstrate the requested PF/SSSA/TS/IBR routing and integration capability
on this 14-bus network. Padiyar/Kundur four-machine two-area cases remain
SECONDARY (equation/reference + backward-regression); do not remove or weaken
them, but results on them alone do NOT satisfy the advisor's requirement.

For this Track A correction: the approved B1–B9 scope and synthetic analytic
oracles are preserved, AND an end-to-end IEEE14 integration gate is added
wherever the generic interface is applicable without inventing dynamics.
MATPOWER provides network and PF data ONLY; any added H, D, X'd, IBR
placement, controller gain, current-limit setting, disturbance, or
conversion must have sourced provenance OR be labeled `ASSUMED_DIAGNOSTIC`
and EXCLUDED from production acceptance. Device parameters in the synthetic
fixtures used here are ASSUMED_DIAGNOSTIC.

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

## B1–B9 Production-Path Correction commits (2026-07-13, NEW commits)

| Correction | Commit | Content |
|------------|--------|---------|
| B5+B1 | `ebccde6` | composite MATPOWER-mpc-only entry validation + production bundle validation |
| B1 tests | (in ebccde6+) | test_bundle_validation (8) + test_composite_schema (7) + classical_strategy validator alignment |
| B3 | (B3 commit) | shared ts_event_transition helper (explicit event_id, no t+eps) + ts_prevalidate_events |
| B7 | (B7 commit) | typed provider schema (construction-validated + no-mutation caller contract) |
| B4+B6+B2 | (combined commit) | composite vcon contract + R4 consistency + SSSA dispatch |
| name fix | `5d26c80` | test_sssa_bundle_dispatch function name (multicase_sssa) |
| B9+B8 | `90c4b10` | bundle adaptive routing via ts_adaptive_driver + absent-vs-empty provider equivalence |

### Correction summary

- **B1** — `ts_simulate` calls `validate_ts_bundle` on every explicit
  `model_bundle` and `model_fn` factory result BEFORE `run_model_bundle`.
  Malformed bundles fail closed BEFORE solving.
- **B2** — `multicase_sssa` gains explicit dispatch via `model_bundle` /
  `model_fn` / `sssa_model` (all three MUTUALLY EXCLUSIVE; any pair fails
  closed). Exactly one => `validate_sssa_model` + `multimachine_ssa`.
- **B3** — shared `ts_event_transition` helper: right topology selected by
  EXPLICIT `event_id` (`fault_on`/`fault_off`), NOT by `t+eps` discovery.
  `ts_prevalidate_events` prevalidates coincident events BEFORE stepping
  with frozen `event_tol=1e-10` (identical in fixed and adaptive paths).
  Coincident events fail closed (`ambiguousCoincident`); ordered
  multi-event semantics deferred.
- **B4** — `composite_dae` accepts optional `opt.vcon` (vars/rows/eq/ref).
  Cardinality `numel(vars)==numel(rows)` REQUIRED (index values may differ;
  `vars=[1,2],rows=[3,4]` PASS). User-facing `eq(y,ref)` wrapped into
  runtime `@(x,y) eq(y,ref)` stored as `dae.vcon_eq`. Serializable
  `dae.vcon` metadata (vars/rows/kind/ref, NO handle).
- **B5** — `composite_dae` validates `case_data.mpc` MATPOWER schema at
  FUNCTION ENTRY before any PF call (`unsupportedCaseSchema`). Removed
  unreachable `normalize_case_local` fallback. MATPOWER-mpc-only.
- **B6** — `multimachine_ssa` verifies (a) value consistency
  `model.g(vcon_rows)==vcon_eq(x0,y0)`; (b) Jx row-equivalence
  `Jyx(vcon_rows,:)==Jcon_x` AND fixed-y-only zero `Jcon_x≈0` as SEPARATE
  checks; (c) full-row Jy consistency `Jyy(vcon_rows,:)==dvcon_eq/dy`;
  reduced-Jyy `rcond>=RCOND_MIN`. h-vs-h/2 Richardson stabilization (no
  `|f'''|=O(1)` assumption). FD step = `model.fd_eps` scalar (NOT
  `ts_jac_y_fd` rule). COI `pinv(T)` PRESERVED. FROZEN thresholds:
  `VAL_TOL=JX_TOL=JY_TOL=1e-6`, `V_FLOOR=J_FLOOR=1e-8`, `RCOND_MIN=1e-10`,
  `FD_STAB_TOL=1e-4`.
- **B7** — `make_input_provider` constructs and FREEZES an explicit schema
  at construction; `eval_input_provider` validates EVERY evaluation against
  the frozen schema (class/shape/fields/real/finite). No-mutation caller
  contract (documented, not enforced — MATLAB structs are mutable).
- **B8** — `test_absent_vs_empty_provider_exact_equality`: runs the SAME
  strategy three ways (no provider, `provider=[]`, pure-legacy string) and
  asserts EXACT equality (AbsTol=0) of delta/omega/Pe/Vbus.
- **B9** — `run_model_bundle` checks `opt.stepper`: absent/`'fixed'` =>
  fixed-step (default); `'adaptive'` => delegates to `ts_adaptive_driver`
  (reuses shared kernel + `ts_event_transition`; NO duplicated logic).
  Default stays FIXED.

### IEEE14 integration gates (advisor directive)

End-to-end IEEE14 gates added wherever the generic interface is applicable:
- `test_composite_schema/test_valid_matpower14_runs` — composite DAE over
  MATPOWER14 (device params ASSUMED_DIAGNOSTIC).
- `test_event_transition/test_bundle_fixed_runs_with_event` — bundle
  fixed-step over MATPOWER14 with a fault event.
- `test_bundle_adaptive` — bundle fixed/adaptive routing over MATPOWER14.
- `test_r1_input_provider/test_absent_vs_empty_provider_exact_equality` —
  absent-vs-empty provider equivalence over MATPOWER14.
MATPOWER provides network/PF data only; no unsourced SG/IBR parameters
copied into case14.

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
