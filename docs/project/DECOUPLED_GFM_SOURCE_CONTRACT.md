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

**Limitation.** These are SG-online values. The islanded (SG-off) measurement
was attempted with the case post-trip dispatch and its equilibrium did not
converge in that harness, so no islanded `K` is claimed here. The chosen design
is therefore checked for robustness over a wide `K` sweep (below) and the
islanded configuration is gated by the existing selector/candidate SSSA path
rather than by an islanded `K` figure.

## 7. Parameter derivation

| symbol | value | classification | derivation |
|---|---|---|---|
| `R_droop` | 0.05 | `PROJECT_DERIVED` | 5 % P--f droop. CAISO/WECC governor practice is 3--5 %; ERCOT's GFM functional test framework bases a criterion on GFM droop `<= 5 %`. Chosen equal to the `Dv = 20` baseline's static droop so the two structures are compared at equal droop. |
| `M` | 0.08 | source-printed, retained | `M = 0.08` (`H_v = 0.04 s`) is printed in the source parameter table (p.5). Held fixed so the comparison is also at equal inertia. |
| `w_D` | 3.0 rad/s | `PROJECT_DERIVED` | Timescale separation on both sides. Upper bound: `w_D/w_n = 0.10..0.13` at the measured `w_n`, so the washout gain `w_n^2/(w_n^2+w_D^2)` is `0.984..0.990` — the washout does not remove `D_t`'s authority at the frequency it must damp. Lower bound: `tau = 1/w_D = 0.333 s`, one to two orders below any primary-frequency-response settling window, so the DC droop is untouched. REGFM_B1's Table-1 `wD = 50` is NOT inherited: its `2H` is far larger, so its swing frequency and washout corner differ. |
| `D_t` | 20.0 | `PROJECT_DERIVED` | Exact-cubic bisection for `zeta = 1/sqrt(2)` (maximally-flat second-order design) at the measured `K`, with `R` and `M` already fixed above. Attained `zeta = 0.7072 (K=0.1862) .. 0.7151 (K=0.1135)`, i.e. within 1.1 % of target across the measured range. |

Robustness of `(w_D, D_t) = (3.0, 20.0)` over a wide `K` sweep, `R = 0.05`,
`M = 0.08`:

| `K` [pu/rad] | 0.02 | 0.05 | 0.1135 | 0.1862 | 0.4 | >= 1.0 |
|---|---|---|---|---|---|---|
| `zeta` | overdamped | 0.827 | 0.715 | 0.707 | 0.782 | overdamped |

The design holds `zeta` in `[0.71, 0.83]` over `K in [0.05, 0.4]`, which brackets
the measured range by roughly 2x on each side. Outside that band the response
becomes over-damped, i.e. sluggish but stable — never under-damped.

## 8. What the separation buys, quantified

At the measured `K` and the unchanged `M = 0.08`, with the two targets frozen
before the numbers (5 % droop; `zeta = 1/sqrt(2)`):

| structure | droop | `zeta` | both targets? |
|---|---|---|---|
| coupled, `Dv = 1.50` (source-printed) | 66.7 % | 0.41 .. 0.32 | no — droop far outside 3--5 % |
| coupled, `Dv = 2.6 .. 3.4` | 38 .. 30 % | 0.71 | no — droop far outside 3--5 % |
| coupled, `Dv = 20` (project baseline) | 5.0 % | 5.40 .. 4.22 | no — heavily over-damped |
| decoupled, `R=0.05, w_D=3.0, D_t=20` | 5.0 % | 0.715 .. 0.707 | yes |

There is no `Dv` that satisfies both, because droop and damping are the same
number. This is the contribution: not a stability fix — the coupled
configuration is small-signal stable (`max Re = -0.2308`) — but the ability to
place the steady-state characteristic and the transient response independently,
with each coefficient defensible on its own grounds.

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
- all-GFM at `D_t = 0`: spectrum = baseline spectrum plus exactly four
  eigenvalues at `-w_D = -3.0`, remainder matching to `4.1e-12`;
- all-GFM at `D_t = 20`: dominant shift `-249.4` against the declared
  `-D_t/M = -250`, and `max Re` unchanged at `-0.2308`;
- Jacobian rows equal the declared coefficients to `2.7e-11` relative over a
  36-point parameter grid.

Full-repository regression not run; targeted producer/consumer/failure-path
coverage above is the delivered evidence, per the risk policy in `AGENTS.md`.

## 11. Limitations

1. No islanded (SG-off) `K` measurement — see section 6.
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
