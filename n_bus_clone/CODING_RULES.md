# Coding Rules — N-Bus Power Flow Studio

## 1. Goal
All numerical analysis in this repository must be implemented *in-house* using
this project's own MATLAB code. The repository must remain free of external
power-system toolboxes, third-party libraries, cloud services, or wrapped
commercial solvers that perform power-flow or stability calculations for us.

## 2. What is allowed
- **MATLAB base built-in functions** such as `eig`, `inv`, `lu`, `qr`, `plot`,
  `bar`, `scatter`, `linspace`, `sprintf`, `fopen`, `fprintf`, `exportgraphics`,
  `uifigure`, `uiaxes`, `str2double`, `mean`, `max`, `sum`, `abs`, `real`,
  `imag`, etc.
- **Project functions only**: `+pfsolver/*`, `+smib/*`, `+pfapp/*`,
  `+pfchecks/*`, `internal/*`, `+cases/*`, `+stability/*`.
- **External system utilities for report rendering only**: `xelatex`
  (PDF compilation) is permitted because it does not perform any power-system
  computation.

## 3. What is prohibited
No code in this repository may call any of the following for power-flow,
small-signal stability, or electrical network modeling:

- MATLAB Power System Toolbox (`powerlib`, `Simscape Electrical`)
- MATPOWER
- Pandapower / PyPower
- PSS/E, PowerWorld, DigSILENT, PSAT, OpenDSS
- Any Python integration (`py.*`, `pyimport`) for power-system computation
- Cloud APIs or remote web services for computation
- Commercial or open-source toolboxes that provide ready-made power-flow,
  continuation power-flow, optimal power-flow, or eigenvalue analysis
- Symbolic toolbox calls (`syms`, `solve`) for numerical solver workarounds

## 4. Implementation rule
Every algorithm that produces a numerical result — power flow, continuation
power flow, optimal power flow, SMIB state matrices, and stability figures —
must be coded explicitly in this repository. If a function is not part of this
project and is not a MATLAB base built-in, it must not be called.

## 5. Plotting and GUI
Figures must use MATLAB base graphics primitives only. Do not use
`matlab2tikz`, `export_fig`, or other third-party plotting helpers.

## 6. Adding dependencies
Before adding any new external file, toolbox call, or system dependency:
1. Document the reason in this file.
2. Add a fallback that keeps the code working on a plain MATLAB installation
   without the dependency.
3. Update the continuous-integration workflow if necessary.

## 7. Verification
Before committing, run:
```matlab
runtests('tests')
```
All tests must pass. Any newly introduced external toolbox call is considered
a regression and must be removed.
