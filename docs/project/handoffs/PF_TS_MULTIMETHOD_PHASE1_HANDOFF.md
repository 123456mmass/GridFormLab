# PF/TS Multi-Method — Phase 1 Machine-Transfer Checkpoint

**Status:** WIP / CHECKPOINT — machine transfer, NOT a release. No
production-readiness claim. Production routing remains NOT_READY.

**Branch:** `plan/pf-ts-multimethod`
**Worktree:** `/home/birds/Documents/Power-flow-pf-ts-method-plan`
**Base:** `31a211d` (Track A IBR interface foundation tip; 16 commits ahead of `main`)
**Checkpoint (multi-method work):** `1731956`
**Merge-base with `main`:** `f59076f` (= `main` HEAD; `main` is an ancestor)
**Last updated:** 2026-07-13

## Last observed test count (fresh, this session)

- Full regression: **528 passed / 0 failed / 0 incomplete**
  (`restoredefaultpath; cd worktree; pf_init_paths; runtests('tests','IncludeSubfolders',true)`)
- Targeted gates: **125 passed / 0 failed / 0 incomplete**
  (PF/TS routing, FDPF, BFS fail-closed, P3.5 Jacobian, BE, RK4,
  no-external-solver scanner, trap/NR bit-identity AbsTol=0).

No files changed after this green run, so the count is current.

## What is in this branch (multi-method, CORE_ONLY / NOT_ROUTED)

23 new files added in checkpoint `1731956` (parent `31a211d`):

- **PF factories:** `+pfsolver/pf_resolve_method.m`, `+pfsolver/pf_method_strategy.m`
- **FDPF:** `+pfsolver/powerflow_fdpf.m` (shared, variant arg),
  `powerflow_fdpf_xb.m`, `powerflow_fdpf_bx.m` (thin wrappers),
  `internal/core/pf_build_b_matrices.m`, `internal/core/pf_find_q_limit_violations.m`
- **BFS:** `+pfsolver/powerflow_bfs.m`, `internal/core/pf_validate_radial_topology.m`
- **TS factories:** `+stability/resolve_ts_integrator.m`, `+stability/ts_integrator_step.m`
- **TS integrators:** `+stability/ts_coupled_jacobian.m` (P3.5 gate),
  `+stability/ts_step_be.m`, `+stability/ts_step_rk4.m`
- **Source register:** `docs/project/plans/PF_TS_MULTIMETHOD_SOURCES.csv`
- **Tests (8):** `test_p0_multimethod_factories`, `test_p1_fdpf`, `test_p2_bfs`,
  `test_pf_routing_end_to_end`, `test_ts_coupled_jacobian`,
  `test_ts_backward_euler`, `test_ts_rk4`, `test_ts_integrator_routing`

## Implemented methods and capability limits

- **PF:** `newton_raphson` (default, bit-identical AbsTol=0), `fdpf_xb`,
  `fdpf_bx` (both variants, shared solver), `bfs` (Phase-1 radial only:
  one REF, all PQ, radial tree, unity taps, zero phase, const-power, no
  shunt/charging — all other features fail closed).
- **TS:** `trapezoidal` (default, bit-identical AbsTol=0), `backward_euler`
  (L-stable, order 1, FIXED-STEP only), `rk4` (order 4, diagnostic,
  FIXED-STEP only). `esdirk32` = `notYetApproved` (no executable handle,
  no scaffold file — source-gated).

## Source/provenance status

- FDPF: Stott-Alsac 1974 (DOI 10.1109/TPAS.1974.293985) + van Amerongen 1989
  (DOI 10.1109/59.192932) — equation-level verified, `SOURCE_VERBATIM`.
- BFS: Shirmohammadi 1988 (DOI 10.1109/59.192932) eqs 1/2/3 — verified,
  `SOURCE_VERBATIM`.
- Backward Euler: NAODE book §4.1 eq 4.9, L-stability §8.4.1 — verified,
  `NUMERICAL_METHOD`.
- RK4: Süli & Mayers 2003 p.352 Butcher tableau — verified, `NUMERICAL_METHOD`.
- P3.5 coupled Jacobian: central-FD `h*=eps^(1/3)~6e-6` per block, derived
  (Süli & Mayers) — `PROJECT_DERIVED`, `VERIFIED_SOURCE_LOCATED`.
- ESDIRK32: `EQUATION_LOCATION_PENDING` — NOT registered, no scaffold.

## Factory-only routing — production status NOT_READY

Factories and solvers are package-level, tested by DIRECT calls. They are
NOT wired into `solve_case.m` / `ts_simulate.m` / `ts_adaptive_driver.m`
(those single-owner files are NOT modified in this branch). Production
routing remains **NOT_READY** until Phase 2 (single-owner wiring) is
separately approved.

## Shared files deliberately untouched

`solve_case.m`, `run_ts.m`, `run_pf.m`, `run_ssa.m`, `scripts/plot_ts_result.m`,
`pf_init_paths.m`, `+stability/ts_step_kernel.m`, `+pfsolver/powerflow_newton_raphson.m`,
all SSSA files (`multimachine_ssa.m`, `multicase_sssa.m`, `synchronous_emf6_ssa.m`,
`padiyar_model11_ssa.m`, `padiyar_model11_dae.m`, `classical_ssa.m`,
`composite_dae.m`) — NONE modified by the multi-method work.

## Outstanding shared-file ownership conflict

`solve_case.m` and `+stability/ts_simulate.m` are BOTH user-owned dirty on
`main` (interactive dialog system: `prompt_pf_options`/`prompt_ts_options`/
`case_selection_interactive`) AND on the `TRACK_COORDINATION.md` single-owner
list. Phase 2 production wiring requires editing these files and is BLOCKED
until the user checkpoints the dialog system and grants single-owner ownership.
The dirty dialog files are preserved on `main` and are NOT in this branch.

## Phase 2 synchronization procedure (for Agent B)

1. User checkpoints dirty-main dialog system and grants ownership of
   `solve_case.m`, `ts_simulate.m`, `ts_simulate_emf6.m`,
   `ts_simulate_padiyar_model11.m`, `ts_adaptive_driver.m`.
2. PF wiring: `solve_case.m:87` → `pf_resolve_method` + `pf_method_strategy`
   factory call; add `pf_method` default `'newton_raphson'`; metadata fields.
3. TS wiring: resolve integrator before fixed-step loop in each of the 3
   model routes + `ts_adaptive_driver.m`; add adaptive+{BE,RK4} fail-closed
   gate (`adaptiveNotFrozen`); metadata `res.integrator`.
4. Default paths must remain AbsTol=0 (bit-identical) — gated by tests.
5. Full regression must pass on each Phase-2 commit (fresh count recorded).

See the canonical plan (Part 2 — Production Integration Plan) for the full
file-by-file change list, acceptance gates, and stop conditions.

## Agent B continuation commands

```bash
git clone https://github.com/123456mmass/GridFormLab.git
cd Power-flow
git fetch origin
git switch --track origin/plan/pf-ts-multimethod
```

Then verify:
```bash
git branch --show-current          # plan/pf-ts-multimethod
git rev-parse HEAD                 # must match remote (see handoff report)
git rev-parse main                 # f59076f
git merge-base HEAD main           # f59076f
git status --short                 # clean
```

Reproduce the green run:
```matlab
restoredefaultpath;
cd('<worktree>');
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);   % expect 528/0/0
```

## Stop conditions

Stop and ask if: dirty user-owned file must be modified; main has diverged
and rebase would conflict; a model route's BE/RK4 diverges; event semantics
differ by integrator; implementation requires external solvers; results
improve only after tuning; SSSA scope creep; ownership ambiguous; esdirk32
must silently fall back.
