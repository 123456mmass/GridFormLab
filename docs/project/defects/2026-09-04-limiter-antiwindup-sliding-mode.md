# TS-2026-09-04-01 — The current-limiter anti-windup switch is a sliding surface, and the step controller cannot cross it

- **Status:** RESOLVED for the four-scenario suite by an opt-in regularization
  (`anti_windup_blend`), which is DECLARED per run and defaults to 0. The
  underlying nonsmooth wall class `TS-2026-08-13-03` is untouched and stays OPEN.
- **Area:** IBR current-reference limiter / conditional anti-windup; switched-TS
  adaptive stepper
- **Branch / base:** `main` at `3f6f4ac`
- **Environment:** Windows 11, MATLAB R2024b, `dt=0.05`, `stepper='adaptive'`,
  `reject_limit=20`, `max_step_subdivisions=12`, derived floor
  `dt_min = 0.05/2^13 = 6.10352e-06`

## Symptom

`sg_fault_bus9` (SG trip at 20 s, bolted fault at bus 9 at 50 s, clearing at
50.15 s) stops at `t = 50.083340 s` with
`ts_simulate_ibr_hybrid:adaptiveDtMin` — 66.7 ms before the clearing it exists
to exercise. 789 accepted samples, 83 controller-rejected steps, max accepted
KCL residual `2.604e-07`.

`TS-2026-09-03-01` established what the stop is NOT: not network KCL (the
algebraic subsystem converges in one iteration), not the domain guard
(`domain_rejected_trials = 0`, and a control with the guard disabled reproduces
the stop with byte-identical counts), and not a collapsing island (the
trajectory into the wall is settling — `f_COI` reaches its nadir 21 ms in and
recovers). It classified the wall and stopped there. This record answers the
remaining question: WHY the coupled Newton makes zero progress, and whether that
is correctable without touching an acceptance gate.

## Root cause: neither branch of the anti-windup switch is self-consistent

The GFL and GFM current loops both freeze their outer integrator when the
current reference is limited AND the error would push further into the limit.
The predicate is a hard switch (`+ibr/gfl_eecon49_full_model.m`,
`+ibr/gfm_eecon49_full_model.m`, helper `conditional_hold`):

```
held = limited && direction_gain * e * limiter_residual > 0
d    = held ? 0 : e
```

`d` therefore JUMPS by the full `|e|` as the state crosses the surface
`|i_ref| = Imax`. At the wall the trajectory sits exactly on that surface, and
the two pure branches disagree about which side they land on:

- solve with the hold ON → the root lands where the limiter is INACTIVE
- solve with the hold OFF → the root lands where the limiter is ACTIVE

This is a sliding mode, not a slow iteration. Three independent measurements:

### 1. The branch classification 2-cycles, up to whatever cap it is given

An active-set outer loop was added to `+stability/ts_step_composite.m`
(freeze the branch → solve → reclassify → repeat until the classification is
its own fixed point), mirroring the pattern `active_bound_run.m` already uses
for equilibrium. At the failing step, IBR2's hold pair cycles

```
(0,0) -> (1,1) -> (0,0) -> (1,1) -> ...
```

and `regime_changes` equals the cap EXACTLY at every cap tried — 4 with
`limiter_regime_max_outer=4`, 12 with 12, 40 with 40. A converging active set
settles below its cap; this one does not settle at any cap. The live switched
residual of the frozen root is `1.879e-06`, i.e. the root of either pure branch
is not a root of the switched system.

### 2. Finite differencing straddles the surface at the failing step and nowhere earlier

`tmp/mt/probe_fdflip.m` perturbs each coordinate by the production FD step and
asks whether IBR2's hold classification changes. At `k = 789` (the failing
step) 2 of 46 state columns and 1 of 28 algebraic columns flip a hold. At every
earlier sample: zero. So the Jacobian columns at the wall are differences
across a jump discontinuity, which is why `rcond(J)` collapses and the line
search finds no admissible decrease.

### 3. The irreducible residual is O(h)

`tmp/mt/probe_hsweep.m` sweeps the step size at the exact failing state.
`residual/h` is roughly constant across the sweep — the signature of `(h/2)·|e|`
from the trapezoidal rule applied to a right-hand side that jumps by `|e|` —
and convergence first appears at `dt_min/8`, below the floor the production run
is allowed to reach.

## Falsified alternatives

Every one of these reproduced `t_end = 50.083340`, `samples = 789`,
`rejections = 83` to the digit:

| hypothesis | probe | result |
|---|---|---|
| trapezoidal order is the problem | backward Euler at the same `h` | identical stop |
| FD step is badly scaled | `fd_perturbation='scaled'` (`h_j = fd_eps(1+abs(z_j))`) | identical stop |
| FD column grouping corrupts the Jacobian | `fd_grouping='off'` (per-column), `fd_structure_check=true` | identical stop, no throw |
| the floor is simply too coarse | `dt_min` down to `0.05/2^18` (32x finer) | 50.083336 — 4 µs EARLIER |
| the active set just needs to be frozen | limiter-regime freezing, caps 4/12/40 | wall unmoved (residual improved 26x) |

The floor result is the decisive negative: 32x more step-size authority buys
4 µs, and in the wrong direction. This matches `TS-2026-09-03-01` finding 11
(the wall is not monotone in `dt_min`) and rules out "give the controller more
room" as a remedy.

Note that limiter-regime freezing DID improve the max accepted KCL residual
`2.604e-07 → 9.95e-09`, a 26x gain that is kept. It is a real improvement to
the quality of accepted steps; it is not a fix for the wall.

## Correction

Regularize the switch instead of the solver. Over a band of width
`blend·Imax` around the surface, the hold ramps continuously rather than
jumping:

```matlab
function [d,held] = conditional_hold(e,direction_gain,limiter_residual,limited,m,blend)
if nargin<6 || isempty(blend), blend=0; end
held = limited && direction_gain*e*limiter_residual>0;
if ~held, d=e; return; end
if blend<=0, d=0; return; end          % historical hard branch, bit-identical
s = min(1, abs(limiter_residual)/(blend*m));
d = e*(1-s);
held = s>=1;
end
```

`d` is now Lipschitz in the state instead of discontinuous, so a difference
quotient across the band measures a slope rather than a jump, and the two
branches meet continuously at the band edges. Outside the band the blended and
hard forms are the SAME EXPRESSION: `s>=1` gives `d=0` (hold) and `~held` gives
`d=e` (free), identical to the historical code.

The new option is `anti_windup_blend` (default `0`), forwarded opt-in through
`+stability/run_hybrid_case.m` and read from the event context by both models.
`blend=0` takes the historical branch, so the option is additive by
construction, not by inspection.

## Verification

### The scenario the wall blocked now completes, over a 50x band of blend widths

```text
blend      t_end        reclose   terminal f_COI   max accepted KCL residual
0 (ctrl)   50.083340    —         —                2.604e-07   adaptiveDtMin
1e-3       150.000000   SUCCESS   59.99997 Hz      9.95e-09
1e-2       150.000000   SUCCESS   59.99996 Hz      9.95e-09
5e-2       150.000000   SUCCESS   59.99997 Hz      9.95e-09
```

Spanning 1e-3 to 5e-2 rules out a single lucky value. The control arm
reproduces the published failure exactly. `kcl_tol` is `1e-6`, so every
accepted step is two orders inside the unchanged gate.

### The delivered chronology is unchanged with the patch present and its options absent

`tmp/mt/probe_chrono.m` runs the delivered 250 s chronology
(`sg_trip 20 → load +20 % 50 → fault bus 9 @85, clear 85.15 → line 6-13 trip
110 → restore/reclose 145 → 250 s`) on the patched tree, setting NEITHER new
option. All six published quantities match:

```text
quantity                    published     this run      match
reclose time (s)            159.252       159.252       yes
samples                     3679          3679          yes
rejected steps              161           161           yes
max accepted KCL residual   9.9721e-09    9.9721e-09    yes
terminal f_COI (Hz)         60.000001     60.000001     yes
reclose status              SUCCESS       SUCCESS       yes
```

### The four-scenario suite at `t_end = 150`, `anti_windup_blend = 1e-3`

```text
sg_load_step30    conv=1  t_end=150.000000  defining=load_step         EXECUTED
sg_fault_bus9     conv=1  t_end=150.000000  defining=fault_clear       EXECUTED
line_fault_9_14   conv=1  t_end=150.000000  defining=line_fault_clear  EXECUTED
former_outage     conv=1  t_end=150.000000  defining=ibr_trip          EXECUTED
```

All four reach their horizon and all four execute the event they exist to
exercise. Under the hard switch, three of the four stopped before their own
defining event (`TS-2026-09-03-01`).

## No acceptance gate was relaxed

`newton_tol = 1e-8`, `kcl_tol = 1e-6`, the Richardson LTE test, `dt_min` and
`reject_limit` are all the delivered values in every run above. The change is to
the MODEL — one controller predicate — declared per run, defaulting off, and
recorded in the suite runner's own header
(`scripts/reporting/run_ieee14_scenario_suite.m`, `base_request`) so a reader of
the artifacts cannot miss that the arms carry it.

## Limitations, stated rather than buried

- **This is a model change, not a solver fix.** `blend = 1e-3` means the
  anti-windup switch engages progressively over 0.1 % of `Imax` instead of at a
  point. That is defensible as a regularization of an idealized hard limiter —
  no physical converter switches in zero width — but it is PROJECT_DERIVED. No
  source prescribes the width, and the results above are the evidence that the
  outcome does not depend on it over two decades, not evidence that any
  particular width is right.
- **The delivered chronology's published numbers were produced WITHOUT the
  blend** and remain so. The four suite scenarios carry it. Comparing a suite
  arm against the chronology therefore compares two model settings, and any
  such comparison must say so.
- **`TS-2026-08-13-03` and `TS-2026-09-03-01` are not closed by this.** The
  nonsmooth wall class still exists for any run that does not opt in, which is
  every delivered artifact. What is established is that the mechanism at these
  particular walls is the anti-windup jump, and that regularizing it crosses
  them.
- **The limiter-regime freezing machinery** (`limiter_regime_freeze`,
  `limiter_regime_max_outer`, and the `limiter_regime` oracle threaded through
  `+ibr/eecon49_dual_mode_model.m` → `+stability/composite_dae.m` →
  `+stability/ts_step_composite.m`) is retained and defaults OFF. It did not
  move the wall. It is kept because it is what MEASURED the 2-cycle, and because
  it improves the accepted-step residual 26x when enabled.

## Related files

- `+ibr/gfl_eecon49_full_model.m`, `+ibr/gfm_eecon49_full_model.m` —
  `conditional_hold`, `anti_windup_blend`, `limiter_freeze`
- `+ibr/eecon49_dual_mode_model.m` — `dual_regime` dispatcher
- `+stability/composite_dae.m` — `composite_limiter_regime`
- `+stability/ts_step_composite.m` — the active-set outer loop
- `+stability/ts_simulate_ibr_hybrid.m` — option validation and event-context
  publication
- `+stability/run_hybrid_case.m` — opt-in forwarding
- `+stability/build_mixed_resource_devices.m` — field normalization for
  struct-array concatenation
- `scripts/reporting/run_ieee14_scenario_suite.m` — the arms that carry it
- `2026-09-03-scenario-suite-adaptive-dtmin-nonsmooth-wall.md` (TS-2026-09-03-01)
- `2026-08-13-dv20-post-line-nonsmooth-newton-wall.md` (TS-2026-08-13-03)
