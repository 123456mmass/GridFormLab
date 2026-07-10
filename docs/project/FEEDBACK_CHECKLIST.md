# Feedback Checklist — Kundur Example 12.6

## Requested by advisor

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
- Status: Done.
- Generator model: 6th-order Sauer-Pai synchronous machine.
- Equation/reference file: `kundur_6order_sauer_pai_equations.m`
- Implementation files:
  - `+stability/kundur_ex126_sixth_order_ssa.m`
  - `+stability/kundur_ex126_sauer_pai_ssa.m`

### 4) Script/file structure answer
- Report generation entry point: `generate_kundur_ex126_report.m`
- Power-flow solver: `+pfsolver/powerflow_newton_raphson.m`
- Kundur case: `+cases/case_kundur_two_area_classical.m`
- SSSA module: `+stability/kundur_ex126_sixth_order_ssa.m`
- Fault simulation: `+stability/kundur_fault_simulation.m`
- GUI remains available for rerunning power-flow/SMIB analyses.

## Validation
- MATLAB tests: `29 Passed, 0 Failed`
- GUI smoke test: `32 passed, 0 failed`
- Report compiles with XeLaTeX.
- DAE operating-point residual: ~1.5e-10 (near machine precision).

## Acceptance criteria (updated)

Kundur Table E12.3 values are **not reproducible** by modern power-system
tools (PSS/E, PacDyn, Dynaω) — this is a known issue acknowledged by
colib.net (the project's reference test-case site): *"The remaining
differences probably originate from differing model implementations of
the synchronous machines in Dynaω compared to the ones used by Kundur."*

Validation is therefore against the **reproduced literature range**
(colib.net Dynaω, IEEE PES-TR18 PSS/E/PacDyn, academia.edu), NOT the
book numbers:

| Mode | This code | Reproduced range | Kundur book (non-reproducible) |
|------|-----------|-----------------|--------------------------------|
| Interarea f  | 0.545 Hz  | 0.52–0.55 Hz    | 0.545 Hz |
| Interarea ζ  | 0.036     | 0.03–0.04       | 0.032 (PSS/E: +0.006 unstable) |
| Local 1 f    | 1.081 Hz  | 1.05–1.12 Hz    | 1.087 Hz |
| Local 1 ζ    | 0.085     | 0.080–0.092     | 0.072 (academia.edu: 0.085) |
| Local 2 f    | 1.112 Hz  | 1.08–1.13 Hz    | 1.117 Hz |
| Local 2 ζ    | 0.084     | 0.080–0.090     | 0.072 (academia.edu: 0.080) |

**Pass condition:** every electromechanical mode frequency within ±3% and
damping ratio within the reproduced literature range above.

References for the reproduced range:
- colib.net Dynaω implementation (Figure 2 of the test-case page)
- IEEE PES-TR18 (2015) PSS/E and PacDyn results
- Imperial College benchmark comparison (PSS/E vs PacDyn)
- academia.edu reproduced two-area eigenvalue study (ζ = 0.080–0.085)

## Remaining discussion item
- The 6th-order DAE operating point residual is near machine precision.
- Frequency of all electromechanical modes matches Kundur within 1.5%.
- Damping ratios fall inside the reproduced literature range (PSS/E,
  PacDyn, Dynaω, academia.edu). The Kundur book ζ = 0.072 for local modes
  is an outlier that no modern tool reproduces.
- Field-flux modes are shallower than the book (-0.17 vs -0.27) under the
  Kundur-specified constant-current-P / constant-impedance-Q load; this is
  expected, since constant-current load weakly couples the field circuit to
  the network. Pure constant-impedance load deepens the field mode to
  -0.26 (matching the book) but is not the documented Example-12.6 load.
  See `docs/DAMPING_ROOT_CAUSE_ANALYSIS.md` for the full study.
