# IEEE14 1-SG + 4-IBR Automatic GFL/VSG Mode-Switching Mission

**Status:** `PHASES_0_TO_17 = AUTHORIZED`;
`MANDATORY_PHASE_1_USER_PAUSE = REMOVED`;
`SIX_REMAINING_ITEMS = ENGINEERING_DESIGN_CONTRACTS` (not ASSUMED_DIAGNOSTIC);
`PUSH_OR_MERGE = FORBIDDEN`;
`IBR_PRODUCTION_INTEGRATION_READY` = `NOT_STARTED` (until each phase gate
passes with fresh evidence).

**Phase 0-3 DONE** (C0-C5 @ `dff4dd4`): worktree, source audit, generic
event architecture (6 helpers + 21 tests), driver-loop partial integration.
Final regression 475/475/0/0. Track A legacy AbsTol=0 gates preserved.

**Phase 4-17 NOW AUTHORIZED** with these binding policies:
1. Use VERIFIED sources for all governing GFL, REGFM_B1/VSG, SG, limiter,
   anti-windup, synchronism equations.
2. Select ONE complete IEEE14 SG dataset using provenance/completeness
   criteria; NEVER mix datasets (Demetriou OR Kodsi, not both).
3. Derive bumpless GFL↔VSG transfer maps from state continuity, terminal-
   current continuity, algebraic-residual minimization; classify
   PROJECT_DERIVED (write continuity/reset equations + falsification tests
   first).
4. Define the 219 MW post-trip dispatch/reserve/current/ramp/energy
   constraints as an explicit CASE_DEFINED dispatch contract, proven
   feasible BEFORE TS.
5. Define gamma_req from an a-priori eigenvalue-margin study.
6. Choose synchronism thresholds + delays from verified standard ranges;
   freeze ONE CASE_DEFINED value BEFORE running results.
7. NO value may change after viewing outcomes to obtain a pass.
8. Preserve a DECISION LEDGER with rationale, source/derivation, tests.
9. Stop ONLY for: unsourced governing equation, physical infeasibility,
   numerical contract failure, ownership conflict, or change outside the
   approved allowlist. Do NOT stop because a benchmark does not prescribe
   a project-design value.
10. Keep each readiness milestone NOT_READY until its gate actually passes.
11. Phase gates + commits + fresh regressions at each phase. No push/merge.

This plan authorizes **full unattended Phase 0–17 execution** in one
continuous run. Phase 1 remains a hard mathematical/source gate, but is NO
LONGER a mandatory user-pause checkpoint: if Phase 1 source-closes every
required equation/parameter/state-order/base/sign/transfer-map/inactive-
state-policy/dispatch-energy/delay/synchronism/margin, the agent freezes the
profile, records the source matrix, commits C1, and proceeds autonomously
through Phase 17. Genuine source/semantic/numerical stop conditions (listed
below) override unattended execution and trigger an evidence-backed handoff.

## Context

This plan implements the clean-slate IEEE MATPOWER 14-bus mixed-resource
mission defined in the canonical plan
`docs/project/plans/IEEE14_1SG_4IBR_AUTO_VSG_SWITCHING_PLAN.md` (read in full)
and the execution handoff at `/tmp/CLAUDE_IEEE14_IBR_EXECUTION_HANDOFF.md`.

The Track A generic interface foundation (R1–R4 + B1–B9 corrections) at
commit `31a211d` provides the numerical core this mission builds on:
composite DAE (single owner, `YV-I` KCL, 5-arg device ABI), paired-vcon Schur
SSSA, bundle dispatch, right-limit event transition, and fixed/adaptive
bundle routing. Track A did NOT integrate any IBR model — that is this
mission's job.

**User directives that override the canonical plan (binding):**

1. **No ASSUMED_DIAGNOSTIC.** Every device parameter, SG dynamic, dispatch
   value, delay, and synchronism threshold must have a sourced reference.
   Stricter than canonical plan §5.2/§12.2.
2. **Generic hybrid-event/hybrid-state infrastructure precedes IBR models.**
   Two separate event contracts (scheduled + guard-triggered), persistent
   hybrid_state owned solely by the TS driver, explicit coincident-event
   semantics, physical-GFM/control separated from numerical algebraic
   reference, mixed-resource equilibrium solver phase before mixed SSSA,
   source-gate for inactive dual-mode states. (Details below.)
3. **Autonomous selection hierarchy** (when several source-backed
   alternatives exist): choose using this predeclared order:
   a. An IEEE14-specific published profile with complete dynamic data.
   b. A complete standard profile explicitly applicable to the implemented
      device class and operating conditions.
   c. A single internally coherent model family over a mixture of equations
      copied from incompatible sources.
   d. A normative/recommended/default value explicitly stated by the source.
   e. The alternative requiring the fewest additional unsupported semantics
      while satisfying the mission requirements.
   Do NOT mix equations/parameters from incompatible profiles merely to
   obtain a complete model. Record every autonomous selection in the frozen
   contract with: alternatives considered, exact source locations,
   applicability conditions, selection criterion, rejected alternatives and
   reasons, resulting state/input/parameter order, known limitations.
4. **CASE_DEFINED values** allowed only when directly determined by the
   existing IEEE14 case, an explicit user directive, or a deterministic
   conservation/feasibility equation. Not permission to invent a physical
   parameter.
5. **Revised phase ordering:** Phase 0 preflight → Phase 1 source closure →
   Phase 2 generic scheduled+guard event architecture (synthetic tests) →
   Phase 3 persistent hybrid-state/rollback contract → Phase 4 mixed
   equilibrium/reference-gauge contract → THEN sourced GFL/VSG models.

---

## Read-only audit evidence (verified this session)

### Git / worktree state (safe to proceed)

- `origin/main` = `main` = `f59076f` (no race; 0 behind).
- Track A `feature/ibr-interface-foundation` HEAD `31a211d`, 16 ahead / 0
  behind, merge-base `f59076f`. Worktree
  `/home/birds/Documents/Power-flow-ibr-interface` is at `31a211d` but DIRTY
  (4 user-owned launcher/plot files) — must NOT be modified. New integration
  worktree created from immutable commit object `31a211d`.
- `feature/ieee14-auto-vsg-switching` does NOT exist.
- `/home/birds/Documents/Power-flow-ieee14-ibr` does NOT exist.
- Stash `eae0bcd` (Track B preservation) intact — must NOT be touched.
- Historical `feature/ibr-vsg-models` @ `a684cd0` read-only; no worktree.

### Track A interfaces present at `31a211d` (verified by audit)

- `composite_dae(case_data, devices, opt)` — 5-arg device ABI
  `f(t,x_dev,y,u_dev,event_context)`, `current_injection`, `reconstruct`;
  canonical KCL `g = Y*V - Ibus`; optional `opt.vcon` (vars/rows/eq/ref),
  `numel(vars)==numel(rows)` required; runtime `vcon_eq=@(x,y) eq(y,ref)`
  (FIXED y-only, `Jcon_x==0` enforced); MATPOWER-mpc-only entry validation.
  Internal MATPOWER PF is NOT sufficient for SG_OFF/GFM equilibria (see
  correction 5).
- `multimachine_ssa(model)` — paired Schur; B6 consistency checks with FROZEN
  thresholds (VAL_TOL=JX_TOL=JY_TOL=1e-6, RCOND_MIN=1e-10, FD_STAB_TOL=1e-4);
  COI `pinv(T)` preserved; reference-mode reduction removes machine-1 angle/
  speed via `T` (no manual eigenvalue deletion). **vcon is FIXED y-only; a
  dynamic vcon-row handoff is NOT supported and would require separate
  approval (see correction 4).**
- `multicase_sssa` — model_bundle/model_fn/sssa_model mutually exclusive.
- `ts_simulate` — bundle dispatch; `opt.stepper='adaptive'` →
  `ts_adaptive_driver`; default FIXED.
- `ts_event_transition` — 9-arg; `event_tol=1e-10`. **GAP: supports ONLY
  `fault_on`/`fault_off`; no guard-triggered transitions; no hybrid_state.**
- Provider ABI: exogenous `fn(t,event_context)` only (NO state dependence).
  Guard evaluation is NOT an input provider (see correction 1B).

### IEEE14 case facts (recomputed)

- baseMVA=100, 60 Hz, baseKV=69; 14 buses, 5 gens, 20 branches.
- Gens at buses **[1,2,3,6,8]** (confirmed). Bus 1 = REF; buses 2,3,6,8 = PV.
- Total load = **259.0 MW**; bus-1 Pg = **232.4 MW**; buses 2–8 Pg = 40 MW.
- **Post-trip deficit = 219 MW.**
- **NO dynamic data in case file** (no `.machines`). Classical TS falls back
  to hardcoded H=5.0/D=0/X'd=0.30 (UNSOURCED). EMF6 errors without
  `.machines`.

### Historical Track B source gaps (`feature/ibr-vsg-models` @ `a684cd0`)

- 5-state VSG prototype; **8 unsourced equations**. Only 3 of 28 provenance
  rows SOURCE-backed.
- No GFL model, no dual-mode, no integrated limiter, no SG trip/reconnection,
  no IEEE14 auto-selection, no REGFM_B1 inspection.
- Conventions compatible with Track A canonical (YV-I, positive injection,
  `S=V*conj(I)`, system base).
- **Reuse default = none.**

---

## Binding architectural corrections (user-mandated, this revision)

### Correction 1 — Two separate event contracts

**A. Scheduled named transitions** (time-driven):
- explicit `time`
- `event_id`
- `order`
- `atomic_updates`
- `topology_id`

**B. Guard-triggered transitions** (state-driven):
- evaluated only from committed/accepted `(t, x, y, hybrid_state)`
- sourced threshold
- sourced dwell
- source ID
- deterministic priority
- event localization policy
- timeout / fail-closed behavior

**Guard evaluation is NOT an input provider.** R1 providers remain
exogenous `fn(t, event_context)`. **Rejected adaptive trials must not
advance guard, dwell, delay, lockout, or selector state.** Guard state is
mutated ONLY by accepted (committed) steps.

### Correction 2 — Persistent hybrid_state owned solely by the TS driver

```text
hybrid_state =
  device_modes              % per-device 'gfl'|'GFM'|'tripped'
  device_online             % per-device online/offline
  pending_commands          % per-device pending mode + timing metadata
  dwell_timers              % per-device / per-transition dwell remaining
  hold_timers               % modal hold (T_down) remaining
  lockouts                  % per-device lockout-until
  active_configuration_id   % current selector configuration
  selector_table_version    % which validated table is active
  selector_fingerprint      % equilibrium fingerprint the table was built on
```

**Event transition must RETURN the updated hybrid_state.** Every RHS /
current / reconstruct call receives an IMMUTABLE hybrid-state snapshot
through an extended `event_context` (which now also carries the snapshot).
**No device closure, provider, or global variable may mutate mode state.**
The TS driver is the sole mutator.

### Correction 3 — Coincident-event semantics

- Sort by unique `(time, order)`; `event_id` globally unique.
- Several inseparable changes use ONE `event.atomic_updates` transaction.
- Ordered same-time events allowed ONLY if EVERY intermediate state is valid.
- Topology/mode update applied exactly ONCE per event.
- Algebraic re-solve policy stated explicitly (right-topology re-solve on the
  final event at that timestamp).
- ONE public right-limit sample after the final event at that timestamp.
- No duplicate public timestamps.
- Ambiguous order fails closed (`ts_event_transition:ambiguousCoincident`).

### Correction 4 — Separate physical GFM control from numerical algebraic reference

**Preferred design (default):**
- Preserve ONE fixed numerical angle-gauge / reference constraint across
  all modes.
- GFM/GFL/SG mode changes alter DEVICE EQUATIONS / current injection only.
- Do NOT dynamically move vcon rows.
- Rename "reference handoff" events to "control/mode commit" events
  (`sg_open_and_gfm_mode_commit`, `sg_reclose_and_mode_commit`).

**If a dynamic vcon-row handoff is required, STOP and request separate
approval** because Track A supports only FIXED y-only vcon ownership
(`multimachine_ssa` B6 enforces `Jcon_x==0`).

### Correction 5 — Explicit mixed-resource equilibrium solver phase before mixed SSSA

The mixed equilibrium solver must solve, in-house:

```text
f(x, y, u, mode) = 0
g(x, y, Y, u, mode) = 0
```

plus dispatch / reference / limiter constraints for EACH candidate
configuration. **`composite_dae`'s internal MATPOWER PF is NOT sufficient**
to establish SG_OFF/GFM equilibria.

Specify: unknown ordering, Jacobian structure, residual form, conditioning
(rcond gate), initialization (warm-start from PF), failure IDs, and result
provenance (equilibrium fingerprint). This is a NEW production solver
(built from base MATLAB / audited primitives; no external nonlinear solver).

### Correction 6 — Source-gate for inactive dual-mode states

Frozen inactive states may create zero eigenvalues and invalidate the SSSA
selector. **Require a sourced tracking / shadow-controller rule OR an
explicit active-state reduction contract.** No manual zero-eigenvalue
deletion. If neither can be sourced, STOP at Phase 1.

### Correction 7 — Revised phase ordering

```text
Phase 0: preflight / checkpoint
Phase 1: source closure + autonomous freeze (no mandatory user pause)
Phase 2: generic scheduled+guard event architecture (synthetic tests)
Phase 3: persistent hybrid-state / rollback contract
Phase 4: mixed equilibrium / reference-gauge contract
Phase 5+: sourced GFL/VSG models through Phase 17
```

### Correction 8 — Phase 1 source gate (autonomous, no mandatory pause)

Phase 1 remains a hard mathematical/source gate. If every required item is
source-closed, freeze the profile, record the source matrix, commit C1, and
proceed autonomously to Phase 2. When several source-backed alternatives
exist, choose autonomously using the hierarchy in directive 3. Genuine stop
conditions (no verified source; only a source range with no normative
default; GFL↔GFM transfer or inactive-state behavior would have to be
invented; IEEE14 SG dynamics unsourced; 219 MW dispatch/energy/ramp contract
unclosable; synchronism thresholds/dwell/delays unsourced; candidate profiles
materially different and hierarchy does not identify one unambiguously;
mixed equilibrium infeasible; reference/gauge not square/full-rank/well-
conditioned) override unattended execution. When such a condition occurs: do
not guess, do not weaken the gate, preserve all reviewable commits, write an
evidence-backed handoff, report the exact gap and smallest user decision
needed, and stop once at the actual blocker.

---

## File ownership and allowlist (all phases)

**Authorized actions in Phase 0:**
- Read-only git/worktree audit (done).
- Create `feature/ieee14-auto-vsg-switching` worktree at
  `/home/birds/Documents/Power-flow-ieee14-ibr` from immutable `31a211d`.
- Compute SHA-256 of the two canonical files in the main worktree; copy
  ONLY those two; verify hashes; commit as C0.
- Rerun fresh Track A baseline (454/0/0 expected) to confirm the clean base.

**Authorized actions in Phase 1:**
- Fetch + inspect full-text primary sources (REGFM_B1 NREL 90260; Ding et al.
  83340; WECC generic RES; IEEE TR-121; NREL 87959).
- Write the equation/source matrix and frozen contract documents under
  `docs/project/` in the NEW worktree (e.g.
  `docs/project/IEEE14_IBR_EQUATION_SOURCE_MATRIX.md`,
  `docs/project/IEEE14_IBR_FROZEN_CONTRACT.md`).
- Commit as C1 (source/provenance + frozen contracts).

**Authorized actions in Phase 2–17 (sole integration owner, after Phase 1
source-closes):**
- Add clean-slate `+ibr/**` production models/contracts.
- Add explicitly IBR-named IEEE14 case/case-contract files under `+cases/**`.
- Add focused `tests/test_ibr_*.m` and `tests/test_ieee14_ibr_*.m`.
- Add IBR scripts/docs/provenance artifacts.
- Modify Track A shared `+stability/**` integration files ONLY as the sole
  integration owner and only when required by the canonical plan.
- Make reviewable phase commits.

**FORBIDDEN (all phases):**
- Edit/stage/commit dirty main-worktree user files.
- Modify Track A / Padiyar / report / adaptive worktrees.
- Recreate removed Track B worktree; pop/drop stash `eae0bcd`.
- `git reset --hard`, `git clean`, mass rewrite, amend Track A history.
- Push, merge, rebase, force-push, delete branches, change `main`.
- Import/register old Track B runtime; cherry-pick unsourced equations.
- External numerical solvers in production.
- Change SG legacy equations, tolerances, FD steps, timestep/event values,
  iteration caps, acceptance criteria, or adaptive default to force results.
- Use ASSUMED_DIAGNOSTIC values in production acceptance claims.
- Continue past a failed targeted/full-regression gate.

---

## Phase sequence

### Phase 0 — Preflight, checkpoint, integration ownership

**Work:**
1. Read-only audit (done above — recorded in Context).
2. Create `feature/ieee14-auto-vsg-switching` worktree at
   `/home/birds/Documents/Power-flow-ieee14-ibr` from immutable `31a211d`.
3. Checkpoint canonical plan + prompt: SHA-256 both originals in the main
   worktree; copy ONLY those two; verify hashes match; commit as C0.
4. Rerun fresh Track A baseline:
   ```matlab
   restoredefaultpath; cd('/home/birds/Documents/Power-flow-ieee14-ibr');
   pf_init_paths; r = runtests('tests','IncludeSubfolders',true);
   ```
   Expect 454/0/0.
5. Freeze allowlist (this plan).

**Exit gate:** no user work at risk; clean base identified; no push/merge/
history rewrite; baseline green.

### Phase 1 — Source audit, mathematical contract freeze, EXPLICIT USER APPROVAL (HARD GATE)

**Work:**
1. Fetch + inspect full-text primary sources (5 URLs).
2. Source-close every item below. If ANY cannot be source-closed without a
   new semantic choice, STOP and handoff.

   Source-closure checklist (all required, no ASSUMED_DIAGNOSTIC):
   1. GFL positive-sequence model + state order (REGC_B1 + REEC_B1 / Ding).
   2. VSG/VSM profile derived from REGFM_B1 (voltage-source-behind-impedance;
      VSM control block; measurement filters; voltage control).
   3. GFL↔VSG state transfer maps (BOTH directions) + inactive-state
      evolution rule (frozen / tracking / shadow-controller). Per correction 6:
      must avoid spurious zero eigenvalues; sourced tracking/shadow rule or
      explicit active-state reduction contract required.
   4. Current limiter + anti-windup algorithm on correct bases/frames.
   5. SG synchronism check thresholds (ΔV, Δf/slip, Δθ), dwell, timeout
      (IEEE PES TR-121).
   6. Delays: `T_up = T_detect+T_logic+T_controller`; `T_sg_min_off`;
      `T_settle = ln(1/ρ)/(−Ω_current)`; `T_minimum_hold`; `T_guard`;
      `T_lockout`; `ρ`.
   7. IEEE14 dynamic data for SG1 (H, D, X'd or full EMF6 reactances/time-
      constants). Case file has NONE; find a sourced IEEE14 dynamic dataset
      (IEEE PES reference / published benchmark) or STOP. Hardcoded
      H=5.0/D=0/X'd=0.30 defaults are UNSOURCED and forbidden.
   8. Dispatch / energy contract resolving the 219 MW post-trip deficit
      (pre-fault IBR schedules, post-trip reserve/participation, P/Q/current/
      energy/ramp limits, load-shed policy) — sourced or case-defined.
   9. Selection margin `gamma_req` (source/requirement/a-priori study).

3. Re-audit historical Track B against REGFM_B1 (evidence only; no promotion).
4. Write the equation/source matrix and frozen contract documents.
5. Classify every equation/parameter: SOURCE_VERBATIM / SOURCE_TRANSFORMED /
   CASE_DEFINED / PROJECT_DERIVED / NUMERICAL_METHOD. (ASSUMED_DIAGNOSTIC,
   UNSOURCED, DECISION_REQUIRED may NOT support production claims.)

**Exit gate (Phase 1 — user approval REQUIRED):**
- Authoritative equation/source matrix complete.
- No production equation `UNSOURCED`.
- Transfer maps closed (both directions); inactive-state rule sourced.
- All diagnostic assumptions excluded from production.
- **If all required items source-close:** freeze the profile, commit C1, and
  proceed autonomously to Phase 2 (no mandatory user pause). Use the
  autonomous selection hierarchy (directive 3) when alternatives exist.
- **If a genuine stop condition occurs** (any item unsourced, or hierarchy
  cannot resolve materially different candidates): STOP, write an evidence-
  backed handoff, report the exact gap and smallest user decision needed.

---

## Phase 2–17 (authorized after Phase 1 source-closes)

- **Phase 2 — Generic scheduled+guard event architecture (synthetic tests).**
  Implement `events.transitions(k)` (correction 1A) + guard-triggered
  transitions (correction 1B). Legacy `fault_on`/`fault_off` bit-identical
  adapter (AbsTol=0). Coincident semantics (correction 3). Synthetic tests.
- **Phase 3 — Persistent hybrid-state / rollback contract (correction 2).**
  TS driver sole mutator; immutable snapshot in extended `event_context`;
  rejected trials do not advance guard/dwell/delay/lockout/selector.
- **Phase 4 — Mixed equilibrium / reference-gauge contract (corrections 4, 5).**
  In-house `f=g=0` solver for each candidate configuration; fixed numerical
  angle-gauge across modes; control/mode commit events (not reference
  handoff).
- **Phase 5 — Sourced GFL model.** (Phase 4 of canonical plan.)
- **Phase 6 — REGFM_B1-derived VSG model.** (Phase 5 of canonical plan.)
- **Phase 7 — Dual-mode fixed-layout IBR + bumpless transfer.** (Phase 6.)
- **Phase 8 — IEEE14 dynamic case + dispatch/energy contract.** (Phase 3.)
- **Phase 9 — Mixed IEEE14 composite equilibrium.** (Phase 7.)
- **Phase 10 — Mixed SSSA + automatic selector.** (Phase 8.)
- **Phase 11 — Fixed-step no-fault hybrid TS.** (Phase 9.)
- **Phase 12 — Fault, SG trip, automatic GFM activation.** (Phase 10.)
- **Phase 13 — SG synchronism, reclose, index-based reselection.** (Phase 11.)
- **Phase 14 — Current limiting, anti-windup, physical FRT.** (Phase 12.)
- **Phase 15 — Multiple-GFM subset selection.** (Phase 13.)
- **Phase 16 — Adaptive-step hybrid TS.** (Phase 14.)
- **Phase 17 — Independent validation, report, readiness derivation.** (Phase 15.)

---

## Verification gates (all phases)

Phase 0: fresh Track A baseline 454/0/0; `test_no_external_solver_dependency`
green; no user work disturbed; no push/merge/history rewrite.

Phase 1: equation/source matrix complete; every production equation/parameter
classified; frozen contract document written; autonomous freeze or genuine
stop with handoff.

Phases 2–17: run targeted tests after each phase; full regression at declared
integration checkpoints; zero failed / zero incomplete; do NOT continue past
a failed gate.

Track A exact legacy gates must remain green (AbsTol=0) throughout:
`test_ts_strategy_equivalence` (2/2),
`test_ts_classical_strategy_equivalence` (3/3),
`test_ts_characterization_fixed` (3/3),
`test_sssa_contract` (10/10),
`test_ts_default_routing` (7/7),
`test_ts_adaptive_rollback` (2/2).
Legacy fault-only event cases bit-identical after the event-system extension.
Default stays FIXED. No external solver. No production `+ibr` auto-registration.

---

## Reviewable commit sequence

C0 canonical plan/prompt checkpoint (hash-verified) · C1 source/provenance +
frozen contracts · C2 clean Track A ABI alignment · C3 generic scheduled+guard
event architecture · C4 persistent hybrid-state/rollback · C5 mixed equilibrium
/reference-gauge · C6 GFL model/tests · C7 REGFM_B1-derived VSG model/tests ·
C8 dual-mode fixed layout/transfer tests · C9 IEEE14 case/dispatch contract ·
C10 mixed composite equilibrium · C11 mixed SSSA selector/index · C12 fixed
no-fault switching · C13 fault/SG-trip/GFM activation · C14 SG sync/reclose/
index-selected return modes/delays · C15 limiter/anti-windup fault acceptance ·
C16 multi-GFM subset selection · C17 adaptive hybrid routing/rollback · C18
full regression/provenance/report/handoff.

Mechanical ABI moves separate from new numerical behavior. Never amend/
rewrite Track A or historical Track B history. No push/merge.

---

## Stop conditions (Phase 0–1)

Stop and ask/report when:
- SG/IBR bus mapping not explicitly approved (it is: [1,2,3,6,8]).
- Post-trip dispatch/energy contract infeasible or unsourced (219 MW deficit).
- Any GFL/VSG/current-limit/reset/synchronism/delay equation lacks verified
  source/derivation (Phase 1 gate).
- IEEE14 dynamic data unsourced (case file has none; must find sourced dataset).
- A required delay/threshold would have to be guessed.
- SG "return" requires true cold-start model rather than breaker reclose.
- Inactive-state rule cannot be sourced and would create spurious zero
  eigenvalues (correction 6).
- A dynamic vcon-row handoff is required (correction 4 — Track A supports
  only FIXED y-only vcon).
- Multiple REGFM/VSM profiles / transfer-map policies / dispatch contracts /
  delay standards / synchronism policies remain unresolved — present as user
  decisions (correction 8).
- `origin/main` advances during verification.
- Action expands beyond approved allowlist.

When blocked: do NOT invent. Create/update an integration handoff in the new
branch with exact file:line evidence, attempted alternatives, completed
phases, test results, and the smallest user decision needed.
