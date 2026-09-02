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
this record answers.

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
the kernel was stepping. Probe: `tmp/mt/probe_wall.m`, `tmp/mt/probe_wall2.m`
(diagnostic controls, not production evidence).

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
trapezoidal equation is satisfied by `x1 ≈ x0` for trivial reasons. What is
solid for `former_outage` is finding 2 — zero progress with an exhausted line
search across four decades — not a clean solvability proof.

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
- **NOT supported:** that the trajectory INTO the wall is healthy. In
  `former_outage` the three survivors pick up the lost converter's share and
  more (`P = 0.446, 0.996, 0.755` pu against `0.29, 0.45, 0.29` before), one is
  current-limited, and `f_COI` is falling at roughly `-0.5 Hz/s` through the last
  0.34 s. A power-deficit collapse is entirely consistent with that trace. The
  wall prevents the run from showing which it is.

Distinguishing those two would need a solver that can cross the corner — which
is a `TS-2026-08-13-03` correction class, none of which is approved — not a
tolerance, `Imax`, `Dv`, event-time or gate change.

## Delivery consequence

Two scenarios die before the event they were built to exercise, so the
`line_fault_clear` handler added in `b4d312c` is NOT exercised by any 120 s
scenario artifact. Its evidence is `tests/test_line_fault_relay_clear.m`, whose
central assertion is an independent KCL discrimination on a compressed timeline:
the post-clearing sample satisfies the reduced UNFAULTED network at `2.1e-8` and
misfits the full, faulted-full and reduced-faulted networks by `>= 1e-3`.

The suite's `expectation_met = true` on these three arms means "a trajectory was
produced and the horizon it reached is the measurement", not "the scenario
answered its question". Reporting must say which arm answered its question and
which was stopped short. `sg_load_step30` answered its question;
`former_outage` answered the ownership half of its question — the outage
committed and the reference moved from IBR2 to IBR3 — and was stopped 0.7 s
later; `sg_fault_bus9` and `line_fault_9_14` did not reach their events.

## Related files

- `+stability/ts_simulate_ibr_hybrid.m`
- `+stability/ts_step_composite.m`
- `+stability/composite_newton.m`
- `+ibr/gfm_eecon49_full_model.m`
- `2026-08-13-dv20-post-line-nonsmooth-newton-wall.md`
- `2026-08-14-all4-gfm-commit-outside-basin.md`
- `output/diagnostics/ieee14_scenario_suite/provenance.txt`
