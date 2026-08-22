# Agent handoff — IEEE14 mixed-resource IBR validation closure

Date: 2026-07-17 (Revision 5 corrective closure); 2026-07-18 IBR dynamic-equation contract Phases 0A/1/2/3; 2026-07-18/19 GFL-RMS10 reopening Phases 0/1/2/3/4; 2026-07-19/20 domain-preserving Newton globalization; 2026-07-20 GFM-VSG-no-PLL SMIB-first characterization; 2026-07-21 SSSA load sweep (SMIB loaded-IBR)
Branch: `main`
Tested working tree: `ea7150f` (uncommitted domain-preserving Newton fix on top of all-GFL equilibrium)

This is the current canonical handoff. Historical phase handoffs remain
provenance but do not override this runtime status.

## 2026-08-22 (later) — BOTH SWITCHING REPORTS BROUGHT IN LINE WITH THE CODE

Tested working tree: uncommitted, on top of `76f6ea4`.
Environment: MATLAB R2026a Update 3 (glnxa64); TeX Live with `xelatex`
(`newtxtext.sty` **absent**, which still blocks the English PDF).

Two report-truth defects were closed in this pass. Read them in this order:
`DOC-2026-08-22-02` (the DC-link prose) and `DOC-2026-08-17-01` (the 16-state
correction and the equation-renumbering map).

**The English report contradicted itself inside one subsection.** `NUM-2026-08-20-01`
updated the displayed DC-link row but not the paragraph that proves it. The align
row printed the Thevenin-plus-chopper closure while the "Proof of each row"
paragraph four lines below still said the coded current was
`I_dc = P_ac/V_dc + (C/T_dc)(V_dc^0-V_dc)`, that the feed-forward "cancels
exactly", that "this cancellation is deliberate", and that "at steady state row
(3) gives `V_dc = V_dc^0`". Those are exactly the three claims that defect was
opened to remove. My own earlier statement in this session that the English
report was correct on the model was therefore wrong, and is retracted in the
record. Also corrected there: the glossary listed `T_dc` as a live parameter; the
figure-source paragraph and the file header declared the **ideal** cache after
every figure had been regenerated from `..._dcreal` (the generated
`run_summary_v2.tex` already declared `_dcreal`, so one page asserted two
provenances); and the text promised "the figure of `n_x(t)` below" which the
report does not contain.

**The Thai report is now fully corrected and its PDF is rebuilt.** It carried the
whole earlier generation: a 20-state IBR, the retired ideal DC row, prose that
explicitly *defended* the `P_ac/V_dc` cancellation, small-signal prose calling the
four real roots near `-10 s^-1` the DC family (that value is `-1/T_dc` of the
retired closure, while the table it introduces prints `-96.812311` ...
`-91.111042`), a `200 s` provenance declaration that had become false once 11 of
its 15 figure inputs were regenerated from the 250 s `_dcreal` arm, an `\input` of
a compact modal table that has **never existed**, and an include of the
generator-less `comparison_arms.png`. Both orphans sat inside `\IfFileExists`
guards, so the missing table was **silently omitted** rather than failing the
build — worth remembering before trusting that a report compiled cleanly.

**The equation-renumbering blocker is resolved, not bypassed.** That is what had
held the Thai fix since 08-17, because the owner cites equations by printed
number. Deleting the four command-delay rows removes four numbered `align` rows,
so the count goes 52 -> 48. The full map, produced by enumerating numbered
equations in both trees rather than by hand:

```text
(1)-(32)   unchanged        through the GFL inner-current rows
(33),(34)  DELETED          GFL command-delay rows
(35)-(41)  -> (33)-(39)     the seven GFM branch rows, shift -2
(42),(43)  DELETED          GFM command-delay rows
(44)-(52)  -> (40)-(48)     shift -4
   eq:transfer 44->40  eq:contgate 45->41  eq:stackf  46->42
   eq:dae      47->43  eq:trap     48->44  eq:resid   49->45
   eq:frozen   50->46  eq:assign   51->47  eq:nxcount 52->48
```

**No equation was added.** Every new derivation in this revision — the forced
`E_dc`, the equilibrium quadratic, the boundedness argument, the predicted
`lambda_dc` — is written as inline math specifically so that nothing below it
moves a second time. The same map is in the Thai report's header comment so it
travels with the file. The English report's 40 `eq:` labels are in the identical
order they were at the start of the session, so nothing renumbered there at all.

**The active dimensions were verified against the artefact, not asserted.**
`generate_switch_new_report_figures` was re-run against
`output/diagnostics/ieee14_gfm_lock_compare_dcreal/adaptive_250s.mat` with
`t_max=250` and reports `nx_before_trip = 41` with per-device
`[5 9 9 9 9] -> [5 10 9 9 9]` across the first promotion. That is `41 = 5 + 4*9`
and a `9 -> 10` step, published by the same `ts_dynamic_state_indices` authority
the integrator uses. The `n_x` figure the Thai report shows is that re-run.

One adapter was needed and is worth knowing: the 250 s arm caches store the
trajectory as `result`, while `generate_switch_new_report_figures` loads `r` (its
default input `engine_release_200s_preserved.mat` stores `r`). A temporary script
renamed the struct — nothing numerical changed — which is the same fallback the
current decision-figure generators already implement
(`generate_ieee14_decision_figure.m:230-236`). If that generator is touched again,
give it the same `isfield` fallback rather than repeating the adapter.

`mode_switch_PQ.png` and `mode_switch_electrical.png` under
`docs/source/figures/switch_ieee14_new/` were **deliberately restored** to their
08-11 bytes after that run overwrote them. They belong to the superseded
non-`rev2` reports; refreshing them from a different cache and horizon would have
silently changed those reports instead. Only `state_switch_dimension.png`, the one
file a `rev2` report includes, was kept.

**Gates run.** `xelatex` twice on the Thai report: exit 0, no undefined
references, 32 pages. `pdftotext` on the result confirms `E_dc - V_dc` in the DC
row, the measured DC eigenvalue family in the modal table, `5+4x9=41` and
`5+4x10=45`, the state table's `9`/`10` totals, GFM rows printed `(10)`-`(16)`,
and a highest printed equation number of `48`. Static checks on the English
report: 38 `equation` + 5 `align` environments, 40 `eq:` labels in unchanged
order, braces balanced, `$` count even. The full MATLAB regression was **not**
run and was not required: no production `.m` file changed in this pass — the only
MATLAB executed was report-figure generation from an existing cache.

**Still open, and it is the same one item.** The English PDF is the 08-20 build,
so none of the English source corrections above are visible in the delivered PDF
yet. `newtxtext.sty` is absent from TeX Live on this host, the `AGENTS.md` font
contract forbids substituting a package to force a compile, and a failed
`pdflatex` pass **deletes** the existing PDF. Rebuild on the Windows host that
produced the 08-20 build, or install `newtx` first, and copy the PDF aside before
invoking LaTeX. The Thai PDF is current.

**Agent-review disclosure.** This session's configuration states that the Agent
tool must not be used unless the user requests it, so the `Explore` -> `Plan` ->
`custom-advisor` workflow in `CLAUDE.md` was performed as an explicit
self-review pass instead. No agent was consulted. Every material claim above is
backed by a command whose output is quoted in the defect records.


## 2026-08-22 — NON-IDEAL DC LINK: closure delivered, evidence re-run resumed (`NUM-2026-08-20-01`)

Tested working tree: uncommitted, on top of `416e47a` (== `origin/main`).
Environment for this session: MATLAB R2026a Update 3 (26.1.0.3276743) on
**glnxa64**, the same NTFS volume previously worked from Windows 11.

**The idealisation is gone and the model now carries DC dynamics.** The owner
questioned a small-signal participation of exactly `1.000` on a DC-link voltage,
four times over. The suspicion was correct: the retired closure
`Idc = Pac/Vdc + (C/Tdc)(Vdc0-Vdc)` with `dv = (Idc-Pac/Vdc)/C` cancels `Pac/Vdc`
identically, leaving `dVdc/dt = (Vdc0-Vdc)/Tdc` whose equilibrium **is** the
initialiser's own `x(3) = Vdc_ref`; and `C` cancels too, so the declared `Cdc = 0.10`
never entered a residual, a Jacobian or an eigenvalue. Replacement (owner chose
Thevenin-plus-chopper from four candidates):

```text
C dVdc/dt = (Edc-Vdc)/Rdc - Pac/Vdc - max(0,Vdc-Vdc_max)/Rch
```

State count, state order, layout, active-index sets, transfer contract and schema
are all unchanged: still 16 states per IBR, still `6+4*16 = 70` composite rows.

**Independent confirmation on the delivered artefact.** Read on 2026-08-22 with
`h5read` against only the `/result/x_traj` dataset, so no project code is in the
measurement path:

| device | ideal cache (08-16) | non-ideal cache (08-20) |
|---|---|---|
| IBR1 | $1.000000000000$, range $0$ | $0.932108$–$1.002649$, range $7.054\times10^{-2}$ |
| IBR2 | $1.000000000000$, range $0$ | $0.922653$–$1.002662$, range $8.001\times10^{-2}$ |
| IBR3 | $1.000000000000$, range $0$ | $0.940320$–$1.010782$, range $7.046\times10^{-2}$ |
| IBR4 | $1.000000000000$, range $0$ | $0.920807$–$1.008987$, range $8.818\times10^{-2}$ |

Every maximum sits below `Edc = 1.0453`, which is the boundedness proposition a
Thevenin source satisfies by construction, and below `Vdc_max = 1.10`, so the
**chopper provably never conducted** on this trajectory and is reported as inactive
rather than as protection that acted. The spectrum was predicted before it was
recomputed — `lambda_dc = -(1/C)(1/Rdc - Pac/Vdc^2) = -100 + 10 Pac/Vdc^2` — and the
regenerated table returns four **distinct** real modes `-96.812311`, `-92.911157`,
`-92.693034`, `-91.111042` ordered by the power each converter carries.

**What this handoff corrects.** The defect record originally read
`Status: RESOLVED ... all five 250 s arms re-run`. That was untrue and is corrected
in the record itself rather than erased. The cache directory held two complete arms
(`adaptive`, `pinned_gfm1`), one arm **truncated by a kill**
(`pinned_gfm2`, 14.2 MB against its 92.9 MB ideal peer), two never started
(`pinned_gfm4`, `locked_gfl`) and **no `summary.mat`** — which the runner writes only
after every requested arm returns (`run_ieee14_gfm_lock_comparison.m:117-120`). The
record's own comparison table listed two arms while the prose above it claimed five;
the table was honest. The truncated file was **renamed, not deleted**, to
`pinned_gfm2_250s.mat.truncated-kill-0329`.

Reused-arm metrics reproduce exactly on Linux, so the platform change is not a
variable: `adaptive` 250.000000 s, reclose SUCCESS 159.2397, 4990 samples, 4 GFM max,
4 support commits applied / 0 rejected; `pinned_gfm1` 250.000000 s, reclose SUCCESS
151.4244, 3232 samples.

**The five-arm evidence is now complete.** `pinned_gfm2`, `pinned_gfm4` and
`locked_gfl` were resumed with `reuse_completed=true` (748.0 s total; the two finished
arms read from cache), `summary.mat` carries five rows, and every arm's expectation is
MET in both caches:

| arm | ideal DC | non-ideal DC |
|---|---|---|
| `adaptive` | 250.0000, SUCCESS $159.3436$, n 4994, rej 137 | 250.0000, SUCCESS $159.2397$, n 4990, rej 135 |
| `pinned_gfm1` | 250.0000, SUCCESS $151.2760$, n 3243, rej 553 | 250.0000, SUCCESS $151.4244$, n 3232, rej 542 |
| `pinned_gfm2` | 250.0000, SUCCESS $153.7212$, n 3175, rej 331 | 250.0000, SUCCESS $149.9191$, n 3183, rej 321 |
| `pinned_gfm4` | $25.4905$, `adaptiveDtMin`, n 809, rej 423 | $25.4907$, `adaptiveDtMin`, n 819, rej 449 |
| `locked_gfl` | 20.0000, `noVoltageFormingSource`, n 43, rej 0 | 20.0000, `noVoltageFormingSource`, n 43, rej 0 |

Read that table for three things, not for the reclose times. **`pinned_gfm4` never
reached the horizon and that is pre-existing** — the wall moved by $2\times10^{-4}$ s
between the two closures, so it is not attributable to the DC source; start from
`TS-2026-08-13-03` / `IBR-2026-07-20-01` if it is re-opened. **`locked_gfl` is
unchanged in every field**, which is expected because `per_island_vf_check` refuses
before any Newton solve, so the DC equation is never evaluated there. **The largest
change is `pinned_gfm2`, not `adaptive`:** its reclose advances $3.8021$ s, roughly 37x
the adaptive arm's $0.1039$ s, so the five-arm set must not be summarised as
"essentially unchanged" — the qualitative conclusions survive, the margin numbers
moved.

**Mixed provenance: CLOSED for the English report.** The English `rev2` report had
been describing a Thevenin link while plotting a run in which `V_dc` was frozen at
1.000000 — its model section and `sssa_*.tex` inputs were non-ideal, but every figure
in `figures/switch_ieee14_decision/` was dated 08-16/08-18 and `run_summary_v2.tex`
declared the **ideal** cache as its source. Regenerated 2026-08-22 from `..._dcreal`
(four page groups, dpi 300, `axis_audit.n_hidden = 0`), then scalars rebuilt:
`\NewRunReclose` $159.344 \to 159.240$, `\NewRunSamples` $4994 \to 4990$,
`\NewRunRejectedSteps` $137 \to 135$. Every `figures/...` reference in
`report_ieee14_switch_en_rev2.tex` now resolves, including
`comparison_switch_vs_lock.png`, which the report had always referenced and which had
never been generated — the `\IfFileExists` guard meant the PDF simply built without
it. The 16 ideal-DC figures were copied to
`output/diagnostics/figures_backup_pre_dcreal_regen/` before being overwritten,
because that figure directory is untracked and git could not have restored it.

**A false provenance sentence was found and fixed while doing this.**
`generate_ieee14_report_scalars.m` hardcoded "That re-run was gated on being
bit-identical to the delivered artifact" into every file it wrote. That is true only
of the ideal-DC cache, whose re-run really was gated that way; stamped onto the
non-ideal cache it is a false claim, because the closure changed on purpose. The
sentence is now selected from the cache actually read (`ibr` cache-name comparison, not
a substring test), the non-ideal branch states plainly that bit-identity is **not**
claimed and why, and the `Regenerate with:` line now carries the real `result_file` so
the command reproduces the file instead of silently defaulting back to the ideal cache.
`checkcode` clean.

**Still open, and it is Thai-report work.** `report_ieee14_switch_th_rev2.tex:1457`
includes `comparison_arms.png`, dated 08-16 and produced by **no generator in the
repository** (an orphan from a retired one), and `:1132` inputs
`sssa_modes_compact_n1.tex`, which was never generated because its generator
`scripts/reporting/write_sssa_modes_compact.m` has **no caller**. Both are
`\IfFileExists`-guarded, so the Thai PDF builds with one stale figure and one absent
table.

**FAIL-CLOSED: the English PDF was NOT rebuilt, so the delivered artefact still
embeds the ideal-DC figures.** The regeneration above fixed the figure *sources* and
the scalar *macros*; `report_ieee14_switch_en_rev2.pdf` is still the 2026-08-20 03:16
build and therefore still shows the old plots. Rebuilding it on this Linux host is
blocked: `newtxtext.sty` is absent from TeX Live 2025/Debian here (`kpsewhich
newtxtext.sty` empty, `find / -name newtxtext.sty` empty), and the report's font
contract in `AGENTS.md` requires Times through `newtxtext,newtxmath`. **Substituting a
different font package to make it compile was rejected** -- it would silently break the
requirement that figure lettering match the body text in typeface and size, which is
the whole point of that contract. Installing the package needs network plus system
package authority and is outside this session's scope, so the step is deferred rather
than worked around.

Evidence and collateral, stated because a `pdflatex` failure is destructive here: the
first pass **deleted the existing PDF before aborting**. It was restored
byte-identical from a pre-run copy at
`output/diagnostics/report_en_rev2_pre_dcreal_figs.pdf` (`cmp` clean). The failed run
also overwrote the build log; it is preserved as
`report_ieee14_switch_en_rev2.FAILED-linux-no-newtx.log` so it cannot be mistaken for
the log of the delivered build, whose own log is lost. **Anyone rebuilding this report
must copy the PDF aside first.**

Rebuild either on the Windows host that produced the 08-20 build, or after installing
`newtx` here; then confirm the embedded figures carry the 19:40--19:41 timestamps
rather than the 08-16/08-18 ones.

**Kernel file touched, ownership re-check required before anyone else edits it.**
`+stability/ts_step_composite.m:307` gains one registered identifier
`ibr:dc_source_thevenin:dcVoltage` in the existing `trial_domain_classifier`, whose
only prior member was the RMS10 low-voltage inversion. `P_ac/V_dc` is singular at
`V_dc = 0`, which is the physics of a constant-power load on a DC bus and cannot be
removed; a Newton line-search **trial** can propose `V_dc <= 0` even when the accepted
iterate is physical. This does not weaken a gate: a violation at an **accepted** state
is thrown outside that try/catch and still aborts, and `composite_newton.m:132-136`
never assigns the accepted iterate, its residual or its Jacobian from a rejected
trial. Widening the guard so `1/V_dc` were evaluated anyway would have been a silent
fallback and was rejected.

**Gates run this session, all on glnxa64:** `tests/test_ibr_dc_source_thevenin.m`
**9/9**, `tests/test_ieee14_arm_metrics.m` **14/14**, 0 failed and 0 incomplete in both —
so the DC closure's own suite and the metric consumer that reads the regenerated
summaries are green on this platform, not merely inherited from the Windows session.
`checkcode` clean on the one script changed here. The independent `h5read` measurement
and the reused-arm metric reproduction are recorded above. Full repository regression
not run — optional per repository policy; the targeted gates cover the changed producer
(`generate_ieee14_report_scalars.m`), its output, and the DC closure whose evidence was
completed.

**Session limitation, disclosed:** the mandatory `Explore` / `Plan` / `custom-advisor`
review agents were not invoked, because this session was configured not to call the
agent tool. The equivalent inspection and self-review was performed directly by the
primary agent against repository evidence, and every material claim above is backed by
a file, a line number or a measurement rather than by agent assertion.

## 2026-08-17 — Reports described a 20-state IBR the run does not integrate (`DOC-2026-08-17-01`)

Tested working tree: uncommitted, on top of `416e47a`. Status **PARTIALLY RESOLVED**:
corrected in the English `rev2` report, still stale in the Thai `rev2` report.

Both switching reports stated a fixed **20**-vector IBR state
(`x_pl(3) | GFL 4..11 | GFM 12..20`), `A_GFL = {1:11}`, `A_GFM = {1:3,12:20}`, an
`11 -> 12` active-dimension step, and two integrated command-delay rows per branch.
The executed model is `+ibr/eecon49_dual_mode_model.m` with `dev.nx = 16` over
`plant 1:3 | GFL 4:9 | GFM 10:16`, `gfl_active = 1:9`, `gfm_active = [1:3 10:16]`.

The decisive check needs no model knowledge — the row count of the delivered
trajectory is **70**, and `70 = 6 + 4*16`. A 20-state IBR would give `6 + 4*20 = 86`
and the 17-state `decoupled_dual` variant would give `74`. Neither is 70.

Cause: the report text predates `TD-2026-08-12-01`, which removed the command-delay
states by singular perturbation — the source lag carries `T_d = 1.5/f_sw ~= 0.3 ms` at
`f_sw = 5 kHz`, more than 300x below the phasor step, so `v_del = v_cmd` on the slow
manifold. Wrong: the state count, block sizes, index ranges, both active-set
expressions, the dimension step, and the two lag rows in each branch block. **Not**
wrong: every equation of every retained state, so no reported number, figure or gate
moves. This is a documentation defect, not a numerical one.

**Residual, and why it is held rather than fixed.**
`docs/source/report_ieee14_switch_th_rev2.tex` still carries the stale text at `:623`
(section title), `:626`, `:630-632`, `:637-641`, `:646-647`, `:651`, `:655`,
`:660-698` (a 20-row state table including rows 10, 11, 19, 20 and the `11`/`12`
active totals at `:695`), `:898-902` and `:1025`. It is additionally stale on the DC
closure: `:729` still prints `dVdc/dt = (1/C)[(C/Tdc)(Vdc0-Vdc)]` and `:742-747`
explicitly **defends** the `Pac/Vdc` cancellation as intentional design, so after
`NUM-2026-08-20-01` the Thai text contradicts production code rather than merely
lagging it. Correcting the IBR section **shifts every equation number after it**, and
the project owner refers to equations by number, so the change waits on an explicit
decision instead of being applied silently.

**Two silent omissions found while checking, both `\IfFileExists`-guarded so the PDFs
build with the content simply absent:** the Thai report inputs
`figures/switch_ieee14/sssa_modes_compact_n1.tex`, which was never generated — its
generator `scripts/reporting/write_sssa_modes_compact.m` exists but has **no caller**
anywhere in the repository; and the English report references
`figures/switch_ieee14_decision/comparison_switch_vs_lock.png`, which does not exist.
`figures/switch_ieee14/handback_comparison_summary.tex` is a 0-byte file.

## 2026-08-16 — THREE-ARM COMPARISON: the switching policy is measured, not asserted (AGSI-2026-08-16-01)

Tested working tree: on top of `416e47a` (== `origin/main`). No production file changed.

The study now answers "how much better is the switching policy" with numbers, on
three arms of the same 250-s chronology that are **bit-identical up to the SG
trip** (`max|Δx| = max|Δy| = max|Δu| = 0` over 42 shared samples, every pair), so
the difference afterwards is attributable to the control policy and nothing else.

```text
arm            horizon   reclose      GFM max   outcome
adaptive       250.000   159.3436     4         SUCCESS, f_COI 60.000000 Hz
pinned_gfm1    250.000   151.2760     1         SUCCESS (manual_override, IBR2)
locked_gfl      20.000   --           0         refused: noVoltageFormingSource
```

**The locked arm gives the binary result.** With all four converters locked
grid-following the SG is the only voltage-forming source, so opening its breaker
leaves an energised island with no angle reference; `per_island_vf_check` refuses
before any Newton solve and the trajectory ends at the event-left sample. On this
resource mix, promoting at least one converter is a *necessary condition* for a
post-trip trajectory to exist — not an improvement to one.

**The pinned arm gives the quantitative result**, and it survives, so the honest
claim is a margin comparison rather than survival. Adaptive wins 4 of the 5
disturbance windows on peak excursion, and loses the SG trip itself:

| window | adaptive | pinned 1 GFM | settled: adaptive | settled: pinned |
|---|---|---|---|---|
| SG trip 20 s | 0.7587 | **0.5312** | 0.0040 | 0.0113 |
| load +20 % 50 s | **1.0042** | 1.4478 | **0.3753** | 1.2215 |
| fault 85 s | **1.1386** | 1.4977 | **0.3753** | 1.2296 |
| line 6-13 trip 110 s | **0.3764** | 1.2325 | **0.3503** | 1.1426 |
| restore/reclose 145 s | **1.1605** | 1.1736 | **0.0120** | 0.0203 |

(`max|f_COI − 60|` and the mean over the last 30 % of each window, both in Hz.)

The larger effect is the **settled** deviation, not the peak: after the load step
the adaptive island holds 0.3753 Hz against 1.2215 Hz, a factor of **3.26**. The
mechanism is droop sharing — the supervisor had promoted four units by then, so
each carries a quarter of the imbalance. The adaptive arm's loss at the SG trip is
the transient cost of its own promotion sequence and is reported as found.

**Selector-table result worth keeping.** The SG_OFF band at the correct dispatch
enumerates 15 candidates and the admissible set is **not monotone in the number of
grid-forming units**: all four singletons are ready, only `[2 4]` and `[3 4]` of
the six pairs are, no triple is, and the full set is. This is direct evidence that
the configuration table has to be *computed* rather than guessed, and that "more
grid-forming is safer" is false on this system.

**What was blocking, and what it cost.** The delivered artifact carries no
reference-AGSI overlay: the option is `agsi_reference`, it defaults false, and the
published driver never set it — see `AGSI-2026-08-16-01`. The re-run needed for
the sub-indices was gated on bit-identity against the delivered artifact and
passed exactly, including a COI residual of `0.000e+00` between the overlay's own
centre-of-inertia frequency and the published one.

**Deliverables** (all under `docs/source/figures/switch_ieee14_decision/`):
`decision_indices.png` plus island- and reclose-window zooms (9 panels: `S` with
`Γ_on`/`Γ_off`, the six sub-indices, mode, reference owner, two marker families);
`electrical_adaptive.png` and `electrical_pinned_gfm1.png` (8 panels);
`comparison_arms.png`; `comparison_event_excursions.png`;
`comparison_summary.tex` + `comparison_macros.tex`. One command rebuilds
everything: `generate_ieee14_switch_evidence`.

**Gates run:** 45/45 on the four new/touched test files
(`test_ieee14_switch_event_marks` 11, `test_ieee14_arm_metrics` 14,
`test_ieee14_decision_signals` 15, `test_ts_hybrid_agsi_reference` 5) plus the
targeted supervisor/reclose/COI suites. Full repository regression not run; this
change adds only reporting code and one added assertion to an existing test.

**Deferred, with the reason recorded:** the all-synchronous five-SG arm. It hits
four independent single-SG walls (`sg_composite_device:singleMachineOnly` at
`:72`/`:192`, `ibr_config_selector:sgReferenceOwner` at `:110-134`,
`mixed_equilibrium_solve:badSGReference` at `:177-193`,
`ts_simulate_ibr_hybrid:syncControllerSg` at `:3772`) and the repository has
per-machine dynamic data for bus 1 only. The arm table already carries a
`scenario_fn` per row so that arm slots in without restructuring.

## 2026-08-15 — SG RECLOSE SUCCEEDS AND THE 250-s CHRONOLOGY COMPLETES (AGSI-2026-08-14-02 + RECLOSE-2026-08-15-01)

Tested working tree: on top of `f786f0d` (== `origin/main`).

**Both blockers are resolved and the canonical chronology now runs end to end:**

```text
conv=1  t_end=250.000000  failure_id=[]  wall=533.4 s
requested_sg_on=145   actual_reclose=159.3436   status=SUCCESS
dV 0.004743/0.05   df 1.59e-05/0.001   dtheta 0.9677/10 deg   limiting_gate=none
terminal: f_coi=60.000000 Hz  bus |V| 0.9667..1.0575  handback C1_COMPLETE
          reselection_status=NO_FEASIBLE_SG_ON_ONE_STEP  (correct fail-closed)
          rejected_steps=137  floor_accepted_steps=0
```

The reclose closes on merit inside the unchanged 20-s timeout with positive
margin on all three synchronism sub-gates. No threshold, dwell, timeout, event
time, tolerance, limit, AGSI weight, or test expectation was changed anywhere.

**Independent oracle.** The terminal state reproduces the published EECON49
Figure-4 operating point, which neither correction touches:

```text
dev    mode   |I|       P pu      Q pu      |S| pu   published
SG1    sg     1.34620   1.33190  -0.19567   1.3462   134.62 MVA
IBR2   GFM    0.36623   0.31718   0.17674   0.3631    36.31 MVA
IBR3   gfl    0.34156   0.28844   0.16073   0.3302    33.02 MVA
IBR6   gfl    0.48093   0.44428   0.24757   0.5086    50.86 MVA
IBR8   gfl    0.29199   0.26765   0.14915   0.3064    30.64 MVA
```

IBR2's terminal current matches its certified SG_ON `[2]` equilibrium value
`0.366232` to five decimals — 69 % below the limit it had previously been pinned
on for 12 s.

### Correction 1 — `AGSI-2026-08-14-02`, transition certificate (opt-in)

The unconditional form of the incumbent-`xi` conditioning was FALSIFIED by
measurement (it turns the healthy `t=22.05` arrival from a 19.7 deg stable swing
into a 376 deg slip). The transaction now evaluates candidates
**least-intervention-first**: (1) the arrival exactly as the ordinary transfer
maps leave it, committed untouched if a forward trial with the production kernel
rides it; (2) only if that fails, the incumbent-conditioned variant; (3) if
neither rides, refuse fail-closed. Over 250 s conditioning fires at exactly ONE
transaction — `t=53.4025`, untouched 195.1 deg rejected, conditioned 15.562 deg
accepted — and the other four certificate-bearing commits go untouched. Opt-in
`support_transition_certificate`, default OFF, default path proven
byte-identical. Slip limit is the unstable-equilibrium separation (180 deg), not
the steady-state pull-out limit (90 deg).

### Correction 2 — `RECLOSE-2026-08-15-01`, post-reclose command timescale (opt-in)

`derive_handback_duration` returns ONE duration
`T = max(T_minimum_hold, t_mode, t_control)` and `enter_online_governor` used it
for EVERY post-reclose command. The SG field voltage therefore walked
`0.169925 -> 0.989169` over `t_mode = 13.875 s`, which is **11.6x** the declared
actuator response `t_control = -log(rho)*max([Tsv Tch TA]) = 1.198 s`. The
machine stayed under-excited, IBR2's voltage-loop q integrator overshot its
equilibrium by 5.3x (`xi_Vq` `-0.2114` vs `-0.0396`), `|I_ref|` reached
`Imax = 1.2`, `conditional_hold` froze both integrators to six figures for 12 s,
and the coupled algebraic system lost solvability at any step size.

Fix: split the timescales. `derive_handback_duration` also returns `t_control`;
`enter_online_governor` takes an optional `T_efd`; only the FIELD-VOLTAGE command
uses it. Mechanical power and the IBR P/Q references keep the full duration, so
`SWITCH-2026-08-10-03`'s 1.28758 pu command-step concern is unaffected. New
option `handback_efd_timescale` in {`mode` (default, byte-identical), `control`}.
The alternative duration is the expression the same function already computed for
the declared lags, frozen by test — not a fitted number.

Also plumbed: `fd_perturbation` (existing kernel FD rule) through the driver,
default `absolute` and byte-identical.

### Falsified during this work, recorded so nobody re-runs it

Four numerical arms all die at the same place, so the wall was never a solver
artefact: baseline `173.005724`, `fd_perturbation='scaled'` `173.005776`,
`reject_limit=40` `173.005724` (bit-identical), fixed `dt=0.02` `172.580000`.
Also falsified: inner-loop integrator windup (`xi_Id` stays ~1e-6); a large
angular displacement (a rad-vs-deg unit error of mine — the true pairwise gap is
~10 deg); a stale `E_ref` (it equals the terminal voltage at the certified
destination to `0.000e+00`); and the undocumented `handback_complete` ordering
gate as the primary cause (with excitation restored on the actuator timescale the
ramp completes, the gate opens by itself, and the release is then refused on its
merits).

**Diagnostic-harness defect worth knowing:** passing `s.scenario_opt` as the
`scenario` argument to `stability.ibr_selector_table` makes
`ibr_config_selector.m:305-320` resolve NO dispatch, so every SG_ON row is
certified at IBR `P_ref = 0` with the SG carrying 2.55-2.73 pu. Production
`run_hybrid_case.m:410-411` passes the full struct and is unaffected. Arithmetic
tell: the defective `[2]` row gives `omega = -0.194035` and hence
`handback_duration_s = 15.439096`; the correct one gives `-0.215905` and
`13.875225`.

Gates: G0 clean · G1 oracle PASS on all three commits · G4 **outcome (a)
SATISFIED** · targeted regression recorded below. Full repository regression not
run — optional per repository policy; the targeted gates cover the changed
producer and its consumers.

Residual items left for the owner, neither blocking: the `handback_complete`
conjunct in `hold_ok` (`ts_simulate_ibr_hybrid.m:1078-1081`) is still
undocumented and untested; and `ibr_config_selector` still ignores a dispatch
supplied under a key it does not consume instead of failing closed.

## 2026-08-14 — Incumbent-GFM xi conditioning: implemented, gate-failed, NOT delivered (AGSI-2026-08-14-01)

Approved plan: map incumbent EECON49 GFMs' `gfm_xi_Vd/gfm_xi_Vq` to the
authenticated candidate `eq_x0` inside `sg_off_support_transaction` (new pure
helper `+stability/condition_eecon49_incumbent_gfm_state.m`, named-state only,
`1e-10` current guard, atomic fail-closed; `ibr_decoupled_dual` byte-identical
no-op). Contract evidence 50/50 (8 pure + 8 integration + regressions), no
parameter/gate/threshold/event change anywhere.

**Gate outcome: FAILED — reclose still not reached, and the tree now fails
earlier (adaptiveDtMin at t=24.917 s vs baseline t=152.017 s).** Three facts
rule out an implementation defect: (1) baseline and corrected runs are
bit-identical up to the first xi assignment, which then equals the certificate
exactly; (2) replay at the t=24.06 all-four commit slips WITH the conditioning
(1095 deg) and WITHOUT it (2060 deg), while continuing the `[2 4]` island
without the commit converges; (3) the corrected supervisor path simply commits
all-four mid-transient (arriving voltage-profile distance to the certificate
0.064 pu vs 0.020 pu at the baseline's settled t=53.40 commit). The defect has
two components and this correction removes only one: stale incumbent xi at an
admissible commit (fixed), and inadmissible mid-transient commits (unfixed,
and now actively reached). Correction class 2 (arriving-state admissibility /
transition certification, fail-closed refusal) or a supervisor settle interlock
is the candidate next plan; neither is approved.

Disposition: the helper and tests remain UNCOMMITTED in the working tree
(committing a gate-failing production transaction would publish a regressed
chronology); `AGSI-2026-08-14-01` stays OPEN with the full evaluation appended;
the TRACK_COORDINATION claim is HELD (not released) until the owner decides
discard-vs-extend. Also recorded: the plan's 60-s short-chronology gate G5 is
infeasible on the canonical chronology (`fault_clear <= t_end` schedule
contract forbids t_end<85.15 s), and the helper's current guard is structurally
blind to the conditioned coordinates (terminal current = state `i_d/i_q`).

## 2026-08-13 — Decoupled GFM model + reference-AGSI overlay (`MODEL-2026-08-13-01`)

A project-owned GFM family now sits alongside the EECON49-mapped baseline, which
stays byte-faithful (SHA-256 verified, its two test files pass unmodified). The
new swing block separates the three roles that the source structure conflates:

```text
M d(omega)/dt = kappa P_ref - P_inv - (1/R)(omega-1) - D_t (omega - omega_f)
d(omega_f)/dt = w_D (omega - omega_f)
```

`R` alone fixes the steady-state droop, `D_t` alone adds transient damping
through the washout, `M` alone fixes inertia. The extra state is unavoidable:
two proportional speed terms collapse to one coefficient, which is why the
in-repo REGFM_B1 reference ships `D1=0` and damps through `D2` + washout.

**The measurement that changed the story.** `K` had never been measured; the
contract used an estimate `K~=5 pu/rad`. Read off the full-KCL Schur-reduced
SSSA matrix, `K_ii = 0.1135..0.1862 pu/rad` — 27–44x smaller. So at 5 % droop
the coupled VSG is **over-damped** (`zeta = 4.22..5.40`), not `zeta~=0.81`;
`Dv=1.50` gives `0.41`, not `0.06`; and `M=5.0` gives `0.68`, not `0.10`, which
voids the earlier reason for rejecting `H_v=2.5 s`. Those three figures are
withdrawn in `EECON49_GFL_GFM_SOURCE_CONTRACT.md`. The `Dv=20` **droop**
justification is unaffected; only its damping claim was wrong. On the
single-machine characteristic no `Dv` reaches both 5 % droop and
`zeta ≈ 1/sqrt(2)` — the latter would require 30–38 % droop — which is the
structural gap the decoupled model closes.

Trap for future retunes: `zeta(D_t)` is **non-monotone**, so the small-`D_t`
approximation must not be used; solve the exact cubic (a test asserts this).

**Correction the same day (`MODEL-2026-08-13-02`) — read this before setting
`D_t`.** The first values shipped, `w_D = 3.0` and `D_t = 20`, were sized on that
single-machine cubic at the SG-online `K`. Running the production chronology
falsified the basis at once: the authenticated all-four SG-off island became
small-signal **unstable** (`Omega = +0.336` versus the coupled baseline's
`-0.483`), the SG-trip transaction refused to commit an uncertified
configuration, and the run failed closed at `t = 1.0` with `candidateNotReady`.

Cause is filter placement. At `D_t = 0` the island's slowest mode is
`-0.4829 ± 3.917j`, i.e. 0.623 Hz (3.92 rad/s); `w_D = 3.0 rad/s` is 0.48 Hz, so
the washout corner sat on the mode it was meant to damp, all four washout poles
migrated into it, and the phase lag made the damping path positive feedback. The
basis was wrong because `w_D` was sized from the SG-online `w_n = 23..30 rad/s`.
Measured on the island through the production dispatch path, the synchronising
coefficients are `[-0.0151, 0.0015, 0.1169, 0.0525] pu/rad` — two of them `<= 0`,
so the single-machine cubic has no real `w_n` there at all. Designing a
grid-forming damping term at the SG-online operating point was the underlying
error: the island is the point the device exists to serve.

The measured `(w_D × D_t)` surface then settled the question: **no** `D_t > 0`
improves this system at any `w_D` from 3 to 100, while the SG-online margin moves
by `1.1e-6` across the same 25 points. `D_t` is therefore `0` on measured
evidence and `w_D` is `50` (REGFM_B1 Table-1 `SOURCE_VERBATIM`, ~13× above the
island mode, so an enabled `D_t` cannot repeat the placement error). The
"5 % droop AND `zeta ≈ 1/sqrt(2)`" claim is withdrawn as a single-machine figure
that was given system scope; its test was rewritten to assert only the structural
separation, and a new island oracle keeps the withdrawn pair refused.

What survives intact: the separation itself. `D_t = 0` reproduces the coupled
baseline bit-for-bit (island margin agrees to `1.2e-13`), `R` alone fixes the
droop, and `D_t` moves the Schur-reduced trace by exactly `-4 D_t/M`. The damping
knob is delivered, characterised, and set to zero — on this island it has no
beneficial setting, which is a measured property of the network, reported as
found.

**Reference-AGSI overlay (opt-in `agsi_reference`).**
`+stability/agsi_reference_terms.m` publishes `J_R/J_P/J_SCR/J_lock` plus the
trigger pair with per-sample in-band flags, as pure post-processing, with **no
aggregate index**. Switching still consumes `J_V/J_f` only, proven byte-identical
on 13 arrays, all decision fields and the event log; with the option omitted the
result carries no new field at all. First observations on the compressed arm:
`J_f` stays in band while `J_V/J_R/J_P/J_SCR` leave it at the islanding instant
(`J_R` peaks near 377 Hz/s, consistent with the recorded 94 % inertia loss).
Classified `ASSUMED_DIAGNOSTIC`; never citable for readiness.

**Provenance correction.** The claim that `docs/text/EECON49_[Nui].pdf` is
password-protected was false — it is not encrypted and page 5 is readable with
`pdftotext -layout`; the Read tool simply cannot render it. `Dv=1.50` is
`SOURCE_PRINTED`. That makes it a verified quotation, not a validated result:
EECON49 remains an unvalidated peer M.Sc. baseline, not authority.

Gates on this tree: 25/25 new tests (8 dual-model, 6 decoupling oracle, 6
end-to-end registration incl. the island oracle, 5 AGSI overlay), 163/163
targeted batch A (metadata/selector/inventory/baseline), 26/27 batch B — the one
failure is `TEST-2026-08-13-04`, reproduced identically on a pristine `e233b6c`
worktree and therefore pre-existing. Full regression omitted under the
`AGENTS.md` risk policy. Strongest oracles: with `D_t=0` the SG-online all-GFM
spectrum equals the baseline spectrum plus exactly four eigenvalues at `-w_D`
(remainder 4.1e-12) and the island margin equals the baseline's to `1.2e-13`.

NOT claimed: this does not resolve `TS-2026-08-13-03`. Measured on the paired
production chronology, the coupled baseline reaches `t=2.55/2.56` at
`dt=0.05/0.02` and fails there with `stepNewton`; **reclose is not reached by
either structure**, and no production report was regenerated. The damping knob
has no beneficial setting on this island (`D_t=0`), so the delivered
configuration is numerically equivalent to the coupled baseline.

## 2026-08-13 — EECON49 16-state reduction + synchronizer Pmin fix (commit 1)

`TD-2026-08-12-01` and `RECLOSE-2026-08-12-01` (RESOLVED). This commit
delivers the two gated bodies of work that share the same tested tree:

- **Command-delay reduction** — the source Eqs. (20)-(21) delay states
  (`Vd_del/Vq_del`) are removed by singular perturbation: the physical delay
  `T_d = 1.5/f_sw = 0.3 ms` (`f_sw = 5 kHz`, PROJECT_DERIVED owner-set) is
  >300x below the phasor step `dt = 0.10 s`, so the fast lag collapses onto
  `v_del = v_cmd`. Dual superset 20→16 states, standalone GFL/GFM 12→10,
  active GFL 11→9, active GFM 12→10. Equilibrium and retained dynamics
  unchanged; the spurious +1.29 @ 11.4 Hz all-GFL mode disappears
  (all-GFL SG-online now stable at −0.065). Secondary consequence: the
  retired lag had smoothed the fault-onset command jump, so the fault window
  needs `dt<=0.05` (sweep: 0.05/0.02/0.01/0.005 integrate; 0.10 stalls).
- **Synchronizer Pmin floor** — the breaker-open synchronizer command was
  floored at `Pmin=0`; when the SG leads the grid the angle term demands a
  negative command that clipped to 0, freezing the angle ~106 deg and timing
  the reclose out. Symmetric authority `Pmin=-Pmax` (PROJECT_DERIVED; the
  online governor keeps `Pmin=0`) restores the critically-damped capture
  loop. Oracle + unit test prove convergence from either sign.
- `docs/project/EECON49_GFL_GFM_SOURCE_CONTRACT.md` updated to the 16-state
  layout with the reduction derivation retained beside the source equations.

Gates on this tree: G-STATE 29/29, G-EQUIL/G-SSSA (all_gfl −0.065,
all_gfm −0.231), `test_sg_offline_synchronizer_retard` 3/3, plus the five
eecon49 state/model test files 21/21. Full repository regression omitted
under the risk policy (targeted producer/consumer/failure-path coverage).
Pre-droop baseline evidence for the follow-up parameter change is captured
read-only in `output/diagnostics/baseline_dv150.mat`.

FOLLOW-UP (not in this commit): islanded-VSG reclose reachability diagnosis
(defect record drafted on the follow-up branch of this work), and the
report re-validation it requires.

## 2026-08-12 — Switched-TS kernel runtime optimization (PERF-2026-08-11-01)

The switched-TS production run (`stability.run_hybrid_case` via
`generate_ieee14_switch_report_figures.m`) cost 2–3 h per 200-s horizon. Two
bit-identical changes landed:

- **S1** — the dual-mode IBR and SG devices rebuilt a constant event-context
  field name with `matlab.lang.makeValidName` on every residual evaluation
  (2,532,277 calls, ~38% of runtime); it is now computed once per device and
  threaded through the closures. `composite_dae` precomputes flat
  handle/index dispatch tables instead of copying a device struct per visit.
- **S2** — `+stability/ts_fd_column_groups.m` (new) derives, from
  `composite_dae`'s dispatch layout alone, which FD state columns may be
  perturbed together (device k's rows read only `x(xr_k)`; its injection hits
  only KCL row `bus_map(k)`; `Y*V` is x-independent). FD columns per Jacobian
  drop 82→41. `forward_fd` keeps the singleton path byte-for-byte, and a new
  `fd_structure_check` rebuilds both ways and requires exact equality.

**Wall clock: 200-s production run 2–3 h → 20.3 min** (grouped-vs-per-column
A/B measured 1.72× in-session; S1's share is the profiler's 38% makeValidName
attribution). Bit-identity is established by the compressed-arm `tol=0`
comparison (all arrays + 16 decision fields + 36 event-log checks), a
whole-arm `fd_structure_check` (2735 Jacobians, no mismatch; the derivation is
structural so it holds trajectory-wide), and 102/103 targeted tests (the one
failure is the pre-existing, unrelated `test_algebraic_residual_in_tol_range`,
TEST-2026-08-11-01).

Falsified and reverted (measured, not bit-identical): FD-step scaling
(iteration count is flat across `fd_eps` 1e-9…1e-3), an extrapolating
ordinary-step predictor (4083 vs 2725 iters, `max|dx|=280.7`), and
subdivision-hint hysteresis (3829 vs 2725 iters, `max|dx|=126`). The
structural reason both trajectory-changing ideas failed: a step subdivides
exactly when its Newton count hits `max_iter=50`, so any change to iteration
counts changes the accepted dyadic structure and hence the discretization.

The existing cache `output/diagnostics/engine_release_result.mat` is a stale
pre-fix diagnostic-variant artifact (mtime predates `d63f48d`/`b6e510f`;
written by `run_engine_release_tmp.m` with support supervision off, timeout 5,
subdiv 4) and is NOT a valid equivalence oracle. The full-production
clean-HEAD A/B was launched then stopped mid-run per the maintainer's decision
to accept the targeted-gate evidence.

Follow-up requested by the maintainer, not started: an **adaptive (or finer
fixed-dt) stepping** route to cut the stiff-window cost further. It changes the
published numbers, so it needs its own Plan-Mode cycle, a separate audit +
tests (AGENTS.md), correct interaction with exact event landing / AGSI dwell
timers / reclose sync windows, and full report re-validation.

Status update (2026-08-12): the adaptive follow-up is now **planned** (plan
`snug-wobbling-church.md`; ownership claimed in `TRACK_COORDINATION.md`):
opt-in `stepper='adaptive'` on `ts_simulate_ibr_hybrid`, default fixed stays
byte-identical, plus a diagnosis-first Phase-2 for the reclose timeout. Two
new production runs confirm the reclose outcome is config/gate-driven, not
dt-driven: 250 s at `dt=0.10` (~32 min) and 250 s at `dt=0.01` (27.5 min,
25011 samples) both converge to `t_end=250` and both give
`reclose=SYNC_TIMEOUT` at the CASE_DEFINED deadline (145+20=165 s). Earlier
SUCCESS-at-154.3 figures came from the stale diagnostic-variant cache and the
older code state, not from these runs.

Phase-1 landed (2026-08-12, commit `f9b710b`): opt-in `stepper='adaptive'` on
`ts_simulate_ibr_hybrid` is implemented and pushed. The default fixed path was
byte-identical and the discontinuity restart reinitializes
`dt_adaptive=dt_min` after each event (`ADAPT-2026-08-12-01`).

**Evidence correction (2026-08-13, `ADAPT-2026-08-13-02`):** the
`run_hybrid_case` pass-through loop transposed its cell list, so it forwarded
only `stepper`; caller overrides such as `dt_max`, tolerances,
`reject_limit`, and Rannacher options were silently dropped. The historical
`3402`-sample, `235`-reject, ~410-s and ~6--11x arm metrics therefore describe
the driver's defaults, not the requested override tuple, and are no longer
current acceptance evidence. Removing the transpose restores every option.
Fresh post-correction gates pass 11/11: fixed-path bit identity and validator
forwarding 4/4, analytic LTE 3/3, rollback/determinism/exact event landing 4/4.
A corrected all-four `reject_limit=12` diagnostic now genuinely crosses the
old lease but still fails after `line_trip` at a separate nonsmooth
DAE/Newton-conditioning wall; no equation, threshold, tolerance, or default
was changed. Phase-3 production/report re-validation remains blocked until
that chronology result is represented honestly.


## 2026-08-04 — IEEE14 160-s controller comparison

Starting commit `f7ff316`. The existing REGFM_B1/all-KCL 160-s trajectory was
retained as the legacy selector baseline, and two fresh runs were completed
with an authenticated nonlinear SG-trip candidate producer: exhaustive
ET-FCSPS and an in-house finite-set BO offline replay. Every candidate starts
from the same accepted event-left state, applies the same SG-trip transaction,
device-owned mode mapping, post-trip dispatch, full-KCL right-limit solve, and
0.25-s production prediction. The returned request is still revalidated and
committed only by the existing atomic transaction.

All three methods selected IBR1--IBR4 as GFM with IBR1 as the island reference,
reached 160 s, and produced exactly identical raw trajectories for AGSI++,
modes, P/Q, dq currents, frequency, angle, voltage, reference identity, and SG
signals. ET-FCSPS and BO used 8 predictions each because the authenticated
feasible universe contains only 8 candidates and the frozen BO budget is 8.
Consequently ET-FCSPS is preferable for this four-IBR case: it gives the
deterministic finite-set minimum without a surrogate, while BO demonstrates no
evaluation reduction or response improvement. BO remains
`ASSUMED_DIAGNOSTIC_OFFLINE_REPLAY`, not online production authority.

Fresh long-run times were 2182.918 s (ET-FCSPS) and 2223.825 s (BO); the 1.9%
difference is not a controller benefit because their dynamic trajectories are
identical and common candidate evidence was reused. Both runs have minimum
voltage 0.0600765 pu including the fault, online-frequency range
58.3238--63.5606 Hz, 8 switches, 508.700 aggregate GFM-seconds, reclose/handback
at 147.175 s, and maximum accepted residual `9.982 x 10^-9`. The historical
legacy cache runtime is not used as a speed benchmark.

Reports are separate from the earlier no-controller reports:
`docs/source/report_ieee14_controller_th.tex` (detailed) and
`docs/source/report_ieee14_controller_en.tex` (concise), with final PDFs
`output/pdf/ieee14_bus_with_controller_th.pdf` and
`output/pdf/ieee14_bus_with_controller_en.pdf`. Figures use raw production
signals; no noise, smoothing, clipping, or result tuning was applied. The
production adapter defect and correction are recorded in
`docs/project/defects/2026-08-04-et-fcs-production-trip-adapter.md`.

## 2026-08-04 — ET-FCSPS core and paired BO baseline

Starting commit `6eeb05c`. An additive, production-isolated ET-FCSPS decision core is now
implemented under `+stability/et_fcs_*.m`. It validates/fingerprints an accepted value-state,
enumerates 16 four-IBR mode vectors (and 32 SG-off mode-owner pairs), applies dwell/lockout and
full-network evidence gates, validates an isolated prediction horizon, computes unmodified
dimensionless metrics, ranks deterministically, emits a fingerprint-bound `COMMIT_REQUEST`, and
revalidates it with a pure commit guard. The core never mutates hybrid state; existing atomic
event handling remains the only commit authority. A project-owned authenticated trial-table
provider interface is included so production policy rejects arbitrary callbacks.

The frozen IEEE14 prototype policy is `PROJECT_DERIVED`: `T_p=0.25 s`, AGSI++-aligned engineering
normalizers, voltage/current-dominant soft weights, and explicit provenance. It is frozen before
closed-loop results and does not alter AGSI++, thresholds, SG/IBR equations, case limits, or event
chronology. An in-house Base-MATLAB finite-set BO replay baseline uses an RBF Gaussian process and
expected improvement after the identical hard screen. It is explicitly
`ASSUMED_DIAGNOSTIC_OFFLINE_REPLAY`, budgeted at 8 predictions, never feeds ET-FCSPS/production,
and reports paired winner, regret, and prediction-evaluation reduction. With a full budget it is
required to recover the exhaustive winner.

Fresh gates: ET-FCSPS/BO unit-oracle suite 20/20 PASS; existing authenticated selector table 44/44
PASS; existing SG-ON integration 12/12 PASS; Code Analyzer zero issues for all new files. The full
repository regression was intentionally omitted under the risk policy because the new core is
unreachable from the default production runtime. Reports and PDFs were not edited. Remaining
production-integration gate: create and verify a nonlinear accepted-state trial-table producer
using the existing full-KCL state mapping/short-horizon runtime, then connect the returned request
to the existing atomic event transaction under a separate shared-runtime ownership plan. See
`docs/project/plans/ET_FCSPS_IMPLEMENTATION_PLAN.md` and defect record
`docs/project/defects/2026-08-04-et-fcs-provider-name-dispatch.md`.

## 2026-08-04 — detailed ET-FCSPS technical report

Documentation-only follow-on to the 18-slide proposal deck. A 14-page Thai A4 report now
documents the proposed Event-Triggered Finite-Control-Set Predictive Supervisor in technical
detail: the exact current bounded AGSI++ equation and local hysteresis/dwell behaviour, accepted
system snapshot, 16 mode vectors and up to 32 mode-owner pairs, event/candidate generation,
full-KCL and reserve hard gates, isolated short-horizon prediction, normalized objective,
deterministic tie-break, reference-owner transaction, fail-closed fallback, pseudocode,
complexity, expected outcomes as falsifiable hypotheses, fair BO role comparison, proposed
interfaces, phased implementation, verification matrix, examples, and technical Q&A. The report
marks existing behaviour `VERIFIED CURRENT` and the supervisor `PROJECT-DERIVED PROPOSAL / NOT
YET IMPLEMENTED`; it does not claim closed-loop improvements. AVR, LLM/BO online authority,
SG/IBR equations, thresholds, case data, numerical results, and production runtime are unchanged.
XeLaTeX builds twice with no error, overfull, undefined-reference, or missing-character warning;
all 14 rendered pages were visually inspected. Source:
`docs/source/report_et_fcs_predictive_supervisor_th.tex`. Final artifact:
`output/pdf/report_et_fcs_predictive_supervisor_th.pdf`. Full regression was intentionally omitted
because the change is documentation-only; static/build/render checks cover the changed scope.

## 2026-08-04 — ET-FCS predictive-supervisor proposal deck

Documentation-only follow-on at starting commit `f78ea00`: an 18-slide Thai Beamer deck proposes
an event-triggered finite-control-set predictive supervisor above the existing AGSI++ local state
machines. It separates verified current behaviour from the unimplemented `PROJECT_DERIVED`
proposal, enumerates all 16 four-IBR mode vectors, defines global measurements, hard feasibility
gates, short-horizon cost/ranking, reference-owner transactions, fail-closed fallback, expected
benefits with measurable falsification metrics, phased implementation, and predeclared gates. The
workflow is rendered as a non-overlapping numbered two-row sequence. The BO comparison is role-specific and does
not claim universal superiority or closed-loop improvement before identical-contract testing. AVR,
LLM/BO online switching, SG/IBR equations, thresholds, cases, and production runtime are unchanged.
XeLaTeX builds 18 pages with no overfull/error warnings; every rendered slide was visually checked.
Source: `docs/source/presentation_fcs_predictive_supervisor_th.tex`. Final artifact:
`output/pdf/presentation_fcs_predictive_supervisor_th.pdf`.

## 2026-08-04 — final 160-s REGFM_B1/EMF6 chronology

Starting HEAD was `d3e448c` on `main`. The IEEE14 1-SG + 4-IBR report chronology now runs through
the project-owned REGFM_B1 all-KCL hybrid engine for the full 0--160 s sequence. The primary
`dt=0.0125 s` run completed in 4820.172442 s with maximum accepted-step residual
`9.98175508801e-9`, maximum attempted parent residual `3.19889806266e-4`, and subdivision depth 1.
The SG passed `Delta V=0.012765179 pu`, `Delta f=0.000779556 pu`, and
`Delta theta=3.401986499 deg` at the synchronism guard, closed at 147.175 s, and the coordinated
transaction returned IBR1--IBR4 from GFM to GFL. At 160 s, voltage spans
0.984909456--1.055630216 pu, `P_e,SG=1.048198640 pu`, `P_m,SG=1.046208344 pu`, and
`f_SG=60.046773383 Hz`; its last-2-s slope remains `+0.007391996 Hz/s`, so exact steady state is
not claimed.

The closure uses frozen `PROJECT_DERIVED` post-trip dispatch, an `ASSUMED_DIAGNOSTIC` deterministic
offline phase planner/voltage matcher, and a project-owned two-state Sauer--Pai Type-A primary
governor. There is no Bayesian-optimisation controller. A `dt=0.025 s` comparison completed in
1853.621603 s but closed at 148.175 s, so the report exposes 1.000-s event-time sensitivity and
does not claim time-step-independent controller validation. Seeded band-limited ripple is a
display-only dotted overlay; solid raw traces remain visible and all solver/AGSI/timer/mode data
remain untouched.

Targeted production/consumer/failure-path verification is 108/108 PASS. The full repository
regression was intentionally omitted under the risk policy. Thai and English reports compile to
12 and 8 pages with no overfull/error warnings; all pages were rendered and visually reviewed.
The English report contains no example-report author/title reference. See
`docs/project/defects/2026-08-04-agsi-bounded-publication-evidence.md` for the historical failed
route and the diagnostic evidence boundary.

## 2026-08-04 — EECON49 full-state switch/reclose evidence

Historical intermediate status; superseded by the final REGFM_B1/EMF6 section above.

The EECON49 IEEE14 report route now uses the project operational six-state EMF6 SG and
source-mapped 12-state GFL/GFM switching supersets. A positive-feedback current-error defect
(`i-iref`) was corrected to `iref-i`; dedicated equilibrium and fixed-bus eigenvalue gates pass.
The compressed ideal-SG trip/reclose gate remains an internal software test only. The exact 160-s
chronology remains `OPEN_MODEL_LIMITATION`: it stops fail-closed at 36.040 s after SG trip because
the source does not publish the DC-energy law, post-trip active-power redistribution, command
dynamics, or multi-GFM sharing contract. The reports now include only the accepted prefix as
explicitly labelled diagnostic evidence, with separate IBR1--IBR4 modes and IBR+SG electrical
traces. A seeded synthetic measurement overlay affects display only; raw data and decisions are
unchanged. No full 145-s recovery claim is made. Proportional-sharing and aggregate-swing
diagnostic candidates were falsified and removed; details are in
`docs/project/defects/2026-08-04-agsi-bounded-publication-evidence.md`.
Fresh targeted verification: 25/25 PASS. EN/TH XeLaTeX builds pass and all 7+10 rendered pages
were visually reviewed. Full regression intentionally omitted under the risk policy; the only
open gate is the advisor-approved long-duration dispatch/energy/control law required for 160 s.

Continued 2026-08-04 diagnostics also rejected direct Sakimoto-governor splicing, a critically
damped secondary integrator, immediate GRA override, proportional dispatch, command lags, and
single-GFM arbitration on the legacy report driver. The reduced-6 wrapper was additionally found to
have split limiter semantics (clamped KCL current versus unclamped swing power), so it is not a
valid workaround. The production REGFM_B1/all-KCL engine remains the correct integration base, but
its present event schedule orders fault before SG trip and lacks the required later load/line
events; a 40-s SG-cycle performance probe exceeded 600 s without a terminal result. Experimental
runtime edits were removed; details remain in the linked defect record.

## 2026-07-21 — Separate SMIB TDS current and power plots

The ideal-SMIB TDS diagnostic now preserves the perturbed algebraic-voltage
trajectory and reconstructs four independent time-domain products:
`i_d(t)`, `i_q(t)`, `P(t)`, and `Q(t)`. GFL-RMS10 uses its native inverter-base
current states. GFM-noPLL has no current state, so its current traces are
explicitly classified as a reporting-only transform of `I_inv` into the VSM
rotor frame. Active/reactive power uses the system-base generator convention
`S=V*conj(I_sys)` and is checked at every sample with a `1e-10` pu numerical
identity gate. SSSA load-sweep plots remain separate and retain load increase
(%) on the horizontal axis; only TDS plots use time (s).

Targeted verification only per user instruction: the new signal/plot suite
passed 3/3 and the existing GFM/GFL SMIB oracle suites passed 15/15. Full
repository regression was intentionally not run.

## 2026-07-21 — SSSA load-sweep plot correction and dq/P/Q diagnostics

Starting commit `3379688`. The plot adapter now preserves the raw 10-mode GFL
and 4-mode GFM spectra, constructs cumulative one-to-one tracked-mode indices,
and includes the base case in `[0 20 40 60 80]`. Plot A is the complete linear
real/imaginary eigenvalue plane with unconnected markers; a labelled
low-frequency detail is additional only. Plots G--J publish accepted-equilibrium
`i_d`, `i_q`, `P`, and `Q` as four separate figures for each load level. GFL
currents are native states;
GFM-no-PLL currents are a labelled VSM-frame diagnostic transform because that
4-state model has no current state. Every point verifies
`P+jQ = V*conj(I)` within `1e-10` pu before publishing.
When `sssa_plot_visible=true`, generated desktop figures remain open after the
sweep returns; only `Visible='off'` headless figures are closed automatically.

Targeted verification only, per explicit user instruction not to run the full
suite: `tests/test_sssa_load_sweep.m` 31/31 PASS after the visible-figure gate;
the earlier launcher-consumer rerun was 21/21 PASS. Full repository regression
intentionally omitted.

## 2026-07-21 — SSSA load sweep (single GFL/GFM to infinite bus, shunt load)

**Starting commits:** `smib_starting_commit=83390db`,
`smib_delivery_commit=efa9617`, `load_sweep_starting_commit=efa9617`.

### Scope

A configurable SSSA load-sweep product that scales a shunt load at constant
power factor and re-solves equilibrium + full-KCL SSSA at every load level.
User redirected scope from IEEE14-mixed+SG to a SINGLE IBR (GFL-RMS10 OR
GFM-no-PLL — two separate cases) connected to an ideal infinite bus through
`Z_line`, with a shunt load at the IBR terminal bus. Default percentages
`[0 20 40 60 80]`, user-adjustable. New schema `smib_loaded_ibr/1.0`; the
existing ideal `smib_verification/1.0` fixture stays bit-identical.

### Files added

- `+cases/case_ibr_smib_loaded_gfl_rms10.m`, `+cases/case_ibr_smib_loaded_gfm_no_pll.m`
- `+ibr/smib_loaded_equilibrium.m` (dedicated Newton equilibrium solver; 2-stage init)
- `+ibr/smib_loaded_sssa_oracle.m` (SSSA oracle with load current term)
- `+stability/+load_sweep/route_smib_ibr.m` (route adapter)
- `tests/test_sssa_load_sweep.m` (31 tests after plot/visibility corrections, GFL+GFM)
- `docs/project/defects/2026-07-21-gfl-rms10-smib-unstable-mode.md`

### Files modified

- `+stability/sssa_load_sweep.m` (route `smib_ibr`; default `[0 20 40 60 80]`)
- `+stability/sssa_load_sweep_point.m` (accept `smib_ibr`; smib snapshot copy)
- `+stability/sssa_load_sweep_scale_case.m` (smib_loaded_ibr branch)
- `+stability/+load_sweep/applicability.m`, `fingerprint.m` (smib_loaded_ibr)
- `+wizard/defaults_for_method.m`, `discover_cases.m`, `validate_request.m`, `dispatch_analysis.m`
- `tests/test_wizard_smib_cases.m` (loaded-IBR discovery)
- `docs/project/SSSA_LOAD_SWEEP_CONTRACT.md`, `docs/project/defects/INDEX.md`

### Dispatch policy (ASSUMED_DIAGNOSTIC)

IBR references (`P_ibr_base`, `Q_ibr_base` for GFL; `P_ibr_base`+`V_ref` for
GFM) are held FIXED at base. The infinite bus is the slack that absorbs the
incremental load through `Z_line`. Terminal voltage decreases monotonically
with load (GFL: 0.994→0.975; GFM: 0.986→0.976). Setting IBR reference = load
would make line flow = 0 and degenerate to an isolated IBR+load.

### Fresh targeted metrics (R2025a-equivalent)

- GFL loaded-IBR sweep `[0 20 40 60 80]`: all 5 points SUCCESS, 10 eigenvalues
  each, equilibrium residual <5e-12, mode matching available. `max_real≈3.4e5`
  (UNSTABLE — same magnitude as the existing ideal-SMIB oracle 3.37e5; this
  is a GFL-RMS10 device-model property, NOT a load-sweep defect; see defect
  record `SWEEP-2026-07-21-01`).
- GFM loaded-IBR sweep `[0 20 40 60 80]`: all 5 points SUCCESS, 4 eigenvalues
  each, `max_real≈-0.56` (ASYMPTOTICALLY STABLE), mode matching available.
- Ideal SMIB (`smib_verification/1.0`) + `sssa_load_sweep` rejected with
  `wizard:validate_request:loadSweepSmibIncompatible` /
  `LOAD_SWEEP_NOT_APPLICABLE_TO_IDEAL_SMIB`.
- Final targeted verification: `tests/test_sssa_load_sweep.m` 31/31 PASS;
  `tests/test_wizard_smib_cases.m` + `tests/test_wizard_dispatch.m` 21/21 PASS.

### Readiness

`SSSA_LOAD_SWEEP_PRODUCTION_READY = DIAGNOSTIC_ONLY`. Production device
f/current_injection closures are used unchanged; no external solver; no
device-equation edits. The load-growth/dispatch study policy is
`ASSUMED_DIAGNOSTIC` (IBR-refs-fixed + infinite-bus-slack). No exact stability
boundary, CPF nose point, or production operating-limit approval is claimed.
Stability is an outcome, not an acceptance gate.

### Full regression

Intentionally not run per the user's explicit instruction. The proportional
targeted producer and launcher-consumer suites above were used instead.

## 2026-07-20 — Separate GFL/GFM SMIB launcher cases

The IBR case dialog now lists `gfl_rms10_smib` and `gfm_no_pll_smib`
separately. Each route supports PF/equilibrium, SSSA, event-free TDS, or Full
Verification using the existing device closures and independent SMIB oracles.
It does not expose IEEE14 mode counts, SG-cycle comparison, or events.

Fresh R2025a targeted metrics: GFL order/roots 10/10, `||f||inf=2.79e-13`,
`||g||inf=1.11e-16`, Schur/direct error `6.68e-15`; its positive PLL pole is
retained and classified UNSTABLE. GFM no-PLL order/roots 4/4,
`||f||inf=6.52e-14`, `||g||inf=2.08e-16`, Schur/direct error `8.10e-11`,
ASYMPTOTICALLY STABLE, event-free TDS drift zero. Figures are written beneath
`output/figures/smib/{gfl_rms10,gfm_no_pll}/`. IEEE14 integration readiness is
unchanged.

## 2026-07-20 — GFM-VSG without PLL (SMIB-first, source-traced)

**Starting repository checkpoint:** `4d8b015` (`HEAD` one commit ahead of
`origin/main`; source-set separation commit). No shared file edited.

### Scope

New opt-in positive-sequence RMS GFM-VSG with NO PLL:
`+ibr/gfm_vsg_no_pll_model.m` (4-state `[delta_vsm, delta_omega_vsm, P_f,
Q_f]`, algebraic PNNL VFlag=0 Q-V droop, Thevenin behind pure `jX_L`).
Source contract: `docs/project/GFM_NO_PLL_SOURCE_CONTRACT.md`. Sourced study
parameters (Avila-Martinez 2025 + PNNL-35110): `H_GFM=5 s`, `D_GFM=20 pu`,
50 Hz, 100 MVA, `X_L=0.15 pu`, `m_q=0.05`, `T_P=T_Q=0.01 s`.

### Hard no-PLL contract (enforced)

No `delta_PLL`, no `xi_PLL`/`x_PLL_int`, no PLL PI gains, no PLL freeze, no
PLL-estimated frequency, no runtime `angle(V)` tracking. Runtime rotor angle
ONLY from `dot(delta_vsm)=omega_base*delta_omega_vsm`. Construction-time
`reject_unsupported_options` rejects dormant PLL/AVR/limiter fields.
Behavioral tests: angle-derivative structure, terminal-angle independence,
rigid-frame covariance.

### DUAL SMIB verification (GFL + GFM as separate cases)

Generic `+ibr/smib_tds_oracle.m` (`ASSUMED_DIAGNOSTIC_SMIB_TDS_ORACLE`,
NOT a production TS solver) added alongside the existing
`+ibr/smib_sssa_oracle.m`. Both are generic over either device via runtime
metadata (`dev.nx`/`dev.active_state_indices`); no hard-coded state count.

Targeted gates (all PASS):
- Device ABI: `tests/test_ibr_gfm_vsg_no_pll_model.m` — 15/15.
- GFM SMIB: `tests/test_ibr_gfm_vsg_no_pll_smib.m` — 6/6 (equilibrium, SSSA,
  FD convergence, event-free TDS, small-perturbation consistency, no-PLL
  behavior).
- GFL SMIB: `tests/test_ibr_smib_sssa_oracle.m` — 9/9 (GFL control case
  extended with SSSA/TDS tests).

GFM-noPLL SMIB metrics: `f0=6.5e-14`, `g0=2.1e-16`, `gy_rcond=0.92`,
`eigenvalue_count=4`, `schur_direct_err=8.1e-11`, `max_real_eig=-0.556`
(stable), 4 eigenvalues (1 complex conjugate swing pair + 2 real filter
modes). Event-free TDS drift=0; nonlinear-vs-linear error=2.9e-5 at
amp=1e-3; perturbation-halving ratio=1.4e-5.

GFL control case: `f0=2.8e-13`, `g0=1.1e-16`, `gy_rcond=0.83`,
`eigenvalue_count=10`, `schur_direct_err=6.7e-15`. NOTE: GFL has an
unstable PLL eigenvalue (real part ~3.4e5) at this operating point; the
linear SSSA response overflows and is reported honestly as `Inf`
(`linear_overflow=true`). Stability is an outcome, not a gate. This is
pre-existing GFL behavior, not a defect of the GFM-no-PLL work.

### Verification plots

`scripts/ibr/smib_verification_plots.m` generates PF/equilibrium + SSSA
figures for both devices (separate directories) plus a 2x2 summary.
Diagnostics: `output/diagnostics/smib/{gfl_rms10,gfm_no_pll}_smib.txt`.
Figures: `output/figures/smib/{gfl_rms10,gfm_no_pll}/` + summary PNG.

```
GFL_SMIB_PF_EQUILIBRIUM_PLOT = PASS
GFL_SMIB_SSSA_PLOT = PASS
GFM_NO_PLL_SMIB_PF_EQUILIBRIUM_PLOT = PASS
GFM_NO_PLL_SMIB_SSSA_PLOT = PASS
```

### Delivery status

```
GFL_SMIB_SSSA_ORACLE = PASS
LEGACY_REGFM_B1_WITH_PLL_SMIB_COMPARISON = PASS
GFM_NO_PLL_SOURCE_CONTRACT = PASS
GFM_NO_PLL_SMIB_EQUILIBRIUM = PASS
GFM_NO_PLL_SMIB_SSSA = PASS
GFM_NO_PLL_EVENT_FREE_TS = PASS
GFM_NO_PLL_IEEE14_INTEGRATION_READY = NOT_READY
```

IEEE14 integration NOT_READY: `device_contract_metadata` registration,
`build_mixed_resource_devices` factory case, and IEEE14 60 Hz mapping of
`H_GFM`/`D_GFM`/`X_L`/`m_q` remain `BLOCKED_CASE_MAPPING` pending separate
approval. Phase 5 shared composite SSSA/TS comparison deferred (standalone
oracle is the first-milestone gate). AVR/dynamic voltage PI, current
limiter, fault LVRT: OUT-OF-SCOPE future extensions.

## 2026-07-19 — Domain-preserving Newton globalization (RESOLVED_PENDING_FINAL_REGRESSION)

**Starting repository checkpoint:** `ea7150f` (`HEAD == origin/main`).
Defect record: `docs/project/defects/2026-07-19-domain-preserving-newton-globalization.md`.

### User-visible symptom

The IEEE14 Profile-B `1-SG + 4-IBR` full-analysis run with `Zf=0.1i` died at
`t=3.25 s` — before `sg_trip=5 s` and `sg_on=8 s` — so the SG reclose workflow
was never reached. `dt=0.01` surfaced `ts_simulate_ibr_hybrid:stepNewton`
(residual `4.983e-4`); `dt=0.005` surfaced
`ibr:gfl_rms10_model:lowVoltagePowerInversion` from a `composite_newton`
line-search trial iterate.

### Root cause

`composite_newton` propagated any exception from the line-search trial
evaluation `residual_fn(z_new)` to the caller. The classified RMS10 runtime
domain exception is raised when a *trial* iterate leaves the balanced-LVRT
voltage domain, not when the *accepted* iterate does. Accepted-trajectory
instrumentation proved accepted IBR terminal voltages stayed above `0.48735`
(overall `0.45766`), far above `V_div_min=0.1` — a Newton-globalization
defect, not a physical LVRT violation. The throw bypassed
`trial.converged=false`, so `advance_with_subdivision` never bisected.

### Correction (opt-in, backward-compatible; TS trial path only)

- `+stability/composite_newton.m`: optional 7th input `opt`, always-returned
  7th output `info`. `try/catch` wraps only `r_new=residual_fn(z_new)` in the
  alpha-halving loop. Exact-ID classifier on
  `ibr:gfl_rms10_model:lowVoltagePowerInversion`; every other exception
  rethrows. Classified trial: increment counter, record bounded diagnostics,
  never assign accepted state from the trial, halve alpha via the existing
  `1..2^-19` sequence, continue. Legacy acceptance rule unchanged. Current
  residual, Jacobian/FD, and final reporting remain uncaught.
- `+stability/ts_step_composite.m`: policy on only when
  `step_opt.domain_preserving_trials=true` (sole caller:
  `ts_simulate_ibr_hybrid`). Pure voltage-reconstruction diagnostic (no
  DAE/device callbacks); reports every below-threshold online GFL device;
  reads `V_div_min` from device provenance (no hard-coded threshold).
- `+stability/ts_simulate_ibr_hybrid.m`: publishes
  `domain_rejected_trials`/`subdivision_depth` in `res`/`meta`/`empty_result`;
  extends `advance_with_subdivision.stats`; preserves subdivision invariants
  and scheduled-event boundaries; composes domain-specific failure messages
  only when terminal-leaf classified evidence exists.
- `+stability/run_hybrid_case.m`: copies counters to the public result and
  `execution_summary` on every path.
- `+ibr/dual_mode_ibr_model.m`: forwards `gfl_runtime_min_voltage` from
  standalone GFL provenance (additive metadata only).

No equation, parameter, threshold, tolerance, event timing, accepted-state
rule, or PF/equilibrium/SSSA result changed. Equilibrium, SSSA, and
`ts_simulate_composite` remain default-off and bit-identical.

### Verification

- `tests/test_composite_newton_contract.m`: **9/9 PASS** (6 new + 3 legacy).
- `tests/test_ts_domain_preserving_newton.m`: **5/5 PASS** (new).
- Numerical invariance gates (expected values unchanged): 96 passed, 2
  pre-existing failures in the `mixed_equilibrium_solve` path (confirmed by
  `git stash` baseline; unrelated — that path calls `composite_newton` with
  the 6-arg default form).
- End-to-end `Zf=0.1i`:
  - `dt=0.005` (PASSES): prior `lowVoltagePowerInversion` trial throw is
    now a rejected trial; the domain-preserving catch engaged **197 times**
    and the run completed all 3005 accepted samples to `t=15 s`, reaching
    `sg_trip=5 s`, `sg_on=8 s`, terminating at `sg_reclose_timeout=13 s`.
    Accepted IBR voltages stayed `min|V|=0.48825 >= V_div_min`;
    `domain_rejected_trials=197`, `subdivision_depth=4` published; event
    landings exact.
  - `dt=0.01` (STILL FAILS — separate defect IBR-2026-07-20-01): fails at
    `t=3.25 s` with `domain_rejected_trials=0` and `subdivision_depth=4`.
    No classified domain throw occurred, so the domain-preserving catch was
    never engaged; subdivision exhausted without rescue. Non-smooth
    residual trajectory and near-singular `rcond~7e-7` indicate a
    non-domain Newton/Jacobian stall (limiter discontinuity or
    conditioning), not a trial-voltage violation. Out of scope for this
    fix; tracked as a follow-up defect.
- Evidence: `output/diagnostics/verify_domain_preserving_fix_20260720.log`
  and `output/diagnostics/diagnose_dt01_t325_20260720.log`.
- Full repository regression: **1185 passed / 10 failed / 7 incomplete**
  (MATLAB R2026a, tested tree `ea7150f` with the fix applied). All 10
  failures confirmed pre-existing by `git stash` baseline (fail identically
  without the fix): 2 in `mixed_equilibrium_solve` (6-arg default
  `composite_newton`), 2 in `test_ibr_launcher_settings_ui` (UI dialog),
  2 in `test_ibr_ts_plotting_absolute` (figure creation), 1 in
  `test_ibr_equilibrium_initializer` (SG device), 1 in
  `test_ieee14_1sg_4ibr_phaseB1`, 1 in `test_wizard_characterization`, 1
  in `test_wizard_ibr_subanalysis`, 1 in
  `test_ieee14_sg_reference_equilibrium`. The 7 incomplete are the
  pre-existing `test_pgaz_conversion_contract` assumption filters (external
  pgaz tool not installed). None are caused by the domain-preserving
  change.

### Scope and follow-up

The domain-throw defect is resolved and verified by targeted tests. The
dt=0.01 end-to-end gate is **not** met and is tracked as a separate
non-domain Newton/Jacobian stall (IBR-2026-07-20-01); a full root-cause
fix (domain-aware FD, Jacobian regularization, or limiter smoothing) is a
separate numerical-method contract requiring its own plan and approval.

SG governor/reclose controller is **out of scope** for this slice per the
user decision; it is diagnosed separately after the TS fault path is
correct. At `dt=0.005` the run reaches the reclose workflow and reports
`SYNC_TIMEOUT` — a physical synchronism outcome, not a numerical failure.
`IBR_PRODUCTION_INTEGRATION_READY` remains `NOT_READY`.

## 2026-07-19 — all-GFL SSSA initialization (RESOLVED)

**Starting repository checkpoint:** `4cbf413` (`HEAD == origin/main`).
Resolution evidence was generated on MATLAB R2026a. See defect record
`docs/project/defects/2026-07-19-sg-on-all-gfl-equilibrium.md`.

### User-visible symptom

In the compact IBR launcher, choosing `SSSA` with `Initial GFM count = 0` and
`Initial GFL count = 4` (SG1 remains online) failed closed before eigenanalysis:

```matlab
o = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
o.ibr_analysis = 'sssa';
o.initial_gfm_count = 0; o.initial_gfl_count = 4;
o.initial_gfm_indices = []; o.initial_reference_resource_index = [];
o.ibr_events = struct('enabled',false); o.plot_results = false;
r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',o);
```

Observed route: `wizard:dispatch_analysis:ibrEquilibrium` wrapping
`mixed_equilibrium_solve:noConverge`.  It is correct that no eigenvalue/state
table is printed without a converged equilibrium.  Do not fabricate a spectrum,
silently convert a GFL to GFM, relax a tolerance, or alter any source/case
parameter to make this pass.

### Correction

The helper `+stability/mixed_ibr_sg_on_gfl_initialize.m` is a
`PROJECT_DERIVED` **warm-start only** for the narrow SG-on/all-online-GFL
configuration. It changes each online GFL terminal bus from the inherited PF
PV label to the effective PQ semantics implied by its actual `P_ref,Q_ref`,
runs the existing in-house PF, and calls device-owned
`equilibrium_initialize`. `+stability/sg_composite_device.m` now exposes an
EMF6 stationary initializer based on the same stator equations and derives its
constant `[Tm,Efd]` seed through the existing RHS. `mixed_equilibrium_solve`
then still solves and verifies the unmodified full DAE/KCL system at the
unchanged `1e-8` gate.

The diagnosis found stationary device states but a load-inconsistent network
seed: SG RHS was `1.62e-15`, every GFL RHS was below `2e-11`, while a physical
KCL component reached `0.164 pu`. The complete KCL error matched the difference
between constant-power PF loads and the composite DAE's frozen
constant-admittance loads. The helper now represents the unchanged loads with
the exact admittances frozen by `composite_dae` before its mode-aware PF.

### Closure evidence

- independent EMF6 stationary oracle: exact SG-state agreement; angle residual
  `2.78e-17`;
- corrected initial/coupled residual `9.63e-12`, physical KCL `8.43e-12`;
- SSSA publishes all 45 active states and 45 finite roots; the physical result
  is honestly classified `UNSTABLE` under the unchanged equations;
- event-free 15 s TS accepts `1500/1500` steps;
- scoped producer/consumer/launcher regression: `45/45` passed;
- wizard UI smoke: `24/24` passed;
- full repository regression was started, then stopped by explicit user
  instruction that it was unnecessary; no full-suite PASS is claimed.

### Report and TS follow-up

The report generator and `docs/source/report_ieee14_ibr_pf_sssa_ts_en.tex`
now publish the 14 solved PF bus rows, all 20 branch sending-end flow/loss
rows, and the complete 45-root SG1 + four-GFL SSSA table. Every numerical
table and plot in this report uses SG1 plus IBR2/3/6/8 in GFL-RMS10 mode; no
GFM resource is active in the reported operating point. The detailed GFM
state order, ODEs, and controls remain in the report as documentation of the
reserved inactive dual-mode branch. Regenerated R2026a evidence records
all-GFL equilibrium residual `9.6265e-12`, physical KCL `8.4308e-12`, and
event-free TS completion at 15 s with `1500/1500` accepted steps. The final
17-page PDF is A4 portrait throughout; PF, line-flow, resource, SSSA, and TS
result pages were visually inspected from rasterized output.

The PF resource-reporting path also now consumes the committed mode selection.
Previously, its presentation-only fallback interpreted an explicit empty
`initial_gfm_indices=[]` as missing and printed IBR2 as GFM despite the solved
all-GFL request. The numerical PF was unaffected; the corrected report prints
SG1 plus four GFL-RMS10 resources and active order 45.

The report operating-point tables were subsequently unified. Bus voltages,
bus generation/load/net injection, all 20 branch flows, and device injections
are now reconstructed from the same accepted SG1 plus four-GFL equilibrium
used by SSSA and TS. The source REF/PV/PQ PF is retained only as the frozen
constant-admittance load anchor and is not published beside the equilibrium
tables. The report producer independently checks
`Sgen + Sshunt - Sload - Sbranch_loss`; the regenerated balance norm is
`1.8610e-11 pu`. Table 5 bus generation equals the aggregation of Table 7
device injections by bus.

The user-observed TS failure at `20260719_082442` is not the normal-operation
route: the configured bus-4 fault reaches `fault_on` at 3 s and produces
`|V|=0.039238 pu`, below the unchanged GFL-RMS10
`V_div_min=0.1 pu` balanced-LVRT domain. Runtime therefore correctly rejects
the right-limit transaction with
`ibr:gfl_rms10_model:lowVoltagePowerInversion`. The compact launcher already
labels this choice `Fault only - fail-closed diagnostic (RMS10 LVRT not
ready)` and defaults its event-choice dialog to `No events`. Do not remove the
voltage-domain gate or reinterpret this configured-fault result as an
event-free TS regression.

### Scope already delivered and not to regress

- IBR menu separates `Power Flow`, `SSSA`, `Time-Domain Simulation (TS)`, and
  `Full Analysis`; do not collapse them again.
- GFM/GFL count UI is intended to be available for PF/SSSA/TS, with GFL being
  the complement of selected online IBRs and reference index automatic.
- The report is `docs/source/report_ieee14_ibr_pf_sssa_ts_en.tex`; figures are
  MATLAB-generated vector PDFs from
  `scripts/reporting/render_ieee14_ibr_pf_sssa_ts_matlab_figures.m`.
- Existing Profile B remains SG1 + IBR2 GFM13 + IBR3/6/8 GFL-RMS10, 48 active
  states. Its existing results are not evidence for the new all-GFL route.

## 2026-07-19 — IBR PF/SSSA/TS/Full launcher products

### SG trip-return PF/SSSA comparisons

The compact IBR submenu now also offers additive `Power Flow Comparison` and
`SSSA Comparison` products. Each solves and indexes three stationary points:
`PRE_TRIP`, `SG_TRIPPED`, and `SG_RETURNED`. They publish resource/device/bus
indices, online/mode status, active-state mappings, P/Q/terminal-voltage tables,
and a grouped P/Q/V figure. SSSA spectra are complete per point and explicitly
`NOT_MODE_MATCHED` across operating points. This is distinct from Full Analysis:
it is an operating-point comparison, not a fault/reclose trajectory or physical
acceptance claim.

The RMS10 registered dual-device type was also added to the explicit allowlist
in `mixed_ibr_reduced_initialize`; unknown device types remain fail-closed. No
ODE, state order, parameter, limiter, Jacobian, or numerical tolerance changed.
Targeted evidence on MATLAB R2025a: 14/14 comparison and RMS10 SG-off
equilibrium tests passed. Active dimensions were 48/52/57 and equilibrium KCL
infinity norms were respectively 5.218e-15, 4.582e-11, and 1.465e-14. The SSSA
classification was UNSTABLE at all three points and is retained as a physical
result rather than tuned away. Final broader regression evidence is recorded in
the delivery commit/test record.

The compact `solve_case` flow now selects IBR, the IEEE14 1-SG + 4-IBR case,
then Power Flow / SSSA / Time-Domain Simulation (TS) / Full Analysis. The
interactive IBR launcher defaults to RMS10 Profile B (IBR2 GFM13,
IBR3/6/8 GFL-RMS10), which produces 48 active states from a 98-state fixed
inventory. The GFM/GFL count remains editable; the UI reconciles count,
explicit indices, complementary GFL count, and reference index. Full Analysis
returns separate `pf`, `equilibrium`, `sssa`, and `ts` products, with SSSA and
TS sharing the same equilibrium.  Detailed PF reports, SG+IBR state/eigenvalue
tables with descriptions, and four TS plot products are enabled.  The legacy
WECC code remains only for explicit regression consumers and is not offered by
the compact launcher UI. RMS10 LVRT remains fail-closed/not ready.

PF reporting converts IEEE14 voltage using the in-repository 69-kV base, uses
a linear mismatch plot, and prints per-resource P/Q in pu and MW/MVAr with a
reconciliation against total generation. Targeted evidence: 22/22
numerical/report/plot/SSSA tests, 60/60 launcher tests before the final AUTO
field adjustment, and 14/14 final AUTO UI + IBR sub-analysis tests passed.
Full regression was intentionally not run at the user's request.

## IBR dynamic-equation contract — Phases 0A/1/2/3 (2026-07-18)

**Status:** Phases 0A (source verdict), 1 (Section H core mappings), 2
(standalone modal helper), and 3 (Section H reporting) complete and pushed
to `main` (`0cb65e9`). Phases 0B, 4, 5 remain BLOCKED.
**Branch:** `main`
**Tested commit:** `0cb65e9` (HEAD == origin/main after fast-forward push)

Source-traceable dynamic-equation and state-order contract for GFM-VSG
(REGFM_B1, 13-state) + GFL-PLL (WECC REGC_A/REEC_A, 7-state, PLL-less).
The primary paper (Fu et al. IEEE JESTIE 2024) supports LINEAR_SSSA only;
no nonlinear GFL source is approved. GFL PLL participation is reported as
`NOT APPLICABLE TO CURRENT PRODUCTION MODEL` until Phase 0B approves an
explicit-state GFL source.

### What was delivered (commits 5e7db6d..0cb65e9)

1. **Phase 0A** (`5e7db6d`): frozen source verdict + equation register +
   13/7-state tables + Section H contract + Phase 0B source checklist
   (`docs/project/IEEE14_IBR_DYNAMIC_EQUATION_CONTRACT.md`).

2. **Phase 1** (`d4d1c7d`): IBR-owned metadata registry
   (`+ibr/device_contract_metadata.m`) + state/input inventory snapshot
   (`+ibr/state_inventory_snapshot.m`). Strict device_type/nx/state_names
   registry; GFM 13-state (page+eq citations from NREL/TP-5D00-90260),
   GFL 7-state (WECC block-level provenance), dual 20-state composed.

3. **Phase 2** (`aba4ba2`): standalone no-inv modal helper
   (`+stability/modal_analysis.m`). Read-only consumer of `sssa.A` and
   separately `sssa.physical_A`. Left via `eig(A','vector')`, biorthogonal
   U/conj(alpha), signed participation, deterministic sort + conjugate
   pairs + cluster projectors + physical lift (map-dependent oblique
   attribution, NOT canonical eigenvectors of A). Does NOT modify
   `composite_sssa_model.m` or `Ared` construction.

4. **Phase 3** (`0cb65e9`): Section H report assembler
   (`+ibr/section_h_report.m`) + text renderer
   (`+ibr/render_section_h_report.m`). 12 mandatory log sections + full/
   physical spectrum tables + participation table + TS tables + execution
   counters + convergence summary + `analysis_fingerprint` (canonical
   serialization + SHA-256). Pure read-only consumer: no eig/inv/pinv/
   modal_analysis/state_inventory_snapshot/solver calls. Two shape-guard
   tests added to prevent the cell-array collapse regression.

5. **Cell-index bug fixes** (`0cb65e9`): five sites in
   `+stability/modal_analysis.m` (lines 334, 335, 497, 512, 656) used
   parentheses indexing on cell arrays, returning a cell instead of the
   string content; `strcmp` then mis-compared on ill-conditioned/clustered
   paths. Fixed to curly-brace indexing. Defect record:
   `docs/project/defects/2026-07-18-cell-array-collapse-and-indexing.md`.

### Verification (Phase 3 delivery, commit 80568cf)

- Phase 3 targeted (`test_ibr_section_h_report.m`): **23/23 PASS**
  (20 base + 3 hardening shape guards).
- Phase 2 targeted (`test_modal_analysis.m`): **24/24 PASS**.
- Phase 1+2+3 targeted: **77/77 PASS**.
- Full regression: **1024 passed / 0 failed / 4 incomplete** (the 4
  incomplete are pre-existing `test_pgaz_conversion_contract` assumption
  filters on the external pgaz validation tool, unrelated to this change).
- MATLAB R2026a Update 3 (glnxa64); `matlab -batch` with `pf_init_paths`.

### Phase 3 hardening (commit 80568cf)

Advisor review of the Phase 3 delivery identified four follow-up items;
three were applied in-scope (no contract change), one was deferred to a
new Phase 3.1 task:

1. `canonical_serialize` now errors fail-closed on unsupported types
   (`ibr:section_h_report:unsupportedType`) instead of returning an `'X'`
   placeholder — a fingerprint must not silently drop a value.
2. Fingerprint claims reduced to "change-detection" (not "durable" /
   "MATLAB-version-independent"); `mat2str`/`num2str` formatting can vary
   across MATLAB releases. Stability is asserted only for identical input
   on the same MATLAB version (`test_fingerprint_stable_identical_input`).
3. Three new shape-guard tests: unsupported-type fail-closed,
   `full_state_eigenvalues.rows` is a cell array, `participation.rows` is a
   cell array (regression guards for the `struct()` collapse bug).
4. Defect record corrected: the `struct()` collapse explanation now
   describes comma-separated-list semantics precisely.

Deferred to Phase 3.1 (task #8, separate plan + approval required):
NaN/Inf/−0 representation policy, nested struct depth/cycle handling,
cross-MATLAB-version canonicalization audit.

### Scope and ownership

- Track B owned: `+ibr/**`, `tests/test_ibr_*.m`, `docs/ibr/**`,
  `scripts/ibr/**`.
- Single-owner shared (new file, not an edit to existing shared kernel):
  `+stability/modal_analysis.m` (created in Phase 2 `aba4ba2`; cell-index
  fixes in `0cb65e9`). No edit to `composite_sssa_model.m`, `composite_dae.m`,
  `solve_case.m`, `run_pf.m`, `run_ssa.m`, `run_ts.m`, `pf_init_paths.m`,
  TS kernel/driver, topology/event, or launcher files.
- No production numerical equation, Ared, ABI, schema, or runtime contract
  changed. `IBR_PRODUCTION_INTEGRATION_READY` remains `NOT_READY`.

### GFL-RMS10 reopening + Phases 4/5/6 (2026-07-18/19)

**Status:** Phase 0B reopened as a user-authorized PROJECT_DERIVED RMS10
composite (NOT a complete source-defined GFL). Phases 4/5/6 complete for the
normal-operation slice. Tested commits `7ce08ae` → `5373921`.

The user supplied three textbooks (Yazdani 2010, Teodorescu 2011, Bacha 2014)
that close the nonlinear PLL/current-controller/L-filter core (6 of 10 GFL
states SOURCE_DEFINED). The remaining 4 states (P/Q filters, outer-loop
integrators) and all limiters/anti-windup/LV semantics are APPROVED_PROJECT_DERIVED.
Full provenance: `docs/project/IEEE14_IBR_GFL_RMS10_PROVENANCE.md`;
frozen numerical parameter manifest:
`docs/project/IEEE14_IBR_GFL_RMS10_PARAMETER_MANIFEST.md`.

Final source verdict (honest):
- `SOURCE_DEFINED_NONLINEAR_CORE_CLOSED = YES`
- `FULL_SOURCE_DEFINED_GFL_MODEL = NO`
- `APPROVED_PROJECT_DERIVED_RMS10_SLICE = YES`
- `NUMERICAL_PARAMETER_PROFILE_FROZEN = YES`

What was delivered (commits 7ce08ae → 5373921):

1. **Phase 0** (`7ce08ae`): parameter manifest + provenance doc frozen BEFORE
   production code (stop condition satisfied).
2. **Phase 1** (`7ce08ae`): `+ibr/gfl_rms10_model.m` — 10-state device mirroring
   the WECC/REGFM_B1 generic ABI. Equilibrium verified machine-zero residual
   (~1e-15). LV fail-closed (no PLL freeze). Anti-windup one-sided conditional
   hold. 25 device tests PASS.
3. **Phase 2** (`7ce08ae`): `tests/test_ibr_gfl_rms10_model.m` — 25 falsification
   tests (ABI, equilibrium, kappa, dq/sign, current-plant oracle, PLL ODE,
   P/Q filters, current-priority limit, anti-windup hold/release, vector clamp,
   LV fail-closed, Jacobian FD, no-external-solver grep, fail-closed IDs).
4. **Phase 3** (`dd3af91`): opt-in routing via `params.gfl_family`
   (construction-time). `gfl_model.m` dispatcher; `dual_mode_ibr_model.m`
   23-state layout with distinct `device_type='ibr_dual_mode_rms10'`;
   `device_contract_metadata.m` registers `ibr_gfl_rms10` (10/2) +
   `ibr_dual_mode_rms10` (23-state); `build_ieee14_sg_ibr_devices.m` forwards
   `device_modes(k).gfl_family`; `section_h_report.m` derives GFL-PLL
   applicability from state inventory (APPLICABLE_EXPLICIT_GFL_PLL_STATES when
   an active RMS10 delta_PLL/xi_PLL row is present). Legacy ibr_dual_mode
   (20-state) unchanged (G15); REGFM_B1 GFM unchanged (G16).
5. **Phase 3 tests + Phase 4** (`5373921`): routing/metadata/dual/sssa/ts
   integration tests. Profile B (SG1 + GFM_IBR2 + 3xRMS10) equilibrium
   converges (kcl=2.3e-14); full-KCL SSSA via shared `composite_sssa_model`
   (48 active states, no hand-built A); event-free TS no-drift via shared
   `ts_simulate_composite`; disturbance response finite; limiter transaction
   fail-closed. 133 targeted tests PASS.
6. **m_max fix** (`5373921`): default 1.10 → 1.30. At IEEE14 bus 8 (|V|=1.09)
   the v_t feedforward reached 1.099 > V_t_max=1.10, triggering the vector
   clamp and breaking equilibrium. 30% overmodulation headroom keeps the
   clamp inactive across the normal-operation domain.

Generic-ABI integration contract (user-mandated, FROZEN): GFL-RMS10 plugs
into the existing composite-device ABI used by SG EMF6 and REGFM_B1. No
GFL-specific PF/equilibrium/SSSA-A/TS solvers. PF→equilibrium→SSSA→TS reuse
the shared project-owned kernels. Shared files (composite_dae, composite_sssa,
ts_simulate_*) remain unchanged.

### Remaining (NOT blocked)

- **Phase 5 reporting**: this handoff + decision ledger D18 + frozen contract +
  source matrix + Phase 0B audit reopen + Thai TeX report (GFL-RMS10 as
  primary proposed model). In progress.
- **Phase 6**: full regression `pf_init_paths; r=runtests('tests','IncludeSubfolders',true)`
  once on the final tree (required: changes IBR equations + composite DAE
  routing + equilibrium + SSSA + TS). Then commit + fast-forward push.
- **Phase 3.1** (task #8, deferred): canonical serialization hardening.
- **LVRT/fault TS** is OUT OF SCOPE for this slice. A future LVRT route
  requires a separate authoritative source + approved contract.
  `GFL_RMS10_LOW_VOLTAGE_RIDE_THROUGH_READY` remains false.

### Historical Phase 0B BLOCKED record (superseded above)

The original Phase 0B bounded search (2026-07-18) ended SOURCE_GAP_BLOCKED:
no complete source-defined GFL was found. That remains true. The GFL-RMS10
slice reopens Phase 0B by explicit user authorization of a PROJECT_DERIVED
composite, NOT by discovery of a complete source. Full audit evidence stays in
`docs/project/IEEE14_IBR_PHASE0B_SOURCE_AUDIT.md` (now annotated as reopened
by the PROJECT_DERIVED path).

## Mission C — Characterization handoff (2026-07-17)

**Status:** Characterization phase complete (read-only). Controller-enabled run NOT yet performed.
**Branch:** `main`
**Tested commit:** pending full regression (targeted 18/18 GREEN on `d213d9c`)

Mission C aim: physical SG resync + IEEE14 demo close. Phase 0 audit found no sourced
IEEE14 governor/synchronizer/AVR → binding STOP for physical acceptance.
Proceeding with diagnostic workflow validation (opt-in, ASSUMED_DIAGNOSTIC, NOT VALIDATED).

### What was delivered in this commit

1. **Per-sample resync diagnostics** (`ts_simulate_ibr_hybrid.m:269-328`):
   Pure read-only measurement hook records synchronism state every accepted sample
   during offline coast. `res.resync_diagnostics` struct array with guard margins
   (dV, df, dtheta, signed_margin, limiting_gate), SG state (omega, delta,
   V_open_circuit, Tm, Te, Efd), bus voltage. Zero integration-logic dependency —
   disabled route bit-identical (all 16 prior tests GREEN).

2. **2 RED characterization tests** (`test_ieee14_ibr_sg_reclose_workflow.m:63-106`):
   Record hook fires, no sample eligible with strict guard, df > df_max throughout
   (Tm-frozen coast falsifies natural-reclose hypothesis), signed_margin<0 everywhere.
   18/18 GREEN including all 16 prior tests.

3. **Diagnostic parameter manifest** (`docs/project/diagnostic_synchronizer_parameter_manifest.md`):
   SG plant (Kodsi, EMF6, τ=5.148s). Governor P-only (Kp=20 from 1/R_D, Ki=0) —
   no integral/anti-windup. Exciter: fixed Efd default; Padiyar AVR deferred.
   All gains = ASSUMED_DIAGNOSTIC. Status: REQUIRES_REVISION per advisor.

### Characterization findings (physical)

| Gate | Tm FROZEN | Tm=0 Diagnostic | Verdict |
|---|---|---|---|
| A. Frequency | df>0.001 always FAIL | df<0.001 always PASS | Runback solves df |
| B. Voltage | dV≈0.064>0.05 FAIL | UNKNOWN (may converge) | ~0.014pu excess |
| C. Phase | dθ cycles 0.2s FAIL | dwell feasible at ω<0.00053 (~25s) | ~25s asymptotic |
| D. Base defects | NONE confirmed | NONE | V_open verified real |

- ω₀≈0.073 at sg_on=8.0s (3s coast), ω→∞≈0.164 asymptotically
- 0/501 samples all three margins >0 over 15s → SYNC_TIMEOUT is PHYSICAL
- Analytical ω verified to 1e-8 for Tm frozen; τ=5.148s confirmed
- dV≈0.064 NOT 18 pu (earlier margin/deg misinterpretation fixed)
- dθ = binding gate; Tm=0 alone needs ~25s for ω to decay below dwell threshold
  (ω·377·0.5 < 10° → ω<0.00053)

### Missing contracts

1. **Diagnostic timeout profile:** ~30s (τ·ln(ω₀/dwell_ω) + dwell + margin).
   Public sync_timeout=5s unchanged.
2. **Phase-synchronizer contract:** Tm=0 ω decay is asymptotic — active slip
   control or braking could accelerate phase capture.
3. **AVR contract:** Required only if fixed Efd does not converge dV below 0.05pu.

### Next steps

1. **Do NOT run controller-enabled reclose** before manifest revision.
2. **Tm=0 passive characterization run:** verify dV trajectory with fixed Efd
   over ~30s horizon, confirm ω matches analytical oracle, record dθ dwell stats.
3. If dV converges <0.05: no AVR. If not: integrate Padiyar AVR (diagnostic limits).
4. If ω/timing unacceptable: active slip control or separate opt-in timeout.
5. File allowlist: `ts_simulate_ibr_hybrid.m` + new controller files + tests.
   `sg_composite_device.m` is **read-only** (controller external to EMF6).
6. Before mutation: read `AGENTS.md`, `TRACK_COORDINATION.md`, this handoff,
   plan at `docs/project/plans/`, manifest.

### Flags

- `IBR_PRODUCTION_INTEGRATION_READY = NOT_READY`
- No VALIDATED milestone from diagnostic route
- All diagnostic = ASSUMED_DIAGNOSTIC / NOT PHYSICAL ACCEPTANCE

## Revision 5 — Corrective closure (2026-07-17)

The earlier "936 passed / 8 failed / full regression passed / zero new
regressions" claim was WRONG. `git stash` does NOT revert committed source, so
the 8 `test_ieee14_ibr_ts_event_runner` failures at `7c986f4` were incomplete
schema migration, not pre-existing. Revision 5 closes that gap and the remaining
Phase 4b/5 contracts:

- **Event-runner migration.** Two pinned authenticated tables in `setupOnce`;
  8 physical-intent tests migrated to `event_run_with_table`; 2 new missing-table
  tests assert `stability:gfm_selection:missingTable`. 14/14 GREEN.
- **Validator latent bugs fixed.** `fidi` nested-handle unreachable from
  `manual_branch`; early-return paths did not assign outputs. Both fixed; all
  failure IDs use string concatenation consistently.
- **Production `cand` field bug fixed.** `ts_simulate_ibr_hybrid.m:610` now
  reads the committed selection from the validator output with a schedule-literal
  fallback.
- **Real timers (Step 3).** `assemble_runtime_context` reads `hold_timers`/
  `lockouts` from `hybrid_state`; malformed values fail closed.
- **Validator parity (Step 4).** Identity check for ALL candidates + sanitized-
  key uniqueness; manual branch gains identity + hold/lockout checks;
  `runtime_n_mode_changes` reflects the post-sort winner.
- **Authenticated SG_ON routing (Step 5).** `reselection_transaction` consumes
  an authenticated candidate via `authenticate_sg_on_candidate`; `compute_tdown`
  derives `T_down` from the authenticated candidate's omega.
- **`N_exhaustive_max=4` guard (Step 6).** `ibr_selector_table.m` fails closed
  with `stability:gfm_selection:excessiveUniverse` before enumeration.
- **Unpinned automatic integration (Step 8).** New
  `test_unpinned_automatic_sg_off_integration` asserts the runtime-selected
  candidate + provenance come from the table; SG_ON reports zero feasible.

### Verification (Revision 5)

Targeted gates on the edited tree: selector unit 44/44, event runner 14/14,
reclose workflow 16/16, SG_ON integration 12/12 — **86/86 GREEN, 0 failed,
0 incomplete**. Full regression pending (run once on the final tree per
AGENTS.md risk policy).

### Limitations (Revision 5)

- Automatic selection (unpinned) picks candidate `[5]` (highest margin) on
  IEEE14, which can make post-trip dynamics fail to converge (stepNewton). This
  is an honest outcome of the frozen margin-based ranking policy, not a bug;
  the demo/comparison/solve_case defaults retain the known-stable manual
  `[2 3 4 5]` tuple. A ranking-policy review (margin vs dynamics stability) is
  a separate workstream.
- `IBR_PRODUCTION_INTEGRATION_READY = NOT_READY` (unchanged).



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
fail-closed at `recloseTransaction` is correct behavior. Observed at the
failed close: nonzero SG speed deviation, relaxed guard acceptance, and a
rejected right-limit KCL. Inferred from the EMF6 breaker/current-injection
equations: closing at that state introduces an incompatible stator-current
injection. **The current jump was not directly measured** (the transaction
was rejected, so no committed post-close state exists to measure against; the
diagnostic records rotor state, bus voltage, guard margins, and the right-limit
residual, but never computes stator current). This is NOT a defect. The
transaction-level equilibrium-consistent reclose mechanics are proven
separately in `test_ieee14_ibr_sg_reclose_workflow` (`right_kcl_norm < 1e-6`).

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
(`ts_simulate_ibr_hybrid:recloseTransaction`). Observed at the failed close:
nonzero SG speed deviation, relaxed guard acceptance, and rejected KCL.
Inferred from the EMF6 breaker/current-injection equations: closing at that
state introduces an incompatible stator-current injection. **The current jump
was not directly measured.** This fail-closed behavior is preserved and is NOT
a defect. The transaction-level equilibrium-consistent reclose mechanics
(breaker close → right-limit KCL → commit → reference handback) are proven
separately in
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
0 incomplete / 0 errored** (R2026a Update 3, `matlab -nodesktop -nosplash
-batch`, cache-clear sequence applied). The final numerical full-tree gate
was run on tested source SHA-A `df5f97d`: **922 passed / 0 failed / 0 incomplete
/ 0 errored**. Final delivery SHA-B `f928fd8` contains documentation-only
changes. This 922 is distinct from the targeted gates below:

- **V5 validation-closure targeted regression**: **107/0/0** across 9 targeted
  files (the final validation-closure gate, distinct from the full regression).
- **C0–C7 corrective-pass targeted regression**: **80/0/0** across 7 targeted
  files (`test_ieee14_ibr_switching_comparison`,
  `test_ieee14_ibr_sg_on_integration`, `test_ieee14_ibr_sg_reclose_workflow`,
  `test_ieee14_ibr_ts_event_runner`, `test_ieee14_1sg_4ibr_phaseEF`,
  `test_ibr_ts_plotting_absolute`, `test_no_external_solver_dependency`).

All four previously documented baseline incomplete tests are resolved.

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

## Analysis Wizard UI (2026-07-19)

**Status:** Wizard backend delivered; compact legacy-style dialogs restored as
the default interactive surface after desktop review. Full regression was
stopped by user request; focused verification is recorded below.
**Branch:** `main`
**Doc:** `docs/project/IEEE14_ANALYSIS_WIZARD.md`

`solve_case.m` refactored into a thin wrapper (Extract + delegate). The
wizard UI (base-MATLAB `figure`/`uipanel`/`uicontrol`, NOT uifigure) and
the programmatic path both route through the SINGLE shared dispatcher
`wizard.dispatch_analysis` (G4). Pure logic lives in `+wizard/*`
(headless-testable); page/render builders live in nested packages
`+wizard/+pages/*`, `+wizard/+render/*`.

Frozen contracts preserved across the refactor (characterization tests
18/18 green before AND after):
- programmatic ABI (name-value `analysis`/`case`/`options`);
- stable analysis IDs (`pf`/`sssa`/`ts`/`ibr`; no `ibr_ts`);
- per-analysis result schemas; launcher sub-struct; execution_summary;
- error IDs (`solve_case:analysis`, `solve_case:case` preserved, not relaxed
  to `wizard:*`);
- log-file tokens (`PF VERIFICATION`, `STATUS: COMPLETE`, etc.);
- partial invocation: partially specified calls open the wizard with
  selections pre-populated and NEVER auto-execute (raise
  `MATLAB:hg:NonInteractiveFunctionSupport` in batch, matching the old
  `listdlg` behavior);
- events=false reaches the production IBR runtime as an ACTUALLY empty
  schedule (distinct slim 17-field schema vs 58-field events-on; empty
  `events`; all-zero per-sample `transaction_id`; zero `event_transactions`).

IBR settings dialog moved verbatim from `solve_case.m` into
`+wizard/ibr_settings_dialog.m` (base-MATLAB three-column contract
unchanged; `test_ibr_launcher_settings_ui.m` contract checks green, source
location updated). `run_ts.m` NOT edited (correction #7).

Generic 12-section view model (`wizard.adapt_result`) for ALL analyses;
IBR Section H producer reused ONLY through the explicit
`wizard.adapt_ibr_section_h` adapter (PF/SSSA/TS return `not_applicable`).

### Tests (headless)

- `tests/test_wizard_characterization.m` — 18 (frozen ABI, before/after refactor)
- `tests/test_wizard_pure_layer.m` — 29 (registry/discover/defaults/build/validate)
- `tests/test_wizard_dispatch.m` — 15 (dispatch + adapt_result + config_io)
- `tests/test_wizard_section_h_adapter.m` — 6 (Section H adapter)
- `tests/test_wizard_ui_smoke.m` — 21 (real hidden-figure renderer and navigation)
- existing launcher tests (`test_ibr_launcher_settings_ui.m`,
  `test_ibr_launcher_configuration_logging.m`, `test_solve_case_launcher.m`)
  — 16 green

The default `solve_case()` path is now `wizard.legacy_show`: compact analysis
and case list dialogs followed by method-specific editable settings. It uses
the same `wizard.build_request` / `validate_request` / `dispatch_analysis`
backend as programmatic calls. The six-page UI is non-default. Desktop defects
in its footer, initial-case commit, Events navigation, and blank Results page
were corrected as fallback hardening (`UI-2026-07-19-01`).

Focused final-tree evidence: legacy backend Code Analyzer 0 issues; launcher
and dispatcher tests 31/31; hidden-figure wizard smoke 21/21; broader focused
wizard/launcher suite 66/66. No failed or incomplete targeted tests. No
numerical equation, parameter, tolerance, solver, or result schema changed.
Full repository regression was intentionally not rerun by user request.

## 2026-08-05 — in-domain reference-PCC stress comparison

The second frozen stress case (`reference_fault_recovery_stress`) completed all
three 0--160 s arms. It uses the bus-2 fault from 19.25--19.50 s and SG-trip
request at 20.0125 s, leaving the declared post-clear recovery interval before
the trip. The legacy selector retained all four IBRs as GFM (`2-3-4-5`),
whereas both ET-FCSPS and BO selected the authenticated subset `2-3-5` with
resource 2 (IBR1) as the dynamic reference owner. This is the first paired
stress result in which the selected GFM set differs from the manual baseline.

Raw comparison metrics are preserved in
`output/diagnostics/ieee14_controller_reference_fault_recovery_stress/summary.csv`.
Legacy, ET-FCSPS and BO wall times were 4864.512 s, 3976.605 s and 2496.714 s,
respectively; all reached 160 s with maximum accepted residuals
$8.701\times10^{-9}$, $7.939\times10^{-9}$ and $7.939\times10^{-9}$. ET-FCSPS and BO used eight authenticated
predictions. The stress schedule reports `NOT_REQUESTED` for actual SG
reclose/handback, so this run is not claimed as a successful SG-recovery case;
the controller comparison is limited to the SG-trip mode/owner decision and
the subsequent accepted trajectory. The large raw `.mat` files remain local,
ignored cache artifacts; the CSV is the committed machine-readable summary.

## 2026-08-06 — IEEE14 switching report: Phase D/E/F/G/H complete

Started from HEAD `126ae57`. Committed `a2d346a` (pushed, local==remote).

- **Phase D**: eecon49 slack 1.06 -> 1.00 pu at angle 0, +-5% band
  (Vmax 1.05/Vmin 0.95) on all buses. EECON49 mapping re-derived:
  phi=0.508383707164714 (positive-Q root, residual -1.1e-15 on
  |S_SG1|-1.3462), lost_sg_MW=133.190444. Bus 6 solves at 1.0575 pu (above
  Vmax) and is reported, not tuned.
- **Phase E**: bus_role labelling descriptor (REF/PV/PQ/GFM/GFL); PF
  bit-identical, 12-col contract intact.
- **Phase F**: Qmin/Qmax registered from mpc.gen into bus_data 11/12
  (SOURCE_DEFINED); enforce_q_limits enabled in both builders. P-limit
  fail-closed (no mechanism).
- **Phase G**: horizon 160 -> 200 s from case contract; cache-horizon guard;
  .fig companions saved. Full 200-s run passes: FULL_200_S_GATE_PASSED,
  reclose 146.825 s, max step residual 9.99e-9, f_SG settles 60.0002 Hz.
  5 remote load buses below Vmin 0.95 at endpoint — reported openly.
- **Solver**: ts_algebraic_solve iteration lease 30 -> 60 (NUMERICAL_METHOD,
  kcl_tol unchanged) fixing fault-on non-convergence (TS-2026-08-05-01).
- **Phase H**: event timeline figure.
- Reports EN/TH updated to 200-s. Targeted gates 19/19 pass. Full regression
  omitted per risk policy (targeted producer/consumer coverage).
