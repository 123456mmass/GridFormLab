# Padiyar two-area model contract

## Scope

This contract covers the 4-machine, 10-bus two-area case in K. R. Padiyar,
*Power System Dynamics: Stability and Control*, second edition, Section 9.6.1,
Tables 9.1--9.5 (PDF pages 338--344; printed pages 325--331).

The production case is `cases.case_padiyar_two_area_4m_avr`.

## Source hierarchy

1. Tables 9.1--9.4 define network, operating point, machine and AVR inputs.
2. The model-1.1 equations in Chapters 6 and 9 define the dynamic model.
3. Table 9.5 is a secondary published cross-check, not a value to fit.

No subtransient parameters are inferred. Kundur Table E12.3 is not used.

## Model order

Each generator has five states:

```text
[delta, omega, E'q, E'd, Efd]
```

This is Padiyar model 1.1 (two-axis transient machine) plus a
single-time-constant AVR. Four generators give 20 states before any reference
reduction.

## Bases and signs

- Network and printed machine parameters: 100 MVA base.
- Frequency: 60 Hz, used as `omega_B=2*pi*f`. The cited pages omit an
  explicit frequency row; 60 Hz is confirmed by reproduction of all three
  published swing-mode imaginary parts from the otherwise fixed input data.
- Generator current is positive from the machine into the network.
- Complex power injection is `S=V*conj(I)`; positive P/Q means injection.
- `delta` is electrical radians and `omega` is per-unit absolute speed.
- Loads are constant impedances during dynamic analysis.

## Dynamic equations

For each generator:

```text
delta_dot = omega_B*(omega-1)
omega_dot = (Pm-Pe-D*(omega-1))/(2H)
E'q_dot   = (Efd-E'q-(Xd-X'd)*Id)/T'd0
E'd_dot   = (-E'd+(Xq-X'q)*Iq)/T'q0
Efd_dot   = (KA*(Vref-|Vt|)-Efd)/TA
```

The AVR reference is derived during initialization so the printed operating
point is an equilibrium:

```text
Vref = |Vt| + Efd/KA
```

The stator algebraic equations use one documented dq/current convention in
initialization, runtime, torque, current injection, SSSA and TS. Direct
electrical air-gap power includes stator copper loss consistently.

## Numerical gates

- In-house Newton PF must converge.
- PF values are compared with Table 9.2 and discrepancies are reported.
- Dynamic initialization must satisfy both f and g residuals.
- SSSA and TS must use the same DAE functions.
- No-fault TS must have zero non-converged steps and bounded numerical drift.
- Table 9.5 comparisons are reported without parameter tuning.
- Full repository regression must remain passing.
