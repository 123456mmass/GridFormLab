# IBR-2026-07-17-01 — Fixed IEEE14 GFM commit indices + single-count/single-result selector table

Status: `OPEN`  
Area: Generic automatic GFM selection — selector-table enumeration + fingerprint ownership  
Observed on: `main` at the Mission-B kickoff checkpoint (origin/main `997a990`)  
Environment: MATLAB R2026a on Linux

## Re-opened (Revision 3)

Marked RESOLVED prematurely. Blockers remain:
1. Schedule still forces manual fields for automatic mode (`ibr_event_schedule.m:84`).
2. Fingerprint only checks non-empty string; no current-input / actual-topology data flow.
3. Cross-count ranking broken (rank_authenticated_candidates hardcodes count=0); no runtime rerank.
4. No N_exhaustive_max guard before enumeration.
5. Per-island ownership hard-coded to island 1 (`sg_event_handler.m:105`).
6. `find(X,1)` selection regression fixed in Phase 3; schema closure (Phase 4b) not yet done.
7. Phase 5–9 not delivered.

Phase 3/4a history that passed is preserved below.

## Observed defects

The production `automatic_gfm_switching` path claims to be selector-owned, but two
defects in `+stability/ibr_selector_table.m` plus one in `solve_case.m` kept the
decision tied to a single hardcoded IEEE14 count/subset instead of the full
authenticated candidate universe:

1. **Single-count table.** `build_context` enumerated only **one**
   `n_gfm_required` count per context (default 1 for SG_OFF, 0 for SG_ON) instead
   of the whole feasible band. The table could therefore never discover that a
   different count (or fewer GFMs) is feasible and preferred by the frozen
   ranking policy.
2. **Single-result fingerprint.** `build_fingerprint` hashed only
   `sg_off_selected` / `sg_off_omega` / `sg_on_selected` / `sg_on_omega` — the
   single selected result per context — instead of the complete cached candidate
   universe. A change in any non-selected candidate, or a feasibility/count flip,
   would not invalidate the table.
3. **Fixed IEEE14 literals.** `solve_case.m` hardcodes the automatic defaults
   `selected_gfm_indices=2:5`, `reference_resource_index=2` (handled in the
   literals-migration phase).

## Reproduction and evidence

Read-only Phase 0 audit (`docs/project/plans/IEEE14_GENERIC_MIXED_RESOURCE_EXECUTION_PLAN.md`)
dumped the payload: `configurations` was exactly `[1×1 struct]` per context with
`counts` collapsing to the single default, and the fingerprint embedded only the
single selected set. The candidate universe for Neligible=4 spans counts 1..4
(~15 subsets), yet the table cached one.

Verify the table path with the targeted selector-table unit suite:

```bash
cat _run_phase3_targeted.m | /home/birds/bin/matlab -nodesktop -nosplash
```

## Root cause

The table treated the selector as a single-answer cache keyed by the default
count rather than as a precomputed authenticated universe. Ranking policy was
only ever applied to one caller-pinned count, and the fingerprint scoped to the
one surviving answer — so the table could not authenticate that its single
answer was exhaustive, nor could it adapt when a different count dominates.

## Correction

`+stability/ibr_selector_table.m`:

- `build_context` now enumerates **every count in the safe feasible band**
  `cmin:cmax` (cmin=1 SG_OFF / 0 SG_ON, cmax=#eligible switchable dual-mode
  IBRs) and accumulates all candidates into one flat array sharing one struct
  template. The frozen ranking policy decides the winner; topology-infeasible
  counts are rejected by the evaluator inside the band, so the policy still
  picks the physically correct count. A caller pin (manual_override / explicit
  `n_gfm_required`) still collapses the band to one.
- `feasible_count_range` / `uncovered_island_min` / `bus_pos` / `make_ybus`
  **removed** (a topology-derived cmin is an optimization, not a correctness
  requirement — and the `make_ybus` copy would have ignored off-nominal taps, a
  latent bug vs. the canonical builders in `classical_sssa.m:133` /
  `ibr_scr_metrics.m:475`). Eligibility factored into `eligible_gfm_indices`.
- `build_fingerprint` now serializes the **full candidate universe** per
  context via `config_array_to_str`, so any change in any candidate invalidates
  the table. Selected indices + status are retained as audit metadata.
- Concatenation helper rewritten as `cat_candidates` (uniform-template padding);
  the empty-config branch uses a proper `blank_candidate()` template.

## Verification

- Phase 3 targeted runtests on `tests/test_ibr_selector_table_unit.m` on the
  edited tree: **Passed 22 / Failed 0 / Incomplete 0**; reports
  `PHASE 3 TARGETED: ALL GREEN`, env MATLAB R2026า.
- `test_fingerprint_changes_when_*` green (topology/dispatch/resource-order
  sensitivity preserved); `test_selector_table_builds_sg_off_and_sg_on` green;
  fingerprint never the `ffffffff` saturating-multiply collision.

## Limitations

- The bounded-default band `[cmin,cmax]` relies on rejecting topology-infeasible
  counts inside the evaluator; it does **not** pre-derive cmin from island
  topology (a deliberate NUMERICAL_METHOD choice to avoid re-implementing a tap/
  phase-aware Ybus builder). Exhaustive enumeration holds only while
  `Neligible <= N_exhaustive_max`.
- Reference ownership and the per-island commit are outside this record (handled
  in the runtime transaction phases).

## Revision 5 — Corrective closure (2026-07-17)

The earlier "936 passed / 8 failed / full regression passed / zero new
regressions" claim was WRONG. `git stash` does NOT revert committed source, so
the 8 `test_ieee14_ibr_ts_event_runner` failures at `7c986f4` were incomplete
schema migration, not pre-existing: the source now requires an authenticated
selector table on the automatic path, but the `event_run` helper still did not
inject one. This revision closes that gap and the remaining Phase 4b/5
contracts.

### Closed in Revision 5

1. **Event-runner migration.** `tests/test_ieee14_ibr_ts_event_runner.m` now
   builds two pinned authenticated tables in `setupOnce` (`table_4gfm`,
   `table_1gfm`) and migrates the 8 physical-intent tests to
   `event_run_with_table`. Two new missing-table tests assert the canonical
   `stability:gfm_selection:missingTable` failure ID with full no-publication
   semantics. 14/14 GREEN.
2. **Missing-table failure ID.** `ts_simulate_ibr_hybrid.m:575` now emits
   `stability:gfm_selection:missingTable` (shared namespace, no prepend).
3. **Validator latent bugs fixed.** `validate_runtime_candidate_compatibility.m`
   had two latent bugs exposed by the migration: (a) `fidi` nested-function
   handle was unreachable from `manual_branch` (undefined function error); (b)
   early-return paths did not assign `runtime_out`/`cand_out` outputs (MATLAB
   "Output argument not assigned" error). Both fixed. All failure IDs now use
   string concatenation `['stability:gfm_selection:' suffix]` consistently.
4. **Production `cand` field bug fixed.** `ts_simulate_ibr_hybrid.m:610` read
   `cand.selected_gfm_indices` but the validator output did not always carry
   it; now reads from the validator output with a schedule-literal fallback.
5. **Real timers.** `assemble_runtime_context` now reads `hold_timers`/`lockouts`
   from `hybrid_state` (Step 3) instead of hardcoding `0`/`-inf`. Malformed
   values fail closed with `runtimeContextMalformed`.
6. **Validator parity.** Identity check now verifies ALL candidates (not only
   `cfgs(1)`) + sanitized-key uniqueness (`identityCollision`). Manual branch
   gains identity + hold/lockout checks. `runtime_n_mode_changes` reflects the
   post-sort winner (`ranked(1)`), not `nchanges(1)`.
7. **Authenticated SG_ON routing (Step 5).** `reselection_transaction` now
   consumes an authenticated SG_ON candidate via `authenticate_sg_on_candidate`
   (routes through the validator); `compute_tdown` derives `T_down` from the
   authenticated candidate's omega, not the raw `table.sg_on` aggregate.
8. **`N_exhaustive_max=4` guard (Step 6).** `ibr_selector_table.m` now fails
   closed with `stability:gfm_selection:excessiveUniverse` before enumeration
   if the eligible universe exceeds 4 (safety bound; IEEE14 has ≤ 4).
9. **Unpinned automatic integration (Step 8).** New
   `test_unpinned_automatic_sg_off_integration` builds a real IEEE14 table with
   NO pin and asserts the runtime-selected candidate + provenance come from the
   table, and SG_ON reports zero feasible (physically infeasible under frozen
   gates).

### Verification (Revision 5)

- Targeted gates on the edited tree: selector unit 44/44, event runner 14/14,
  reclose workflow 16/16, SG_ON integration 12/12 — **86/86 GREEN, 0 failed,
  0 incomplete**.
- Full regression pending (run once on the final tree per AGENTS.md risk
  policy).

### Limitations (Revision 5)

- Automatic selection (unpinned) picks candidate `[5]` (highest margin) on
  IEEE14, which can make post-trip dynamics fail to converge (stepNewton). This
  is an honest outcome of the frozen margin-based ranking policy, not a bug;
  the demo/comparison/solve_case defaults retain the known-stable manual
  `[2 3 4 5]` tuple. A ranking-policy review (margin vs dynamics stability) is
  a separate workstream.
- `IBR_PRODUCTION_INTEGRATION_READY = NOT_READY` (unchanged).

