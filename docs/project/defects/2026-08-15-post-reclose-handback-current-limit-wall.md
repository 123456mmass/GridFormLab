# Post-reclose handback ramp hits a Newton/algebraic wall while the only GFM is current-limited

- **ID**: `RECLOSE-2026-08-15-01`
- **Status**: `RESOLVED`
- **Discovered**: 2026-08-15, by the predeclared G4 full-chronology gate of
  `AGSI-2026-08-14-02` (the first run that ever reached SG reclose on the
  IEEE14 EECON49 production chronology)
- **Resolved**: 2026-08-15 — the post-reclose FIELD-VOLTAGE command was being
  walked over the destination mode's decay time instead of the declared
  actuator-lag response time. With `handback_efd_timescale='control'` the
  canonical 250-s chronology completes with `reclose_status='SUCCESS'` and
  converges to the published EECON49 operating point. See "Resolution" below.
- **Branch / tested tree**: `main`, working tree on top of `f786f0d`
- **Environment**: Windows 11, MATLAB `-batch`, project-owned solvers only

## Scope and evidence boundary

This record is about what happens AFTER the SG recloses. It is a different
subsystem from `AGSI-2026-08-14-01/02` (the SG-off support transaction and its
transition certificate), which is what made this region reachable at all. No
correction is proposed here and nothing was tuned; the record exists so the
owner can decide who fixes it and how.

## Symptom

The 250 s chronology now reaches SG reclose and succeeds:

```text
requested_sg_on = 145.000     actual_reclose = 159.3436     status = SUCCESS
```

but the run then terminates at `t = 174.541585` without reaching the 250 s
horizon:

```text
failure_id     = ts_simulate_ibr_hybrid:adaptiveDtMin
failure_reason = Adaptive step could not satisfy the DAE at dt_min=6.104e-06,
                 t=174.541585 (err=Inf alg_res=Inf converged=0,
                 backward-Euler rescue attempted). No silent fixed-step fallback.
```

The previous baseline on the same chronology failed at `t = 152.017`, i.e.
BEFORE the reclose window, so `t > 152` is territory this project had never
integrated before. This is a newly-exposed failure, not a regression of a
previously working path.

## Reproduction

```matlab
pf_init_paths();
chk_g4_certificate_full_tmp   % scratch driver; canonical chronology + certificate ON
```

Result artefact: `output/diagnostics/reclose_cert_full.mat`
Progress log: `output/diagnostics/reclose_cert_full_progress.log`
Forensics used below: `chk_g4_divergence_tmp.m` (read-only; scratch, not committed).

## Observations (measured, no inference)

1. **The system is RECOVERING when Newton fails, not diverging.** The bus
   voltage minimum dips to `0.6920 pu` at `t=166.58` and has recovered to
   `0.9149 pu` by the failing step; COI frequency peaks at `61.891 Hz` at
   `t=166.58` and has fallen back to `60.2320 Hz`. No state is non-finite at
   the last accepted sample.

   ```text
   t          min|V|    f_coi(Hz)   SG1_P(pu)   SG1_Q(pu)
   159.044    0.9795     60.001       0.000      0.000
   163.832    0.7672     61.408      -0.057     -0.979
   166.582    0.6920     61.891       0.385     -0.564
   169.332    0.7506     61.314       0.966     -1.018
   174.542    0.9149     60.232       1.224     -1.125
   ```

2. **The sole remaining GFM is pinned exactly on its current limit for the
   whole handback window.** IBR2 reaches `|I| = 1.2006` at `t=161.05` and then
   reads `|I| = 1.20000` against `Ilim = 1.20000` at every sampled instant from
   `t=163.83` through the failure — about 13.5 s of continuous saturation.

   ```text
   dev          159.044   161.049   163.832   166.582   169.332   172.132   174.542
   IBR2 |I|     0.32605   1.2006    1.2000    1.2000    1.2000    1.2000    1.2000
   IBR2 lim     1.2       1.2       1.2       1.2       1.2       1.2       1.2
   IBR3 |I|     0.74843   0.7635    0.81255   0.74592   0.60497   0.42038   0.36048
   IBR6 |I|     0.85790   0.8770    0.93642   0.93240   0.76233   0.56729   0.50633
   IBR8 |I|     0.69464   0.70472   0.73890   0.71918   0.53556   0.36065   0.30827
   SG1  |I|     0.00000   1.2202    1.2779    0.81625   1.4496    1.8048    1.8171
   SG1  lim     NaN       NaN       NaN       NaN       NaN       NaN       NaN
   ```

   The three GFL devices are far from their limits and unloading. Only IBR2 is
   saturated, and the SG carries no current limit in this model (`lim = NaN`).

3. **The failure sits 0.24 s inside the handback ramp.**

   ```text
   handback_status = C1_ACTIVE
   handback_start_time = 159.343560     (= the reclose instant)
   handback_duration_s = 15.439096
   => scheduled completion  174.782656
   failure                  174.541585   (0.2411 s before completion)
   handback_complete_time = NaN
   ```

4. **Step-size reduction does not help; the failure is Newton
   non-convergence.** The adaptive stepper walks `dt` from `5.0e-02` down to
   `6.1035e-06` — a factor of ~8200 — and the last seven rejection records all
   read `reason = newton_nonconvergence` at the same `t = 174.542`. Backward-Euler
   rescue was attempted and also failed.

   ```text
   k      dt          lte         residual    iter
   3472   0.05        0.041761    7.0929e-11   13
   3473   0.00625     0.0017112   1.9022e-09   75
   3476   4.7684e-05  4.0791e-10  9.3620e-14  145
   3479   6.1035e-06  3.0025e-06  7.0794e-09   64
   ```

   Newton iteration counts had already been climbing after the reclose
   (`iter = 7-9` before it, then `13 -> 19 -> 16` at `t = 161/166/171`).

5. **Configuration at the failure**: `SG1 = sg` online, `IBR2 = GFM` online,
   `IBR3/IBR6/IBR8 = gfl` online; `reference_owner_indices = 1` (the SG owns
   the reference), `gfm_reference = NaN`, topology `restored`,
   `reselection_status = PENDING_SEVERITY` (post-reclose mode reselection had
   not fired).

6. **The reclose itself was clean**, with margin on every sub-gate — this is not
   a marginal or forced close:

   ```text
   t=159.344  good_since=158.844
   dV     =0.004743   margin_V     =0.045257
   df     =1.5916e-05 margin_f     =0.000984
   dtheta =0.9677 deg margin_theta =9.0323 deg
   signed_margin=0.000984   limiting_gate=none
   ```

## Diagnostic-harness defect found while investigating this record (2026-08-15)

**The runs that produced every measurement above were driven with a selector
table certified at the WRONG dispatch.** This is a defect in the scratch driver,
not in production, but it invalidates several inferences that were drawn from
those runs, so it is recorded before the analysis that depends on it.

`+stability/ibr_config_selector.m:305-320` resolves a scenario dispatch only via
`scenario.config.dispatch` or `scenario.scenario_opt.dispatch`. The driver
`chk_g4_certificate_full_tmp.m:29-30` passed `s.scenario_opt` **as** the
`scenario` argument, so neither key resolved (`s.scenario_opt.scenario_opt` does
not exist) and every SG_ON row was evaluated with all four IBR `P_ref = 0`, the
online SG absorbing the entire 2.59 pu of load as a solved slack unknown.

Production is NOT affected: `+stability/run_hybrid_case.m:410-411` passes the
full `scenario` struct, so the production route builds the table correctly. The
defective table reached the failing run only because the driver injected it via
`opt.selector_table`.

Arithmetic proof that the failing run used the defective table: it recorded
`handback_duration_s = 15.439096`, and `ln(1/0.05)/15.439096 = 0.194036`, which
is exactly the mis-dispatched `[2]` row's `omega = -0.194035`. The correctly
dispatched `[2]` row gives `omega = -0.215905` and hence `T = 13.875225 s`.

Measured side-by-side (`chk_table_dispatch_probe_tmp.m`, four predictions
declared before running, all four confirmed):

```text
row      BROKEN (scenario=s.scenario_opt)        FIXED (scenario=s)
         omega      ready  SG Tm   IBR P_ref     omega      ready  SG Tm   IBR P_ref
[]       -0.114317    1    2.5464  0 0 0 0       -0.065196    0    1.3319  0.31718 0.28844 0.44428 0.26765
[2]      -0.194035    1    2.6128  0 0 0 0       -0.215905    1    1.3319  0.31718 0.28844 0.44428 0.26765
[2 3 4 5]-0.205022    1    2.7282  0 0 0 0       -0.230765    1    1.3319  0.31718 0.28844 0.44428 0.26765
```

Three consequences, two of which REVERSE earlier statements in this record:

1. **REVERSED — "the ramp aims away from the certified operating point."** At the
   correct dispatch the `[2]` row's `eq_u_eq` is
   `[1.33190 0.98917 0.31718 0.17674 0.99145 0.28844 0.16073 0.96673 0.44428 0.24757 1.05753 0.26765 0.14915 1.04937]`,
   which equals `sync_ctl.target_u` in every entry. The ramp aims exactly at the
   certified point of the configuration it is running. The 1.28 pu discrepancy
   reported earlier was entirely an artefact of the defective table.
2. **REVERSED — "all-GFL is certified, so releasing IBR2 is admissible."** At the
   correct dispatch the all-GFL SG-online row FAILS the frozen margin
   (`omega = -0.0652` against `gamma_req = 0.10`, `failure_id
   stability:ibr_candidate_evaluate:insufficientRobustMargin`). The statement in
   `SWITCH-2026-08-10-03` that "automatic handback must retain the minimum
   authenticated GFM subset rather than force all four IBRs to GFL" therefore
   still holds, and **releasing IBR2 is not an available fix**.
3. **CONFIRMED and strengthened — the target is source-defined.** Computing the
   apparent power per device from `target_u` gives 0.3631 / 0.3302 / 0.5086 /
   0.3064 pu at buses 2/3/6/8 and `P = 1.3319` at bus 1, matching the published
   EECON49 figure's 36.31 / 33.02 / 50.86 / 30.64 MVA and 134.62 MVA to four
   significant figures. The ramp's destination is the published operating point.

### The certified equilibrium contains no reactive fight at all

At the correctly-dispatched `[2]` row's own equilibrium, every IBR terminal
voltage equals its frozen `E_ref` exactly:

```text
bus    |V| at eq_y0     E_ref (eq_u_eq)     difference
2      0.991447         0.991447            0.000e+00
3      0.966733         0.966733            0.000e+00
6      1.057535         1.057535            0.000e+00
8      1.049367         1.049367            0.000e+00
bus 1  1.000000  (= the case REF voltage setpoint)
```

Since `Q = Q_ref + (kE/kQ)*(E_ref - |V|)` (see the GFM mechanism section), a zero
voltage error means the certified point demands no circulating reactive power
whatsoever. **The destination is consistent; the failure is on the path to it,
not at it.** This also removes `E_ref` staleness as the primary explanation: at
this equilibrium the frozen `E_ref` values are precisely the correct ones.

## Inference (clearly separated from the observations above)

- `alg_res = Inf` together with `dt`-insensitivity is the signature of an
  **algebraic** problem, not a stiffness problem: the algebraic constraints must
  hold at the new time whatever `dt` is, so shrinking `dt` cannot recover
  feasibility. This points at the algebraic manifold rather than the
  integrator.
- SG1 at `|I| = 1.8171` with `P = 1.2243`, `Q = -1.1245` (so `|S| ~ 1.66 pu`) is
  heavily loaded, and the model gives the SG no current limit. Whether that is
  physically intended for this case is a separate question for the owner.

### The ramp reaches its endpoint, so the infeasibility is essentially AT the target

The handback is an **open-loop** trajectory: `stability.c1_smoothstep(t, t0, T)`
produces `alpha(t)` from time alone, with no feasibility check, and `alpha`
interpolates three things simultaneously (`ts_simulate_ibr_hybrid.m:3798-3818`):

```text
Pref  : Pref_start  -0.00013497  ->  Pref_target  1.3319044     (governor Pmax = Tmax = 1.3462)
Efd   : Efd_start    0.16992     ->  Efd_target   0.98917
u(handback_indices = [3 4 6 7 9 10 12 13]) : handback_start_u -> target_u
        e.g.  0.72373 -> 0.28844 ,  0.87957 -> 0.44428 ,  0.70294 -> 0.26765
```

so the ramp restores the SG to its full pre-event dispatch (`1.3319044 pu`,
98.9 % of the governor's `Pmax`) while roughly halving the IBR real-power inputs.

At the failing step the ramp is late but NOT at its endpoint, and the two
steppers disagree on how late:

```text
adaptive stepper : alpha = 0.99927619   (linear fraction 0.984386)
fixed    stepper : alpha = 0.95663901   (linear fraction 0.874404)
```

Because the two runs break at materially different `alpha`, the failure is NOT
pinned to the ramp endpoint and cannot be attributed to the target dispatch
alone. An earlier draft of this record inferred "the DAE loses solvability at the
commanded target"; the fixed-stepper run falsifies that specific claim. What both
runs share is the late-ramp region, not a single `alpha`.

### Confirmed under a second, independent stepper

The same chronology was re-run with `stepper='fixed'`
(`chk_g4_fixed_stepper_tmp.m`, artefact `reclose_cert_fixed.mat`). Both steppers
reach the reclose and both break in the same post-reclose window:

```text
                reclose (SUCCESS)   terminated    failure_id
adaptive          t=159.3436        t=174.5416    ts_simulate_ibr_hybrid:adaptiveDtMin
fixed             t=157.4500        t=170.9500    ts_simulate_ibr_hybrid:stepNewton
                                                  (residual 1.390e-04 at t=171.000)
```

This settles the open hypothesis: the obstruction is NOT an adaptive-stepper
artefact. It also independently reproduces the reclose SUCCESS under a second
integrator.

### The primary mechanism: two voltage-forming sources fighting, measured

In BOTH runs the SG absorbs almost exactly the reactive power the surviving GFM
injects:

```text
                SG1 Q (pu)   IBR2 Q (pu)   SG1 |I|    IBR2 |I| / lim
adaptive         -1.12450      +1.12490     1.81710    1.20000 / 1.20000
fixed            -1.14041      +1.12356     1.76838    1.20000 / 1.20000
```

At the same time the SG owns the reference (`reference_owner_indices = 1`,
`gfm_reference = NaN`) while IBR2 is still in GFM mode — so two voltage-forming
sources are on the network simultaneously. The near-exact antisymmetry of their
reactive powers (`-1.1245` vs `+1.1249`; `-1.1404` vs `+1.1236`) is the measured
signature of reactive circulation between two sources that disagree on terminal
voltage, and IBR2 reaches its current limit sustaining it. Saturation onset is
`t=162.50` in the fixed run (170 consecutive samples to the failure) and
`t~161.05` in the adaptive run.

Stated as inference: the surviving GFM should have been returned to GFL once the
SG took the reference, and the reactive fight persists because it was not.

### An ordering constraint locks the relief mechanism behind the ramp

The mode reselection that would release IBR2 from GFM back to GFL — the action
that would end the fight described above — is gated on the handback having
completed (`ts_simulate_ibr_hybrid.m:1078-1081`):

```matlab
hold_ok = isfinite(actual_reclose) && ...
    t-actual_reclose >= settings.T_minimum_hold-settings.event_tol && ...
    sync_ctl.handback_complete;
if hold_ok && ~isempty(release)
```

Measured controller state at the failure, IDENTICAL in both runs:
`handback_complete = 0`, `handback_complete_time = NaN`,
`handback_status = C1_ACTIVE`, `reselection_status = PENDING_SEVERITY`. So
`hold_ok` is false and the release branch is never entered.

The resulting structure is an ordering deadlock, stated as inference: the ramp
that stresses the island must finish before the mechanism that would relieve the
stress is allowed to act, and the ramp cannot finish while the stress persists.
This is a structural observation about the gating order; it does not by itself
prove that releasing IBR2 earlier would restore feasibility, which remains
untested.

- Remaining unknown: the exact expression that overflows to `Inf` in the adaptive
  run. Note the fixed run reports a finite stalled residual (`1.390e-04`)
  instead, so `Inf` is a symptom of the adaptive path's deep subdivision rather
  than the primitive cause.
- A decisive next test would be to ask whether the post-reclose configuration
  (SG1 online and owning the reference, IBR2 still GFM, IBR3/IBR6/IBR8 GFL) has
  ANY equilibrium on the restored network at the target dispatch. If it does not,
  the fix belongs to the reselection ordering rather than to the integrator.

## Falsified / open hypotheses

- NOT "a state ran away": every state is finite and the voltage/frequency
  excursion is recovering at the failing step (observation 1).
- NOT "the reclose was forced through a marginal guard": all three sub-gates
  had positive margin (observation 6).
- NOT "the transition certificate refused something and starved the island":
  every support transaction in the run was APPLIED, and the last one is 22 s
  before the failure (`t=152.393`).
- FALSIFIED "adaptive-stepper-specific breakdown": the fixed stepper reaches the
  same reclose and breaks in the same post-reclose window
  (`t=170.9500`, `stepNewton`, residual `1.390e-04`). Two independent
  integrators, same region, same saturated-GFM and reactive-circulation
  signature.
- FALSIFIED (an earlier draft of this record) "the DAE loses solvability at the
  commanded target dispatch": the two steppers break at materially different
  ramp positions (`alpha = 0.9993` vs `0.9566`), so the failure is not pinned to
  the endpoint.
- OPEN: whether the post-reclose configuration with IBR2 still in GFM has any
  equilibrium at the target dispatch on the restored network.
- OPEN: the exact expression producing `Inf` on the adaptive path. The fixed path
  stalls at a finite residual instead, so `Inf` is likely a consequence of deep
  subdivision rather than the primitive cause.

## Consequence

The `AGSI-2026-08-14-02` G4 gate outcome is therefore NEITHER of its two
predeclared acceptable outcomes: reclose SUCCESS was achieved, but the run did
not reach the 250 s horizon, so it is not outcome (a); and the certificate did
not refuse anything, so it is not outcome (b). Per that plan's own G5 rule, the
certificate is NOT committed on this evidence and the owner decides.

## Resolution (2026-08-15)

### Root cause

`derive_handback_duration` (`+stability/ts_simulate_ibr_hybrid.m:2334-2352`)
returns ONE duration

```matlab
t_mode    = log(1/rho)/(-c.omega);                                  % 13.875 s here
t_control = -log(rho)*max([sync_ctl.Tsv sync_ctl.Tch sync_ctl.TA]);  %  1.198 s here
T         = max([settings.T_minimum_hold, t_mode, t_control]);        % 13.875 s
```

and `enter_online_governor` used it for EVERY post-reclose command, including the
field voltage. The SG therefore walked `Efd` from the OFFLINE synchronizer value
`0.169925` to the certified online value `0.989169` over 13.875 s — the
destination mode's 95 % decay time, which is **11.6x** the 95 % response time of
the machine's own declared exciter/governor lags (`Tsv=0.2, Tch=0.4, TA=0.02`).

Consequences, in the order they were measured:

1. The SG is under-excited for the whole ramp and absorbs reactive power
   (`Q_SG = -1.1245 pu` at the wall, against `-0.1957 pu` at its equilibrium).
2. IBR2, the only remaining former, holds its terminal voltage against that, so
   its voltage-loop q-axis integrator overshoots its equilibrium value by 5.3x:
   `xi_Vq` goes `-0.0147` (arriving) -> `-0.2114` (at the wall) where the
   equilibrium is `-0.0396`.
3. `|I_ref| = |kiV*[xi_Vd; xi_Vq]| + kpV*e` reaches the circular limit
   `Imax = 1.2`, so `conditional_hold` (`+ibr/gfm_eecon49_full_model.m:127-128`)
   freezes both voltage integrators. Measured: `xi_Vd`/`xi_Vq` are constant to
   six significant figures for the last 12 s. The voltage error never reverses
   sign, so the loop can never unwind.
4. With the former degenerate to a fixed-magnitude current source, the coupled
   algebraic system loses solvability late in the ramp and Newton fails at any
   step size.

### Why it is not a solver problem

Four production runs, differing only in numerical settings, fail at essentially
the same point:

```text
arm                                   reclose      terminated    failure_id
baseline adaptive                     159.3436     173.005724    adaptiveDtMin
E1 fd_perturbation='scaled'           159.3436     173.005776    adaptiveDtMin
E2 reject_limit=40                    159.3436     173.005724    adaptiveDtMin   (bit-identical)
E3 stepper='fixed', dt=0.02           158.9200     172.580000    stepNewton
```

Changing the FD perturbation rule, the rejection budget, the integrator and the
nominal step all leave the wall in place. Two adaptive runs with DIFFERENT ramp
durations (15.439 s and 13.875 s) fail at the same ramp fraction
(`alpha = 0.99928` and `0.99930`), which is what identified the ramp itself as
the governing variable.

### Correction

Split the command timescales, opt-in, default unchanged:

- `derive_handback_duration` now also returns `t_control` on its own. `T` and
  `status` are untouched.
- `enter_online_governor` takes an optional `T_efd`; omitting it keeps
  `T_efd = T_handback`.
- The online branch walks ONLY the field-voltage command over `T_efd`. Mechanical
  power and the IBR P/Q references keep the full handback duration, so the
  concern that produced the C1 ramp in the first place — an instantaneous
  1.28758 pu command reset, `SWITCH-2026-08-10-03` — is unaffected.
- New option `handback_efd_timescale` ∈ {`'mode'` (default, historical),
  `'control'`}.

Classification: `NUMERICAL_METHOD`/`PROJECT_DERIVED`. The alternative duration is
not a fitted number — it is the expression the same function already computes for
the declared actuator lags, and `tests/test_ts_hybrid_handback_command_timescale.m`
freezes it as `-log(rho)*max([Tsv Tch TA])` and asserts it is strictly shorter
than `t_mode`. No equation, base, limit, threshold, dwell, timeout, event time,
AGSI weight, or acceptance gate changed.

### Verification

Canonical 250-s chronology, adaptive stepper, correctly-dispatched selector
table, transition certificate ON, `handback_efd_timescale='control'`:

```text
conv=1  t_end=250.000000  failure_id=[]  wall=533.4 s
requested_sg_on=145   actual_reclose=159.3436   status=SUCCESS
terminal: f_coi=60.000000 Hz  sg_freq=60.000000 Hz  bus |V| 0.9667..1.0575
          handback C1_COMPLETE   reference_owner=SG
          reselection_status=NO_FEASIBLE_SG_ON_ONE_STEP  (correct fail-closed)
          rejected_steps=137   floor_accepted_steps=0
```

**Independent oracle.** The terminal state reproduces the published EECON49
Figure-4 operating point, which is data this correction never touches:

```text
dev    mode   |I|       P pu      Q pu      |S| pu    published
SG1    sg     1.34620   1.33190  -0.19567   1.3462    134.62 MVA
IBR2   GFM    0.36623   0.31718   0.17674   0.3631     36.31 MVA
IBR3   gfl    0.34156   0.28844   0.16073   0.3302     33.02 MVA
IBR6   gfl    0.48093   0.44428   0.24757   0.5086     50.86 MVA
IBR8   gfl    0.29199   0.26765   0.14915   0.3064     30.64 MVA
```

IBR2's terminal current `0.36623` matches the certified SG_ON `[2]` equilibrium's
`0.366232` to five decimals, i.e. 69 % below the limit it previously sat on, and
the bus-voltage range equals the certified equilibrium's exactly.

`reselection_status=NO_FEASIBLE_SG_ON_ONE_STEP` confirms the ordering now runs to
completion: the handback finishes, the severity dwell elapses, the one-step
release IS attempted, and it is correctly refused because the all-GFL SG-online
row fails the frozen margin at the production dispatch. IBR2 therefore remains
GFM — the documented "retain the minimum authenticated GFM subset" behaviour of
`SWITCH-2026-08-10-03`, reached by the intended path rather than by a deadlock.

### What was NOT the cause (falsified during this investigation)

- **Inner-loop integrator windup.** `gfm_xi_Id`/`gfm_xi_Iq` stay at ~1e-6
  throughout; linear-fit slopes are `-6.7e-07/s` and `2.7e-06/s`. The
  unconditional inner integration is harmless here.
- **A large angular displacement.** An earlier reading of a ~148 deg swing was a
  UNIT ERROR: `gfm_delta_VSG` and the SG `delta` are unwrapped RADIANS, not
  degrees. Correctly reduced, the arriving pairwise SG-IBR2 angle is
  `37.7163 rad = 6 turns + 0.97 deg` against `11.39 deg` at the destination, a
  gap of about 10 deg, and IBR2's angle relative to bus 1 is within 0.06 deg of
  the network angle at the close. There is no pole-slip-scale displacement.
- **A stale `E_ref`.** At the certified destination every IBR terminal voltage
  equals its frozen `E_ref` to 0.000e+00, so the frozen values are the correct
  ones for this operating point.
- **The `handback_complete` ordering gate as the primary defect.** It is real,
  undocumented and untested, and it did block the release for the whole ramp —
  but with the excitation restored on the actuator timescale the ramp completes,
  the gate opens on its own, and the release is then refused on its merits. No
  change to that gate was needed.
- **Solver settings** (FD perturbation rule, rejection budget, integrator,
  nominal step): see the four-arm table above.

## Limitations

- Single chronology and profile (`eecon49_figure4`); the fix is opt-in, so the
  default route is byte-identical and unproven for this chronology.
- The `handback_complete` conjunct in `hold_ok`
  (`+stability/ts_simulate_ibr_hybrid.m:1078-1081`) remains undocumented and
  untested. It is no longer load-bearing for this chronology but it is still a
  latent ordering hazard, and it is left for the owner to rule on.
- The diagnostic-harness dispatch defect described above is fixed only in the
  scratch driver; `+stability/ibr_config_selector.m` still ignores a dispatch
  supplied under a key it does not consume rather than failing closed.
- No parameter, threshold, limit, dwell, timeout, ramp constant, or AGSI weight
  was changed while producing this record.

## Related files

- `+stability/ts_simulate_ibr_hybrid.m` (adaptive stepper region, handback
  `derive_handback_duration`, reclose transaction)
- `+stability/synchronism_guard.m` (the reclose gate that passed)
- `docs/project/defects/2026-08-14-all4-gfm-commit-outside-basin.md` (the
  correction that made this region reachable)
- `docs/project/defects/2026-08-13-islanded-vsg-inertia-reclose-unreachable.md`
- `docs/project/defects/2026-08-13-dv20-post-line-nonsmooth-newton-wall.md`
  (an earlier Newton wall on this chronology, different location and cause)
