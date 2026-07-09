# Kundur Example 12.6 / Table E12.3 reproduction memory (2026-07-10)

## Goal
Reproduce all 24 Kundur Example 12.6 / Table E12.3 eigenvalues with published
parameters and `<0.5%` error, using an in-house MATLAB model only.

## Current status: Stage 0–6 complete; Stage 7 root cause identified

### Stages passed
- **Stage 0**: Source manifest, raw case (`+cases/kundur_ex126_book_case.m`),
  contract (`docs/KUNDUR_E123_MODEL_CONTRACT.md`), derivation
  (`docs/KUNDUR_GENTPJ_DERIVATION.md`).  3 manifest tests pass.
- **Stage 1**: Base/sign/state contracts.  dq roundtrip, base conversion,
  power/torque identity tests pass (`test_kundur_book_contract.m`).
- **Stage 2**: Standalone case from book data only.
- **Stage 3**: GENTPJ machine derivation documented and implemented.
  Unsaturated limit matches legacy `kundur_ex126_kundur_ssa` exactly
  (`||Aflux - Alegacy||_F < 1e-8`).
- **Stage 4**: Equilibrium passes from PF directly, no fsolve/Newton:
  `||f|| = 4.75e-15`, `||g|| = 4.35e-10`, `newton_iterations = 0`.
- **Stage 5**: Jacobian plateau stable at `fd_eps = 3e-6`
  (`docs/probes/probe_kundur_book_fd_plateau.m`).
  Structural checks: `rank(A)=23`, `rank(A²)=22`, `||A*v_angle|| < 1e-8`.
- **Stage 6**: Family matcher implemented
  (`+stability/kundur_e123_family_compare.m`,
  `+stability/kundur_e123_reference.m`).  24 rows classified correctly.

### Calibration quarantine
- `kundur_ex126_book_e123_ssa.m` is quarantined as calibrated diagnostic.
- Removed from `dynamic_accuracy_benchmark_catalog.m`.
- `test_kundur_e123_book.m` renamed `test_kundur_e123_calibrated_diagnostic.m`.
- `test_no_kundur_calibration_claims.m` enforces no accepted path calls it.

### Full test suite: 74/74 pass

---

## Root cause of eigenvalue discrepancy (Stage 7, item 7)

### Finding: PSAT Model 6 uses `gd`/`gq` corrections absent from GENTPJ

PSAT's 6th-order model (`@SYclass/fcall.m`, `ord==6`) uses:

```text
gd = (X''d/X'd) * (T''d0/T'd0) * (Xd - X'd)
gq = (X''q/X'q) * (T''q0/T'q0) * (Xq - X'q)

dE'q/dt  = (-E'q - (Xd-X'd)*Id + Vf) / T'd0
dE'd/dt  = (-E'd + (Xq-X'q)*Iq) / T'q0
dE''q/dt = (-E''q + E'q - (X'd-X''d+gd)*Id) / T''d0
dE''d/dt = (-E''d + E'd + (X'q-X''q+gq)*Iq) / T''q0
```

Our GENTPJ model uses (without saturation):

```text
dE'q/dt  = (Efd + c_d*E''q - d_d*E'q) / T'd0
dE'd/dt  = (c_q*E''d - d_q*E'd) / T'q0
dE''q/dt = (E'q - E''q - Id*(X'd-X''d)) / T''d0
dE''d/dt = (E'd - E''d + Iq*(X'q-X''q)) / T''q0
```

The subtransient equations differ by `gd*Id/T''d0` and `gq*Iq/T''q0`.

### Numerical impact

With Kundur parameters:
- `gd = (0.25/0.3)*(0.03/8.0)*(1.8-0.3) = 0.00469` (small, ~2% of X'd-X''d)
- `gq = (0.25/0.55)*(0.05/0.4)*(1.7-0.55) = 0.0653` (significant, ~22% of X'q-X''q)

The `gq` correction is large and directly affects the q-axis damper modes,
which are the most discrepant family (12–26% error).

### PSAT saturation

PSAT's `synsat.m` uses a quadratic saturation function on `E'q` with
parameters from `Syn.con` columns 25–26.  In the Kundur case these are **0**,
so PSAT runs **without saturation** in the differential equations.
Saturation only affects the operating-point initialization.

### Current eigenvalue comparison (saturated GENTPJ, cc_p_cz_q)

| Family | Computed | Book E12.3 | Real error |
|---|---|---|---|
| Interarea | -0.108+j3.442 | -0.111+j3.43 | 2.9% |
| Local 1 | -0.558+j6.873 | -0.492+j6.82 | 13.3% |
| Local 2 | -0.565+j7.067 | -0.506+j7.02 | 11.6% |
| Field | -0.19, -0.20 | -0.265, -0.276 | 26–28% |
| q-damper | -2.5, -3.4, -4.6, -4.7 | -3.4, -4.1, -5.3, -5.3 | 12–26% |
| d-damper real | -34, -36, -39, -40 | -31, -32, -34, -36 | 0.2–24% |
| d-damper pairs | -42±j0.22, -42±j0.11 | -38±j0.14, -38±j0.04 | 10–180% |

Frequencies are within 1% for all oscillatory modes.  The damping (real parts)
is systematically off, consistent with the missing `gd`/`gq` corrections.

### Load model effect (probe)

CC-P vs CZ-P both give similar q-damper and field errors.  CZ makes interarea
worse (28% vs 3%).  The load model is not the root cause.

### Stator saturation effect (probe)

GENTPJ saturated stator vs unsaturated stator: small shift (~0.004 in real
part).  Not the root cause.

---

## CRITICAL: PSAT also does NOT reproduce Table E12.3

PSAT Model 6 eigenvalues were computed by running PSAT 2.1.11 on the
Kundur case (`d_kundur1_mdl`, `sssa` routine).  Results:

| Mode | PSAT | Ours | Book E12.3 |
|---|---|---|---|
| Interarea | -0.127±j3.13 (0.50 Hz) | -0.108±j3.44 (0.55 Hz) | -0.111±j3.43 (0.55 Hz) |
| Local 1 | -0.519±j6.17 (0.98 Hz) | -0.558±j6.87 (1.09 Hz) | -0.492±j6.82 (1.09 Hz) |
| Local 2 | -0.510±j6.00 (0.95 Hz) | -0.565±j7.07 (1.12 Hz) | -0.506±j7.02 (1.12 Hz) |
| Field | -0.179, -0.172 | -0.19, -0.20 | -0.265, -0.276 |
| q-damper | -3.5, -4.4, -5.9, -5.9 | -2.5, -3.4, -4.6, -4.7 | -3.4, -4.1, -5.3, -5.3 |
| Zero | 0, 0, **+0.012** | ±0.00006 | -0.00076±j0.0022 |

Key observations:
- PSAT has an **unstable eigenvalue** (+0.012) — worse than ours.
- PSAT frequencies are **lower** than both the book and ours.
- **Our frequencies are closer to the book** than PSAT's.
- The `gd`/`gq` corrections in PSAT do NOT fix the discrepancy.
- No modern tool (PSAT, PSS/E, PacDyn, Dynaω) reproduces Table E12.3.

Conclusion: the `gd`/`gq` path is NOT the answer.  Kundur likely used a
model or parameter set that differs from what is published.  The
investigation must continue from the book's own equations, not from any
third-party tool.

## Next steps

1. Study the Kundur book's own state-space formulation (Chapter 12,
   Section 12.6–12.8) for the exact linearization procedure used.
2. Check if Kundur used the incremental saturation factor (Ksd_incr) in the
   linearized equations, not the total factor.
3. Investigate whether the book used a different load model Jacobian for the
   CC-P load (e.g., constant phasor vs angle-following current).
4. Consider whether the book's published parameters are on a different base
   or use different definitions (e.g., T'd0 vs T'd).
5. Do NOT follow PSAT's model equations — they don't reproduce the table.

---

## Key files

- Active solver: `+stability/kundur_ex126_book_flux_ssa.m`
- Raw case: `+cases/kundur_ex126_book_case.m`
- Contract: `docs/KUNDUR_E123_MODEL_CONTRACT.md`
- Derivation: `docs/KUNDUR_GENTPJ_DERIVATION.md`
- Family matcher: `+stability/kundur_e123_family_compare.m`
- Reference targets: `+stability/kundur_e123_reference.m`
- dq helpers: `+stability/kundur_book_dq.m`, `+stability/kundur_book_network_current.m`
- Probes: `docs/probes/probe_kundur_book_fd_plateau.m`,
  `docs/probes/probe_stator_saturation_effect.m`,
  `docs/probes/probe_load_model_effect.m`
- Tests: `test_kundur_book_input_manifest.m`, `test_kundur_book_contract.m`,
  `test_kundur_book_flux_path.m`, `test_kundur_e123_family_compare.m`,
  `test_no_kundur_calibration_claims.m`, `test_kundur_e123_calibrated_diagnostic.m`
- Legacy diagnostic: `+stability/kundur_ex126_kundur_ssa.m`
- Calibrated (quarantined): `+stability/kundur_ex126_book_e123_ssa.m`
- PSAT reference: `~/Downloads/psat-2.1.11-mat/psat/@SYclass/fcall.m` (model 6)

## PSAT Kundur case data notes
- PSAT uses bus 3 (G3) as slack, not bus 1 (G1).
- PSAT H field = 13/12.35 = 2×H_book (M = 2H convention).
- PSAT saturation params (Syn.con cols 25–26) = 0 → no saturation in DEs.
- PSAT Taa (Syn.con col 24) = 0.
- PSAT load model: Pl.con with ZIP parameters; active load is constant-current.
