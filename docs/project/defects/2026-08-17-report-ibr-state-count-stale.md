# DOC-2026-08-17-01 — the switching reports described a 20-state IBR that the run does not integrate

Status: **RESOLVED** (2026-08-22). Corrected in the English `rev2` report on
2026-08-17 and in the Thai `rev2` report on 2026-08-22, which also rebuilt its
PDF (32 pages, `xelatex`, two passes, no undefined references). The equation
renumbering that held the Thai fix back is now applied and mapped below.
History of the partial state is kept in this record rather than erased.

Branch: `main`. Tested tree: uncommitted work on top of `416e47a`.
Environment: MATLAB R2026a, Windows 11.

## Symptom

Section "Inverter-based resource" of both switching reports stated that each IBR
carries a **fixed 20-vector** state
(`x_pl(3) | x_GFL(4..11) | x_GFM(12..20)`), that the active-index map returns
`A_GFL = {1:11}` and `A_GFM = {1:3, 12:20}`, and that a GFL→GFM change steps the
active dimension `11 → 12`. Both per-branch state lists ended with the two
command-delay states `V_d,del`, `V_q,del`, and both branch equation blocks
integrated them as rows (10)–(11) and (19)–(20).

The model the reported run actually integrates has **16** stored states with
**9** active in GFL and **10** in GFM, and integrates no command-delay state at
all.

## Reproduction

Row count of the delivered trajectory, which is decisive on its own:

```matlab
S = load(fullfile('output','diagnostics','ieee14_gfm_lock_compare','adaptive_250s.mat'));
size(S.result.x_traj,1)   % -> 70
```

`70 = 6 (SG stored states) + 4 x 16 (IBR stored states)`. A 20-state IBR would
give `6 + 4*20 = 86`, and the 17-state `decoupled_dual` variant would give `74`.
Neither is 70.

## Root cause, with evidence

The report text predates defect `TD-2026-08-12-01`, which removed the
command-delay states by singular perturbation and was never reflected in the
report body.

* The chronology driver and the comparison runner both request
  `case_profile='eecon49_figure4'`
  (`scripts/examples/run_ieee14_eecon49_chronology.m:52,55`;
  `scripts/reporting/run_ieee14_gfm_lock_comparison.m:217-218,233,267`).
* That profile dispatches `ibr_model_id='eecon49_dual'`
  (`+cases/scenario_ieee14_1sg_4ibr.m:98-103`), i.e.
  `+ibr/eecon49_dual_mode_model.m`.
* That model declares `dev.nx=16` (`:117`) over the layout
  `plant 1:3 | GFL 4:9 | GFM 10:16` (`:10-16`), with
  `gfl_active=1:9` and `gfm_active=[1:3 10:16]` (`:78-79`).
* Its own header states why (`:18-26`): the source command-delay lag carries
  `T_d = 1.5/f_sw ~= 0.3 ms` at `f_sw = 5 kHz`, more than 300x below the phasor
  step, so `v_del = v_cmd` on the slow manifold and the two delay states per
  branch are removed algebraically. The retained AC current rows use the
  commanded voltage `vcd/vcq` directly
  (`+ibr/gfl_eecon49_full_model.m:89-91`,
  `+ibr/gfm_eecon49_full_model.m:117-120`).
* The `INDEX.md` row for `TD-2026-08-12-01` records the same arithmetic:
  "dual 20->16 and standalone 12->10".

## What was and was not wrong

Wrong: the state count, the block sizes, the index ranges, the two active-set
expressions, the active dimension step, and the presence of two lag rows in each
branch equation block.

Not wrong: every equation of every **retained** state. The reduction leaves both
the equilibrium and the retained-state dynamics unchanged, so no reported number,
figure or gate is affected. This is a documentation defect, not a numerical one.

## Fix

`docs/source/report_ieee14_switch_en_rev2.tex` now states the 16-state layout,
`A_GFL = {1:9}`, `A_GFM = {1:3, 10:16}`, the `9 -> 10` dimension step, six GFL
and seven GFM controller rows, and carries a new subsection
(`sec:ibr-reduction`) that derives the reduction and cites `TD-2026-08-12-01`. A
Limitations bullet discloses the correction against the earlier revisions. The
arithmetic check `6 + 4*16 = 70` is printed in the body so a reader can falsify
the claim against the stored trajectory.

## Fix, Thai report (2026-08-22)

`docs/source/report_ieee14_switch_th_rev2.tex` now states the same 16-state
layout as the English report. Corrected in place: section title, the
`\in\mathbb{R}^{16}` state vector with blocks `(3) | (6) 4..9 | (7) 10..16`, the
two controller lists with the delay states dropped, `A_GFL={1:9}` and
`A_GFM={1:3,10:16}` with the `9`/`10` active totals, the state table reduced to
16 rows with GFM renumbered `10..16`, the GFL block reduced to rows `(4)-(9)`,
the GFM block to `(10)-(16)`, both per-state proofs renumbered with the delay
sentences removed, the composite active-set itemize, and the `n_x` counting
identity (`9`/`10` per IBR, `5+4*9=41` and `5+4*10=45`). A new subsection
`sec:ibr-reduction` derives the reduction and cites `TD-2026-08-12-01`, and
states plainly that earlier revisions printed the pre-reduction layout.

**Independent oracle for the active dimensions.** Rather than assert `9`/`10`
from the source, the numbers were read back out of the delivered artefact.
`generate_switch_new_report_figures` re-run against
`output/diagnostics/ieee14_gfm_lock_compare_dcreal/adaptive_250s.mat`
(`t_max=250`) reports `nx_before_trip = 41` and per-device
`[5 9 9 9 9] -> [5 10 9 9 9]` across the first promotion, i.e. `41 = 5 + 4*9`
and a `9 -> 10` step on the promoted converter. That is the same quantity the
integrator solved, published by the same `ts_dynamic_state_indices` authority.

## Equation renumbering, applied and mapped

Deleting the four command-delay rows removes four numbered `align` rows, so the
Thai report goes from 52 to 48 numbered equations. This was the blocker: the
owner cites equations by printed number. The complete map, produced by
enumerating numbered equations in both trees rather than by hand:

| before | after | what |
|---|---|---|
| (1)-(32) | unchanged | through the GFL inner-current rows |
| (33),(34) | **deleted** | GFL command-delay rows |
| (35)-(41) | (33)-(39) | the seven GFM branch rows, shift -2 |
| (42),(43) | **deleted** | GFM command-delay rows |
| (44)-(52) | (40)-(48) | shift -4 |

By label: `eq:transfer` 44->40, `eq:contgate` 45->41, `eq:stackf` 46->42,
`eq:dae` 47->43, `eq:trap` 48->44, `eq:resid` 49->45, `eq:frozen` 50->46,
`eq:assign` 51->47, `eq:nxcount` 52->48. Every label from `eq:kcl` through
`eq:ibractive` keeps its number, and **no equation was added**: each new
derivation in the revision is written as inline math specifically so nothing
below it moves a second time. The same map is recorded in the report's own
header comment so it travels with the file.

Verification: the rebuilt PDF's highest printed equation number is `48`; the GFL
block ends at `(9)` and the GFM block runs `(10)`-`(16)`; the state table prints
16 rows with active totals `9` and `10`.

## Falsified en route

* "The report describes the 17-state `decoupled_dual` variant." No: that layout
  is `plant 1:3 | GFL 4:9 | GFM 10:17` with 9/11 active
  (`+ibr/decoupled_dual_mode_model.m:12-18,83-84,116`), it is selected only by
  `case_profile='decoupled_figure4'`, and it would give 74 composite rows.
* "The 20-state text describes the superset while the run integrates a
  projection of it." No: the report's own sentence quantifies the *stored*
  vector as `\in R^{20}` and the stored vector is 16.

## Related

* `TD-2026-08-12-01` — the reduction itself
  ([record](2026-08-12-eecon49-command-delay-reduction.md)).
* `AGSI-2026-08-16-01` — the overlay re-run whose artifact supplied the row
  count used as the independent check
  ([record](2026-08-16-agsi-overlay-absent-from-delivered-chronology.md)).
