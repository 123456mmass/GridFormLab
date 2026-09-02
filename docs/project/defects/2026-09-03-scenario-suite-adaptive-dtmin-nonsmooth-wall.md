# TS-2026-09-03-01 - Two new scenarios stop at the same nonsmooth Newton wall, on topologies TS-2026-08-13-03 never covered

- **Status:** OPEN (no production correction proposed here; this record
  classifies the stop and closes the physical-vs-numerical question that the
  scenario suite shipped as unresolved)
- **Area:** switched-TS adaptive stepper / GFM voltage-loop active set
- **Branch / base:** `main` at `b4d312c`
- **Environment:** Windows 11, MATLAB R2025a Update 1, `dt=0.05`,
  `stepper='adaptive'`, `reject_limit=20`, `max_step_subdivisions=12`

## Symptom

Three of the four scenarios added in `b4d312c` stop before their requested
120 s horizon with `ts_simulate_ibr_hybrid:adaptiveDtMin`:

| scenario | stops at | the event it was built to exercise |
|---|---|---|
| `sg_fault_bus9` | 50.083340 s | fault clearing at 50.15 s — NOT reached |
| `line_fault_9_14` | 50.083340 s | `line_fault_clear` at 50.15 s — NOT reached |
| `former_outage` | 60.706647 s | the outage at 60 s — reached and COMMITTED |

`sg_load_step30` reaches 120 s and recloses at 81.5 s.

The suite reported these as `expectation_met = true` under the pre-existing
`TRAJECTORY_THEN_ANY` token and left the cause unresolved between genuine
physical collapse and the known wall of `TS-2026-08-13-03`. That is the question
this record answers. `a6ac6b7` separately made the "stopped before its own
defining event" fact explicit in the runner, `summary.mat` and
`provenance.txt`, so `expectation_met` can no longer be read as "the scenario
answered its question".

## Method

The discriminator is the one `TS-2026-08-13-03` finding 5 already validated: from
the EXACT accepted final state and its own topology, replay a single coupled
`stability.ts_step_composite` at decreasing `h`. A converging `h` falsifies
"no DAE solution exists at this state".

The reconstruction is self-checked before anything is read from it. The DAE is
rebuilt by `composite_dae` from the same case profile, the admittance is rebuilt
from the sample's own `topology_history` label, and the accepted sample must
satisfy KCL on the rebuild:

```text
sg_fault_bus9   topology 'fault'  |g|inf = 4.241e-14
former_outage   topology 'pre'    |g|inf = 1.805e-13
```

Both are far inside `kcl_tol=1e-6`, so the rebuilt `(dae, Y, u, ec)` is the one
the kernel was stepping.

Probe: `scripts/diagnostics/probe_scenario_wall_solvability.m`, committed rather
than left in a scratch directory, because the earlier records in this class cite
`chk_*_tmp.m` files that no longer exist in the tree and their evidence is
therefore no longer reproducible. It is a DIAGNOSTIC over recorded runs: it
changes no production option, and the `domain_preserving_trials=false` row in it
is a control, not a proposal.

## Reproduction

```matlab
pf_init_paths;
probe_scenario_wall_solvability();   % all three early-stopping scenarios
probe_scenario_wall_solvability('scenarios',{'former_outage'});
```

The probe refuses to report a scenario whose rebuild fails the KCL self-check,
and refuses a topology it cannot reconstruct, rather than printing numbers that
describe a different system.

## Findings

### 1. The algebraic subsystem at the wall is not the problem

At both walls `ts_algebraic_solve` converges in ONE iteration, leaving the
residual at the values above. The network solution is not near-singular in `y`;
`rcond(g_y)` stays at `1e-3` order. The wall is not network KCL.

### 2. The coupled Newton makes literally zero progress

At every step size at or above the stepper's floor, the returned state is the
initial state exactly:

```text
sg_fault_bus9, h = 1e-2 ... 6.104e-6:  max|dx| = 0,  line_search_exhausted = 1
former_outage, h = 1e-2 ... 1e-6:      max|dx| = 0,  line_search_exhausted = 1
```

The reported residual is therefore the residual of the UNCHANGED iterate, and it
scales linearly with `h` — `1.35e-3, 1.38e-4, 1.37e-5, 1.22e-6` at
`h = 1e-2, 1e-3, 1e-4, 1e-5` for `sg_fault_bus9`, i.e. `h·|f|` with
`|f| ≈ 0.135`. A diverging solve does not do this. A line search that finds no
admissible decrease from the first iterate does exactly this.

`rcond(J)` of the coupled system collapses to `1.46e-5` (`sg_fault_bus9`) and
`4.42e-6` (`former_outage`) at the nominal `h`, recovering to `~1e-3` as `h`
shrinks — the conditioning signature of `TS-2026-08-13-03` finding 3.

### 3. A small enough step converges: static infeasibility is falsified

```text
sg_fault_bus9  h = 1e-6:  converged, 4 iterations, residual 9.537e-10,
                          max|dx| = 3.29e-6, from an initial residual of
                          1.35e-7 -- a genuine 142x reduction, not a
                          tolerance-trivial pass
former_outage  h = 1e-6:  still fails (residual 5.218e-8, max|dx| = 0)
               h = 1e-7:  converged, residual 5.788e-10
```

The stepper floor is `dt_min = 6.104e-6`, so both converging step sizes are
BELOW the floor the production run is allowed to reach. For `sg_fault_bus9` a
solution demonstrably exists at the accepted state and the stepper simply cannot
legally take a step small enough to find it.

The `former_outage` result is weaker and must be stated as such: at `h = 1e-7`
the unchanged iterate already sits at `5.2e-9`, within one order of
`newton_tol = 1e-8`, so that convergence is close to the regime where the
trapezoidal equation is satisfied by `x1 ≈ x0` for trivial reasons. Against that,
its `max|dx|` at the converging sizes scales exactly with `h` — `5.02e-5` at
`h = 1e-7`, `5.02e-6` at `1e-8`, `5.02e-7` at `1e-9` — which is a real step of
`|dx|/h ≈ 502` per unit time, not a null move. What is solid for `former_outage`
is finding 2, zero progress with an exhausted line search across four decades;
the solvability reading is supporting evidence, not a clean proof.

### 4. The worst residual row is a voltage-loop integrator, not a network row

```text
sg_fault_bus9   IBR2.gfm_xi_Vd  (state row 19)
former_outage   IBR3.gfm_xi_Vq  (state row 37)
```

`TS-2026-08-13-03` finding 3 localized its wall to `IBR3.gfm_xi_Vd`. Same
controller, same integrator pair, different converter and different topology.

### 5. The converters are sitting ON the current-reference limiter surface

```text
sg_fault_bus9   IBR2 |I|/Imax = 1.0045   IBR6 1.0018   IBR8 1.0029   IBR3 0.9216
former_outage   IBR3 |I|/Imax = 1.0000   IBR6 0.9543   IBR8 0.8376
```

This is the switching surface `TS-2026-08-13-03` finding 4 identified as
governing that wall. In `former_outage` the row that fails is the integrator of
the one converter that is exactly on the surface.

### 6. The domain-preserving guard is not the mechanism

`domain_rejected_trials = 0` at every failing `h`, and a diagnostic control with
`domain_preserving_trials=false` reproduces the failures with byte-identical
iteration counts and residuals. This rules out `DOC-2026-08-28-02`'s counter and
the domain guard as the blocking mechanism, so the reading does not depend on
that unreproduced counter.

## Root-cause classification

Same class as `TS-2026-08-13-03`, `OPEN_NUMERICAL_METHOD_AND_MODEL_INTERFACE`,
now with evidence on two topologies its record did not cover: a bolted fault
ridden by a SINGLE grid-forming converter, and a post-outage island. The
governing surface is the hard circular current-reference projection plus
conditional anti-windup; damped Newton with forward-FD columns straddles it,
the coupled Jacobian conditions out, and the line search returns no decrease.

## What is NOT established

The scenario suite must not be read as saying the island would survive under a
better solver. Two separate claims, only one of which is supported:

- **Supported:** the STOP is a solver wall at a nonsmooth corner. It is not a
  proof that the DAE has no solution at the accepted state, and for
  `sg_fault_bus9` a solution provably exists there.
- **NOT supported, and no longer arguable from this evidence:** that the island
  was collapsing when the wall arrived. The trajectory says the opposite. See
  below.

### The trajectory into the wall is a RECOVERY, not a collapse

An earlier reading of this evidence recorded that `former_outage` had `f_COI`
"falling about 0.5 Hz/s" and that a power-deficit collapse was equally
consistent. That was read off the last handful of accepted samples, which span a
fraction of a second at the collapsed step size, and it is wrong. Reading the
whole window from the event to the wall — 57 samples over 0.707 s — inverts it:

```text
former_outage, f_COI from the outage to the wall
  t = 60.000   60.000 Hz   (the outage instant)
  t = 60.021   58.684 Hz   <-- NADIR, 21 ms after the outage
  t = 60.100   58.909 Hz
  t = 60.219   59.334 Hz
  t = 60.368   59.707 Hz
  t = 60.707   59.529 Hz   (the wall)
```

The island dips 1.3 Hz, reaches its nadir 21 ms in, and then RECOVERS toward
59.5 Hz. Bus voltages do the same: `Vmin` dips to 0.6997 pu at `t = 60.314` and
is back to 0.7691 pu at the wall, with `Vmax` recovering from 0.8902 to 0.9588.
Total served power falls from 2.6234 pu to 2.1969 pu, which is the load the
network sheds through its voltage dependence, not a diverging deficit. `f_COI`
is not monotone in either direction over the window.

The same holds for `sg_fault_bus9`, once the physics of its window is read
correctly. The fault takes `Vmin` to 0.055 pu and served power to 1.01 pu, so the
island cannot deliver into a bolted short and goes OVER-frequency: `f_COI` rises
to a maximum of 60.676 Hz at `t = 50.018` and is settling at 60.524 Hz when the
wall arrives 83 ms into the fault. That is ordinary faulted-network behaviour,
not a collapse.

So the honest statement is stronger than the one first recorded here: at the
moment each run stopped, the trajectory was settling, and the stop is attributable
to the solver. What still cannot be claimed is the counterfactual — that a solver
able to cross the corner would carry `sg_fault_bus9` through its clearing at
50.15 s, or `former_outage` to 120 s. Nothing here simulates past the wall, and
`AGSI-2026-08-14-01` is a live reason a later transaction could still refuse.

Crossing the corner is a `TS-2026-08-13-03` correction class, none of which is
approved, and not a tolerance, `Imax`, `Dv`, event-time or gate change.

## Delivery consequence

Two scenarios die before the event they were built to exercise, so the
`line_fault_clear` handler added in `b4d312c` is NOT exercised by any 120 s
scenario artifact. Its evidence is `tests/test_line_fault_relay_clear.m`, whose
central assertion is an independent KCL discrimination on a compressed timeline:
the post-clearing sample satisfies the reduced UNFAULTED network at `2.1e-8` and
misfits the full, faulted-full and reduced-faulted networks by `>= 1e-3`.

The suite's `expectation_met = true` on these three arms means "a trajectory was
produced and the horizon it reached is the measurement", not "the scenario
answered its question". `a6ac6b7` makes that split machine-readable: each
scenario declares its defining event, and the runner reports separately whether
that event executed, in `summary.mat`
(`defining_event_executed`, `events_not_executed`) and in `provenance.txt`.
`sg_load_step30` answered its question; `former_outage` answered the ownership
half of its question — the outage committed and the reference moved from IBR2 to
IBR3 — and was stopped 0.7 s later; `sg_fault_bus9` and `line_fault_9_14` did not
reach their events.

## Related files

- `+stability/ts_simulate_ibr_hybrid.m`
- `+stability/ts_step_composite.m`
- `+stability/composite_newton.m`
- `+ibr/gfm_eecon49_full_model.m`
- `scripts/diagnostics/probe_scenario_wall_solvability.m`
- `scripts/reporting/ieee14_event_execution.m`
- `2026-08-13-dv20-post-line-nonsmooth-newton-wall.md`
- `2026-08-14-all4-gfm-commit-outside-basin.md`
- `output/diagnostics/ieee14_scenario_suite/provenance.txt`
## Continuation - 2026-09-03 (one-former island vs the same fault with four formers)

The previous section stops short of answering what the framework actually does
in the faulted window. The question is whether the solver wall is the whole
story or whether a different configuration would have carried `sg_fault_bus9`
through the clearing. Five probes (`tmp/mt/probe_dt.m`, `probe_formers.m`,
`probe_imax2.m`, `probe_dwell.m`, `probe_spacing.m`, and `probe_floor.m`) and a
positive-control replay address it.

### 7. Positive control: the framework RIDES the same fault on the same bus with the same Zf

`output/diagnostics/ieee14_gfm_lock_compare_zeta/adaptive_250s.mat` (`zeta`
comparison deliverable, committed earlier) contains the chronology. It
faults **the same bus 9** with **the same Zf = 0.01+0.01i** at **t = 85 s**
(originally the `combined` event profile: `sg_trip 20 -> load +20% 50 -> fault
bus 9 85 -> line 6-13 trip 110 -> restore/reclose 145 -> 250 s`). That run
CROSSES, produces 3679 samples through 250 s, and ends with `converged=1`,
`reclose_status=SUCCESS`, `f_COI` settled at 60.000001 Hz. The topology
labels visited across the fault window are identical
(`pre -> fault -> fault_cleared -> post_fault -> line_open -> line_restored`).
The solver configuration (`dt=0.05`, `stepper='adaptive'`, `reject_limit=20`,
`max_step_subdivisions=12`, `selector_table=selector_table`) is the same.

The only traced structural difference is the number of grid-forming
converters AT the fault instant:

```text
chronology (4 formers at 85 s):
  load_step at 50 s augments support twice -- 2 formers by 51.34 s,
  4 formers by 53.38 s, held through the fault
sg_fault_bus9 (1 former at 50 s):
  no augmentation between sg_trip at 20 s and fault_on at 50 s
```

**Read** (`probe_formers.m`, case-insensitive compare on `device_modes`):
the chronology carries 4 GFM across the entire pre-fault window;
`sg_fault_bus9` carries 1. Same fault, same bus, same Zf, same solver, same
case profile (`eecon49_figure4`), same selector fingerprint -- different
island thickness, opposite outcome.

### 8. The current-limiter surface is NOT the discriminator

`TS-2026-09-03-01` finding 5 noted that the converters at the wall are ON the
`current-reference` limiter surface. The chronology positive control shows
that being ON the surface is not the obstruction: the chronology puts **4 of
4 converters** ON the surface through the same fault and still crosses.

```text
| max |I|/Imax in the fault window (Zf=0.01+0.01i, same bus 9)
device   chronology (4f, @85 s)   sg_fault_bus9 (1f, @50 s)
IBR2     1.0068  (ON surface)     1.0045  (ON surface)
IBR3     1.0059  (ON surface)     0.9216  (below)
IBR6     1.0060  (ON surface)     1.0018  (ON surface)
IBR8     1.0067  (ON surface)     1.0029  (ON surface)
```

(`probe_imax2.m`, corrected version: `device_current_limit_sys` is per-sample
5 x nsamples, SG row excluded, otherwise identical; the previous version of
this probe flattened the limit matrix and printed nonsense.)
The chronology succeeds with every converter saturated; `sg_fault_bus9`
stops with three of four saturated and one below. The surface is a regime
both runs enter; it is not what separates crossing from stopping.

### 9. The supervisor cannot act during the fault regardless

Even setting the thick-island question aside, the framework is structurally
unable to add a former during the bolted short. Three independent checks:

- **`ts_simulate_ibr_hybrid:3262`** refuses a support-augmentation commit
  while `topology == 'fault'`, with the explicit reason "no destination
  equilibrium exists while the bolted fault is committed". This is a
  permanent guard, not a transient one; the topology label at the wall is
  still `'fault'`.
- **`:2356`** refuses reference-recovery transitions during the fault for
  the same reason.
- **The severity up-dwell (`T_d_on = 0.10 s`)** requires severity to stay
  above `gamma_on = 0.65` for 100 ms before an augmentation is commanded.
  The wall lands 83.34 ms after the fault. Even with NO guard and a clear
  severity signal, the controller is 17 ms short of its own decision
  window. The dwell timer is therefore moot for the failing arm.

`probe_dwell.m` confirms all three: in the window `50.000 .. 50.0833` (a)
`dwell_timers` is empty at every checked sample, (b) `topology` is `'fault'`
throughout, (c) `selector_log` carries zero entries in the window 49.9 .. end,
i.e. the supervisor was never asked to make a decision. The wall is not
"the supervisor tried to act and was blocked"; it is "the supervisor never
got to the point of asking, and the guards would have refused anyway".

### 10. Both runs hit the `dt_min` floor inside the fault window

```text
dt_min = 0.05 / 2^13 = 6.104e-6   (production floor, both runs)
sample spacing INSIDE the fault window
  chronology    min = 3.003e-3 s   median = 5.006e-3 s   n = 55
                (closest the chronology got to the floor: 492x)
  sg_fault_bus9 min = 5.005e-6 s   median = 5.027e-3 s   n = 26
                (hit the floor at 2 of 784 accepted samples;
                 both wall samples were at the floor)
```

(`probe_dt.m`, window `[fault_on, fault_clear]`, sample spacing just
`diff(t)`.) Both runs reach `dt_min` in the fault window; the chronology
recovers and `sg_fault_bus9` does not. **The wall is not a wall the
chronology avoided** -- it is a wall the chronology hit and stepped out of
on the same step size the thin island cannot. The controller's marginal
step-size budget in the fault window is what separates the two runs.

### 11. `dt_min = 1e-6` does not carry `sg_fault_bus9` through (non-monotonicity)

The obvious remediation would be to lower `dt_min` by 6.25x to `1e-6`. It
was tried (`probe_floor.m`, wall time 109 s, `adaptiveDtMin` still emitted):

```text
dt_min=1e-6    conv=0   t_end=50.083337 s   CROSSED=0
               samples=791   rejected=89   floor_acc=0
               max accepted KCL residual = 4.179e-8  (kcl_tol = 1e-6)
               failure: ts_simulate_ibr_hybrid:adaptiveDtMin
               applied: sg_trip@20.00 gfm_support_augment@22.09
                        gfm_support_release@25.33 fault_on@50.00
```

The stop is at `t_end = 50.083337` -- within one sample-spacing of the
default-floor stop (50.083340 s). Rejections go 83 -> 89. Samples go 789 ->
791. The wall moved 3 ms EARLIER with a smaller floor, in the wrong
direction. **Lowering `dt_min` does not help and the trajectory into the
wall is not monotone in `dt_min`.** This is consistent with
`TS-2026-08-13-03` finding 5 ("step size is not monotone for this wall
class") and is the reason the wall cannot be removed by tightening floor
alone.

### Updated root-cause reading

The `sg_fault_bus9` stop belongs to the regime of *one grid-forming
converter attempting to ride a bolted fault on a network whose solver is
already at its nonsmooth wall*. The same regime with 4 formers rides out
(the chronology positive control), so the reading is "thin-island wall at
a nonsmooth corner", not "the framework cannot ride this fault". Lowering
the floor does not carry the thin island through; the relevant correction
class is `TS-2026-08-13-03` (controller / anti-windup), none of whose
findings is approved.

## Updated delivery consequence

The `defining_event_executed = false` report for `sg_fault_bus9` and
`line_fault_9_14` still stands and is now reinforced: the thin-island wall
has been shown to be independent of floor, of current-limiter surface,
and of supervisor availability. The two scenarios remain honest negatives
with respect to `line_fault_clear` and `fault_clear` execution.
`sg_load_step30` reaches 120 s. `former_outage` commits the outage at 60 s
and reports the ownership handoff (IBR2 -> IBR3) before stopping 0.7 s
later in the same wall class.
