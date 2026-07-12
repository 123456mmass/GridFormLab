# Track A Handoff — Adaptive Time-Step TS (honesty closure)

**Branch:** `feature/adaptive-ts`
**Worktree:** `/home/birds/Documents/Power-flow-adaptive`
**Last updated:** 2026-07-12 (honesty closure)

## Purpose and honest status

This handoff documents the adaptive-step (variable-dt, LTE-based) TS driver
shared by the classical, Padiyar, and EMF6 models, AND the honesty closure
that corrects the overclaims made by the earlier Phase 8 report.

The adaptive implementation is numerically sound and tests pass, but
**readiness claims for switching the production default to adaptive were not
supported by tracked, reproducible evidence**. Independent verification
confirmed 8 findings (all CONFIRMED); this closure corrects them. The
production default is restored to **fixed-step**; adaptive remains an explicit
production candidate. Required final statuses are reported at the end.

## Traced routing contract (verified)

```
run_ts.m                  ts_options.stepper='fixed'   (production default, restored)
   -> solve_case.m         opt = merge_options(entry.options, user_opt)
                           [catalog base stepper='fixed' (restored) + user]
   -> solve_case.m         stability.ts_simulate(case_data, opt)

DIRECT ts_simulate(case_data) without stepper: opt has NO stepper field
   -> ts_simulate.m            isfield(opt,'stepper')&&strcmpi(...,'adaptive') => FALSE
                               -> fixed-step path (classical)
   -> ts_simulate_padiyar_model11.m   same check -> fixed if no stepper
   -> ts_simulate_emf6.m              same check -> fixed if no stepper

ADAPTIVE path (only when opt.stepper=='adaptive'):
   classical  -> ts_simulate.m                    run_classical_adaptive
   padiyar    -> ts_simulate_padiyar_model11.m    run_adaptive
   emf6       -> ts_simulate_emf6.m               run_emf6_adaptive
```

- **Direct `ts_simulate(case)` without `stepper`** stays FIXED (the dispatch
  checks `isfield(opt,'stepper') && strcmpi(opt.stepper,'adaptive')`).
- **`solve_case` via catalog** is FIXED by default (catalog base
  `stepper='fixed'`, restored) unless the user passes `stepper='adaptive'`.
- **`run_ts.m`** sets `stepper='fixed'` (restored); adaptive is explicit.
- End-to-end routing is asserted by `tests/test_ts_default_routing.m`
  (7 tests: catalog base fixed, run_ts source fixed, direct default fixed,
  explicit fixed, explicit adaptive schema, solve_case default fixed,
  solve_case user-override adaptive).

## Phase status — ALL DONE

- Phase 0: DONE — fresh baseline + characterization tests.
- Phase 1: DONE — generic one-step contract (ts_model_strategy + generalized
  ts_step_kernel); Padiyar/EMF6 fixed equivalence bit-identical (AbsTol=0).
- Phase 2: DONE — classical fixed mechanical migration (classical_dae +
  expand_machines_classical + classical_step); legacy inline corrector removed.
- Phase 3: DONE — generic adaptive controller (ts_adaptive_driver) with step
  doubling (denominator 3), LTE estimator, weighted state-aware norm,
  accept/reject, dt controller (exponent 1/3), exact event landing, fail-closed.
- Phase 4: DONE — Padiyar adaptive (manual + AVR); 15s long-horizon gate.
- Phase 5: DONE — EMF6 adaptive.
- Phase 6: DONE — classical adaptive; fixed-vs-adaptive common-grid guard.
- Phase 7: DONE — cross-model convergence + fresh PSAT + full regression.
- Phase 8: DONE — production default switched to adaptive (separate commit).

## Honesty closure (this set of commits) — corrects Phase 8 overclaims

The closure is split into 5 corrective commits (no history rewrite, no push,
no merge):

1. **Restore fixed default** — `run_ts.m` + `network_case_catalog.m` revert
   to `stepper='fixed'`; stale `% fixed (default)` comments in the three
   `ts_simulate*.m` files corrected to describe the dispatch accurately (no
   logic change); `tests/test_ts_default_routing.m` asserts default is FIXED
   and adds end-to-end routing tests (solve_case + direct).
2. **Tracked validation runners + shared helper** — ONE shared helper
   `scripts/validation/adaptive_ts_compare_fixed.m` (owns ID mapping,
   event-segmented `interp_no_extrapolate`, COI frame, metrics, structural
   checks). Replaces every `/tmp` runner with tracked scripts:
   `ts_fixed_psat_case14_cv.m`, `ts_fixed_psat_rts24_cv.m`, `ts_fixed_psat_phase7_cv.m`,
   `adaptive_ts_diagnostic.m`. No whole-trajectory `interp1` across events.
3. **Honest NOT_READY tolerance contract** — replaces the tautological
   `test_ts_tolerance_selection.m` with a contract asserting NOT_READY;
   writes `docs/project/plans/adaptive_tolerance_study_proposal.md`
   (prospective, NOT executed).
4. **Held-out diagnostics + 1deg provenance** —
   `tests/test_ts_adaptive_heldout_diagnostic.m` (structural gates only,
   numerical diffs report-only); `tests/test_ts_classical_adaptive.m`
   expanded to report Pe/Vbus with honest 1.0 deg provenance.
5. **Documentation correction** — this file: removes `/tmp`, fixes counts,
   distinguishes evidence types, states NOT_READY, honest limitations.

## Evidence types (kept distinct)

1. **Fixed canonical PSAT baseline** (fresh, PSAT runs each invocation):
   - Case14: psat_comparison=PASS, dCOI=0.0096 deg, dw=3.816e-6, dPe=0.0422 MW.
   - RTS-24: psat_comparison=PASS, dCOI=0.0068 deg, dw=4.620e-6, dPe=0.0827 MW.
   - These are FIXED-step production results, NOT adaptive held-out evidence.
   - Reproduce: `ts_fixed_psat_phase7_cv` (tracked).
2. **Adaptive-vs-fixed diagnostics** (event-segmented, report-only):
   - Case14 classical: structural_pass=1, delta_coi=0.0630 deg, pairwise=0.6962
     deg, Pe=55.77 MW, Vbus=3.38e-1 pu.
   - Padiyar 15s: structural_pass=1, delta_coi=0.0859 deg, pairwise=0.1335 deg.
   - EMF6 Kundur: structural_pass=1, delta_coi=0.0015 deg, pairwise=0.0019 deg.
   - Reproduce: `adaptive_ts_diagnostic` (tracked).
3. **Held-out adaptive diagnostics** (RTS-24 + Kundur, structural gates only):
   - RTS-24 classical: structural_pass=1 (diagnostics reported, NOT gated).
   - Kundur emf6: structural_pass=1 (diagnostics reported, NOT gated).
   - Reproduce: `runtests('tests/test_ts_adaptive_heldout_diagnostic.m')`.
4. **EMF6 adaptive vs PSAT (Kundur 12.6)**: 1.8951 deg COI angle diff.
   **NOTE:** the PSAT Kundur6 input is SAVED `.mat` reference data
   (`docs/source/figures/kundur_ex126/psat_kundur6_ts_raw.mat`), NOT a fresh
   PSAT execution. It is a diagnostic comparison only; it must NOT be called
   "fresh PSAT execution" or used as adaptive held-out acceptance evidence.

## 1.0 deg threshold — honest provenance

- First appeared: `tests/test_ts_classical_adaptive.m`, Phase 6 commit
  `0b890a4`, authored AFTER adaptive results were already observed (Phases
  3-5). No recorded executable selection study exists.
- Status: `FIXED_VS_ADAPTIVE_1DEG_REGRESSION_GUARD = PASS` (non-regression
  guard only; value unchanged per policy — do NOT relax/increase/remove/tune).
- Status: `FIXED_VS_ADAPTIVE_PRODUCTION_TOLERANCE_JUSTIFIED = NOT_READY`.
- The comparison is expanded to REPORT delta/omega/Pe/Vbus (COI, bus-ID,
  gen-ID mapped) but NO new acceptance thresholds are imposed on Pe/Vbus.

## Required final statuses

- `ADAPTIVE_IMPLEMENTATION_READY` = PASS (implementation sound; tests pass).
- `TOLERANCE_SELECTION_EVIDENCE` = NOT_READY.
- `HELD_OUT_ADAPTIVE_VALIDATION` = NOT_READY (diagnostics executed; not
  acceptance; RTS-24/Kundur are previously observed, not genuinely held-out).
- `REPRODUCIBLE_VALIDATION_ENTRYPOINTS` = PASS (tracked scripts, no `/tmp`).
- `DOCUMENTATION_MATCHES_CODE` = PASS (after this correction).
- `ADAPTIVE_DEFAULT_SWITCH_READY` = NOT_READY (default restored to fixed).
- `FIXED_VS_ADAPTIVE_1DEG_REGRESSION_GUARD` = PASS (non-regression only).
- `FIXED_VS_ADAPTIVE_PRODUCTION_TOLERANCE_JUSTIFIED` = NOT_READY.
- `FULL_REGRESSION` = PASS (351 passed / 0 failed / 0 incomplete, fresh).
- `MERGE_READINESS` = origin/main race check clean (0 behind); adaptive
  default NOT ready, so a merge would carry adaptive as an explicit candidate
  only, not as the default.

## File ownership (Track A) — exact counts

Versus merge-base `0534132` (= origin/main): **28 new + 6 modified** files,
14 commits ahead, 0 behind.

**New (28):**
- `+stability/classical_dae.m`, `expand_machines_classical.m`,
  `ts_adaptive_driver.m`, `ts_model_strategy.m` (4).
- `scripts/validation/adaptive_ts_compare_fixed.m` (shared helper),
  `ts_fixed_psat_case14_cv.m`, `ts_fixed_psat_rts24_cv.m`, `ts_fixed_psat_phase7_cv.m`,
  `adaptive_ts_diagnostic.m` (5).
- `tests/test_corrector_terminology.m`, `test_ts_adaptive_convergence.m`,
  `test_ts_adaptive_heldout_diagnostic.m`, `test_ts_adaptive_lte.m`,
  `test_ts_adaptive_rollback.m`, `test_ts_algebraic_ordering.m`,
  `test_ts_characterization_fixed.m`, `test_ts_classical_adaptive.m`,
  `test_ts_classical_strategy_equivalence.m`, `test_ts_default_routing.m`,
  `test_ts_emf6_adaptive.m`, `test_ts_event_convention.m`,
  `test_ts_padiyar_adaptive.m`, `test_ts_result_schema.m`,
  `test_ts_strategy_equivalence.m`, `test_ts_tolerance_selection.m` (16).
- `docs/project/plans/adaptive_ts_track_a.md`,
  `docs/project/plans/adaptive_tolerance_study_proposal.md`,
  `docs/project/handoffs/TRACK_A_ADAPTIVE_TS.md` (3).

**Modified (6):**
- `+cases/network_case_catalog.m` (default restored to fixed).
- `+stability/ts_simulate.m`, `ts_simulate_emf6.m`,
  `ts_simulate_padiyar_model11.m` (stepper dispatch + comments).
- `+stability/ts_step_kernel.m` (generalized to strategy struct).
- `run_ts.m` (default restored to fixed).

Track A does NOT touch `+ibr/**`, `tests/test_ibr_*.m`, `docs/ibr/**`,
`scripts/ibr/**`, `AGENTS.md`, `CLAUDE.md`,
`docs/project/TRACK_COORDINATION.md`, or the shared
`docs/project/AGENT_HANDOFF.md`. No `git reset --hard`, `clean`, mass
rewrites, push, or merge occurred.

## Reproduce (tracked files only — NO `/tmp`)

```matlab
restoredefaultpath; cd('/home/birds/Documents/Power-flow-adaptive');
pf_init_paths;
% Full regression (fresh):
r = runtests('tests','IncludeSubfolders',true);   % 351/351/0/0
% Routing contract:
runtests('tests/test_ts_default_routing.m');       % 7/7
% Held-out adaptive diagnostics (structural gates, report-only):
runtests('tests/test_ts_adaptive_heldout_diagnostic.m');  % 3/3
% Adaptive-vs-fixed diagnostics (all 3 models, event-segmented):
adaptive_ts_diagnostic;
% Tolerance NOT_READY contract:
runtests('tests/test_ts_tolerance_selection.m');   % 4/4
% Fresh fixed canonical PSAT (requires PSAT at
% /home/birds/Documents/psat-2.1.11-mat/psat; reference tool, not a prod dep):
ts_fixed_psat_phase7_cv;       % Case14 + RTS-24 fresh PSAT
```

## Equation provenance

`docs/project/plans/adaptive_ts_track_a.md` records the step-doubling LTE
estimator derivation (Richardson denominator 3, local O(h^3), global O(h^2),
controller exponent 1/3, weighted state-aware norm, DAE error control, event
convention). Labeled **project-derived** because the Hairer–Nørsett–Wanner
primary source was not confirmed by direct bibliographic inspection this
session; the estimator is proven by the analytic unit test
(`test_ts_adaptive_lte.m`: local factor ~8, global ~4, denominator 3,
exponent 1/3) before production use.

## Limitations (honest)

- Tolerance selection, held-out adaptive validation, and the 1.0 deg
  production justification are all NOT_READY. The default stays fixed.
- The EMF6-vs-PSAT Kundur comparison uses SAVED PSAT `.mat` data, not a fresh
  PSAT execution; it is a diagnostic only.
- RTS-24 and Kundur adaptive results were observed before the closure; they
  are NOT genuinely held-out. A future prospective tolerance study
  (`adaptive_tolerance_study_proposal.md`) must label them as previously
  observed or pick unseen cases.
- The adaptive driver's `atol_x/rtol_x/atol_y/rtol_y` are PROPOSED values,
  NOT the output of a recorded selection study. They must not be presented
  as "selected" or "a-priori justified".

## When the default may switch back to adaptive

ONLY after a future SEPARATELY APPROVED prospective tolerance-study protocol
is executed and demonstrates every gate on all three models with genuinely
unseen held-out cases. Any FAIL or NOT_READY => default stays fixed.
