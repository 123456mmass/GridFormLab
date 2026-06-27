# Plan — 6th-Order Multi-Machine Small-Signal Stability Model

## 1. Goal
Replace the hard-coded Kundur Table E12.3 reproduction with a **genuine
6th-order synchronous-machine small-signal stability analysis (SSSA)** for the
Kundur two-area four-machine system. The model must:
- Start from the in-house power-flow solution (`+cases/case_kundur_two_area_classical`).
- Use only project code and MATLAB base built-ins (no Pandapower, MATPOWER, etc.).
- Produce 24 eigenvalues that can be compared with Kundur Table E12.3.
- Add a **rotor-angle-difference GUI plot** for visualising interarea and local
  oscillations.

## 2. Theoretical background (presentation-ready)

### 2.1 Synchronous machine sixth-order model
Each generator uses the classical sixth-order subtransient model with states:

```
x_i = [ δ_i,  ω_i,  E'_{qi},  E'_{di},  E''_{qi},  E''_{di} ]^T
```

Differential equations (using Kundur-style notation and manual/constant
excitation, so `E_{fd}` is constant):

```
δ̇_i = ω_i − ω_s                                          (1)
ω̇_i = (1 / 2H_i) [ T_{m,i} − T_{e,i} − D_i (ω_i − ω_s) ]  (2)

Ė'_{qi} = (1 / T'_{d0i}) [ E_{fd,i} − E'_{qi} − (X_{di} − X'_{di}) I_{di} ]   (3)
Ė'_{di} = (1 / T'_{q0i}) [ −E'_{di} + (X_{qi} − X'_{qi}) I_{qi} ]             (4)

Ė''_{qi} = (1 / T''_{d0i}) [ E'_{qi} − E''_{qi} − (X'_{di} − X''_{di}) I_{di} ] (5)
Ė''_{di} = (1 / T''_{q0i}) [ E'_{di} − E''_{di} + (X'_{qi} − X''_{qi}) I_{qi} ] (6)
```

### 2.2 Stator algebraic equations
In the machine dq reference frame (d-axis aligned with rotor angle δ_i):

```
V_{di} = E''_{di} + R_{ai} I_{di} − X''_{qi} I_{qi}      (7)
V_{qi} = E''_{qi} + R_{ai} I_{qi} + X''_{di} I_{di}      (8)

T_{e,i} = V_{di} I_{di} + V_{qi} I_{qi}                  (9)
```

Transformation between network frame (rectangular phasor) and machine dq frame:

```
[ V_d ]   [  sin δ   −cos δ ] [ V_Re ]
[ V_q ] = [  cos δ    sin δ ] [ V_Im ]

[ I_d ]   [  sin δ   −cos δ ] [ I_Re ]
[ I_q ] = [  cos δ    sin δ ] [ I_Im ]
```

### 2.3 Network algebraic equations
The network is represented by the bus admittance matrix `Ybus` obtained from the
power-flow solution. Loads are modelled as **constant impedance** at the
operating point:

```
Y_{load,k} = (P_k − j Q_k) / |V_k|^2
```

For each generator bus, the injected current into the network is:

```
I_k = (V_k − E''_k) / (R_a + j X''_k)
```

Wait — better approach: the machine is represented by a **subtransient voltage
source behind subtransient impedance**:

```
E''_k = V_k − (R_a + j X''_k) I_k
```

Then the network equation for all buses becomes:

```
I_bus = Ybus_reduced · V_bus
```

where `Ybus_reduced` includes the equivalent machine subtransient admittances at
the internal nodes. This is the **classical network reduction** used in many
SSSA implementations.

### 2.4 DAE and linearization
Overall we have a DAE system:

```
ẋ = f(x, y)         (differential: 24 states)
0  = g(x, y)         (algebraic: network voltages/currents)
```

Linearise about the operating point (power-flow solution):

```
[ Δẋ ]   [ A  B ] [ Δx ]
[ 0  ] = [ C  D ] [ Δy ]
```

Eliminate algebraic variables Δy:

```
A_sys = A − B · (D \ C)
```

Eigenvalues of `A_sys` give the small-signal modes.

### 2.5 Expected result
For the Kundur two-area system with 4 machines × 6 states, we expect 24
eigenvalues matching Table E12.3, including:
- Two near-zero rotor-angle/frequency modes (modes 1,2).
- Three rotor-angle oscillation modes: interarea (~0.55 Hz), Area 1 local
  (~1.09 Hz), Area 2 local (~1.12 Hz).
- Field-flux modes (~−0.1 to −0.3).
- Damper-flux modes (~−3 to −38).

## 3. Implementation steps

### Step 1 — Machine data
Add complete machine parameters to the Kundur case file:
- `H`, `D`, `R_a`
- `X_d`, `X'_d`, `X''_d`
- `X_q`, `X'_q`, `X''_q`
- `T'_{d0}`, `T''_{d0}`, `T'_{q0}`, `T''_{q0}`
- `E_fd` (constant for manual excitation)

Reference values are taken from Kundur Example 12.6 tables.

### Step 2 — Initial condition from power flow
After power flow converges, for each generator:
- Compute terminal voltage phasor `V_t = V_k ∠θ_k`.
- Compute terminal current `I_t = (S_t / V_t)*`.
- Transform to dq frame using initial δ (initially set equal to terminal angle).
- Solve steady-state field voltage `E_fd` and initial `E'_{q}, E'_{d}, E''_{q}, E''_{d}`.
- Iterate rotor angle δ so that q-axis aligns with `E'_{q}` axis or another chosen
  reference (many conventions exist).

### Step 3 — Build 6th-order state-space
Create `+stability/kundur_ex126_sixth_order_ssa.m` that:
- Reads power-flow result.
- Forms reduced Ybus with machine subtransient admittances.
- Computes DAE Jacobian numerically (analytical partial derivatives preferred).
- Returns reduced `A_sys`, eigenvalues, right eigenvectors (for mode shapes).

### Step 4 — Validation
Compare computed eigenvalues against `+stability/kundur_ex126_classical_analysis.m`
(Table E12.3). Compute frequency/damping errors and print a summary.

### Step 5 — GUI enhancement
Add a panel/figure to `+pfapp` for **rotor angle difference**:
- Show a small transient simulation of selected modes.
- Plot δ_G1, δ_G2, δ_G3, δ_G4 with option for average Area 1 vs Area 2 angle.
- Hook into the existing SMIB Stability tab or create a new Multi-Machine SSA tab.

### Step 6 — Documentation for presentation
Create a concise theory summary (this plan) plus:
- Equation list for whiteboard explanation.
- One-page validation table (computed vs Kundur).
- One-page guide on which file does what (so the user can walk an examiner
  through the code).

## 4. Deliverables
- `+stability/kundur_ex126_sixth_order_ssa.m`
- Updated `+cases/case_kundur_two_area_classical.m` with full machine data
- New GUI component: `+pfapp/run_sixth_order_ssa_action.m` or added to existing
  SMIB result display
- `docs/source/figures/kundur_ex126/sixth_order_eigenvalues.png`
- `PLAN_6TH_ORDER_SSA.md` (this file)
- Short `PRESENTATION_GUIDE.md` with talking points

## 5. Coding constraints
- Only MATLAB base functions.
- No `powerlib`, MATPOWER, Pandapower, PSS/E, etc.
- All derivatives are either analytical or computed by finite-difference using
  project code.
- Linear solver: manual Gaussian elimination or MATLAB backslash (`\`) on a
  small dense matrix is acceptable because it is a base built-in.

## 6. First action
Start Step 1 and Step 2: collect machine parameters and implement the initial
condition calculation from the converged power-flow solution.
