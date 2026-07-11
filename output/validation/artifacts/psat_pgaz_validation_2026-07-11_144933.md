# Three-way (Ours + PSAT + PGAz) Validation Artifact

Generated: 2026-07-11 14:48:15 +0700 (FRESH, this session — no saved .mat)

## Provenance
- Repository (absolute): `/home/birds/Documents/Power-flow`
- validated_source_commit: `20910e5a0319b51c02e5aed71ce26623eeac5485` (branch `main`)
- git status --porcelain: clean (artifact run from a clean tree)
- MATLAB version: 26.1.0.3276743 (R2026a) Update 3
- OS/platform: GLNXA64

## Reference tools (validation only, never production deps)
- PSAT: `/home/birds/Documents/psat-2.1.11-mat/psat` v2.1.11 [available]
  - PF: Newton (fm_spf, lftol=1e-12); TD: trapezoidal converged Newton (method=2).
  - Entry points: pgaz_pf.m, pgaz_ts.m (NOT in pf_init_paths).
- PGAz: `/home/birds/Documents/PGAz_V1.1.1` v1.1.1 [available]
  - Authors: Jaingeawkum, Surinkaew, Ngamroo (KMITL, 2024). File timestamps 2026-03-10.
  - Classical 2nd-order only (pgaz_ts.m L31); trapezoidal + fixed 3-iteration corrector (L48-49);
  - Norton behind jx'd (L36); fault = extra shunt admittance (L38). NOT used for EMF6.

## Commands (reproduce)
```matlab
restoredefaultpath; cd('<repo-root>'); pf_init_paths;
addpath('/home/birds/Documents/PGAz_V1.1.1');  % PGAz, validation session only
run_three_way_validation('case_matpower6_case14');
run_three_way_validation('case_ieee_rts24_pgaz', struct('fault_bus',15));
r = runtests('tests','IncludeSubfolders',true);
```

## Fresh three-way results

### Case14 (fault bus 4)

- Gen buses (mapped by ID): [1 2 3 6 8]
- Contract Ybus: Ours-PSAT=3.972e-15 (PASS)  Ours-PGAz=7.324e-15 (PASS)
- Ran: PSAT=PASS (td=1509)  PGAz=PASS (nt=1501)  Ours nonconv=0

| Pair | PF dV | PF dAng | TS dCOI | TS dw | TS dPe | TS dVm |
|---|---:|---:|---:|---:|---:|---:|
| PSAT-Ours | 6.661e-16 | 3.553e-14 | 0.0096 | 3.816e-06 | 0.0422 | 3.179e-05 |
| PGAz-Ours | 1.554e-15 | 1.048e-13 | 0.6143 | 2.916e-04 | 2.4412 | 2.264e-03 |
| PSAT-PGAz | 1.998e-15 | 1.279e-13 | 0.6122 | 2.916e-04 | 2.4352 | 2.258e-03 |

- PSAT_GATE (metrics ok) = PASS | PGAZ_GATE = PASS | ALL_GATES_PASS = PASS

### RTS-24 (fault bus 15)

- Gen buses (mapped by ID): [1 2 7 13 14 15 16 18 21 22 23]
- Contract Ybus: Ours-PSAT=2.842e-14 (PASS)  Ours-PGAz=2.842e-14 (PASS)
- Ran: PSAT=PASS (td=1509)  PGAz=PASS (nt=1501)  Ours nonconv=0

| Pair | PF dV | PF dAng | TS dCOI | TS dw | TS dPe | TS dVm |
|---|---:|---:|---:|---:|---:|---:|
| PSAT-Ours | 4.441e-16 | 6.750e-14 | 0.0068 | 4.204e-06 | 0.0827 | 5.354e-06 |
| PGAz-Ours | 2.319e-13 | 9.513e-12 | 0.3193 | 2.000e-04 | 3.7120 | 3.317e-04 |
| PSAT-PGAz | 2.321e-13 | 9.479e-12 | 0.3155 | 1.981e-04 | 3.6756 | 3.297e-04 |

- PSAT_GATE (metrics ok) = PASS | PGAZ_GATE = PASS | ALL_GATES_PASS = PASS


## Test discovery audit (141 -> 139)

- Previous (a285184): 141 tests (140 passed, 0 failed, 1 PSAT-filtered).
- Current: 152 tests (152 passed, 0 failed, 0 incomplete).
- The 141->139 drop occurred in commit dd72907 ("Withdraw external solvers +
  calibrated Kundur family"). It was a CONSOLIDATION, not deletion:
  6 granular guard tests (fsolve-confined, optimization-toolbox, calibrated-wrapper x3,
  fsolve-matches-Newton) were replaced by 4 broader recursive-scan guards
  (production_scope_has_no_external_solver, legacy_is_off_production_path,
  production_path_does_not_call_calibrated_wrappers, no_kundur_validation_claim_in_production_docs)
  + test_path_bootstrap. Net -2. Coverage preserved/strengthened (recursive scan vs
  hardcoded). The fsolve-vs-Newton comparison moved to legacy/ (fsolve is reference-only;
  production Newton covered by test_nr_solver).
- This session ADDED 13 tests: test_pgaz_conversion_contract (4) + test_validation_gate_logic (9).

## Full regression

- runtests('tests','IncludeSubfolders',true): 152 passed / 0 failed / 0 incomplete (total 152).
- Gate: PASS

## No-fault EMF6 equilibrium contract

- No-fault EMF6 TS: non-converged steps = 0 (contract requires 0). Gate: PASS

## Aggregate gate status

- Case14 ALL_GATES_PASS = PASS
- RTS-24 ALL_GATES_PASS = PASS
- Regression gate = PASS
- OVERALL ALL_GATES_PASS = PASS

Note: this artifact file is generated AFTER the implementation commit, so the
working tree is DIRTY when it is written. The validated_source_commit above is the
commit whose code produced these metrics (not the artifact commit).
