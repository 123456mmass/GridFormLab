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

## Phase status

- Phase 0: IN PROGRESS (baseline + characterization committed below).
- Phases 1–8: pending; see approved plan
  `/home/birds/.claude/plans/nifty-dazzling-peacock.md` and
  `docs/project/plans/adaptive_ts_track_a.md`.

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
