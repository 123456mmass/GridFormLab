# IBR-2026-07-16-01 — IEEE14 IBR corrective validation defects

Status: `RESOLVED`  
Area: IEEE14 generic mixed-resource IBR hybrid TS and comparison validation  
Observed on: `main` at committed base `1295438`, with uncommitted corrective work  
Environment: MATLAB R2026a Update 3 on Linux

## Observed defects

1. `automatic_gfm_switching=false` may be supplied inside `ibr_events`, while
   `run_hybrid_case` historically read only the top-level option and defaulted
   to `true`. Scenario B could therefore execute the automatic GFM path.
2. The no-firmware post-trip voltage-forming check searched globally for any
   voltage-forming device instead of requiring one in every energized island.
3. Raw samples stored a transaction ID internally but did not publish it, and
   scheduled, reclose, and reselection boundaries did not consistently share
   one left/right transaction identity.
4. Natural-synchronism tests used diagnostic threshold overrides and shortened
   event times while describing the result as public IEEE14 physical evidence.
5. Scenario-B tests accepted broad failure outcomes, and one fixture placed
   `sg_on` after `t_end`, allowing schedule validation to fail before reaching
   the intended runtime path.
6. Candidate rejection metadata was created separately from the public event
   log and could be lost or replaced by empty fields instead of preserving the
   rejected candidate modes and failing island IDs.
7. Comparison markers grouped events only as scheduled/committed/rejected,
   lost event identity, and could place or duplicate timeout markers at the
   reconnect-request time rather than the actual timeout.

## Reproduction and evidence

Inspect the production and test paths with:

```bash
rg -n "automatic_gfm_switching|noVoltageFormingSource|transaction_id" \
  +stability/run_hybrid_case.m +stability/ts_simulate_ibr_hybrid.m \
  tests/test_ieee14_ibr_*.m
rg -n "event_times|sg_reclose_timeout|requested_sg_on_time" \
  +stability/plot_ibr_switching_comparison.m
```

For MATLAB verification, begin every invocation with the repository cache
reset sequence documented in `docs/project/AGENT_HANDOFF.md`, then run the
targeted IEEE14 IBR comparison, reclose, integration, plotting, event-runner,
and no-external-solver tests. A test that exits early on non-convergence is not
evidence that its intended runtime path executed.

## Root causes established so far

- Runtime option ownership was split between top-level options and the nested
  event schedule without one canonical normalization point.
- Island-aware infrastructure existed, but the no-firmware trip branch used a
  global early-exit scan instead.
- Transaction identity was added incrementally to right-side samples rather
  than designed around a complete coincident-group boundary.
- Several tests asserted permissive outcomes or adjusted fixtures around the
  desired behavior instead of proving that the intended branch executed.
- Plot marker extraction discarded event type while aggregating status.

These statements describe inspected code paths. They do not claim the current
uncommitted corrective implementation is verified.

## Falsified or incomplete hypotheses

- The recent Scenario-B failure was not solely a stale MATLAB cache problem;
  at least one test fixture failed schedule ordering before exercising the
  target branch.
- `transition_failure` does not inherently delete arbitrary struct fields. The
  material issue is whether candidate fields are copied into the public event
  log with a uniform struct-array schema.
- A passing suite is insufficient when the test returns early on
  non-convergence or accepts unrelated failure identifiers.

## Required correction and verification

- Normalize and validate the switching flag before schedule construction;
  conflicting representations fail closed with a structured public result.
- Check every energized island using project-owned island detection and add a
  synthetic two-island regression.
- Define one transaction identity per committed/rejected boundary, publish it,
  and test left/right/rejected sample semantics without fallback assertions.
- Preserve actual rejected-candidate modes, commitment status, and failing
  island IDs in the public event log.
- Run the public 15-second natural IEEE14 timeline without diagnostic guard or
  delay overrides; keep diagnostic workflow runs explicitly labelled.
- Return typed marker metadata and test actual event identities and times.
- Run proportional targeted tests, the real comparison runner, and the full
  regression on the final production tree before marking this record resolved.

## Resolution log

- `2026-07-16`: Record created during corrective work. Production edits were
  present but targeted tests, marker correction, full regression, documentation,
  commit, and delivery were not yet complete. Status remains `OPEN`.
- `2026-07-16` (update): Corrective pass executed against the approved plan.
  Production fixes applied and verified:
  - **C0**: `automatic_gfm_switching` normalization/conflict/type validation
    moved BEFORE device build + equilibrium in `run_hybrid_case.m`; non-scalar/
    non-boolean values fail closed with a structured result
    (`run_hybrid_case:automaticGfmSwitchingInvalidType`); conflict returns
    `run_hybrid_case:automaticGfmSwitchingConflict` without wasting build work.
    Overrides (`synchronism_overrides`/`delays_overrides`) now propagated from
    both top-level and nested `ibr_events` (nested takes precedence).
  - **C1**: per-island VF check extracted into pure helper
    `+stability/per_island_vf_check.m` (no algebraic solve, no composite-DAE
    dependency); `trip_transaction` calls it; Scenario-B bit-identity verified
    (failure_id, failing_island_ids, candidate_modes unchanged).
  - **C4**: `mark_transaction_left` helper back-patches continuous→left + tx_id;
    reclose/reselection share group_tx_id with right sample; `NO_MODE_CHANGE_REQUIRED`
    publishes no right sample; `res.transaction_id` published.
  - **C2**: `plot_ibr_switching_comparison` returns `[plot_path, marker_metadata]`;
    `event_markers` typed by `log.type`; no fabricated timeout marker.
  - **Phase 5 (C-workflow KCL)**: diagnosed via instrumentation
    (`reclose_left_state_diag` on failed reclose event log). Root cause: relaxed
    guard (`df_max=10`, `dtheta_max=180` with angle wrapping) passes at a
    non-synchronous state (SG omega ~0.07 pu, ~4 Hz after coasting ~3 s);
    right-limit KCL correctly fails. Observed at the failed close: nonzero SG
    speed deviation, relaxed guard acceptance, and rejected KCL. Inferred from
    the EMF6 breaker/current-injection equations: closing at that state
    introduces an incompatible stator-current injection. **The current jump was
    not directly measured** (the transaction was rejected, so no committed
    post-close state exists to measure against; the diagnostic records rotor
    state, bus voltage, guard margins, and the right-limit residual, but never
    computes stator current). Dynamic C-workflow stays fail-closed (preserved,
    NOT a defect). Transaction-level equilibrium-consistent reclose mechanics
    proven in `test_ieee14_ibr_sg_reclose_workflow` (`right_kcl_norm < 1e-6`).
    No KCL/Newton solve added to the synchronism guard (separate layers
    preserved); no tolerance/parameter relaxed.
  - **Phase 6 (Scenario-A metrics)**: no-event path now publishes `u_history`
    (= `eq.u_eq` repeated), `bus_voltage_magnitude` (read-only reconstruction
    from `y_traj`), `sample_side`, `transaction_id`. Core fields
    (`t`, `x_traj`, `y_traj`, `converged`, `residual_per_step`, `iter_per_step`)
    remain bit-identical. Device-level diagnostics requiring device reconstruct
    (`coi_frequency_Hz`, `device_P_MW`, `device_modes_history`) are NOT produced
    on the no-event path — documented gap, not a regression.
  - **C5/C6**: weak `isfield` skip gates strengthened; tautological `unique(t)`
    replaced by composite-key `(t, sample_side, transaction_id)`; deterministic
    field names `metrics.B`/`metrics.C_natural`.
  - **C7**: handoff corrections applied (`ecode`→`pcode`, RFC 4122 garble
    removed, "memory corruption bug" replaced with observed bounded evidence,
    `testtests`→`tests`, "two plots"→"three comparison figures", C-natural vs
    C-workflow distinction clarified).
  Targeted tests pass (switching_comparison 19/19, sg_on_integration 11/11,
  sg_reclose_workflow 16/16). Full regression: **922 passed / 0 failed /
  0 incomplete / 0 errored** (R2026a Update 3, `matlab -nodesktop -nosplash
  -batch`, ~18.5 min). Status flipped to `RESOLVED`.

## Follow-up (tested on SHA-A `df5f97d`)

A post-delivery review found the C-workflow diagnostic evidence was partly
over-claimed. This follow-up fixed two production bugs, corrected the evidence
narrative, and added the targeted assertions that were previously missing.

### Production bug 1 — `df_pu` used the wrong frequency convention

- **Previous (bad) expression:** in `reclose_left_state_diag`
  (`+stability/ts_simulate_ibr_hybrid.m`), `diag.df_pu = abs(rec.omega - 1.0)`.
  This inflates a real ~0.07 pu slip to ~0.93 pu.
- **Corrected convention:** `diag.df_pu = abs(rec.omega)`.
- **Independent oracle:** the hybrid route calls `synchronism_guard(...,
  rec.omega, 0.0f, gopt)` (`ts_simulate_ibr_hybrid.m`) with `omega_ref=0.0`,
  so `rec.omega` IS the frequency deviation. Therefore `df_pu` must equal
  `abs(sg_omega)`. Verified both by the new assertion and by an independent
  read-only probe (`df_pu == abs(sg_omega)` to 17 digits: both = 0.07309…).
- **Previous test defect:** the C-workflow test asserted only that
  `reclose_diag`/`sg_omega` are present and `sg_omega < 0.5` — it never checked
  the `df_pu` convention, so the suite passed despite the bug. Fixed by adding
  a `df_pu == abs(sg_omega)` assertion, verified red-then-green.

### Production bug 2 — no-event `sample_side` contract diverged from the hybrid route

- **Previous (bad) contract:** `run_hybrid_case` set ALL samples to
  `'continuous'` including `t=0`.
- **Corrected contract:** first sample `'initial'`, all others `'continuous'`.
- **Independent oracle:** the hybrid route's `new_samples()` sets the first
  sample's side to `'initial'` (`ts_simulate_ibr_hybrid.m`). Verified by a new
  assertion (`sample_side{1}=='initial'`, rest `'continuous'`,
  `transaction_id` all zeros), red-then-green.
- **Previous test defect:** the Scenario-A test asserted only `numel ==
  numel(t)`, not per-sample values, so it passed despite the divergence.

### Evidence narrative corrected

- **right_norm:** a prior narrative claimed `right_norm == Inf` and cited a
  residual ~1.53e-2 from the `ts_algebraic_solve:failed` string as the KCL
  residual. Both were wrong. A read-only probe of
  `rec_log.reclose_diag.right_norm` (same C-workflow config, public entry
  point `run_hybrid_case`, no code modified) returns exactly **Inf** — meaning
  the algebraic right-limit solve returned no finite accepted residual. The
  ~1.53e-2 value is the *solver's own convergence failure* reported in the
  failure-id string, a different field. Honest report: `right_norm = Inf`.
- **Current jump:** the mechanism "SG stator current jumps 0→large at the
  breaker close" was reclassified from *measured* to **inferred**. The reclose
  transaction was rejected, so no committed post-close state exists to measure
  against; the diagnostic records rotor state, bus voltage, guard margins, and
  the right-limit residual, but never computes stator current. The narrative
  now reads: "Observed: nonzero SG speed deviation, relaxed guard acceptance,
  and rejected right-limit KCL. Inferred from the EMF6 breaker/current-injection
  equations: closing at that state introduces an incompatible stator-current
  injection. The current jump was not directly measured."

### Verification

- **Tested source SHA-A:** `df5f97d0b153f636ec21c134c2f4860d94d7efcb`
  (fast-forwarded to `origin/main` before regression). SHA-A contains only
  the two production fixes + the two new assertions; the documentation edits
  in this record land in a later commit, so the record references a stable SHA.
- **Targeted regression on SHA-A:** **58/0/0** across 4 files
  (switching_comparison 19, sg_reclose_workflow 16, sg_on_integration 11,
  ts_event_runner 12).
- **Full regression on SHA-A:** **922 passed / 0 failed / 0 incomplete /
  0 errored** (R2026a Update 3, `matlab -nodesktop -nosplash -batch`).
- Current-jump classification changed: measured → **inferred**.
- No IBR architecture redesign; no tolerance/parameter/threshold relaxed.
