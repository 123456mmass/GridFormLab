# Kundur Example 12.6 / Table E12.3 model contract

**Scope.** This contract applies to `cases.kundur_ex126_book_case` and the
experimental, in-house `stability.kundur_ex126_book_flux_ssa` path.  Sources
are Kundur pp. 813--815 (Figure E12.8, Example 12.6, Table E12.3) and Kundur
Eq. (3.189) for the supplied saturation coefficients.

## Bases

- Network: 100 MVA, 230 kV, 60 Hz.
- Machine parameters: 900 MVA, 20 kV, 60 Hz.
- Terminal-voltage pu is unchanged because the transformer nominal voltage
  bases match the machine/network bases.
- Convert each machine impedance once: `Xsys = Xmachine*(100/900)`.
- Convert inertia once in the swing equation:
  `Hsys = Hmachine*(900/100)`.
- Saturation flux/voltage arguments are pu voltage quantities, hence are
  unchanged by the MVA conversion.  Example 12.6 specifies no `Kis` current
  parameter; none is inferred from `Asat`.

## Network and dq convention

Generator current is positive from the machine into the network.  With
terminal phasor `V = Vre + j*Vim` and q-axis angle `delta`,

```text
Vd = sin(delta)*Vre - cos(delta)*Vim
Vq = cos(delta)*Vre + sin(delta)*Vim
Id = sin(delta)*Ire - cos(delta)*Iim
Iq = cos(delta)*Ire + sin(delta)*Iim
Ig = (sin(delta)*Id + cos(delta)*Iq)
   + j*(-cos(delta)*Id + sin(delta)*Iq)
```

Thus `Re(V*conj(Ig)) = Vd*Id + Vq*Iq`.  At synchronous speed, electrical
torque equals terminal electrical power plus stator copper loss.

## States and GENTPJ stator interface

Each generator state is

```text
[delta, omega, E'q, E'd, E''q, E''d]
```

and the saturated stator equations are

```text
X''d_sat = Xl + (X''d-Xl)/Satd
X''q_sat = Xl + (X''q-Xl)/Satq
Vd = E''d - Ra*Id + X''q_sat*Iq
Vq = E''q - Ra*Iq - X''d_sat*Id
```

The local nonlinear stator solve is used identically for initialization,
differential equations, network injection, and torque.

## Saturation

Kundur Eq. (3.189), above the knee, is

```text
psi_I  = Asat * exp(Bsat*(psi_at-PsiT1))
Satd   = 1 + psi_I/psi_at
Satq   = 1 + (Xq/Xd)*(Satd-1)
```

Below or at `PsiT1`, `Satd = Satq = 1`.  The air-gap magnitude is

```text
psi_at = hypot(Vq + Ra*Iq + Xl*Id, Vd + Ra*Id - Xl*Iq)
```

No fitted parameters, artificial damping, `D_load`, bus-voltage refinement,
or external power-system solver is permitted.
