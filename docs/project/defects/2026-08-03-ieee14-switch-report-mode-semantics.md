# IEEE14 switching report mode semantics and figure-count contract

- ID: `SWITCH-2026-08-03-01`
- Status: `RESOLVED_TEST_CONTRACT`
- Area: IEEE14 AGSI++ GFL/GFM reporting and demo figures
- Affected tree/environment: `main` based on `b311cf4`; MATLAB on Windows; 2026-08-03

## Observed symptoms

The Thai and English reports did not make the stored per-IBR mode, dwell timers,
normal index-driven transitions, and coordinated SG-reclose handback distinct
enough to answer reviewer questions.  The Thai prose also described the SG as
having no governor, although the implemented SG includes primary droop and lacks
only secondary/integral frequency restoration.  After adding the required binary
mode timeline, `test_ieee14_switch/test_demo_route_ieee14` still required exactly
eight figures and failed because the correct output now contains nine.

## Deterministic reproduction

```matlab
restoredefaultpath; cd('D:/Project/Power-flow'); pf_init_paths;
o = ibr.padiyar_switch_demo(system="ieee14", T=6, dt=2e-3, visible=false);
numel(o.fig_paths)
string(o.fig_paths)
```

Before correcting the test contract, the result contains nine paths including
`padiyar_switch_mode.png`, while line 70 of `tests/test_ieee14_switch.m` expects
eight.

## Root cause and evidence

The report previously summarized outcomes without exposing the implemented
hybrid-state semantics.  `+ibr/SwitchableIbr6.m` stores a mode and independent
up/down dwell timestamps for every device.  `+ibr/padiyar_switch_tds.m` applies
normal AGSI++ decisions per device after accepted steps, but the SG-reclose path
performs a coordinated GFM-to-GFL reference handback.  The SG configuration uses
primary droop `R=0.05`; therefore “no governor” was an inaccurate presentation
statement.  The eight-figure assertion was a stale presentation count, not a
numerical or switching acceptance criterion.

## Falsified hypotheses

- The ninth path is not an accidental duplicate: it has the unique basename
  `padiyar_switch_mode.png` and contains four binary device timelines.
- The test failure does not indicate changed switching equations or results:
  the remaining switching, convergence, equilibrium, and failure-path tests pass.
- SG reclose is not another index-threshold crossing; code inspection shows the
  explicit coordinated handback path.

## Correction

- Added a four-panel `0=GFL`, `1=GFM` mode timeline and a frozen reporting script.
- Expanded the Thai report and briefly updated the English report with the state
  machine, transition audit, event coverage, AGSI variable definitions, and model
  limitations.
- Corrected the SG wording to primary droop without secondary restoration.
- Updated the presentation test to require nine figures and independently assert
  that the new mode-timeline basename is present.

No physical equation, model parameter, threshold, dwell time, numerical result,
or numerical acceptance gate was changed.

## Verification and limitations

Code Analyzer reports zero findings for the modified demo and generator.  The
targeted switching suites are rerun after correcting the stale presentation
contract.  The report explicitly limits claims to the reduced positive-sequence
RMS study model; it does not claim EMT, relay-grade synchronism checking, or
hardware readiness.

## Related files

- `+ibr/padiyar_switch_demo.m`
- `scripts/reporting/generate_ieee14_switch_report_figures.m`
- `tests/test_ieee14_switch.m`
- `docs/source/report_ieee14_switch_th.tex`
- `docs/source/report_ieee14_switch_en.tex`
