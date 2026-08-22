# DC link was an ideal source: `V_dc` carried no dynamics and `C_dc` cancelled

- **ID**: `NUM-2026-08-20-01`
- **Status**: RESOLVED. Closure replaced and verified; the five-arm 250 s
  re-run **completed 2026-08-22** and `summary.mat` carries all five rows with every
  expectation MET. An earlier revision of this line claimed the five arms had been
  re-run while only two had; that overstatement and its correction are kept below
  under "Correction to this record" rather than erased.
- **Component**: `+ibr/gfl_eecon49_full_model.m`, `+ibr/gfm_eecon49_full_model.m`,
  `+ibr/eecon49_dual_mode_model.m`, `+cases/scenario_ieee14_1sg_4ibr.m`,
  `+stability/ts_step_composite.m`
- **Classification of the change**: `PROJECT_DERIVED`, owner-authorised. The
  EECON49 source publishes the DC-link energy balance but not the law for
  `I_dc`, so the law is the project's to set — and therefore the project's to
  justify.

## Symptom (observation, not inference)

The owner asked whether the small-signal table was right to show a DC-link
participation of exactly `1.000`, four times over, and doubted that `V_dc` should
be constant. Measured on the delivered 250 s adaptive trajectory
(`output/diagnostics/ieee14_gfm_lock_compare/adaptive_250s.mat`, 4994 accepted
samples, state 3 of each 16-state IBR at offset 6):

```
IBR1  V_dc: min=1.000000000000  max=1.000000000000  range=0.000e+00
IBR2  V_dc: min=1.000000000000  max=1.000000000000  range=0.000e+00
IBR3  V_dc: min=1.000000000000  max=1.000000000000  range=0.000e+00
IBR4  V_dc: min=1.000000000000  max=1.000000000000  range=0.000e+00
```

`range` is exactly zero, not small. Four states out of seventy carried no
information for the whole run.

## Root cause with evidence

The retired closure was, at `gfl_eecon49_full_model.m:126-135` and
`gfm_eecon49_full_model.m:165-171` (identical local copies):

```matlab
Idc = Pac/vdc + (C/Tdc)*(Vdc0-vdc);
dv  = (Idc - Pac/vdc)/C;
```

Two exact cancellations follow algebraically, and both were verified in the
delivered artefacts rather than assumed:

1. `Pac/vdc` cancels identically, leaving `dVdc/dt = (Vdc0 - Vdc)/Tdc`. Since the
   initialiser sets `x(3) = Vdc_ref = Vdc0`, the initial condition **is** the
   equilibrium of that scalar equation, so `V_dc(t) = Vdc0` for all `t`. This is
   the measured zero range above.
2. `C` cancels. The case value `Cdc = 0.10`
   (`scenario_ieee14_1sg_4ibr.m:254,258`) therefore never entered any residual,
   any Jacobian or any eigenvalue. A declared parameter had no effect anywhere.

Consequences in the delivered small-signal table: the DC row was exactly
decoupled, so `-1/Tdc = -10` was its eigenvalue with algebraic multiplicity four;
the unit vector on that coordinate was exactly a **left** eigenvector, so the
participation factor was exactly `1.000` as a matter of algebra, not of rounding.
The owner's suspicion was correct: those four rows were the visible receipt of an
ideal DC source.

## Fix

`I_dc` is now the current of a source behind its own internal resistance, with an
overvoltage chopper, in one shared helper so the two controller branches cannot
drift apart:

- `+ibr/dc_source_thevenin_params.m` — derives `E_dc` (forced by requiring the
  dispatched point to be an equilibrium), `R_dc` (from a declared regulation
  `eps_dc`, bounded above by the requirement that the link support the largest
  current-limited power), `R_ch`, the boundedness proposition and the reported
  stiffness. The derivation is in the file, not only the numbers.
- `+ibr/dc_source_thevenin_rhs.m` — evaluates
  `C dVdc/dt = (Edc-Vdc)/Rdc - Pac/Vdc - max(0,Vdc-Vdc_max)/Rch`.
- Both `*_eecon49_full_model.m` files call the shared helper; their duplicated
  local `dc_link_rhs` functions are deleted.
- `dc_source` in the scenario gains `eps_dc=0.10`, `Pr=1.0`, `Vdc_max=1.10`,
  `delta_ch=0.02`, `Pmax=1.06*1.2`. `Tdc` is retained **only** for
  `ibr.gfm_decoupled_full_model`, which is off the EECON49 path and deliberately
  keeps its earlier closure; that asymmetry is intentional and recorded here.

State count, state order, layout, active-index sets, the transfer contract and
the schema are all unchanged: still 16 states per IBR, still `6+4*16=70` rows.

### One kernel change was required, and why it is not a relaxation

`P_ac/V_dc` is singular at `V_dc = 0`. That singularity is the physics of a
constant-power load on a DC bus, so it cannot be removed. A Newton line-search
trial can propose `V_dc <= 0` even when the accepted iterate is physical; with the
old ideal closure that never happened because `V_dc` never moved, so the existing
guard never fired. On the first re-run it fired and aborted the whole simulation.

`+stability/ts_step_composite.m:307` already had a `trial_domain_classifier`
whose sole registered identifier was the RMS10 low-voltage inversion. The DC-bus
boundary is the same class of object, so `ibr:dc_source_thevenin:dcVoltage` is
now registered alongside it. This does not weaken any gate: a violation at an
**accepted** state is thrown outside that try/catch and still aborts, and
`composite_newton.m:132-136` never assigns the accepted iterate, its residual or
its Jacobian from a rejected trial. Widening the guard so `1/V_dc` were evaluated
anyway would have been a silent fallback and was rejected.

## Falsified hypotheses

- *"The DC link will over-volt during the 85 s fault and needs the chopper to
  survive."* **False**, and the primary agent said so before checking, then
  corrected it. For `V_dc > E_dc` every term of the link equation is negative
  whenever `P_ac >= 0`, so `dVdc/dt < 0` and `V_dc(t) <= max(V_dc(0),E_dc) = E_dc`
  for all `t`. A Thevenin source is bounded by its own EMF; the earlier worry
  applies to a constant-current or constant-power source, not this one. The
  chopper is retained because a real converter has one and a different dispatch
  would engage it, and it is provably inactive here (`E_dc = 1.0453 <=
  Vdc_max = 1.10`). It is reported as inactive, never as protection that acted.
- *"`eps_dc` should be enlarged so the DC mode is resolvable at dt = 0.05 s."*
  **Rejected on principle.** That would choose a physical parameter from
  numerical convenience. `eps_dc = 0.10` comes from the reachability bound
  (`eps <~ 0.115` at margin 2) and the usual ten per cent regulation of a DC link
  fed through a boost stage. The resulting stiffness is reported instead.

## Verification

Analytic prediction made **before** the spectrum was recomputed:
`lambda_dc = -(1/C)(1/Rdc - Pac/Vdc^2) = -100 + 10*Pac/Vdc^2` per unit second.

Measured, `docs/source/figures/switch_ieee14/sssa_modes_n1.tex` after
regeneration:

```
10 & $-96.812311$ & $0$ & IBR2:$V_{dc}$
11 & $-92.911157$ & $0$ & IBR8:$V_{dc}$
12 & $-92.693034$ & $0$ & IBR3:$V_{dc}$
13 & $-91.111042$ & $0$ & IBR6:$V_{dc}$
```

Four **distinct** real modes with the link voltage dominant, ordered by the power
each converter carries, and inverting the prediction on them returns per-converter
powers of 0.319, 0.709, 0.731 and 0.889 pu — the loading the time-domain figures
show for the same devices. Nothing was fitted; the closure was derived first.

Equilibrium `V_dc` is now solved rather than pinned. Over the seven admissible
SG-off configurations it ranges 0.989226 to 1.002153 pu with per-configuration
spread 3.7e-4 to 1.08e-2, and in every configuration the grid-forming device sits
nearest 1.000 because it holds the power closest to its dispatch. Before the fix
every entry was exactly 1.000000 with spread 0.

Other gates:

- `dVdc(0)` at the dispatched point: `-1.06e-14` in both branches, so the sourced
  AC initial condition and the power flow are untouched.
- GFL and GFM return bit-identical `dVdc/dt` at every probed `V_dc`, so a runtime
  transfer steps neither `V_dc` nor its derivative.
- Admissible SG-off configuration count unchanged at 7 of 15.
- `tests/test_ibr_dc_source_thevenin.m` (new): equilibrium exactness, branch
  agreement, boundedness, eigenvalue against a central finite difference (an
  oracle that never touches the analytic formula), chopper inertness and
  conduction, the registered domain identifier, the two reported margins,
  fail-closed parameter validation, and a test that **halving `C_dc` doubles
  `dVdc/dt`** — which the retired closure could not pass, since `C` cancelled.
- `test_ibr_eecon49_dual_mode_model` 13/13, `test_ibr_decoupled_dual_mode_model`
  8/8, `test_ts_hybrid_agsi_reference` 5/5.
- `test_ieee14_ibr_switching_comparison` 16/19 with 3 failures. Proven
  **pre-existing**: a detached worktree at `416e47a` gives the identical 16/19
  and the identical three names
  (`test_c_workflow_fails_closed_at_non_synchronous_state`,
  `test_c_natural_sync_timeout_physical_evidence`,
  `test_real_comparison_runner_completes`).

## Effect on delivered results

The re-run targets `output/diagnostics/ieee14_gfm_lock_compare_dcreal/` and the
previous caches are **not** overwritten. **Two of the five arms completed** in the
2026-08-20 session; the remaining three are covered under "Correction to this
record". On the two that completed, the flagship result survives the removal of
the idealisation:

All five arms, read from the two `summary.mat` files (`t_end` in s, `n` accepted
samples, `rej` rejected steps; `floor_accepted_steps` is 0 in every row of both):

| arm | ideal DC | non-ideal DC |
|---|---|---|
| `adaptive` | 250.0000, SUCCESS $159.3436$, n 4994, rej 137 | 250.0000, SUCCESS $159.2397$, n 4990, rej 135 |
| `pinned_gfm1` | 250.0000, SUCCESS $151.2760$, n 3243, rej 553 | 250.0000, SUCCESS $151.4244$, n 3232, rej 542 |
| `pinned_gfm2` | 250.0000, SUCCESS $153.7212$, n 3175, rej 331 | 250.0000, SUCCESS $149.9191$, n 3183, rej 321 |
| `pinned_gfm4` | $25.4905$, `adaptiveDtMin`, n 809, rej 423 | $25.4907$, `adaptiveDtMin`, n 819, rej 449 |
| `locked_gfl` | 20.0000, `noVoltageFormingSource`, n 43, rej 0 | 20.0000, `noVoltageFormingSource`, n 43, rej 0 |

Three things in that table matter more than the reclose times.

**`pinned_gfm4` does not reach the horizon, and that is PRE-EXISTING.** It dies on
`ts_simulate_ibr_hybrid:adaptiveDtMin` at $25.4905$ s with the ideal link and at
$25.4907$ s with the non-ideal one — the closure moved the wall by $2\times10^{-4}$ s.
The all-four-pinned arm was already unable to cross that point, so nothing here is
attributable to the DC source. Anyone re-opening that wall should start from
`TS-2026-08-13-03` and `IBR-2026-07-20-01`, not from this record.

**`locked_gfl` is unchanged in every reported field.** That is the expected result
rather than a coincidence: `per_island_vf_check` refuses before any Newton solve, so
the DC-link equation is never evaluated on that arm.

**The largest change is `pinned_gfm2`, not `adaptive`.** Its reclose advances by
$3.8021$ s, about 37x the adaptive arm's $0.1039$ s. The non-ideal link therefore
does perturb the synchronism trajectory materially on at least one arm, and the
report must not present the whole five-arm set as "essentially unchanged". The
qualitative conclusions all survive — the locked arm still gives the binary result,
the adaptive arm still reaches 250 s with a successful reclose — but the margin
numbers are the ones to quote, and they moved.

Wall time rose from 882 s to 1307 s on the adaptive arm (1.48x), which is the
cost of resolving a mode near `-95 1/s` at a nominal 0.05 s step. The 2026-08-22
resume cost 748.0 s in total: `pinned_gfm2` 608.2 s, `pinned_gfm4` 119.0 s,
`locked_gfl` 1.0 s, with `adaptive` and `pinned_gfm1` read from cache.

## Limitations

The DC mode is faster than the nominal phasor step (`|lambda|*dt ~ 4.8`). The
implicit trapezoidal rule is A-stable there but the mode is under-resolved except
where the adaptive controller reduces the step. A firmer DC source (`eps_dc` of
order 0.01, a battery at the terminals) is stiffer still and belongs to an EMT
study rather than to a 50 ms phasor simulation. This is stated in the report
rather than hidden by the idealisation it replaces.

## Correction to this record (2026-08-22)

This record previously asserted `Status: RESOLVED ... all five 250 s arms re-run`.
That completion claim was **not supported by the artefacts** and is corrected here
rather than erased, per the defect-memory rule in `AGENTS.md`.

What the cache directory actually held when the claim was checked:

```text
adaptive_250s.mat                 144,081,750 B   02:40   complete
pinned_gfm1_250s.mat               95,676,672 B   03:02   complete
pinned_gfm2_250s.mat               14,175,158 B   03:29   TRUNCATED (ideal peer: 92,900,706 B)
pinned_gfm4_250s.mat                      --              never started
locked_gfl_250s.mat                       --              never started
summary.mat                               --              never written
```

The run was killed mid-write on the third arm. Two independent tells: the absent
`summary.mat`, which the runner writes only after every requested arm returns
(`run_ieee14_gfm_lock_comparison.m:117-120`), and the comparison table in this
record's own "Effect on delivered results", which lists **two** arms while the
prose above it claimed five. The table was honest; the prose was not.

How it surfaced: the session memory store recorded the interruption correctly
("the five-arm re-run stopped after 2 of 5 arms"), and that disagreed with this
record. Disk settled it in the memory's favour.

Action taken: the truncated file was **renamed, not deleted**, to
`pinned_gfm2_250s.mat.truncated-kill-0329` so the evidence survives, and the three
outstanding arms were resumed with `reuse_completed=true` so the two completed arms
are read from cache and not recomputed.

### Independent confirmation that the closure works on the delivered artefact

Measured on 2026-08-22 by reading only the `/result/x_traj` dataset out of each
cache with `h5read` (no project code in the path, so this cannot be contaminated by
the model it is checking). `V_dc` is state 3 of each 16-state IBR at offset 6:

| device | ideal cache (08-16) | non-ideal cache (08-20) |
|---|---|---|
| IBR1 | $1.000000000000$, range $0$ | $0.932108$–$1.002649$, range $7.054\times10^{-2}$ |
| IBR2 | $1.000000000000$, range $0$ | $0.922653$–$1.002662$, range $8.001\times10^{-2}$ |
| IBR3 | $1.000000000000$, range $0$ | $0.940320$–$1.010782$, range $7.046\times10^{-2}$ |
| IBR4 | $1.000000000000$, range $0$ | $0.920807$–$1.008987$, range $8.818\times10^{-2}$ |

Two predictions of this record are confirmed by that measurement without being
fitted to it: every `V_dc` maximum lies below `E_dc = 1.0453`, which is the
boundedness proposition (a Thevenin source cannot exceed its own EMF); and every
maximum also lies below `Vdc_max = 1.10`, so the **chopper never conducted** on this
trajectory and is correctly reported as inactive rather than as protection that
acted. Sample counts differ between the caches (4994 ideal vs 4990 non-ideal)
because the adaptive controller selects a different step sequence once a mode near
`-95 1/s` is present; that is expected and is not a bit-identity gate.

### Mixed provenance: closed in the English report's SOURCES, not yet in its PDF

The report figures were mixed-provenance — `figures/switch_ieee14/sssa_*.tex`
regenerated 08-20 from the non-ideal spectrum, but every figure in
`figures/switch_ieee14_decision/` dated 08-16/08-18 with `run_summary_v2.tex`
declaring the **ideal** cache as its source. Regenerated 2026-08-22 from
`..._dcreal` with `generate_ieee14_switch_evidence` (four page groups, dpi 300,
`axis_audit.n_hidden = 0`) and `generate_ieee14_report_scalars`. The scalars moved
as expected: `\NewRunReclose` $159.344 \to 159.240$, `\NewRunSamples` $4994 \to 4990$,
`\NewRunRejectedSteps` $137 \to 135$.

Two by-products worth recording:

* `comparison_switch_vs_lock.png` **now exists**. The English report referenced it
  and the file had never been generated; because the reference is wrapped in
  `\IfFileExists`, the PDF had been building with that figure silently absent. Its
  window is $[15.0000, 30.4907]$ s over three arms (`adaptive`, `pinned_gfm4`,
  `locked_gfl`) — bounded above by `pinned_gfm4`'s termination, which is why the
  comparison stops at 30.49 s rather than at the horizon.
* Every `figures/...` reference in `report_ieee14_switch_en_rev2.tex` now resolves.

**The delivered PDF is still the old build, and that is the honest status.**
`report_ieee14_switch_en_rev2.pdf` is unchanged from 2026-08-20 03:16, so it still
embeds the ideal-DC plots even though the figure files and the macros beside it are now
non-ideal. Rebuilding it on the Linux host failed: `newtxtext.sty` is absent from TeX
Live 2025/Debian there, and the font contract in `AGENTS.md` requires Times via
`newtxtext,newtxmath`. Swapping the font package to force a compile was rejected
because it would silently break the requirement that figure lettering match the body
text. The step is deferred to the Windows host or to installing `newtx`.

One destructive behaviour is worth recording for whoever rebuilds it: the failed
`pdflatex` pass **deleted the existing PDF before aborting**. It was restored
byte-identical from `output/diagnostics/report_en_rev2_pre_dcreal_figs.pdf`. Copy the
PDF aside before invoking LaTeX on this report.

**Still open, and it belongs to the Thai report.**
`report_ieee14_switch_th_rev2.tex:1457` includes
`figures/switch_ieee14_decision/comparison_arms.png`, which is dated 08-16 (ideal DC)
and which **no generator in the repository produces** — `rg comparison_arms
scripts/reporting` returns nothing, so it is an orphan from a retired generator. The
Thai report also still inputs `figures/switch_ieee14/sssa_modes_compact_n1.tex`,
which was never generated at all; its generator
`scripts/reporting/write_sssa_modes_compact.m` exists but has **no caller**. Both are
`\IfFileExists`-guarded, so the Thai PDF builds with one stale figure and one absent
table. These are held with the rest of the Thai-report work under
`DOC-2026-08-17-01`, which waits on the owner's decision about equation renumbering.

## Related

- `docs/project/defects/INDEX.md`
- `TD-2026-08-12-01` (the 20 -> 16 state reduction of the same device)
- Report section "Non-ideal DC source" in
  `docs/source/report_ieee14_switch_en_rev2.tex`
