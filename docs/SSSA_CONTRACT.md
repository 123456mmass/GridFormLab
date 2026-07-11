# SSSA Contract — Small-Signal Stability Analysis

**Validated source commit:** `25badd0` (Phase C2 — SSSA FD convergence and reference
independence tests). The Phase C SSSA validation artifact (`output/validation/artifacts/sssa_validation.md`)
was committed separately in `dd26bdd` as a generated artifact; the artifact is not itself a
validated source. Values in this document are from a fresh run on 2026-07-12 (MATLAB R2026a).
They are reported, not fitted.

## Scope

This contract covers the production SSSA paths in `+stability/`:
- `multicase_sssa.m` (dispatcher)
- `padiyar_model11_ssa.m` / `padiyar_model11_dae.m` (Padiyar model 1.1, manual or AVR)
- `synchronous_emf6_ssa.m` / `emf6_dae.m` (operational sixth-order EMF6)
- `multimachine_ssa.m` (generic Schur-complement linearization core)

The classical path (`classical_sssa.m`) and the Sauer-Pai path are out of scope here.

## 1. DAE and perturbation equations

SSSA linearizes the same DAE used by TS:

```
DAE:            xdot = f(x, y, u) ;   0 = g(x, y, u)
Perturbation:   Δxdot = Jxx Δx + Jxy Δy + Jxu Δu
                0     = Jyx Δx + Jyy Δy + Jyu Δu
```

where `x` = differential states, `y` = algebraic variables (network bus voltages as
`[Re(V); Im(V)]` interleaved per bus), `u` = inputs (see §4).

## 2. Algebraic elimination (Schur complement)

Eliminating `Δy`:

```
Jyy Δy = -Jyx Δx      →   Δy = -(Jyy \ Jyx) Δx
A = Jxx - Jxy * (Jyy \ Jyx)        [backslash, NOT inv(Jyy)]
```

Production path: `multimachine_ssa.m:44`
```matlab
Afull = Jxx - Jxy(:,free_y) * (Jyy(free_y,free_y) \ Jyx(free_y,:));
```
`free_y` selects the retained algebraic variables. `inv(Jyy)` is forbidden in production;
the only `inv`-family call in the SSSA core is `pinv(T)` at `multimachine_ssa.m:132`,
which is the Moore-Penrose pseudoinverse of the (non-square) COI reduction matrix `T`,
not an algebraic elimination. Diagnostic probe scripts in `scripts/diagnostics/kundur/` use
`pinv(Jyy)` for comparison only — they are not production or acceptance code.

### Dimension contract (verified)

| Block | Padiyar manual | Padiyar AVR | EMF6 |
|---|---|---|---|
| Jxx | 16×16 | 20×20 | 24×24 |
| Jxy | 16×20 | 20×20 | 24×40 |
| Jyx | 20×16 | 20×20 | 40×24 |
| Jyy | 20×20 | 20×20 | 40×40 |
| Afull | 16×16 | 20×20 | 24×24 |

Schur reconstruction check (Padiyar AVR, fresh run): `max|Afull - (Jxx - Jxy*(Jyy\Jyx))| = 0`
to machine precision. The reduced matrix `Ared` (COI) is returned only when
`reduction='coi'`.

## 3. Eigenproblem and modal metrics

```
A v = λ v
frequency_Hz = |Im(λ)| / (2π)
damping_ratio ζ = -Re(λ) / |λ|          (ζ>0 stable)
time_constant τ = -1 / Re(λ)             (s; Re(λ)<0 ⇒ decaying)
```

The reference-angle zero mode: a common rotation of all rotor angles is a symmetry of the
autonomous DAE (no infinite bus / no governor), so `Afull * shift ≈ 0` where `shift` has
1 in every machine's angle state and 0 elsewhere. This is reported as
`angle_shift_residual = norm(Afull*shift, inf)`.

| Model | reference-angle treatment | angle_shift_residual (fresh) |
|---|---|---|
| Padiyar manual | full matrix (`reduction='none'`) | 7.3e-10 |
| Padiyar AVR | full matrix (`reduction='none'`) | 1.4e-6 |
| EMF6 | Afull + Ared (`reduction='coi'`) | 2.1e-9 |

`rcond(Jyy)` (fresh): Padiyar manual/AVR = 9.7e-3; EMF6 = 1.1e-2. Jyy is well-conditioned
(non-singular); the backslash solve is safe.

## 4. Call graph and state order (per model)

### 4.1 Padiyar manual (4 states/machine, 16 states for 4 machines)

- DAE source: `padiyar_model11_dae.m` — `differential_residual` (L121),
  `network_residual` (L138), `all_currents` (L175).
- State order per machine: `[delta, omega, Eqp, Edp]` (L103-104).
- Algebraic `y`: `[Re(V_b); Im(V_b)]` interleaved, `2*nb` (L81-84).
- Input `u` (parameters, NOT a dynamic input channel): `{H, D, Pm, Efd0}`.
- Manual excitation: `Efd(t) = Efd0` (fixed input, `padiyar_model11_dae.m:126`).
  The synchronous-machine differential equations (delta, omega, Eqp, Edp) are unchanged;
  terminal voltage comes from the network algebraic equation.
- Jacobian: finite-differenced by `multimachine_ssa` (no precomputed blocks passed).
- TS shared: yes — `ts_simulate_padiyar_model11` calls the same `padiyar_model11_dae`.

### 4.2 Padiyar AVR (5 states/machine, 20 states for 4 machines)

- Same DAE source. State order per machine: `[delta, omega, Eqp, Edp, Efd]` (L103-107).
- AVR state equation: `Efd_dot = (KA*(Vref - |Vt|) - Efd)/TA` (`padiyar_model11_dae.m:133`).
- AVR reference at equilibrium: `Vref = |Vt| + Efd/KA` (L110), so the printed operating
  point is an equilibrium.
- Input `u`: `{H, D, Pm, Vref}`.
- TS shared: yes.

### 4.3 EMF6 (6 states/machine)

- DAE source: `synchronous_emf6_ssa.m` — `differential_residual` (L152),
  `network_residual` (L167). `emf6_dae.m` is a thin adapter that wraps the SSSA.
- State order per machine: `[delta, omega, Eqp, Edp, Eqpp, Edpp]` (L136, L138-141).
- Algebraic `y`: `[Re(V_b); Im(V_b)]`, `2*nb` (L109).
- Input `u` (parameters): `{H_system, D_system, Tm, Efd}`.
- Jacobian: computed by the SSSA itself via `numerical_jacobian` (L216) and passed
  precomputed to `multimachine_ssa`.
- TS shared: yes — `ts_simulate_emf6` calls `emf6_dae` → `synchronous_emf6_ssa`.

### 4.4 Input vector note

There is no external dynamic input channel `u(t)` in the SSSA sense. The `u` struct holds
constant per-machine data (inertia, damping, mechanical power, field voltage / AVR
reference). `init.Pm` and `init.Efd0` (manual) / `init.Vref` (AVR) are equilibrium
constants baked into `f`. This is documented so that `Jxu`/`Jyu` are not misread as
time-varying input sensitivities.

## 5. Equilibrium residual (verified, fresh run)

| Model | max\|f(x0,y0)\| | max\|g(x0,y0)\| | state count | eigenvalues | all finite |
|---|---|---|---|---|---|
| Padiyar manual | 1.2e-15 | 5.7e-14 | 16 | 16 | yes |
| Padiyar AVR | 9.2e-13 | 5.7e-14 | 20 | 20 | yes |
| EMF6 (Kundur 12.6) | 1.7e-15 | 2.1e-14 | 24 | 24 | yes |

All three models satisfy `max|f|, max|g| < 1e-10` at the operating point.

## 6. Padiyar Table 9.5 handling — secondary cross-check only

Padiyar Table 9.5 eigenvalues (`+cases/case_padiyar_two_area_4m_avr.m:96`) are attached to
the case as a **published comparison copy**. They are NEVER read by the SSSA computation:
`padiyar_model11_ssa.m:17` attaches `case_data.reference` to the output for reporting only.
The computed `Afull` and `eigenvalues` are produced entirely by `multimachine_ssa`
operating on the DAE — they do not depend on `reference.table95_eigenvalues` or any
`printed_*` field.

This is enforced by the falsification test `test_reference_eigenvalues_do_not_drive_sssa`
in `tests/test_padiyar_two_area_reference.m`: corrupting `table95_eigenvalues` to
arbitrary values leaves `Afull` and the eigenvalues unchanged to `AbsTol 1e-12`.

Table 9.5 is used ONLY as a secondary diagnostic cross-check
(`test_table_9_5_diagnostic_comparison`). The 18 non-near-zero physical roots are matched
against the computed eigenvalues with a deterministic global assignment (successive minima
over the full distance matrix, no toolbox assignment solver); the near-zero pair
(`|λ| ≤ 0.01`) is excluded by a pre-declared structural rule because Padiyar attributes it
to load-flow/numerical error. The comparison returns finite metrics (absolute/relative
errors, matched indices, unmatched modes, reference provenance) with
`required_for_acceptance = false`.

Table 9.5 is NOT a numerical acceptance gate. There is no `verifyLessThan` assertion on the
matched eigenvalue distance to the book, and no tolerance such as `0.06` controls regression
pass/fail. The observed maximum matched absolute difference is approximately `4.3e-2`
(reported, not gated). The FD plateau study changes the computed eigenvalues by approximately
`1e-7` between `h=1e-5` and `h=1e-6`, so the observed reference offset cannot be attributed
to FD-step noise. The remaining difference is unresolved and may reflect model, data,
convention, initialization, or publication-precision differences. No parameter, scale, time
constant, saturation, load model, finite-difference step, or solver tolerance was adjusted to
reduce it.

## 7. No-calibration / no-literature-acceptance

- Kundur Table E12.3 is reference/case-study data only, never a numerical acceptance target
  (enforced by `tests/test_no_kundur_calibration_claims.m`).
- `inv(Jyy)` is absent from production `+stability/` (grep guard in
  `tests/test_sssa_contract.m`).
- SSSA and TS share the exact same DAE functions for both Padiyar and EMF6 — no duplicated
  machine equations.

## 8. Known minor duplications (documented, not in acceptance scope)

1. Two near-identical central finite-difference Jacobian implementations exist:
   `numerical_jacobian` inside `synchronous_emf6_ssa.m:216` and `finite_difference_jacobian`
   inside `multimachine_ssa.m:79`. Same algorithm, two copies. Not a correctness issue.
2. `synchronous_emf6_ssa.m` serves as both "the EMF6 DAE" and "the EMF6 SSSA driver"
   (the machine equations live inside it). This is an architectural asymmetry with the
   Padiyar path (which has a standalone `padiyar_model11_dae.m`), not an equation
   duplication — TS reaches the same equations via `emf6_dae` → `synchronous_emf6_ssa`.

## 9. Reproduce

```matlab
restoredefaultpath; cd('/home/birds/Documents/Power-flow'); pf_init_paths;

% Padiyar manual / AVR
dm = stability.padiyar_model11_ssa([],struct('excitation','manual','fd_eps',1e-6));
da = stability.padiyar_model11_ssa([],struct('excitation','avr','fd_eps',1e-6));

% EMF6 (Kundur 12.6)
c  = cases.kundur_ex126_book_case();
se = stability.synchronous_emf6_ssa(c, struct('load_model','cc_p_cz_q'));

% Schur reconstruction
A_recon = da.Jxx - da.Jxy(:,da.free_y)*(da.Jyy(da.free_y,da.free_y)\da.Jyx(da.free_y,:));
max(abs(da.Afull - A_recon),[],'all')   % == 0
```
