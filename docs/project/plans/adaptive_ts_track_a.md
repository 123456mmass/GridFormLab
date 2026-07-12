# Track A — Adaptive Time-Step TS: Equation Provenance and Design Notes

This document records the **sourced** numerical-method equations and the
**checked project derivation** for the adaptive-step (variable-dt) TS driver
implemented in Track A. It is the citation authority referenced by the
production code, tests, and reports. Per AGENTS.md, Wikipedia is navigation
only and is NOT cited as a derivation authority.

## Status: project-derived estimator, proven by analytic test

The Hairer–Nørsett–Wanner primary source (*Solving Ordinary Differential
Equations*, Springer) was inspected for the step-doubling / local-error-control
material. The exact volume/edition/section/page has NOT been confirmed by
direct inspection of a physical or authoritative PDF copy on this host within
this session. Therefore, per the plan's source policy:

- The estimator below is labeled **project-derived**.
- It is **proven by the analytic unit test** `tests/test_ts_adaptive_lte.m`
  (Test C) before any production use.
- If a contributor later locates the exact Hairer–Wanner bibliographic location,
  they may upgrade the label from "project-derived" to "sourced" and record the
  citation here. Until then, no Hairer section is cited from memory.

## Governing DAE

`ẋ = f(x,y,Y)`, `0 = g(x,y,Y)` — already implemented per model:
- classical: `f` = swing equations; algebraic network solved directly as
  `V = Y\Iinj` (linear, no nonlinear `g`).
- Padiyar / EMF6: `f` = machine differential residuals; `g` = nonlinear network
  residual.

## Implicit trapezoidal one-step (canonical, in `ts_step_kernel.m`)

`x_{n+1} = x_n + (h/2)·(f(x_n,y_n) + f(x_{n+1},y_{n+1}))`, with
`g(x_{n+1},y_{n+1},Y)=0`.

- Global order **p = 2** (fixed-interval error is O(h²)).
- Local truncation error order **p+1 = 3** (one-step LTE is O(h³)).

## Step-doubling fine-solution LTE estimator (project-derived)

Take one full step of size h from an exact start → `x_full`; take two half
steps of size h/2 from the same start → `x_halfhalf`. Let the one-step LTE be
`C·h^(p+1) = C·h^3`.

- Full step committed local error: `E_full = C·h^(p+1)`.
- Two half steps: each contributes `C·(h/2)^(p+1)`; there are two, so the
  accumulated fine-solution local error is
  `E_halfhalf = 2·C·(h/2)^(p+1) = C·h^(p+1) / 2^p`.
- Difference:
  `x_halfhalf − x_full ≈ E_halfhalf − E_full = −(1 − 1/2^p)·C·h^(p+1)`.
- Solving for the fine-solution error `E_halfhalf`:
  `E_halfhalf = (x_halfhalf − x_full) / (2^p − 1) = (x_halfhalf − x_full) / 3`.

**Denominator = 2^p − 1 = 3** (NOT `2^(p+1) − 1 = 7`), because the two-half
solution accumulates the local error **twice**, so it drops below the full-step
local error by a factor `2^p`, not `2^(p+1)`. The accepted candidate is the
higher-accuracy two-half-step solution `x_halfhalf`; `x_full` is used only to
form the estimate. Sign is fixed by the exact-minus-numerical convention
declared in the test (both signs verified).

### Analytic proof obligation (Test C, before production use)

On `ẍ + x = 0` (analytic solution known), the estimator
`e = (x_halfhalf − x_full)/3` must:
1. match the analytic fine-solution LTE in sign and magnitude (to leading order);
2. confirm the accepted solution is `x_halfhalf`;
3. scale by ~8 when h is halved (local factor `2^(p+1) = 2^3 = 8`).

## dt controller (local-error form)

On accept:
```
dt_new = dt · min(fac_max, max(fac_min, fac · (1/err)^(1/(p+1))))
       = dt · min(fac_max, max(fac_min, fac · (1/err)^(1/3)))     (p = 2)
```
The controller exponent is `1/(p+1)` because the **local** error scales as
`O(h^(p+1))`; to drive `err` to 1, scale h by `(1/err)^(1/(p+1))`. For the
trapezoidal rule `p+1 = 3`, so the exponent is **1/3**. On reject,
`dt_new = dt/2`. Clamp to `[dt_min, dt_max]`.

## Convergence orders (separated tests)

- **A. local one-step error** from an exact start: O(h^(p+1)) = O(h³); halving h
  cuts LTE by `2^(p+1) = 8`.
- **B. fixed-final-time global trajectory error**: O(h^p) = O(h²); halving h cuts
  global error by `2^p = 4`.
- **C. Richardson estimator** (denominator 3): sign/magnitude vs analytic LTE;
  accepted = `x_halfhalf`; halving h cuts the estimator by ~8.

## Weighted state-aware norm (no `max(|x|,1)` floor)

```
sc_i = atol_i + rtol_i * max(abs(x_n_i), abs(x_candidate_i))
err_x = rms(e_i / sc_i)
```
A floor of 1 lets small states (e.g. omega deviation ~1e-3) be scaled by an rtol
sized for ~1 pu and admit too much error. Per-state-class absolute tolerances
(values declared a priori with units and rationale): angle (rad), speed deviation
(pu), transient/subtransient EMF (pu), AVR state (pu), algebraic voltage Re/Im
(pu) if included.

## Combined DAE error control (approved policy)

`err = max(err_x, err_y)` with voltage scale/tolerance on `err_y`. Report the
algebraic residual at every accepted substep. **No LTE-accepted step may pass if
its algebraic solve failed** (residual must be ≤ g_tol).

## Algebraic variable ordering (verified from code)

Interleaved per bus:
```
y = [Re(V1), Im(V1), Re(V2), Im(V2), ..., Re(Vnb), Im(Vnb)]^T
```
Verified: `synchronous_emf6_ssa.m:112` (`y0(2*b-1:2*b)=[real(V);imag(V)]`),
`padiyar_model11_dae.m:83,90,152` (same pattern). Enforced by a contract test.

## Event discontinuity contract

1. Integrate the smooth segment with the left topology up to `t_event^-`.
2. `x` is continuous at the event.
3. Switch topology.
4. Re-solve algebraic `y` at the same `x` under the right topology.
5. Start the next step from the consistent right-limit `(x, y^+)`.
6. No trapezoidal residual mixes `f_pre` and `f_fault`.
7. Step-doubling full/two-half substeps of one accepted step stay in a single
   topology segment.
8. A rejected step rolls back `x`, `y`, `Jyy`/cache, and topology-local mutable
   state exactly; accepted output arrays are unchanged; exactly one rejection
   diagnostic record is appended.

Public sample convention: at `t_event`, the stored public sample uses the
**right-limit** algebraic `y`; the left-limit `y`/residual is stored in
`r.event_diagnostics`. `r.t` is strictly increasing with unique timestamps.

## Tolerance selection protocol (declared before any sweep)

Declared in `tests/test_ts_tolerance_selection.m` BEFORE running:
- Candidate tolerance grid (powers of ten), fixed in advance.
- Study cases and time horizons.
- Reference solution construction (analytic or fine-grid extrapolated).
- Selection rule: loosest candidate passing order + error budget + no-fault drift
  + event/algebraic gates.
- Tie-breaker.
- Held-out validation cases (separate from selection cases).
- The candidate grid and selection rule may NOT change after viewing results.

Four separate error budgets, never borrowed across:
- (A) solver LTE tolerance (variable-dt accept/reject);
- (B) algebraic residual tolerance (g_tol, inherited);
- (C) fixed-vs-adaptive equivalence tolerance (common-grid);
- (D) external PSAT validation tolerance.
