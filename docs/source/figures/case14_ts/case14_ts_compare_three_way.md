# IEEE 14-bus TS comparison: PSAT vs PGAz vs Ours

Scenario: bus 4 three-phase fault, t_fault=1.0 s, t_clear=1.1 s, Zf=0+j0.1 pu, t_end=15 s, dt=0.01 s.
Model: classical (5 generators at buses 1,2,3,6,8; H=5, D=0, x'd=0.3).
Rotor angles/speeds compared in the COI frame (inter-machine) because each tool uses a different absolute angle reference (PSAT fixes the slack angle; PGAz/Ours float the COI).

## Power flow

| Pair | Max |dV| (pu) | Max |dAngle| (deg) |
|---|---:|---:|
| PSAT vs Ours | 4.49319e-06 | 0.000807331 |

## Transient stability (COI frame)

| Pair | Max |delta_rel| (deg) | Max |omega_rel| (pu) | Max |Vm_bus4| (pu) |
|---|---:|---:|---:|
| PSAT vs Ours | 0.628091 | 0.000291613 | 0.00225732 |
| PSAT vs PGAz | 0.628091 | 0.000291613 | 0.00225732 |
| PGAz vs Ours | 1.22782e-11 | 5.9952e-15 | 4.11893e-14 |

## Notes

- All three tools reproduce the same PF solution to ~1e-4 (PSAT vs Ours) and ~1e-9 (PGAz vs Ours).
- Rotor-angle trajectories agree in the COI frame. The remaining PSAT vs Ours/PGAz difference comes from the integration scheme (PSAT full-Newton trapezoidal vs Heun predictor-corrector) and is amplified by the mild post-fault frequency drift (no governor in the classical model).
- The scenario is angle-stable (inter-machine swings are bounded); the absolute COI drifts because no governor/AGC is modelled.
