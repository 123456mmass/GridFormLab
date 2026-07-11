# Repository instructions for agents

These instructions apply to the entire repository.

## Non-negotiable rules

1. Production PF/SSSA/TS must use in-house MATLAB code. PSAT, PGAz, MATPOWER,
   Optimization Toolbox solvers, and book/reference programs are validation
   references only.
2. Do not use `git reset --hard`, `git clean`, or mass rewrites. This project
   previously lost uncommitted launchers and solver files through a reset.
   Checkpoint new files before any history operation.
3. Preserve numerical behavior when reorganizing files. Move wrappers to
   `compat/` and scripts to `scripts/`; update `pf_init_paths` and tests.
4. Do not claim equivalence from visually similar plots. Compare mapped bus and
   generator IDs, identical network/fault/load/machine inputs, and numeric error
   metrics.

## Numerical contracts

- PF: `pfsolver.powerflow_newton_raphson`, no external nonlinear solver.
- Network cases: `power_case/1.0`, 12-column `bus_data`, 7-column `line_data`,
  and MATPOWER-v2-compatible `mpc` matrices.
- Internal bus types: `1=REF`, `2=PV`, `3=PQ`; MATPOWER: `3=REF`, `2=PV`,
  `1=PQ`.
- Classical TS default: adaptive implicit trapezoidal corrector, exact fault
  event grid, update and trapezoidal-residual convergence checks.
- Sixth-order model: the operational EMF6 model
  (`stability.emf6_dae` / `stability.synchronous_emf6_ssa`) is the SINGLE
  equation set shared by SSSA and higher-order TS (`stability.ts_simulate_emf6`).
  It uses the in-house Newton solver and published parameters only -- no
  calibration knobs. The historical primitive-flux (psi-state) and calibrated
  GENTPJ (Kundur Table E12.3) realizations are in `legacy/`, off the MATLAB
  path, and are not in the catalog, launcher, or acceptance tests.
- Higher-order EMF6 TS uses a FIXED corrector (default `corrector_iter=3`).
  Do NOT describe it as adaptive until a residual-based convergence/
  rejection path is audited and tested. Adaptive corrector is validated only
  for the classical path.
- TS plot angle is `delta_i(t)-delta_i(0)` (PSAT `delta_Syn` style). Stability
  decisions use COI-relative and pairwise metrics, not the plotted common drift.
- Production packages (`+pfsolver`,`+stability`,`+smib`,`+pfapp`,`+pfchecks`,
  `+cases`,`internal`) contain no `fsolve`/`optimoptions`/`fmincon`/`fminsearch`
  (guarded by `test_no_external_solver_dependency`). `fsolve` is permitted only
  in `compat/powerflow_fsolve.m` as a reference comparison tool.
- Kundur Table E12.3 is reference/case-study data only, never a numerical
  acceptance target. Never tune parameters, scales, time constants, saturation,
  load model, finite-difference step or solver tolerance to match it.

## Required checks

```matlab
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);
```

For numerical cross-validation:

```matlab
compare_case14_ts_three_way;
compare_rts24_psat;
```

Read `docs/project/AGENT_HANDOFF.md` for current pass/fail status and known
technical debt before changing Kundur or sixth-order models.
