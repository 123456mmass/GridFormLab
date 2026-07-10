# IEEE 14-bus TS comparison: PSAT vs PGAz vs Ours

Scenario: bus 4 three-phase fault, t_fault=1.0 s, t_clear=1.1 s, Zf=0+j0.1 pu, t_end=15 s, dt=0.01 s.
Model: classical (5 generators at buses 1,2,3,6,8; H=5, D=0, x'd=0.3).
Rotor angles/speeds compared in the COI frame (inter-machine) because each tool uses a different absolute angle reference (PSAT fixes the slack angle; PGAz/Ours float the COI).

## Power flow

| Pair | Max |dV| (pu) | Max |dAngle| (deg) |
|---|---:|---:|
| PSAT vs Ours | 4.49319e-06 | 0.000807331 |
| PSAT vs PGAz | 4.49319e-06 | 0.000807331 |
| PGAz vs Ours | 1.55431e-15 | 1.06581e-13 |

## Transient stability (COI frame)

| Pair | Max |delta_rel| (deg) | Max |omega_rel| (pu) | Max |Pe| (MW) | Max |Vm_bus4| (pu) |
|---|---:|---:|---:|---:|
| PSAT vs Ours | 0.0195881 | 7.5429e-06 | 0.0749563 | 5.40275e-05 |
| PSAT vs PGAz | 0.628091 | 0.000291613 | 2.45949 | 0.00225732 |
| PGAz vs Ours | 0.614315 | 0.000291642 | 2.44121 | 0.00226426 |

## Notes

- Ours uses the production adaptive/event-aware implicit trapezoidal corrector; PSAT uses its converged trapezoidal Newton iteration; PGAz uses three fixed predictor-corrector iterations.
- Rotor-angle trajectories are compared in the COI frame, while electrical power and fault-bus voltage retain their physical references.
- The scenario is angle-stable (inter-machine swings are bounded); the absolute COI drifts because no governor/AGC is modelled.
