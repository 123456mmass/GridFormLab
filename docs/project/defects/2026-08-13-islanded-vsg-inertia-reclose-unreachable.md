# Islanded VSG reclose unreachable: 94 % inertia loss at the SG trip

- ID: `RECLOSE-2026-08-13-01`
- Status: `RESOLVED_REACHABILITY / RECLOSE_CHRONOLOGY_BLOCKED`
- Branch / tree: `main`, command-delay reduction commit `e233b6c` plus the
  inspected Dv=20 working tree on 2026-08-13.
- Environment: Windows 11, MATLAB `-batch`, project paths via `pf_init_paths`.
- Related: `RECLOSE-2026-08-12-01` (synchronizer `Pmin` floor, RESOLVED),
  `TD-2026-08-12-01` (command-delay reduction), `SWITCH-2026-08-10-03`.

## Symptom

The IEEE-14 EECON49 switching arm reports `reclose_status = SYNC_TIMEOUT` and
`handback_status = NOT_STARTED`. The islanded phase never reaches a steady
state: in the final second of a 25 s run the two forming units sit at
48.96 Hz and 79.71 Hz, bus voltages span 0.52–1.25 pu, and device currents
reach 1.34 pu against `Imax = 1.2`.

## Reproduction

```
matlab -batch "chk_nosupport_tmp"      % supervision OFF, 25 s, SYNC_TIMEOUT
matlab -batch "chk_timeline2_tmp"      % mode-aware timeline of the collapse
matlab -batch "chk_trip_transient_tmp" % step vs ramp of the post-trip input
matlab -batch "chk_basin_island_tmp"   % the certified equilibrium is robust
matlab -batch "chk_blockdiff_tmp"      % per-state-block substitution
```
(diagnostic scripts at the repository root, `chk_*_tmp.m`, read-only, not
committed.)

## Root cause (evidence-backed)

Islanding removes essentially all of the inertia, and the post-trip operating
point is therefore stable but not reachable.

Inertia on the 100 MVA system base, from the model's own published quantities:

| source | quantity | value |
|---|---|---|
| SG1 | `H_system = H_machine/(Sbase/Sm)`, `synchronous_emf6_ssa.m:79,95` | 2.5 s |
| each IBR | `H_system = 0.5*M/kappa`, `eecon49_dual_mode_model.m:197`, `M = 0.08` | 0.04 s |
| island pre-trip | 2.5 + 4(0.04) | 2.66 s |
| island post-trip | 4(0.04) | 0.16 s |
| forming units only at the trip (2 GFM committed) | 2(0.04) | 0.08 s |

The trip removes 94 % of the island inertia in one step. GFL units contribute
no swing inertia at all — they are current sources behind a PLL — so while
their outer P–PI loops ramp, the SG's 1.33 pu output lands on the two forming
VSGs:

```
df/dt = f0*dP/(2*H_forming) = 60*1.33/(2*0.08) = 4.99e2 Hz/s
```

Even the residual imbalance the droop must absorb after the loops settle
(≈0.045 pu, inferred from the observed frequency sag) gives
`60*0.045/(2*0.16) = 8.4 Hz/s`. The measured island frequency indeed sinks
monotonically: 0.9957 pu at t = 1.43 s, 0.9909 at 1.79 s, 0.9856 at 2.10 s.

`M = 0.08, Dv = 1.50` were inherited as in-repository values. The former
citation to `IBR_REDUCED6_EECON49_MANIFEST.md` was a cross-family
classification error: that manifest governs the reduced-6 model, not this
full-state family.

**Correction (2026-08-13).** This record previously added that "the local
comparison PDF is password-protected", and therefore classified the `Dv=1.50`
attribution as unverified source history. That is factually wrong.
`docs/text/EECON49_[Nui].pdf` is not encrypted (`pdfinfo` reports
`Encrypted: no`) and page 5 prints `Dv = 1.50 p.u., M = 0.08, tau_E = 0.05,
T_d = 0.02, H_SG = 2.5`, readable with `pdftotext -layout -f 5 -l 5`. The
failure was the Read tool's inability to render that PDF, not encryption.
`Dv = 1.50` is `SOURCE_PRINTED`. That does not make it a validated result --
the source is an unvalidated peer M.Sc. work used as a comparison baseline --
and it does not change any measurement in this record.

The owner subsequently set the genuinely free full-state islanded-role value
`Dv=20` as `PROJECT_DERIVED` from a 5 % droop design target; see
`EECON49_GFL_GFM_SOURCE_CONTRACT.md`, whose damping figures were also corrected
on 2026-08-13 once the synchronising coefficient was measured rather than
estimated. `M=0.08` remains unchanged.

## Measured feasibility envelope

`chk_deficit_envelope_tmp` measures the basin in the power direction on the
verified harness (control row holds the equilibrium to 2.27e-12): from the
certified all-4-GFM equilibrium — the most favourable case, maximum forming
inertia — apply a sudden generation deficit distributed by the case
participation vector.

| deficit (pu) | droop `f_ss = 60(1-delta/(n*Dv))` | min f reached | max abs dtheta | verdict |
|---|---|---|---|---|
| 0.02 | 59.800 Hz | 59.787 | 9.5 deg | resynchronises |
| 0.05 | 59.500 | 59.470 | 10.4 | resynchronises |
| 0.10 | 59.000 | 58.945 | 11.7 | resynchronises |
| 0.20 | 58.000 | 57.891 | 14.2 | resynchronises |
| 0.40 | 56.000 | 55.745 | 18.6 | resynchronises |
| 0.80 | 52.000 | 50.838 | 29.3 | resynchronises |
| 0.85 | 51.500 | 49.095 | 41.9 | resynchronises |
| 0.90 | 51.000 | 38.772 | 8.5e4 | diverges |
| 0.95 | 50.500 | 38.284 | 8.5e4 | diverges |
| 1.00 | 50.000 | 37.717 | 8.6e4 | diverges |
| 1.10 | 49.000 | 36.736 | 8.6e4 | diverges |
| **1.3319** (what the trip applies) | **46.681** | 34.257 | 8.7e4 | **diverges** |

The critical deficit lies between **0.85 and 0.90 pu**: the island rides through
0.85 pu (settling at 51.5 Hz, having dipped to 49.1 Hz) and loses synchronism at
0.90 pu. The trip applies 1.3319 pu, roughly 1.5x the capability.

Two independent inadequacies follow, and only the second involves inertia:

1. **Steady state.** The aggregate droop is `n*Dv = 4(1.50) = 6 pu/pu`, so the
   island frequency error is `delta/6` outright. Holding +/-1 Hz needs
   `delta <= 0.10 pu`; +/-3 Hz needs `delta <= 0.30 pu`. The case applies
   1.3319 pu, i.e. `f_ss = 46.7 Hz`. No amount of inertia changes this — it is
   the droop gain.
2. **Transient.** `H_island` falls from 2.66 s to 0.16 s, so the first swing
   exceeds the synchronising limit at the applied deficit.

This also explains why the certified equilibrium sits at exactly
`omega = 1.000000`: for an SG-off island the equilibrium solver *re-dispatches*
`P_ref` (it is an output of the solve, `mixed_equilibrium_solve.m:425,453,627`
via `p_participation`), so the balanced point exists at 60 Hz. The runtime
installs that re-dispatched input at the trip. The failure is the path: while
the units still deliver their pre-trip powers under post-trip commands the
imbalance really is ~1.33 pu, which is the row that diverges.

## What is NOT the cause (each falsified with evidence)

- **Not the equilibrium, the SSSA verdict, or the TS kernel.** Starting the TS
  exactly at the certified SG-off all-4-GFM equilibrium with no events holds it
  to `max|omega-1| = 2.27e-12`; antisymmetric VSG-angle kicks of
  0.5/2/5/10/20 deg all resynchronise to `omega = 1.000000` with the relative
  angles exactly restored (`chk_basin_island_tmp`, and the control row of
  `chk_redist_tmp` and `chk_blockdiff_tmp`).
- **Not numerical stiffness.** The divergence is dt-independent across
  dt = 0.05/0.01/0.005/0.002.
- **Not the current limiter.** Raising `Imax` to 10 pu (diagnostic only) makes
  the collapse worse, not better.
- **Not the support augmentation.** With `automatic_support_supervision = false`
  the two-GFM island collapses as well; the augmentation only accelerates it
  (0.4 s instead of ≈20 s).
- **Not any single state block handed over by the mode transfer.** Substituting
  the arm's post-augment common plant, VSG speed, voltage state, voltage PI or
  current PI individually into the certified equilibrium all HOLD; only all
  blocks together eject (`chk_blockdiff_tmp`).
- **Not the post-trip input schedule.** From the arm's own accepted sample at
  `sg_trip`, applying the installed input as a step or ramping it over
  0.2/0.5/1.0/2.0 s all diverge (`chk_trip_transient_tmp`).

## Secondary finding (separate, real, not sufficient)

`sg_off_support_transaction` (`+stability/ts_simulate_ibr_hybrid.m:2261`) sets
`u_right = u`, deliberately bumpless, whereas `trip_transaction` (`:1855-1857`)
installs the committed candidate's certified `cand.eq_u_eq`. Every candidate
carries `eq_u_eq` (`+stability/ibr_candidate_evaluate.m:325`, persisted at
`+stability/ibr_config_selector.m:393`), so after a live augmentation the island
runs the input certified for the *previous* configuration — here up to 0.355 pu
per unit away from the committed set's own certificate. The transaction's only
acceptance test is the algebraic `right_limit` KCL solve; nothing checks that
the (configuration, input) pair has an operating point. Stepping a healthy
certified island from its own input to that one is by itself enough to lose
synchronism, and no ramp rate rescues it (`chk_redist_tmp`). Installing the
certified input at the augmentation does **not** repair the arm, so this is a
genuine runtime/certification gap but not the cause of the timeout.
`reselection_transaction` has the same structure.

### Fix applied for the secondary finding (2026-08-13, owner-directed)

`sg_off_support_transaction` now installs the committed candidate's own
`candidate.eq_u_eq` and fails closed when a candidate carries none, so a
configuration is never committed against an input for which nothing was
certified. It reuses the existing audited helper
`apply_authenticated_candidate_inputs`, which writes only the `P_ref`/`Q_ref`
entries of `ibr_eecon49_dual` devices — the offline SG synchronizer actuator
(`RECLOSE-2026-08-12-01`) and every `E_ref` are untouched, and the new test
asserts that every other input entry is bit-unchanged.

Gates: the redesigned `tests/test_ts_hybrid_support_certified_input.m` is now
6/6 PASS with no `assume*`: table invariant, deterministic SG-trip pairing,
support augmentation pairing, stale-fingerprint rejection, and deeper
missing-certificate fail-closed coverage. The pre-forwarding broader Dv20 gate
was 34/34 across this suite, model/Path-B consumers, fixed identity, rollback,
and SG-online quotient; after fixing `ADAPT-2026-08-13-02`, fresh adaptive
plumbing/LTE/rollback/event-landing tests pass 11/11. Historical exact adaptive
counts that depended on caller overrides are stale and are not reused.

This does NOT make the reclose succeed; the timeout is the reachability failure
above. Published arm numbers change because the augmentation now runs a
different input, so report re-validation is required.

RESIDUAL, not done: `reselection_transaction` receives `target_modes`,
`target_selected` and `authority` but no candidate row, so no `eq_u_eq` is in
scope there. Closing it requires plumbing the candidate from the caller and
touches the SG-online handback path stabilised by `SWITCH-2026-08-10-03` and
`RECLOSE-2026-08-12-01`; deferred rather than changed silently.

## Falsified diagnostic traps recorded so that they are not repeated

1. **Reading a frozen inactive branch.** `eecon49_dual_mode_model.m:151-158`
   integrates only the active branch, so `delta_VSG`/`omega_VSG` (dual indices
   10, 11) are frozen at the transfer anchor while a device is in GFL mode.
   Differencing that constant against a rotating VSG angle manufactures an
   unbounded linear drift. This produced a spurious "59422 deg / 185 crossings
   of +/-180 deg, first slip at t = 1.770 s". Mode-aware extraction (GFL:
   `delta_PLL` index 4 and `omega = 1 + kiPLL*xi_PLL/omega_b`; GFM: indices 10,
   11) is mandatory, and `res.device_frequency_Hz` is already mode-aware.
2. **Holding an infeasible input before the transition under test.** A step-vs-
   ramp harness that held the pre-trip dispatch (1.3175 pu total) for 0.5 s with
   the SG already open destroyed the state before the transition began
   (`dw/dt = -1.31/0.32 = -4.1 pu/s`). Always include a control row that must
   hold the equilibrium to ~1e-12.
3. **Silently ignored solver option.** `mixed_equilibrium_solve` has no
   `u_override`; for an SG-off island the input is an *output* of the solve
   (`:425,453,627` via `p_participation`). Passing the option produced an
   identical baseline result (`residual = 1.686e-10`) that looked like a valid
   forced-input test.
4. **Raw angle winding.** The accepted post-augment `delta_VSG` values are
   `[100.3, -253.9, -254.1, 113.6] deg`, i.e. two units wound a full turn
   behind; modulo 360 they span only 13 deg. Absolute `max|dtheta|` figures
   from the arm therefore carry a constant ~354 deg offset, and a substitution
   test must reduce the winding or the verdict is meaningless.
5. **Reading a transient dip as recovery.** The two-GFM island appears to
   recover at t = 1.79 s (angle spread falling, `|V|` back to 0.993) but that is
   a dip inside a longer divergence.

## Owner decision and current closure

The owner selected `Dv=20` for the full-state islanded role and kept `M=0.08`.
The decision was frozen from the independently documented 5 % P--f droop target
and damping design basis before the final chronology result; it did not tune a
value to a test. Equilibrium remains bit-identical because the initializer does
not consume `Dv`; the all-GFL/all-GFM SSSA points remain stable, and the
1.3319-pu deficit envelope resynchronises (`f_ss=59.001 Hz`, minimum 58.589 Hz,
angle swing 21.1 deg). This resolves the original Dv=1.50 island-reachability
finding.

It does **not** establish reclose success. Under the canonical Dv20 chronology,
automatic one-GFM/two-GFM configurations fail in the fault window; an
authenticated all-four configuration crosses the fault but reaches a separate
post-line nonsmooth Newton wall before `sg_on`. Crossed state/topology evidence
classifies that blocker in `TS-2026-08-13-03`: line right-limit KCL is feasible,
but the trajectory crosses the circular current-reference/conditional
anti-windup active set, the coupled Jacobian becomes poorly conditioned, and
line search exhausts. Fixing that numerical/model interface would materially
change the approved contract and is deferred fail-closed.

No gate, threshold, timeout, event, limiter, tolerance, or source/case value was
relaxed. Report evidence must say reclose was not reached; stale success caches
are not publishable.
