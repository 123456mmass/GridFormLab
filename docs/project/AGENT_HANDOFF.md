# Agent handoff — IEEE14 mixed-resource IBR G2/event checkpoint

Date: 2026-07-15
Branch: `main`
Tested working tree: parent `2ac62d1` plus the checkpoint described here

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

- REGFM G2 differential-angle and physical-spectrum focused gates: `36/36`
  passed.
- Hybrid event, plot, and launcher/UI gates: `22/22` passed; plotting contract
  subsequently rechecked at `4/4` after timeout-marker clarification.
- IEEE14 IBR 15 s event run: `1500/1500` accepted steps, 4324 Newton
  iterations, maximum step residual `8.92e-9`, and `converged=true`.
- Four-GFM post-trip equilibrium KCL norm: `4.58e-11`; 52 complete raw roots
  and 43 physical decision roots, `Omega_physical=-1.48281 1/s`.
- MATPOWER case14 production launcher: PF converged in 5 iterations at
  `6.34e-15 pu` mismatch; SSSA printed all 10 roots; 15 s TS accepted
  `1500/1500` steps with zero non-converged steps and maximum corrector
  residual `5.84e-9`.

Fresh targeted delivery gates passed `84/84`; the partial-failure plotting and
launcher repair gate subsequently passed `26/26`. A repository-wide run on the
pre-repair tree reported `821 total`, `815 passed`, `2 failed`, and
`4 incomplete`. Both failures were stale launcher-test assumptions: one
incorrectly required SSSA evaluation after every selector candidate had
already failed the independently audited SCR/equilibrium gates, and one used
the newly approved 15 s launcher default while retaining a 10-step oracle.
Those tests were corrected against the selector trace and an explicit
0.1 s/0.01 s fixture, then passed in the targeted repair gate. Per explicit
user instruction, the full suite was not rerun after those test-only repairs.
The prior committed full baseline remains `804 total`, `800 passed`,
`0 failed`, `4 incomplete`.

## Honest limitations and readiness

The selector evaluates the correct post-trip context (SG breaker open) and the
four-GFM candidate satisfies frozen `gamma_req=0.1 s^-1` on the physical
tangent spectrum. The complete raw spectrum is still retained for reporting;
locked active-bound directions and the common PLL rotational gauge are
removed before the physical eigenproblem, never by deleting roots afterward.

The 15 s all-four-GFM event demonstration is numerically converged and remains
within the sourced IBR current limits. The SG-on event at 3 s is an accepted
reclose request, not an asserted breaker closure. With the case synchronism
limits it reaches `SYNC_TIMEOUT` at 8 s; `actual_reclose_time=NaN`. This honest
protection outcome is shown as a separate plot marker. A successful reclose
transaction remains covered only by declared test guard overrides and is not
claimed as natural case evidence.

```text
IEEE14_IBR_GFL_MODEL_READY       = STRUCTURAL_ONLY
PHASE_G2_LIMITER_READY           = G2_IMPLEMENTED
IBR_EVENT_RUNNER_READY           = IMPLEMENTED_FAIL_CLOSED
IBR_PRODUCTION_INTEGRATION_READY = NOT_READY
```

Remaining blockers are natural synchronism/reclose evidence and independent
validation. The final full-regression count is pending refresh on this working
tree. No external solver is reachable from production.

## Preserved local material

`docs/text/`, `docs/probes/ieee14_ibr_phaseG/`, the local Thai report source/
PDF, and the archived font/resource file are committed validation/provenance
material by explicit user instruction. They remain unreachable from
production and `pf_init_paths`.
