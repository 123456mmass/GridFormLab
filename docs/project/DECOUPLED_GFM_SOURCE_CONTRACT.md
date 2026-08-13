# Decoupled GFM swing — source contract and derivation

Status: `PROJECT_MODEL_IMPLEMENTED_PENDING_CHRONOLOGY_GATES`
Date: 2026-08-13
Owner classification: `PROJECT_DERIVED` (swing block) over `SOURCE_MAPPED`
plant/control equations.

This document is the equation and parameter contract for the project's own
grid-forming model, `ibr.gfm_decoupled_full_model` (standalone, 11 states) and
`ibr.decoupled_dual_mode_model` (dual-mode superset, 17 states). It records the
derivation, not merely the numbers.

## 1. What this model changes, and what it does not

Unchanged and reused verbatim from the EECON49-mapped implementation
(`ibr.gfm_eecon49_full_model`, `ibr.gfl_eecon49_full_model`, both retained
byte-faithful as the comparison baseline):

- AC L-filter current dynamics and the reduced command path (`v_del = v_cmd`,
  defect `TD-2026-08-12-01`);
- DC-link state and the project DC current-source closure;
- Q--V amplitude loop, voltage PI, current PI;
- the circular current-reference limiter and the conditional anti-windup;
- the whole GFL branch, including its PLL;
- the dual-mode superset layout, transfer contract and input ABI
  `u = [P_ref; Q_ref; E_ref]`.

Changed: the GFM swing block only.

Explicitly NOT claimed: this model does **not** resolve the `Dv = 20`
post-line-trip nonsmooth Newton wall (`TS-2026-08-13-03`). That blocker lives in
the current-reference limiter / anti-windup active set and is independent of the
swing coefficients.

## 2. Why one extra state is unavoidable

The baseline swing has a single free coefficient:

```text
M d(omega)/dt = kappa P_ref - P_inv - Dv (omega - 1)
```

`Dv` is the only term that produces a steady-state P--omega characteristic, so
the droop is `1/Dv`; the same `Dv` divided by `2 sqrt(M omega_b K)` is the swing
damping ratio. Adding a second proportional term cannot separate the two roles,
because

```text
-(1/R)(omega-1) - D (omega-1) = -(1/R + D)(omega-1)
```

collapses back to one coefficient. The in-repo NREL REGFM_B1 reference model
writes exactly that algebra as `-(1/mp + D1)*omega_m`
(`+ibr/regfm_b1_vsg_model.m:629`) and consequently ships `D1 = 0`, moving all
transient damping into a washout term `D2*(omega_m - x_washout)` with its own
state. Separation therefore requires one additional state; that is a structural
fact, not a modelling preference.

## 3. Equations

In the EECON49 absolute-speed variables (`omega = 1` at equilibrium, `omega_b =
2 pi f_base`, `kappa = Sbase/Mbase`):

```text
M d(omega)/dt   = kappa P_ref - P_inv - (1/R)(omega - 1) - D_t (omega - omega_f)
d(theta)/dt     = omega_b (omega - 1)
d(omega_f)/dt   = w_D (omega - omega_f)
```

`omega_f` is a first-order washout (low-pass) of the measured speed, so
`D_t (omega - omega_f)` is the high-pass part `D_t s/(s + w_D)` of the speed:
full authority for `w >> w_D`, none at DC.

Properties, each with an executable oracle:

| property | statement | oracle |
|---|---|---|
| droop is `R` alone | at any steady state `omega_f = omega`, the `D_t` term is identically 0, so `omega - 1 = R (kappa P_ref - P_inv)` | `test_ibr_decoupled_swing_decoupling_oracle/testSteadyStateDroopIsRAloneForEveryDampingSetting` |
| damping is `D_t` alone | `D_t` moves the damping ratio monotonically over the design band with `R`, `M` held | same file, `testThreeKnobsActOnThreeSeparateProperties` |
| inertia is `M` alone | `w_n(D_t=0) = sqrt(K omega_b / M)` | same test |
| exact baseline reduction | `D_t = 0` with `Dv = 1/R` reproduces the baseline RHS bit-for-bit | `testZeroTransientDampingReproducesBaselineExactly` (AbsTol 0, 200 random states) |
| washout inert at `D_t=0` | the cubic factors as `(s + w_D)(M s^2 + (1/R) s + K omega_b)` | `testWashoutIsDynamicallyInertAtZeroTransientDamping`; in the full system `test_ieee14_decoupled_full_state/testAllGfmSpectrumAddsExactlyFourWashoutModesAtZeroDamping` |

## 4. State contract

Standalone (`nx = 11`):

```text
[i_d i_q V_dc theta omega E xi_Vd xi_Vq xi_Id xi_Iq omega_f]
```

Dual superset (`nx = 17`), `device_type = 'ibr_decoupled_dual'`:

```text
common plant 1:3   [i_d i_q V_dc]
GFL 4:9  (PLL)     [delta_PLL xi_PLL xi_P xi_Q xi_Id xi_Iq]
GFM 10:17 (no PLL) [delta_VSG omega_VSG E xi_Vd xi_Vq xi_Id xi_Iq omega_f]
```

Active states: 9 in GFL, 11 in GFM. `omega_f` is appended **last** on purpose,
so indices 1:16 keep exactly the meaning they have in the 16-state baseline and
every index-based consumer stays valid. The GFM branch has no PLL and the GFL
branch has one; that ownership is asserted by test.

Equilibrium sets `omega_f = 1 = omega`, so the equilibrium vector is
bit-identical to the baseline equilibrium on the shared states and is
independent of `R`, `D_t`, `w_D` and `M` (verified over a 144-point grid at
`AbsTol 0`).

**Transfer decision (`PROJECT_DERIVED`).** On entry to GFM the washout state is
initialised TRACKED, `omega_f = omega_VSG`, after the existing PLL-frequency
carry-over. Leaving it at the equilibrium value 1 while `omega` is carried from
the PLL would inject a step torque `-D_t (omega_PLL - 1)/M` into the swing row
at the transfer instant, which no source or derivation justifies. `omega_f` does
not enter the current injection, so the existing current-continuity gate is
unaffected. Measured on the test fixture the avoided step is `0.133 pu/s` at
`D_t = 40`.

## 5. Characteristic polynomial

Linearising `(theta, omega, omega_f)` about the equilibrium with synchronising
coefficient `K = d(P_inv)/d(theta)`:

```text
M s^3 + (M w_D + 1/R + D_t) s^2 + ((1/R) w_D + K omega_b) s + K omega_b w_D = 0
```

Two limits confirm the structure:

- `D_t = 0`: `s = -w_D` is always a root and the remainder is the baseline
  quadratic `M s^2 + (1/R) s + K omega_b`;
- `w_D -> infinity`: the `D_t` term vanishes, i.e. a washout that tracks
  instantly provides no damping.

At frequency `w` the washout contributes `D_t w^2/(w^2 + w_D^2)` of real
damping, so the small-`D_t` approximation is

```text
zeta ~= [1/R + D_t w_n^2/(w_n^2 + w_D^2)] / (2 sqrt(M K omega_b)).
```

**That approximation must not be used to pick `D_t`.** `zeta(D_t)` is not
monotone in general — it has an interior extremum, because a large `D_t` moves
the system out of the second-order regime — so every design value below is
solved on the exact cubic by bisection. The non-monotonicity is asserted by test
so a later edit cannot silently reintroduce the approximation.

## 6. Measured synchronising coefficient

Every design number below rests on a measured `K`, not an estimate. `K` is read
directly off the full-KCL Schur-reduced SSSA state matrix, which already
contains the network response:

```text
K_ii = -M * A(row of gfm_omega_VSG_i, col of gfm_delta_VSG_i)
A    = sssa.A from stability.composite_sssa_model(..., full_kcl=true)
```

IEEE14 all-GFM SG-online, `Dv = 20`, `M = 0.08`:

```text
K_ii = 0.1653 (IBR2), 0.1421 (IBR3), 0.1862 (IBR6), 0.1135 (IBR8) pu/rad
range 0.1135 .. 0.1862 pu/rad
w_n  = sqrt(K omega_b / M) = 23.13 .. 29.62 rad/s  (3.68 .. 4.71 Hz)
```

Reproduce: `chk_decoupled_ksync_tmp.m` (repo root, uncommitted diagnostic).

An earlier revision of `EECON49_GFL_GFM_SOURCE_CONTRACT.md` used an unmeasured
`K ~= 5 pu/rad`, which is 27--44x too large; the damping figures derived from it
are withdrawn there.

**The islanded values, measured after the first attempt failed.** The SG-off
measurement initially did not converge in the standalone harness, and that gap
was recorded here as a limitation. It has since been closed by going through the
production dispatch path (post-trip `P`/`Q` schedule + `mixed_ibr_reduced_initialize`
+ `mixed_equilibrium_solve`, residual `6.6e-11`):

```text
island    K_ii = [-0.0151, 0.0015, 0.1169, 0.0525] pu/rad
SG-online K_ii = [ 0.1653, 0.1421, 0.1862, 0.1135] pu/rad
```

Two islanded values are `<= 0`, so `w_n = sqrt(K w_b / M)` is not real for those
devices and the single-machine cubic has no valid natural frequency there at all.
Designing on the SG-online values alone was therefore not conservative — it was
the wrong operating point for the role this device exists to serve. Section 7a
records what that cost.

## 7. Parameter derivation

| symbol | value | classification | derivation |
|---|---|---|---|
| `R_droop` | 0.05 | `PROJECT_DERIVED` | 5 % P--f droop. CAISO/WECC governor practice is 3--5 %; ERCOT's GFM functional test framework bases a criterion on GFM droop `<= 5 %`. Chosen equal to the `Dv = 20` baseline's static droop so the two structures are compared at equal droop. Unaffected by `D_t`/`w_D` — this is the one coefficient the separation makes independent, and it holds exactly. |
| `M` | 0.08 | source-printed, retained | `M = 0.08` (`H_v = 0.04 s`) is printed in the source parameter table (p.5). Held fixed so the comparison is also at equal inertia. |
| `D_t` | **0.0** | `PROJECT_DERIVED` from measurement | No positive value is defensible on this system. See section 7a: in the authenticated all-four ISLAND every `D_t > 0` degrades the margin monotonically at every washout corner tested, and in the SG-online configuration `D_t` does not move the dominant mode at all. |
| `w_D` | **50.0 rad/s** | `SOURCE_VERBATIM` (REGFM_B1 Table 1), retained | `regfm_b1_vsg_model.m:175`. Inactive while `D_t = 0`, but retained rather than left arbitrary because it is ~13x above this island's slowest mode (3.92 rad/s), so a caller who does enable `D_t` keeps the washout pole clear of the mode that sets the island margin. |

## 7a. Measured system behaviour of D_t — and what was withdrawn

An earlier revision of this document sized `D_t = 20.0` and `w_D = 3.0` by
solving the single-machine cubic of section 5 for `zeta = 1/sqrt(2)` at the
SG-online `K`. Both values, and the contribution claim built on them, are
**withdrawn**. What the measurement showed:

**The island becomes unstable.** With the authenticated all-four SG-off
candidate evaluated through the production path
(`stability.ibr_candidate_evaluate`, `gamma_req = 0.1`):

```text
coupled  Dv=20                      island Omega = -0.48291   ready
decoupled R=0.05, D_t=0             island Omega = -0.48291   ready   (identical to 1.2e-13)
decoupled R=0.05, wD=3.0, D_t=20    island Omega = +0.33598   REFUSED
```

The production chronology therefore never even reached the SG trip: the
transaction refused to commit an uncertified configuration and failed closed
with `stability:gfm_selection:candidateNotReady` at `t = 1.0`.

**The mechanism.** At `D_t = 0` the island's slowest mode is
`-0.4829 +- 3.917j`, i.e. 0.623 Hz (3.92 rad/s) — an inter-machine/island swing
mode — and the four washout poles sit exactly at `-w_D`. At `D_t = 20` with
`w_D = 3.0` all four washout poles have vanished into that mode and the pair has
crossed to `+0.336 +- 3.396j` (0.540 Hz, `zeta = -0.0985`). The chosen washout
corner `w_D = 3.0 rad/s = 0.48 Hz` sits essentially **on** the mode it was meant
to damp, so the washout's phase lag turns the transient-damping path into
positive feedback at that frequency. This is a filter-placement error, not a
device-equation error.

**Why the design basis missed it.** The `w_D` criterion used was `w_D << w_n`
with `w_n = 23..30 rad/s` from the SG-online `K`. Measured on the island through
the production dispatch path, the synchronising coefficients are

```text
island    K_ii = [-0.0151, 0.0015, 0.1169, 0.0525] pu/rad
SG-online K_ii = [ 0.1653, 0.1421, 0.1862, 0.1135] pu/rad   (the basis used)
```

Two island values are `<= 0`, so `w_n = sqrt(K w_b / M)` is not even real for
those devices and the single-machine cubic has no valid natural frequency there.
The mode that actually had to be respected is the island swing mode at
3.92 rad/s, 6--8x below the frequency the design basis assumed. `w_D = 3.0`
landed on it.

**The full surface.** Island and SG-online margins over
`w_D in {3,10,30,50,100}` x `D_t in {0,5,10,20,40}`:

| `w_D` | `D_t`=0 | 5 | 10 | 20 | 40 |
|---|---|---|---|---|---|
| 3 | −0.4829 | −0.1586 | **+0.0628** | **+0.3360** | **+0.5900** |
| 10 | −0.4829 | −0.3093 | −0.1398 | **+0.1476** | **+0.5126** |
| 30 | −0.4829 | −0.4301 | −0.3732 | −0.2504 | **+0.0062** |
| 50 | −0.4829 | −0.4529 | −0.4212 | −0.3532 | −0.2023 |
| 100 | −0.4829 | −0.4686 | −0.4539 | −0.4232 | −0.3565 |

(bold = refused by `gamma_req`.) Over the same 25 points the SG-online all-four
margin moves from `-0.2050217` to `-0.2050206` — a change of `1.1e-6`.

Two conclusions follow, and neither is what the design intended:

1. **`D_t > 0` never improves this system.** Every entry is worse than the
   `D_t = 0` column. A larger `w_D` only reduces the harm; it does not turn it
   into a benefit.
2. **`D_t` does move real modes, but not the binding ones.** At SG-online,
   `D_t = 20` shifts four modes from about `-244` to about `-494`, exactly the
   declared `-D_t/M = -250`. Those modes are far from the `-0.205` dominant
   mode, so the shift is invisible in the margin. The single-machine cubic
   describes the modes `D_t` owns; it does not describe the modes that limit
   this network.

`D_t = 0` is therefore the value the evidence supports, and it is recorded as a
measured result rather than a default left unset. The knob remains exact and
available — `D_t = 0` reproduces the coupled baseline bit-for-bit, and any
positive value moves the swing rows exactly as declared — but on THIS system
there is no positive value with a defensible justification. A different network,
or an island whose binding mode is the swing mode rather than an inter-machine
mode, could well use it; that would need its own island-level derivation.

## 8. What the separation actually buys, and what it does not

Stated at the measured `K` and the unchanged `M = 0.08`, separating the
statements that hold from the one that was withdrawn.

**Holds — the structural result.** In the coupled baseline droop and damping are
one number, so the two cannot be placed independently. On the single-machine
characteristic at the SG-online `K`:

| structure | droop | single-machine `zeta` |
|---|---|---|
| coupled, `Dv = 1.50` (source-printed) | 66.7 % | 0.41 .. 0.32 |
| coupled, `Dv = 2.6 .. 3.4` | 38 .. 30 % | 0.71 |
| coupled, `Dv = 20` (project baseline) | 5.0 % | 5.40 .. 4.22 |

No `Dv` gives both 5 % droop and a damping ratio near `1/sqrt(2)`. The decoupled
structure removes that coupling exactly: `R` alone fixes the droop (proved at
`AbsTol 0`), and `D_t` alone moves the swing rows by exactly `-D_t/M` (measured
in the coupled 49-state system as a `-249.4` shift against a declared `-250`).

**Withdrawn — the system-level claim.** An earlier revision of this section
asserted that `R = 0.05, w_D = 3.0, D_t = 20` "holds 5 % droop AND
`zeta ~= 1/sqrt(2)`" as if that were a property of the studied system. It is
not. Section 7a shows that on this network the modes `D_t` owns are not the modes
that bind the margin, and that this particular `(w_D, D_t)` pair makes the
all-four island unstable. The `zeta` figure was a single-machine number
presented with more scope than it had.

**So the honest summary is:** the contribution delivered here is a GFM whose
droop, transient damping and inertia are *provably independent knobs*, with the
baseline reproduced bit-for-bit at `D_t = 0` and each knob's effect verified
against its declared equation. On the IEEE14 island studied, the damping knob has
no beneficial setting — that is a measured property of this network, reported as
found. The droop and inertia knobs are used; the damping knob is delivered,
characterised, and set to zero.

## 9. Registration surface

The 17-state family is registered at every consumer that dispatches on the
16-state family. Three of these fail **silently** if a family is omitted — they
select a different operating point or gate without throwing — and are marked:

| consumer | what it decides |
|---|---|
| `+ibr/device_contract_metadata.m` | `decoupled_dual` contract, 17 metadata rows, exact-match dispatch (fails closed on wrong `nx`/order) |
| `+stability/build_mixed_resource_devices.m` | factory dispatch `'decoupled_dual' -> ibr.decoupled_dual_mode_model` |
| `+stability/ibr_candidate_evaluate.m` | **silent** — mode-aware SG-off source dispatch |
| `+stability/ibr_scr_metrics.m` | **silent** — `not_applicable_full_state_source_model` SCR profile |
| `+stability/ts_simulate_ibr_hybrid.m` | **silent** — authenticated candidate `P_ref`/`Q_ref` installation |
| `+stability/mixed_ibr_reduced_initialize.m` | SG-off P/Q-reference warm start |
| `+ibr/state_inventory_snapshot.m` | dual-mode inactive-anchor classification |
| `+cases/scenario_ieee14_1sg_4ibr.m` | `case_profile='decoupled_figure4'`, parameters, provenance |
| `scripts/reporting/generate_gfl_gfm_sssa_tables.m` | report symbol `$\omega_f^{GFM}$` |

`+ibr/build_ieee14_switch_system.m` (the Path-B `SwitchableIbr6` diagnostic
route) is deliberately NOT extended; it keeps the baseline family only.

**Delivery note on the report label.** The `$\omega_f^{GFM}$` symbol mapping is
present in the working tree but is NOT part of this commit, because that file
also carries SG-online report-table work from an earlier session that has not
been validated. Omitting it degrades nothing: an unmapped state name falls
through to `latex_text`, so the table still generates with the raw identifier.
It will land with the report re-validation.

## 10. Verification

Fresh on the current tree, MATLAB R2026a:

```text
tests/test_ibr_decoupled_dual_mode_model.m            8/8
tests/test_ibr_decoupled_swing_decoupling_oracle.m    6/6
tests/test_ieee14_decoupled_full_state.m              5/5
tests/test_ibr_eecon49_dual_mode_model.m             13/13  (baseline, unmodified)
tests/test_ieee14_eecon49_full_state.m                6/6  (baseline, unmodified)
```

Baseline immutability (`G0`): `+ibr/gfm_eecon49_full_model.m` and
`+ibr/eecon49_dual_mode_model.m` are byte-identical to their pre-work state
(SHA-256 `56552f24...762813` and `b5a7d4d8...f2883c2`) and their two test files
pass without modification.

Key measured results:

- all-GFL: decoupled equilibrium and reduced spectrum identical to the baseline
  profile at `AbsTol 0` / `1e-12` (the appended state cannot leak into GFL);
- all-GFM SG-online at `D_t = 0`: spectrum = baseline spectrum plus exactly four
  eigenvalues at `-w_D`, remainder matching to `4.1e-12`;
- all-GFM ISLAND at `D_t = 0`: `Omega = -0.48291` versus the coupled baseline's
  `-0.48291`, agreeing to `1.2e-13` — the equivalence holds at system level in
  the islanded configuration too, which is what falsified an implementation
  defect when the island later proved sensitive to `D_t`;
- SG-online at `D_t = 20`: the four swing rows shift from about `-244` to about
  `-494`, i.e. the declared `-D_t/M = -250`, while `max Re` stays `-0.2308` —
  the knob acts exactly as specified on modes that do not bind the margin;
- Jacobian rows equal the declared coefficients to `2.7e-11` relative over a
  36-point parameter grid;
- island/SG-online margin surface over `w_D x D_t` (section 7a), which is the
  evidence for `D_t = 0`.

Full-repository regression not run; targeted producer/consumer/failure-path
coverage above is the delivered evidence, per the risk policy in `AGENTS.md`.

## 11. Limitations

1. The damping knob has no beneficial setting on this network (section 7a). It
   is delivered, characterised and set to zero, so the default configuration is
   numerically equivalent to the coupled baseline. Only the droop and inertia
   knobs are exercised here.
2. The decoupled model does not address `TS-2026-08-13-03`; no chronology or
   reclose claim is made for it, and no production report has been regenerated
   with it.
3. `zeta(D_t)` is non-monotone; any future retune must use the exact cubic.
4. The 17-state family is not wired into the Path-B `SwitchableIbr6` route.
5. `Imax`, event times, `gamma_on/off`, dwell, timeout, lockout, tolerances and
   every other gate are untouched by this work.

## 12. Reproduction

```matlab
pf_init_paths;
% design measurement
chk_decoupled_ksync_tmp        % measured K, wD/D_t design sweeps
chk_decoupled_ksync2_tmp       % wide-K robustness, washout timescale
% oracles
chk_decoupled_standalone_tmp   % 16/16 standalone
chk_decoupled_dual_tmp         % 29/29 dual layout + transfer
chk_decoupled_e2e_tmp          % 15/15 registration + SSSA
% committed tests
runtests({'tests/test_ibr_decoupled_dual_mode_model.m', ...
          'tests/test_ibr_decoupled_swing_decoupling_oracle.m', ...
          'tests/test_ieee14_decoupled_full_state.m'})
```

The `chk_*_tmp.m` harnesses are uncommitted diagnostics; the committed tests are
the durable instruments.
