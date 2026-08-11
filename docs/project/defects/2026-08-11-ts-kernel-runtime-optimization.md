# Switched-TS kernel runtime: 2–3 h per 200-s production run

- **ID:** PERF-2026-08-11-01
- **Status:** RESOLVED (S1+S2 delivered; bit-identity established by targeted
  gates and a whole-arm `fd_structure_check`. The full-production clean-HEAD
  A/B was intentionally not completed — see Verification. S4/S5 hypotheses
  falsified and reverted.)
- **Area:** shared coupled-trapezoidal TS kernel, composite DAE dispatch,
  dual-mode IBR device model
- **Branch / commit observed:** `main`, working tree on top of `b6e510f`
- **Environment:** MATLAB R2026a, Windows 11 Pro 26200

## Symptom

One 200-s switching production run (`dt=0.10`, `max_step_subdivisions=9`,
1 SG + 4 dual-mode IBRs, all-KCL composite DAE) takes 2–3 hours, so no
report number can be re-verified inside a working session.

## Reproduction

```matlab
pf_init_paths;
addpath(fullfile(pwd,'scripts','diagnostics'));
% short surrogate arms (seconds to a minute), same runtime path:
profile_switch_ts_kernel(arms=string({'compressed_fast'}),run_profiler=true);
% authoritative 200-s comparison against the existing cache:
rerun_production_and_compare();
```

## Measurement method, and one measurement error to avoid

`scripts/diagnostics/profile_switch_ts_kernel.m` drives a compressed
switching chronology (all seven event types inside 3.5 s) through
`stability.run_hybrid_case`, i.e. the identical
`ts_simulate_ibr_hybrid → ts_step_composite → composite_newton → forward_fd`
path as production. `scripts/diagnostics/compare_ts_equivalence.m` is the
falsification instrument: it compares two saved results array by array with a
declared tolerance, treats decision fields and event times as exact, and
reports diagnostic counters separately.

Observation worth recording: wall-clock numbers taken in **different** MATLAB
`-batch` sessions on this machine disagreed by up to 2.7x on identical code
(89.97 s vs 33.2 s for the same arm and the same 2725 Newton iterations).
Only A/B measurements taken inside **one** session, alternating the two
variants, were reproducible (±1.5%). Every speedup quoted below is an
in-session A/B; iteration counts and profiler call counts are deterministic
and are quoted directly.

## Root cause, with evidence

Baseline profile of the arm (`output/diagnostics/ts_profile_*_s0b.mat`):

| cost | evidence |
|---|---|
| `matlab.lang.makeValidName` | 2,532,277 calls, ~38% of total time |
| `dev = devices(k)` struct-array copies + per-call index ranges | ~19% |
| device physics proper | ~4% |

(A) `+ibr/eecon49_dual_mode_model.m` rebuilt the event-context field name
from the constant `device_id` with `matlab.lang.makeValidName` on **every**
`dual_f` and `dual_current` call — 8 rebuilds per residual evaluation, for a
value that cannot change during a run. `+stability/sg_composite_device.m` did
the same once per call.

(B) `+stability/composite_dae.m` copied a whole device struct
(`provenance`, `params`, function handles) out of the device struct array and
recomputed its index ranges on every device visit, 10 times per residual
evaluation.

(C) `+stability/ts_step_composite.m/forward_fd` used one residual evaluation
per unknown column: `nz = n_active (49–53) + ny (28)`, i.e. 78–82 residual
evaluations per Jacobian, plus the `r0` evaluation that
`composite_newton.m:90` had just performed at the same point.

## Correction

**S1 — cost per residual evaluation (bit-identical).** The status field name
is computed once per device at construction and threaded through every
closure; `resolve_status`/`set_context_mode` take the resolved key.
`composite_dae` precomputes flat handle/index tables (`dev_f`, `dev_inj`,
`dev_pe`, `dev_recon`, `dev_xr`, `dev_ur`, `dev_has_u`) once and the five
dispatch functions read those instead of indexing the struct array;
`Ibus` starts as `complex(zeros(nb,1))`. `makeValidName` calls in the
residual path: 2,532,277 → 0.

**S2 — residual evaluations per Jacobian (bit-identical).**
`+stability/ts_fd_column_groups.m` (new) derives, from `composite_dae`'s own
dispatch structure alone, which state columns may be perturbed in one
residual evaluation: device k's differential rows read only `x(xr_k)`,
device k's injection lands only on KCL row `bus_map(k)`, and `Y*V` does not
involve `x`, so two state columns with a different owning device **and** a
different mapped bus have disjoint row sets and each takes exactly the
difference quotient it would have taken alone. Algebraic (y) columns are
deliberately **not** grouped: the frozen device ABI hands every device the
whole `y`, so `composite_dae` alone cannot bound which bus voltages a device
reads. Columns per Jacobian: 82 → 41 for the production device set.
`forward_fd` reuses the singleton path byte-for-byte, and the new
`fd_structure_check` option rebuilds the Jacobian per column and requires
exact equality.

Measured, in one session, alternating arms twice each:

| build | wall | Newton iterations | trajectory |
|---|---|---|---|
| per-column FD (`fd_grouping='off'`) | 57.53 s, 56.85 s | 2725 | reference |
| grouped FD (default `'auto'`) | 33.18 s, 33.35 s | 2725 | AbsTol 0 |

**1.72x**, with `x_traj`/`y_traj`/`u_history`/`bus_voltage_magnitude`/
`device_currents`/`device_P`/`device_Q`/`sg_omega`/`sg_freq` bit-identical,
all three diagnostic counters identical, 16 decision fields and 36 event-log
checks identical. A whole arm run with `fd_structure_check=true` (2735
Jacobians) raised no mismatch.

## Falsified hypotheses

**H1 — "the absolute FD step `fd_eps=3e-6` is badly scaled, so Newton
converges linearly."** Falsified by measurement
(`scripts/diagnostics/probe_fd_step_sensitivity.m`, one recorded stiff state
of a sustained current-limited fault, `h=0.20`): the coupled Newton solve
takes **21 iterations for every FD rule tested** — absolute `fd_eps` from
1e-9 to 1e-3 (six orders of magnitude) and the repository's own scaled rule
`fd_eps*(1+|z_j|)` for `fd_eps` from 1e-7 to 1e-5. Only the terminal residual
moves (1.8e-12 … 8.9e-9); the iteration count does not change at all, and
`rcond(J) ≈ 1.95e-5` is identical to three digits across the whole sweep.
Changing the FD rule moves the accepted point by 6.8e-13 … 5.3e-12.

**H2 — "the hard current limiter makes the residual non-smooth, so Newton
cannot converge quadratically."** Falsified in its strong form by the
per-iteration trace: iterations 1–16 crawl with the line search backtracking
to `alpha` between 0.0625 and 0.5 and residual ratios 0.97–0.99, then
`alpha=1` is accepted and the residual collapses
0.9357 → 0.5574 → 6.04e-3 → 1.23e-5, i.e. textbook quadratic convergence in
the same solve with the same limiter active. The residual is smooth enough
for full-step Newton; the iterate simply started outside the basin.

**H3 — "then use an extrapolating predictor for ordinary steps."** At the
single recorded state this looked decisive: `state_predictor='hold'` needs 21
iterations (17 of them backtracks) while `'explicit_euler_kcl'` needs **4**
with `alpha==1` throughout and moves the accepted point by only 3.3e-12.
Falsified end-to-end: over the whole switching arm it is worse **and** not
equivalent — 4083 vs 2725 Newton iterations, subdivision depth 7 vs 5,
`max|dx| = 280.7`. Reverted; the reason is recorded in-source at
`+stability/ts_simulate_ibr_hybrid.m` next to the predictor selection.

**S4 — "require K consecutive clean steps before coarsening the
subdivision hint."** The hint oscillates 0,1,0,1 in a stiff phase, so every
other logical step pays a doomed full-length parent trial that exhausts
`max_iter=50`. Hysteresis was expected to remove that trial with the accepted
leaves unchanged. Falsified: 3829 vs 2725 iterations, wall 45.5 s vs 35.2 s,
`max|dx| = 126`. The published reasoning was wrong — retaining a hint of 2 or
more does not merely skip a doomed trial, it forces a **finer** dyadic
structure than the coarsening path would have accepted. Reverted, with the
finding recorded in-source at `next_subdivision_hint`.

## The structural finding behind both reverts

The published trajectory of this run is fixed not only by the DAE, the
tolerances and the event times but by **which logical steps subdivide**, and
that is decided by whether a step's Newton iteration count reaches
`max_iter=50`. Any change that moves iteration counts therefore changes the
accepted dyadic structure and with it the discretization, producing O(1)
trajectory differences no matter how tight `newton_tol` is. This is why the
declared gate for this work is AbsTol 0 rather than "inside 1e-10": for this
runtime path a small-but-nonzero difference is not a tolerance ball, it is a
different discretization. Optimizations that leave every iterate bit-identical
(S1, S2) are admissible; optimizations that change iterate values or counts
are not, unless a full-horizon rerun proves otherwise.

Note the asymmetry the measurements support: the FD **rule** does not change
the iteration count (H1 sweep, 21 iterations for every rule), while the
initial guess and the subdivision hint do. A Jacobian-side change is
therefore not automatically excluded; it needs a full-horizon rerun as its
gate, which is exactly what remained un-run when this record was written.

## Remaining lever, deliberately not taken

After S1+S2 the profiler still attributes ~78% of the run to residual
evaluation (`coupled_residual`: 128,361 calls, 49.8 s of 64.1 s profiled),
and 41 of the 47 residual evaluations per Jacobian are FD columns. Of those
41, **28 are algebraic (y) columns** — the block that S2 deliberately did not
touch.

Two ways to shrink it, both examined:

1. *Bit-identical y colouring.* Column j at bus b can only touch the
   differential rows of devices at b and the KCL rows i with `Y(i,b) ~= 0`, so
   two y columns may share a group iff their buses share no neighbour — a
   distance-2 colouring of the admittance graph. On IEEE-14 the distance-2
   graph is nearly complete (bus 4 alone reaches buses 2,3,5,7,9), so the
   estimated gain is 28 → roughly 20–24 columns. Not worth the machinery, and
   it would additionally require every device to *declare* bus-local y access
   rather than have it verified by inspection.
2. *Analytic `d(Y*V)/dy`.* `g = Y*V - Ibus` is exactly linear in y through the
   network term, so that block can be written analytically and FD applied only
   to `Ibus`, whose y dependence is bus-local. Then no two y columns conflict
   at all: 28 → 2 groups, i.e. 41 → 15 columns, an estimated further ~2x.
   This is **not** bit-identical: it replaces an FD approximation with the
   exact block. The measured evidence that it might still be admissible is
   that the FD *rule* does not move the iteration count (H1 sweep) and moves
   the accepted point by ~1e-12; the risk is the discretization sensitivity
   documented above. Its only valid gate is a full-horizon rerun, so it needs
   explicit authorization and a run budget, and it is left undone here.

Also left undone deliberately: `+ibr/dual_mode_ibr_model.m:352` still rebuilds
its status key per call. That device family (`regfm_b1_dual`) is not on the
production switching route, so the change would carry risk without a covering
gate in this work's targeted suite.

## Verification

- Targeted gate, 10 files, **102/103 pass**. The single failure is
  `test_ts_shared_kernel/test_algebraic_residual_in_tol_range`, proven
  pre-existing and unrelated — see
  [stale algebraic lease test](2026-08-11-stale-algebraic-lease-test.md).
- `tests/test_ts_fd_column_groups.m` (new, 9 tests): partition cover and
  group count, no group sharing a device or a bus, grouped == per-column via
  `fd_structure_check` at equilibrium / off equilibrium / with a faulted Y,
  `fd_grouping` auto vs off giving identical `x_full`/`y_full`/`iterations`/
  `residual_norm`/`rcond` at AbsTol 0, six fail-closed precondition cases,
  the shared-bus counterexample that forced the "no shared device **and**
  no shared bus" rule instead of "one column per device", and three
  `fd_perturbation` tests (default scalar step byte-identical to the implicit
  path; grouping exact under a per-column vector step; unknown rule rejected).
- `compare_ts_equivalence` at `tol=0` after every stage, on the compressed
  switching arm: PASS.
- Whole-arm `fd_structure_check=true` (2735 Jacobians) on the compressed arm:
  no mismatch — the grouped and per-column Jacobians are byte-identical at
  every step. Because `ts_fd_column_groups`' derivation is structural (it
  reads `composite_dae`'s dispatch layout, never the state or `Ynet`), this
  exactness does not depend on the trajectory, so it also holds on the states
  the full production chronology reaches (reclose/handback) that the
  compressed arm does not.
- 200-s production rerun: completed in **1219 s (20.3 min)** vs the 2–3 h
  baseline; converged; reached t=200.000; reclose **SYNC_TIMEOUT** at the
  CASE_DEFINED deadline (sg_on 145 + timeout_s 20 = t=165), reselection
  NOT_REQUESTED — i.e. the decisions the current `production_request` config
  gives at this code state. **Correction (2026-08-12):** an earlier revision
  of this record stated "reclose SUCCESS at 154.3 s, reselection at 159.2 s,
  handback complete" for this rerun. That was wrong: those SUCCESS values
  belong to the stale diagnostic-variant cache (`engine_release_result.mat`
  produced by `run_engine_release_tmp.m` with support supervision off,
  timeout_s=5, at an older code state), not to the rerun. Independently
  confirmed by a fresh 250-s run at `dt=0.01` (27.5 min, converged,
  t(end)=250): it also gives `reclose=SYNC_TIMEOUT at NaN` — the timeout is
  dt-independent and config/gate-driven, not a timestep artifact. The
  misattribution arose from misreading the direction of the
  `compare_ts_equivalence` output (cache vs rerun). No numerical result in
  this record depends on the misattribution: bit-identity was established by
  the compressed arm and `fd_structure_check`, and the rerun's role was
  wall-clock only.
- Full-production clean-HEAD (`b6e510f`, per-column FD) vs my-tree A/B at
  `tol=0`: **intentionally not completed.** It was launched (to confirm S1+S2
  bit-identity on the exact production path including reclose/handback) but
  stopped at t≈70 s per the maintainer's decision to accept the targeted-gate
  evidence rather than wait ~35 min for a redundant confirmation. The change
  is a pure refactor: S1 threads a provably-identical constant key and reads
  identical handles/indices; S2's grouped FD is proven byte-identical by
  `fd_structure_check` above. No trajectory tolerance is being spent — the
  delivered numbers equal current main's — so the skipped A/B lowers
  confirmation redundancy, not delivered accuracy.

## Limitations

- No test in the repository pins an absolute trajectory of
  `ts_simulate_ibr_hybrid`, and
  `test_event_disabled_is_canonical_bit_identical` compares two routes that
  call the same `ts_step_composite`, so it passes even if that step changes.
  `compare_ts_equivalence` against a stored result is the only instrument
  that can falsify a trajectory change; the targeted suite cannot.
- The reference cache `engine_release_result.mat` is a **200-s** run
  (`r.t(end) = 200.000000`, 2016 samples), not the 250-s horizon that
  `generate_ieee14_switch_report_figures.m:33` declares. The comparison is
  run at 200 s for that reason; a 250-s run is a separate job.
- S1's end-to-end contribution was not isolated in-session because the change
  is not switchable at runtime. Its evidence is the profiler call count
  (2,532,277 → 0) and the S0 profile's 38% attribution, not a wall-clock A/B.
- The `composite` profiling arm routes through `ts_simulate_composite`
  (`run_hybrid_case.m:167-202` sends `ibr_events.enabled=false` there), so it
  does **not** cover the event supervisor. Only the compressed arm and the
  production rerun do.

## Related files

- `+stability/ts_fd_column_groups.m` (new), `tests/test_ts_fd_column_groups.m` (new)
- `+stability/ts_step_composite.m` (`fd_grouping`, `fd_structure_check`,
  `fd_perturbation`, grouped `forward_fd`)
- `+stability/composite_dae.m`, `+stability/sg_composite_device.m`,
  `+ibr/eecon49_dual_mode_model.m`, `+ibr/dual_mode_ibr_model.m`
- `+stability/ts_simulate_ibr_hybrid.m`, `+stability/run_hybrid_case.m`
  (FD-knob forwarding; falsified-alternative notes)
- `scripts/diagnostics/profile_switch_ts_kernel.m`,
  `scripts/diagnostics/compare_ts_equivalence.m`,
  `scripts/diagnostics/probe_fd_step_sensitivity.m`,
  `scripts/diagnostics/rerun_production_and_compare.m` (all new)
- [stale algebraic lease test](2026-08-11-stale-algebraic-lease-test.md)
