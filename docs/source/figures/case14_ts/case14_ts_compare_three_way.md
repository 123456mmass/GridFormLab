# IEEE 14-bus TS comparison: PSAT vs Ours

Scenario: bus 4 three-phase fault, t_fault=1.0 s, t_clear=1.1 s, Zf=0+j0.1 pu, t_end=15 s, dt=0.01 s.
Model: classical (5 generators at buses 1,2,3,6,8; H=5, D=0, x'd=0.3).
PSAT results regenerated FRESH this session (run_psat_case14); PSAT is reference-only. PGAz not available -> two-way.

## Power flow

| Pair | Max |dV| (pu) | Max |dAngle| (deg) |
|---|---:|---:|
| PSAT vs Ours | 6.66134e-16 | 3.55271e-14 |

## Transient stability (COI frame)

| Pair | Max |delta_rel| (deg) | Max |omega_rel| (pu) | Max |Pe| (MW) | Max |Vm_bus4| (pu) |
|---|---:|---:|---:|---:|
| PSAT vs Ours | 0.00957113 | 3.81603e-06 | 0.0421714 | 3.17926e-05 |

## Notes

- Ours: production adaptive/event-aware implicit trapezoidal corrector (non-converged steps = 0/1500). PSAT: converged trapezoidal Newton (TD pts=1509).
- Rotor angles/speeds compared in the COI frame; electrical power and fault-bus voltage retain physical references.
