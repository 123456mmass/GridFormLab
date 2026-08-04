# SWITCH-2026-08-04-01 — bounded AGSI and publication-evidence correction

- **Status:** RESOLVED_DIAGNOSTIC_160S_WITH_CONTROLLER_LIMITATION
- **Area:** switch supervisor, IEEE14 report producer, TH/EN reports
- **Starting commit:** `7304460`
- **Environment:** Windows, MATLAB, branch `main`

## Symptoms

1. Published AGSI++ traces exceeded 1 although the presentation contract requires a normalized
   decision index in `[0,1]`.
2. The report originally presented a failed 36.040-s prefix and a compressed 4-s software gate
   beside the required 160-s event chronology without a sufficiently explicit evidence boundary.
3. The PF tables used explicit `+` signs and different effective widths.
4. The exact 160-s attempt exits the model-validity domain at 36.040 s after SG trip, before the
   50-s load step. The fixed GFM schedules do not replace the disconnected SG active power.

## Governing decisions

- User-approved mathematical contract: the weighted AGSI/AGSI++ decision value is saturated to
  `[0,1]`. The unsaturated sum is retained as `parts.raw_total` for diagnosis; switching and plots
  use `parts.bounded_total`.
- User-approved event contract: `T=160`; SG1 trip 20 s; every configured load P/Q +20% at 50 s;
  bus-9 fault 85--85.15 s; line 6--13 trip 110 s; SG1/line/base-load restoration 145 s; endpoint
  160 s.
- No Bayesian-optimisation controller is added before advisor review. Per the later explicit user
  instruction, continuous diagnostic plots use a seeded synthetic measurement overlay; raw states,
  SG/IBR equations, AGSI, thresholds, timers and mode decisions remain unchanged and captions label
  the overlay. A complete recovery claim still requires a raw 0--160-s trajectory to pass all gates.

## Test-contract correction

The previous tests asserted that the public baseline AGSI trace exceeded 10 and AGSI++ could be
below 3. Those assertions tested the old unbounded raw stress, contradicting the newly approved
normalized decision contract. They now assert `[0,1]` for both public routes. The independent
oracle is the implementation split between `raw_total` and `bounded_total`; behavioural switching
and no-chatter assertions remain unchanged. This is a mathematical-contract change explicitly
approved by the user, not a tolerance relaxation to obtain PASS.

## Fix

- Saturate the decision index and publish raw/bounded diagnostics separately.
- Freeze the exact 160-s schedule in the case and add an exact-value test.
- Remove the compressed 4-s figures and keep that case as an internal test only.
- After the user requested signal plots, add the exact-run accepted prefix as explicitly labelled
  diagnostic evidence: AGSI/GRA/reference/mode timelines and IBR+SG $P,Q,i_d,i_q,f$, angle and voltage.
- Generate both PF tables at `\textwidth`, with symmetric fill and minus signs only.
- Replace the one-line diagram with the user-supplied network figure.

## Falsified recovery hypotheses

- **Observation:** exact chronology with the existing common-reference election ends fail-closed at
  36.040 s; all four IBRs are GFM, frequency and angle drift, and later events are not reached.
- **Falsified:** simply restoring topology/load/reclose events can create recovery. The trajectory
  fails before those events.
- **Falsified diagnostic candidate:** proportional replacement of the lost SG power without changing
  the common-swing equation extended the prefix only to 41.830 s.
- **Falsified diagnostic candidate:** summing the four swing equations while applying the full lost-P
  command as a step caused a more severe transition near 20.32 s because the source-defined
  $M=0.08$ and missing command/ramp dynamics produce an abrupt acceleration. These experimental
  kernel edits were removed and are not delivered.
- **Open material choice:** a sourced or advisor-approved dispatch/secondary-frequency/energy-control
  law (including command dynamics and limits) is required before a truthful 160-s recovery result can
  be generated. Filling or extending the failed trace is not an admissible substitute.

### Continued 160-s investigation (same working day)

The following candidates were run on an uncommitted diagnostic tree and then removed because they
failed the predeclared nonlinear/system gates. No candidate result feeds the report or production
state.

- A Sakimoto-style two-state speed-primary governor attached directly to the mapped full-state GFM
  produced a fixed-bus right-half-plane pole at `+2.245 s^-1`; the local eigenvalue gate rejected it
  before a report run.
- A one-state secondary-frequency integrator with gain fixed analytically from
  `D_v^2/(4M)=7.03125` passed the per-device fixed-bus gate but the four-GFM island left the validity
  domain at 22.47 s. Local stability therefore did not establish multi-GFM stability.
- Deterministic post-trip active-power sharing, immediate GRA-loss override, and 0.5-s/5-s command
  lags were each falsified with both the mapped full-state pair and reduced-6 pair. Four physical
  GFM oscillators lost relative synchronism; electing one GFM left the remaining weak-grid GFL
  branches unstable. Reducing the step from 0.01 s to 0.002 s did not remove the physical runaway.
- The reduced-6 diagnostic exposed a separate limiter trap: the wrapper clamps the network-current
  injection while the device swing equation reads the unclamped electrical power. This split
  contract can publish incompatible network and rotor powers and must not be used as a recovery
  route without a device-owned limiter equation.
- The audited REGFM_B1 production hybrid engine is the appropriate next base because it already has
  multi-GFM equilibrium/all-KCL gates. A 40-s SG-cycle probe (trip 20 s, reclose request 39 s,
  `dt=0.01 s`) did not reach a terminal result within the declared 600-s runtime gate. Its current
  event schedule also assumes fault-before-trip, whereas the required chronology places the fault
  at 85 s after the 20-s SG trip; load-step and line-trip events are not yet supported by that route.

All experimental runtime edits were removed. The tested/pushed tree therefore retains the previous
fail-closed 36.040-s evidence rather than silently replacing it with an unvalidated controller.

## Verification

Targeted gates at this intermediate point were 25/25 PASS (24 combined IBR/IEEE14/full-state tests
plus the isolated bounded Padiyar index test). The full regression was intentionally omitted under
the repository risk policy.

## 2026-08-04 diagnostic 160-s resolution

The earlier 36.040-s observation remains valid for the retired report driver and is retained above
as defect history. The report producer now routes the chronology through the audited REGFM_B1
all-KCL hybrid engine. It adds a frozen `PROJECT_DERIVED` post-trip active-power allocation, an
`ASSUMED_DIAGNOSTIC` deterministic offline phase planner/voltage matcher, and a project-owned
two-state Sauer--Pai Type-A primary governor. These assumptions close the previously missing
diagnostic workflow; they do not constitute controller identification, protection validation, or
hardware readiness.

The primary fixed-step run (`dt=0.0125 s`) reaches 160.000 s with maximum accepted-step residual
`9.98175508801e-9`, maximum attempted parent residual `3.19889806266e-4`, and subdivision depth 1.
The SG passes the declared synchronism guard and closes at 147.175 s; the coordinated transaction
then returns all four IBRs to GFL. At the endpoint, `f_SG=60.046773383 Hz`, the last-2-s slope is
`+0.007391996 Hz/s`, the voltage range is `0.984909456--1.055630216 pu`, and
`P_e=1.048198640 pu`, `P_m=1.046208344 pu`. Recovery therefore means completion of the declared
topology/reference/mode/voltage transaction, not exact steady-state restoration.

A `dt=0.025 s` comparison also reaches 160 s but closes at 148.175 s, one second later. The report
therefore does not claim time-step-independent controller timing. Seeded band-limited ripple is
display-only: solid raw traces remain visible and the overlay never enters states, equations,
AGSI, timers, gates, or event decisions. Final targeted verification is 108/108 PASS; the full
repository regression remains intentionally omitted under the documented risk policy. English
and Thai reports build without overfull/error warnings and all 8+12 rendered pages were visually
reviewed.

## Related files

- `+ibr/SwitchableIbr6.m`
- `+ibr/padiyar_switch_tds.m`
- `+cases/case_ieee14bus_eecon49_switch.m`
- `scripts/reporting/generate_ieee14_switch_report_figures.m`
- `tests/test_ibr_switchable6.m`
- `tests/test_padiyar_switch.m`
- `tests/test_ieee14_eecon49_full_state.m`
- `docs/source/report_ieee14_switch_th.tex`
- `docs/source/report_ieee14_switch_en.tex`
