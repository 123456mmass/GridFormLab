# SWITCH-2026-08-03-02 — source-case restoration did not recover in reduced switching model

- **Status:** OPEN_MODEL_LIMITATION (event-contract defect resolved; recovery remains unvalidated)
- **Area:** IEEE 14-bus 1-SG + 4-IBR AGSI++ report case
- **Environment:** Windows, MATLAB R2026a, branch main, tested tree based on 3009e686

## Symptom

The first report run restored only the SG at 145 s while leaving the +20% load and line 6--13
outage active. Newton converged through 160 s, but the endpoint was nonphysical for a recovery
claim: all four IBRs were GFM and minimum bus voltage was 0.588 pu.

## Reproduction and evidence

Run the report producer from MATLAB after pf_init_paths and adding scripts/reporting to the path.
The source-data contract is: SG trip 20 s; all-load +20% at 50 s; bus-9 three-phase fault
85--85.15 s with 0.01+j0.01 pu; line 6--13 trip at 110 s; restoration at 145 s.
The authored source text specifies reconnecting the generator and transmission line and returning
load to its initial value.

## Root cause and correction

Observation: the old driver had only permanent load-step/line-trip contracts. Correction adds
finite step_off and line_reclose_time, restores both at 145 s, and removes the old forced
simultaneous GFM-to-GFL handback. IBRs now remain GFM until their own AGSI++ off threshold and
dwell are satisfied.

The corrected source-data route still exits the model-validity domain at 147.020 s
(dt=0.005 s), before any validated GFM-to-GFL transition. This is not hidden or tuned away.
The manual-field reduced SG lacks AVR/PSS, governor/turbine, synchronizer, and breaker dynamics;
the reduced-6 IBR omits DC-link and detailed inner/protection dynamics. Recovery is therefore
unvalidated and remains fail-closed.

## Falsified hypotheses

- Numerical convergence alone proves recovery: false; the earlier 160 s route converged but did
  not return near the operating point.
- Forcing all IBRs to GFL at reclose is a valid handback: false; it violates the local
  threshold/dwell state machine and caused immediate re-forming.
- Restoring topology/load alone is sufficient in this reduced model: false; the corrected route
  still leaves its validity domain after reclose.

## Verification

Targeted unit suites and PDF build commands are recorded in the final handoff. Figures contain
the raw valid prefix only, with no noise, smoothing, clipping, or fabricated recovery.

## Related files

- +ibr/padiyar_switch_tds.m
- +ibr/SwitchableIbr6.m
- scripts/reporting/generate_ieee14_switch_report_figures.m
- docs/source/report_ieee14_switch_th.tex
- docs/source/report_ieee14_switch_en.tex
