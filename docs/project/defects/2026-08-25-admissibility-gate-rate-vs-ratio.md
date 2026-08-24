# Admissibility gate compared the wrong quantity to its own declared basis

- **ID**: `GATE-2026-08-25-01`
- **Status**: `RESOLVED_PENDING_ARM_EVIDENCE`
- **Component**: `+stability/ibr_candidate_evaluate.m` stability gate; SG_ON
  reselection endpoint; `+cases/case_ieee14_1sg_4ibr_auto_vsg.m` selector contract
- **Branch / tree**: `main`, working tree carrying the uncommitted 17-state
  non-ideal DC-link work
- **Environment**: MATLAB R2026a, Windows 11

## Symptom

On the 250-s IEEE-14 EECON49 chronology the last grid-forming converter never
returned to grid-following. IBR2 was promoted to GFM at the `sg_trip`
transaction (`t=20.0000`), the SG reclosed successfully at `t=159.2519`, and
IBR2 was still GFM at `t=250`. The published status was
`reselection_status = NO_FEASIBLE_SG_ON_ONE_STEP` with
`actual_mode_reselection_time = NaN`.

The three other converters did return: IBR3, IBR6 and IBR8 all released at
`t=146.2782` through the SG-off support supervisor. Only the reference owner
stayed.

## Reproduction

```matlab
pf_init_paths();
s   = cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
tbl = stability.ibr_selector_table(s.case_data, s.resources, s, struct());
c   = tbl.sg_on.configurations(1);      % the all-GFL row
[c.feasible c.ready_to_commit c.omega c.margin]
```

Before the fix: `feasible = 0`, `ready_to_commit = 0`, `omega = -0.0651964`,
`margin = -0.0348`, `failure_id =
stability:ibr_candidate_evaluate:insufficientRobustMargin`.

## Observations (measured, separated from inference)

1. **The release mechanism was running, not absent.** Reconstructing the
   severity evidence from the delivered arm cache, IBR2's two-term AGSI stayed
   at or below `0.0072` for 1537 accepted samples over roughly 77 s
   (`t = 173.2 .. 250`), continuously under `severity_gamma_off = 0.35`. The
   dwell `severity_T_d_off = 1.0 s` was therefore satisfied repeatedly. The
   supervisor attempted the release on every one of those samples and was
   refused each time.

2. **The C1 handback did complete.** `handback_status = C1_COMPLETE` and the
   ramp variable `alpha` first reached 1 at `t = 173.127`, exactly
   `159.2519 + 13.8752`. See the separate observation below about the published
   completion time.

3. **The only one-step release target is the all-GFL row.** With one committed
   GFM, `choose_sg_online_one_step` forms `target = setdiff([2],2) = []`, so the
   sole candidate is the zero-GFM configuration. That row carried
   `ready_to_commit = 0`, and the validator requires it, so `accepted` was empty
   and the audit reported `NO_FEASIBLE_SG_ON_ONE_STEP`.

4. **The blocking mode is genuine physics.** The all-GFL SG-online spectrum's
   rightmost root is `-0.065196 +/- 0.124395j` (`f = 0.0198 Hz`,
   `zeta = 0.4642`). Its participation is `SG1:omega` `0.258` plus the four GFL
   PLL integrators (`xi_PLL` `0.111 / 0.085 / 0.080 / 0.068`, summing to
   `0.344`) with smaller `xi_Q` and `xi_P` contributions: a system-wide
   interaction between the machine rotor speed and the converter phase-locked
   loops.

5. **The mode is not an artefact of the DC-link work.** Three structurally
   different evaluations return the same root to six significant figures:
   the 17-state Thevenin source (`-0.065196`), the algebraic-source limit
   `source_state = false` (`-0.065196`), and the pre-DC-extension cached table
   `output/diagnostics/automatic_selector_table.mat` (`-0.065196`). A permanent
   +20 % load gives `-0.072055`, still short of the old floor.

6. **The worst-ratio mode is a different mode from the rightmost one.** The
   least-damped mode by ratio is `-1.146045 +/- 7.254946j`, `f = 1.1547 Hz`,
   `zeta = 0.1560` -- the electromechanical mode the contract's derivation
   names, at more than three times the declared 5 %.

7. **FD robustness.** `zeta_worst = 0.156033` at every member of the frozen FD
   set (`eps = 1.5e-06, 3e-06, 6e-06`), identical to six significant figures.

## Root cause

`+cases/case_ieee14_1sg_4ibr_auto_vsg.m` declared the criterion as

```
'gamma_req_rad_per_s', 0.1,
'derivation', '0.1 rad/s = conservative of 2*pi*1*0.05 = 0.31
               (5% damping at 1 Hz electromechanical mode)'
```

so the basis is a damping RATIO, `zeta >= 0.05`, anchored at 1 Hz. The gate at
`+stability/ibr_candidate_evaluate.m:401-402` instead applied an ABSOLUTE
decay-rate floor to every root:

```matlab
cand.fd_robust_margin_pass = all(isfinite(cand.fd_omegas)) && ...
    all(cand.fd_omegas <= -gamma_req);
```

A rate floor and a ratio floor are the same requirement at exactly one
frequency,

    f* = gamma_req/(2*pi*zeta_min) = 0.1/(2*pi*0.05) = 0.3183 Hz,

and diverge on both sides of it. At `f = 0.0198 Hz` the rate floor demands
`zeta >= 0.1/0.1404 = 0.712`, i.e. 14x the declared requirement. The all-GFL
configuration was rejected by a criterion 14x stricter than its stated basis,
on a mode the derivation never addressed, while the electromechanical mode the
derivation does address passed with `zeta = 0.156`.

The consequence was inverted with respect to the contract: measured worst
damping ratios put the configuration the supervisor refused to LEAVE
(`sg_on sel=[2]`, `zeta_worst = 0.1316`) BELOW the configuration it refused to
ENTER (all-GFL, `zeta_worst = 0.1560`). Four admissible rows had less
ratio headroom than the row being rejected.

## Falsified hypotheses

- *The 17-state DC-source extension created the blocking mode.* Falsified by
  observation 5: the algebraic-source limit and the pre-extension cached table
  both give the identical root.
- *The candidate was certified at the wrong operating point.* Falsified by the
  +20 % load probe, which moves the root to `-0.072055` and does not change the
  verdict.
- *The hand-back mechanism was missing or mis-wired.* Falsified by observation 1:
  it ran continuously for 77 s and was refused by the table, not by a timer.
- *`handback_complete_time = 250` meant the ramp never finished.* Falsified by
  observation 2; see the separate defect below.
- *A runtime guard forbids zero GFM while an SG is online.* Falsified:
  `+stability/per_island_vf_check.m:77` treats `synchronous` as voltage-forming,
  `+stability/mixed_equilibrium_solve.m:149-163` counts the SG in `vf_count`,
  and `+stability/ibr_selector_table.m:131` states the intent outright
  ("SG_ON : zero GFM permitted"). The all-GFL + SG-online state is also the
  terminal state of the pre-existing `coordinated_sg_handback` route.

## Fix

Owner-approved change of acceptance criterion (the owner selected the
damping-ratio option after being shown the measured impact of all three
alternatives). The criterion now matches the basis the contract declares.

1. `+cases/case_ieee14_1sg_4ibr_auto_vsg.m` -- selector contract gains
   `zeta_min_damping = 0.05`, `acceptance_criterion = 'damping_ratio_floor'`,
   `equivalence_frequency_Hz`, and a `gamma_req_role` field recording that
   `gamma_req` is retained as the ordering key and reference rate, NOT the gate.
   The EECON49 switch case inherits this struct verbatim
   (`+cases/case_ieee14bus_eecon49_switch.m:197`).
2. `+stability/ibr_candidate_evaluate.m` -- the pass condition becomes
   `all(fd_omegas < 0) && all(fd_zeta_worsts >= zeta_min)`, evaluated at every
   member of the frozen FD set. New fields `fd_zeta_worsts`, `zeta_min`,
   `zeta_worst`, `zeta_margin`. New local `worst_damping_ratio` minimises the
   ratio over the WHOLE spectrum and maps a root at the origin to `-Inf` so a
   marginal zero-frequency mode can never certify.
3. `omega` and `margin` are deliberately UNCHANGED. `margin = -omega -
   gamma_req` remains the 4th sort key in
   `internal/candidate_order_matrix.m:90-94`. Ranking on the ratio instead would
   move the SG_OFF winner from `[2]` to `[5]` (measured), which is a separate
   decision and is not made here. A candidate can therefore be admissible with
   `zeta_margin >= 0` while `margin < 0`; the reason strings state both.
4. `+stability/validate_runtime_candidate_compatibility.m` -- the manual-override
   exact match now canonicalises index sets before comparing. Without this the
   criterion fix has NO observable effect: the stored zero-GFM row holds a
   literal `[]` (0x0) while `choose_sg_online_one_step` derives its target with
   `setdiff` on a row vector and obtains `1x0`, and `isequal([],zeros(1,0))` is
   false in MATLAB, so the row matched the first search loop
   (`ts_simulate_ibr_hybrid.m:2196`, which reshapes) but failed the validator's
   raw comparison and was rejected as `manualCandidateNotInTable`.
   Canonicalisation normalises SHAPE only; membership and cardinality are
   preserved, so the comparison stays exact.
5. Candidate struct templates in `+stability/ibr_config_selector.m:527` and
   `+stability/ibr_selector_table.m` gain the four new fields.
   `ibr_config_selector.m:393` assigns struct-array elements directly and
   requires identical field sets.

## Verification

Measured impact across all 23 evaluated rows: exactly one verdict changes.

| context | before | after |
|---|---|---|
| `sg_off` | 7 feasible, 8 rejected at the EQUILIBRIUM stage | identical, row for row |
| `sg_on`  | 15 feasible, all-GFL rejected | 16 feasible |

The eight rejected `sg_off` rows carry no spectrum (`omega = NaN`); their
reasons are `Device IBR6 violates an equilibrium operating limit` and
`Coupled Newton did not converge`. The non-monotone SG_OFF admissibility result
therefore rests on equilibrium feasibility, not on the damping gate, and is
untouched.

Damping-ratio headroom over `zeta_min = 0.05`, narrowest first:

| row | `zeta_worst` | headroom |
|---|---|---|
| `sg_off [2 3 4 5]` | 0.1223 | +0.0723 |
| `sg_on [2]` | 0.1316 | +0.0816 |
| `sg_on [2 3]` | 0.1437 | +0.0937 |
| `sg_on [3]` | 0.1457 | +0.0957 |
| `sg_on <none>` (all-GFL) | 0.1560 | +0.1060 |

No row is marginal; the tightest is 1.4x the floor.

Targeted gates run (no full repository regression; see the policy note below):

| file | result |
|---|---|
| `test_ibr_selector_scr_sssa` | 16/16 (13 existing + 3 new) |
| `test_ibr_selector_table_unit` | 44/44 |
| `test_ieee14_ibr_sg_on_integration` | 12/12 |
| `test_ibr_index_selected_gfm_commit` | 13/13 |
| `test_ieee14_ibr_sg_reclose_workflow` | 20/20 |
| `test_ieee14_ibr_ts_event_runner` | 19/19 |

`test_ieee14_decoupled_full_state` fails 5/6, PROVEN PRE-EXISTING and unrelated:
see `GATE-2026-08-25-02` below.

### Test changes and their justification

`tests/test_ibr_selector_scr_sssa.m:215` previously asserted
`cc.sssa_pass == (cc.omega <= -result.gamma_req)`, i.e. that the gate IS the
absolute-rate floor. That equivalence is false under the declared contract and
survived only because the sampled row happened to satisfy both criteria, making
it a latent trap rather than a check. It is replaced by assertions on the
declared criterion, on `zeta_worst` being minimised over the whole spectrum and
FD set, and on `margin` retaining its ordering-key definition.

Three new falsification tests were added, each with an oracle independent of the
implementation:

- `test_the_criterion_is_the_ratio_the_contract_declares` derives
  `f* = gamma/(2*pi*zeta)` from the contract's own numbers and demonstrates on
  two concrete modes that the rate floor is stricter below `f*` and the ratio
  floor above it.
- `test_worst_damping_ratio_is_not_the_rightmost_root` asserts on the real
  all-GFL spectrum that the worst-ratio root and the rightmost root are
  different roots, that the gate used the former, and that this row is
  admissible with `zeta_margin > 0` while `margin < 0`.
- `test_a_low_damping_ratio_still_fails_closed` builds a 5 Hz mode at 1 %
  damping whose every root sits left of `-gamma_req` -- a set the OLD gate would
  have accepted -- and requires the new gate to reject it. It also pins that a
  root at the origin returns `-Inf` and a real negative root returns `zeta = 1`.

One of these tests initially failed at `AbsTol 1e-9` because it compared
`zeta_worst` (the worst over three FD epsilons) against the ratio of the
`eps = 1.0` spectrum alone; the two differ by `5.5e-08`. The TEST was wrong, not
the gate: the exact oracle for the stored spectrum is `fd_zeta_worsts(2)`. The
assertion was corrected to compare that entry exactly and to bound
`zeta_worst <= min(zeta)` with a separate FD-accuracy check.

### Pending

The five-arm re-run under the corrected criterion is required before any claim
about the delivered trajectory. `reuse_completed = false` is mandatory: the
criterion changes the candidate evidence and therefore the
`selector_table_fingerprint`, so every arm's cached option signature is stale by
construction. Expected, to be confirmed rather than asserted:
`reselection_status` becomes `SUCCESS`, `n_gfm_at_end` becomes 0, and
`actual_mode_reselection_time` becomes finite at roughly `t = 173.1`.

### Known consequence, reported not hidden

The handed-back all-GFL configuration is better damped in RATIO but slower in
absolute decay: its slowest mode has `tau = 15.3 s` against `4.6 s` for the
one-GFM configuration it replaces. Settling after the release is correspondingly
slower. `+stability/ts_simulate_ibr_hybrid.m` `compute_tdown` and
`derive_handback_duration` require only `omega < 0`, which `-0.0652` satisfies,
so nothing fails closed; but a hold derived from this row would be
`ln(1/0.05)/0.0652 = 45.9 s` rather than about 30 s at the old floor.

### Residual limitation

A pure ratio floor places no lower bound on `|lambda|`, so it does not by itself
exclude a mode arbitrarily close to the origin. Two guards make this moot for
this case: the gauge quotient removes the one rigid network-angle coordinate, so
a surviving zero root would be a genuine marginal mode, and
`worst_damping_ratio` maps it to `-Inf` so it cannot certify. No admissible row
in either context lies near the origin -- the least-damped rate among admissible
rows is `-0.0652`. The alternative of adding an explicit settling-time cap was
presented to the owner and not selected.

## Related files

- `+cases/case_ieee14_1sg_4ibr_auto_vsg.m`
- `+stability/ibr_candidate_evaluate.m`
- `+stability/ibr_config_selector.m`
- `+stability/ibr_selector_table.m`
- `+stability/validate_runtime_candidate_compatibility.m`
- `tests/test_ibr_selector_scr_sssa.m`
- `internal/candidate_order_matrix.m` (ordering keys, read-only in this change)

---

# Companion observations recorded during the same investigation

## `GATE-2026-08-25-02`: decoupled family broken by the 17-state DC source

- **Status**: `OPEN`
- **Component**: `+cases/scenario_ieee14_1sg_4ibr.m`,
  `+ibr/decoupled_dual_mode_model.m`

`tests/test_ieee14_decoupled_full_state.m` fails 5 of 6 with

```
ibr:decoupled_dual_mode_model:branchLayout
Expected a 10-state GFL adapter and an 11-state decoupled GFM adapter.
```

raised from `+ibr/decoupled_dual_mode_model.m:71` via
`stability.build_mixed_resource_devices:148`.

`+cases/scenario_ieee14_1sg_4ibr.m:321-323` sets
`r.dynamic_params.dc_source.source_state = true` inside a block that covers BOTH
the `eecon49_dual` and the `decoupled_dual` model families, so the decoupled
family's shared GFL adapter becomes 11 states while its guard still expects 10.
The earlier opt-in remedy that restored `test_ibr_decoupled_dual_mode_model`
did not cover this profile.

PROVEN PRE-EXISTING and independent of `GATE-2026-08-25-01`: with the five gate
files reverted to `HEAD` and the DC-link work left in place, the same file still
reports `6 run, 5 failed, 4 incomplete` with the identical error identifier. The
failing call chain contains none of the gate files, and the error is raised
during device construction, before any candidate is evaluated.

Not fixed here because it lies outside the authorised scope of the gate
correction. It must be resolved before the DC-link work is delivered.

## `GATE-2026-08-25-03`: `handback_complete_time` reports the last step, not completion

- **Status**: `OPEN`
- **Component**: `+stability/ts_simulate_ibr_hybrid.m:3885-3886`

The published `handback_complete_time` was `250` on a run whose C1 ramp
demonstrably finished at `t = 173.127` (`handback_t0 = 159.2519`,
`handback_T = 13.8752`, and `alpha` first reaches 1 at exactly that time).

```matlab
if a1>=1
    c.handback_active=false; c.handback_complete=true;
    c.handback_complete_time=t+h; c.handback_status='C1_COMPLETE';
end
```

The branch is not latched: the controller stays active after completion, `a1`
remains at 1, and every subsequent accepted step overwrites
`handback_complete_time` with its own `t+h`. The published value is therefore the
final accepted sample, not the completion instant.

This is a reporting defect only -- `handback_complete` is a boolean and the gate
at `:1099` reads the boolean, not the time -- but the field is quoted in report
scalars, so it must be latched before any report cites it. Diagnostic cost was
real: the value initially suggested the ramp had never finished.

---

# `GATE-2026-08-25-04`: SG_ON authentication handed the validator a Y it could never match

- **Status**: `RESOLVED_PENDING_ARM_EVIDENCE`
- **Component**: `+stability/ts_simulate_ibr_hybrid.m`
  `authenticate_sg_on_candidate`, `choose_sg_online_one_step`

## Why this record exists separately

Correcting the admissibility criterion (`GATE-2026-08-25-01`) made the all-GFL
row `feasible = 1, ready_to_commit = 1`, verified in the table. The 250-s arm was
then re-run and the outcome did **not** change: `reselection_status` was still
`NO_FEASIBLE_SG_ON_ONE_STEP`, `actual_mode_reselection_time` still `NaN`, IBR2
still GFM at `t = 250`, and `reselection events: 0`. A second, independent gate
was refusing the release. The criterion fix was necessary but not sufficient.

## Observability defect found first

`choose_sg_online_one_step` discarded the validator's structured `err_id` at
every `continue`, so the audit could only ever publish the aggregate
`NO_FEASIBLE_SG_ON_ONE_STEP`. An operator could not distinguish "no such row in
the table" from "row present but not ready" from "runtime rejection". A
`rejection_detail` cell was added to the audit, published through
`res.reselection_rejection_detail` and `run_hybrid_case`. It is diagnostic only:
no gate reads it. With it, a 180-s run answered the question immediately:

```
REFUSAL REASONS (1):
  release 2: validator refused (stability:gfm_selection:staleFingerprint)
             selector_table fingerprint stale.
```

## Root cause

`validate_runtime_candidate_compatibility` recomputes the three-layer
fingerprint from the Y it is handed and compares all three against the stored
hashes. Measured layer by layer at the release instant:

| layer | stored | recomputed | match |
|---|---|---|---|
| input | `d3c2efbf` | `4e153dba` | no |
| evidence | `85256462` | `85256462` | **yes** |
| table | `064d464f` | `ee862587` | no (derives from input) |

The evidence layer matches exactly, which proves the criterion change did not
invalidate the fingerprint. Only the topology payload disagrees:

```
max |stored_payload - Ypre|          = 1.028245
off-diagonal difference             = 0.000000e+00   (branch network identical)
diagonal difference                 = on buses 2,3,4,5,6,9,10,11,12,13,14 only
max |Ypre - stored - Yload|         = 8.6e-02   (vs 1.97 the other way round)
```

The off-diagonal being exactly zero and the diagonal differing on precisely the
eleven IEEE-14 load buses identifies the gap: `dae.topology.Ypre` carries the
constant-impedance LOAD admittance that `composite_dae` folds into the diagonal
under `load_model = 'cz_p_cz_q'`, while `ibr_selector_table` hashed the load-free
canonical Ybus (`ibr_selector_table.m:101,390`). The residual `8.6e-02` is
because the DAE converts load at the solved power-flow voltage rather than at
`mpc.bus(:,8)`.

The repository already documents this requirement. The note on
`canonical_ybus_from_mpc` (`ts_simulate_ibr_hybrid.m:3663-3669`) says the helper
exists to derive the runtime fingerprint *"without the LOAD admittance term that
the TS-specific build_ybus_local adds (so the validator's input fingerprint
matches the build-time hash in the no-drift case)"*. `trip_transaction`
(`:1929-1933`) complies and always derives the payload that way -- and it is the
path that authenticates successfully at runtime, which is why the `sg_trip`
promotion at `t = 20` commits. The two SG_ON paths deviated:

- `authenticate_sg_on_candidate` used `Ytopo = Y` and fell back to the canonical
  derivation only when `Y` was empty, i.e. never in practice.
- `choose_sg_online_one_step` passed the live `Ycurr` straight through.

So the SG_ON one-step release could not authenticate for ANY candidate, in any
configuration, independently of the admissibility criterion. The criterion defect
hid it: while the all-GFL row was `ready_to_commit = 0` the release failed one
gate earlier and the fingerprint layer was never reached.

## Fix

Both SG_ON call sites now derive the payload exactly as `trip_transaction` does:
`canonical_ybus_from_mpc(case_data.mpc)`, retaining the passed `Y` only as a
fallback for a caller that supplies no `mpc`. This makes the SG_ON paths
consistent with the SG_OFF path and with the documented intent, rather than
leaving them permanently unauthenticable.

This does not weaken the check. `case_data.mpc` is never mutated at runtime --
verified: no assignment to `case_data.mpc` or to `mpc.branch(:,11)` exists in the
kernel, and the scheduled line trip is applied as a `Yline_stamp` delta against
`Ybase_current` (`:56`), not by editing the case. So `canonical_ybus_from_mpc`
returns the base branch network on every path, and the corrected SG_ON payload
has exactly the same drift sensitivity as the SG_OFF payload that has always been
used. Passing the live load-folded Y provided no drift detection either: it
produced unconditional failure, which is a wall rather than a gate.

Every other gate remains in force on this path: equilibrium convergence and
conditioning, the damping-ratio criterion, the physical-KCL norm, the exact
one-step relation, the hold/lockout revalidation, the severity dwell, and the
right-limit KCL solve on the committed state.

## Limitation, recorded not hidden

Because `case_data.mpc` is static, the canonical payload does not express an
open scheduled branch. A reselection attempted while the chronology line is open
would authenticate against the intact-network hash. This is a property of the
existing contract shared with `trip_transaction`, not something introduced here,
and it is inert for this study because the line is restored at `t = 145`, before
the reclose at `t = 159.2519` and the release window after `t = 173.13`. Making
the payload track the live branch state would change the authentication contract
on both SG_OFF and SG_ON paths and is not done here.

## Verification

Pending: a re-run of the adaptive arm with both fixes in place. The other four
arms are unaffected -- the pinned arms run with
`automatic_support_supervision = false` and never enter the severity release
path, and `pinned_gfm4` and `locked_gfl` terminate at `t = 25.488` and
`t = 20.000`, far short of the release window. Their cached option signatures are
also unchanged, because this fix is runtime-side and does not touch the selector
table or its fingerprint.

---

# `GATE-2026-08-25-05`: the one-step accumulator had never executed

- **Status**: `RESOLVED_PENDING_ARM_EVIDENCE`
- **Component**: `+stability/ts_simulate_ibr_hybrid.m` `choose_sg_online_one_step`

With `GATE-2026-08-25-01` and `-04` both fixed, the validator authenticated the
all-GFL row and control reached the next statement, which threw:

```
Error in stability.ts_simulate_ibr_hybrid>choose_sg_online_one_step (line 2287)
    accepted(end+1,1) = c_auth;
Subscripted assignment between dissimilar structures.
```

`accepted` was initialised as `repmat(struct(),0,1)` -- a struct array with NO
fields. Appending a populated candidate to it is invalid in MATLAB. The line
could therefore never have executed successfully: every prior iteration reached
`continue` first, either because the all-GFL row was not `ready_to_commit`
(`-01`) or because the input fingerprint could not match (`-04`).

Fixed by accumulating into a cell, which has no field-set precondition, and
materialising the struct array the frozen ranking indexes once the loop ends.
Field sets are normalised with `orderfields` against the first accepted
candidate; a genuine mismatch is reported through a new
`candidateFieldMismatch` failure ID rather than silently padded.

## What the three records together establish

The SG-online one-step release path had **three independent latent defects**,
each hiding the next:

| order | defect | why it hid the next |
|---|---|---|
| 1 | admissibility criterion compared decay rate, not damping ratio (`-01`) | the all-GFL row was never `ready_to_commit`, so the validator was never asked |
| 2 | validator handed a load-folded Y against a load-free hash (`-04`) | the input fingerprint could never match, so the accumulator was never reached |
| 3 | accumulator initialised with a field-less struct array (`-05`) | -- |

No test covered this path end to end, which is why all three survived. The
staged release from one grid-forming converter to zero has never completed in
this repository.

---

# `GATE-2026-08-25-06`: the pinned arms are also subject to the post-reclose handback

- **Status**: `OPEN_OWNER_DECISION`
- **Component**: `+stability/ts_simulate_ibr_hybrid.m:1446`,
  `scripts/reporting/run_ieee14_gfm_lock_comparison.m` arm table

Measured on the five-arm re-run: `pinned_gfm1` and `pinned_gfm2` both publish
`reselection_status = NO_FEASIBLE_SG_ON_ONE_STEP`, so they DO enter the
post-reclose severity release path. This falsifies the working assumption --
stated by the primary agent earlier in the same session -- that only the
`adaptive` arm could be affected by a reselection change.

The cause is that `severity_handback_enabled` is set from the presence of
`healthy_pf_V` and `healthy_pf_bus_ids` alone:

```matlab
s.severity_handback_enabled = has_healthy_v && has_healthy_bus;   % :1446
```

whereas `severity_support_enabled` additionally requires
`automatic_support_supervision`:

```matlab
s.severity_support_enabled = logical(option(opt,'automatic_support_supervision',false)) && ...
    logical(option(opt,'automatic_gfm_switching',true)) && has_healthy_v && has_healthy_bus;
```

The pinned arms set `automatic_support_supervision = false`, which disables the
SG-OFF support supervisor but NOT the SG-ON post-reclose handback. Every arm that
supplies a healthy-PF reference is therefore subject to it.

### Consequence requiring an owner decision

Now that the release can complete, the pinned arms will release their pinned
grid-forming units after the reclose. An arm labelled "one grid-forming unit
pinned, no run-time switching" would then perform a run-time switch at
`t ~= 173`, so its declared semantics no longer hold over the post-reclose
window. The arms remain valid controls over the islanded window
`t in [20, 159]`, which is where the comparison's substantive claims live, but
the post-reclose segment would no longer be a no-switching control.

Two coherent resolutions exist and they are not equivalent:

1. Accept it and re-describe the arms: the pin governs the ISLANDED
   configuration, and every policy converges to all-GFL once the machine is back.
   Nothing in the runtime changes; the arm labels and the report prose do.
2. Make the pin hold across the reclose by disabling the severity handback on the
   pinned arms, so they remain no-switching controls for the whole horizon. This
   is an arm-definition change and would need a new option, because
   `severity_handback_enabled` currently has no independent switch.

Not decided here: it changes what the five-arm comparison means, which is the
owner's call. The measurement is recorded so the choice is made on evidence.

### Re-run scope correction

Three arms depend on the release outcome, not one: `adaptive`, `pinned_gfm1` and
`pinned_gfm2`. `pinned_gfm4` (`t_end = 25.4880`,
`ts_simulate_ibr_hybrid:adaptiveDtMin`) and `locked_gfl` (`t_end = 20.0000`,
`ts_simulate_ibr_hybrid:noVoltageFormingSource`) terminate far short of the
release window and are unaffected. The runtime fixes do not touch the selector
table or its fingerprint, so the two unaffected caches remain signature-valid.

---

# Verification of the combined fix (`-01`, `-04`, `-05`)

A 180-s run of the adaptive policy with all three fixes in place, reaching past
the C1 completion at `t = 173.127` so the release window is exercised:

```
handback_status    C1_COMPLETE
reselection_status SUCCESS
mode_reselection   173.1271
terminal modes: SG1=sg IBR2=gfl IBR3=gfl IBR6=gfl IBR8=gfl
REFUSAL REASONS (0):
```

The release time is self-checking: `159.2519 + 13.8752 = 173.1271` exactly, so
the transaction commits on the first sample after the C1 ramp completes. That is
consistent with the pre-fix measurement that IBR2's severity was already
continuously below `gamma_off` well before that instant -- the dwell was never
the binding constraint, and the release now fires as soon as the ordering
constraint (`handback_complete`) is satisfied.

`REFUSAL REASONS (0)` confirms no candidate was rejected on the accepted path,
and `reselection_status` moved from `NO_FEASIBLE_SG_ON_ONE_STEP` to `SUCCESS`,
which is the transition predicted in the `-01` "Pending" section rather than one
asserted after the fact.

The terminal state is all-GFL with the reclosed SG as sole reference owner,
matching the state `coordinated_sg_handback` reaches by its own route, so the
outcome is a first-class published configuration and not a novel one.

## Full-horizon evidence

The 250-s five-arm set produced BEFORE the `-04` and `-05` fixes is retained
under `output/diagnostics/ieee14_gfm_lock_compare_zeta/*.pre_release_fix` (renamed,
not deleted) as the record of the criterion-only state, in which all three arms
that reach the reclose still reported `NO_FEASIBLE_SG_ON_ONE_STEP`. The three
affected arms are being re-run; `pinned_gfm4` and `locked_gfl` are reused because
they terminate at `t = 25.4880` and `t = 20.0000` respectively, and the runtime
fixes leave the selector table and its fingerprint untouched so their option
signatures remain valid.

## Full-horizon verification, and proof the fixes are inert before the release

250-s adaptive arm with all three fixes:

```
IBR2   t= 20.0000  gfl -> GFM      (island reference owner at the sg_trip)
       t=173.1271  GFM -> gfl      (returned after the reclose)
n_gfm: max=4  terminal=0
reselection events: 1  applied=1
  "severity_sg_online_authenticated reselection committed at t=173.127;
   1 device(s) transitioned."
reference_owner_indices(end) = 1
terminal f_COI = 60.000001 Hz
terminal |V| = 0.9667 .. 1.0575 pu
```

The cycle now closes: machine trips, one converter takes over voltage forming,
support units are augmented and released on severity, the machine returns, and
every converter goes back to grid-following with `n_gfm` ending at 0. The
terminal frequency and voltage band show the state is not merely committed but
operable.

**Inertness before the release, measured against the pre-fix run.** Comparing the
post-fix arm with the retained `-01`-only arm over their shared window:

```
last pre-release index: post=3486 (t=173.127094)  pre=3485 (t=173.127094)
time vectors identical on [1,3485]: 1
max |dx| = 0.000e+00
max |dy| = 0.000e+00
```

Exactly zero on both the differential states and the algebraic variables, not
merely small. Every difference between the two runs begins at the release instant
and nowhere earlier, so the three fixes changed no equation, no parameter and no
accepted step before the transaction they enable. Accepted-sample count falls
from 5023 to 3679 (-27 %), consistent with an all-GFL system being smoother and
letting the adaptive stepper take longer steps after the hand-back.

---

# Delivery record (all phases verified)

## The no-adaptation control arm and the A-vs-B-prime comparison

The owner selected the comparison to present: **adaptive (A) versus no
adaptation (B-prime)**, with the control defined as "one grid-forming unit
committed once at the trip and never revisited". Two further defects were found
while building it, both fixed:

- `run_hybrid_case` forwards options to the kernel through an explicit
  whitelist; the new option was silently dropped until added to the list. The
  first probe therefore still returned SUCCESS and the pin was released -- the
  option never reached the kernel.
- The generator's default arm list did not include the new arm, so the first
  A-vs-B figure drew only one trace.

The control arm is expressed by `post_reclose_mode_reselection=false`
(default true; the reclose transaction then never arms the handback and
publishes the explicit `DISABLED_BY_POLICY`). Verified on a 180-s probe:
`reselection_status=DISABLED_BY_POLICY`, `mode_reselection=NaN`, terminal modes
`SG1=sg IBR2=GFM IBR3=gfl IBR6=gfl IBR8=gfl`, `n_gfm max=1 terminal=1`,
"post-reclose mode changes: NONE (the pin held)".

Full-horizon result (`no_adaptation_250s.mat`): `t_end=250.0000 conv=1
reclose=SUCCESS@151.082 resel=DISABLED_BY_POLICY n_gfm_end=1`, expectation
`REACHES_T_END -> MET`. The control is NOT a collapse -- it runs to the horizon.
Its measured cost: peak frequency deviation from nominal 1.4978 Hz at the fault
and 1.2325 Hz sustained after the line trip, against 1.1385 / 0.3764 Hz for the
adaptive policy. The mechanism is droop capacity: an island governed by droop
with no AGC retains a standing deviation, and fewer grid-forming units means
less droop power. The figure
`comparison_adaptive_vs_no_adaptation.png` (window [15,255], derived not chosen,
`n_hidden=0`) shows all four rows: frequency, minimum voltage, GFM count
(control flat at 1, adaptive peaks at 4 and returns to 0), and reference owner
(both hand back to the machine).

This RESOLVES the owner decision recorded in `GATE-2026-08-25-06`: instead of
re-labelling the pinned arms or pinning them across the reclose, the comparison
presents the dedicated control arm whose semantics hold over the whole horizon.

## Report delivery

- EN `report_ieee14_switch_en_rev2.tex`: rebuilt, 39 pages, 0 errors, 0
  undefined references, 0 overfull hboxes over 20 pt, no e-notation. New
  content: the reselection table row (mode return at 173.1271 s, status
  authenticated), the paragraph "The cycle closes: every converter returns to
  grid-following" (with the zeta evidence and the coordinated-hand-back
  equivalence), and Figure 7 (the A-vs-B-prime page) with a caption whose Hz
  numbers come from the generated macros. The one remaining `Overfull \vbox`
  (11.8 pt, page 36, the eight-panel electrical figure) is PRE-EXISTING: the
  HEAD version of the report builds with the same warning (`ovv=1` measured on a
  HEAD checkout build).
- TH `report_ieee14_switch_th_rev2.tex`: rebuilt, 26 pages, 0 errors, 0
  undefined. Same table-row and cycle-closes content in Thai, plus the full
  16-to-17-state upgrade this file still owed from the DC-link work: section
  title, the 17-vector with `I_dc` at index 17 and the append-not-insert
  rationale, active sets `{1:9,17}`/`{1:3,10:16,17}` with 10/11 counts, the
  17-row state table with the DC-source row, the reduction paragraph, the
  heterogeneity list, and the abstract line. No "16 สเตต" string remains in the
  compiled PDF.
- All figures regenerated from the `ieee14_gfm_lock_compare_zeta` cache:
  decision x3, mode_switch_PQ, electrical x2, comparison x5 (including the new
  page), sg_off_admissibility; SSSA tables n1/n2/n4 + the all-GFL SG_ON table
  regenerated under the corrected gate (the DC pairs at zeta=0.707 and the
  all-GFL critical mode -0.065196+/-0.124395 with the rotor/PLL participation
  recorded above); `run_summary_v2.tex` now carries `NReselection=1`,
  `ModeReselectionTime=173.1271`, `Handback=13.8752`; `comparison_macros.tex`
  carries the no-adaptation arm macros including the per-event Hz excursions.
- Fallback `\newcommand` blocks in both reports gained the four new macros so a
  build without the generated files still compiles with em dashes.

## Gates actually run (no full-repository regression; policy note)

Selector/gate: `test_ibr_selector_scr_sssa` 16/16 (13 existing + 3 new
falsification tests), `test_ibr_selector_table_unit` 44/44,
`test_ieee14_ibr_sg_on_integration` 12/12, `test_ibr_index_selected_gfm_commit`
13/13, `test_ieee14_ibr_sg_reclose_workflow` 20/20,
`test_ieee14_ibr_ts_event_runner` 19/19. `test_ieee14_decoupled_full_state`
5/6 failing is PRE-EXISTING and recorded as `GATE-2026-08-25-02` (proven at
HEAD). Runtime inertness before the release instant: `max|dx|=max|dy|=0.000e+00`
over the shared pre-release window against the criterion-only run. The full
repository suite was intentionally not run; the targeted set above covers the
changed producer, its consumers and the relevant failure paths.
