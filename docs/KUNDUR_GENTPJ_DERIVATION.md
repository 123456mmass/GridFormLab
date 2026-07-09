# Kundur Example 12.6 GENTPJ realization

This document defines the equations used by the experimental
`kundur_ex126_book_flux_ssa` path.  It is a derivation/contract, not an
eigenvalue fit.  All reactances below are on one common base.

## 1. Flux reconstruction

Let

```text
ad = (X'd-X''d)/(Xd-X''d)
aq = (X'q-X''q)/(Xq-X''q)
```

For the d axis,

```text
Eq2 = (E''q-E'q + Id*(X'd-X''d))/ad
Eq1 = E''q + Id*(Xd-X''d) - Eq2
```

and for the q axis,

```text
Ed2 = (E''d-E'd - Iq*(X'q-X''q))/aq
Ed1 = E''d - Iq*(Xq-X''q) - Ed2
```

The rotor equations are

```text
T'd0  dE'q/dt  = Efd - Satd*Eq1
T''d0 dE''q/dt =      - Satd*ad*Eq2
T'q0  dE'd/dt  =      - Satq*Ed1
T''q0 dE''d/dt =      - Satq*aq*Ed2
```

With `Satd=Satq=1`, expansion gives

```text
T'd0  dE'q/dt  = Efd + E''q*(Xd-X'd)/(X'd-X''d)
                       - E'q*(Xd-X''d)/(X'd-X''d)
T''d0 dE''q/dt = E'q - E''q - Id*(X'd-X''d)
T'q0  dE'd/dt  = E''d*(Xq-X'q)/(X'q-X''q)
                       - E'd*(Xq-X''q)/(X'q-X''q)
T''q0 dE''d/dt = E'd - E''d + Iq*(X'q-X''q)
```

which is the unsaturated E'/E'' realization used by the legacy diagnostic.

## 2. Saturation

Kundur Eq. (3.189), shown in the book solution to Example 3.3, defines the
saturation-flux component above the knee as

```text
psi_I = Asat*exp(Bsat*(psi_at-PsiT1)).
```

For Example 12.6, the printed coefficients are
`Asat=0.015`, `Bsat=9.6`, and `PsiT1=0.9`.  The printed data do **not** give a
GENTPJ `Kis` parameter; `Asat` is therefore the curve coefficient, not a
current-sensitivity coefficient.

The total GENTPJ multipliers are

```text
Satd = 1 + psi_I/psi_at
Satq = 1 + (Xq/Xd)*(Satd-1).
```

At or below the knee, `psi_I=0` and `Satd=Satq=1`.  The air-gap argument uses
only quantities on the common voltage base:

```text
psi_at = hypot(Vq + Ra*Iq + Xl*Id, Vd + Ra*Id - Xl*Iq).
```

## 3. Saturated stator interface and torque

The saturated subtransient reactances are

```text
X''d_sat = Xl + (X''d-Xl)/Satd
X''q_sat = Xl + (X''q-Xl)/Satq.
```

With generator current positive into the network,

```text
Vd = E''d - Ra*Id + X''q_sat*Iq
Vq = E''q - Ra*Iq - X''d_sat*Id.
```

These two nonlinear equations are solved locally for `(Id,Iq)` while the
network voltage is held fixed.  Define

```text
psi_d = E''q - X''d_sat*Id
psi_q = -E''d - X''q_sat*Iq.
```

Then `Te = psi_d*Iq - psi_q*Id`, equivalently

```text
Te = E''d*Id + E''q*Iq - (X''d_sat-X''q_sat)*Id*Iq.
```

## 4. PF-preserving steady-state initialization

The verified PF supplies terminal `V` and generator current `I`.  Since the
magnitude of `psi_at` is invariant to dq rotation, `Satd` and `Satq` are
known directly.  The rotor angle is obtained from the saturated q-axis
steady-state relation

```text
Vd + Ra*Id - Xq_sat*Iq = 0,
Xq_sat = Xl + (Xq-Xl)/Satq.
```

Then

```text
E''q = Vq + Ra*Iq + X''d_sat*Id
E''d = Vd + Ra*Id - X''q_sat*Iq
E'q  = E''q + Id*(X'd-X''d)/Satd
E'd  = E''d - Iq*(X'q-X''q)/Satq
Efd  = Satd*E''q + Id*(Xd-X''d).
```

Substitution makes all four rotor derivatives zero algebraically.  Finally
`Tm=Te` is evaluated from the same local stator solution.  No bus voltage,
generator P/Q, or PF state is refined after the PF solve.
