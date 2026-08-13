# Washout corner placed on the island swing mode destabilised the all-GFM island

Date: 2026-08-13
Status: RESOLVED (design basis corrected; `D_t` returned to 0 on measured evidence)
Defect ID: `MODEL-2026-08-13-02`

## Symptom

With the decoupled GFM at its first production values
(`R_droop = 0.05`, `w_D = 3.0 rad/s`, `D_t = 20.0`, `M = 0.08`), the production
chronology never reached the SG trip:

```text
t = 1.000  stability:gfm_selection:candidateNotReady
           "Matched sg_off candidate not ready_to_commit."
```

The transaction correctly refused to commit an uncertified configuration. The
authenticated SG-off selector table shows why:

```text
all-four [2 3 4 5], SG off:
  coupled   Dv=20                     Omega = -0.48291   margin +0.383   ready
  decoupled R=0.05, wD=3.0, D_t=20    Omega = +0.33598   margin -0.436   REFUSED
```

The islanded four-GFM configuration is small-signal **unstable** in the
decoupled model at those values, while it is stable in the coupled baseline.
Every SG-online configuration was essentially identical between the two
structures (`-0.20502` vs `-0.20502`), and the 1-GFM and most 2-GFM islands were
within a few percent, so the failure was specific to the all-four island.

## Reproduction

```matlab
pf_init_paths
chk_decoupled_chronology_tmp      % paired production chronology arms
chk_decoupled_selector_tmp        % SG_OFF/SG_ON selector tables, both profiles
chk_decoupled_island_diag_tmp     % D_t=0 equivalence + D_t/wD sweep
chk_decoupled_island_mode_tmp     % which mode crosses + island K
chk_decoupled_washout_design_tmp  % full (wD x D_t) island/SG-online surface
```

(repo-root `chk_*_tmp.m` diagnostics, uncommitted.)

## Root cause

**Filter placement, not a device equation.** At `D_t = 0` the island's slowest
mode is

```text
-0.4829 +- 3.917j     f = 0.623 Hz  (3.92 rad/s)   zeta = +0.122
```

an inter-machine/island swing mode, and the four washout poles sit exactly at
`-w_D`. At `D_t = 20` with `w_D = 3.0`:

```text
+0.336 +- 3.396j      f = 0.540 Hz   zeta = -0.0985
modes at -w_D:  4 (D_t=0)  ->  0 (D_t=20)
```

`w_D = 3.0 rad/s = 0.48 Hz` sits essentially **on** the mode the damping term
was meant to act on. All four washout poles migrate into that mode, and the
washout's phase lag turns the transient-damping path into positive feedback at
that frequency.

**Why the design basis allowed it.** `w_D` had been sized by `w_D << w_n` with
`w_n = 23..30 rad/s` computed from the SG-ONLINE synchronising coefficient. The
island values, measured afterwards through the production dispatch path
(post-trip `P`/`Q` schedule + `mixed_ibr_reduced_initialize` +
`mixed_equilibrium_solve`, residual `6.6e-11`):

```text
island    K_ii = [-0.0151, 0.0015, 0.1169, 0.0525] pu/rad
SG-online K_ii = [ 0.1653, 0.1421, 0.1862, 0.1135] pu/rad   (basis used)
```

Two island coefficients are `<= 0`, so `w_n = sqrt(K w_b / M)` is not even real
for those devices and the single-machine cubic used to size `D_t` has no valid
natural frequency there. The frequency that had to be respected was the island
swing mode at 3.92 rad/s — 6 to 8 times below what the basis assumed. `w_D = 3.0`
landed on it.

Designing a grid-forming damping term at the SG-online operating point was the
underlying error: the island is the operating point the device exists to serve.

## The measured surface

Authenticated all-four margin, `gamma_req = 0.1` (bold = refused):

| `w_D` | `D_t`=0 | 5 | 10 | 20 | 40 |
|---|---|---|---|---|---|
| 3 | −0.4829 | −0.1586 | **+0.0628** | **+0.3360** | **+0.5900** |
| 10 | −0.4829 | −0.3093 | −0.1398 | **+0.1476** | **+0.5126** |
| 30 | −0.4829 | −0.4301 | −0.3732 | −0.2504 | **+0.0062** |
| 50 | −0.4829 | −0.4529 | −0.4212 | −0.3532 | −0.2023 |
| 100 | −0.4829 | −0.4686 | −0.4539 | −0.4232 | −0.3565 |

Over the same 25 points the SG-online all-four margin moves from `-0.2050217` to
`-0.2050206`: a change of `1.1e-6`.

Two findings, neither of them the intended one:

1. **No `D_t > 0` improves this system.** Every entry is worse than the
   `D_t = 0` column. A larger `w_D` reduces the harm; it never produces a
   benefit.
2. **`D_t` does move real modes, just not the binding ones.** At SG-online it
   shifts four modes from about `-244` to about `-494` and the Schur-reduced
   trace moves by exactly `-4 D_t/M`, as the equation declares. Those modes are
   nowhere near the `-0.205` dominant mode, so the margin does not notice.

## Correction

`D_t` default returns to `0.0` and `w_D` to `50.0` (the REGFM_B1 Table-1
`SOURCE_VERBATIM` corner, ~13x above the island swing mode) in
`+ibr/gfm_decoupled_full_model.m` and `+cases/scenario_ieee14_1sg_4ibr.m`.
`D_t = 0` is recorded as a measured result, not an unset default: it is the only
value with a defensible justification on this network. No equation, state order,
gate, threshold or tolerance changed; the knob itself is untouched and exact.

`w_D = 50` is retained rather than left arbitrary specifically so that a caller
who does enable `D_t` cannot repeat the withdrawn placement by accident.

## Withdrawn claims

The first delivery asserted that `R = 0.05, w_D = 3.0, D_t = 20` "holds 5 %
droop AND `zeta ~= 1/sqrt(2)`" as a property of the studied system. That figure
was a single-machine polynomial value at the SG-online `K`, presented with more
scope than it had, and the pair it recommended makes the island unstable. It is
withdrawn in `DECOUPLED_GFM_SOURCE_CONTRACT.md` section 8, and the test that
asserted it
(`test_ibr_decoupled_swing_decoupling_oracle/testCoupledBaselineCannotMeetBothTargetsButDecoupledCan`)
was rewritten as
`testCoupledBaselineCannotSeparateDroopFromDampingButThisModelCan`, which
asserts only the structural statement that survives.

The structural contribution is unaffected: droop, transient damping and inertia
are provably independent knobs, `D_t = 0` reproduces the coupled baseline
bit-for-bit, and each knob moves exactly what its equation declares. On this
network the damping knob has no beneficial setting — delivered, characterised,
set to zero.

## Falsified hypotheses

1. **Implementation defect in the new model** — falsified decisively: at
   `D_t = 0` the decoupled island margin is `-0.48290852` against the coupled
   baseline's `-0.48290852`, agreeing to `1.2e-13`, and the SG-online spectrum
   equals the baseline spectrum plus exactly four eigenvalues at `-w_D`.
2. **The washout state itself is wrong** — falsified: with `D_t = 0` the four
   washout poles are exactly `-w_D` and dynamically inert, and the declared
   cubic factors as `(s + w_D)(M s^2 + (1/R)s + K w_b)`.
3. **The island is simply harder for any GFM** — falsified: the coupled baseline
   certifies the same island at `-0.483` on the same dispatch, topology and
   gates.
4. **A larger `D_t` would help if `w_D` were right** — falsified by the surface:
   at every `w_D` from 3 to 100 the margin is monotonically worse in `D_t`.

## Verification

```text
tests/test_ibr_decoupled_dual_mode_model.m            8/8
tests/test_ibr_decoupled_swing_decoupling_oracle.m    6/6
tests/test_ieee14_decoupled_full_state.m              6/6  (+1 island oracle)
tests/test_ts_hybrid_agsi_reference.m                 5/5
```

The new `testIslandSpectrumEqualsBaselineAtProductionDefaults` pins both halves
through the production candidate path: the island must be certified at the
defaults and match the coupled baseline margin, and the withdrawn
`(w_D = 3.0, D_t = 20)` pair must stay refused with `Omega > 0`, so the recorded
failure mode cannot be silently re-enabled.

## Related files

- `+ibr/gfm_decoupled_full_model.m`, `+cases/scenario_ieee14_1sg_4ibr.m`
- `docs/project/DECOUPLED_GFM_SOURCE_CONTRACT.md` (sections 6, 7, 7a, 8)
- `2026-08-13-decoupled-gfm-model-and-agsi-reference.md`
- `2026-08-13-dv20-post-line-nonsmooth-newton-wall.md`
