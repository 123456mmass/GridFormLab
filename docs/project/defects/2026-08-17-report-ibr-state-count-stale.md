# DOC-2026-08-17-01 — the switching reports described a 20-state IBR that the run does not integrate

Status: **PARTIALLY RESOLVED** (2026-08-17) — corrected in the English `rev2`
report; the Thai `rev2` report still carries the stale description.

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

## Residual work

`docs/source/report_ieee14_switch_th_rev2.tex` still carries the stale text at
`:623` (section title), `:626`, `:630-632`, `:637-641`, `:646-647`, `:651`,
`:655`, `:660-698` (a 20-row state table, incl. rows 10, 11, 19, 20 and the
`11`/`12` active totals at `:695`), `:898-902` and `:1025`. Correcting it also
**shifts every equation number after the IBR section**, which matters because
the project owner refers to equations by number; the change is therefore held
pending an explicit decision rather than applied silently.

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
