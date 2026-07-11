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
| PGAz-Ours | 0.614315 | 2.916422e-04 | 2.441206 | 2.264256e-03 |
| PSAT-PGAz | 0.612232 | 2.916130e-04 | 2.435224 | 2.257649e-03 |

## Gates

| Gate | Status |
|---|---:|
| contract_ybus_pgaz | PASS |
| contract_ybus_psat | PASS |
| gen_mapping_pgaz | PASS |
| psat_ran | PASS (td=1509) |
| pgaz_ran | PASS (nt=1501) |
| ours_nonconv_zero | PASS (nonconv=0) |
| ps_metrics_ok (PSAT_GATE) | PASS |
| pg_metrics_ok (PGAZ_GATE) | PASS |
| ALL_GATES_PASS | PASS |

Tolerances (predeclared by method class): PF dV<1e-6 dAng<1e-4; TS converged dCOI<0.05; TS PGAz (fixed-3-iter) dCOI<1.0.
PGAz uses a fixed 3-iteration corrector (pgaz_ts.m default); its larger TS offset is method accuracy, not a conversion bug (PF matches at machine precision).
