# Feedback Checklist — Kundur Example 12.6

## Historical advisor requests

The items below record requested deliverables and surviving artifacts. `Done`
means an artifact was produced at the time; it does not validate the numerical
values inside that artifact. Regenerate every figure before reuse.

### 1) Table 4 eigen real-vs-imag plot for all state variables/modes
- Status: Done.
- Figure: `docs/source/figures/kundur_ex126/full_eigenvalue_map.png`
- Included in report: `docs/source/report_kundur_ex126_classical.tex`
- Shows all Table E12.3 eigenvalue groups on the complex plane.

### 2) Time-domain fault plot: voltage of every bus and active power of every generator
- Status: Done.
- Fault scenario: temporary 3-phase fault at bus 8, cleared after 0.1 s.
- Figure: `docs/source/figures/kundur_ex126/fault_simulation.png`
- Contains:
  - rotor-angle differences relative to G1
  - active power of G1--G4
  - voltage magnitudes of Bus 1--11
  - rotor speed deviations of G1--G4
- Plot style fixed: white background, dark text, readable in PDF.

### 3) Generator order and equations
- Status: superseded.
- The former equation handout and Sauer--Pai implementation named here no
  longer exist at those paths.
- Use `+stability/emf6_dae.m` for the current EMF6 equations and consult
  `docs/project/AGENT_HANDOFF.md` for the remaining SSSA/TS integration gap.

### 4) Script/file structure answer
- Historical report generator: `scripts/reporting/generate_kundur_ex126_report.m`
- Power-flow solver: `+pfsolver/powerflow_newton_raphson.m`
- Kundur case: `+cases/case_kundur_two_area_classical.m`
- Current generic SSSA dispatcher: `+stability/multicase_sssa.m`
- Fault simulation: `+stability/kundur_fault_simulation.m`
- GUI remains available for rerunning power-flow/SMIB analyses.

## Validation status

The old test counts, numerical ranges, and Kundur pass condition previously
recorded here are withdrawn. They came from legacy or calibrated paths and
must not be quoted as current validation.

Current rules:

- Kundur Table E12.3 is reference data, not an accepted pass/fail benchmark.
- The calibrated Kundur wrapper is diagnostic-only and cannot supply report
  or presentation values.
- New results must identify the exact case, model equations, load model, base
  conversions, reference frame, solver path, commit, and test command.
- External comparisons must map identical buses and generators and use
  identical network, machine, load, and disturbance inputs.
- Current status and known gaps live in `docs/project/AGENT_HANDOFF.md` and
  `docs/KUNDUR_E123_REPRODUCTION_MEMORY.md`.

Before publishing new numerical claims, run:

```matlab
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);
compare_case14_ts_three_way;
compare_rts24_psat;
```
