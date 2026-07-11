# Three-way (Ours + PSAT + PGAz) Validation Artifact

Generated: 2026-07-11 15:58:48 +0700 (FRESH this session — tools run in this invocation, no saved .mat)

## Provenance
- Repository (absolute): `/home/birds/Documents/Power-flow`
- validated_source_commit: `b75e37af49ec525480fe8843c58ded4fda9a1197` (branch `main`)
- git status --porcelain: DIRTY (artifact written after source commit)
- MATLAB version: 26.1.0.3276743 (R2026a) Update 3
- OS/platform: GLNXA64

## Reference tools (validation only, never production deps; added to path for this session only)
- PSAT: `/home/birds/Documents/psat-2.1.11-mat/psat` v2.1.11 [available]
  - Entry points (which -all): runpsat=/home/birds/Documents/psat-2.1.11-mat/psat/runpsat.m; fm_spf=/home/birds/Documents/psat-2.1.11-mat/psat/fm_spf.m
  - PF: Newton (fm_spf, lftol=1e-12); TD: trapezoidal converged Newton (method=2). NOT in pf_init_paths.
- PGAz: `/home/birds/Documents/PGAz_V1.1.1` v1.1.1 [available]
  - Entry points: pgaz_ts=/home/birds/Documents/PGAz_V1.1.1/pgaz_ts.m; pgaz_pf=/home/birds/Documents/PGAz_V1.1.1/pgaz_pf.m; pgaz_ybus=/home/birds/Documents/PGAz_V1.1.1/pgaz_ybus.m
  - Authors: Jaingeawkum, Surinkaew, Ngamroo (KMITL, 2024). File timestamps 2026-03-10.
  - Classical 2nd-order only (pgaz_ts.m L31); trapezoidal + FIXED corrector (L48-49, no residual check);
  - Norton behind jx'd (L36); fault = extra shunt admittance (L468). NOT used for EMF6.

## Commands (reproduce)
```matlab
restoredefaultpath; cd('<repo-root>'); pf_init_paths;
addpath('/home/birds/Documents/psat-2.1.11-mat/psat'); addpath('/home/birds/Documents/PGAz_V1.1.1');
o14=run_three_way_validation('case_matpower6_case14');
o24=run_three_way_validation('case_ieee_rts24_pgaz', struct('fault_bus',15));
s14=run_pgaz_convergence_study('case_matpower6_case14');
s24=run_pgaz_convergence_study('case_ieee_rts24_pgaz', struct('fault_bus',15));
g=check_emf6_no_fault_gate();
r=runtests('tests','IncludeSubfolders',true);
```

## Fresh three-way results (COI = inertia-weighted, angle AND speed; no extrapolation)

### Case14 (fault bus 4)

- Gen buses (mapped by ID): [1 2 3 6 8]
- Contract Ybus: Ours-PSAT=3.972e-15 (PASS)  Ours-PGAz=7.324e-15 (PASS)
- Grid: raw_equal(Ours-PSAT)=0 raw_equal(Ours-PGAz)=1 comparison_valid=PASS event_valid=PASS align(PSAT)=PASS align(PGAz)=PASS extrap=0
- Execution: PSAT ran=1 completed=1 pf=1 (nt=1509) | PGAz ran=1 completed=1 corrector=8 converged=0 residual=0 (nt=1501) | Ours nonconv=0 completed=1

| Pair | PF dV | PF dAng | TS dCOI | TS dw | TS dPe | TS dVm |
|---|---:|---:|---:|---:|---:|---:|
| PSAT-Ours | 6.661e-16 | 3.553e-14 | 0.0096 | 3.816e-06 | 0.0422 | 3.179e-05 |
| PGAz-Ours | 1.554e-15 | 1.048e-13 | 0.6163 | 2.916e-04 | 2.4677 | 2.265e-03 |
| PSAT-PGAz | 1.998e-15 | 1.279e-13 | 0.6153 | 2.916e-04 | 2.4617 | 2.258e-03 |

- psat_comparison=PASS | pgaz_comparison=FAIL | ALL_GATES_PASS=FAIL

### RTS-24 (fault bus 15)

- Gen buses (mapped by ID): [1 2 7 13 14 15 16 18 21 22 23]
- Contract Ybus: Ours-PSAT=2.842e-14 (PASS)  Ours-PGAz=2.842e-14 (PASS)
- Grid: raw_equal(Ours-PSAT)=0 raw_equal(Ours-PGAz)=1 comparison_valid=PASS event_valid=PASS align(PSAT)=PASS align(PGAz)=PASS extrap=0
- Execution: PSAT ran=1 completed=1 pf=1 (nt=1509) | PGAz ran=1 completed=1 corrector=8 converged=0 residual=0 (nt=1501) | Ours nonconv=0 completed=1

| Pair | PF dV | PF dAng | TS dCOI | TS dw | TS dPe | TS dVm |
|---|---:|---:|---:|---:|---:|---:|
| PSAT-Ours | 4.441e-16 | 6.750e-14 | 0.0068 | 4.620e-06 | 0.0827 | 5.354e-06 |
| PGAz-Ours | 2.319e-13 | 9.513e-12 | 0.3196 | 2.170e-04 | 3.8481 | 3.388e-04 |
| PSAT-PGAz | 2.321e-13 | 9.479e-12 | 0.3160 | 2.145e-04 | 3.8099 | 3.367e-04 |

- psat_comparison=PASS | pgaz_comparison=FAIL | ALL_GATES_PASS=FAIL


## PGAz convergence characterization (physical inputs unchanged; only corrector_iter/dt vary)

### PGAz study: Case14

- plateau_ci = 3
- Corrector successive diffs (dCOI deg, domega, dPe MW, dVm):
  ci1-ci2: dCOI=2.844e+00 domega=1.174e-03 dPe=1.138e+01 dVm=7.977e-03
  ci2-ci3: dCOI=2.006e-01 domega=8.301e-05 dPe=7.334e-01 dVm=6.151e-04
  ci3-ci5: dCOI=6.040e-03 domega=2.747e-06 dPe=2.775e-02 dVm=1.647e-05
  ci5-ci8: dCOI=1.463e-05 domega=6.544e-09 dPe=7.219e-05 dVm=3.487e-08
  ci8-ci12: dCOI=2.385e-09 domega=1.105e-12 dPe=1.193e-08 dVm=6.575e-12
- Timestep successive diffs (ci=plateau):
  dt0.020-dt0.010: dCOI=2.581e+00 domega=1.039e-03 dPe=1.017e+01 dVm=6.675e-03
  dt0.010-dt0.005: dCOI=4.874e-01 domega=2.024e-04 dPe=1.992e+00 dVm=1.216e-03

### PGAz study: RTS-24

- plateau_ci = 5
- Corrector successive diffs (dCOI deg, domega, dPe MW, dVm):
  ci1-ci2: dCOI=4.194e+00 domega=2.848e-03 dPe=5.186e+01 dVm=2.239e-03
  ci2-ci3: dCOI=3.140e-01 domega=2.112e-04 dPe=3.954e+00 dVm=1.588e-04
  ci3-ci5: dCOI=2.340e-02 domega=1.591e-05 dPe=2.926e-01 dVm=8.681e-06
  ci5-ci8: dCOI=1.252e-04 domega=8.473e-08 dPe=1.565e-03 dVm=4.022e-08
  ci8-ci12: dCOI=4.999e-08 domega=3.371e-11 dPe=6.321e-07 dVm=2.288e-11
- Timestep successive diffs (ci=plateau):
  dt0.020-dt0.010: dCOI=3.886e+00 domega=2.625e-03 dPe=4.805e+01 dVm=1.826e-03
  dt0.010-dt0.005: dCOI=9.430e-01 domega=6.396e-04 dPe=1.176e+01 dVm=4.402e-04

Plateau corrector count used for primary PGAz: ci=8 (ci8-ci12 ~ 1e-9 on all metrics).
Root-cause attribution: increasing corrector_iter does NOT bring PGAz closer to PSAT/Ours
(ci=3,8,12 all give ~0.6 deg case14 / ~0.3 deg RTS-24). The fixed-3-corrector hypothesis
is REFUTED. The difference is an integration-formulation difference in PGAz (Norton network
solve + fixed-point corrector), NOT corrector count, Ybus (machine-precision match), fault
admittance (matches), or mapping (correct). This is a PGAz-source characteristic; PGAz source
was NOT modified. PGAz comparison gate = FAIL (plateau PGAz exceeds the tight tolerance).

## No-fault EMF6 gate (fault_enabled=false; true no-fault)

- fault_disabled=1  max|f|=1.665e-15  max|g|=2.132e-14  init_residual=2.132e-14
- nonconv=0  max_corrector_resid=1.108e-16  completed=1  all_finite=1
- drift: delta=2.220e-16 omega=2.945e-17 Vbus=0.000e+00 Pe=5.329e-15 (tol 1e-9)
- GATE = PASS

## Production / no-Kundur / EMF6-shared-model gates

- production_dependency (no external solver in production): PASS
- no_kundur_acceptance_target (no literature ranges as acceptance): PASS
- emf6_shared_model (SSSA & TS share emf6_dae): PASS

## Test discovery audit (141 -> 139 -> 191)

- a285184: 141 (140 pass + 1 PSAT-filtered). dd72907: 139 (consolidation of guard tests).
- This session: 191 (152 + 39 new physics/grid/COI/PGAz/gate/artifact tests; -1 removed literature-range test).
- The 141->139 drop was a CONSOLIDATION (6 granular guards -> 4 recursive-scan guards + path_bootstrap),
  not deletion. Coverage preserved/strengthened. fsolve-vs-Newton moved to legacy/ (reference-only).

## Full regression

- runtests: 191 passed / 0 failed / 0 incomplete (total 191). Gate: PASS

## Aggregate gate status (all required gates)

- Case14 ALL_GATES_PASS = FAIL
- RTS-24 ALL_GATES_PASS = FAIL
- OVERALL ALL_GATES_PASS = FAIL
- FALSE gates: case14.pgaz_comparison, rts24.pgaz_comparison

Note: OVERALL is FAIL because the PGAz plateau comparison exceeds the tight tolerance
(0.6 deg case14 / 0.3 deg RTS-24 > 0.05 deg). This is an honest FAIL: PGAz's converged
solution differs from PSAT/Ours due to its integration formulation (proven: ci=12 gives the
same offset; Ybus/fault/mapping/PF all match). PGAz source was not modified. No tolerance
was relaxed to force a pass.
