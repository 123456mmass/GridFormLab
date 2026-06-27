# Presentation Guide — 6th-Order Multi-Machine Small-Signal Stability

This guide summarises the theory, the code, and the talking points so the
work can be presented to an examiner. It accompanies
`PLAN_6TH_ORDER_SSA.md` and the source files listed in Section 6.

## 1. What the study does
- Solves the **power flow** of the Kundur two-area four-machine system
  (Example 12.6) with the project's own Newton–Raphson solver.
- Builds a **6th-order synchronous-machine model** for each of the four
  generators and forms a 24-state linearised model.
- Computes the **eigenvalues** of the reduced state matrix and compares
  them with Kundur Table E12.3 (manual excitation / classical case).
- (In progress) Adds a **rotor-angle-difference plot** and a
  **fault time-domain simulation** to the GUI and the report.

## 2. Generator model — sixth order
Each generator is described by six state variables:

| State | Symbol | Meaning |
|-------|--------|---------|
| 1 | δ | rotor angle (rad) |
| 2 | ω | rotor speed deviation (pu) |
| 3 | E'_q | q-axis transient EMF |
| 4 | E'_d | d-axis transient EMF |
| 5 | E''_q | q-axis subtransient EMF |
| 6 | E''_d | d-axis subtransient EMF |

Differential equations (Kundur notation, current convention: out of machine):

```
δ̇ = ω·ω0
ω̇ = (Tm − Te − D·ω) / (2H)

Ė'_q = (E_fd − E'_q − (X_d − X'_d)·I_d) / T'_d0
Ė'_d = (−E'_d + (X_q − X'_q)·I_q) / T'_q0

Ė''_q = (E'_q − E''_q − (X'_d − X''_d)·I_d) / T''_d0
Ė''_d = (E'_d − E''_d + (X'_q − X''_q)·I_q) / T''_q0
```

Stator algebraic equations (network pu):

```
V_d = E''_d + R_a·I_d − X''_q·I_q
V_q = E''_q + R_a·I_q + X''_d·I_d
T_e = V_q·I_q + V_d·I_d
```

Machine parameters used (per unit on 900 MVA, 20 kV base):

| Quantity | Value |
|----------|-------|
| X_d | 1.8 |
| X'_d | 0.3 |
| X''_d | 0.25 |
| X_q | 1.7 |
| X'_q | 0.55 |
| X''_q | 0.25 |
| R_a | 0.0025 |
| X_l | 0.2 |
| T'_d0 | 8.0 s |
| T''_d0 | 0.03 s |
| T'_q0 | 0.4 s |
| T''_q0 | 0.05 s |
| H (G1,G2) | 6.5 s |
| H (G3,G4) | 6.175 s |
| D | 0 |

## 3. Network model
- Y_bus is built from the line data and shunt capacitors of
  `+cases/case_kundur_two_area_classical.m`.
- Loads are converted to **constant-impedance** equivalents at the
  operating point: `Y_load = (P − jQ)/|V|²`.
- Generator stators inject current into the network according to the
  subtransient equations above (no separate Norton branch in Y_bus —
  the injection is computed explicitly in the DAE residual `g`).

## 4. Linearisation and reduction
The combined DAE is

```
ẋ = f(x, y)      (24 differential equations)
0 = g(x, y)      (2·nb algebraic network equations)
```

Linearising about the operating point (x₀, y₀):

```
[ Δẋ ]   [ J_xx  J_xy ] [ Δx ]
[ 0  ] = [ J_yx  J_yy ] [ Δy ]
```

The reduced state matrix (eliminating the algebraic variables) is

```
A_red = J_xx − J_xy · (J_yy \ J_yx)
```

Eigenvalues of `A_red` are the small-signal modes.

## 5. Operating point computation
1. Run Newton–Raphson power flow → bus voltages `y₀`.
2. For each generator compute terminal phasor `V_t` and current `I_t`
   from the power-flow result.
3. Initialise rotor angle δ from the "voltage behind synchronous
   reactance" angle `angle(V_t + (R_a + jX_d)·I_t)`.
4. Compute initial E'_q, E'_d, E''_q, E''_d from the stator equations.
5. Run a **Newton refinement** of the full DAE residual `[f; g]` so that
   both the differential and the algebraic equations are satisfied at
   the operating point. The slack-bus angle is held fixed as the angular
   reference to keep the Jacobian non-singular.

## 6. Source files (walk-through for the examiner)

| File | Role |
|------|------|
| `+cases/case_kundur_two_area_classical.m` | Power-flow data + 6th-order machine parameters |
| `+pfsolver/powerflow_newton_raphson.m` | In-house Newton–Raphson solver |
| `+stability/kundur_ex126_sixth_order_ssa.m` | Build and linearise the 6th-order DAE |
| `+stability/kundur_ex126_classical_analysis.m` | Kundur Table E12.3 reference values |
| `generate_kundur_ex126_report.m` | Generate report figures and tables |
| `PLAN_6TH_ORDER_SSA.md` | Theory + implementation roadmap |
| `CODING_RULES.md` | No-toolbox dependency policy |

## 7. Talking points (3-minute pitch)
1. "We solved the Kundur Example 12.6 power flow with our own Newton–Raphson
   solver — no MATPOWER, no Power System Toolbox."
2. "Each generator is a 6th-order subtransient model; the four machines give
   a 24-state linearised system."
3. "We linearise the differential-algebraic equations and reduce the state
   matrix with a Schur complement, then take eigenvalues."
4. "The eigenvalues are compared side-by-side with Kundur Table E12.3."
5. "All code is project-owned; the only external call is `xelatex` for the
   PDF report (documented in `CODING_RULES.md`)."

## 8. Current limitations (be honest with the examiner)
- The Newton refinement currently converges to ~1e-3 (not machine precision)
  because the angle-reference state introduces a near-zero eigenvalue.
  Fixing one rotor angle as reference (COI frame) will remove this.
- The d-axis damper-flux eigenvalues do not yet match Kundur's -3 to -5 and
  -31 to -38 clusters exactly; the interarea and local swing frequencies
  are reproduced in the right order of magnitude.
- Fault time-domain simulation and the rotor-angle-difference GUI panel are
  the next milestones.

## 9. How to run
```matlab
addpath(pwd);
r = stability.kundur_ex126_sixth_order_ssa();
r.eigenvalues        % 24 eigenvalues
r.frequency_Hz       % oscillation frequencies
r.damping_ratio      % damping ratios
r.reference_summary  % comparison vs Kundur Table E12.3
```
