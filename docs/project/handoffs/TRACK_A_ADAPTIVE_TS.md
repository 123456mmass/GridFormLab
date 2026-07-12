# Track A Handoff — Adaptive Time-Step TS

**Branch:** `feature/adaptive-ts`
**Worktree:** `/home/birds/Documents/Power-flow-adaptive`
**Last updated:** 2026-07-12

## Phase 0 — Fresh baseline (recorded BEFORE any refactor)

All evidence below is FRESH, produced from the Track-A worktree on commit
`0534132` (= `origin/main` = merge-base). No saved metrics are reused.

### Git state at baseline
- HEAD: `0534132160b28041f9ba33709cdc8eaa4510f404`
- origin/main: `0534132` (identical)
- merge-base(HEAD, origin/main): `0534132`
- ahead/behind: `0 0`; working tree clean.

### Full regression (FRESH)
```
restoredefaultpath; cd('/home/birds/Documents/Power-flow-adaptive');
pf_init_paths; r = runtests('tests','IncludeSubfolders',true);
```
- **TOTAL=284 PASSED=284 FAILED=0 INCOMPLETE=0**
- `test_no_external_solver_dependency` PASS (no fsolve/optimoptions/etc. on the
  production path).
- `test_ts_shared_kernel/test_padiyar_15s_no_algebraic_failure` PASS (stale-Jac
  fix holds; long-horizon clean).

### Fresh Case14 three-way (PSAT + PGAz + Ours)
- psat_execution: PASS (td=1509 points)
- ours_convergence: PASS (nonconv=0)
- psat_comparison (primary): PASS
- all_gates_pass: PASS
- PF: dV=6.661e-16 pu, dAng=3.553e-14 deg
- TS: dCOI=0.0096 deg, dw=3.816e-06 pu, dPe=0.0422 MW, dVm=3.179e-05 pu

### Fresh RTS-24 three-way (PSAT + PGAz + Ours)
- psat_execution: PASS (td=1509 points)
- ours_convergence: PASS (nonconv=0)
- psat_comparison (primary): PASS
- all_gates_pass: PASS
- PF: dV=4.441e-16 pu, dAng=6.750e-14 deg
- TS: dCOI=0.0068 deg, dw=4.620e-06 pu, dPe=0.0827 MW, dVm=5.354e-06 pu

PSAT path: `/home/birds/Documents/psat-2.1.11-mat/psat` (PSAT 2.1.11, Milano).
PGAz: `/home/birds/Documents/PGAz_V1.1.1` (secondary diagnostic only; its larger
trajectory difference is reported, not hidden).

## Phase 0 — characterization test scaffold

`tests/test_ts_characterization_fixed.m` pins the CURRENT fixed-step classical
trajectory on canonical Case14 configurations (adaptive-corrector, fixed-ci10,
no-fault drift). 3 tests PASS. This is the bit-identity basis for the Phase 2
mechanical refactor (dual-path comparison: old inline vs new strategy path).

## Phase 0 — equation provenance

`docs/project/plans/adaptive_ts_track_a.md` records the step-doubling fine-solution
estimator derivation (denominator 3, local O(h^3), global O(h^2), controller
exponent 1/3). Labeled **project-derived** because the Hairer–Nørsett–Wanner
primary source was not confirmed by direct bibliographic inspection this session;
the estimator must be proven by the analytic unit test (Test C) before production
use. Wikipedia is navigation only.

## Phase status — ALL DONE

- Phase 0: DONE — fresh baseline (284/284/0/0) + characterization tests.
- Phase 1: DONE — generic one-step contract (ts_model_strategy + generalized
  ts_step_kernel); Padiyar/EMF6 fixed equivalence bit-identical (AbsTol=0).
- Phase 2: DONE — classical fixed mechanical migration (classical_dae +
  expand_machines_classical + classical_step); legacy inline corrector removed;
  one canonical trapezoidal implementation.
- Phase 3: DONE — generic adaptive controller (ts_adaptive_driver) with step
  doubling (denominator 3), LTE estimator, weighted state-aware norm,
  accept/reject, dt controller (exponent 1/3), exact event landing, fail-closed.
- Phase 4: DONE — Padiyar adaptive (manual + AVR); 15s long-horizon gate.
- Phase 5: DONE — EMF6 adaptive; Kundur 12.6 vs PSAT < 5 deg (1.90 deg fresh).
- Phase 6: DONE — classical adaptive; fixed-vs-adaptive common-grid < 1.0 deg.
- Phase 7: DONE — cross-model convergence + fresh PSAT + full regression
  (342/0/0). Fresh Case14 + RTS-24 PSAT both PASS.
- Phase 8: DONE — production default switched to adaptive (separate commit).

## Final state (commit 87d4bad)

- HEAD: `87d4bad695f66b73d6a85d5d0387f7c7337beaa7`
- origin/main: `0534132160b28041f9ba33709cdc8eaa4510f404` (no advance)
- merge-base: `0534132` (= origin/main; 9 commits ahead, 0 behind)
- Full regression (fresh): 346 passed / 0 failed / 0 incomplete.
- Fresh Case14 PSAT: PASS (dCOI=0.0096 deg, dw=3.816e-6).
- Fresh RTS-24 PSAT: PASS (dCOI=0.0068 deg, dw=4.620e-6).
- EMF6 adaptive vs PSAT (Kundur 12.6): 1.90 deg < 5 deg.
- `test_no_external_solver_dependency`: 12/12 PASS (no fsolve/external in production).
- No Track B / shared-policy files touched (verified by diff).
- Working tree clean.

## Reproduce

```matlab
restoredefaultpath;
cd('/home/birds/Documents/Power-flow-adaptive');
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);   % 346/346/0/0
% Fresh PSAT CV (requires PSAT at /home/birds/Documents/psat-2.1.11-mat/psat):
addpath('/tmp'); track_a_phase7_cv;
% Adaptive cross-model:
addpath('/tmp'); track_a_adaptive_xval;
```

## File ownership (Track A)

Track A allowlist and forbidden files are declared in the approved plan. Track A
does NOT touch `+ibr/**`, `tests/test_ibr_*.m`, `docs/ibr/**`, `scripts/ibr/**`,
`AGENTS.md`, `CLAUDE.md`, `docs/project/TRACK_COORDINATION.md`, or the shared
`docs/project/AGENT_HANDOFF.md`. Track A uses this track-specific handoff file.

## Reproduce

```matlab
restoredefaultpath;
cd('/home/birds/Documents/Power-flow-adaptive');
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);   % 284/284/0/0
addpath('tests');
runtests('test_ts_characterization_fixed');       % 3/3
% Fresh CV (requires PSAT at /home/birds/Documents/psat-2.1.11-mat/psat):
addpath('/tmp'); track_a_case14_cv; track_a_rts24_cv;
```
