# Agent handoff — 2026-07-14

## Latest progression and machine-migration checkpoint

The verified IEEE14 IBR Phase 5 checkpoint is `f1d372d`, published on
`origin/main` on 2026-07-14. Successor mission progression is:

- Phases 0–4: merged and complete.
- Phase 5: GFL structural model complete at `f1d372d`;
  `IEEE14_IBR_GFL_MODEL_READY=STRUCTURAL_ONLY`.
- Phase 6: REGFM_B1-derived GFM/VSG model is parked; planning/implementation
  has not started.
- Phases 7–17: not started.
- `IBR_PRODUCTION_INTEGRATION_READY=NOT_READY`.

Two follow-on commits checkpoint the current workstation for migration:

- `99ab4fe` — user-authorized absolute rotor-angle display policy.
- `681a3c3` — **WIP/CHECKPOINT** of current Padiyar/IEEE14 report code,
  report artifacts, validation-only PSAT driver, and report contract test.

### User-authorized rotor-angle display policy

Default TS/result plots use the stored absolute rotor angle `delta_i(t)` with
no initial-angle, reference-machine, or COI subtraction. Any transformed
diagnostic plot must be explicitly labeled. Stability decisions continue to
use COI-relative and pairwise metrics. No solver, state, or default plotter
implementation was changed for this policy; `scripts/plot_ts_result.m`
already displayed stored absolute angles.

### WIP report producer → artifact → test mapping

- `scripts/reporting/generate_padiyar_two_area_report.m` orchestrates the
  two-area report and invokes
  `scripts/reporting/generate_padiyar_ieee14_psat_tables.m`.
- `scripts/reporting/generate_padiyar_ieee14_psat_tables.m` computes the
  report-only IEEE14 Our/PSAT material and invokes the validation-only
  `scripts/validation/case14/run_psat_case14.m`.
- Generated/current artifacts are
  `docs/source/report_padiyar_two_area.{tex,pdf}` and the IEEE14/two-area
  TeX tables and PNG figures under
  `docs/source/figures/padiyar_two_area/`.
- `tests/test_padiyar_ieee14_report_section.m` is the intended structural
  report contract test.

These report files were captured exactly from the user's current working copy
for machine migration. They were **not regenerated or freshly revalidated in
this checkpoint**. By explicit user direction, Agent A ran no MATLAB tests,
PSAT/report generation, LaTeX compilation, or full regression for commits
`99ab4fe`/`681a3c3`. Their contents are WIP artifacts, not fresh acceptance
evidence and not an IBR readiness claim. Generated TeX tables retain
pre-existing trailing whitespace reported by `git diff --check`; it was not
rewritten because migration required preserving current contents exactly.

The last verified Phase 5 evidence remains the separate `f1d372d` record:
21/0/0 Phase 5 tests, 579/0/4 full regression (four PSAT-environment
incompletes), and 12/0 external-solver guard. Do not attribute those counts to
the WIP report checkpoint.

Local primary-source material under `docs/text/` was deliberately excluded
from Git: ignored PDFs plus untracked extracted `ding.txt` and `regfm.txt`.
The IEEE 1110 PDF version/hash mismatch documented in the Phase 5 handoff
remains unresolved. Preserve these local files; do not force-add them.

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

## 2026-07-13 Report rebuild (report/system-methods-v2 branch)

Canonical PF/SSSA/TS technical report rebuilt (C0-C8) on
docs/source/report_system_methods_update.tex from the equation-audited
14-section architecture. All tables/figures emitted fresh by
generate_system_methods_report against report HEAD 4f78cac.

Verification (all on report branch):
- Full regression: 351/351 passed, 0 failed, 0 incomplete.
- test_no_external_solver_dependency: PASS (real MATLAB path scan).
- Equation provenance audit: READY (101 equations, 0 gaps).
- LaTeX: 13-page PDF, 0 undefined references (compiled twice).
- Stale claims grep: 0 hits ("12 of 12", "May 2026", "PSAT not installed",
  CPF/OPF scope all removed).
- git diff origin/main..HEAD: report allowlist only; run_ts.m dirty edit and
  AGENT_HANDOFF.md advisor directive preserved untouched on main's working tree.

PSAT observed installed at ~/Documents/psat-2.1.11-mat/ (contradicts old
handoff "PSAT not installed"). IEEE14: PSAT fresh, PF dV=6.661e-16,
TS dCOI=0.0096 deg, psat_comparison=PASS. RTS-24: PSAT fresh, PF dV=4.441e-16,
TS dCOI=0.0068 deg (matches prior baseline 0.0067). PGAz runs but TS
discrepancy is diagnostic only (reported honestly, does not fail gate).

ADAPTIVE_DEFAULT_SWITCH_READY=NOT_READY (adaptive timestep is explicit,
not default). IBR_PRODUCTION_INTEGRATION_READY=NOT_STARTED.

No push, no merge. The dirty run_ts.m edit on main is excluded user work.
