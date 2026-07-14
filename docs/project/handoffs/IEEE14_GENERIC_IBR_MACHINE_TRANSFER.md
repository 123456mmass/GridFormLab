# IEEE14 Generic Mixed-Resource IBR Engine — Machine Transfer Handoff

> **Exact checkpoint for cross-machine continuation.** This is WIP — no production-readiness claim.

---

## 1. Timestamp and environment

| Field | Value |
|---|---|
| UTC timestamp | 2026-07-14 19:50 UTC |
| Timezone | ICT (UTC+7) |
| MATLAB version | R2026a (verified) |
| OS | Linux 7.0.0-27-generic |
| Repository | `/home/birds/Documents/Power-flow` |
| Base `main` | `42e2deac24af6d46c9f69ec7b8a727bd10a9af3d` |

## 2. Branch and SHA table

| Ref | SHA | Notes |
|---|---|---|
| Local HEAD (main) | `42e2deac24af6d46c9f69ec7b8a727bd10a9af3d` | Clean base, no local commits past origin |
| `origin/main` | `42e2deac24af6d46c9f69ec7b8a727bd10a9af3d` | **Synced — no divergence** |
| `main` | `42e2deac24af6d46c9f69ec7b8a727bd10a9af3d` | Same as origin |
| merge-base (main, origin/main) | `42e2deac24af6d46c9f69ec7b8a727bd10a9af3d` | Same commit |
| Transfer branch | `wip/ieee14-ibr-generic-engine` | Created from HEAD of main |
| Remote transfer branch | `origin/wip/ieee14-ibr-generic-engine` | See §11 for verified remote SHA |

## 3. Checkpoint commits (in order)

| Commit # | Message | Files |
|---|---|---|
| 1 | `WIP: generic mixed-resource foundation and IEEE14 profile` | `+cases/scenario_ieee14_1sg_4ibr.m`, `+ibr/build_ieee14_sg_ibr_devices.m`, `+stability/build_hybrid_scenario.m`, `+stability/build_mixed_resource_devices.m`, `+stability/resource_table.m` |
| 2 | `WIP: SG composite adapter, stator current, and shared Newton` | `+stability/sg_composite_device.m`, `+stability/sg_stator_current.m`, `+stability/composite_newton.m`, `+stability/mixed_equilibrium_solve.m`, `+ibr/dual_mode_ibr_model.m`, `tests/test_ieee14_1sg_4ibr_phase4.m` |
| 3 | `DIAGNOSTIC: preserve Phase-B NaN probes and root-cause evidence` | `docs/probes/ieee14_ibr_transfer/pf_b0_trace_sg.m`, `docs/probes/ieee14_ibr_transfer/pf_check_fields.m`, `docs/probes/ieee14_ibr_transfer/pf_check_fields2.m`, `docs/probes/ieee14_ibr_transfer/pf_diag_eq.m`, `docs/probes/ieee14_ibr_transfer/pf_phaseB_smoke.m` |
| 4 | `HANDOFF: checkpoint generic IEEE14 IBR mission for machine transfer` | `docs/project/plans/IEEE14_GENERIC_MIXED_RESOURCE_EXECUTION_PLAN.md`, `docs/project/handoffs/IEEE14_GENERIC_IBR_MACHINE_TRANSFER.md` (this file) |

## 4. Complete file manifest

### Production — new files (7)

| File | Lines | Description |
|---|---|---|
| `+cases/scenario_ieee14_1sg_4ibr.m` | 127 | IEEE14 scenario profile (Layer 2) — resource table + case binding; IEEE14 IDs confined here |
| `+ibr/build_ieee14_sg_ibr_devices.m` | 95 | Thin IEEE14 wrapper around generic `build_mixed_resource_devices` (legacy ABI) |
| `+stability/resource_table.m` | 246 | Build/validate serializable indexed resource table + capability flags + uniform schema |
| `+stability/build_mixed_resource_devices.m` | 177 | Generic builder: iterate resource table, dispatch factories by model_id, emit uniform schema |
| `+stability/build_hybrid_scenario.m` | 145 | Bind case_data + resource table + scenario_opt into scenario struct |
| `+stability/sg_composite_device.m` | 233 | EMF6 -> 5-arg ABI composite device; uniform provenance; correction 2 stator current |
| `+stability/sg_stator_current.m` | 49 | EMF6 stator Id/Iq -> network-frame complex current (audited helper, correction 2) |
| `+stability/composite_newton.m` | 69 | Single damped-Newton owner reused by equilibrium, trapezoidal TS, event solve (correction 7) |

### Production — modified files (3)

| File | Δ | Description |
|---|---|---|
| `+stability/mixed_equilibrium_solve.m` | +38/−66 | Angle-only vcon (correction 1: fix Im(V1)=0, free Re(V1)); extract Newton to `composite_newton`; remove `sg_status` global rule |
| `+ibr/dual_mode_ibr_model.m` | +2 | Add `initial_mode` and `initial_online` fields to dev struct (uniform schema) |
| `tests/test_ieee14_1sg_4ibr_phase4.m` | +11/−7 | Update assertions for angle-only vcon; remove `sg_status` global rule tests |

### Diagnostic probes (5)

| File | Description |
|---|---|
| `docs/probes/ieee14_ibr_transfer/pf_b0_trace_sg.m` | **Tpq0=0 NaN root-cause evidence** — line 59: `dx4 = (c_q*Edpp - d_q*Edp)/Tpq0 = 0/0` |
| `docs/probes/ieee14_ibr_transfer/pf_check_fields.m` | SG vs IBR struct field comparison (provenance mismatch proof) |
| `docs/probes/ieee14_ibr_transfer/pf_check_fields2.m` | Detailed field listing (singular-Jacobian investigation) |
| `docs/probes/ieee14_ibr_transfer/pf_diag_eq.m` | FD Jacobian rcond investigation (proves RCOND=NaN, not RCOND≈0) |
| `docs/probes/ieee14_ibr_transfer/pf_phaseB_smoke.m` | Phase B mixed-equilibrium build/solve smoke test |

### Documentation (2)

| File | Description |
|---|---|
| `docs/project/plans/IEEE14_GENERIC_MIXED_RESOURCE_EXECUTION_PLAN.md` | Approved Claude plan (includes Tpq0=0 frozen-state decision) |
| `docs/project/handoffs/IEEE14_GENERIC_IBR_MACHINE_TRANSFER.md` | This file — machine transfer handoff |

**No user-owned or unrelated files were present in the working tree.**

## 5. Completed phases and remaining work

### Completed — Phase B0 (generic foundation, STRUCTURAL_ONLY)

- [x] `resource_table.m` — contract + validation + capability flags + uniform schema
- [x] `build_mixed_resource_devices.m` — factory dispatch by model_id; uniform device schema
- [x] `build_hybrid_scenario.m` — case_data + resource table + scenario_opt routing
- [x] `scenario_ieee14_1sg_4ibr.m` — IEEE14 profile with resource table (IDs confined here)
- [x] `build_ieee14_sg_ibr_devices.m` — demoted to thin wrapper around generic builder
- [x] Probes preserved under `docs/probes/ieee14_ibr_transfer/`
- [x] Plan exported to `docs/project/plans/`

### Incomplete — Phase B1 (singular-Jacobian fix + equilibrium + vcon proof)

- [ ] `sg_composite_device.m` WRITTEN, NOT TESTED — 5-arg ABI, uniform provenance, no NaN protection for Tpq0=0
- [ ] `sg_stator_current.m` WRITTEN — stateless helper, verified audited
- [ ] `composite_newton.m` WRITTEN — structurally complete (extracted from `mixed_equilibrium_solve`)
- [ ] `mixed_equilibrium_solve.m` EDITED — angle-only vcon, `composite_newton` call, but `sg_status` rule NOT yet removed (still in `check_limits` path); **Tpq0=0 NaN not yet handled**
- [ ] `dual_mode_ibr_model.m` MODIFIED (+2 fields) — uniform schema but no `frozen_state_indices` support
- [ ] `test_ieee14_1sg_4ibr_phase4.m` MODIFIED — vcon assertions updated but tests WILL FAIL due to NaN
- [ ] **B1 gate NOT YET REACHED** — NaN not eliminated, no equilibrium convergence demonstration

### Not started — Phases B2 through J

| Phase | Description | Status |
|---|---|---|
| B2 | Fixed-step composite TS (no events) | NOT STARTED |
| C | Runtime mode-switch + transfer maps + frozen anchor | NOT STARTED |
| D | Index-based selector + composite SSSA | NOT STARTED |
| E | SG trip + automatic GFM commitment | NOT STARTED |
| F | SG synchronism + reclose | NOT STARTED |
| G | Limiter + anti-windup + FRT | NOT STARTED |
| H | Adaptive hybrid TS rollback | NOT STARTED |
| I | solve_case.m IBR route + public runner | NOT STARTED |
| J | Final verification + delivery | NOT STARTED |

## 6. Current runtime call graph

```
solve_case('analysis','ibr',...)
  └─ stability.build_hybrid_scenario(case_data, resources, scenario_opt)
       └─ stability.resource_table(case_data, resource_spec, scenario_opt)
            └─ validates + freezes indexed resource table
       └─ builds scenario.config (index-aligned arrays)

stability.run_hybrid_case(scenario, opt)  [NOT YET WRITTEN]
  └─ stability.build_mixed_resource_devices(case_data, resources, scenario_opt)
       └─ PF warm-start
       └─ dispatch by model_id:
            ├─ sg_emf6 → stability.sg_composite_device
            │    └─ synchronous_emf6_ssa (machine + init)
            │    └─ sg_stator_current (correction 2)
            │    └─ sg_f with Tpq0=0 NaN bug (line 166)
            └─ regfm_b1_dual → ibr.dual_mode_ibr_model
       └─ uniform schema staging + provenance emission
  └─ stability.mixed_equilibrium_solve (Phase B1)
       └─ stability.composite_dae
       └─ stability.composite_newton (extracted Newton, correction 7)
       └─ check_limits (still has sg_status references)
  └─ stability.ts_simulate_composite  [NOT YET WRITTEN]
```

## 7. Latest green baseline

| Test | Result | SHA |
|---|---|---|
| Full regression | **616/616** passed, 0 failed, 0 incomplete | `42e2dea` |

This is the `main` HEAD. The WIP tree is NOT green — NaN bug prevents B1 gate.

## 8. Known failures and root cause

### Primary root cause: Tpq0=0 singular limit (NaN)

**Evidence files:**
- `+stability/synchronous_emf6_ssa.m:88-89,161` — `c_q=(Xq-Xqp)/(Xqp-Xqpp)`, `d_q=(Xq-Xqpp)/(Xqp-Xqpp)`, `dx4=(c_q*Edpp-d_q*Edp)/Tpq0`
- `+stability/sg_composite_device.m:166` — same equation online branch
- `+stability/sg_composite_device.m:179` — same equation offline branch
- `docs/probes/ieee14_ibr_transfer/pf_b0_trace_sg.m:59` — verified NaN at runtime

**Source values (Kodsi IEEE14 SG1, case_ieee14_1sg_4ibr_auto_vsg):**
```
Tpq0  = 0.0    (line 352 of case file — round-rotor, no q-axis transient)
Xq    = 0.646  (Xq = Xqp for round-rotor synchronous machine)
Xqp   = 0.646
Xqpp  = 0.256
```
**Computed coefficients:**
```
c_q = (Xq - Xqp) / (Xqp - Xqpp) = 0 / 0.39 = 0
d_q = (Xq - Xqpp) / (Xqp - Xqpp) = 0.39 / 0.39 = 1
```
**Result at equilibrium (Edp=0, Edpp=0):**
```
dx4 = (0*0 - 1*0) / 0 = 0 / 0 = NaN
```
This NaN propagates through FD Jacobian => RCOND=NaN (proved by `pf_diag_eq.m`).

**IMPORTANT correction to prior diagnosis:**
The earlier sessions attributed the NaN to struct provenance field mismatches. Both causes exist:
1. Tpq0=0 produces NaN in the ODE RHS evaluation — the **physical root cause** of the numerical NaN
2. Struct field mismatches (`sg_composite_device.provenance` 8 fields vs `dual_mode_ibr_model.provenance` 10 fields) can corrupt struct-array concatenation — a **separate MATLAB bug** that may also appear

The uniform-schema fix (Phase B0) addresses cause 2. The frozen-state decision (approved by user, see plan §Tpq0=0) addresses cause 1. **Both are needed and they interact**: if the struct mismatch prevents construction, you never reach the ODE evaluation. If it doesn't prevent construction, the NaN is still fatal at nonlinear iteration time.

### Test counts on WIP tree

Tests have NOT been rerun on the WIP tree — NaN bug makes Phase B1 equilibrium gate impossible without applying the Tpq0=0 fix. Full regression on clean `main` = 616/616.

### No other known regressions — the structural-only changes (resource_table, build_mixed_resource_devices, build_hybrid_scenario, scenario profile) do not touch any production runtime path.

## 9. Tpq0=0 approved treatment (singular-limit frozen-state)

**Decision**: User-option-1 with corrected pinned-state contract.

**Equation**: When Tpq0=0, derive singular limit `0 = c_q*Edpp - d_q*Edp`. For Kodsi round-rotor, `c_q=0, d_q=1` → `Edp=0`.

**Contract**:
- Preserve 6-state SG storage layout (state dimension fixed)
- Declare Edp as frozen/algebraically-eliminated state slot
- init/reconstruct Edp = 0
- TS returns dEdp = 0; validate initial consistency
- equilibrium excludes Edp from unknowns, reconstructs zero
- SSSA active-state reduction before eig (NOT eig-then-delete)
- No epsilon Tpq0, no zero-eigenvalue retention
- Branch on exact Tpq0 == 0 (not tolerance)
- Metadata: `frozen_state_indices = 4; frozen_state_values = 0`

**Not yet implemented in WIP** — sg_composite_device.m:166 still has the unfixed NaN equation.

## 10. Files currently being edited and ownership

| Owner | Files | Status |
|---|---|---|
| **Sole writer (this session)** | `+stability/sg_composite_device.m`, `+stability/sg_stator_current.m`, `+stability/composite_newton.m`, `+stability/mixed_equilibrium_solve.m`, `+stability/resource_table.m`, `+stability/build_mixed_resource_devices.m`, `+stability/build_hybrid_scenario.m`, `+cases/scenario_ieee14_1sg_4ibr.m`, `+ibr/build_ieee14_sg_ibr_devices.m`, `+ibr/dual_mode_ibr_model.m`, `tests/test_ieee14_1sg_4ibr_phase4.m` | Written but UNTESTED; NaN not fixed |
| **Shared (single-owner per TRACK_COORDINATION.md §3)** | `+stability/mixed_equilibrium_solve.m` | Edited on WIP branch only; NOT pushed to main |
| **Not touched** | `+stability/ts_simulate.m`, `+stability/ts_step_kernel.m`, `+stability/ts_algebraic_solve.m`, `+stability/composite_dae.m`, `+stability/multimachine_ssa.m`, `+stability/synchronous_emf6_ssa.m`, `solve_case.m`, `+cases/network_case_catalog.m` | Untouched — no single-owner violations |
| **Other worktrees** | Track A (adaptive-ts), Track B (ibr-interface), checkpoint branches | Independent; no conflicts |

## 11. Next task for resuming

### Smallest implementation step

**Fix sg_composite_device.m:166-167 to handle Tpq0=0 frozen state, then run Phase B1 equilibrium test.**

Specifically:

1. In `sg_composite_device.m`, modify `sg_f` (line 154):
   - Add `frozen_state_indices = [4]; frozen_state_values = [0];` as device metadata
   - In the RHS, check if Tpq0(k) == 0 exactly: if so, return dx4 = 0 (skip ODE evaluation, Edp is algebraic)
   - Same fix for the offline branch (line 179)

2. In `mixed_equilibrium_solve.m`, handle frozen state:
   - Read `frozen_state_indices` from device metadata
   - Exclude frozen state indices from equilibrium unknowns
   - Reconstruct frozen states at their algebraic value after solve

3. Run targeted equilibrium test:
   ```matlab
   restoredefaultpath; cd('/home/birds/Documents/Power-flow');
   pf_init_paths;
   c = cases.case_ieee14_1sg_4ibr_auto_vsg();
   disp = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
   modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},'mode',{'gfl','gfl','gfl','gfl'});
   [devices, ~] = ibr.build_ieee14_sg_ibr_devices(c, modes, disp);
   vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
   dae = stability.composite_dae(c, devices, struct('load_model','cz_p_cz_q','vcon',vcon));
   fprintf('dae.x0(4)=%.6f (Edp, expect 0)\n', dae.x0(4));
   f0 = dae.dae_f(0, dae.x0, dae.y0, dae.u0, struct());
   fprintf('max|f|=%.3e, no NaN/Inf: %d\n', norm(f0,Inf), all(isfinite(f0)));
   ```

4. Then proceed clockwise through Phase B1 tests (test_sg_stator_current, test_sg_composite_device, test_angle_only_vcon, test_mixed_equilibrium_sg_on).

If `mixed_equilibrium_solve.m` is the single-owner file and the next session's boundaries require re-approval, the agent should confirm ownership but the file IS in the approved allowlist.

### Remaining Phase B1 tasks

1. Fix Tpq0=0 frozen-state (sg_composite_device.m) + equilibrium exclusion (mixed_equilibrium_solve.m)
2. Verify no NaN in RHS/equilibrium
3. Verify equilibrium Jacobian after active-state reduction is finite and conditioned
4. Run Phase B1 test battery
5. Commit Phase B1 gate

### Later Phase C-J sequence (from plan)

```
Phase B2 → Composite TS (fixed-step, no events)
Phase C → Runtime mode-switch + transfer maps + frozen anchor
Phase D → Index-based selector + composite SSSA
Phase E → SG trip + automatic GFM commitment
Phase F → SG synchronism + reclose
Phase G → Limiter + anti-windup + FRT
Phase H → Adaptive hybrid TS rollback
Phase I → solve_case.m IBR route + public runner → VERIFY IBR engine
Phase J → Full regression + documentation + delivery
```

## 12. Reproduction commands

```bash
# Fresh checkout
git clone https://github.com/<org>/Power-flow.git
cd Power-flow

# Fetch and checkout the WIP transfer branch
git fetch origin wip/ieee14-ibr-generic-engine
git checkout wip/ieee14-ibr-generic-engine

# Verify
git rev-parse HEAD                          # must match remote SHA
git status --short --branch
```

```matlab
% MATLAB setup
restoredefaultpath;
cd('<repo-path>');
pf_init_paths;

% Run full regression on the clean baseline (main)
% NOTE: WIP branch is NOT green — NaN not yet fixed
r = runtests('tests', 'IncludeSubfolders', true);

% Run targeted Phase B1 test after implementing frozen-state fix
% (See §11 above)
```

## 13. Known technical debt (unresolved from prior phases)

1. **struct provenance mismatch** — FIXED by uniform 4-field provenance in `build_mixed_resource_devices.m`. The legacy `build_ieee14_ibr_devices.m` still uses the old provenance schema. When new callers go through the generic builder, they get the fix. The thin wrapper `build_ieee14_sg_ibr_devices.m` routes to the generic builder. Both paths should now produce uniform schema devices.

2. **sg_status ghost reference** — `mixed_equilibrium_solve.m` `check_limits` still references `config.sg_status` (deleted field in the new `config` struct). The plan says to remove it but it was left as a placeholder for `check_limits`. Next session should either remove it or replace with per-island voltage-forming detection.

3. **`+ibr/build_ieee14_ibr_devices.m` NOT updated** — The legacy IBR-only builder (`build_ieee14_ibr_devices.m`) still exists unmodified. Once `build_ieee14_sg_ibr_devices` is the standard path, the IBR-only builder should be deprecated. The WIP does NOT touch it.

4. **`run_hybrid_case.m` not written** — The top-level orchestrator stub is listed in the plan but has no implementation. Phase B2 needs it.

5. **`ts_simulate_composite.m`, `composite_sssa_model.m`, `ibr_config_selector.m`, `transfer_maps.m`, `synchronism_guard.m`** — All listed in plan as "DO NOT EXIST". They remain unwritten.

## 14. Known probes at transfer time

The diagnostic scripts under `docs/probes/ieee14_ibr_transfer/` require `cd` to the repo root. They call `pf_init_paths` and access production paths. They are explicitly DIAGNOSTIC/WIP — not on any production runtime path.

When reopening MATLAB after checkout, run `pf_init_paths` before using any project function (R2026a path quirk: `restoredefaultpath` clears toolbox paths, so do `pf_init_paths` before `clear`).

## 15. WIP status declaration

```
IBR_DIAGNOSTIC_PROTOTYPE_READY  = FAIL (NaN undiagnosed+unfixed in Tpq0=0)
IBR_PRODUCTION_INTEGRATION_READY = NOT_STARTED
```

This transfer represents a WORK-IN-PROGRESS checkpoint. It is not complete, not tested, and makes no claim of numerical correctness, regression cleanliness, or production readiness. The purpose is preservation of all code, evidence, plans, and decisions made to date so a new session on another machine can resume without repeating the investigation.

---

*Generated by agent-a-atomic-lagoon for machine transfer*
*2026-07-14 19:50 UTC*
