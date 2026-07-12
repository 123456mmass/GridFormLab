# Prospective Adaptive-TS Tolerance-Study Protocol (NOT executed)

**Status:** PROSPECTIVE — proposed for FUTURE user approval. NOT executed in
this closure. NOT used to retroactively legitimize the existing 1.0 deg
threshold or any prior adaptive result.

**Current honest status (binding on this closure):**
- `TOLERANCE_SELECTION_EVIDENCE = NOT_READY`
- `HELD_OUT_ADAPTIVE_VALIDATION = NOT_READY`
- `ADAPTIVE_DEFAULT_SWITCH_READY = NOT_READY`
- `FIXED_VS_ADAPTIVE_PRODUCTION_TOLERANCE_JUSTIFIED = NOT_READY`

The existing `1.0 deg` fixed-vs-adaptive threshold in
`tests/test_ts_classical_adaptive.m` remains ONLY as a historical
`ASSUMED_DIAGNOSTIC` regression guard. It was introduced in Phase 6 commit
`0b890a4` AFTER adaptive results were already observed; no recorded a-priori
selection study exists for it. It must NOT be cited as "selected" or
"a-priori justified" until a study of the form below is approved, executed,
and passes every gate.

## Why a new protocol is needed

The tolerance selection protocol declared in
`docs/project/plans/adaptive_ts_track_a.md` (§ "Tolerance selection protocol")
is NOT executable as written: it names a candidate grid, study/held-out
split, and selection rule, but does NOT declare a reference solution
construction, exact time horizons, per-state scaling, or acceptance thresholds
independently of the results. Running it now would amount to selecting
tolerances while viewing pass/fail metrics, which is forbidden by AGENTS.md
§ "Scientific and numerical integrity". This document declares the missing
pieces prospectively, for a future approved run.

## Protocol (to be executed only after separate user approval)

### 1. Study cases and time horizons (declared a priori)
Per model, with horizons chosen to exercise both the transient swing and the
long-horizon drift:

| Model | Study case | Horizon | Fault |
|-------|-----------|---------|-------|
| classical | `case_matpower6_case14` | 10 s | bus 4, 1.0–1.1 s, Zf=j0.1 |
| classical | `case_matpower6_case9` | 10 s | bus 7, 1.0–1.1 s, Zf=j0.1 |
| padiyar | `case_padiyar_two_area_4m_avr` | 15 s | bus 3, 1.0–1.1 s, Zf=j0.1 |
| emf6 | `case_kundur_two_area_classical` | 10 s | bus 8, 1.0–1.05 s, solid |

These are STUDY cases (used to select tolerances). They are NOT held-out.

### 2. Reference solution construction (declared a priori)
A fine-grid reference is built INDEPENDENTLY of the candidate tolerances:
- Fixed-step implicit trapezoidal at `dt_ref = 1e-4 s` (10x finer than the
  finest study `dt`), with the SAME model, fault, and topology contracts.
- The reference uses `corrector_mode='adaptive'` with a tight corrector
  tolerance (`1e-12`) and a high iteration cap (`50`) so corrector error is
  negligible relative to the LTE under study.
- The reference is computed ONCE and frozen; the candidate grid is run
  against this frozen reference. The reference grid is NOT revised after
  viewing candidate results.

### 3. Candidate tolerance grid (declared a priori, powers of ten)
Per-state-class absolute LTE tolerance candidates (the adaptive driver's
`atol_x` for angle/speed states, with `rtol_x` tied to `atol_x` by a fixed
ratio). The grid is fixed and may NOT change after viewing results:

```
atol_x candidates: [1e-3, 1e-4, 1e-5, 1e-6]   (rad for angle, pu for speed)
rtol_x = 1e-1 * atol_x  (fixed ratio, not a free parameter)
atol_y = 1e-5, rtol_y = 1e-4  (algebraic; fixed, not swept in this study)
```

The algebraic tolerance is held fixed because budget (B) is inherited from
the DAE `g_tol` contract, not a free LTE parameter.

### 4. Metrics and acceptance thresholds (declared a priori)
For each candidate, compare the adaptive trajectory to the frozen reference
on a common grid using event-segmented `interp_no_extrapolate`
(`adaptive_ts_compare_fixed` helper). Acceptance requires ALL of:

- **Order test:** measured local error scales as O(h^3) (factor ~8 between
  halvings) and global as O(h^2) (factor ~4), within a 2x band
  (`0.5*expected <= measured <= 2*expected`).
- **Error budget A (solver LTE):** max weighted LTE over the trajectory
  `<= atol_x` (the candidate itself) for 95% of accepted steps, with no
  single step exceeding `10*atol_x`.
- **Error budget B (algebraic residual):** max corrector residual
  `<= 1e-10` at every accepted step (inherited `g_tol`).
- **Error budget C (fixed-vs-adaptive equivalence):** COI angle
  `<= 0.1 deg`, pairwise angle `<= 0.5 deg`, speed `<= 1e-3 pu`,
  Pe `<= 5 MW`, Vbus `<= 1e-2 pu` — declared a priori from the
  corrector-tolerance bound, NOT from observed adaptive results.
- **No-fault drift:** delta drift `< 1e-6 rad`, omega drift `< 1e-6 pu`.
- **Event/algebraic gates:** exact event landing (events on grid to
  `1e-14`), no cross-event interpolation, no extrapolation, ID mapping
  consistent, algebraic convergence at every step.
- **Held-out cases (see §5):** the selected tolerance must ALSO pass the
  same metrics on the held-out cases, WITHOUT revisiting the selection.

These thresholds are declared BEFORE running the candidate grid. They are
not adjusted after viewing results.

### 5. Held-out validation cases (separate from study cases, untouched)
Genuinely unseen cases (NOT RTS-24 or Kundur, which are now previously
observed and therefore ineligible as held-out for this study):

| Model | Held-out case | Horizon | Fault |
|-------|--------------|---------|-------|
| classical | `case_ieee300bus` | 5 s | bus 3, 1.0–1.1 s, Zf=j0.1 |
| classical | `case_matpower_ieee30bus` | 5 s | bus 30, 1.0–1.1 s, Zf=j0.1 |
| padiyar | (no second Padiyar case exists in catalog; this gate is N/A until one is added) | — | — |
| emf6 | `case_saadat_ieee30bus` (if EMF6 parameters are available; else N/A) | 5 s | TBD |

RTS-24 and Kundur are EXPLICITLY excluded from held-out status for this
study because their adaptive results were already observed in Phases 5–7
and in this closure's diagnostics. A future protocol must either (a) label
them as "previously observed, not held-out" or (b) pick genuinely unseen
cases as above.

### 6. Selection rule and tie-breaker (declared a priori)
- **Rule:** the LOOSEST candidate (largest `atol_x`) that simultaneously
  passes the order test, error budget A, no-fault drift, and
  event/algebraic gates on ALL study cases, AND passes error budget C plus
  the held-out cases.
- **Tie-breaker:** prefer the looser (larger) tolerance.
- The candidate grid and selection rule may NOT change after viewing
  results. If no candidate passes, the result is `NO_TOLERANCE_SELECTED`
  and the default remains fixed.

### 7. Artifact format and failure semantics
- The study produces a tracked artifact recording: the frozen reference
  commit, the candidate grid, per-candidate per-case metrics, the
  selection decision, and the held-out results.
- If any structural invariant fails (finite, coverage, no extrapolation,
  exact event landing, ID mapping, algebraic convergence), the study STOPS;
  the root cause is fixed before re-running. Tolerances are NOT relaxed to
  recover.
- If no candidate passes, `TOLERANCE_SELECTION_EVIDENCE` remains
  `NOT_READY` and the production default stays `fixed`.

## What this proposal does NOT do

- It does NOT execute any selection sweep now.
- It does NOT choose or legitimize any tolerance now.
- It does NOT retroactively justify the 1.0 deg threshold.
- It does NOT switch the production default to adaptive. The default may
  switch back to adaptive ONLY after this protocol is separately approved,
  executed, and every gate passes on all three models with untouched
  held-out cases. Any `FAIL` or `NOT_READY` => default stays fixed.

## Approval gate

This protocol requires explicit user approval BEFORE execution. Until then,
all tolerance-selection claims are `NOT_READY` and the adaptive stepper is
an explicit production candidate, not the default.
