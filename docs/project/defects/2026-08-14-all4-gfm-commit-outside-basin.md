# All-4-GFM support commit lands outside the certified configuration's basin

Date: 2026-08-14
Status: OPEN
Defect ID: `AGSI-2026-08-14-01`

## Scope and evidence boundary

Diagnostic classification of why the IEEE14 EECON49 production chronology loses
island synchronism at `t=53.4025` and therefore can never satisfy the reclose
synchronism guard. Nothing was tuned, and no gate, threshold, event time,
parameter, or contract was changed to produce these numbers. Every metric is
resolved BY STATE NAME (see "Diagnostic traps" below).

## Symptom

Production arm (`case_profile='eecon49_figure4'`, `Dv=20`, adaptive stepper,
250 s horizon): the SG-off severity supervisor augments to the authenticated
all-four GFM configuration `[2 3 4 5]` at `t=53.4025`. Within 0.6 s the forming
units lose synchronism and never recover. At `t=152.017` the run fails closed
with `ts_simulate_ibr_hybrid:adaptiveDtMin`.

Measured forming-unit speeds (`gfm_omega_VSG`, mode-aware):

```text
t=53.3525 (2 GFM)   IBR2 0.983459  IBR6 0.983480                    spread 2.1e-5
t=53.4527 (4 GFM)   IBR2 1.004660  IBR3 0.988698  IBR6 0.996673  IBR8 0.988511
t=54.0063           IBR2 1.074075  IBR3 0.985769  IBR6 0.990544  IBR8 0.984721
t=152.0             IBR2 1.076482  IBR3 0.987254  IBR6 0.988450  IBR8 0.988705
```

IBR2 runs ~5.4 Hz fast against the other three for ~100 s. Its injected power
oscillates between +0.79 and −0.85 pu with a ~2 Hz slip beat, i.e. it
periodically absorbs instead of supplying.

## Reproduction

- `chk_t53_replay_basin_tmp.m` — the decisive controlled replay (ARM A/B/B2/C)
- `chk_t53_left_right_tmp.m` — left/right limits at the commit
- `chk_sync_coefficient_tmp.m` — measured `K=dP/ddelta` per forming unit
- `chk_all4_at_loadstep_tmp.m` — base load vs +20 % load
- `chk_ibr2_deref_tmp.m` — reference/mix variations
- Saved trajectory: `output/diagnostics/reclose_route_adaptive.mat`

## Root cause

The committed configuration is stable; the arriving STATE lies outside its basin
of attraction.

Controlled replay at +20 % load, identical devices, identical network, identical
event context, identical solver settings, 6 s horizon, no events:

```text
ARM A  production arriving state + production inputs   -> SLIPS  (angle exc 4358 deg)
ARM B  certified equilibrium     + production inputs   -> SYNC   (angle exc 6.6 deg)
ARM B2 certified equilibrium     + certified inputs    -> SYNC   (angle exc 0.0 deg)
```

A and B differ ONLY in the initial state. Therefore neither the configuration,
the installed inputs, the load level, nor the network explains the slip.

### The carrying coordinate: IBR2's voltage-loop integrators

Injecting one group of the production deviation at a time into the certified
equilibrium (6 s, no events, everything else at the certified values) isolates
the responsible coordinate exactly:

```text
group injected into the certified equilibrium      relative-angle excursion
relative angles (wrapped)                              8.2 deg   SYNCHRONISED
angles verbatim (the raw -23 rad values)               8.6 deg   SYNCHRONISED
gfm_omega_VSG                                          6.6 deg   SYNCHRONISED
currents i_d, i_q                                      7.1 deg   SYNCHRONISED
current-loop integrators xi_Id, xi_Iq                  6.6 deg   SYNCHRONISED
Vdc                                                    6.6 deg   SYNCHRONISED
voltage loop gfm_E, xi_Vd, xi_Vq                    4338.9 deg   *** SLIPS ***
everything except angles                            1437.1 deg   *** SLIPS ***
```

Narrowing further, within the voltage loop and across units:

```text
gfm_E only                                             6.6 deg   SYNCHRONISED
xi_Vd, xi_Vq only                                   4332.8 deg   *** SLIPS ***

IBR2 voltage loop only                              4827.4 deg   *** SLIPS ***
IBR3 voltage loop only                                13.0 deg   SYNCHRONISED
IBR6 voltage loop only                                12.2 deg   SYNCHRONISED
IBR8 voltage loop only                                 7.4 deg   SYNCHRONISED
```

And the repair direction, starting from the FULL production state:

```text
production state, untouched (control)               4358.0 deg   *** SLIPS ***
production state, gfm_E re-seeded to certified      4328.9 deg   *** SLIPS ***
production state, xi_Vd/xi_Vq re-seeded to certified   8.6 deg   SYNCHRONISED
production state, whole V-loop re-seeded               8.6 deg   SYNCHRONISED
```

Two numbers decide the island. The deviation that carries it is small:

```text
IBR2 xi_Vd  production 0.144253  certified 0.199658  delta -0.055405
IBR2 xi_Vq  production 0.012850  certified -0.015680 delta +0.028530
```

Why IBR2 specifically: IBR3 and IBR8 are transferred from GFL at this very
transaction, so `equilibrium_initialize` seeds their voltage loop consistently
with the terminal voltage (`E - |V| = 0.00000` for both). IBR2 has been GFM
since `t=20` and does NOT pass through a transfer, so it enters the new
configuration carrying integrator values accumulated over 33 s under the
previous one-GFM and two-GFM configurations, inconsistent with the operating
point the new configuration was certified at (`E - |V| = +0.00991`, the only
nonzero one).

The transfer contract conditions the devices that CHANGE mode and leaves the
incumbent formers' integrators untouched, while the transaction simultaneously
moves every former to a new certified operating point.

Angular history is NOT the cause: the raw `-23 rad` VSG angles injected verbatim
stay synchronised (8.6 deg), and the wrapped relative angles at the commit are
only 1.3–3.0 deg from the certified equilibrium.

The gap is a selector-contract gap: `ibr_candidate_evaluate` certifies that the
NEW configuration has a feasible, SSSA-stable equilibrium, and
`sg_off_support_transaction` installs that configuration's certified input
(`ts_simulate_ibr_hybrid:2367`). Neither step tests whether the CURRENT state is
inside the new equilibrium's region of attraction. On a 0.16 s-inertia island
that test is the binding one.

## Falsified hypotheses

Each was falsified by measurement, not by argument:

1. **Dispatch/`P_ref` is wrong at the commit** — installed right-limit values
   match the candidate certificate to 0.2 % (`0.73142` vs `0.73395`, etc.).
2. **A unit is current-saturated at the commit** — at the right limit every unit
   has `sat=0`, `hold=[0 0]`; `rawIref/Imax` = 0.558 / 0.782 / 0.647 / 0.719.
3. **The GFL→GFM transfer seeds `omega` wrongly** — the transfer carries
   `omega_PLL_pu` (`eecon49_dual_mode_model.m:253-258`,
   `gfl_eecon49_full_model.m:106`); right-limit speeds are 0.9829–0.9836,
   coherent with the running island.
4. **`K_IBR2 < 0` causes the slip** — `K=dP/ddelta` for IBR2 is negative at every
   islanded point measured (−0.016 at the certified equilibrium), yet the
   certified all-4-GFM equilibrium rides a 2.0 pu deficit with a 24.5 deg
   excursion. A negative single-unit coefficient is not sufficient for slip.
5. **IBR2 being the angle reference matters** — `ref=IBR2` and `ref=IBR6` give
   bit-comparable results (17.1 deg vs 17.1 deg at 1.3319 pu). The reference is
   an angle datum, not a physical role.
6. **Insufficient inertia (`M`)** — `M=2.5` (H_v 1.25 s) does not restore
   synchronism at the canonical deficit and degrades Newton convergence.
7. **Too many formers / a GFM-GFL mix would be better** — the opposite: all-4
   rides 2.0 pu, while 2-GFM configurations slip at 2.0 pu. Removing IBR2 from
   the forming set (`[3 4 5]`) has NO equilibrium at all (residual 3.42e+02).
8. **The +20 % load step is the trigger** — the certified all-4-GFM equilibrium
   at +20 % load rides the same ladder (15.8 deg at 1.3319 pu vs 17.1 deg at
   base load).
9. **The single-GFM window damaged the island** — during `t=25.4..50` with IBR2
   alone, `omega` is 1.000000 and flat. That window is the healthiest in the run.

## Withdrawn intermediate claims from this same investigation

Both were produced by this diagnosis and are withdrawn on later measurement in
the same session. They are recorded so no one restarts from them:

1. **"96 % of the arriving deviation is angular, therefore the angles carry the
   instability."** WITHDRAWN. The norm split (`45.45` total vs `2.01` excluding
   angles) is arithmetically correct but causally irrelevant: injecting the raw
   `-23 rad` angles alone stays synchronised at 8.6 deg.
2. **"The basin absorbs 25–40 % of the arriving deviation"** (from an
   `x_eq + alpha*(x_prod - x_eq)` ladder). WITHDRAWN — the ladder scaled
   `2*pi`-periodic angles linearly, so intermediate `alpha` values are not
   physical interpolants (halving `-23.14 rad` moves the RELATIVE angle by about
   two full turns). The ladder measured a coordinate artefact, not a basin edge.
   No basin-radius figure is claimed; the isolation above supersedes it.

## Diagnostic traps recorded

- `gfm_delta_VSG` / `gfm_omega_VSG` are FROZEN while a device is in GFL mode.
  Any metric that reads them without checking the active set reports the frozen
  seed, not physics. This is the trap in `dual-branch-frozen-state-indices`.
- Raw VSG angle differences are meaningless without `mod 2*pi`: at the commit
  IBR2 and IBR3 differ by 25.06 rad, which is 4 full turns plus 4.5 deg, i.e.
  coherent.
- `err=Inf alg_res=Inf` in the `adaptiveDtMin` message is a backward-Euler
  sentinel (`ts_simulate_ibr_hybrid:2768`), not a measured residual. The real
  per-trial reasons are in `res.rejection_history` (`newton_nonconvergence`).
- An index helper built over ALL devices must not reuse the `slot=gfm-1` offset
  intended for an SG-skipping helper; that defect produced an exact
  `max|w-1| = 1.0000` (reading `gfl_xi_PLL = 0`) in an earlier probe revision.

## Consequence for reclose

The island never re-locks frequency after `t=53.4`, so the synchronism guard
cannot be satisfied inside the 20 s window, and `reclose_status` stays
`PENDING_SYNC_FAIL`. The `t=152.017` `adaptiveDtMin` failure is a downstream
symptom: the coupled Newton cannot cross the current-reference/anti-windup
switching surface while a forming unit is slipping through it (a one-step replay
from the exact failing state converges at `h=1e-2` but not at `h<=5e-3`, worst
row `IBR6.gfm_xi_Vd` at `rawIref/Imax = 1.0000`; same class as
`TS-2026-08-13-03`).

Improving the stepper alone cannot deliver reclose: crossing the wall leaves the
island still unsynchronised.

## Candidate correction classes — NOT approved or implemented

Ranked by how directly they address the measured carrier. Each changes a
contract and requires its own reviewed plan before any implementation.

1. **Incumbent-former voltage-loop conditioning at a support transaction.**
   IMPLEMENTED AND EVALUATED — see the section below ("Correction attempt
   #1, AGSI plan"). The evaluation falsifies it as a STANDALONE fix: the
   arriving state at an early (mid-transient) commit is outside the basin
   even with the xi pair conditioned, and conditioning changes the
   supervisor's event path so the all-four commit lands 29 s earlier,
   mid-transient, where the island is still far from the certificate.
2. add a region-of-attraction / arriving-state admissibility test to support
   augmentation (selector contract change: certify the TRANSITION, not only the
   destination equilibrium). Strictly more conservative than 1: it would refuse
   the commit rather than condition it.
3. stage the augmentation (commit formers one at a time with dwell). Does not
   address the carrier directly — the incumbent's integrators stay stale at
   every stage — but reduces the per-commit operating-point jump. Needs its own
   dwell derivation and changes event ordering.
4. raise island inertia by an audited virtual-inertia sizing derivation, which
   the measured `M=2.5` arm shows is not sufficient on its own.

Class 1 alone is now falsified for this chronology (below); class 2 (or a
supervisor interlock) is the candidate next step and needs its own plan.

Ruled out by the measurements above: angle pre-alignment (angles are already
coherent to 1.3–3.0 deg and the raw angles are benign), reference reassignment,
`M`, and any GFM/GFL mix change.

Do not alter `Dv`, `M`, `Imax`, event times, dwell, timeout, the synchronism
guard, or any tolerance merely to make this arm pass.

## Correction attempt #1 (incumbent xi conditioning): implemented, gate-failed, falsified as standalone fix — 2026-08-14

Approved plan AGSI-2026-08-14-01 implemented candidate class 1 exactly as
specified: `+stability/condition_eecon49_incumbent_gfm_state.m` copies only the
two named states `gfm_xi_Vd/gfm_xi_Vq` of every incumbent EECON49 GFM from the
authenticated `candidate.eq_x0`, inside `sg_off_support_transaction`, after the
ordinary mode transfers and before the right-limit KCL, with the existing
`1e-10` terminal-current guard, an exact ownership invariant, stable failure
IDs, and atomic fail-closed rejection. `ibr_decoupled_dual` is a byte-identical
no-op. Contract evidence: 8/8 pure-helper tests
(`tests/test_ts_hybrid_support_state_conditioning.m`), 8/8 integration tests
(`tests/test_ts_hybrid_support_certified_input.m`, including fingerprint-
covered `eq_x0` tamper and missing-certificate refusals), combined targeted
regressions 50/50. No parameter, gate, threshold, event time, or tolerance was
changed. The helper code and tests remain in the working tree, UNCOMMITTED,
because their own declared acceptance gate (G6: full 250-s reclose SUCCESS)
FAILED.

### Full production run on the corrected tree: earlier failure, not reclose

Canonical 250-s adaptive chronology (`chk_g6_full_conditioned_tmp.m`, options
byte-identical to `chk_reclose_route_adaptive_tmp.m`; trajectory
`output/diagnostics/reclose_full_conditioned.mat`):

```text
sg_trip                t=20.0000   applied
gfm_support_augment    t=22.0521   [2 4],      1 incumbent conditioned (IBR2)
gfm_support_augment    t=24.0631   [2 3 4 5],  2 incumbents conditioned (IBR2, IBR6)
adaptiveDtMin          t=24.917    FAILURE (baseline failed at t=152.017)
```

Two structural facts establish that this is NOT an implementation defect:

1. **Determinism.** The baseline and post-fix runs are bit-identical in
   `t`, `x`, `y`, `u` up to the LEFT sample of the first support transaction
   (`t=22.0521`). At its RIGHT sample exactly two coordinates differ —
   `x(19)/x(20)`, IBR2's xi pair — and both equal the `[2 4]` certificate
   exactly. The divergence is purely dynamical, from the exact intended
   assignment.
2. **Replay isolation at the `t=24.0631` all-four commit** (fixed `dt=0.01`,
   no events, installed `u/ec` held):

```text
ARM A  committed right sample (xi conditioned)            SLIPS  1095 deg
ARM B  same commit, incumbents KEEP arriving xi           SLIPS  2060 deg
ARM C  no commit, continue the [2 4] island 10 s          converges, coherent (max dw 0.0078)
```

ARM B is decisive: with the conditioning UNDONE at this transaction the island
still slips. The arriving state at `t=24.06` is outside the certificate's
basin independent of the xi pair — the conditioning did not cause the slip,
and undoing it does not prevent it.

### Why the tree fails EARLIER than the baseline

The conditioning changed the supervisor's evidence, and therefore its event
path. The `[2 4]` right sample at `t=22.05` differs only in IBR2's xi, but the
supervisor consumes the post-commit trajectory, so the divergence propagates
into its J_V/J_f evidence:

```text
baseline: augment[2 4] 22.05 -> release[4] 25.31 -> [2] alone, healthy ->
          augment[2 4] 51.38 -> augment[2 3 4 5] 53.40 -> slip -> wall 152.0
post-fix: augment[2 4] 22.05 -> NO release -> augment[2 3 4 5] 24.06 ->
          slip -> wall 24.9
```

The baseline commits the all-four set onto an island that ran `[2]` alone for
~28 s and is settled; the post-fix tree commits it ~2 s after the trip
transient. Distance of the arriving algebraic state to the same `[2 3 4 5]`
certificate (bus voltage profile at the commit):

```text
post-fix t=24.06  commit: max|dV| = 0.064 pu, rms 0.041 pu  -> SLIPS
baseline t=53.40  commit: max|dV| = 0.020 pu, rms 0.007 pu  -> 4358 deg slip (stale xi)
```

So the original defect had TWO independent components, and this correction
removes only one:

- stale incumbent xi at an otherwise-ADMISSIBLE commit (fixed here; causal
  replay 4358 -> 8.6 deg at the t=53.40-class state);
- an INADMISSIBLE commit, where the arriving state is outside the basin even
  with xi taken from the certificate. The supervisor can reach this state by
  committing all-four mid-transient — which the corrected tree itself now does
  at `t=24.06`.

### Structural notes for the next attempt

- The `1e-10` current-continuity guard measures exactly `0` for this family:
  the EECON49 terminal current is the state pair `i_d/i_q` and does not depend
  on `xi_Vd/xi_Vq`. The guard is necessary and catches current-carrying
  defects, but it is structurally blind to the conditioned coordinates
  (anticipated in the plan's advisor review; it is a necessary invariant, not
  an admissibility screen).
- The plan's G5 gate (short chronology to `t=60`) is infeasible on the
  canonical chronology: `ibr_event_schedule` requires
  `fault_on < fault_clear <= t_end` (`ibr_event_schedule.m:243`), and the
  CASE_DEFINED fault is at 85/85.15 s. No `t_end < 85.15` run is schedulable
  without moving event times, which is forbidden. The G5 attempt failed
  pre-TS with verified `metadata.failure =
  'run_hybrid_case:invalidEventSchedule'` (saved in
  `output/diagnostics/reclose_short_conditioned.mat`); no numerical contract
  was weakened. The 250-s run is the only production-chronology run, so G6
  substituted for G5. **Owner ratification of this gate-sequence change is
  requested.**
- The arriving-vs-certified voltage-profile distance is a DIAGNOSTIC
  measurement, not a gate candidate: it separates the bad t=24.06 commit
  (0.064 pu) from the settled t=53.40 one (0.020 pu), but any threshold in
  `(0.020, 0.064)` would be fitted to exactly two samples of one chronology
  (threshold-tuning in disguise), and the distance alone provably misses the
  second failure component — the baseline t=53.40 commit is admissible by
  distance yet slipped on stale xi. It must not become a gate without an
  independent derivation.
- The candidate next correction (class 2) is a **simulation-based transition
  certificate**: before committing an augment, forward-simulate the committed
  candidate for a short horizon with the installed inputs held, and refuse
  fail-closed (the transaction is already atomic; refusal keeps the left
  state) if the island slips by the project's EXISTING pairwise synchronism
  criterion (<90°). It certifies the TRANSITION instead of the destination
  equilibrium and reuses an existing physics predicate instead of a tuned
  scalar. Known risks: a finite horizon is necessary-not-sufficient (not an
  RoA proof); the predictor is a new producer needing its own validation and
  fail-closed semantics; the horizon needs a derivation (e.g. bounded below
  by the synchronism dwell window); and the never-admissible path must be
  defined (the run continues in the current configuration — fail-safe, but it
  must be documented so the chronology does not silently stall). This class
  is NOT approved.
- Separately, `severity_T_d_on = 0.10 s` (the supervisor on-dwell that lets a
  0.1 s stress window trigger the mid-transient commit) needs its provenance
  classification established (CASE_DEFINED vs PROJECT_DERIVED) before ANYONE
  re-sets it; only if genuinely free may the owner set it, with a recorded
  physical derivation, never "the value that prevents t=24.06". An agent may
  not touch it.

Status: this defect remains **OPEN**. The xi-conditioning correction is
validated against its contract tests but is not delivered; reclose remains
unreachable. The working tree keeps the uncommitted helper/tests so the next
plan can build on or discard them deliberately.

### Owner decisions (2026-08-15)

1. The G5→G6 gate-sequence substitution is **ratified**: the 250-s run is the
   only production-chronology run, and no numerical contract was weakened.
2. Next correction direction: **keep the xi-conditioning helper and add the
   simulation-based transition certificate** (component 2) — forward-simulate
   the would-be committed state before commit and refuse fail-closed using the
   existing pairwise synchronism criterion. Requires its own reviewed plan.
3. `severity_T_d_on = 0.10 s`: establish provenance (CASE_DEFINED vs
   PROJECT_DERIVED) read-only before anyone touches it; report first.

### Correction attempt #2 (transition certificate): the xi conditioning is NOT universally beneficial — 2026-08-15

Implementing the class-2 certificate produced the measurement that falsifies
the class-1 premise as an UNCONDITIONAL rule. All arms below are the validated
isolated-trial harness (fixed `dt=0.01`, `linear_kcl` predictor, inputs and
event context held, live `Y`, 6 s), started from the SAME accepted right sample
of the baseline `[2 4]` support commit at `t=22.0521`:

```text
A  right sample verbatim (what baseline production integrated)
     peak 19.7 deg   omega -> 1.00017 / 1.00016    STABLE
B  incumbent xi -> [2 4] authenticated table-row eq_x0
     Newton wall at +0.240 s, peak 54.7 deg
C  incumbent xi -> [2 4] live base-load equilibrium
     peak 376.1 deg, crosses 180 deg               SLIPS
```

Only two coordinates differ between the arms (`x(19)`, `x(20)` = IBR2's
`gfm_xi_Vd/gfm_xi_Vq`).

Two conclusions follow, and the second one is the important one:

1. **The isolated trial is FAITHFUL.** Arm A reproduces the independently
   known production fact for this commit — the baseline ran `[2 4]` healthy
   from `t=22.05`, converged `omega` to `1.000000`, and released to `[2]` at
   `t=25.31` on low severity. So the certificate's forward-trial method is not
   over-rejecting; the hypothesis that the trial is unrepresentative (inputs
   held, no supervisor) is FALSIFIED.
2. **The xi conditioning moves a state that was already inside the basin OUT
   of it.** At this commit the arriving `xi` is the correct one and the
   destination-equilibrium `xi` is wrong: conditioning to the certified target
   converts a 19.7 deg stable response into a 376 deg pole slip.

This is the mirror image of the `t=53.4025` all-four commit, where the
arriving `xi` is stale and conditioning is what rescues it (4358 -> 8.6 deg).
The two commits therefore demand OPPOSITE actions, so "condition every
incumbent EECON49 GFM at every support transaction" is falsified as a
universal contract. The distinguishing variable is not yet established; the
`t=22.05` commit is a 1->2 GFM augment on a still-settling post-trip island
(`t_trip=20`, i.e. 2 s earlier) while the `t=53.40` commit is a 2->4 augment
on an island that had run `[2]` alone for ~28 s.

Consequences recorded honestly:

- Correction class 1 must NOT be delivered as an unconditional rule. Any
  future version needs a positive admissibility criterion for WHEN the
  destination `xi` is the right target, derived and validated on both commits,
  not assumed.
- The class-2 certificate as an independent gate is supported by this
  evidence: the trial faithfully separates stable from slipping arrivals
  (19.7 / 15.6 deg stable vs 376 / 1095 deg slipping) at every commit tested.
  It is the conditioning it was asked to protect, not the certificate, that
  the evidence rejects.
- The 90-degree pole-slip limit used in the first certificate implementation
  is ALSO wrong on the physics: 90 deg is the steady-state pull-out limit
  (`dP/ddelta = 0`), whereas transient loss of synchronism is bounded by the
  unstable equilibrium point (~`180 deg - delta_SEP`) under the equal-area
  criterion, and a GFM's heavily damped first swing can legitimately exceed
  90 deg and recover. Published GFM transient-stability work states the
  loss-of-synchronism condition at the UEP, not at 90 deg. The measured
  separation here (19.7/15.6 vs 376/1095 deg) is wide enough that any limit
  between roughly 120 and 500 deg gives identical verdicts on this evidence,
  so the correction is a physics fix, not threshold tuning.

Gate status for this attempt: G0 ownership PASS; G1 offline oracle PASS on the
two all-four commits (accept 15.6 deg settled, reject 93.6 deg mid-transient);
G2 certificate contract 8/8 PASS; existing support suites 16/16 PASS; G3
regressions 34/34 PASS (eecon49 dual, decoupled dual, adaptive rollback,
fixed bit-identity, support selector). G4 (full 250-s chronology, certificate
ON) was STOPPED after the certificate refused the `t=22.05` commit, which the
A/B/C measurement above then explained as a conditioning defect rather than a
certificate defect. Nothing is committed.

Also found while running G4 and not yet fixed: the live-destination
equilibrium acceptance check reported `live equilibrium did not converge
(residual 4.534e-13)` at `t=51.58` — a residual that is converged, so the
convergence flag is being read incorrectly in that helper path.

### Admissibility search for the conditioning (owner decision, 2026-08-15)

Measured at each commit's EVENT-LEFT sample (pre-commit; old configuration,
old inputs — everything the transaction can see), against the known
conditioning verdicts:

```text
commit                          R_f       R_f_gfm   dw_max    dw_pair   t-t_trip  verdict
BASE [2 4]     @22.05           3.695e+0  3.317e+0  0.008798  0.000000   2.052    HARMFUL
BASE release [2] @25.31         5.425e-1  1.289e-1  0.000342  0.000018   5.310    healthy
BASE [2 4]     @51.38           3.252e+0  2.876e+0  0.007629  0.000000  31.383    healthy
BASE [2 3 4 5] @53.40           6.443e+0  6.280e+0  0.016657  0.000267  33.403    HELPS
POST [2 3 4 5] @24.06           2.948e+0  2.948e+0  0.007820  0.003910   4.063    insufficient
```

**Hypothesis H_qs ("conditioning is admissible only when the arrival is
quasi-steady for the old configuration") is FALSIFIED.** The dynamic residual
is LARGEST (`R_f = 6.44`) exactly where conditioning HELPS, and smaller
(`3.70`) where it HARMS; `dw_max` orders the same wrong way (0.0167 helps vs
0.0088 harms). Neither a dynamic-residual nor a speed-deviation
quasi-steadiness test can be the criterion.

Best discriminator found — the outer-loop PI internal consistency at the left
sample (`kiV = 4.50`, the `gfm_eecon49_full_model` default; at the PI's own
equilibrium `xi_Vd = i_d/kiV`, `xi_Vq = i_q/kiV`, `E = |V|`):

```text
commit                unit  |E-|V||    |xiVd*kiV-id|  |xiVq*kiV-iq|  verdict
BASE [2 4]   @22.05   IBR2  0.001051   0.001215       0.009161       HARMFUL
BASE [2345]  @53.40   IBR6  0.003394   0.003883       0.021982       HELPS
BASE [2345]  @53.40   IBR2  0.009908   0.012716       0.043404       HELPS
POST [2345]  @24.06   IBR6  0.033307   0.033186       0.134003       insufficient
POST [2345]  @24.06   IBR2  0.039687   0.047334       0.035585       insufficient
```

The ordering is monotone and physically readable: an integrator that is
ALREADY consistent with its own terminal condition carries no stale wind-up,
so re-seeding it injects a spurious current-reference step (HARMFUL); a
moderately wound-up integrator is the case the conditioning was designed for
(HELPS); a grossly wound-up one sits on a physical state that is itself far
outside the basin, so re-seeding two coordinates cannot rescue it.

**But the margin is too tight to declare a derived threshold.** Between
HARMFUL (`0.00122`) and the nearest HELPS (`0.00388`, IBR6) there is only a
factor of `3.2`, on two samples of one chronology. Fitting a limit into that
gap is precisely the threshold-tuning that was already rejected for the
voltage-distance screen. No admissibility threshold is therefore claimed.
`dw_pair` does separate the two all-four commits by `15x`
(`0.000267` settled vs `0.003910` mid-transient) but is trivially `0` when
only one device is GFM before the commit, so it cannot rule on `t=22.05`.

**Independent feasibility finding:** at `+20 %` load the `[2 4]`
configuration has NO equilibrium (coupled Newton residual `1.961e+01`,
non-convergent), while `[2 3 4 5]` converges to `1.579e-10` with physical KCL
`6.97e-11`. So after the load step the two-GFM support set is infeasible and
only the all-four set can be certified.

**Correction to the note above** (recorded rather than silently edited): the
`residual 4.534e-13` message was NOT a convergence-flag misread.
`mixed_equilibrium_solve` sets `converged = false` from gates DOWNSTREAM of
the Newton loop — reduced-Jacobian conditioning (`rcond < 1e-10`), the
physical all-row KCL gate (`>= 1e-6`), and device/reference limit checks — so
a tiny Newton residual can legitimately accompany `converged = false`. The
refusal was a correct fail-closed on a real gate; the DEFECT is in the
diagnostic message, which printed the Newton residual and therefore
misattributed the cause. The message must report `failure_id`/`failure_reason`
instead.

### Advisor review (independent read-only review, 2026-08-14)

An independent advisor review verified the verdict from source: helper and
call site match the plan contract point-for-point; the driver diff is
confined to `sg_off_support_transaction`; the supervisor path change is an
emergent consequence of an unconditional contract (`severity_T_d_on=0.10`
plus evidence-driven J_V/J_f), not an implementation choice; ARM B is the
decisive experiment; no missed in-scope defect was found; do NOT commit the
gate-failing correction (it would publish an observable regression of the
production chronology from t=152 s to t=24.9 s). The review's two caveats,
both incorporated above: (1) the G5→G6 substitution is a plan deviation the
owner should ratify; (2) the voltage-distance screen cannot stand as a gate,
and the class-2 simulation-based transition certificate is the preferred next
mechanism with the risks listed above. Evidence asymmetry disclosed: the
baseline `t=152.017` failure number comes from the baseline script's stdout
and this record, while the post-fix `t=24.917` appears explicitly in
`output/diagnostics/reclose_full_conditioned_progress.log`; ARM A/B wall
times are fixed-dt replay numbers valid for A/B/C comparison only, not
predictions of production failure timing.

### Correction attempt #3 (trial-as-oracle, least-intervention-first) — 2026-08-15

Owner decision after the admissibility search came back inconclusive: use the
forward trial itself as the decision oracle, because no static threshold is
defensible on the available evidence (best discriminator margin 3.2x) while the
trial is independently validated.

Design now in the working tree:

- `sg_off_support_transaction` evaluates TWO candidate right states and lets
  the governing equations choose:
  1. the arrival exactly as the ordinary transfer maps leave it (UNTOUCHED);
     if the trial rides it, COMMIT IT — never perturb a state already inside
     the destination basin;
  2. only if the untouched arrival fails, the incumbent-conditioned variant
     (the stale-wind-up case conditioning was designed for);
  3. if neither rides, REFUSE fail-closed through the existing atomic
     machinery (no right sample, lockout + fresh dwell before any retry).
- With the option OFF (default) there is NO conditioning and NO trial, so the
  default path is byte-identical to pre-AGSI-2026-08-14 `main`. The falsified
  unconditional conditioning is therefore not a production behaviour at all;
  it exists only where the trial can judge it.
- An unavailable conditioning target (no incumbent, faulted network, or no
  solvable live destination equilibrium) marks only the VARIANT unavailable,
  never the transaction refused — necessary because `[2 4]` has no equilibrium
  at +20 % load while its untouched arrival is perfectly admissible.
- Slip limit corrected 90 -> 180 deg (unstable-equilibrium separation).
- The live-equilibrium diagnostic now reports `failure_id`/`failure_reason`
  instead of the Newton residual.

G1 re-run on the corrected design — the oracle reproduces every
independently-known outcome and picks the right ACTION at each commit:

```text
commit                  untouched (A)        conditioned (B)      decision
[2 4]     @22.05 base   19.7 deg   PASS      (not needed)         commit untouched
[2 3 4 5] @53.40 +20%   195.1 deg  reject    15.6 deg  PASS       commit conditioned
[2 3 4 5] @24.06 base   188.0 deg  reject    194.0 deg reject     REFUSE
```

The `t=22.05` row is the one that matters for faithfulness: the baseline
production run committed that transition and stayed healthy, and the oracle now
commits it untouched, as production did.

Test status on this tree: 25/25 (9 certificate contract, 8 conditioning helper,
8 certified-input) and G3 regressions 34/34.

Cosmetic defect noted during G4 (not fixed mid-run): on the trivial-accept path
(`fewerThanTwoFormers`, e.g. a release down to a single former, where there is
no pairwise relation to protect) the audit carries `horizon=NaN, steps_run=0`,
so the success log prints `horizon=NaN s, 0 steps`. The verdict is correct; the
message is misleading and should report the trivial-accept reason instead.

Two tests that this attempt CORRECTED, with the reason each was wrong (both
were authored during correction attempt #1, and both encoded the unconditional
conditioning contract that measurement falsified):

- `test_support_augmentation_runs_its_certificate`: the class-1 extension
  asserting the incumbent `xi` equals the table-row `eq_x0` at the right sample
  was removed. The pre-existing certified-INPUT pairing assertions
  (RECLOSE-2026-08-13-01) are untouched and still enforced.
- `test_malformed_reauthenticated_state_fails_closed_at_support` became
  `test_default_path_does_not_depend_on_eq_x0`: a missing destination-state
  certificate must NOT refuse the default path, because that path never
  consults `eq_x0`. The replacement is strictly stronger — it asserts the run
  is byte-identical (`t`, `x_traj`, `u_history` at `AbsTol=0`) to the
  intact-table run, proving `eq_x0` is not a hidden dependency. The `eq_u_eq`
  fail-closed contract and both fingerprint-tamper refusals remain unchanged.

#### Defect found BY G4 in the new code: live-network load multiplier — 2026-08-15

The first G4 attempt on the corrected design reproduced the baseline path exactly
through `t=51.38`, then refused the all-four commit at `t=53.4025` with the
conditioned variant measuring **184.61 deg** — where the G1 oracle, on the same
arriving right sample, had measured **15.6 deg**. Identical arriving state with a
different verdict proves the conditioning TARGET differed, not the trial.

Cause: `sched.load_step_factor = 0.20` is the DELTA applied to the base load
admittance (`Yload_delta = factor*Yload_base`, driver `:53-55`), but the new
bookkeeping passed the raw factor as the load MULTIPLIER, so
`live_destination_candidate` solved the destination equilibrium at 20 % of base
load instead of 120 %. Conditioning the incumbent `xi` toward a 20 %-load
equilibrium injects the wrong current reference and slips the island.

A second omission was found by inspection at the same time: the
`topology_restore` case restored `Ycandidate = Ypre` (base loads AND the tripped
branch) but did not reset the bookkeeping, so any certificate after `t=145`
would have solved its destination equilibrium on a network that no longer
existed.

Fix (`+stability/ts_simulate_ibr_hybrid.m`): `load_mult = 1+sched.load_step_factor`
at `load_step` (`:575`), and `load_mult=1.0; chronology_line_open=false` at
`topology_restore` (`:602`).

Isolated verification (`chk_loadmult_fix_tmp.m`, same arriving state, same
certificate, only the multiplier varied) — the arithmetic alone accounts for the
whole discrepancy:

```text
conditioning target solved at load_mult=0.20   ok=0  peak=184.61 deg   <- reproduces the G4 symptom
conditioning target solved at load_mult=1.20   ok=1  peak= 15.56 deg   <- matches the G1 oracle (15.6)
```

This is recorded as a defect in the correction itself, not in the pre-existing
model: it was introduced by attempt #3's live-network bookkeeping and was caught
by the predeclared full-chronology gate rather than by any targeted test, because
no targeted test exercises a support commit after a `load_step`.

#### G4 outcome on the fixed tree: reclose REACHED and SUCCEEDED; horizon not reached — 2026-08-15

Full canonical chronology, 250 s, adaptive stepper, certificate ON, helper
present. Artefact `output/diagnostics/reclose_cert_full.mat`, wall 1121.3 s.

Every support transaction and the reclose, as logged:

```text
t= 22.0521  augment [2 4]      APPLIED  unconditioned   19.681 deg  (horizon 5.897 s, 590 steps)
t= 25.3100  release  [2]       APPLIED  trivial accept  (single former, no pairwise relation)
t= 51.3831  augment [2 4]      APPLIED  unconditioned   36.168 deg
t= 53.4025  augment [2 3 4 5]  APPLIED  CONDITIONED     15.562 deg  (horizon 6.416 s, 642 steps)
t= 85/85.15 fault on/clear     integrated on the four-former island
t=110       line_trip          applied
t=145.0000  topology_restore + sg_on (reclose request accepted, dwell monitored)
t=146.2492  release  [2]       APPLIED   (3 devices transitioned)
t=148.2666  augment [2 4]      APPLIED  unconditioned   14.300 deg
t=152.3934  release  [2]       APPLIED   <- past the baseline failure point (152.017)
t=159.3436  sg_reclose         APPLIED  "SG SG1 reclosed; reference owner -> SG (island 1)"
            requested_sg_on=145  actual_reclose=159.3436  status=SUCCESS
t=174.5416  TERMINATED         ts_simulate_ibr_hybrid:adaptiveDtMin
```

What this establishes:

1. **The two-component decomposition was correct, and the trial-as-oracle form
   of the correction works on the production chronology.** The `t=53.4025`
   all-four commit — the transaction this whole defect is about — is APPLIED for
   the first time, and it is applied because the oracle rejected the untouched
   arrival (195.1 deg) and accepted the conditioned one (15.562 deg, matching
   the offline G1 measurement of 15.56 deg).
2. **Least-intervention-first is doing real work, not decoration.** Four of the
   five certificate-bearing commits are committed UNTOUCHED. Conditioning is
   applied at exactly one transaction in 250 s — the stale-wind-up case it was
   derived for. The falsified unconditional rule never runs.
3. **Reclose is reachable and the guard closes on merit.** All three synchronism
   sub-gates hold positive margin at the close (`dV` 0.004743 vs 0.05,
   `df` 1.59e-05 vs 0.001, `dtheta` 0.9677 deg vs 10 deg, `limiting_gate=none`),
   inside the unchanged 20 s timeout. Nothing was relaxed to obtain it.
4. **The reclose reproduces under a second, independent integrator.** Re-running
   the same chronology with `stepper='fixed'` also recloses successfully, at
   `t=157.4500`, so the result does not depend on the opt-in adaptive stepping:

   ```text
                   reclose (SUCCESS)   terminated    failure_id
   adaptive          t=159.3436        t=174.5416    adaptiveDtMin  (err=Inf)
   fixed             t=157.4500        t=170.9500    stepNewton     (residual 1.390e-04)
   ```

   At `t=53.4025`/`t=53.4000` both runs commit the all-four configuration with the
   CONDITIONED variant (15.562 deg adaptive, 14.916 deg fixed), i.e. the decision
   the oracle makes is stepper-independent too.

What this does NOT establish, stated plainly:

5. **The predeclared G4 gate is NOT satisfied by THIS run.** Outcome (a) required
   reclose SUCCESS *and* a completed 250 s run; outcome (b) required a
   certificate refusal *and* a completed run. This run is neither: it terminates
   at `t=174.5416`, 15.2 s after the reclose, with `err=Inf alg_res=Inf` at
   `dt_min=6.1e-06`.
6. The new failure is in a different subsystem and was recorded separately as
   `RECLOSE-2026-08-15-01`. It has since been **root-caused and fixed** (the
   post-reclose field-voltage command was walked over the destination mode's
   decay time instead of the declared actuator-lag response time), and with that
   correction the same chronology completes. See the G4 re-run below.

### G4 SATISFIED after RECLOSE-2026-08-15-01 — outcome (a) — 2026-08-15

Same chronology, correctly-dispatched selector table, certificate ON, plus
`handback_efd_timescale='control'` from `RECLOSE-2026-08-15-01`:

```text
conv=1  t_end=250.000000  failure_id=[]  wall=533.4 s
requested_sg_on=145   actual_reclose=159.3436   status=SUCCESS
terminal: f_coi=60.000000 Hz  bus |V| 0.9667..1.0575  handback C1_COMPLETE
          reselection_status=NO_FEASIBLE_SG_ON_ONE_STEP  (correct fail-closed)
          rejected_steps=137  floor_accepted_steps=0
```

Every support decision is unchanged from the runs above — same times, same
variants, same excursions — so the excitation-timescale correction does not
perturb any transition this defect is about. In particular the `t=53.4025`
all-four commit is still `variant=conditioned` at `15.562 deg`.

The terminal state reproduces the published EECON49 Figure-4 operating point,
which is an oracle neither correction touches: SG1 `134.62 MVA`, IBR
`36.31 / 33.02 / 50.86 / 30.64 MVA` at buses 2/3/6/8, and IBR2's terminal current
`0.36623` against its certified equilibrium value `0.366232`.

**Therefore `AGSI-2026-08-14-01/02` are RESOLVED:** the all-four-GFM support
commit is applied on the production chronology, SG reclose succeeds, and the run
completes to the declared horizon.


Gate ledger for this attempt: G0 ownership/baseline clean (HEAD `f786f0d` ==
`origin/main`, only allowlist files touched) · G1 oracle PASS (all three commits
get the right action) · targeted suites 25/25 PASS re-run after the `load_mult`
fix (9 certificate + 8 conditioning + 8 certified-input) · G3 regressions 34/34
PASS · **G4 NOT satisfied** as above. Full repository regression not run; it is
optional per repository policy and the targeted gates above cover the changed
producer and its consumers.

## Related files

- `+stability/ts_simulate_ibr_hybrid.m` (`:2305` support transaction, `:2367`
  certified-input install, `:2768` BE sentinel, `:575`/`:602` live-network
  bookkeeping for the destination equilibrium)
- `+stability/select_support_augmentation_candidate.m`
- `+stability/ibr_candidate_evaluate.m`
- `+ibr/eecon49_dual_mode_model.m` (`:230-291` transfer maps)
- `docs/project/defects/2026-08-13-dv20-post-line-nonsmooth-newton-wall.md`
- `docs/project/defects/2026-08-13-islanded-vsg-inertia-reclose-unreachable.md`
