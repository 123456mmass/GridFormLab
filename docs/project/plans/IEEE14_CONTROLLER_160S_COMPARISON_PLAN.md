# IEEE14 160-s controller comparison plan

Date: 2026-08-04
Branch: `main`
Starting commit: `f7ff31690d031fb7b6eb32e3b1dd391caf4b23fa`

## Scope and non-goals

Run the identical project-owned IEEE 14-bus all-KCL chronology in three arms:
the verified cached legacy selector baseline, exhaustive ET-FCSPS, and an
eight-evaluation finite-set BO replay.  ET-FCSPS and BO may change only the
SG-trip GFL/GFM/reference-owner transaction.  SG/IBR equations, source/case
parameters, event times, post-trip dispatch, synchronizer, governor, solver,
time step, thresholds, and handback transaction remain identical.

The controller reports are new, separate TH/EN documents.  A requested
presentation correction is also applied to the existing English switch report
(GFM state wording and reference-owner figure label); no SG/IBR equation,
threshold, event, or numerical trajectory is changed.  No display ripple
enters controller evidence or numerical results.

The publication chronology is retained as a null/sanity case.  A second,
predeclared reference-PCC stress case is added after the first result showed
identical decisions: a bus-2 three-phase fault from 19.75--20.00 s, SG trip at
20.0125 s, and SG return request at 145 s.  This deliberately presents the
supervisor with a non-equilibrium accepted state one fixed step after clearing,
without changing the case model, controller equations, thresholds, weights,
solver, or time step.

That one-step-clear case is retained as an outside-validity diagnostic after
its declared voltage screen rejected all candidates.  The in-domain stress
case uses the same identities with fault 19.25--19.50 s and SG trip at
20.0125 s, leaving 0.5125 s (41 fixed steps) for post-clear recovery.

## Frozen experiment contract

- `CASE_DEFINED`: IEEE14 EECON49 Figure-4 data profile and the existing
  0--160 s chronology; fixed `dt=0.0125 s`.
- `PROJECT_DERIVED_PROTOTYPE`: ET-FCSPS policy already frozen by
  `stability.et_fcs_policy_ieee14`, including `T_p=0.25 s` and its weights.
- `NUMERICAL_METHOD`: every candidate starts from the same accepted event-left
  state, receives the same SG-trip transaction, physical mode-transfer map,
  post-trip dispatch and full-KCL right-limit solve, then uses the production
  fixed-step composite trapezoidal kernel for prediction.
- `CASE_DEFINED_NAMEPLATE_PROXY`: IBR P/Q reserve evidence uses the existing
  case resource limits.  It is not an energy-duration or readiness claim.
- `ASSUMED_DIAGNOSTIC_OFFLINE_REPLAY`: BO reveals at most eight costs from the
  immutable ET trial table.  It is allowed to choose the subsequent production
  trajectory but is not represented as an online optimizer or as proof of
  computational superiority.

## Allowlist

- additive `+stability/et_fcs_*production*.m` and controller comparison helpers;
- narrowly scoped plumbing in `+stability/run_hybrid_case.m` and
  `+stability/ts_simulate_ibr_hybrid.m`;
- controller-specific tests and reporting scripts;
- new raw artifacts below `output/diagnostics/ieee14_controller_compare/`;
- new raw stress artifacts below
  `output/diagnostics/ieee14_controller_reference_fault_stress/`;
- new raw stress artifacts below
  `output/diagnostics/ieee14_controller_reference_fault_recovery_stress/`;
- new TH/EN report sources and PDFs only;
- requested English switch-report source/PDF and figure-label correction;
- current handoff and any defect record required by reproducible evidence.

## Predeclared gates

1. The baseline cache must contain a converged raw trajectory ending at exactly
   160 s and match the frozen chronology and `dt` provenance.
2. Candidate trials are isolated, finite, full-KCL, start from one fingerprinted
   accepted event-left state, and cover the complete 0.25-s horizon.
3. Hard voltage, frequency, RoCoF, current, reserve, KCL, online/reference,
   dwell and lockout gates precede cost.
4. The committed ET/BO candidate must be present in the authenticated candidate
   universe and pass a stale-snapshot guard before the atomic event transaction.
5. Every long run either reaches 160 s with finite accepted states and declared
   residual bounds, or is reported fail-closed without extrapolation.
6. Comparison metrics use raw trajectories: minimum/maximum voltage, frequency
   nadir/peak, maximum RoCoF/current utilization, switch count, GFM-on time,
   reclose/handback status, residuals, prediction evaluations and wall time.
7. TH/EN PDFs build, render, and pass visual inspection with repository fonts;
   the requested English switch-report correction is presentation-only and
   does not alter numerical evidence.
8. A stress-case controller benefit is claimed only if all compared arms reach
   160 s and raw evidence differs in at least one predeclared quantity:
   selected GFM set, reference owner, switch count/GFM-on time, voltage,
   frequency, or current utilisation.  If the result remains identical, it is
   reported as a null result and is not tuned away.

## Verification and delivery

Run targeted controller-core, selector, event-transaction and SG-online gates,
then the two new long simulations.  Generate machine-readable MAT/CSV evidence,
new figures, and the two reports.  Record exact commands, tree, runtimes,
limitations and result classification; commit and fast-forward push after all
declared gates pass.
