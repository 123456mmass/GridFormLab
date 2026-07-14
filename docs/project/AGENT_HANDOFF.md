# Agent handoff — 2026-07-14

## IBR Generic Mixed-Resource Engine — Phase B1-J Complete

**Current commit:** `a003520` on `main` (HEAD == origin/main). All 4 checkpoint
commits (823d4e6, 61aa433, df4190a, 6126425) preserved without rebase/amend.

### Completed phases (B0-J)

| Phase | Description | Commit | Tests |
|---|---|---|---|
| B0 | Generic foundation (resource table, uniform schema) | 6126425 | structural |
| B1 | Tpq0=0 frozen-state + equilibrium gate | 733b433 | 13/13 |
| B2 | No-event composite TS vertical slice | 3ab81e8 | 6/6 |
| C | Transfer maps + frozen anchor | ddfba19 | 6/6 |
| D | Composite SSSA + index-based selector | 38dc4d9 | 6/6 |
| E+F | SG trip + GFM commit + synchronism + reclose | 63492de | 6/6 |
| I | solve_case IBR Simulation route | a003520 | functional |
| J | Final regression + handoff (this) | TBD | 649/653 |

Phases G (limiter/FRT) and H (adaptive rollback): structural foundations exist;
full sourced implementation deferred per frozen contract stop-gaps.

### Key architectural decisions implemented

1. **Tpq0=0 frozen-state (singular limit):** Kodsi SG1 has Tpq0=0 (round-rotor).
   Edp is algebraically eliminated: dEdp=0, Edp=0 frozen. Generic: derived from
   device metadata (frozen_state_indices/values), never hard-coding state index 4.
   Active-state Newton + SSSA reduction before eig.

2. **Index-based resource configuration:** No hard-coded SG_ON/SG_OFF, no
   one-SG/four-IBR assumptions. All decisions derive from validated resource
   indices, capabilities, committed configuration, topology, equilibrium
   feasibility, and SSSA evidence.

3. **Coupled trapezoidal residual (correction 7):** TS solves R_x and R_g
   simultaneously via composite_newton (NOT Picard iteration). Active-state
   only (frozen Edp excluded from Newton unknown vector).

4. **solve_case IBR route:** 4th analysis type. Non-interactive:
   `solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt)`.
   Thin dispatcher — no equations, no device construction in solve_case.

### New production files (10)

- `+stability/resource_table.m` — validated indexed resource table
- `+stability/build_mixed_resource_devices.m` — generic factory dispatch
- `+stability/build_hybrid_scenario.m` — case_data + resources binding
- `+stability/sg_composite_device.m` — EMF6 5-arg ABI + frozen-state metadata
- `+stability/sg_stator_current.m` — EMF6 stator Id/Iq (correction 2)
- `+stability/composite_newton.m` — one damped-Newton owner
- `+stability/run_hybrid_case.m` — top-level mixed-SG+IBR orchestrator
- `+stability/ts_simulate_composite.m` — coupled trapezoidal composite TS
- `+stability/composite_sssa_model.m` — active-state Galerkin before eig
- `+stability/ibr_config_selector.m` — index-based resource-config selector
- `+stability/transfer_maps.m` — GFL↔GFM algebraic continuity maps
- `+stability/synchronism_guard.m` — signed-margin SG reclose predicate
- `+stability/sg_event_handler.m` — per-SG trip+GFM commit+reclose

### Edited files (5)

- `+stability/mixed_equilibrium_solve.m` — frozen-state exclusion, per-island VF
- `+stability/ts_hybrid_state_init.m` — device_frozen_anchor field
- `+ibr/dual_mode_ibr_model.m` — frozen_state metadata, uniform schema
- `+stability/build_mixed_resource_devices.m` — normalize frozen fields
- `solve_case.m` — add 'ibr' analysis type

### Test files (7 new, 2 updated)

- `tests/test_ieee14_1sg_4ibr_phaseB1.m` — 13 tests
- `tests/test_ieee14_1sg_4ibr_phaseB2.m` — 6 tests
- `tests/test_ieee14_1sg_4ibr_phaseC.m` — 6 tests
- `tests/test_ieee14_1sg_4ibr_phaseD.m` — 6 tests
- `tests/test_ieee14_1sg_4ibr_phaseEF.m` — 6 tests
- `tests/test_ieee14_1sg_4ibr_phase4.m` — updated (10 tests)
- `tests/test_ieee14_1sg_4ibr_phase8_real.m` — updated (6 tests)

### Latest regression

**649/653 passed, 0 failed, 4 incomplete** (PSAT/PGAz filtered — expected).

### Unfinished (deferred)

- Phase G: REGFM_B1 Eqs.10-13 limiter/FRT sourced edit (pending source)
- Phase H: Adaptive hybrid TS rollback (structural engine present)
- Phase J final: this handoff replaces the old

### Status flags

```
IBR_DIAGNOSTIC_PROTOTYPE_READY  = PASS (NaN root cause diagnosed + fixed)
IBR_PRODUCTION_INTEGRATION_READY = STRUCTURAL_COMPLETE (pending G+H for READY)
```

### Safe continuation

1. Phase G: implement REGFM_B1 Eqs.10-13 current limiter + anti-windup in
   `regfm_b1_vsg_model.m`.
2. Phase H: adaptive-step TS variant in `ts_simulate_composite.m`.
3. Then flip `IBR_PRODUCTION_INTEGRATION_READY = READY`.
4. Multi-case validation (IEEE9/RTS-24/Padiyar) is a separate future mission.

### Reproduction

```matlab
restoredefaultpath; cd('C:\Users\User\Desktop\Power-flow');
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);
result = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',...
    struct('t_end',5.0,'dt',0.01));
```
