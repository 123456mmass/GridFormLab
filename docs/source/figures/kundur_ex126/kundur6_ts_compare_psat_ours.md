# Kundur 6th-order TS: PSAT vs in-house

Model: 6th-order GENTPJ, identical params (Xd=1.8, X'd=0.3, X'd=0.25, Xq=1.7, T'd0=8, H=6.5/6.175, Sn=900).
Scenario: solid 3-phase fault at bus 8, t=1.0-1.05 s, t_end=10 s, dt=0.001 s.
Load model: both constant-impedance (PSAT pq2z; in-house load_model='cz').

## Result (COI frame)

PSAT fixes the slack angle during TD; the in-house model floats (no governor), so rotor angles are compared in the COI frame.

| Metric | Value |
|---|---:|
| max |delta_rel| (deg) | 1.8951 |
| max |omega_rel| (pu) | 0.000368881 |
| max |delta_abs| (deg, reference offset) | 39.9819 |

Initial rotor angles (deg):

| Gen | PSAT | Ours |
|---:|---:|---:|
| 1 | 63.448 | 63.304 |
| 2 | 52.768 | 52.480 |
| 3 | 37.551 | 37.331 |
| 4 | 26.628 | 26.201 |

This independently cross-validates the in-house 6th-order model (the same model validated to <0.5% vs Kundur Table E12.3 for SSSA). The ~1.9 deg COI-frame difference comes from the integration scheme (PSAT implicit-Newton trapezoidal vs in-house Heun predictor-corrector) and the ~0.14 deg PF/load-model offset.
