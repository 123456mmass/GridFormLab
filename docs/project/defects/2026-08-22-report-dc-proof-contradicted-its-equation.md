# DOC-2026-08-22-02 — the reports' DC-link prose contradicted their own DC-link equation

Status: **RESOLVED** (2026-08-22).

Branch: `main`. Tested tree: uncommitted work on top of `76f6ea4`.
Environment: MATLAB R2026a Update 3 (glnxa64), TeX Live with `xelatex`.

## Symptom (observation, not inference)

`NUM-2026-08-20-01` replaced the ideal DC-link closure and updated the displayed
DC-link row of both reports. It did **not** update the prose that proves that
row. The English `rev2` report therefore contradicted itself inside a single
subsection:

* the align row printed
  `dot V_dc = (1/C)[(E_dc-V_dc)/R_dc - P_ac/V_dc - max(0,V_dc-V_dc^max)/R_ch]`;
* the "Proof of each row" paragraph immediately below it stated that "the coded
  current is `I_dc = P_ac/V_dc + (C/T_dc)(V_dc^0-V_dc)`", that the feed-forward
  "cancels exactly", that "this cancellation is deliberate", and that "at steady
  state row (3) gives `V_dc = V_dc^0`".

Those are the three claims `NUM-2026-08-20-01` was opened to remove. A reader
following the proof would conclude the DC state cannot move, while the equation
above it and the trajectory both say it does.

Five further inconsistencies were found in the same sweep:

1. **English glossary** listed `T_dc` — "DC restoration time" — as a live model
   parameter, though no retained equation contains it.
2. **English figure-source contract** and the file's own header comment declared
   the figures were rendered from
   `output/diagnostics/ieee14_gfm_lock_compare/adaptive_250s.mat`, the **ideal**
   cache, after every figure had been regenerated from `..._dcreal`. The
   generated macro file `run_summary_v2.tex` already declared `_dcreal`, so the
   report asserted two different provenances for the same page.
3. **English** promised "the figure of `n_x(t)` below"; the report contains no
   such figure (11 `fig:` labels, none of them a state-dimension figure).
4. **Thai** small-signal prose attributed "the four real roots near
   `-10 s^-1`" to the DC-bus family. That value is `-1/T_dc` of the retired
   closure; the generated table it introduces prints `-96.812311`,
   `-92.911157`, `-92.693034`, `-91.111042`.
5. **Thai** `\input` a compact modal table `sssa_modes_compact_n1.tex` that has
   never existed, and included `comparison_arms.png` (2026-08-16, ideal DC),
   which the English report had already superseded with
   `comparison_full.png` + `comparison_windows.png` — its own caption calls the
   single-page version the thing it replaced. Both are inside `\IfFileExists`
   guards, so the missing table was **silently omitted** rather than raising a
   build error, and the stale figure has no generator that would refresh it.

## Reproduction

```bash
cd docs/source
grep -n "cancels exactly\|cancellation is deliberate\|T_{dc}" report_ieee14_switch_en_rev2.tex
grep -n -- "-10~" report_ieee14_switch_th_rev2.tex
grep -n "sssa_modes_compact_n1\|comparison_arms" report_ieee14_switch_th_rev2.tex
ls -la figures/switch_ieee14/sssa_modes_compact_n1.tex   # ENOENT
ls -la figures/switch_ieee14_decision/comparison_arms.png # 08-16, no generator
```

## Root cause, with evidence

The 08-20 revision edited the *displayed equations* and added a new derivation
section (`sec:dcsource`), but the proof paragraphs, the symbol glossary, the
figure-provenance paragraph and the header comment are separate prose blocks
that no generator owns. Nothing in the build fails when they disagree with the
equation they describe: LaTeX has no cross-check between an align row and the
sentence under it, and `\IfFileExists` converts a missing generated input into
a silent omission. The two past-tense "what this replaced" paragraphs the 08-20
revision *did* add (English `:937`, `:1505`) show the intent was present; the
proof paragraph was simply missed.

## Fix

English (`docs/source/report_ieee14_switch_en_rev2.tex`):

* the row-(3) proof now derives the coded closure: the source publishes only
  `C dot V_dc = I_dc - P_ac/V_dc`, the coded current is the Thevenin law
  `\eqref{eq:dcsrc}` less the chopper draw `\eqref{eq:dcchop}`, **nothing
  cancels** (`P_ac` drives the coordinate, `C_dc` scales it, so both enter the
  residual and the Jacobian), and setting `dot V_dc=0` with the chopper off
  gives `V_dc^2 - E_dc V_dc + R_dc P_ac = 0`, whose upper root is `V_dc^0` at
  the dispatched loading — which is what fixes `E_dc` in `\eqref{eq:dcedc}` —
  and moves with `P_ac` elsewhere. The quadratic is the one `sec:dcsource`
  already states, not a new derivation;
* the glossary drops `T_dc` and adds `E_dc, R_dc`, `R_ch, V_dc^max`,
  `varepsilon, P_r`; the single surviving `T_dc` in the past-tense paragraph is
  glossed as "a declared restoration time constant no longer used on this path";
* the figure-source paragraph and header comment now name
  `ieee14_gfm_lock_compare_dcreal/adaptive_250s.mat`, matching
  `run_summary_v2.tex`;
* the dangling figure promise became "the reported dimension `n_x(t)`".

Thai (`docs/source/report_ieee14_switch_th_rev2.tex`): row (3) replaced with the
Thevenin-plus-chopper form, its proof rewritten (no cancellation; `E_dc` forced
by the equilibrium requirement; the quadratic; the `V_dc <= max(V_dc(0),E_dc)`
bound and why the chopper stays off), the filter rows switched from the delayed
command to `v_cd, v_cq`, new symbols added to the glossary, the `-10 s^-1`
sentence corrected to the measured family just above `-100 s^-1` with the
predict-then-measure argument, the abstract/scope provenance moved to the
`_dcreal` 250 s arm, the never-generated compact table replaced by the generated
`sssa_modes_n1.tex` itself, and `comparison_arms.png` replaced by
`comparison_full.png` + `comparison_windows.png` with translated captions and
the one cross-reference to its right panel repointed to the windows figure's
left column. The 16-state correction delivered in the same pass is recorded
under `DOC-2026-08-17-01`, including the equation-renumbering map.

`write_sssa_modes_compact` was **not** used and **not** repaired: it projects a
five-column source and the current generated table has four columns (no `zeta`),
so it errors `noRows`. Pointing the Thai report at the generated table the
English report already uses is the smaller change and makes bit-identity
trivially true instead of asserted.

## Verification

* English: 38 `equation` + 5 `align` environments and all 40 `eq:` labels in the
  same order as before the edits, so **no equation was renumbered**; braces
  balanced, `$` count even.
* Thai: rebuilt with `xelatex` twice, exit 0, **no undefined references**, 32
  pages. `pdftotext` of the result confirms `E_dc - V_dc` in the DC row,
  `-96.812311 / -92.911157 / -91.111042` in the modal table, `5+4x9=41` and
  `5+4x10=45`, the state table's `9`/`10` totals, GFM rows printed `(10)`-`(16)`,
  and a highest printed equation number of `48`.
* The regenerated `state_switch_dimension.png` came from the `_dcreal` 250 s arm;
  `nx_before_trip = 41` with per-device `[5 9 9 9 9] -> [5 10 9 9 9]`, which is
  the independent oracle for the `9`/`10` active dimensions.

## Falsified en route

* "The English `rev2` report is correct about the model, only the Thai one is
  stale." This was the primary agent's own stated position earlier in the
  session; the row-(3) proof paragraph refutes it. Recorded because it shows a
  self-contradiction inside one subsection survived a review that had just
  edited the equation four lines above it.
* "The Thai report's `200 s` provenance sentences were merely out of date." They
  were a deliberate declaration (equations from the 250 s code, plots from the
  preserved 200 s run). What made them wrong is that 11 of 15 figure inputs had
  since been regenerated from the 250 s `_dcreal` arm, so the declaration had
  become false in the opposite direction from the obvious reading.
* "The 08-10 power-flow tables are stale too." They are not: the closure leaves
  the AC equilibrium untouched (`dVdc(0) = -1.06e-14`), and the English report
  inputs the same two tables.

## Limitations

The English PDF is still the 2026-08-20 build. `newtxtext.sty` is absent on this
Linux host, the font contract in `AGENTS.md` forbids substituting a package to
force a compile, and a failed `pdflatex` pass **deletes** the existing PDF. The
source-level corrections above are therefore not yet visible in the delivered
English PDF; the Thai PDF is current. Rebuild the English report on the Windows
host that produced the 08-20 build, or install `newtx` first, and copy the PDF
aside before invoking `pdflatex`.

`mode_switch_PQ.png` and `mode_switch_electrical.png` in
`docs/source/figures/switch_ieee14_new/` were deliberately restored to their
2026-08-11 bytes after the regeneration run overwrote them: they belong to the
superseded non-`rev2` reports, and refreshing them from a different cache and
horizon would have silently changed those reports instead. Only
`state_switch_dimension.png`, the one file a `rev2` report includes, was kept.

## Related

* `NUM-2026-08-20-01` — the closure whose prose was left behind
  ([record](2026-08-20-ideal-dc-link-carried-no-dynamics.md)).
* `DOC-2026-08-17-01` — the 16-state correction delivered in the same pass, and
  the equation-renumbering map
  ([record](2026-08-17-report-ibr-state-count-stale.md)).
* `DOC-2026-08-22-01` — the generator that stamped an unearned bit-identity
  sentence, found in the same sweep
  ([record](2026-08-22-hardcoded-bit-identity-provenance.md)).
* `TD-2026-08-12-01` — the command-delay reduction
  ([record](2026-08-12-eecon49-command-delay-reduction.md)).
