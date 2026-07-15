# IEEE14 IBR GFL provenance — WECC REGC_A/REEC_A

Status: `SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES`.

This document supersedes the former Ding-derived six-state GFL profile as the
canonical runtime contract. `IEEE14_IBR_GFL_PHASE5_PROVENANCE.md` remains a
historical record only; its `Kps/Kis` model is not on the production path.

## Primary sources

- WECC, *Specification of the Second Generation Generic Models for Wind
  Turbine Generators*, 23 January 2014, Sections 3.2-3.3 and Appendices A-B:
  <https://www.wecc.org/sites/default/files/documents/meeting/2024/WECC-Second-Generation-Wind-Turbine-Model%20Spec-012314.pdf>
  (`SHA-256 aef13405133f110351eeb341ffb4c674af5b498bd7881a936c03521e3584caea`)
- WECC, *Wind Plant Dynamic Modeling Guidelines*, REGC_A/REEC_A guidance:
  <https://www.wecc.org/sites/default/files/documents/meeting/2024/WECC%20Wind%20Plant%20Dynamic%20Modeling%20Guidelines.pdf>
  (`SHA-256 077f6c8e295a7e5914f962981bb3782d3ae6575d6e929e227bb7131f0883f94d`)
- WECC, *Converting REEC_B to REEC_A for Solar PV Generators*, Table 2
  example parameters:
  <https://www.wecc.org/sites/default/files/documents/meeting/2024/Converting%20REEC_B%20to%20REEC_A%20for%20Solar%20PV%20Generators.pdf>
  (`SHA-256 a6fe566afec39b22368d1227d8b6145ee7d4350d1ae5dd100d415d2e4381c10c`)

The source documents are referenced by URL and are not production
dependencies. The project implementation is base MATLAB and does not load an
external model or solved trajectory.

## Implemented control option and state order

The selected IEEE14 option is constant P/Q REEC_A (`PFflag=0`, `QFlag=0`),
P-priority current limiting (`PQFlag=1`), and REGC_A converter-current
dynamics. Flag selection is `CASE_DEFINED`; the REGC_A/REEC_A blocks are
`SOURCE_DEFINED`; their explicit ODE realization and fixed state order are
`SOURCE_TRANSFORMED`.

| Index | State | Unit/base | Governing block |
|---:|---|---|---|
| 1 | `Vt_f` | pu voltage | REEC_A terminal-voltage filter |
| 2 | `P_f` | pu inverter base | REEC_A electrical-power filter |
| 3 | `Iq_cmd_f` | pu inverter-base current | REEC_A reactive-current command lag |
| 4 | `Pord` | pu inverter-base power | REEC_A active-power order/rate limiter |
| 5 | `Vlvpl_f` | pu voltage | REGC_A LVPL voltage filter |
| 6 | `Ip_reg` | pu inverter-base current | REGC_A active-current lag |
| 7 | `Iq_reg` | pu inverter-base current | REGC_A reactive-current lag |

There is no PLL state in this WECC model. Network-frame current aligns
algebraically with the terminal-voltage angle. Consequently, the dual-mode
20-state ABI shares no artificial GFL/GFM state.

## Bases, frame, and sign

Let `kappa=Sbase/Mbase`. REEC_A/REGC_A power and current states use inverter
base. Composite inputs and outputs use system base:

```text
P_inv = kappa*P_sys
Q_inv = kappa*Q_sys
I_sys = (Ip - j*Iq)*exp(j*angle(V))/kappa
S_sys = V*conj(I_sys)
```

Positive `P` and `Q` are injections into the network. This convention matches
the composite residual `g=YV-Iinj`.

## Source-mapped parameters and limits

The defaults are frozen before results. REGC_A typical values come from the
WECC specification; REEC_A values use the official conversion example where
applicable. `Vdip=0.90` and the constant-P/Q/P-priority flag combination are
CASE_DEFINED selections within the documented WECC ranges/options. They are
not fitted to IEEE14 results.

The implemented limit path includes:

- voltage-dip reactive-current injection with deadband and `Kqv`;
- P/Q-priority circular current allocation using `Imax`;
- active-power order magnitude and rate limits;
- REGC_A LVPL and low-voltage active-current management;
- high-voltage reactive-current management; and
- fail-closed equilibrium `Pmin/Pmax` and total-current checks.

REGC_A is a strong-grid current-source model. The selector therefore applies
the frozen CASE_DEFINED applicability rule `SCR>3`; `SCR<=3` is rejected.
The in-repo SCR metric uses the network Ybus with the REF source shorted,
`Zth` from a linear solve (`\`, never `inv`/`pinv`), and explicit resource
`Mbase`. Excluding load admittance and SG subtransient reactance from this SCR
metric is a documented `PROJECT_DERIVED` simplification, not a source claim.

## Initialization and equilibrium

For finite `V`, `Psys`, and `Qsys`:

```text
Pinv = kappa*Psys
Qinv = kappa*Qsys
Ip   = Pinv/abs(V)
Iq   = Qinv/abs(V)
xeq  = [abs(V); Pinv; Iq; Pinv; abs(V); Ip; Iq]
```

Initialization fails closed if power is outside `[Pmin,Pmax]` or
`hypot(Ip,Iq)>Imax`. At a valid point every seven-state derivative is zero and
the terminal complex power equals the requested system-base P/Q.

## Numerical and failure contract

`max(Vt_f,0.01)` is the declared `NUMERICAL_METHOD` guard for current-command
division at zero voltage. It is not a tuning parameter. Invalid mapping,
state/input size, non-finite values, invalid parameter ordering, zero network
voltage, equilibrium power violation, and equilibrium current violation all
fail closed with stable `ibr:wecc_regca_reeca_model:*` identifiers.

## Falsification evidence

`tests/test_ibr_gfl_model.m` independently checks the 7-state ABI, system/
inverter-base identity, global-angle rotation, P- and Q-priority oracles,
voltage-dip reactive injection, LVPL, low/high-voltage current management,
parameter/mapping failures, and absence of the former unsourced `Kps/Kis`
path. Selector/SCR and physical GFL↔GFM transfer tests are separate integration
gates. A passing isolated model test does not by itself establish production
readiness.
