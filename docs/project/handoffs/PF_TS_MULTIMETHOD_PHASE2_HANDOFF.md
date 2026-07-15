# PF/TS Multi-Method Phase-2 Production Routing Handoff

Date: 2026-07-15
Branch: `wip/pf-ts-phase2`
Worktree: `C:\Users\User\Desktop\Power-flow-pf-ts`
Base (tested): `origin/main` = `17d2050` ("Fix and verify G2 active-bound solver
contract") — a descendant of `b555027` and `b6cad39`.
Merge-base with `main`: `17d2050` (branch was created from the clean
post-Agent-A `main`; `main` is an ancestor of this branch tip).

This handoff records the Phase-2 production wiring of the existing CORE_ONLY
/ NOT_ROUTED PF and TS factories into the single-owner dispatchers. It is PURE
WIRING: no new equations, no new solver/integrator files, no edits to the
canonical `powerflow_newton_raphson.m` or `ts_step_kernel.m`.

## Honest readiness statuses

```text
PF_PROGRAMMATIC_ROUTING_READY     = PASS      (gates below)
PF_INTERACTIVE_SELECTION          = DEFERRED (dialogs untouched)
BFS_ROUTED_CAPABILITY             = GATED     (meshed catalog fail-closed; radial factory-only)
TS_INTEGRATOR_ROUTING_READY       = PASS      (gates below)
RK4_STATUS                        = DIAGNOSTIC_ONLY
ADAPTIVE_BE_RK4                   = FROZEN_OUT (adaptiveNotFrozen, route + driver)
ESDIRK32                          = NOT_YET_APPROVED (notYetApproved, no scaffold)
```

## Scope (programmatic API routing only)

This slice wires the factories into `solve_case` (PF) and `ts_simulate` /
`ts_simulate_emf6` / `ts_simulate_padiyar_model11` / `ts_adaptive_driver` (TS).
The supported surface is the NON-INTERACTIVE programmatic API:
`solve_case('analysis','pf','options',struct('pf_method',...))` and
`solve_case('analysis','ts',...,'options',struct('integrator',...))`.

The interactive dialogs (`prompt_pf_options`, `prompt_ts_options` in
`solve_case.m`) are NOT modified; `prompt_ts_options` continues to restrict
`opt.method` to `'trapezoidal'` (interactive users stay on trapezoidal).
Programmatic users can pass any registered integrator.

## Files changed (exact allowlist)

- `solve_case.m` — PF dispatch wiring (line 92) through
  `pf_resolve_method` + `pf_method_strategy`; NR metadata enrichment
  (fill-if-missing, never clobbers FDPF/BFS `method_executed` 'XB'/'BX'/'bfs');
  method-neutral PF label; logs report `Method executed` + `Dispatch req`.
- `+stability/ts_simulate.m` — removed `method='trapezoidal'` pre-resolution
  default (line 24) so selector provenance is truthful; resolve+gate INSIDE the
  `model_bundle`/`model_fn` branches and the classical built-in path (exactly-
  one resolution per executed route; Padiyar/EMF6 dispatched unresolved);
  `step_fn` at classical (266) and bundle (638) call sites; endpoint
  algebraic-residual evidence + gate; metadata via `ts_method_metadata`.
- `+stability/ts_simulate_emf6.m` — resolve+gate before DAE construction;
  `step_fn` at EMF6 call site; `method` field fix (adaptive line 237);
  endpoint residual + metadata.
- `+stability/ts_simulate_padiyar_model11.m` — resolve+gate before DAE;
  `step_fn` at Padiyar call site; `method` field fix (lines 96, 170);
  endpoint residual + metadata.
- `+stability/ts_adaptive_driver.m` — REAL fail-closed guard (not a comment):
  reads `opt.integrator`, rejects every non-trapezoidal integrator with
  `ts_adaptive_driver:adaptiveNotFrozen` BEFORE any step. Constants
  p=2/denom=3/exp_ctl=1/3 unchanged (trapezoidal-only reachable).
- `+stability/ts_method_metadata.m` (NEW) — shared additive metadata:
  `method_requested`/`method_executed`/`dispatch_requested` (canonical name),
  `method_source` (impl provenance), `selection_source` (default/explicit_*
  selector), `capability`, `runtime_diagnostic` (rk4 only), `fallback_used`,
  `dispatch`.
- `tests/test_pf_phase2_solve_case_routing.m` (NEW) — 8 end-to-end PF tests.
- `tests/test_ts_phase2_integrator_routing.m` (NEW) — 20 end-to-end TS tests
  incl. provider BE/RK4 bundle + stage-time oracle + event landing/right-limit
  oracle.

NOT touched: `powerflow_newton_raphson.m`, `ts_step_kernel.m`, the factory
files (`pf_resolve_method`, `pf_method_strategy`, `resolve_ts_integrator`,
`ts_integrator_step`), the integrator files (`ts_step_be`, `ts_step_rk4`),
event helpers (`ts_topology_at`, `ts_event_transition`,
`ts_prevalidate_events`, `validate_ts_strategy`, `validate_ts_bundle`,
`make_input_provider`), SSSA files, `pf_init_paths.m`, interactive dialogs.

## Contracts delivered

- `opt.pf_method` resolves through the project-owned strategy (default
  `newton_raphson`, bit-identical AbsTol=0).
- `opt.integrator` takes precedence over legacy `opt.method`
  (`resolve_ts_integrator` precedence: explicit_integrator >
  explicit_method_alias > default).
- No silent fallback: unknown PF method → `pf_resolve_method:unknownMethod`;
  unknown integrator → `resolve_ts_integrator:unknownIntegrator`;
  `esdirk32` → `notYetApproved`; BFS on meshed topology →
  `pf_validate_radial_topology:*`.
- Default NR + trapezoidal outputs remain AbsTol=0 (bit-identical).
- `adaptive + backward_euler/rk4` fails `adaptiveNotFrozen` at BOTH route
  level (`ts_simulate:adaptiveNotFrozen`, `ts_simulate_emf6:adaptiveNotFrozen`,
  `ts_simulate_padiyar_model11:adaptiveNotFrozen`) AND driver level
  (`ts_adaptive_driver:adaptiveNotFrozen`).
- All event/right-limit behavior unchanged (no edits to topology/event helpers;
  step uses `Y_now`, right-limit re-solved at `t_next` with `Y_next`).
- RK4 `capability='diagnostic'`, `runtime_diagnostic=true`; never default,
  never interactive choice.
- Metadata: `method_source` (implementation provenance) vs `selection_source`
  (default/explicit_* selector) are DISTINCT. FDPF/BFS `method_executed`
  ('XB'/'BX'/'bfs') preserved; NR `full_ac_mismatch` sourced from existing
  `max_mismatch`. `method_requested` NOT uniform across NR/XB/BX/bfs.
- `dispatch_requested` = canonical resolver name for every PF method.
- Endpoint algebraic-residual evidence additive:
  `res.integrator_algebraic_residual` (per-step vector) +
  `res.max_integrator_algebraic_residual`; coupled BE/RK4 gated vs `g_tol`.
- No external solver (`test_no_external_solver_dependency` green).

## Evidence (fresh, this branch)

Tested tree: `wip/pf-ts-phase2` (commits C2 + C3). MATLAB R2025a.

Baseline (pre-C2, on `17d2050`): 747 total / 743 passed / 0 failed / 4
incomplete (4 = PGAz conversion contract, filtered by assumption — PGAz not
installed; not new failures).

Targeted gates (post-C3):
- `test_pf_phase2_solve_case_routing`: 8/0
- `test_ts_phase2_integrator_routing`: 20/0
- `test_p0_multimethod_factories`: 16/0
- `test_pf_routing_end_to_end`: 7/0
- `test_nr_solver`: 11/0, `test_pf_contract`: 23/0,
  `test_solve_case_launcher`: 1/0
- `test_ts_strategy_equivalence`: 2/0, `test_ts_shared_kernel`: 6/0,
  `test_ts_default_routing`: 7/0, `test_ts_integrator_routing`: 11/0,
  `test_ts_backward_euler`: 5/0, `test_ts_rk4`: 6/0,
  `test_ts_result_schema`: 8/0, `test_ts_simulate_general`: 11/0,
  `test_ts_coupled_jacobian`: 7/0
- `test_no_external_solver_dependency`: 12/0

Full post-C3 regression: 775 total / 771 passed / 0 failed / 4 incomplete
(4 = PGAz conversion contract, filtered by assumption — PGAz not installed;
same 4 as baseline). Versus baseline (747 total / 743 passed): +28 tests
(8 PF + 20 TS), all passing. A full PASS is invalidated by subsequent source
changes.

## Commands

```matlab
restoredefaultpath; cd('C:/Users/User/Desktop/Power-flow-pf-ts'); pf_init_paths;
% Targeted:
runtests('tests/test_pf_phase2_solve_case_routing.m')
runtests('tests/test_ts_phase2_integrator_routing.m')
% Full:
r = runtests('tests','IncludeSubfolders',true);
```

## Commit split

- **C2** (`87e943c`) — PF wiring (`solve_case.m`) + label + log +
  `test_pf_phase2_solve_case_routing.m`.
- **C3** (this commit) — TS wiring (4 files) + `ts_method_metadata.m` +
  `test_ts_phase2_integrator_routing.m`.
- **C4** (this doc) — handoff with honest statuses.

## Known limitations / deferred

- Interactive dialogs unchanged (`PF_INTERACTIVE_SELECTION = DEFERRED`); a
  capability-aware method menu is a separately-approved UI change.
- BFS is catalog-gated: no radial catalog case exists, and `solve_case`
  cannot accept an inline three-bus case, so BFS SUCCESS is asserted by the
  existing direct-factory `test_pf_routing_end_to_end` (factory-level inline
  radial). A radial catalog expansion is a separate approval.
- RK4 is diagnostic-only (bounded stability region, not A-stable).
- ESDIRK32 remains `notYetApproved` (source-gated; no scaffold created).
- Adaptive BE/RK4 is FROZEN OUT (the method-specific algebraic adaptive-error
  definition is not frozen; `adaptiveNotFrozen`).
- Provider-bearing BE/RK4 bundle tests use a minimal synthetic linear-ODE
  oracle (no `+ibr` reference); composite/IBR provider bundles are out of
  scope for this slice.

## Delivery

Independent read-only review pending. Fast-forward `main` and push ONLY if
`main` is unchanged since `17d2050`; if `main` moved, stop for
synchronization approval (do not rebase/merge without explicit approval).
