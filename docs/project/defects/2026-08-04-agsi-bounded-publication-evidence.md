# SWITCH-2026-08-04-01 — bounded AGSI and publication-evidence correction

- **Status:** RESOLVED_WITH_OPEN_160S_CONTROL_GAP
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

## Verification

Targeted gates: 25/25 PASS (24 combined IBR/IEEE14/full-state tests plus the isolated bounded Padiyar
index test). The full regression was intentionally omitted under the repository risk policy. EN/TH
XeLaTeX builds pass; 7 English and 10 Thai pages were rendered and visually reviewed. The exact
160-s dynamic gate remains OPEN for the material control-law choice above.

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
