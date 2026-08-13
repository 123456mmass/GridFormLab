# Dv=20 chronology stalls after line trip on a nonsmooth controller active-set corner

Date: 2026-08-13  
Status: OPEN  
Defect ID: `TS-2026-08-13-03`

## Scope and evidence boundary

This record classifies the short Dv=20 EECON49 chronology blocker. It does not
change or recommend changing `Dv`, `M`, `Imax`, event times, selector ranking,
solver tolerances, synchronism gates, dwell, timeout, or lockout. Diagnostics
use project-owned MATLAB equations only. Counterfactual delayed-line and crossed
state/topology probes are diagnostic controls, not production evidence.

## Symptom

Under the source-case chronology

```text
sg_trip=1.0, load_step=1.5, fault_on=2.0, fault_clear=2.15,
line_trip=2.5, topology_restore=sg_on=3.0
```

with the authenticated all-four GFM candidate `[2 3 4 5]` and production
`Dv=20`, fixed trajectories at `dt={0.05,0.02,0.01}` pass the bolted fault and
commit `line_trip`, then fail closed shortly afterward. The corrected adaptive
route with a diagnostic `reject_limit=12` likewise commits every event through
`line_trip` and fails at `t=2.550134732` with `adaptiveDtMin` after both
trapezoidal and backward-Euler Newton solves fail at the floor.

Automatic one-GFM and two-GFM candidates fail earlier inside the fault window,
so all-four capacity resolves one layer but not the post-line layer.

Evidence:

- `output/diagnostics/fault_capacity_resolution_run.log`
- `output/diagnostics/fault_adaptive_attribution_plumbing_fixed_run.log`

## Reproduction

Primary diagnostic controls:

- `chk_fault_dv_line_attribution_tmp.m`
- `chk_postline_cross_state_tmp.m`
- `chk_all4_finedt_chronology_tmp.m`

The crossed-state log is:

- `output/diagnostics/postline_cross_state_run.log`

## Findings

### 1. The line-trip right-limit transaction is feasible

Fresh early-line and delayed-line arms are byte-identical through the
`t=2.5` line-trip left limit:

```text
max|dx|=0, max|dy|=0, max|du|=0
```

The line transaction holds all differential states exactly
(`max|dx_right-left|=0`), changes only the algebraic solution
(`max|dy_right-left|=6.731e-2`), and satisfies KCL. A one-step replay from the
line-right state converges for both trapezoidal and backward Euler across
`h=1e-2 ... 1.25e-5`.

Therefore the branch stamp and atomic right-limit solve are not themselves the
failure.

### 2. Event timing changes the incoming trajectory, not topology feasibility

Moving only `line_trip` from `2.5` to `3.5` lets the Dv=20 all-four arm reach
`t=4.0` and cross the same branch removal. At `t=2.58`, the early-line and
delayed controls differ by only

```text
max|dx| = 1.938e-2, dominated by IBR2.gfm_delta_VSG
max|dy| = 5.433e-2
```

Yet the delayed-control state is one-step solvable under **both** line-in and
line-out topologies. Conversely, restoring the line algebraically at the early
wall does not make every nominal step converge. Thus neither topology alone
nor a static algebraic infeasibility explains the failure; the accepted
post-line trajectory reaches a sensitive active-set corner.

### 3. The terminal failure is a differential controller row

At the early fixed wall (`t=2.58`, line out), the algebraic system itself solves
to `1.6e-12` with `rcond(g_y)≈1.7e-3`. The failed coupled step has:

```text
trapezoidal h=0.01: residual=3.78e-5, rcond(J)=2.62e-6,
                       line_search_exhausted=1
worst row: IBR3.gfm_xi_Vd
```

Backward Euler at the same nominal size also exhausts its line search. This
localizes the wall to the voltage-loop integrator/current-reference active set,
not to network KCL.

### 4. The current-reference limiter and anti-windup surface is crossed

At the wall, physical current states are only approximately at the declared
limit, but the **raw current references** are substantially saturated:

```text
IBR2 raw |Iref| / Imax = 2.243, voltage integrators held [d,q]
IBR6 raw |Iref| / Imax = 1.094, voltage integrators held [d,q]
IBR3 raw |Iref| / Imax = 0.997, immediately beside the active-set boundary
```

Crossing the line algebraic solution can move IBR3 from just below to just above
the circular reference limit, changing `conditional_hold` for `xi_Vd` while a
forward-FD Newton column is being formed. That is exactly the worst residual
row. The evidence establishes an active-set discontinuity and associated
conditioning collapse; it does **not** prove that the physical current limit
should be removed, enlarged, or smoothed.

A prior diagnostic with an artificially large `Imax` made the island behavior
worse, so “the limiter alone causes the complete trajectory problem” is
falsified. The narrower proven statement is: the current-reference limiter /
anti-windup switching surface governs this local Newton wall.

### 5. A smaller replay step solves; the DAE is not statically infeasible

From the exact same accepted wall state and topology:

```text
h = 1e-2, 5e-3  -> coupled Newton fails
h <= 1e-3       -> trapezoidal and backward Euler converge in about 3 iterations
                    with residuals <= O(1e-10)
```

This falsifies static physical infeasibility at that accepted state. It also
shows why nominal-output-step sweeps are non-monotone: each run follows a
different discrete active-set trajectory, and the existing failure-driven
subdivision does not choose step size from proximity to the limiter surface.

A short all-four fixed sweep (`chk_all4_finedt_chronology_tmp.m`, horizon 2.7 s,
line trip 2.5, restore/sg_on 2.65, `max_step_subdivisions=12`) makes the
non-monotonicity explicit:

```text
dt=0.005  -> conv=1, reached t=2.70 (crossed line trip + restore + sg_on)
dt=0.0025 -> conv=0, stepNewton at t=2.52 (just after line trip)
dt=0.001  -> conv=1, reached t=2.70 (26619 attempts, depth 12)
```

`dt=0.005` and `dt=0.001` both traverse the post-line window while the
intermediate `dt=0.0025` does not; smaller nominal `dt` is not by itself a
monotone remedy. Evidence: `output/diagnostics/all4_finedt_chronology_run.log`.

## Root-cause classification

`OPEN_NUMERICAL_METHOD_AND_MODEL_INTERFACE`:

- **model interface:** hard circular current-reference projection plus
  conditional anti-windup creates a piecewise-smooth RHS;
- **numerical method:** forward-FD damped Newton and failure-driven dyadic
  subdivision can straddle that switching surface, yielding a poorly
  conditioned coupled Jacobian and a line search with no residual decrease;
- **trajectory dependence:** Dv=20 and the frozen event chronology determine
  when the post-line path reaches that corner, but local SSSA stability and a
  feasible line right-limit do not guarantee traversal.

This classification is narrower than “current limiter is the root cause of all
island dynamics” and narrower than “Dv=20 is wrong.” Neither broad claim is
supported.

## Falsified hypotheses

1. **Line-trip topology is algebraically infeasible** — falsified by exact
   right-limit KCL and crossed delayed-state/topology solves.
2. **The line branch stamp is wrong** — falsified by identical prefix,
   successful delayed removal of the same stamp, and right-limit KCL.
3. **No DAE solution exists at the wall** — falsified by converged replay at
   `h<=1e-3` from the identical accepted state.
4. **The physical-current limiter alone causes the complete island trajectory**
   — falsified by the prior high-`Imax` control; the proven issue is the local
   raw-reference/anti-windup active-set crossing.
5. **Adaptive reject lease is the final root cause** — falsified: forwarding
   `reject_limit=12` crosses the old lease and still reaches the same post-line
   layer.
6. **More GFMs alone resolve the chronology** — falsified: all four traverse the
   fault but can still hit the post-line wall.

## Candidate correction classes — NOT approved or implemented

Any production correction materially changes a numerical or model contract and
requires a reviewed re-plan (`Explore -> Plan -> custom-advisor` or disclosed
self-review if unavailable):

1. event-aware / active-set-aware Newton that keeps FD columns on one limiter
   regime and locates switching times;
2. semismooth Newton with an explicit generalized derivative for the circular
   projection and conditional anti-windup;
3. an independently derived smooth limiter/anti-windup model, which is a device
   equation change and needs physical/source justification;
4. scaled/trust-region globalization with independent convergence and
   trajectory-oracle gates;
5. transient-capacity evidence in selector ranking, which is a selector
   contract change and cannot be inferred from SSSA alone.

Do not alter a tolerance, `Imax`, `Dv`, event time, candidate, or safety gate
merely to make this arm pass.

## Delivery consequence

The predeclared Dv=20 chronology integration gate is not met, so reclose is not
reached on the canonical chronology. Report generation must remain fail-closed
or be changed to publish “not reached / chronology blocked” honestly; no reclose
success can be regenerated from stale caches.

## Related files

- `+ibr/gfm_eecon49_full_model.m`
- `+stability/ts_step_composite.m`
- `+stability/composite_newton.m`
- `+stability/ts_simulate_ibr_hybrid.m`
- `2026-07-20-dt01-newton-stall-t325.md`
- `2026-08-13-adaptive-option-forwarding-cell-orientation.md`
- `2026-08-13-islanded-vsg-inertia-reclose-unreachable.md`
