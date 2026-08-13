# Decoupled GFM swing model, reference-AGSI overlay, and provenance corrections

Date: 2026-08-13
Status: DELIVERED (model + registration + overlay); chronology/report claims remain blocked
Record ID: `MODEL-2026-08-13-01`

This is a delivery and correction record, not a failure record. It exists
because it withdraws three published numbers and one provenance claim, and
because it adds a model family and an opt-in diagnostic to shared files.

## 1. What was delivered

**A project-owned GFM swing with independent droop, damping and inertia.**
`+ibr/gfm_decoupled_full_model.m` (11 states) and
`+ibr/decoupled_dual_mode_model.m` (17 states) place the swing block as

```text
M d(omega)/dt = kappa P_ref - P_inv - (1/R)(omega - 1) - D_t (omega - omega_f)
d(omega_f)/dt = w_D (omega - omega_f)
```

so `R` alone sets the steady-state droop, `D_t` alone adds transient damping
through a washout, and `M` alone sets the inertial timescale. The washout state
is required, not stylistic: `-(1/R)(om-1) - D(om-1) = -(1/R+D)(om-1)` collapses
to a single coefficient, which is exactly why the in-repo NREL REGFM_B1
reference model ships `D1 = 0` and does its damping through `D2` and a washout
(`regfm_b1_vsg_model.m:629-630`). Full derivation:
`docs/project/DECOUPLED_GFM_SOURCE_CONTRACT.md`.

The EECON49-mapped baseline (`gfm_eecon49_full_model.m`,
`eecon49_dual_mode_model.m`) is retained **byte-faithful** as the comparison
model. Verified by SHA-256 before and after
(`56552f24...762813`, `b5a7d4d8...f2883c2`) and by its two test files passing
unmodified.

**An opt-in reference-AGSI in-band overlay.** `+stability/agsi_reference_terms.m`
publishes `J_R`, `J_P`, `J_SCR`, `J_lock` (plus the trigger pair `J_V`, `J_f`)
with per-sample in-band flags `J <= 1`. It is pure post-processing over the
recorded samples and forms **no aggregate index**, because an aggregate is one
step from being a decision variable. The switching supervisor still triggers on
`severity = min(1, max(0, 0.5*J_V + 0.5*J_f))` alone.

## 2. Withdrawn numbers (the reason this record exists)

`EECON49_GFL_GFM_SOURCE_CONTRACT.md` justified `Dv = 20` partly on a damping
figure derived from an **unmeasured** synchronising coefficient `K ~= 5 pu/rad`.
`K` has now been measured from the full-KCL Schur-reduced SSSA state matrix,
`K_ii = -M * A(row omega_i, col delta_i)`, on the IEEE14 all-GFM SG-online
configuration:

```text
K_ii = 0.1653, 0.1421, 0.1862, 0.1135 pu/rad   (IBR2, IBR3, IBR6, IBR8)
```

That is 27--44x smaller than the estimate, so three published figures are
withdrawn and replaced:

| claim | published | measured |
|---|---|---|
| `zeta` at `Dv=20`, `M=0.08` | `~0.81` | `4.22 .. 5.40` (over-damped) |
| `zeta` at `Dv=1.50` | `~0.06` | `0.41 .. 0.32` |
| `zeta` at `M=5.0`, `Dv=20` | `~0.10` | `0.68 .. 0.54` |

Consequences stated honestly:

- the `Dv = 20` **droop** justification (5 %, inside the WECC/CAISO 3--5 % and
  ERCOT `<=5 %` bands) is unaffected and stands;
- its **damping** justification does not stand: at 5 % droop this VSG is
  heavily over-damped, and at the low-`K` device `zeta = 5.40` sits above the
  5.0 upper end of the NESO GBGF-I equivalent-damping range. Over-damping is
  not an instability — the configuration is stable at `max Re = -0.2308` — but
  it is a sluggish response, and no `Dv` satisfies both the droop band and a
  damping target (`zeta = 1/sqrt(2)` would need 30--38 % droop). That is the
  quantified motivation for the decoupled model;
- the earlier **rejection of `H_v = 2.5 s`** rested on the withdrawn
  `zeta ~= 0.10`; that reason does not hold. `M = 0.08` is nonetheless retained,
  because it is the source-printed value and holding it fixed compares the two
  structures at equal inertia. Raising `M` is out of scope and would need its
  own virtual-inertia derivation.

## 3. Corrected provenance claim

Two documents stated that the local source PDF is password-protected and
therefore classified `Dv = 1.50` as unverified source history
(`EECON49_GFL_GFM_SOURCE_CONTRACT.md`,
`2026-08-13-islanded-vsg-inertia-reclose-unreachable.md`; the same sentence had
been copied into `scenario_ieee14_1sg_4ibr.m` and
`build_ieee14_switch_system.m` comments).

**That is factually wrong.** `docs/text/EECON49_[Nui].pdf` is not encrypted
(`pdfinfo` reports `Encrypted: no`) and page 5 prints
`Dv = 1.50 p.u., M = 0.08, tau_E = 0.05, T_d = 0.02, H_SG = 2.5`, readable with
`pdftotext -layout -f 5 -l 5`; the sibling `.docx` corroborates it. The failure
was the Read tool's inability to render that PDF — a tool limitation, not
encryption. `Dv = 1.50` is `SOURCE_PRINTED`. Recorded explicitly so the
misdiagnosis is not reintroduced in a later session.

That does not promote the source to authority: EECON49 is an unvalidated peer
M.Sc. work used as a comparison baseline and strategy template. A verified
quotation is not a verified result.

## 4. Parameter derivation actually used

| symbol | value | classification | basis |
|---|---|---|---|
| `R_droop` | 0.05 | `PROJECT_DERIVED` | 5 % P--f droop; equal to the baseline's static droop so the structures compare at equal droop |
| `M` | 0.08 | source-printed, retained | equal-inertia comparison |
| `w_D` | 50.0 rad/s | `SOURCE_VERBATIM` (REGFM_B1 Table 1) | ~13x above the island's slowest mode (3.92 rad/s), so an enabled `D_t` keeps the washout pole clear of the mode that sets the island margin |
| `D_t` | 0.0 | `PROJECT_DERIVED` from measurement | no positive value is defensible on this network — see `MODEL-2026-08-13-02` |

**Correction, same day (`MODEL-2026-08-13-02`).** The first delivery of this
work shipped `w_D = 3.0, D_t = 20.0`, sized by solving the single-machine cubic
for `zeta = 1/sqrt(2)` at the SG-online `K`. Running the production chronology
falsified that basis immediately: the authenticated all-four SG-off candidate
became small-signal **unstable** (`Omega = +0.336` against the coupled
baseline's `-0.483`), so the SG-trip transaction refused to commit and the run
failed closed at `t = 1.0` with `candidateNotReady`.

Cause: `w_D = 3.0 rad/s = 0.48 Hz` sat essentially on the island's own swing
mode (0.623 Hz, 3.92 rad/s); all four washout poles migrated into it and the
phase lag turned the damping path into positive feedback. The island
synchronising coefficients are `[-0.0151, 0.0015, 0.1169, 0.0525] pu/rad` — two
of them `<= 0` — so the single-machine cubic had no valid natural frequency
there and the SG-online basis was simply the wrong operating point for a
grid-forming damping term. The measured `(w_D x D_t)` surface then showed that
**no** `D_t > 0` improves this system at any `w_D` from 3 to 100, while SG-online
margins move by `1.1e-6` over the same sweep. `D_t` is therefore 0 on measured
evidence, and the "holds 5 % droop AND `zeta ~= 1/sqrt(2)`" claim below is
withdrawn as out of scope. Full record: `MODEL-2026-08-13-02`.

A trap worth recording: `zeta(D_t)` is **not monotone** — it has an interior
extremum, because large `D_t` moves the system out of the second-order regime.
The small-`D_t` approximation
`zeta ~= [1/R + D_t g(w_n)]/(2 sqrt(M K w_b))` therefore cannot be used to pick
`D_t`; at `D_t = 20` it predicts `1.55` against a true `0.715`. A second and
larger trap: even the exact cubic is a single-machine statement, and on this
network the modes it describes are not the modes that bind the margin.

A second design decision worth recording: on entry to GFM the washout state is
initialised TRACKED (`omega_f = omega_VSG`) after the PLL-frequency carry-over.
Leaving it at 1 would inject a step torque `-D_t(omega_PLL - 1)/M` at the
transfer instant (measured: `0.133 pu/s` at `D_t = 40`) that no source or
derivation justifies.

## 5. Registration surface and the silent hazards

Nine consumers dispatch on the dual family. Three fail **silently** — they pick a
different operating point or gate without throwing — and were the real risk in
this work:

- `ibr_candidate_evaluate:is_source_full_state_resources` — mode-aware SG-off
  source dispatch. Omission silently selects the fallback dispatch.
- `ibr_scr_metrics` — `not_applicable_full_state_source_model` profile.
  Omission silently makes the family SCR-eligible, i.e. adds a gate.
- `ts_simulate_ibr_hybrid` authenticated-input installation. Omission silently
  commits a configuration against the previous operating point — the exact
  defect `RECLOSE-2026-08-13-01` fixed for the baseline family.

Each is now covered behaviourally, not by inspection:
`test_ieee14_decoupled_full_state` asserts the mode-aware branch via the
fail-closed `missingModeAwareDispatch` identifier (with the baseline family as a
control), the SCR profile against the baseline family, and the reduced-initializer
applicability. `+ibr/build_ieee14_switch_system.m` (the Path-B `SwitchableIbr6`
diagnostic route) is deliberately NOT extended.

The ninth registration — the `$\omega_f^{GFM}$` report symbol in
`scripts/reporting/generate_gfl_gfm_sssa_tables.m` — is present in the working
tree but NOT in this commit: that file also carries unvalidated SG-online
report-table work from an earlier session. Nothing breaks without it, because an
unmapped state name falls through to `latex_text` and the table still generates
with the raw identifier. It lands with the report re-validation.

## 6. Verification

MATLAB R2026a, branch `main`, tested working tree on top of `e233b6c`.

```text
tests/test_ibr_decoupled_dual_mode_model.m            8/8
tests/test_ibr_decoupled_swing_decoupling_oracle.m    6/6
tests/test_ieee14_decoupled_full_state.m              6/6   (+1 island oracle)
tests/test_ts_hybrid_agsi_reference.m                 5/5
targeted batch A (11 files, metadata/selector/inventory/baseline)  163/163
targeted batch B (7 files, TS driver + equilibrium)  26/27
```

The single batch-B failure is `TEST-2026-08-13-04`, reproduced identically on a
pristine `e233b6c` worktree, i.e. pre-existing and unrelated.

Decisive measurements:

- **G0** baseline byte-identity by SHA-256, and its two test files pass
  unmodified;
- **all-GFL**: decoupled equilibrium and reduced spectrum identical to the
  baseline profile at `AbsTol 0` / `1e-12`;
- **SG-online all-GFM at `D_t = 0`**: spectrum equals the baseline spectrum plus
  exactly four eigenvalues at `-w_D`, remainder to `4.1e-12`;
- **ISLAND all-GFM at `D_t = 0`**: `Omega = -0.48290852` against the coupled
  baseline's `-0.48290852`, agreeing to `1.2e-13`. Together these are the
  strongest oracle in the delivery: the washout state is dynamically inert with
  the knob off, at system level, in both configurations — which is what
  falsified an implementation defect once the island proved sensitive to `D_t`;
- **`D_t` acts exactly as declared**: with `D_t = 20` the Schur-reduced trace
  moves by exactly `-4 D_t/M` (four devices) and four SG-online modes shift from
  about `-244` to about `-494`, while `max Re` stays `-0.2308` — the knob is
  correct and the modes it owns simply do not bind this network;
- **G-AGSI-BITIDENT**: enabling the overlay leaves 13 published arrays
  byte-identical (`max|diff| = 0`), every decision field `isequaln`, and the
  event log identical in type/time/applied; with the option omitted the result
  carries no `agsi_reference` field at all.

Full repository regression not run; targeted producer/consumer/failure-path
coverage above is the delivered evidence under the `AGENTS.md` risk policy.

## 7. What is NOT claimed

1. The decoupled model does **not** resolve `TS-2026-08-13-03` (the post-line
   nonsmooth current-limiter/Newton wall). Measured on the paired production
   chronology: the coupled baseline reaches `t = 2.55/2.56` at `dt = 0.05/0.02`
   and fails there with `stepNewton`, exactly as that record states. Reclose is
   not reached by either structure, and no chronology completion or regenerated
   production report is claimed.
2. The **damping knob has no beneficial setting on this network**
   (`MODEL-2026-08-13-02`). `D_t = 0` is the production value on measured
   evidence, which makes the default configuration numerically equivalent to the
   coupled baseline. Only the droop and inertia knobs are exercised here. The
   separation itself is proven; its usefulness on THIS island is not.
3. The reference-AGSI terms are `ASSUMED_DIAGNOSTIC` and must never be cited for
   a readiness or production claim. First measured values on the compressed arm
   show `J_f` in band throughout while `J_V`, `J_R`, `J_P` and `J_SCR` leave the
   band at the islanding instant (`J_R` peaks near `377 Hz/s`, consistent with
   the 94 % inertia loss already recorded in
   `2026-08-13-islanded-vsg-inertia-reclose-unreachable.md`). That is reported
   as a diagnostic observation, not as a gate result.
4. No threshold, dwell, timeout, lockout, `Imax`, event time, tolerance, or
   acceptance gate was changed anywhere in this work.

## Related files

- `+ibr/gfm_decoupled_full_model.m`, `+ibr/decoupled_dual_mode_model.m`
- `+stability/agsi_reference_terms.m`
- `docs/project/DECOUPLED_GFM_SOURCE_CONTRACT.md`
- `docs/project/EECON49_GFL_GFM_SOURCE_CONTRACT.md`
- `2026-08-13-decoupled-washout-corner-island-instability.md`
- `2026-08-13-dv20-post-line-nonsmooth-newton-wall.md`
- `2026-08-13-islanded-vsg-inertia-reclose-unreachable.md`
- `2026-08-13-standalone-emf6-oracle-equilibrium.md`
