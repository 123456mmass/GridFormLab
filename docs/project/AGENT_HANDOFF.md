# Agent handoff — IEEE14 mixed-resource IBR G2/event checkpoint

Date: 2026-07-15
Branch: `main`
Tested working tree: parent `250fffc` plus the checkpoint described here

This is the current canonical handoff. Historical phase handoffs remain
provenance but do not override this runtime status.

## Delivered runtime path

```text
case/resource table
  -> configurable initial GFL/GFM composition
  -> project-owned PF warm starts
  -> all-KCL mixed equilibrium
  -> optional SCR/equilibrium/full-state-SSSA selector
  -> shared coupled trapezoidal step
  -> exact event landing and atomic right-limit transaction
  -> device-owned GFL<->GFM transfer
  -> SG synchronism dwell/reclose or fail-closed timeout
  -> two audited TS plots + index/work-count log
```

Implemented models/layouts are: WECC REGC_A/REEC_A GFL (7 states),
REGFM_B1 G2 GFM (13 states), and a 20-state dual-mode superset
(`GFM=1:13`, `GFL=14:20`). The IEEE14 mixed case has 6 SG states plus four
dual-mode IBRs, 86 states total.

The active-bound equilibrium layer uses its locked outer active set. The TS
event supervisor does not duplicate a trapezoidal residual/Jacobian: event and
no-event routes call `stability.ts_step_composite`.

## Configuration and log contract

The IBR launcher is available programmatically and through the analysis/case
dialogs in `solve_case`. IBR controls appear only for the IBR analysis. Users
may set normal-operation GFM/GFL counts, exact initial GFM indices/reference,
fault external bus and impedance, the independent `fault_on`, `fault_clear`,
`sg_trip`, `sg_on` times, exact post-trip GFM indices/reference, timestep/end
time, and plot options.

Count-only GFM selection calls the full selector; it never selects a first
device implicitly. Explicit indices are capability/cardinality checked. Every
initial/event/reclose snapshot logs online SG/GFM/GFL counts and indices,
device ID/external bus/mode/online flag, global state range, active local and
global indices, and all-KCL residual. The execution summary separates PF,
equilibrium, SSSA, and TS invocations from Newton iterations, TS step attempts,
accepted steps, and event transactions.

The SSSA launcher prints `FULL STATE EIGENVALUES` for every case. Rows use
two-digit numbering and two-decimal scientific notation. Display ordering
never changes the computed eigenvalue set.

## Event and plot contract

- Fault topology is `Yfault(fb,fb)=Ypre(fb,fb)+1/Zf`.
- Scheduled events land exactly and publish left/right samples.
- SG trip, mode transfer, and algebraic right limit are one atomic transaction;
  failure rolls back without a false right-side sample.
- The active-state partition is recomputed after every committed mode/online
  change.
- SG reclose preserves SG differential state and commits only after the
  phasor-voltage/pu-slip guard and dwell pass; otherwise it remains offline or
  times out explicitly.
- `plot_ibr_ts_results` creates exactly two PNGs from audited result fields:
  frequency/voltage and device P/Q/current, with labeled event times.

## Fresh focused evidence

- GFL/GFM/G2/equilibrium/transfer/selector/SSSA/TS/event/launcher/external
  closure: `183/183 passed` (combined focused runs).
- Event/no-event supervisor: `11/11 passed`.
- Selector + SG-off SSSA + launcher subset: `25/25 passed`.
- MATPOWER case14 manual launcher gate: PF converged in 5 iterations; SSSA
  printed all 10 full-state roots; short fault TS produced 6 finite samples/
  5 accepted steps.
- Default IEEE14 IBR event demo (`dt=0.01`, `t_end=0.1`, all four IBRs become
  GFM): 10/10 TS steps accepted, 38 Newton iterations, logged right-limit KCL
  below `1e-6`, and both PNGs created.

Final repository-wide regression on this source tree: `804 total`,
`800 passed`, `0 failed`, `4 incomplete`. The four incomplete tests are the
pre-existing PGAz comparisons filtered by their validation-only assumptions;
production results do not depend on them.

## Honest limitations and readiness

The selector evaluates the correct post-trip context (SG breaker open), but
no current IEEE14 candidate satisfies frozen `gamma_req=0.1 s^-1`. Computed
spectral abscissae are positive for evaluated one-through-four-GFM candidates,
so it returns `NO_FEASIBLE_CANDIDATE` and never silently certifies them.

The short explicit all-four-GFM event demonstration converges but is not a
stability certificate. At `dt=0.01`, explicit two- and three-GFM trajectories
fail closed near `t=0.1`; two GFM reaches that horizon at `dt=0.0025`. This
timestep sensitivity is reported, not tuned away. With case synchronism
limits, the short default run reports `PENDING_SYNC_FAIL`; a successful
reclose transaction is separately falsified with declared test-only guard
overrides and is not a natural case result.

```text
IEEE14_IBR_GFL_MODEL_READY       = STRUCTURAL_ONLY
PHASE_G2_LIMITER_READY           = G2_IMPLEMENTED
IBR_EVENT_RUNNER_READY           = IMPLEMENTED_FAIL_CLOSED
IBR_PRODUCTION_INTEGRATION_READY = NOT_READY
```

Remaining blockers are a feasible/stable sourced post-trip configuration,
longer-horizon nonlinear TS evidence, natural synchronism/reclose evidence,
and independent validation. The final full regression is complete. No
external solver is reachable from production.

## Preserved local material

`docs/text/`, `docs/probes/ieee14_ibr_phaseG/`, the local Thai report source/
PDF, and the archived font/resource file remain untracked user/validation
material. They are not production dependencies and must not be staged.
