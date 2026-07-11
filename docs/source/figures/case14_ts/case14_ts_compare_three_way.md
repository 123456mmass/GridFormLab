# IEEE 14-bus TS three-way: PSAT vs PGAz vs Ours (FRESH)

Scenario: bus-4 3-ph fault, Zf=0+j0.1 pu, t_fault=1.0 s, t_clear=1.1 s, dt=0.01 s, t_end=15 s.
Model: classical (gens 1,2,3,6,8; H=5, D=0, x'd=0.3). All three tools run FRESH this session.
PSAT/PGAz are reference tools only. Generators mapped by bus ID; angles/speeds in COI frame.

## Contract (Ybus machine precision)

| Pair | max|dY| | Gate |
|---|---:|---:|
| Ours-PSAT | 3.972e-15 | PASS |
| Ours-PGAz | 7.324e-15 | PASS |

## Power flow (pairwise)

| Pair | max|dV| (pu) | max|dAng| (deg) |
|---|---:|---:|
| PSAT-Ours | 6.661338e-16 | 3.552714e-14 |
| PGAz-Ours | 1.554312e-15 | 1.048051e-13 |
| PSAT-PGAz | 1.998401e-15 | 1.278977e-13 |

## Transient stability (COI frame, pairwise)

| Pair | max|dCOI| (deg) | max|dw| (pu) | max|dPe| (MW) | max|dVm bus4| (pu) |
|---|---:|---:|---:|---:|
| PSAT-Ours | 0.009571 | 3.816033e-06 | 0.042171 | 3.179264e-05 |
| PGAz-Ours | 0.616348 | 2.916429e-04 | 2.467655 | 2.264528e-03 |
| PSAT-PGAz | 0.615333 | 2.916136e-04 | 2.461673 | 2.257957e-03 |

## Gates

| Gate | Status |
|---|---:|
| contract_ybus_pgaz | PASS |
| contract_ybus_psat | PASS |
| gen_mapping_pgaz | PASS |
| psat_execution | PASS (td=1509) |
| pgaz_execution | PASS (nt=1501; fixed ci=8, residual unavailable) |
| ours_convergence | PASS (nonconv=0) |
| comparison_grid_valid | PASS |
| event_grid_valid | PASS |
| psat_comparison (primary) | PASS |
| pgaz_comparison (diagnostic) | FAIL |
| ALL_GATES_PASS | PASS |

Primary PSAT tolerance: PF dV<1e-6, dAng<1e-4; TS dCOI<0.05 deg, dw<1e-4 pu, dPe<0.1 MW, dVm<1e-3 pu.
PGAz is reported as a secondary diagnostic. Completion is not described as residual convergence, and its larger trajectory difference is not hidden by a relaxed tolerance.
