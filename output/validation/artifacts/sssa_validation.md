# Phase C SSSA Validation Artifact

**Generated:** 2026-07-12 (FRESH this session — all values computed in this invocation,
no saved metrics replayed as fresh).
**Validated source commit:** `a09830b` (Phase C closure: make Table 9.5 comparison
diagnostic-only). This is the source/tests/docs commit whose behavior the artifact records;
the artifact itself is committed separately in C4 and is NOT a validated source. The
pre-closure validated source commit was `25badd0` (Phase C2); the pre-closure artifact
commit was `dd26bdd`. The closure commit `a09830b` supersedes both as the validated
source: it removes the hidden Table 9.5 acceptance gate, retracts the unsupported FD-noise
causal claim, and corrects the provenance wording.
**MATLAB:** R2026a Update 3.

## Scope

Phase C verifies the production SSSA paths from their equations, NOT from
published/literature acceptance targets:

- Padiyar model 1.1 manual (4 states/machine, 16 states for 4 machines)
- Padiyar model 1.1 AVR (5 states/machine, 20 states)
- Operational EMF6 (6 states/machine, 24 states for Kundur 12.6)

## SSSA call graph (audited)

| Path | DAE source | x order/machine | x count | y order | ref-angle | Jacobian | TS shared |
|---|---|---|---|---|---|---|---|
| Padiyar manual | `padiyar_model11_dae.m` | delta,omega,Eqp,Edp | 16 | Re/Im(V), 2*nb | full (none) | FD by multimachine_ssa | yes |
| Padiyar AVR | same | +Efd | 20 | same | full | FD | yes |
| EMF6 | `synchronous_emf6_ssa.m` (emf6_dae wraps) | delta,omega,Eqp,Edp,Eqpp,Edpp | 24 | Re/Im(V), 2*nb | Afull + Ared (coi) | numerical_jacobian by SSSA | yes |

Input vector `u`: no dynamic input channel. Padiyar `u` = params {H,D,Pm,Efd0/Vref};
EMF6 `u` = params {H_system,D_system,Tm,Efd}. Documented in `docs/SSSA_CONTRACT.md`.

## Equations contract

```
DAE:           xdot = f(x,y,u);   0 = g(x,y,u)
Perturbation:  Δxdot = Jxx Δx + Jxy Δy + Jxu Δu;   0 = Jyx Δx + Jyy Δy + Jyu Δu
Schur:         A = Jxx - Jxy*(Jyy\Jyx)             [backslash, NOT inv(Jyy)]
Eigenproblem:  A v = λ v
Modal:         freq_Hz = |Im(λ)|/(2π);  ζ = -Re(λ)/|λ|;  τ = -1/Re(λ)
```

## 1. Equilibrium residual (fresh run)

| Model | max\|f(x0,y0)\| | max\|g(x0,y0)\| | state count | eigenvalues | all finite |
|---|---|---|---|---|---|
| Padiyar manual | 1.249e-15 | 5.684e-14 | 16 | 16 | yes |
| Padiyar AVR | 9.215e-13 | 5.684e-14 | 20 | 20 | yes |
| EMF6 (Kundur 12.6) | 1.665e-15 | 2.132e-14 | 24 | 24 | yes |

All three satisfy `max|f|, max|g| < 1e-10` at the operating point.

## 2. Shared DAE (SSSA == TS residual)

`test_sssa_contract.test_2a/2b`: SSSA's DAE and a fresh DAE built the way TS builds it
give the SAME residual on the SAME (x,y) — equilibrium AND a perturbed state — to
AbsTol 1e-12. Proves the equations (not just the equilibrium) are one function.

- Padiyar: `padiyar_model11_ssa` and `ts_simulate_padiyar_model11` both consume
  `padiyar_model11_dae`. TS reports `initial_dae_residual == combined DAE residual`.
- EMF6: `synchronous_emf6_ssa` and `emf6_dae` (TS adapter) share the same equations.

## 3. Schur complement contract (fresh run)

`test_sssa_contract.test_3`: `Afull == Jxx - Jxy(:,free_y)*(Jyy(free_y,free_y)\Jyx(free_y,:))`
verified for all three models to AbsTol 1e-12. Dimension contract holds:

| Block | Padiyar manual | Padiyar AVR | EMF6 |
|---|---|---|---|
| Jxx | 16x16 | 20x20 | 24x24 |
| Jxy | 16x20 | 20x20 | 24x40 |
| Jyx | 20x16 | 20x20 | 40x24 |
| Jyy | 20x20 | 20x20 | 40x40 |
| Afull | 16x16 | 20x20 | 24x24 |

`rcond(Jyy)`: Padiyar manual/AVR = 9.74e-3; EMF6 = 1.11e-2 (Jyy well-conditioned,
backslash solve safe).

Schur reconstruction (Padiyar AVR, fresh): `max|Afull - (Jxx - Jxy*(Jyy\Jyx))| = 0`.

## 4. No inv(Jyy) in production

`test_sssa_contract.test_4` grep guard: `+stability/` contains no `inv(Jyy)` or
`inv(J_yy)`. The only `inv`-family call in the SSSA core is `pinv(T)` at
`multimachine_ssa.m:132` (Moore-Penrose pseudoinverse of the COI reduction matrix T,
not an algebraic elimination). Diagnostic probe scripts in `scripts/diagnostics/kundur/`
use `pinv(Jyy)` for comparison only — not production or acceptance code.

## 5. FD convergence study (fresh run)

`test_sssa_fd_convergence`: central-FD Jacobian re-derived independently from the DAE
handles at h = 1e-4, 1e-5, 1e-6, 1e-7. All blocks finite at every h. Physical modes
(|lambda|>0.01) matched between h=1e-5 and h=1e-6 (plateau):

| Model | plateau eigenvalue match (h=1e-5 vs 1e-6) |
|---|---|
| Padiyar manual | 1.686e-07 |
| Padiyar AVR | 5.799e-09 |
| EMF6 | 1.078e-07 |

All three are << 1e-3 (pre-declared tolerance). The default FD steps used in
production (`fd_eps=1e-6` for Padiyar, `3e-6` for EMF6) sit on the plateau — they
were NOT selected to make eigenvalues look good.

## 6. Eigenvalue structure

`test_sssa_contract.test_5`: all eigenvalues finite; complex eigenvalues come in
conjugate pairs (verified for all three models).

## 7. Reference-angle structure (fresh run)

`test_sssa_contract.test_6`: a common rotation of all rotor angles is a symmetry of
the autonomous DAE, so `Afull*shift ~ 0` (zero mode). `angle_shift_residual`:

| Model | angle_shift_residual | tolerance |
|---|---|---|
| Padiyar manual | 7.260e-10 | < 1e-5 |
| Padiyar AVR | 1.355e-06 | < 1e-5 |
| EMF6 | 2.056e-09 | < 1e-5 |

The 1e-5 tolerance covers central-FD Jacobian noise at h~1e-6 (Padiyar AVR's 1.4e-6
is FD truncation, not a structural failure of the zero mode). Padiyar uses
`reduction='none'` (full matrix, zero-mode retained); EMF6 uses `reduction='coi'`
(Afull with zero-mode + Ared COI-reduced).

## 8. Modal metrics

`test_sssa_contract.test_7`: `frequency_Hz` and `damping_ratio` present and finite
for all three models; `time_constant = -1/Re(lambda)` finite for non-zero real parts.

## 9. Reference independence (falsification, fresh run)

`test_sssa_reference_independence`: corrupting `reference.table95_eigenvalues` and
`operating_point.printed_*` to arbitrary/fake values leaves `Afull` and the
eigenvalues unchanged to AbsTol 1e-12 (Padiyar manual, AVR, and EMF6). The
Padiyar SSSA attaches `case_data.reference` to its output for REPORTING only;
the computation is produced entirely by `multimachine_ssa` operating on the DAE.
The PF result (voltage, angle) is likewise invariant to reference corruption.

## 10. Padiyar Table 9.5 — secondary diagnostic cross-check only (fresh run)

Table 9.5 is an external published reference, NOT a numerical acceptance gate. There is no
`verifyLessThan` assertion on the matched eigenvalue distance, and no tolerance such as
`0.06` controls regression pass/fail. The comparison returns finite metrics with
`required_for_acceptance = false`.

18 non-near-zero physical roots matched against computed eigenvalues using a deterministic
global assignment (successive minima over the full distance matrix; no toolbox assignment
solver). The near-zero pair (`|λ| ≤ 0.01`) is excluded by a pre-declared structural rule
because Padiyar attributes it to load-flow/numerical error. The matched indices are unique
(one-to-one), and the sorted absolute-error multiset is invariant to the ordering of either
input (verified by `test_table_9_5_matching_permutation_invariant`). The specific
(ref_idx, computed_idx) pairing is order-dependent when reference eigenvalues are
near-degenerate — a documented limitation of greedy assignment versus a full Hungarian
solver; a toolbox assignment solver is not used.

| book λ | computed λ | abs_err | freq err % | damping err % |
|---|---|---|---|---|
| -39.9893 | -40.0225 | 3.32e-02 | 0.00 | 0.00 |
| -39.4922 | -39.5270 | 3.48e-02 | 0.00 | 0.00 |
| -24.5058±20.6749j | -24.5061±20.72j | 4.30e-02 | 0.21 | 0.09 |
| -25.0383±11.9973j | -25.0384±12.04j | 3.75e-02 | 0.31 | 0.06 |
| -11.5835 | -11.5566 | 2.69e-02 | 0.00 | 0.00 |
| -11.1735 | -11.1485 | 2.50e-02 | 0.00 | 0.00 |
| -0.7594±7.2938j | -0.7553±7.27j | 2.23e-02 | 0.30 | 0.83 |
| -0.7365±6.6899j | -0.7336±6.67j | 2.11e-02 | 0.31 | 0.70 |
| -0.0044±4.4444j | -0.0042±4.43j | 1.21e-02 | 0.27 | 3.79 |
| -4.5727 | -4.5701 | 2.58e-03 | 0.00 | 0.00 |
| -4.4802 | -4.4776 | 2.61e-03 | 0.00 | 0.00 |
| -4.1121 | -4.1095 | 2.65e-03 | 0.00 | 0.00 |
| -4.2449 | -4.2423 | 2.56e-03 | 0.00 | 0.00 |

Maximum matched absolute difference ≈ `4.3e-2` (reported, NOT gated). The FD plateau study
(§5) changes the computed eigenvalues by approximately `1e-7` between `h=1e-5` and `h=1e-6`,
so the observed ~4e-2 reference offset cannot be attributed to FD-step noise. The remaining
difference is unresolved and may reflect model, data, convention, initialization, or
publication-precision differences. No parameter, scale, time constant, saturation, load
model, finite-difference step, or solver tolerance was adjusted to reduce it. This
statement separates observed evidence (the plateau study), possible hypotheses (the listed
sources of difference), and the absence of a proven root cause; no hypothesis is asserted as
fact.

## 11. Manual / AVR excitation equations

- **Manual** (4 states): `Efd(t) = Efd0` (fixed input, `padiyar_model11_dae.m:126`).
  Differential states delta, omega, Eqp, Edp unchanged; terminal V from network
  algebraic equation. `u = {H, D, Pm, Efd0}`.
- **AVR** (5 states): `Efd_dot = (KA*(Vref - |Vt|) - Efd)/TA` (`:133`);
  `Vref = |Vt| + Efd/KA` at initialization (`:110`). `u = {H, D, Pm, Vref}`.

## 12. Test counts (fresh run on C3 = `a09830b`)

| Test file | Passed | Failed | Incomplete |
|---|---|---|---|
| test_emf6_contract.m | 6 | 0 | 0 |
| test_emf6_physics_contract.m | 7 | 0 | 0 |
| test_padiyar_two_area_reference.m | 14 | 0 | 0 |
| test_sssa_contract.m | 10 | 0 | 0 |
| test_sssa_fd_convergence.m | 2 | 0 | 0 |
| test_sssa_reference_independence.m | 5 | 0 | 0 |
| test_no_external_solver_dependency.m | 12 | 0 | 0 |
| test_no_kundur_calibration_claims.m | 3 | 0 | 0 |
| test_no_table95_acceptance_gate.m (NEW) | 3 | 0 | 0 |
| **SSSA targeted total** | **62** | **0** | **0** |
| **Full regression** | **284** | **0** | **0** |

## 13. Phase C gate status

| Gate | Status |
|---|---:|
| PHASE_B_PF_READY | PASS |
| SSSA_CALL_GRAPH_AUDITED | PASS (docs/SSSA_CONTRACT.md) |
| SSSA_SHARED_DAE | PASS |
| SSSA_EQUILIBRIUM_RESIDUAL | PASS |
| SSSA_STATE_ORDER | PASS |
| SSSA_STATE_COUNTS | PASS (manual=16, AVR=20, EMF6=24) |
| SSSA_FD_CONVERGENCE | PASS |
| SSSA_DEFAULT_FD_ON_PLATEAU | PASS |
| SSSA_SCHUR_SOLVE | PASS |
| SSSA_NO_EXPLICIT_INV | PASS |
| SSSA_REFERENCE_ANGLE_STRUCTURE | PASS |
| SSSA_CONJUGATE_PAIR_STRUCTURE | PASS |
| SSSA_MODAL_METRICS | PASS |
| SSSA_REFERENCE_INDEPENDENCE | PASS |
| SSSA_TABLE95_DIAGNOSTIC_COMPUTED | PASS |
| SSSA_TABLE95_NOT_ACCEPTANCE_GATE | PASS |
| SSSA_TABLE95_MATCHING_ORDER_INVARIANT | PASS |
| SSSA_NO_UNSUPPORTED_CAUSAL_CLAIM | PASS |
| SSSA_NO_PARAMETER_TUNING | PASS |
| SSSA_NO_EXTERNAL_SOLVER | PASS |
| ARTIFACT_SOURCE_PROVENANCE | PASS (validated source = a09830b; pre-closure source = 25badd0; pre-closure artifact = dd26bdd) |
| DOCUMENTATION_MATCHES_RUNTIME | PASS (docs/SSSA_CONTRACT.md) |
| TARGETED_TESTS | PASS (62/0/0 on a09830b) |
| FULL_REGRESSION | PASS (284/0/0 on a09830b) |

Padiyar Table 9.5 proximity itself is NOT a required gate. There is no
`TABLE95_MATCH = PASS/FAIL` based on a book tolerance; the matched absolute difference is
reported as a metric (≈ 4.3e-2) only.

**PHASE_C_SSSA_READY = PASS.**

## 14. Commands (reproduce)

```matlab
restoredefaultpath; cd('/home/birds/Documents/Power-flow'); pf_init_paths;

% SSSA targeted
r1 = runtests('tests/test_emf6_contract.m');
r2 = runtests('tests/test_emf6_physics_contract.m');
r3 = runtests('tests/test_padiyar_two_area_reference.m');
r4 = runtests('tests/test_sssa_contract.m');
r5 = runtests('tests/test_sssa_fd_convergence.m');
r6 = runtests('tests/test_sssa_reference_independence.m');

% Guards
r7 = runtests('tests/test_no_external_solver_dependency.m');
r8 = runtests('tests/test_no_kundur_calibration_claims.m');

% Schur reconstruction
da = stability.padiyar_model11_ssa([],struct('excitation','avr','fd_eps',1e-6));
A_recon = da.Jxx - da.Jxy(:,da.free_y)*(da.Jyy(da.free_y,da.free_y)\da.Jyx(da.free_y,:));
max(abs(da.Afull - A_recon),[],'all')   % == 0

% Full regression
r = runtests('tests','IncludeSubfolders',true);
```

## 15. Explicit statements

- All values above are from fresh runs on C3 (`a09830b`) in this session (no saved .mat replayed as fresh).
- No parameter tuning to match PSAT/PGAz/Kundur/Table 9.5.
- No tolerance was relaxed after seeing a result (all tolerances pre-declared).
- No hidden non-convergence (all equilibrium residuals < 1e-10).
- No `inv(Jyy)` in production `+stability/` (grep-guarded).
- No reference eigenvalues drive the SSSA solver (`reference.table95_eigenvalues` is attached for reporting only).
- No hard eigenvalue-distance assertion to Table 9.5 controls regression acceptance (guard: `tests/test_no_table95_acceptance_gate.m`).
- The observed Table 9.5 offset is unresolved and is not attributable to FD-step noise based on the measured plateau study.
- SSSA and TS share the exact same DAE for both Padiyar and EMF6.
- Adaptive TS was NOT started; the TS kernel was NOT modified; the PF solver was NOT modified.
- Repository overall working tree is DIRTY after C4: unrelated user-owned changes (AGENTS.md edits, Padiyar contract doc, IBR plan files, Padiyar report sources) are intentionally preserved and are NOT part of this closure. The closure-scoped files (C3 source/tests/docs + C4 artifact) are committed.
