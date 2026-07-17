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
