# Agent handoff — 2026-07-11

## Current baseline

The branch was returned to `47b1cd6` (adaptive classical TS integrator) after a
later reset/rewrite changed solver behavior. Missing uncommitted files were
recovered from Git dangling blobs or the known follow-up commit, then the root
was reorganized without changing the validated classical PF/TS equations.

A local safety stash named `safety-before-rollback-to-47b1cd6-2026-07-11`
contains the discarded post-reset rewrite. Do not pop it into `main`; inspect
individual files first.

## 2026-07-11 EMF6 unification + fsolve removal (this session)

The operational EMF6 model is now the SINGLE sixth-order equation set shared
by SSSA and higher-order TS:
- SSSA: `stability.multicase_sssa` dispatches every sixth-order case to
  `stability.synchronous_emf6_ssa` (in-house Newton, no fsolve).
- TS: `stability.ts_simulate` routes `model='emf6'` (and the legacy aliases
  `flux6`/`genpj6`/`kundur6`) to the new `stability.ts_simulate_emf6`, which
  consumes `stability.emf6_dae` directly (`dae_f(x,y)`, `dae_g(x,y,Y)`,
  `electrical_power(x,y)`). Fixed corrector (default `corrector_iter=3`);
  adaptive mode is present but NOT advertised as validated.
- Event grid snaps fault/clear times to exact grid points (the classical
  engine's `t_now >= t_fault` comparison is otherwise one step late under
  floating-point accumulation).

fsolve/optimoptions removed from all production packages. Moved to `legacy/`:
`synchronous_flux_ssa`, `kundur_ex126_book_flux_ssa`, `sauer_pai_flux_ssa`,
the `sauer_pai_ex83_ssa_*_tmp` trio, `genpj6_dae`, `ts_simulate_genpj6`,
`kundur_fault_simulation_6th_order`, `kundur_e123_{family,primitive}_compare`,
and their three tests. `powerflow_fsolve` moved to `compat/` (reference tool,
assume-guarded). The calibrated `kundur_ex126_kundur_ssa`/`book_e123_ssa`
family remains in `+stability` as fsolve-free reference implementations but is
NOT in the catalog, launcher, or acceptance tests.

Full regression: 141 tests, 140 passed, 0 failed, 1 PSAT-filtered.
Cross-validation reproduced on this host:
- Case14 PSAT-vs-Ours: PF 4.49e-6 pu / 8.07e-4 deg; TS 0.0196 deg /
  7.54e-6 pu / 0.0750 MW / 5.40e-5 pu; 0 non-converged steps (matches the
  documented baseline exactly -- classical path undisturbed).
- Kundur 12.6 EMF6-vs-PSAT: 1.89 deg / 3.67e-4 pu (tol 5 / 1e-3), 1 non-conv
  step of 6000 during the solid fault, init residual 2.13e-14. EMF6 uses only
  published parameters; no calibration.
- RTS-24: in-house TS runs clean (0 non-conv, max resid 2.3e-8). PSAT is not
  installed on this host and no saved RTS-24 PSAT reference exists here, so
  the PSAT leg is NOT re-verified (the documented baseline is from the
  original PSAT environment and is not re-fabricated).

Reproduce with: `pf_init_paths; runtests('tests','IncludeSubfolders',true);`
and `pf_init_paths; run_cross_validation;`

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

1. RESOLVED (2026-07-11): production packages no longer call `fsolve`/
   `optimoptions`; the historical sixth-order/diagnostic files that did are in
   `legacy/`. `compat/powerflow_fsolve.m` remains as an assume-guarded
   reference comparison tool.
2. RESOLVED (2026-07-11): the operational EMF6 SSSA and higher-order TS now
   share one equation set (`stability.emf6_dae`). `test_emf6_model` and
   `test_emf6_contract` cover the no-fault equilibrium, shared-model,
   initialization-consistency, torque/power-identity, reference-angle
   invariance and regression contracts.
3. Higher-order EMF6 TS is pinned to a FIXED corrector. Adaptive residual
   convergence is validated only for the classical path; an audited adaptive
   EMF6 path is future work.
4. RESOLVED (2026-07-11, session 2): the calibrated `kundur_ex126_kundur_ssa`
   / `kundur_ex126_book_e123_ssa` / `genrou_ssa` / `sixth_order_ssa` /
   `classical_analysis` family and `kundur_e123_reference` were moved from
   `+stability` to `legacy/kundur/`, off the MATLAB path. They carried
   historical tuning knobs and a calibrated Table E12.3 reproduction target;
   the reporting/validation/diagnostic scripts that depended on them were
   moved to `legacy/kundur/` as well. They must never be re-introduced as a
   production acceptance target.
5. Pre-existing stale data-shape expectations in `test_kundur_book_input_manifest`
   and `test_matpower6_case14` (10-col/5-col vs the documented 12-col/7-col
   contract) were corrected to match `AGENTS.md`.

## Safe continuation order

1. DONE (2026-07-11): removed production `fsolve` dependencies without
   changing the classical PF/TS baselines.
2. DONE (2026-07-11): unified EMF6 TS and SSSA around `emf6_dae`; added
   no-fault-equilibrium and equation-derived contract tests.
3. DONE (2026-07-11): full regression (141/140/0/1 PSAT-filtered) and the
   Case14 + Kundur6 cross-validations reproduced. RTS-24 PSAT leg could not be
   re-run on this host (PSAT absent) and is reported as not re-verified.
4. NEXT: audit/relocate the calibrated `kundur_ex126_kundur_ssa` family to
   `legacy/` (item 4 above); add a residual-based adaptive EMF6 corrector
   with tests (item 3 above); re-run RTS-24 vs PSAT where PSAT is available.
5. Always commit new files before any branch/reset operation.
