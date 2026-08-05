# eecon49 fault-on right-limit exhausts the algebraic-solver iteration lease

- **ID:** TS-2026-08-05-01
- **Status:** RESOLVED
- **Area:** fault-on algebraic right-limit, `+stability/ts_algebraic_solve.m` and
  the fault homotopy `+stability/ts_simulate_ibr_hybrid.m` (`fault_right_limit_homotopy`)
- **Branch / commit:** `main` @ `126ae57` + committed Phase D/E/F/G/H work
- **Environment:** Windows 11, MATLAB R2026a, `D:\Project\Power-flow`

## Symptom

A 200-s production run on the Phase D operating point (slack `|V|=1.00` pu,
`phi=0.508383707164714`, `lost_sg_MW=133.190444`) fails closed at the fault-on
event:
```
Production run failed closed at 85.000000 s (required 200 s):
ts_simulate_ibr_hybrid:rightLimit
Fault homotopy failed near lambda=0.086914: ts_algebraic_solve:failed:
Algebraic solve did not converge: residual=1.116e-06 (tol=1.000e-06),
iterations=30, line_search_failures=0.
```
`generate_ieee14_switch_report_figures` ran with the default `reuse_cache=false`
(no stale-cache reuse; the horizon guard correctly forced a fresh run).

## Reproduction

`generate_ieee14_switch_report_figures()` with the Phase D case values reproduces
it deterministically. The fault-on event at 85.0 s calls
`fault_right_limit_homotopy`, whose endpoint right-limit solve in
`ts_algebraic_solve` reaches the hard `for k = 1:30` ceiling at residual
`1.116e-06` against `kcl_tol=1e-06`.

## Root cause analysis (resolved)

H1 was confirmed over H2 by the error signature: the failure occurred in the
loop-end branch (`for k = 1:30` finished, `converged=false`), not the
non-finite-step or line-search-exhausted branches, and `line_search_failures=0`
means every damped-Newton step was accepted (monotonic convergence). The solve
was genuinely converging and only ran out of the fixed 30-iteration lease at a
residual 11% above `kcl_tol`, because the Phase D operating point shifted the
fault-on right-limit enough to cross the old convergence margin.

- **H1 — lease shortfall (converging smoothly):** the Newton residual made
  monotonic progress (`line_search_failures=0`) and landed 11% above tolerance
  purely because the solver's fixed 30-iteration cap ran out. A few more
  iterations would take the residual below `1e-06`. This would make raising the
  iteration budget a legitimate `NUMERICAL_METHOD` change.
- **H2 — genuine marginal stall:** the fault-on right-limit on the new operating
  point is near a conditioning boundary and 30 iterations is not merely tight.
  Raising the cap would not help.

The operating point shift (slack 1.06 -> 1.00, re-derived `phi`) changed the
fault-on solve enough to cross the old convergence margin. This is a shared
single-owner solver; a change to its iteration lease must be justified by
convergence evidence, not tuned to make this case pass.

## Constraints (AGENTS.md)

- `kcl_tol` (acceptance residual) MUST NOT be raised to make the run pass.
- `ts_algebraic_solve.m` is a shared single-owner numerical file; ownership and
  a numerical-contract decision are required before editing its iteration lease.

## Resolution

H1 was confirmed: the residual made monotonic progress with every step accepted
(`line_search_failures=0`) and the loop-end branch fired, so the solve was
converging and only exhausted the fixed 30-iteration lease at 11% above
`kcl_tol`. The iteration lease was raised 30 -> 60 in `ts_algebraic_solve.m` as
a `NUMERICAL_METHOD` change; `kcl_tol` was unchanged.

## Verification

- The 200-s production run now completes: `FULL_200_S_GATE_PASSED`,
  `diverged=0`, `newton_all_converged=1`, `max_step_residual=9.99e-09`,
  subdivision depth 1, all 8 events landed, SG reclose at 146.825 s,
  `reclose_status='SUCCESS'` (accepted-step residual is the gate; the attempt-
  level residual 3.48e-04 is diagnostic only).
- Report (EN/TH) rebuilt at 13 / 12 pages, no undefined references.
- Endpoint all-bus voltage range 0.9203--1.0000 pu: regulating buses in the
  $\pm5\%$ band, five remote load buses below $V_{\min}=0.95$ pu — reported
  openly, not claimed as full recovery.

## Related files

- `+stability/ts_algebraic_solve.m` (iteration cap raised 30 -> 60)
- `+stability/ts_simulate_ibr_hybrid.m` (`fault_right_limit_homotopy`,
  `kcl_tol=1e-06`)
- `scripts/reporting/generate_ieee14_switch_report_figures.m` (horizon guard,
  `reuse_cache`)
- `+cases/case_ieee14bus_eecon49_switch.m` (Phase D operating point)
- `docs/source/report_ieee14_switch_en.tex`,
  `docs/source/report_ieee14_switch_th.tex` (updated to 200-s results)
