# SWITCH-2026-08-03-02 — IEEE14 source-case restoration and missing island dispatch contract

- **Status:** OPEN_MODEL_LIMITATION (event and current-feedback defects resolved; full chronology unvalidated)
- **Area:** IEEE 14-bus 1-SG + 4-IBR AGSI++ EECON49 report case
- **Environment:** Windows, MATLAB, branch `main`, working tree based on `4a94bc5`

## Symptom history

The first report route restored only the SG at 145 s while leaving the +20% load and line 6--13
outage active. A later reduced-state route restored all scheduled events but left its validity
domain near reclose. After replacing that diagnostic projection with the EECON49 full-state
GFL/GFM branches and the six-state operational EMF6 SG, the full chronology now fails earlier:
the SG trips at 20 s, all IBRs become GFM by 20.150 s, frequency then falls because their fixed
active-power references do not replace the removed SG dispatch, and the accepted trajectory
ends fail-closed at 36.040 s (about 43.69 Hz, minimum voltage 0.6328 pu).

## Reproduction

```matlab
pf_init_paths;
addpath(fullfile('scripts','reporting'));
generate_ieee14_switch_report_figures;
```

The source chronology is: SG trip 20 s; mapped load +20% at 50 s; bus-9 three-phase fault
85--85.15 s with `Zf=0.01+0.01i` pu; line 6--13 trip at 110 s; SG/line/load restoration at
145 s. The present full-state run stops before the last four events; they are not claimed as
validated by this trajectory.

## Resolved defects

1. The report driver now has finite load-step and line-out intervals and restores SG, topology,
   and base dispatch at the same scheduled restoration event.
2. The EECON profile uses the operational six-state EMF6 SG and full-state EECON49-mapped IBR
   branches rather than the reduced-6 projection.
3. The first full-state current-controller implementation used `i-iref`, which is positive
   feedback for the printed PI voltage command. A fixed-bus finite-difference linearization
   exposed a local GFL eigenvalue at approximately `+156.7 1/s`. The implementation now uses
   `iref-i`; every nonzero local GFL/GFM branch mode is in the closed left half-plane. The two
   exact zeros in the GFL superset are the ideal DC energy port and inactive padding state.
4. A compressed ideal-SG reclose gate (`T=4`, trip 1 s, reclose 3 s, `dt=0.01`) converges,
   returns all four devices to GFL, gives two mode changes per IBR, final minimum voltage
   1.033013253 pu, and maximum Newton residual about `9.93e-9`.
5. The first dual-run report generator reused the mutable `SwitchableIbr6` objects after the
   long run, so the compressed gate inherited committed modes/timers and falsely diverged at
   0.58 s. The producer now constructs a fresh system for every independent trajectory; the
   standalone and generated recovery results agree.

## Remaining source gap and root cause

The PDF publishes the device block diagrams and parameter table, but it does not publish:

- the energy-source/DC current control law `I_dc` or its energy/power limits;
- post-SG-trip active-power redistribution or secondary frequency dispatch;
- leader election, synchronization, and sharing equations for four simultaneous GFMs;
- the detailed transfer from the island reference back to the reclosed SG reference.

The code closes the unspecified DC port with ideal instantaneous power balance so that the
printed `V_dc` state can be retained without inventing a gain. It also has an explicitly
`PROJECT_DERIVED` first-committed-GFM angle/frequency reference for the diagnostic island.
Neither choice supplies the missing active-power reserve. Fixed pre-trip IBR references therefore
leave a real-power deficit after the SG trip. Adding SG electrical states alone cannot correct a
missing dispatch/energy contract; a governor/secondary controller or an independently sourced IBR
dispatch law is required.

## Falsified hypotheses

- **“A sixth-order SG is sufficient for paper-like recovery.”** False. EMF6 adds rotor/flux
  dynamics, but `Tm` and `Efd` are equilibrium controls held constant; it does not create
  governor, AVR, synchronizer, breaker, or secondary-dispatch behavior.
- **“All IBRs switch simultaneously.”** False in the full-state result. IBR1--2 commit at
  20.130 s and IBR3--4 at 20.150 s because each has a local index/timer.
- **“One GFM becomes the PF slack.”** False. The elected device supplies a common plotted/
  coordinated angle-frequency reference only; all devices remain current injections in full KCL.
- **“Noise, state reset, or threshold tuning can prove recovery.”** False. Those operations
  would alter evidence rather than close the physical contract and are prohibited.

## Verification and limitation

The dedicated full-state tests cover route/state order, equilibrium residuals, fixed-bus local
eigenvalues, and the compressed coordinated handback. Existing IEEE14 switching and EMF6 contract
tests cover the legacy consumers. Fresh targeted result on 2026-08-04: 31 passed, 0 failed,
0 incomplete across `test_ieee14_eecon49_full_state`, `test_ibr_sg_on_all_gfl_equilibrium`,
`test_ieee14_switch`, `test_emf6_contract`, and `test_emf6_physics_contract`. Both XeLaTeX reports
built without overfull/math/error warnings and all 19 rendered PDF pages were visually inspected.
The full repository regression was intentionally omitted because the targeted producer, consumer,
and failure-path gates cover this scope. The full chronology remains intentionally fail-closed at
36.040 s; it is not a reproduction of the paper's 145-s recovery.

## Related files

- `+ibr/gfl_eecon49_full_model.m`
- `+ibr/gfm_eecon49_full_model.m`
- `+ibr/padiyar_switch_tds.m`
- `+ibr/SwitchableIbr6.m`
- `+stability/sg_composite_device.m`
- `scripts/reporting/generate_ieee14_switch_report_figures.m`
- `tests/test_ieee14_eecon49_full_state.m`
- `docs/source/report_ieee14_switch_th.tex`
- `docs/source/report_ieee14_switch_en.tex`
