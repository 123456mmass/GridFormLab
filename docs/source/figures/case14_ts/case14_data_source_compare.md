# Case14 data-source comparison

Important: PSAT built-in `d_014_dyn_mdl.m` is not identical to PGAz/MATPOWER `case14_mp_test.m`.

| Source | Lines | Dynamic generators | Notes |
|---|---:|---:|---|
| PGAz `case14_mp_test.m` | 20 | 0 dynamic Syn; 5 classical Gen rows for pgaz_ts | MATPOWER/PGAz static case used by our imported case14 |
| PSAT `d_014_dyn_mdl.m` | 20 | 5 Syn | Different loads/line data/dynamic parameters; not directly comparable to PGAz case14 TS |
| Added PSAT `d_case14_mp_test_mdl.m` | 20 | 0 | Static clone of PGAz/MATPOWER case14; dynamic Syn still needed for PSAT TS |

## Load comparison

| Bus | PGAz Pd | PSAT d014 Pd | Added PSAT Pd | PGAz Qd | PSAT d014 Qd | Added PSAT Qd |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| 2 | 21.7000 | 30.3800 | 21.7000 | 12.7000 | 17.7800 | 12.7000 |
| 3 | 94.2000 | 131.8800 | 94.2000 | 19.0000 | 26.6000 | 19.0000 |
| 4 | 47.8000 | 66.9200 | 47.8000 | -3.9000 | 5.6000 | -3.9000 |
| 5 | 7.6000 | 10.6400 | 7.6000 | 1.6000 | 2.2400 | 1.6000 |
| 6 | 11.2000 | 15.6800 | 11.2000 | 7.5000 | 10.5000 | 7.5000 |
| 7 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| 8 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |
| 9 | 29.5000 | 41.3000 | 29.5000 | 16.6000 | 23.2400 | 16.6000 |
| 10 | 9.0000 | 12.6000 | 9.0000 | 5.8000 | 8.1200 | 5.8000 |
| 11 | 3.5000 | 4.9000 | 3.5000 | 1.8000 | 2.5200 | 1.8000 |
| 12 | 6.1000 | 8.5400 | 6.1000 | 1.6000 | 2.2400 | 1.6000 |
| 13 | 13.5000 | 18.9000 | 13.5000 | 5.8000 | 8.1200 | 5.8000 |
| 14 | 14.9000 | 20.8600 | 14.9000 | 5.0000 | 7.0000 | 5.0000 |

Files saved in C:\Users\User\Desktop\IBR\Power-flow\docs\source\figures\case14_ts
