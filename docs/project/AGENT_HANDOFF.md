# Agent handoff — 2026-07-11

## Current baseline

The branch was returned to `47b1cd6` (adaptive classical TS integrator) after a
later reset/rewrite changed solver behavior. Missing uncommitted files were
recovered from Git dangling blobs or the known follow-up commit, then the root
was reorganized without changing the validated classical PF/TS equations.

A local safety stash named `safety-before-rollback-to-47b1cd6-2026-07-11`
contains the discarded post-reset rewrite. Do not pop it into `main`; inspect
individual files first.

## Stable entry points

- `run_powerflow.m`
- `run_sssa.m`
- `run_ts.m`
- `solve_case.m`
- `pf_init_paths.m`

Root is reserved for those entry points and project documentation. Historical
wrappers are in `compat/`; runnable support scripts are under `scripts/`; old
reference submissions are under `legacy/` and are deliberately not on the
MATLAB path.

## Restored contracts and files

- `+cases/standardize_case.m` and `standardize_study_case.m`
- standard network/study schema calls in case loaders
- `+stability/classical_sssa.m`
- `+stability/emf6_dae.m` and `synchronous_emf6_ssa.m`
- `internal/core/nonlinear_newton.m`
- catalog-driven `solve_case` with state/status logging
- PF/SSSA launchers and missing contract/launcher tests

## Validated numerical baselines

### IEEE RTS-24 vs PSAT 2.1.11

Same converted network, constant-impedance load, classical machines, bus-15
fault, `Zf=j0.1`, 1.0–1.1 s, `dt=0.01`:

- PF max voltage and angle differences: numerical zero
- max incremental COI-angle error: `0.0067 deg`
- max speed error: `4.67e-6 pu`
- max fault-bus voltage error: `0.0054 mpu`
- max electrical-power error: `8.27e-4 pu`
- non-converged adaptive steps: `0`

### IEEE 14-bus three-way check

The validator maps generators by bus `[1,2,3,6,8]`, compares angles/speeds in
the COI frame, and reads fault voltage from bus ID 4 (an earlier script
accidentally read generator-column 4 / bus 6). PSAT PF and TD both converge to
15 s. With the production adaptive engine, PSAT vs Ours gives:

- PF max voltage difference: `4.49e-6 pu`
- PF max angle difference: `8.07e-4 deg`
- TS max COI-angle error: `0.0196 deg`
- TS max speed error: `7.54e-6 pu`
- TS max electrical-power error: `0.0750 MW`
- TS max bus-4 voltage error: `5.40e-5 pu`

Run `compare_case14_ts_three_way` after any TS change.

## Known technical debt — do not hide

1. Some historical sixth-order/diagnostic files still call Optimization
   Toolbox `fsolve`; migrate them to `internal/core/nonlinear_newton` or move
   them out of production packages. Do not add new `fsolve` use.
2. The operational EMF6 SSSA and the older GENTPJ TS path are not yet one
   implementation. `test_emf6_model/test_ts_uses_same_emf6_dae` documents the
   remaining integration gap.
3. Higher-order TS is pinned to fixed corrector iterations. Adaptive residual
   convergence is validated only for the classical path.
4. Kundur book-model work must be validated against printed parameters and
   PSAT using identical conventions before changing production defaults.

## Safe continuation order

1. Remove remaining production `fsolve` dependencies without changing PF/TS
   baselines.
2. Unify EMF6 TS and SSSA around `emf6_dae` and add no-fault equilibrium tests.
3. Run full regression and both Case14/RTS-24 cross-validations.
4. Commit new files before any branch/reset operation.
