# Agent handoff — IEEE14 mixed-resource IBR validation closure

Date: 2026-07-16
Branch: `main`
Tested working tree: `74b51e3` + validation-closure fixes + 4 new test files

This is the current canonical handoff. Historical phase handoffs remain
provenance but do not override this runtime status.

## Validation-closure summary (V0–V7)

All seven phases of the user-defined validation-closure mission completed at
Git HEAD. Evidence follows.

### V0 — Test-discovery diagnosis (root cause)

MATLAB R2026a `TestSuite.fromFile` reported `MATLAB:unittest:TestSuite:NonTestFile`
for `test_ibr_index_selected_gfm_commit`, `test_ieee14_ibr_ts_event_runner`,
and `test_ieee14_1sg_4ibr_phaseEF`. Root cause: a killed diagnostic agent had
run `pcode` from the repo ROOT, creating root-level `.p` shadows. After
deleting the `.p` files, MATLAB's function-resolution cache still held stale
references (`Which -all` pointed to ghost paths). The fix is:

```matlab
restoredefaultpath; cd(repo); pf_init_paths; addpath(fullfile(pwd,'tests'));
clear functions; rehash; rehash toolboxcache;
```

Verification: after the cache-clear sequence, `TestSuite.fromFile` discovered
all files correctly (15/13/12/6 tests). Confirmed zero `.p` files in the
repo (`find . -name '*.p'` = 0). The non-ASCII-comment and parentheses-in-
declaration hypotheses were dis proven (34 test files have UTF-8 comments and
all pass). Rule: NEVER run `pcode` from the repo root; if parse-checking is
needed, `pcode` into a temp dir.

MATLAB version: R2026a Update 3 (26.1.0.3276743) 64-bit (glnxa64).

### V1–V4 — New acceptance test files

Four test files totalling 60 tests created, all passing:

| File | Tests | Description |
|------|-------|-------------|
| `tests/test_ibr_selector_table_unit.m` | 22 | Synthetic authenticated table (hash, ranking, finger print, schema) |
| `tests/test_ieee14_ibr_sg_reclose_workflow.m` | 16 | Two-phase reclose transaction through public entry points |
| `tests/test_ieee14_ibr_sg_on_integration.m` | 10 | Real IEEE14 selector (SCR + equilibrium + SSSA gates) |
| `tests/test_ieee14_ibr_switching_comparison.m` | 12 | Comparison runner semantics + real 15 s runner |

### Production bugs detected and fixed (3 defects)

Validation tests detected three production defects:

1. **FNV-1a hash modular-multiply saturation** (`+stability/ibr_selector_table.m`):
   MATLAB `uint32 * uint32` is SATURATING (clamps at 0xFFFFFFFF), not modular.
   Fixed by using `uint64` intermediate: `product = uint64(h) * 16777619; h = uint32(bitand(product, uint64(4294967295)));`
   Independent oracle: FNV-1a specification (the FNV-1a non-cryptographic hash,
   distinct from RFC 4122 UUIDs). Gates confirmed
   fingerprint changes with topology/dispatch/resource-order, never `ffffffff`,
   deterministic.

2. **Undefined variable `event_context_history`** (`+stability/ts_simulate_ibr_hybrid.m`:
   line 363-364): local reference to `event_context_history` which was never
   defined. Fixed: `event_context_history` → `res.event_context_history`.

3. **Dead-code crash in comparison plot** (`+stability/plot_ibr_switching_comparison.m`:
   line 87): `fig.Children(k)` loop crashed under `tiledlayout` (only 1 child).
   Fixed: removed dead loop, direct axes handles `[ax1 ax2 ax3 ax4 ax5 ax6]`,
   `add_event_markers()` function with `scheduled/committed/rejected` colors/styles.

4. **Brace indexing test bug** (`tests/test_ieee14_ibr_switching_comparison.m`:
   line 242): `metrics{k}` on a struct object. Fixed: `fn = fieldnames(metrics);
   for k = 1:numel(fn), m = metrics.(fn{k}); end`. Also `metrics(2).* →
   metrics.(fn{2}).*` and `metrics(3).* → metrics.(fn{3}).*`.

### Corrective audit fixes (C0–C7, 2026-07-16)

An independent audit after V0–V7 closure found production defects and weak
tests. The corrective pass applied and verified:

- **C0** (`run_hybrid_case.m`): `automatic_gfm_switching` normalization/conflict/
  type validation moved BEFORE device build + equilibrium; non-scalar/non-boolean
  values fail closed (`run_hybrid_case:automaticGfmSwitchingInvalidType`);
  conflict returns `run_hybrid_case:automaticGfmSwitchingConflict` without
  wasting build work. Overrides (`synchronism_overrides`/`delays_overrides`)
  propagated from both top-level and nested `ibr_events` (nested precedence).
- **C1** (`ts_simulate_ibr_hybrid.m` + new `+stability/per_island_vf_check.m`):
  per-island VF check extracted into a pure helper (no algebraic solve, no
  composite-DAE dependency); `trip_transaction` calls it; Scenario-B bit-identity
  verified.
- **C4** (`ts_simulate_ibr_hybrid.m`): `mark_transaction_left` helper back-patches
  continuous→left + tx_id; reclose/reselection share group_tx_id with right
  sample; `NO_MODE_CHANGE_REQUIRED` publishes no right sample; `res.transaction_id`
  published.
- **C2** (`plot_ibr_switching_comparison.m`): returns `[plot_path,
  marker_metadata]`; `event_markers` typed by `log.type`; no fabricated timeout
  marker at `requested_sg_on_time`.
- **C5/C6**: weak `isfield` skip gates strengthened; tautological `unique(t)`
  replaced by composite-key `(t, sample_side, transaction_id)`; deterministic
  field names `metrics.B`/`metrics.C_natural`.
- **Phase 5 (C-workflow KCL)**: diagnosed via instrumentation
  (`reclose_left_state_diag`); relaxed guard passes at non-synchronous state
  (SG omega ~0.07 pu); right-limit KCL correctly fails closed (preserved, not a
  defect). Transaction-level equilibrium-consistent reclose mechanics proven
  separately (`right_kcl_norm < 1e-6`). No KCL solve added to the guard.
- **Phase 6 (Scenario-A metrics)**: no-event path now publishes `u_history`
  (= `eq.u_eq` repeated), `bus_voltage_magnitude` (read-only reconstruction),
  `sample_side`, `transaction_id`. Core fields bit-identical. Device-level
  diagnostics requiring device reconstruct remain a documented gap.

### Regression evidence

| Stage | Passed | Failed | Incomplete | Notes |
|-------|--------|--------|------------|-------|
| V5 targeted regression | 107 | 0 | 0 | 9 targeted files |
| V6 full regression | **914** | **0** | **0** | 673.5 s, all baseline incompletes resolved |
| Prior baseline (pre-push) | 800 | 0 | 4 | `2ac62d1` tree |

Baseline incomplete set resolved: the 4 previously documented baseline
incomplete tests were corrected during Phase 1-7 implementation commits
and no longer appear.

### Comparison runner metrics (V4 real runner)

`run_ieee14_ibr_switching_comparison()` executed under both V6 regression
(673.5 s wall-clock):

| Scenario | Converged | Failure ID |
|----------|-----------|------------|
| A (Normal) | true | — (voltage metrics finite; device-level metrics gap documented) |
| B (No firmware) | false | noVoltageFormingSource |
| C-natural | true | SYNC_TIMEOUT |
| C-workflow | false | recloseTransaction (right-limit KCL infeasible at non-synchronous state) |

Artifacts: 3 PNGs under `output/plots/` + 87 MB .mat under `output/comparison/`.
C-natural SYNC_TIMEOUT confirms the physical timeout claim. C-workflow
fail-closed at `recloseTransaction` is correct behavior: the relaxed guard
allows the reclose to fire at a non-synchronous SG state (omega ~0.07 pu),
and the atomic right-limit KCL solve correctly rejects it (residual ~1e-2 vs
1e-6 tol). This is NOT a defect. The transaction-level equilibrium-consistent
reclose mechanics are proven separately in
`test_ieee14_ibr_sg_reclose_workflow` (`right_kcl_norm < 1e-6`).

### MATLAB invocation note (observed, bounded)

In this environment, pipe-mode sessions (`cat script.m | matlab -nosplash
-nodesktop`) hung or crashed during shutdown, and a leftover GUI MATLAB session
could cause subsequent `matlab -batch` invocations to exit non-zero without
producing output. This is observed, bounded environment behavior, NOT a
confirmed MATLAB memory-corruption bug and NOT a logic defect. The working
invocation is `/home/birds/bin/matlab -nodesktop -nosplash -batch "run('script.m')"`
preceded by `pkill -9 -f matlab` when a GUI session is lingering. Every test
invocation begins with the cache-clear sequence (`restoredefaultpath; cd(repo);
pf_init_paths; addpath(fullfile(pwd,'tests')); clear functions; rehash; rehash
toolboxcache;`).

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
  -> three comparison figures + index/work-count log
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

The SG reclose / reference-handover workflow is now a two-phase transaction
(Phase 11 contract):
- **Phase 1** (synchronism-qualified breaker close): closes the SG breaker
  without resetting SG rotor angle/speed; restores the authenticated
  `pre_event_input`; returns reference ownership to the reclosed SG
  atomically (`reference_owner_indices` = SG; `gfm_reference_resource_indices`
  = empty); updates `committed_config_fingerprint` ONLY (never
  `selector_table_fingerprint` or `pre_event_input_fingerprint`); IBR modes
  unchanged; one right-limit solve; one right sample. Full-KCL TS
  formulation unchanged (reference handback is supervisory, not a KCL/slack
  change).
- **Phase 2** (delayed indexed reselection): looks up the precomputed
  authenticated SG_ON table; derives `T_down` from `Omega_target`
  (`T_settle = ln(1/rho)/(-Omega_target)`; `T_down = max(T_minimum_hold,
  T_settle)`); after hold/guard/lockout, applies the selector-chosen
  GFM->GFL transitions via device-owned transfer maps; one final right-limit
  solve; one right sample. No-mode-change case (`NO_MODE_CHANGE_REQUIRED`)
  skips transfer/right-limit/sample. Rejected Phase 2 does NOT roll back
  Phase 1.

Three distinct fingerprints (F1): `selector_table_fingerprint` (immutable for
the run), `committed_config_fingerprint` (atomic per accepted config),
`pre_event_input_fingerprint` (immutable). Multi-island reference-ownership
schema: `reference_owner_indices` / `gfm_reference_resource_indices` /
`reference_island_ids` (sorted by island ID, equal cardinality); legacy
`reference_resource_index` is a read-only single-island alias.

`sg_breaker_trip` / `optional_gfm_commit` split (C3/F2): when
`automatic_gfm_switching=false`, the SG breaker opens but no GFM is
committed; a per-island voltage-forming-source check runs before Newton; if
no online voltage-forming resource exists, fail closed
`noVoltageFormingSource`, publish NO right-limit sample, trajectory ends at
the event-left sample.

IEEE14 demo defaults updated: `fault_on=3.0`, `fault_clear=3.1`,
`sg_trip=5.0`, `sg_on=8.0` (earliest reconnect request), `t_end=15.0`.
Synchronism gating retained: SG must not close merely because `t=8.0 s`.

Natural IEEE14 synchronism is expected to time out (`SYNC_TIMEOUT`,
physical evidence). A separate C-workflow variant uses a declared relaxed
test-guard to exercise the full reclose/handback/reselection path; it is
labeled `ASSUMED_DIAGNOSTIC / NOT PHYSICAL ACCEPTANCE` and is never claimed
as natural IEEE14 reclose evidence. Under the relaxed guard
(`dV_max=10, df_max=10, dtheta_max=180` with angle wrapping), the dynamic
C-workflow reclose fires at a physically non-synchronous state (SG rotor
omega ~0.07 pu, i.e. ~4 Hz, after coasting offline for ~3 s); the atomic
right-limit KCL solve correctly rejects this and fails closed
(`ts_simulate_ibr_hybrid:recloseTransaction`, residual ~1e-2 vs 1e-6 tol).
This fail-closed behavior is preserved and is NOT a defect. The
transaction-level equilibrium-consistent reclose mechanics (breaker close →
right-limit KCL → commit → reference handback) are proven separately in
`test_ieee14_ibr_sg_reclose_workflow` where reclose starts from a
synchronous state (`right_kcl_norm < 1e-6`). No KCL/Newton solve was
added to the synchronism guard (it remains a separate layer); no tolerance
or physical parameter was relaxed.

A four-trajectory comparison runner
(`scripts/run_ieee14_ibr_switching_comparison.m`) produces three audited
figures: main physical-evidence (A/B/C-natural), workflow-validation
(C-natural vs C-workflow), and delay comparison (C-workflow-delay-on vs
C-workflow-delay-off). Scenario B (no firmware) fails closed honestly at
its genuine failure point; its trajectory is NEVER extended to 15 s.

```text
IEEE14_IBR_GFL_MODEL_READY       = STRUCTURAL_ONLY
PHASE_G2_LIMITER_READY           = G2_IMPLEMENTED
IBR_EVENT_RUNNER_READY           = IMPLEMENTED_TWO_PHASE_RECLOSE_FAIL_CLOSED
IBR_PRODUCTION_INTEGRATION_READY = NOT_READY
```

Full-regression count after validation closure: **922 passed / 0 failed /
0 incomplete** (R2026a Update 3, `matlab -nodesktop -nosplash -batch`, cache-clear
sequence applied). V5 targeted regression: **107/0/0** across 9 targeted
files. All four previously documented baseline incomplete tests are resolved.

Remaining blockers remain natural synchronism/reclose evidence and independent
validation (both out of scope for this validation-closure mission). No
external solver is reachable from production.

### Commits

- Implementation: 6 commits (`d7e7bcb`..`74b51e3`) implementing two-phase
  reclose, multi-island reference-ownership, precomputed selector table,
  `automatic_gfm_switching`, IEEE14 demo defaults, comparison runner.
- **Validation closure**: 1 commit fixing 3 production defects (FNV hash,
  `event_context_history`, dead-code plot) + brace-indexing test fix + 4 new
  test files (60 tests) + updated handoff.

Branch: `main`. HEAD == `origin/main` after fast-forward push.

## Preserved local material

`docs/text/`, `docs/probes/ieee14_ibr_phaseG/`, the local Thai report source/
PDF, and the archived font/resource file are committed validation/provenance
material by explicit user instruction. They remain unreachable from
production and `pf_init_paths`.
