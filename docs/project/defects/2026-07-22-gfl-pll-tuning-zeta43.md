# GFL-RMS10 PLL tuning: kp=9.2/ts^2 + spurious omega_b factor (zeta~43, no oscillatory PLL mode)

- **ID:** SWEEP-2026-07-22-01
- **Status:** RESOLVED_BY_REDUCED6_MODEL (10-state GFL-RMS10 left as-is; reduced 6-state EECON49 model adopts the source-correct PLL)
- **Area:** GFL small-signal PLL synchronization mode
- **Branch/commit/env:** work tree at session 2026-07-22; MATLAB R2025a; SMIB verification via `ibr.smib_sssa_oracle`.

## Symptom (observation)
The GFL-RMS10 SMIB spectrum is entirely real (no complex/oscillatory eigenvalues),
with one extremely fast mode at `-3.371e5 /s` on `delta_PLL`. Domain reviewers
(advisor + MSc) stated a grid-following converter must exhibit an oscillatory
PLL mode; the reference EECON49-P4 team model and the weak-grid literature
(e.g. Adaptive Hybrid GFL-GFM, "PLL-induced instability in weak grids") confirm
a complex PLL mode is expected.

## Reproduction
Run `gfl_rms10_smib` SSSA (or `ibr.gfl_rms10_model` + `ibr.smib_sssa_oracle` at
V=1, P=0.4, Q=0.1, Z=0.02+0.20j). Observed 10 real eigenvalues incl.
`delta_PLL = -3.371e5`, `-46.0`; no imaginary parts.

## Root cause (inference, source-backed)
Two compounding errors in the PLL PI, versus Teodorescu et al. 2011 eq.(4.38):
1. **Transcription:** the source gives `Kp = 2*zeta*wn = 9.2/ts` (ts to the first
   power); the code sets `kp_PLL = 9.2/(ts_pll^2)` (ts squared) -> 10x too large
   at ts_pll=0.1.
2. **Spurious omega_b factor:** the model integrates the angle as
   `d(delta_PLL)/dt = omega_b*(kp*v_q + ki*xi)`, multiplying the PI output by
   omega_b (=377). The EECON49-P4 reference PLL (eq.9-11) adds the PI output to
   omega0 directly in rad/s with NO omega_b multiplier.

The code's `Ti_pll = ts/4.6` is correct and encodes the intended `zeta = 1/sqrt(2)
= 0.707` (Teodorescu example, ts=100 ms). Combined, the two errors inflate the
effective loop gain by ~3770x, driving the damping ratio from the intended 0.707
to ~43.4. An overdamped 2nd-order loop splits into two real poles: the physical
`-46` (slow) and a spurious `-3.371e5` (fast). Analytic 2-state check:
`s^2 + omega_b*kp*|V|*s + omega_b*ki*|V| = 0` -> wn=3994 rad/s, zeta=43.4,
roots {-46.0, -3.468e5} (matches the observed spectrum).

## Falsified hypotheses
- "All-real is correct because it is power electronics / no rotating mass": the
  current/PQ/filter loops are legitimately overdamped (real), but a properly
  tuned SRF-PLL (zeta~0.7) is underdamped -> a complex pair. Retuning `ts_pll`
  cannot fix it (zeta ~ 1/sqrt(ts_pll); zeta=0.7 would need ts_pll~376 s), so the
  formula itself is the defect, not the parameter value.

## Fix
The reduced 6-state EECON49 model `ibr.gfl_reduced6_model` implements the
source-correct PLL: `d(delta_PLL)/dt = kp_PLL*v_q + ki_PLL*xi_PLL` (rad/s, NO
omega_b), with the EECON49-P4 gains `kp_PLL=1.20, ki_PLL=5.00`. This yields an
underdamped complex PLL pair (see verification). The legacy 10-state
`gfl_rms10_model` is retained but is no longer the primary GFL model; its PLL
gain formula was NOT changed under this record (it would alter a separate,
already-committed numerical contract and its tests). If the 10-state model is
kept in service, its `kp_PLL` should be corrected to `9.2/(ts_pll*omega_b)` (or
the omega_b factor removed with `kp_PLL=9.2/ts_pll`) under its own change.

## Verification (reduced6 model)
SMIB SSSA of `gfl_reduced6_model` at V=1, P=0.4, Q=0.1, Z=0.02+0.20j:
`||f0||inf = 2.79e-13`, asymptotically stable (max_real = -0.582), with the
expected **complex PLL pair `-0.582 +/- j2.145` (0.341 Hz, zeta~0.26)**; current
loop `-1306/-1406`, PQ outer `-1.36/-1.43`. Unit test
`test_ibr_gfl_reduced6:test_pll_complex_mode_present` asserts the complex mode;
53/53 targeted tests pass.

## Limitations
Full repository regression not run (targeted only, per session policy). The
legacy 10-state GFL-RMS10 PLL remains mis-tuned by design decision to avoid
touching its committed contract; documented here for traceability.

## Related
- Prior sign defect: [2026-07-21-gfl-rms10-smib-unstable-mode.md](2026-07-21-gfl-rms10-smib-unstable-mode.md) (SWEEP-2026-07-21-01) — fixed the `+3.4e5` saddle (sign); this record explains the residual `-3.4e5` magnitude (tuning).
- Files: `+ibr/gfl_reduced6_model.m`, `+ibr/gfl_rms10_model.m` (lines ~138-141), `tests/test_ibr_gfl_reduced6.m`.
