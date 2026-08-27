# DOC-2026-08-26-03 — `rev2` English report carries three claims its own generated inputs contradict

- **Status:** RESOLVED
- **Area:** `docs/source/report_ieee14_switch_en_rev2.tex` (prose only; no executed code)
- **Branch / commit:** `main` at `3b9c67d`
- **Environment:** Windows 11, TeX Live 2026; found while inventorying the report
  for a conference deck, by reading each number back to the file that generates it

## Symptom

Three statements in the committed report cannot be reconciled with the generated
files the same report `\input`s.

### 1. A bit-identity gate is claimed for a cache whose generator denies it

`:336-342` states:

```
The re-run was gated on being \textbf{bit-identical} to the delivered artefact
before any figure was drawn: $\max|\Delta x|=\max|\Delta y|=\max|\Delta u|=0$
exactly, ... and the same reclose outcome at $t=\NewRunReclose\second$.
```

`\NewRunReclose` is defined in `figures/switch_ieee14_decision/run_summary_v2.tex:22`,
and that file's own provenance header (`:3-9`) reads:

```
% PROVENANCE. Accepted values of
%   output/diagnostics/ieee14_gfm_lock_compare_zeta/adaptive_250s.mat.
% This cache is NOT bit-identical to the earlier delivered artifact, and no
% such claim is made for it: the DC-link closure changed under
% NUM-2026-08-20-01, so the trajectory legitimately differs. Compare it to
% the earlier cache by outcome, never by bit-identity.
```

So the sentence asserts, of the very number it prints, the opposite of what the
generator of that number asserts. The bit-identity gate was real — for the
**ideal-DC** cache under `AGSI-2026-08-16-01`, which is what the paragraph was
written about. It did not survive the model change.

The bit-identity that *is* currently measured is a different one and is
uncontested: the six arms agree exactly on the common window `[0,20)` s over 42
samples (`figures/switch_ieee14_decision/comparison_summary.tex:49-53`).

### 2. Three different cache paths are named for one result set

| Location | Path named |
|---|---|
| `:73` | `output/diagnostics/ieee14_gfm_lock_compare/adaptive_250s.mat` (ideal DC) |
| `:24`, `:320` | `output/diagnostics/ieee14_gfm_lock_compare_dcreal/adaptive_250s.mat` (resistive Thevenin, 16 states) |
| `run_summary_v2.tex:3` | `output/diagnostics/ieee14_gfm_lock_compare_zeta/adaptive_250s.mat` (inductive Thevenin, 17 states) |

The macros the report prints come from the third. The first two are the two
superseded DC closures, whose own reclose instants differ from the printed one
(`159.3436` ideal / `159.2397` resistive / `159.2519` present; handoff
`docs/project/AGENT_HANDOFF.md:249`).

### 3. The state count and the active-set counts each appear in two values

| Quantity | Stale value | Current value |
|---|---|---|
| IBR superset | "sixteen-state" (`:143`, `:217`) | "17-state" (`:352`), 17 (`:734`) |
| GFL active | `9`, `A_GFL={1:9}` (`:1173-1174`) | `10`, `A_GFL={1:9,17}` (`:791-798`) |
| GFM active | `10`, `A_GFM={1:3,10:16}` (`:1175-1176`) | `11`, `A_GFM={1:3,10:16,17}` (`:791-798`) |

The current values are the ones the code integrates
(`+ibr/eecon49_dual_mode_model.m:95-96` appends index 17 to both sets when
`n_src==1`).

## Reproduction

```bash
sed -n '336,343p;143p;217p;352p;1172,1177p' docs/source/report_ieee14_switch_en_rev2.tex
sed -n '1,12p;22p'  docs/source/figures/switch_ieee14_decision/run_summary_v2.tex
grep -n 'gfl_active\|gfm_active' +ibr/eecon49_dual_mode_model.m
```

## Root cause (inferred)

All three are the same failure mode already recorded for the Thai report in
`DOC-2026-08-26-01`: a model revision was applied to the sections that own the
model and to the generated inputs, but not to every sentence elsewhere that had
quoted the previous revision. The DC link went through three closures (ideal →
resistive Thevenin → inductive Thevenin with a source-current state); each pass
updated the section it was about. LaTeX cross-checks nothing between a sentence
and the `\input`-ed file whose macro it cites, so a stale claim about a macro's
provenance survives every rebuild silently.

## Impact

No numerical impact: all three are prose. Every printed value is the correct
current value, because the values come from the macros. The impact is on a
reader, and item 1 is the serious one: it advertises a verification gate that
was not run on the presented trajectory. Items 2 and 3 mislead about which cache
and which model produced the numbers.

## Initial disposition

The defect was first recorded without editing the report because the original
presentation-only allowlist did not include that document and replacing the
unsupported gate claim required owner authority.  The owner subsequently
expanded the scope to include proven stale report statements, so the resolution
below supersedes this initial disposition.

## Suggested resolution

1. Replace `:336-342` with the measured common-window statement, or delete it and
   cite `NUM-2026-08-20-01` for why bit-identity is not available across the
   model change.
2. Make `:24`, `:73`, `:320` name `..._zeta`, and record the two superseded caches
   once, as history, in the DC-link section that explains the three revisions
   (`:1632-1645` already tells that story).
3. Update `:143`, `:217` to seventeen and `:1173-1176` to `10` / `11` with the
   `,17` in both index sets.

## Resolution (2026-08-27)

The owner expanded the approved presentation pass to include corrections of
proven stale statements in the English report.  The report now:

1. identifies the presented result as the inductive-Thevenin, 17-coordinate
   result set and removes the unsupported cross-model bit-identity claim;
2. states only the measured identity of the six present policy arms on their
   common pre-disturbance window `[0,20)` s (42 accepted samples);
3. uses the current result provenance consistently; and
4. states the current 17-coordinate superset with 10 active GFL states and 11
   active GFM states, including coordinate 17 in both active sets.

Verification on Windows 11 with TeX Live 2026: two consecutive
`xelatex -interaction=nonstopmode -halt-on-error report_ieee14_switch_en_rev2.tex`
runs exited zero and produced 38 pages.  Pages 1, 3, 5, and 21 were rendered
and visually inspected; the corrected abstract/contributions, provenance
paragraph, and active-set definitions are legible with no clipping or overlap.
No numerical model, parameter, equation, acceptance criterion, or runtime path
was changed.

## Related

- `docs/project/defects/2026-08-26-thai-report-dc-state-without-equation.md`
  (`DOC-2026-08-26-01`) — same failure mode, Thai report, RESOLVED.
- `docs/project/defects/2026-08-26-production-dc-comment-stale-bound.md`
  (`DOC-2026-08-26-02`) — the production derivation comment, still OPEN.
- `docs/project/AGENT_HANDOFF.md:185-285` — the three DC closures and their caches.
