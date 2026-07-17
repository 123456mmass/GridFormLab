# Defect: cell-array collapse in struct() constructor + cell-indexing bugs

Date: 2026-07-18
Status: RESOLVED
Area: IBR Section H reporting + stability modal analysis (Phase 2/3)
Affected files: `+ibr/section_h_report.m`, `+stability/modal_analysis.m`

## Symptom

Two distinct but related cell-array defects surfaced during Phase 3 Section H
report test bring-up:

1. **`execution_counters.rows` and `convergence_summary.rows` collapsed to a
   1x1 struct** instead of the expected 14-entry (resp. N-entry) cell array.
   Tests that indexed by name (`find(strcmp(names,'equilibrium_invocations'))`)
   returned empty, and `assertEqual(inv_row.status, ...)` errored with
   `MATLAB:minrhs` ("Not enough input arguments") because `inv_row` was empty.

2. **Participation status/reason read with parentheses on cell arrays** in
   `modal_analysis.m` silently returned a 1x1 cell (the whole array) rather
   than the i-th element, so `strcmp(cond_status(i), 'AVAILABLE_SIMPLE')`
   compared the entire cell array (which `strcmp` treats as a single string
   concatenation) and could mis-classify conditioning/pairing status.

## Reproduction

### Defect 1 (struct() collapse)

```matlab
rows = cell(3,1);
rows{1} = struct('name','a','value',1);
rows{2} = struct('name','b','value',2);
rows{3} = struct('name','c','value',3);
tbl = struct('status','AVAILABLE','rows',rows,'summary',struct('n',3));
% tbl.rows is a 1x1 struct with fields name,value holding ONLY the first
% element ('a',1) — the other two are lost.
```

The `struct()` constructor expands a cell-array value into a struct array
*field-by-field* when every cell element is a struct with identical fields.
When the cell is stored as the value of a single struct field via
`struct('rows',rows,...)`, MATLAB creates a struct array whose `rows` field
takes only the first cell element, collapsing the rest.

### Defect 2 (parentheses on cell array)

```matlab
status = repmat({"AVAILABLE_SIMPLE"}, 1, 3);
status(2)            % returns a 1x1 cell {"AVAILABLE_SIMPLE"}, NOT the string
strcmp(status(2), 'AVAILABLE_SIMPLE')   % compares cell to char — unreliable
strcmp(status{2}, 'AVAILABLE_SIMPLE')   % correct: compares the string content
```

## Affected tree/environment

- Branch: `main`
- Commits: Phase 2 `aba4ba2` (modal_analysis.m), Phase 3 working tree
  (section_h_report.m, not yet committed at the time of discovery)
- MATLAB: R2026a Update 3 (glnxa64)
- Discovered by: Phase 3 test `test_counters_distinguish_invocation_iteration`
  failing with `MATLAB:minrhs`.

## Root cause (evidence-backed)

### Defect 1

`+ibr/section_h_report.m` `execution_counters_table` and `convergence_summary`
built a cell array of identical-field structs and stored it via
`struct('status',...,'rows',rows,...)`. The `struct()` constructor treats a
cell-array value as a comma-separated list of struct-array elements; when
assigned to a single field, only the first element survives. The earlier
`{}` cell-literal form with `...` line continuations also produced a scalar
struct (parse behavior of `...` inside a cell literal with struct elements).

Falsified hypotheses:
- "Test fixture is wrong" — disproved: direct construction in a script
  reproduced the collapse with no fixture involvement.
- "Cell literal vs explicit cell(14,1) matters" — disproved: both forms
  collapse when stored via `struct('rows',rows,...)`. The collapse happens
  at the `struct()` constructor, not at cell construction.

### Defect 2

`+stability/modal_analysis.m` used `status(i_chosen)`, `reason(i_chosen)`,
`cond_status(i)`, `pair_status(i)`, and `part_status(i)` where the arrays
are cell arrays (built with `repmat({...},1,n)`). Parentheses indexing on a
cell array returns a cell, not the content; `strcmp` on a cell behaves
unreliably (compares the cell as a container). Curly-brace indexing `{i}`
returns the string content, which is what `strcmp` requires.

Falsified hypotheses:
- "Only the two sites fixed in the prior commit (497, 512) were affected" —
  disproved: a static audit (`rg "status\(|reason\(|part_status\("`) found
  three more sites (334, 335, 656) with the same pattern.

## Correction

### Defect 1

Wrap the cell array in another cell when storing it in a struct field, so
the constructor treats it as a single value rather than a comma-separated
list:

```matlab
% Before (collapses):
tbl = struct('status','AVAILABLE','rows',rows,'summary',struct('n',3));
% After (preserves):
tbl = struct('status','AVAILABLE','rows',{rows},'summary',struct('n',3));
```

Applied to `execution_counters_table` (line 509) and `convergence_summary`
(line 540). Other tables that use dot-assignment (`tbl.rows = rows`) or
`{{}}` empty-cell defaults were already correct and unchanged.

### Defect 2

Replace parentheses with curly braces at five sites in `modal_analysis.m`:
lines 334, 335, 497, 512, 656.

## Verification

- Phase 3 targeted: `test_ibr_section_h_report.m` 20/20 PASS (was 17/18,
  then 18/18 after the struct() fix, then 20/20 after adding two shape-guard
  tests).
- Phase 2 targeted: `test_modal_analysis.m` 24/24 PASS (unchanged count;
  the cell-index fixes do not alter any passing behavior, they correct
  silent mis-reads on ill-conditioned/clustered paths).
- New shape-guard tests added:
  - `test_counters_rows_is_cell_with_14_entries`: asserts
    `iscell(rows)` and `numel(rows)==14` and all 14 expected names in order.
  - `test_convergence_summary_rows_is_cell`: asserts `iscell(rows)` and
    the single EQUILIBRIUM row.
- Full regression: 1019 passed / 0 failed / 4 incomplete (the 4 incomplete
  are pre-existing `test_pgaz_conversion_contract` assumption-filters on the
  external pgaz validation tool, unrelated to this change).

## Limitations

- The shape-guard tests cover `execution_counters` and `convergence_summary`
  only. Other tables (`spectrum_table`, `participation_table`, `ts_tables`)
  use dot-assignment or `{{}}` defaults and were verified by their existing
  cardinality tests, not by an additional shape guard.
- The cell-index audit was scoped to `modal_analysis.m` and
  `section_h_report.m`. A repository-wide audit of parentheses-on-cell
  patterns was not performed; such a bug could exist elsewhere but is out of
  scope for this Phase 3 delivery.

## Related files/commits

- `+ibr/section_h_report.m` (Phase 3, this commit)
- `+ibr/render_section_h_report.m` (Phase 3, this commit)
- `tests/test_ibr_section_h_report.m` (Phase 3, this commit)
- `+stability/modal_analysis.m` (Phase 2 `aba4ba2` + this commit's cell-index
  fixes at 334/335/656)
- `tests/test_modal_analysis.m` (Phase 2 + this commit's reason-set update)
