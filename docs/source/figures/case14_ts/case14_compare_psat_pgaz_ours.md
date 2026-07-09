# IEEE 14-bus comparison: PSAT vs PGAz vs Ours

## PF comparison

Injected PSAT case: `d_case14_mp_test_dyn_mdl.m`.

| Metric | Max abs diff |
|---|---:|
| PSAT - PGAz voltage (pu) | 1.062 |
| PSAT - Ours voltage (pu) | 1.06152 |
| PSAT - PGAz angle (deg) | 67357.1 |
| PSAT - Ours angle (deg) | 67357.1 |

## TS comparison status

| Pair | Status | Max difference / diagnostic |
|---|---|---:|
| PGAz vs Ours | PASS | delta 1.44e-9 deg, omega 1.38e-14 pu, Pe 6.37e-11 MW, Vm 5.26e-14 pu |
| PSAT vs PGAz/Ours | NOT YET COMPARABLE | PSAT TD stopped at t=0 s, points=1, deltat=0, Newton error=1.63758 |

Reason: PF loads/network are now injected, but PSAT dynamic/algebraic initialization for the simplified Syn case is not yet converging. Do not interpret this as a solver mismatch.

## Bus PF table

| Bus | PGAz V | PSAT V | Ours V | PGAz angle | PSAT angle | Ours angle |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 1.060000 | 1.060000 | 1.060000 | 0.000000 | 0.000000 | 0.000000 |
| 2 | 1.045000 | 1.045000 | 1.045000 | -4.983000 | -30.101682 | -4.982589 |
| 3 | 1.010000 | 1.010000 | 1.010000 | -12.725000 | -74.589159 | -12.725100 |
| 4 | 1.018000 | 0.158720 | 1.017671 | -10.313000 | 47.533551 | -10.312901 |
| 5 | 1.020000 | 0.000001 | 1.019514 | -8.774000 | -67365.824620 | -8.773854 |
| 6 | 1.070000 | 1.070000 | 1.070000 | -14.221000 | 1771.242924 | -14.220946 |
| 7 | 1.062000 | 0.000001 | 1.061520 | -13.360000 | 1456.245567 | -13.359627 |
| 8 | 1.090000 | 1.090000 | 1.090000 | -13.360000 | 1456.245567 | -13.359627 |
| 9 | 1.056000 | 0.611249 | 1.055932 | -14.939000 | 1802.578893 | -14.938521 |
| 10 | 1.051000 | 0.647791 | 1.050985 | -15.097000 | 1817.411934 | -15.097288 |
| 11 | 1.057000 | 0.839212 | 1.056907 | -14.791000 | 1785.415533 | -14.790622 |
| 12 | 1.055000 | 1.013294 | 1.055189 | -15.076000 | 1771.542546 | -15.075585 |
| 13 | 1.050000 | 0.976760 | 1.050382 | -15.156000 | 1773.766727 | -15.156276 |
| 14 | 1.036000 | 0.706904 | 1.035530 | -16.034000 | 1795.047785 | -16.033645 |
