# Kundur Example 12.6 / Table E12.3 — clean reconstruction plan

## Purpose and non-negotiable acceptance rule

Reconstruct the *manual-excitation* model of Kundur Example 12.6 from the
book data, and reproduce the 24 Table E12.3 roots with a physical,
in-house MATLAB model.  This plan replaces parameter fitting and does **not**
permit copying state matrices, roots, equations, or architecture from PSAT,
PSS/E, PowerWorld, or other programs.

**Acceptance:** every non-redundant root must meet the advisor's component,
frequency, and damping target of `<0.5%`, using the published parameters.
The two redundant roots must first be proven structurally as the expected
size-two zero-mode Jordan chain.  They must then be compared to the printed
Table E12.3 numerical values by an explicitly documented *absolute* tolerance:
relative percent error is mathematically undefined at zero.  They may not be
replaced by copied table values, artificial damping, a frequency-dependent
load, or an infinite-bus reference.

No stage can be skipped.  A stage that fails leaves the previous baseline
untouched and produces a diagnostic only; it never becomes the benchmark path.

---

## 0. Freeze the evidence and remove invalid baselines

### Book source of truth

Use only:

- `docs/Power System Stability and Control - Prabha Kundur (PowerEn.ir).pdf`
- Book pp. 813–816, corresponding to the PDF images:
  - `docs/source/tmp_check/kundur_p-0835.png` — Figure E12.8, machine,
    transformer, line, operating-point, and saturation data
  - `docs/source/tmp_check/kundur_p-0836.png` — load characteristics and
    manual-excitation instruction
  - `docs/source/tmp_check/kundur_p-0837.png` — Table E12.3
  - `docs/source/tmp_check/kundur_p-0838.png` — rotor-mode interpretation

The input manifest must contain the following unrounded values:

| Item | Value |
|---|---:|
| System base | 100 MVA, 230 kV, 60 Hz |
| Machine base | 900 MVA, 20 kV |
| `Xd, Xq, Xl` | 1.8, 1.7, 0.2 |
| `Xd', Xq'` | 0.3, 0.55 |
| `Xd'', Xq''` | 0.25, 0.25 |
| `Ra` | 0.0025 |
| `T'd0, T''d0, T'q0, T''q0` | 8.0, 0.03, 0.4, 0.05 s |
| `H(G1,G2), H(G3,G4)` | 6.5, 6.175 s |
| `KD` | 0 |
| `Asat, Bsat, PsiT1` | 0.015, 9.6, 0.9 |
| Active load | constant current |
| Reactive load | constant impedance |
| Excitation and torque | constant `Efd`, constant `Tm`; no governor |

### Required cleanup

1. Keep `+stability/kundur_ex126_kundur_ssa.m` as the **legacy diagnostic**
   only.  It must not be called `book`, `exact`, `validated`, or used for the
   Table E12.3 accuracy claim.
2. Keep `+stability/kundur_ex126_book_e123_ssa.m` quarantined until it is
   deleted or renamed `*_calibrated_diagnostic`; its effective scales are not
   physical input data.
3. Do not modify reports, catalog pass/fail status, or public claims until the
   final gate passes.
4. `D_load` is prohibited.  It has been removed from the active legacy path.
5. Every experiment must use a distinct `docs/probes/` file or a new solver
   path.  Do not overwrite a passing baseline to try an equation.

### Gate 0 tests

- `tests/test_kundur_book_input_manifest.m`: exact values above, topology,
  load model, and Table E12.3 target transcription.
- `tests/test_no_kundur_calibration_claims.m`: no benchmark test/wrapper may
  call `kundur_ex126_book_e123_ssa`.
- repository search test: no `D_load` in the book reconstruction path.

---

## 1. Establish coordinate, base, sign, and state contracts before coding

Write `docs/KUNDUR_E123_MODEL_CONTRACT.md`.  It is a one-page mathematical
contract that all code and tests follow.

### 1.1 Per-unit contract

- Network quantities use 100-MVA/230-kV base.
- Machine operational reactances, time constants, and saturation quantities
  are on 900-MVA/20-kV base.
- Because transformer nominal ratios match the voltage bases, voltage pu is
  unchanged through the base conversion.
- Convert impedance from machine to system base only once:
  `Xsys = Xmachine*(100/900)`.
- Convert machine inertia to system-base swing-equation inertia only once:
  `Hsys = Hmachine*(900/100)`.
- Currents used in a saturation law must use the base specified by that law;
  this must be an explicit named conversion, never an implicit factor.

### 1.2 dq and current convention

Specify in one place:

```text
Vd = sin(delta)*Vre - cos(delta)*Vim
Vq = cos(delta)*Vre + sin(delta)*Vim
Ig_network = (sin(delta)*Id + cos(delta)*Iq)
           + j*(-cos(delta)*Id + sin(delta)*Iq)
```

Generator current is positive **from the machine into the network**.  The
stator equations, torque equation, current injection, initialization, and all
Jacobian checks must use this same convention.

### 1.3 State contract

The new solver has exactly six states per machine:

```text
[delta, omega, E'q, E'd, E''q, E''d]
```

These are not merely labels: the implementation reconstructs the underlying
GENTPJ rotor-flux components `Eq1, Eq2, Ed1, Ed2` on every RHS evaluation.
The reconstruction is documented algebraically, including inverse mappings.

### Gate 1 tests

1. `test_kundur_base_conversion.m`
   - verifies all transformed reactances, `Hsys`, and current-base factors;
   - fails if an MVA conversion is applied twice.
2. `test_kundur_dq_roundtrip.m`
   - dq -> network -> dq recovers voltage/current to `<1e-13` for random
     angles and phasors.
3. `test_kundur_stator_power_identity.m`
   - verifies `Re(V*conj(Ig)) == Vd*Id + Vq*Iq`;
   - verifies torque equals terminal power plus stator copper loss under the
     documented convention.

---

## 2. Implement a stand-alone, raw Example 12.6 case definition

Create `+cases/kundur_ex126_book_case.m`; do not call the legacy Kundur case
function.  It contains only printed data, not dynamics or fitted values.

### Required contents

1. Eleven buses, four generators, two shunt capacitors, and all twelve
   branches from Figure E12.8.
2. Transformer `j0.15 pu` on 900 MVA converted once to 100 MVA.
3. Line values `r=0.0001`, `x=0.001`, `bc=0.00175 pu/km`, with each charging
   value represented as `bc*length/2` at each end.
4. Bus 7: `PL=967 MW`, `QL=100 MVAr`, `QC=200 MVAr`; bus 9:
   `PL=1767 MW`, `QL=100 MVAr`, `QC=350 MVAr`.
5. Four printed terminal operating points and the 400-MW area export.
6. Immutable metadata identifying page/table/image sources for every group.

### Gate 2 tests

- branch/bus count and endpoint tests;
- transformer and double-circuit tie-line tests;
- Ybus symmetry and passive-network sign test;
- power-flow reproduction of all four printed terminal voltage magnitudes and
  angles; report mismatches before proceeding;
- bus-wise active/reactive balance at the power-flow point `<1e-10 pu`.

---

## 3. Derive the machine realization on paper, then implement it in isolation

Create `docs/KUNDUR_GENTPJ_DERIVATION.md` before changing a solver.  Each code
line in the machine RHS must cite an equation number in this derivation.

### 3.1 Unsaturated consistency derivation

For the d axis define

```text
ad = (X'd-X''d)/(Xd-X''d)
Eq2 = (E''q-E'q + Id*(X'd-X''d))/ad
Eq1 = E''q + Id*(Xd-X''d) - Eq2
```

and for the q axis define

```text
aq = (X'q-X''q)/(Xq-X''q)
Ed2 = (E''d-E'd - Iq*(X'q-X''q))/aq
Ed1 = E''d - Iq*(Xq-X''q) - Ed2
```

The flux equations are

```text
T'd0  dE'q/dt  = Efd - Satd*Eq1
T''d0 dE''q/dt =       - Satd*ad*Eq2
T'q0  dE'd/dt  =       - Satq*Ed1
T''q0 dE''d/dt =       - Satq*aq*Ed2
```

When `Satd=Satq=1`, algebraic expansion **must exactly recover** the
unsaturated GENTPJ E'/E'' equations.  This is a symbolic hand derivation and
also a numerical identity test over random states/currents.

### 3.2 Saturation derivation and decision gate

Do not guess the saturation curve.  Resolve from the Kundur model definition:

- exact argument of the saturation curve;
- exact role of `Asat`, `Bsat`, and `PsiT1`;
- whether `Asat` is a current contribution or a curve coefficient;
- units/base of every saturation argument;
- definitions of `Satd`, `Satq`, and the saturated subtransient reactances.

The candidate stator interface is only accepted after the source derivation
confirms it:

```text
X''d_sat = Xl + (X''d-Xl)/Satd
X''q_sat = Xl + (X''q-Xl)/Satq
Vd = E''d - Ra*Id + X''q_sat*Iq
Vq = E''q - Ra*Iq - X''d_sat*Id
```

If the book/source supports a different convention, replace the contract and
write the derivation first.  Do not select whichever formula gives a better
root match.

### 3.3 Unit-machine tests (no network)

Create `+stability/private/kundur_book_machine_rhs.m` and
`kundur_book_stator_current.m`.  Unit-test them separately from the DAE.

Required tests:

1. unsaturated flux-vs-EMF RHS identity over at least 100 deterministic
   pseudo-random valid samples;
2. stator residual `<1e-12` after solving `(Id,Iq)`;
3. saturation disabled gives exactly `Satd=Satq=1`;
4. below-knee saturation is continuous and equals one;
5. at-knee left/right finite-difference derivatives are documented;
6. positive saturation reduces only the specified magnetizing part of the
   subtransient reactance and leaves `Xl` unchanged;
7. field/rotor steady-state equations are zero for independently constructed
   terminal `V`, `I`, `Efd` data;
8. no NaN/Inf for low voltage, zero current, or near-knee values.

---

## 4. Solve the operating point consistently with the new machine model

The PF establishes terminal `V` and specified generator P/Q.  The dynamic
initialization must then calculate `delta`, `Id/Iq`, `E'`, `E''`, `Efd`, and
`Tm` from the **same new equations**.

### Procedure

1. Initialize terminal phasors from the standalone case PF.
2. Solve each machine's two stator equations and rotor steady-state equations
   as a small local nonlinear solve.  Do not use a global, underdetermined
   least-squares problem to hide an incorrect initialization.
3. Set `Tm=Te` only after current, torque, and copper loss use the same base.
4. Assemble the complete DAE residual.
5. If necessary, refine only physically free variables with a square
   gauge-fixed Newton system.  Fix one absolute angle *or* impose a COI
   constraint, never both redundantly.
6. Store residual components by state, machine, and bus; a scalar norm alone
   is not accepted.

### Gate 4 acceptance

```text
max(abs(f)) < 1e-10 pu/s
max(abs(g)) < 1e-10 pu current
max(abs(Tm-Te)) < 1e-10 pu
```

and each individual machine rotor/stator residual must pass.  Failure blocks
linearization.

---

## 5. Linearize the DAE with numerical-convergence evidence

Use the existing in-house `stability.multimachine_ssa` Schur-complement engine,
but supply Jacobians from the new book-flux model only.

### Jacobian method

1. Start with central differences.
2. Compute `A(h)` at `h = 1e-4, 3e-5, 1e-5, 3e-6, 1e-6, 3e-7` with
   state-aware perturbation scaling.
3. Require all non-reference mode families to converge between adjacent
   accepted steps; choose the plateau value, not an arbitrary `1e-6`.
4. Independently check selected Jacobian columns against complex-step only if
   the relevant residual has been made analytic for that test; otherwise do
   not misuse complex-step through `abs`, `max`, or branch logic.
5. Check `rcond(Jyy)` and use a documented linear solve.  No explicit inverse.

### DAE structural checks

- `A*v_angle ~= 0` must be below tolerance, where `v_angle` increments all
  four rotor angles equally.
- With `KD=0`, verify `rank(A)=23` and `rank(A^2)=22` at a predeclared,
  step-convergence-supported tolerance: this is the Kundur double zero
  Jordan chain, not an unstable physical pair.
- Verify covariance by rotating every rotor angle and every network phasor by
  the same small angle before eliminating algebraics.
- COI reduction is diagnostic only: compare Table E12.3 with the 24-state
  full realization, and use the 22-state COI realization to inspect the
  physical modes.

### Gate 5 acceptance

- residual gate from Stage 4 remains satisfied;
- no mode-family changes across the chosen finite-difference plateau;
- no positive non-reference mode larger than the numerical uncertainty;
- all structural checks pass.

---

## 6. Compare the full spectrum without discontinuous nearest-root matching

Create `+stability/kundur_e123_reference.m`, containing the exact Table E12.3
values and dominant-state labels:

```text
1,2   -0.76e-3 +/- j0.22e-2
3     -0.096
4,5   -0.111 +/- j3.43
6     -0.117
7     -0.265
8     -0.276
9,10  -0.492 +/- j6.82
11,12 -0.506 +/- j7.02
13..16 -3.428, -4.139, -5.287, -5.303
17..20 -31.03, -32.45, -34.07, -35.53
21,22 -37.89 +/- j0.142
23,24 -38.01 +/- j0.038
```

### Family matcher

The comparator must:

1. classify conjugate pairs first;
2. identify the three rotor pairs using frequency bands and participation in
   `[delta,omega]` states;
3. identify field and amortisseur groups from state participation, not solely
   sorted real part;
4. use one-to-one assignment only within a fixed physical family;
5. report root real part, imaginary part, frequency, damping ratio,
   participation, component errors, and family membership;
6. fail clearly if a family has the wrong root count, rather than silently
   matching a different root.

### Reference-pair handling

The two printed near-zero values are reported separately from ordinary
relative error.  Report:

- `||A*v_angle||`;
- nullity of `A` and `A^2`;
- zero-Jordan residual;
- full eig result at each accepted finite-difference step;
- absolute distance to `-0.00076 +/- j0.0022`.

Only call this pair reproduced after the numerical-method sensitivity is
explained and the predeclared absolute criterion passes.  Do not inject the
printed pair.

---

## 7. Debug protocol if a family fails

Change **one** documented item per experiment, in this exact order:

1. operating-point/base/sign invariant;
2. machine state mapping and unsaturated-equivalence unit test;
3. saturation-law source interpretation;
4. saturated stator interface;
5. Jacobian step plateau;
6. network representation (line charging, shunts, and load current Jacobian);
7. only then investigate published-model ambiguity.

For every experiment record:

```text
commit/file hash
one changed assumption
residual max(f), max(g)
Jacobian step
full 24 roots
family comparison
pass/fail decision
```

Never change `H`, reactances, time constants, line R, load model, or damping
as a fitting parameter.  A discrepancy is evidence about the derivation, not
a license to tune published data.

---

## 8. Final acceptance and reporting gate

Before changing any report/table/catalog:

1. run `runtests('tests')` on a plain MATLAB installation;
2. run the new Kundur-specific suite twice in fresh MATLAB processes;
3. store the raw computed 24 roots and all matching diagnostics;
4. verify no path calls a prohibited external solver/toolbox;
5. compare against Table E12.3 with the family matcher;
6. obtain a reviewer-facing table with every row marked pass/fail;
7. only if every row passes the defined criterion, update benchmark catalog
   and report language.

If any row fails, the report must say `in progress` and retain the actual
computed root.  No calibrated wrapper may appear as an in-house reproduction.

---

## Current implementation position (2026-07-10)

- Stage 0: partial.  `D_load` has been removed; legacy calibration wrapper is
  still present and must remain quarantined.
- Stage 1: partial.  Existing tests cover dq/zero mode only; model contract
  has not yet been written.
- Stage 3: started.  `+stability/kundur_ex126_book_flux_ssa.m` is a separate
  flux-equation path.  Its unsaturated limit agrees with the legacy E'/E''
  formulation, and its equilibrium residual passes.  Its saturation law and
  saturated stator interface are **not accepted yet**, so it is diagnostic,
  not a benchmark result.
- Stages 2, 4–8: not complete.
