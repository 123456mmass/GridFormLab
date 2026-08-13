# Adaptive-hybrid TS: post-event step not reinitialized across discontinuity

Date: 2026-08-12
Status: RESOLVED_EVIDENCE_CORRECTED
Failure ID: `ts_simulate_ibr_hybrid:adaptiveDtMin` (symptom); root cause is a
step-size reinitialization defect in the opt-in adaptive path.

> **Evidence correction, 2026-08-13 (`ADAPT-2026-08-13-02`):** the
> discontinuity-restart code correction remains implemented, but a later audit
> proved that `run_hybrid_case` forwarded only `stepper`; caller overrides such
> as `dt_max=0.5`, `dt_max_armed=0.05`, and `reject_limit=12` were silently
> dropped by a transposed cell-array loop. Consequently, the historical exact
> counts and wall time below describe the driver's defaults, not the listed
> override tuple. They are retained as historical observations but are not
> current acceptance evidence. Fresh post-forwarding LTE, rollback, exact-event
> landing, and fixed-path bit-identity gates pass 11/11; see
> `2026-08-13-adaptive-option-forwarding-cell-orientation.md`.

## Symptom

The opt-in adaptive stepper (`stepper='adaptive'` on
`stability.ts_simulate_ibr_hybrid`) failed on the `compressed_fast` switching
arm at `t≈1.45`–`1.64` with

```
ts_simulate_ibr_hybrid:adaptiveDtMin
Adaptive step could not satisfy the DAE at dt_min=9.766e-05, t=1.636588
(err=Inf alg_res=Inf converged=0, backward-Euler rescue attempted).
```

Newton would not converge at `dt_min` even after the backward-Euler floor
rescue. The FIXED production path (`dt=0.10`) and every fixed `dt` down to
`0.005` crossed the same window and completed to `t=3.5`.

## Reproduction (read-only harness)

`chk_adaptive_arm_tmp.m` — single adaptive run of the compressed arm
(`sg_trip=1, load_step=1.5, fault_on=2, fault_clear=2.15, line_trip=2.5,
restore=sg_on=3`, `Zf=0.01+0.01i`, `rtol_x=1e-4`, `dt_max=0.5`,
`dt_max_armed=0.05`).

## Bounded diagnosis (four falsification probes, all read-only)

1. **Quiet-window** (`chk_adaptive_quiet_tmp.m`): with events compressed to
   `[0.90,1.00]`, the controller grows `dt` to `dt_max=0.5` with `lte=0` over
   the `0→0.9 s` equilibrium coast. The Richardson estimator and step
   controller are correct → **estimator-bug hypothesis falsified.**
2. **Predictor toggle** (`chk_adaptive_predictor_tmp.m`): `state_predictor`
   `hold` vs `linear_kcl` gives byte-identical failure (`t=1.6366`, 768
   samples, 79 rejects). The linear predictor is not involved → **predictor
   hypothesis falsified.**
3. **Fixed fine-dt sweep** (`chk_fixed_finedt_tmp.m`): the FIXED stepper at
   `dt ∈ {0.10,0.05,0.02,0.01,0.005}` all converge to `t=3.5`. The composite
   Newton kernel is not the wall at fixed step → the failure is specific to the
   adaptive state path, not the kernel.
4. **Fixed dt-convergence** (`chk_fixed_conv_tmp.m`): the fixed trajectory
   converges as `dt→0` (max‖x−x_ref‖ vs the `dt=0.00125` reference shrinks
   ~2–8× per halving), so the arm has a well-defined ground-truth trajectory.
   BUT the production `dt=0.10` is grossly unconverged there (device 2 reaches
   `|I|=3.87×` its limit — a numerical overshoot; the `dt=0.01` state gap
   reaches ~12). The fast post-`sg_trip` transient genuinely needs `dt~1e-3`.
5. **Divergence localization** (`chk_adaptive_diverge_tmp.m`): the adaptive
   trajectory departs the fine-fixed trajectory immediately after `sg_trip`
   (max‖Δx‖≈0.30 by `t=1.05`, growing to ≈0.85 by `t=1.63`). The departure
   begins at the FIRST post-event step, not at a late stiff corner.

## Root cause

At an event the driver sets `rannacher_steps_remaining=1` so the next step is a
damped backward-Euler restart (order 1). On the FIXED path that BE step is one
nominal `dt`. On the adaptive path the step size carried into the restart was
the *pre-event* `dt_adaptive`, which the controller had grown to `0.4–0.5` in
the pre-trip quiet coast; the armed cap only limited it to `dt_max_armed=0.05`.
A single order-1 BE step of `0.05` spanning the sharpest part of the
post-`sg_trip` transient injected an `O(0.1)` state error. The LTE controller
then spent the following steps chasing that error down toward `dt_min`, and the
now off-manifold state reached a deep current-limiter / low-voltage corner
where the coupled Newton could not converge at any step size (the same
conditioning wall documented for fixed `dt=0.01` in
`2026-07-20-dt01-newton-stall-t325.md`). The `dt_min`/reject-limit fail-closed
then fired.

The defect is a missing **discontinuity step-size reinitialization**: the
pre-event step is meaningless after a C0 break, and every production adaptive
DAE integrator (CVODE, `ode15s`, …) restarts the step at a discontinuity.

## Fix

`+stability/ts_simulate_ibr_hybrid.m`, event-applied block: after
`rannacher_steps_remaining=1`, reset `dt_adaptive = settings.dt_min` (guarded on
`settings.stepper=="adaptive"`; the fixed path has no `dt_min` field). The
backward-Euler restart is then a single small `dt_min` step and the LTE
controller ramps the step back up (`×fac_max` per accepted step) from a
*measured* error. This reinitializes STEP SIZE only — no error tolerance,
equation, base, or gate changes — so it is not a post-hoc tolerance retune.

Two earlier partial changes were kept because they are independently correct
but were NOT sufficient alone (both left the `t=1.6366` failure unchanged):
per-attempt predictor rescaling for halved retries, and a backward-Euler
order-reduction rescue at the `dt_min` floor for C0 limiter kinks.

## Verification

Historical post-fix run: `converged=1`, `t(end)=3.5000`, `samples=3402`,
`rejected=235`, `floor_accepted=27`, 6 BE steps, observed
`dt∈[9.77e-05, 0.5]`, median `6.4e-4`, `wall≈410 s`. Every event
(`sg_trip, load_step, fault_on, fault_clear, line_trip, topology_restore,
sg_on`) was crossed with Newton residuals `~1e-9` and `iter≈10`.

**Correction:** because `ADAPT-2026-08-13-02` later proved the non-`stepper`
caller overrides were dropped, these exact counts, the stated `dt_max=0.5`, and
the ~6–11× timing comparison are historical diagnostic observations under the
driver defaults—not verified evidence for the requested option tuple. They must
not support a production-performance or parameter-forwarding claim. Current
post-forwarding acceptance evidence is the fresh 11/11 targeted gate recorded
in the correction note above; a current-tree full arm/performance rerun remains
required before publishing replacement metrics.

## Falsified hypotheses

1. Richardson estimator / controller bug — falsified (quiet-window grows to
   `dt_max` with `lte=0`).
2. Linear predictor corruption — falsified (`hold`≡`linear_kcl`).
3. Composite Newton kernel cannot cross the window — falsified (fixed
   `dt≤0.005` all cross).
4. Genuinely infeasible physics / no ground truth — falsified (fixed converges
   as `dt→0`).

## Limitations / related

- The underlying fine-`dt` composite-Newton conditioning wall
  (`2026-07-20-dt01-newton-stall-t325.md`, OPEN) is unchanged. The adaptive fix
  avoids driving the state INTO that corner; it does not widen the corner. If a
  future scenario legitimately requires `dt<dt_min` through a limiter kink, the
  fail-closed path still fires by design.
- The production `dt=0.10` fixed run is materially unconverged through the
  post-`sg_trip`/load-step transient (≈387 % current overshoot). This is a
  separate accuracy observation about the coarse fixed grid, recorded here as
  context; it is not introduced by this change.

## Related files

- `+stability/ts_simulate_ibr_hybrid.m` (adaptive path; the fix)
- `+stability/run_hybrid_case.m` (option pass-through + diagnostics)
- `tests/test_ts_hybrid_adaptive_lte.m`, `..._rollback.m`, `..._fixed_bitident.m`
- `scripts/validation/hybrid_adaptive_compare_fixed.m`
- `2026-07-20-dt01-newton-stall-t325.md`, `2026-08-11-ts-kernel-runtime-optimization.md`
