# IEEE 14-Bus: 1 SG + 4 IBR Automatic GFL/VSG Mode-Switching Plan

**Document status:** CANONICAL CLEAN-SLATE PLAN, PLANNING ONLY — no runtime
implementation is authorized by this document alone.

**Primary study:** `cases.case_matpower6_case14`

**Target capability:** a fault causes the sole synchronous generator (SG) to
disconnect; an index-based controller automatically selects the required IBR
mode configuration; at least one selected IBR changes from grid-following
(`gfl`) to grid-forming VSG (`GFM`); the SG later resynchronizes and reconnects;
the post-reconnection IBR mode configuration is again selected by the index,
after source-based and stability-based delays.

**Date drafted:** 2026-07-13

---

## 1. Purpose

This plan turns the advisor's IEEE 14-bus requirement into an auditable
production-integration sequence. It covers:

- one SG and four inverter-based resources (IBRs);
- source-backed GFL and VSG mathematical models;
- a fixed-dimension dual-mode IBR state contract;
- in-house PF feasibility filtering;
- SSSA eigenvalue-based automatic mode selection;
- fixed-step TS fault, SG trip, VSG activation, and reference handoff;
- SG synchronism check and reconnection;
- index-based post-reconnection mode selection;
- switching delays, dwell, hysteresis, and fail-closed behavior;
- current limiting and anti-windup;
- multiple-GFM configurations;
- adaptive-step TS only after the fixed-step hybrid path is verified;
- independent validation, documentation, and readiness derivation.

The plan does not authorize external solvers in production, parameter fitting,
or promotion of an unsourced equation.

### 1.1 Clean-slate supersession decision

This plan is the canonical design authority for future IEEE14 IBR work. It
supersedes the implementation direction in the following historical artifacts:

```text
docs/project/plans/PLAN_IBR_VSG_DEVELOPMENT.md
docs/project/plans/IBR_PLAN.html
feature/ibr-vsg-models @ a684cd0
```

Those artifacts are preserved read-only as historical diagnostics and as a
record of rejected/source-gap assumptions. They are not deleted, rewritten, or
treated as a production baseline.

The new implementation must start from the verified generic Track A interface
foundation and primary sources. It must not cherry-pick the old Track B runtime
implementation by default. A small helper, test idea, convention, or derivation
may be reintroduced only after an independent line-by-line audit proves that it
matches the new source, state, sign, base, and interface contracts. Reuse is the
exception, not the starting assumption.

This is not an incremental repair of the old five-state VSG prototype. The new
target is a complete IEEE14 mixed-resource system whose GFL, VSG, automatic
selection, delays, SG trip, and SG reconnection are designed together.

---

## 2. Binding user decisions

The following decisions are binding unless the user explicitly revises them:

1. IEEE MATPOWER 14-bus is the primary integration case.
2. The system has one SG and four IBRs at the five original generator buses.
3. The grid-forming controller is a VSG/VSM implementation.
4. The exact IBR runtime mode enumeration is case-sensitive:

   ```matlab
   mode = 'gfl' | 'GFM' | 'tripped'
   ```

5. A plain GFL is not converted into a GFM by changing the PF bus type. A
   switchable IBR must contain both GFL and VSG capabilities from construction.
6. SG loss is the trigger; an index selects which IBR configuration to use.
7. PF is a feasibility/equilibrium gate, SSSA supplies the selection index, and
   TS validates the event sequence.
8. The SG returns after a declared interval, but breaker closure is permitted
   only after synchronism checks pass.
9. After SG reconnection, IBRs are not hard-coded to remain `GFM` and are not
   hard-coded to return to `gfl`. The index selects the target configuration.
10. Every mode change has an explicit delay contract. No delay value may be
    tuned after viewing results.
11. Fixed-step TS is the first canonical hybrid integration path. Adaptive-step
    integration is last.
12. The implementation is clean-slate from Track A; the old Track B runtime and
    old general VSG-first plan are historical evidence only.

---

## 3. Current repository baseline and ownership

### 3.1 Shared-core foundation

Track A is present in the separate worktree:

```text
branch:   feature/ibr-interface-foundation
worktree: /home/birds/Documents/Power-flow-ibr-interface
HEAD:     31a211d
status:   TRACK_A_IBR_INTERFACE_FOUNDATION_READY = PASS
```

It provides the generic foundations needed by this plan:

- typed exogenous input providers;
- model-bundle dispatch and validators;
- a single-owner composite DAE with canonical `YV-I` KCL;
- explicit voltage/reference constraint ownership;
- fixed/adaptive bundle routing;
- right-limit event algebraic re-solve;
- SSSA Schur reduction with paired residual/variable ownership.

It does not contain or execute an IBR model.

### 3.2 Historical IBR diagnostic prototype — evidence only

The historical Track B branch remains in Git without a worktree:

```text
branch:   feature/ibr-vsg-models
HEAD:     a684cd0
status:   diagnostic prototype; production integration NOT_STARTED
worktree: REMOVED on 2026-07-13 by explicit user request
```

Before removal, its four uncommitted synchronized launcher/plot changes were
preserved in:

```text
stash commit: eae0bcdf88eb05088ebde56d880e7e6fa65de581
stash message: checkpoint before removing obsolete Track B worktree (2026-07-13)
```

Historical files may be inspected without restoring the worktree, for example:

```bash
git show feature/ibr-vsg-models:+ibr/vsg_model.m
```

Do not recreate the removed Track B worktree for the new mission.

The existing `+ibr/vsg_model.m` is a historical five-state diagnostic VSG
prototype. It
does not contain a GFL model, dual-mode switching, integrated current limiting,
SG trip/reconnection, or IEEE14 automatic mode selection. Its source audit
predates the inspected UNIFI/WECC REGFM_B1 specification and must not be
promoted merely by adding a citation to nonmatching equations. It is not the
runtime base of the new implementation.

### 3.3 Current dirty-worktree guard

The main worktree and Track A worktree currently contain uncommitted
user-owned launcher/plot changes. Before any branch creation,
rebase, cherry-pick, merge, or history operation:

1. record `git status --short --branch` in every worktree;
2. hash every untracked/new file in scope;
3. checkpoint authorized user work on an isolated branch/commit, or create a
   clean integration worktree without carrying the dirty files;
4. never discard `run_ts.m`, `solve_case.m`, plot changes, or report assets;
5. assign one integration owner for shared `+stability/**` files.

No history operation is authorized by this plan alone.

---

## 4. Layer separation

The implementation must not conflate these roles:

| Layer | Role |
|---|---|
| PF bus type | Steady-state specified/solved variable ownership (`REF`, `PV`, `PQ`) |
| Dynamic device mode | Physical controller mode (`gfl`, `GFM`, `tripped`) |
| Algebraic reference | The single global angle/reference constraint used to remove rotational freedom |
| Protection/event state | SG breaker status, fault topology, reconnect permission, and pending mode commands |
| Selection index | A score calculated from a postulated equilibrium/configuration, not a replacement for protection |

A VSG may remain a physical voltage-forming source without being the unique PF
slack. Conversely, assigning `REF` to a GFL bus does not make that inverter
grid-forming.

---

## 5. IEEE14 case contract

### 5.1 Working device mapping

The working mapping follows the original MATPOWER generator buses:

| Device ID | External bus ID | Initial dynamic type | Capability |
|---|---:|---|---|
| `SG1` | 1 | SG online | SG breaker open/reclose |
| `IBR2` | 2 | `gfl` | `gfl`/`GFM`/`tripped` |
| `IBR3` | 3 | `gfl` | `gfl`/`GFM`/`tripped` |
| `IBR6` | 6 | `gfl` | `gfl`/`GFM`/`tripped` |
| `IBR8` | 8 | `gfl` | `gfl`/`GFM`/`tripped` |

This mapping must be explicitly confirmed before numerical implementation. No
code may infer it from struct ordering or assume bus row equals external bus ID.

### 5.2 Static-data limitation

`case_matpower6_case14` provides network and steady-state generator data only.
It does not provide complete SG, GFL, VSG, protection, energy-source, or
mode-transition parameters. Every added parameter must be one of:

- source-provided and cited;
- derived by a documented base/convention transformation;
- an a-priori `ASSUMED_DIAGNOSTIC` value excluded from production acceptance.

### 5.3 Active-power feasibility

The original case contains:

```text
total real load                         = 259.0 MW
bus-1 SG scheduled real power          = 232.4 MW
remaining IBR scheduled real power     =  40.0 MW
remaining aggregate IBR Pmax           = 440.0 MW
```

After `SG1` trips, the original remaining schedule is deficient by at least
approximately 219 MW plus losses. A PF slack must not silently hide this
deficit. Before any stability index is accepted, the case must declare:

- pre-fault IBR schedules;
- post-trip reserve and participation policy;
- active/reactive power limits;
- converter current limits;
- energy-source availability;
- ramp/response assumptions;
- load shedding, if required.

No dispatch may be adjusted merely to make a trajectory stable or match a
reference.

---

## 6. Device and state contracts

### 6.1 IBR runtime mode

The public runtime field is:

```matlab
device.mode = 'gfl' | 'GFM' | 'tripped';
```

Validation must reject case variation, unknown strings, empty values, and
unsupported transitions.

Transition scheduling uses metadata, not a fourth public mode:

```matlab
device.pending_mode
device.switch_request_time
device.switch_not_before
device.last_switch_time
device.selected_by_index
device.selection_snapshot_id
```

### 6.2 Fixed state dimension

TS may not change state-vector dimension at an event. Each switchable IBR must
have a fixed, construction-time state layout containing the states required by
both GFL and VSG capabilities:

```text
x_ibr = [x_gfl; x_vsg; x_shared_or_transition]
```

The design must specify, source, and test how inactive-branch states behave:

- held/frozen;
- continuously tracking the active branch;
- or evolved under a source-backed shadow-controller equation.

This choice is not yet authorized and is a Phase 1 source/contract gate.

### 6.3 Current injection ownership

Each device returns only positive current injection into the network:

```text
mode='gfl'    -> Iinj = I_gfl(...)
mode='GFM'    -> Iinj = I_vsg(...)
mode='tripped'-> Iinj = 0
```

The composite alone owns:

- interleaved bus-voltage `y`;
- external-bus mapping;
- topology/Y selection;
- KCL `g = YV - sum(Iinj)`;
- reference-row replacement;
- device state/input ranges.

No IBR may return or modify the global network residual.

### 6.4 Bumpless mode transfer

Every `gfl <-> GFM` transition requires a source-backed or explicitly derived
reset/transfer map. At minimum it must address:

- PLL angle/frequency versus VSG internal angle/frequency;
- active/reactive measurement-filter states;
- GFL current-controller integrators;
- VSG voltage-controller states;
- current injection continuity;
- finite right-limit residuals;
- inactive-state freezing/tracking;
- current-limit and anti-windup states.

The existing five-state VSG equilibrium initialization is not automatically a
valid switching reset map.

---

## 7. SG status and reconnection contract

### 7.1 Phase-1 interpretation

For the first implementation, “SG returns” means:

> The generator breaker opened while the machine remained represented and
> spinning; after a minimum off-time, the machine is resynchronized and its
> breaker is reclosed.

It does not mean a cold restart after turbine/excitation shutdown. A true unit
restart requires a separately sourced startup model and is out of this plan.

### 7.2 SG status

```matlab
sg.status = 'online' | 'tripped' | 'synchronizing';
```

The plan must define whether `tripped` means only stator/network disconnection
or also mechanical/excitation changes. Phase 1 assumes network disconnection
only unless a source says otherwise.

### 7.3 Synchronism check

After `t >= t_reconnect_earliest`, calculate the quantities on the two sides of
the open generator breaker:

\[
\Delta V = |V_{SG}|-|V_{bus}|,
\]

\[
\Delta f = f_{SG}-f_{bus},
\]

\[
\Delta\theta = \operatorname{atan2}
\left(\sin(\theta_{SG}-\theta_{bus}),
      \cos(\theta_{SG}-\theta_{bus})\right).
\]

Breaker closure is permitted only after sourced thresholds and a sourced or
approved dwell time are satisfied. The actual close instant may additionally
need breaker-close-time/slip prediction. No numerical threshold is frozen in
this plan.

If synchronism is not achieved before a declared timeout, the SG stays
disconnected and the run reports `SYNC_TIMEOUT`; it must not reset SG angle or
speed to force reconnection.

---

## 8. Automatic mode-selection index

### 8.1 Configuration definition

Let `z` denote system status/topology, including at least:

```text
z = SG_ON | SG_OFF
```

Let `m` be the ordered four-IBR mode vector. Examples:

```text
[gfl, gfl, GFM, gfl]
[GFM, gfl, GFM, gfl]
[gfl, gfl, gfl, gfl]
```

For every candidate `(z,m)`:

1. build the declared dispatch and reference ownership;
2. run in-house PF/equilibrium initialization;
3. reject infeasible P/Q/V/current/headroom configurations;
4. build the mixed-device DAE;
5. run the common SSSA Schur engine;
6. compute the index.

### 8.2 Spectral-abscissa index

For the reduced state matrix `A_z(m)`:

\[
\Omega_z(m) =
\max_{\lambda_i\ne\lambda_{ref}}
\Re\{\lambda_i(A_z(m))\}.
\]

The invariant reference mode is excluded by the explicit reference reduction,
not by manually deleting whichever eigenvalue looks closest to zero.

A candidate is locally asymptotically stable only when:

\[
\Omega_z(m)<0.
\]

Production selection requires an a-priori minimum margin:

\[
\Omega_z(m)\le-\gamma_{req},\qquad \gamma_{req}>0.
\]

`gamma_req` must come from a source, approved engineering requirement, or an
a-priori documented study. It may not be tuned after seeing candidate results.

### 8.3 Feasible set

\[
\mathcal F_z=
\left\{m:\begin{array}{l}
\text{PF/equilibrium converges},\\
P_{min}\le P_k\le P_{max},\\
Q_{min}\le Q_k\le Q_{max},\\
|I_k|\le I_{max},\\
V_{min}\le|V_b|\le V_{max},\\
J_{yy,red}\text{ is square and sufficiently nonsingular},\\
\text{all required energy/headroom constraints pass}
\end{array}\right\}.
\]

### 8.4 Selection policy

The proposed deterministic policy is lexicographic:

\[
m_z^*=\arg\min_{m\in\mathcal F_z,
\Omega_z(m)\le-\gamma_{req}}
\left(N_{GFM}(m),\Omega_z(m),\operatorname{ID}(m)\right).
\]

Interpretation:

1. use the smallest number of GFM devices that meets the required margin;
2. among equal-cardinality candidates, choose the most negative `Omega`;
3. break exact ties by stable device-ID order.

This lexicographic policy is a project design decision and must be explicitly
approved before implementation. It is not claimed to be printed in the NREL
source.

Constraints by SG status:

```text
SG_OFF: N_GFM >= 1
SG_ON:  N_GFM >= 0
```

Therefore, after SG reconnection:

- if all-`gfl` passes the required margin, the target may be all-`gfl`;
- if all-`gfl` fails, the index selects the minimum stable GFM subset;
- no unconditional “keep GFM” or “return all to GFL” rule is allowed.

### 8.5 Offline versus runtime use

SSSA requires an equilibrium. It must not be run against an arbitrary faulted
transient snapshot and called a stability margin. For the first implementation:

- enumerate and validate candidate tables before TS;
- store configuration, equilibrium fingerprint, eigenvalues, `Omega`, and
  feasibility evidence;
- at runtime, select from the validated table using current topology/status;
- use live guards and dwell conditions before committing a transition.

Online re-linearization under changing operating points is a later capability
requiring a separate contract.

---

## 9. Delay, dwell, and hysteresis policy

No universal switch delay is assumed. The system has several distinct delays.

### 9.1 GFL-to-GFM activation delay

\[
T_{up}=T_{detect}+T_{logic}+T_{controller}.
\]

These components come from protection/controller specifications or an
explicit case contract. Because an SG-off all-GFL island may have no physical
voltage/frequency reference, the candidate ranking must be precomputed and the
GFM activation/reference handoff must be coordinated with the SG breaker event.

The implementation must not insert an arbitrary post-trip waiting interval that
makes the algebraic problem singular. If a nonzero dead interval is required by
the source, the mathematical behavior of the all-GFL interval must be explicit
and tested.

### 9.2 SG reconnect delay

```text
t_reconnect_earliest = t_sg_trip + T_sg_min_off
```

`T_sg_min_off` is a case/protection/plant input. Reaching this time only enables
synchronism checking; it does not close the breaker.

### 9.3 Post-reconnection IBR mode delay

Let `Omega_current < 0` be the dominant real part for the currently active,
SG-online configuration during the hold interval. The linear modal envelope is
`exp(Omega_current*t)`. Requiring the envelope to fall to a declared fraction
`rho` gives the project derivation:

\[
T_{settle}=
\frac{\ln(1/\rho)}{-\Omega_{current}}.
\]

Then:

\[
T_{down}=\max(T_{minimum\_hold},T_{settle}).
\]

`rho` and `T_minimum_hold` must be declared before results. If
`Omega_current >= 0`, this formula is invalid; the selector must find another
stable current/target configuration or fail closed.

### 9.4 Guard dwell and lockout

After `T_down`, all transition guards must remain true for `T_guard`. After a
successful mode switch, ordinary switching is inhibited until:

```text
t >= last_switch_time + T_lockout
```

Protection trips may override lockout. Values are source/requirement inputs and
must not be tuned from plots.

---

## 10. Event chronology and atomicity

The target event vocabulary is:

```text
fault_on
sg_trip_request
ibr_gfm_enable_request
sg_open_and_gfm_reference_handoff
fault_off
sg_reconnect_enable
sg_sync_pass
sg_reclose_and_reference_handback
ibr_mode_reselection_request
ibr_mode_commit
```

The event owner must distinguish:

- topology changes;
- device connection changes;
- dynamic mode changes;
- reference-row ownership changes;
- time-triggered versus state-triggered events.

Track A currently supports explicit `fault_on`/`fault_off` identities and rejects
ambiguous coincident events. This plan requires either:

1. a single source-backed compound event whose updates are atomic; or
2. a generic ordered event list with an explicit order contract.

It is forbidden to perturb event time by `t +/- eps` or to invent a small time
offset solely to evade coincident-event validation.

At every accepted event boundary:

1. the arrival step uses the left configuration;
2. the event applies exactly once;
3. state reset/transfer follows the approved map;
4. topology, device modes, and reference ownership move atomically;
5. algebraic `y` is solved under the right configuration;
6. the public sample is the right-limit sample;
7. the next step starts right-consistent.

---

## 11. PF, SSSA, and TS responsibilities

### 11.1 PF/equilibrium

PF and equilibrium initialization must:

- use the in-house Newton PF;
- preserve external bus IDs;
- apply the declared dispatch/participation policy;
- enforce device limits for feasibility classification;
- distinguish dynamic GFL/GFM mode from PF bus role;
- reject a pure-GFL island with no physical voltage-forming source;
- produce a deterministic fingerprint used by the SSSA lookup table.

### 11.2 SSSA

SSSA must:

- use the same device equations as TS;
- verify equilibrium residuals before linearization;
- build `Jxx`, `Jxy`, `Jyx`, `Jyy` consistently;
- use paired `vcon_vars`/`vcon_rows` ownership;
- use backslash, never `inv`/`pinv` to hide algebraic rank defects;
- compute and store full eigenvalue evidence;
- use deterministic reference-mode handling and mode pairing;
- calculate `Omega` without manual eigenvalue deletion.

### 11.3 TS

Fixed-step TS must first demonstrate:

- no-disturbance equilibrium hold;
- deterministic scheduled mode switching without a fault;
- fault landing and clearing;
- SG breaker trip and GFM reference handoff;
- SG synchronism check and reclose;
- index-based post-reconnect mode selection;
- no early switch before delays/dwell;
- state/current/residual continuity at accepted boundaries;
- fail-closed behavior when no valid target exists.

The no-limiter fixed-step fault run is structural evidence only. It is not a
physical fault-ride-through acceptance result.

---

## 12. Equation and source plan

### 12.1 Primary sources already identified

1. **UNIFI/WECC REGFM_B1 VSM GFM specification**
   - voltage source behind impedance;
   - VSM control block;
   - power/voltage/current measurement filters;
   - voltage control;
   - P/Q priority and transient current limiting.
   - <https://www.nrel.gov/docs/fy24osti/90260.pdf>

2. **Ding et al., dynamically configurable GFM/GFL controls**
   - separate GFM and GFL models;
   - GFL/GFM mode transition;
   - frozen integral-state transition concept;
   - spectral-abscissa stability margin;
   - evaluation of mode combinations.
   - <https://www.nrel.gov/docs/fy23osti/83340.pdf>

3. **WECC generic renewable models**
   - REGC current-source converter-interface role;
   - REEC unit electrical controls;
   - REPC plant-level control distinctions.
   - <https://www.wecc.org/sites/default/files/documents/meeting/2024/Summary%20of%202nd%20Generation%20Generic%20RES%20Models%20%20Rev5.pdf>

4. **IEEE PES TR-121, generator synchronizing practices**
   - synchronizing-system and out-of-phase closing requirements.
   - <https://resourcecenter.ieee.org/publications/technical-reports/pes_tp_tr121_psrc_42924>

5. **NREL GFM dispatch in grid-connected/islanded operation**
   - GFM/SG/GFL coexistence and power-sharing context.
   - <https://www.nrel.gov/docs/fy24osti/87959.pdf>

### 12.2 Required provenance classifications

Every implemented relationship must be recorded as one of:

- `SOURCE_VERBATIM`;
- `SOURCE_TRANSFORMED`;
- `CASE_DEFINED`;
- `PROJECT_DERIVED`;
- `NUMERICAL_METHOD`;
- `ASSUMED_DIAGNOSTIC`;
- `UNSOURCED`;
- `DECISION_REQUIRED`.

Only the first five support production claims. A source that contains a
different controller structure cannot be used to relabel the existing custom
equation as sourced.

### 12.3 Mandatory unresolved source work

Before production implementation, close or explicitly fence:

- the exact positive-sequence GFL state equations;
- the exact VSG subset/profile derived from REGFM_B1;
- all per-unit and inverter/system-base transformations;
- GFL-to-VSG and VSG-to-GFL state transfer;
- inactive-state evolution;
- SG open-breaker mechanical/electrical behavior;
- synchronism thresholds and dwell;
- protection/controller switching delays;
- current limiter and anti-windup;
- dispatch/energy/ramp policy;
- required `gamma_req`, `rho`, guard, and lockout requirements.

---

## 13. Proposed architecture and file ownership

Names below are clean-slate proposals, not an implementation allowlist. The
implementation owner must audit existing functions before freezing names. The
new `+ibr/` package is created on the new integration branch from sourced
contracts; it is not populated by wholesale copying from the historical Track B
worktree.

### 13.1 IBR-owned candidates

```text
+ibr/gfl_model.m
+ibr/regfm_b1_vsg_model.m
+ibr/dual_mode_ibr.m
+ibr/ibr_mode_transfer.m
+ibr/ibr_mode_schema.m
+ibr/ibr_parameter_provenance.m
```

### 13.2 Case candidates

```text
+cases/case_ieee14_1sg_4ibr_auto_vsg.m
+cases/ieee14_ibr_dispatch_contract.m
```

### 13.3 Shared integration candidates

```text
+stability/select_ibr_mode_configuration.m
+stability/build_mixed_resource_bundle.m
+stability/ts_hybrid_event_manager.m
+stability/sg_synchronism_check.m
```

Any edit under `+stability/**`, PF dispatch, launchers, or shared case schema
requires the single integration owner defined by `TRACK_COORDINATION.md`.

### 13.4 Test candidates

```text
tests/test_ibr_gfl_model.m
tests/test_ibr_regfm_b1_vsg.m
tests/test_ibr_dual_mode_transfer.m
tests/test_ieee14_ibr_pf_feasibility.m
tests/test_ieee14_ibr_sssa_selector.m
tests/test_ieee14_ibr_ts_trip_handoff.m
tests/test_ieee14_ibr_sg_reconnection.m
tests/test_ieee14_ibr_switch_delay.m
tests/test_ieee14_ibr_current_limit.m
tests/test_ieee14_ibr_adaptive.m
```

---

## 14. Full implementation phases

## Phase 0 — Preflight, checkpoint, and integration ownership

### Work

1. Read repository `AGENTS.md`, current handoff, coordination document, Track A
   handoff, Track B source audit, and both existing IBR plans.
2. Record all worktrees, branches, HEADs, dirty files, untracked files, and
   origin/main race state.
3. Preserve/checkpoint user-owned launcher, plotting, and report work.
4. Assign one integration owner.
5. Create a clean integration branch/worktree only after checkpoint approval.
6. Freeze a file allowlist and forbidden list.

### Exit gate

- no user work is at risk;
- shared-file ownership is unambiguous;
- clean integration base is identified;
- no push/merge/history rewrite occurred without approval.

---

## Phase 1 — Source audit and mathematical contract freeze

### Work

1. Re-audit Track B against REGFM_B1 and the dynamic GFL/GFM paper.
2. Select the exact VSG model profile; do not retain a custom voltage loop if it
   cannot be transformed from the source.
3. Select the exact GFL positive-sequence model and its state order.
4. Freeze state, algebraic, input, parameter, sign, reference-frame, current,
   power, and per-unit contracts.
5. Derive all system-base/inverter-base transformations.
6. Source or fence both mode-transfer maps.
7. Freeze the selector objective, margin definition, and deterministic tie-break.
8. Source/approve switch-delay, synchronism, dwell, and lockout inputs.
9. Record every unresolved item as `NOT_READY`; no equation promotion by analogy.

### Exit gate

- authoritative equation/source matrix complete;
- no production equation is `UNSOURCED`;
- mode-transfer/reset maps are dimensionally and conventionally closed;
- all remaining diagnostic assumptions are clearly excluded from production
  acceptance.

---

## Phase 2 — Align Track A foundation and Track B model work

### Work

1. Establish the clean integration base containing verified Track A interfaces.
2. Do not cherry-pick the historical Track B runtime. Create the new IBR package
   from the frozen Phase 1 contracts and primary sources.
3. Reuse a historical helper or derivation only after an independent audit and
   an explicit provenance record; otherwise reimplement it cleanly.
4. Resolve bundle/composite/device ABI differences without duplicating kernels.
5. Verify fixed state/input/y ordering.
6. Preserve all SG legacy paths bit-identically when the IBR bundle is absent.

### Exit gate

- one composite owner;
- one canonical TS step kernel;
- one Schur SSSA engine;
- no production `+ibr` auto-registration or path scanning;
- no unaudited code copied from the historical Track B runtime;
- legacy SG AbsTol=0 gates pass.

---

## Phase 3 — IEEE14 dynamic case and dispatch/energy contract

### Work

1. Create the explicit device map for buses 1, 2, 3, 6, and 8.
2. Preserve the original network/base data.
3. Add sourced SG/GFL/VSG data or label diagnostic data explicitly.
4. Define pre-fault and post-trip real/reactive schedules.
5. Define power-sharing/participation and converter ratings.
6. Define fault, SG trip, minimum-off, reconnect-enable, timeout, and simulation
   times from source/case requirements.
7. Define load model and energy availability.
8. Add deterministic input-contract fingerprinting.

### Exit gate

- in-house pre-fault PF converges;
- every source/limit is traceable;
- aggregate post-trip supply and reserves are feasible;
- no PF slack silently violates device limits.

---

## Phase 4 — Source-backed GFL model

### Work

1. Implement the selected GFL model with explicit PLL and P/Q-current-control
   contracts.
2. Implement equilibrium initialization from the in-house PF.
3. Implement positive current injection into the shared network.
4. Implement analytic or verified FD Jacobian support.
5. Add PLL lock, power-sign, frame, base, and weak-grid tests.
6. Reject pure-GFL island initialization.

### Exit gate

- single-GFL/infinite-bus equilibrium holds;
- no-disturbance TS holds;
- SSSA and TS share equations;
- pure-GFL island fails closed.

---

## Phase 5 — REGFM_B1-derived VSG model

### Work

1. Implement the exact approved REGFM_B1-derived model profile.
2. Implement voltage-source-behind-impedance current injection.
3. Implement equilibrium initialization and base conversion.
4. Keep current limiting disabled only for the explicitly structural slice.
5. Add power/current identities, equilibrium, Jacobian, and source-mapping tests.

### Exit gate

- single-VSG/infinite-bus PF/init/SSSA/fixed-TS tests pass;
- no unexplained drift;
- every equation maps to source/transformation/code/test.

---

## Phase 6 — Fixed-layout dual-mode IBR and bumpless transfer

### Work

1. Construct fixed state ranges for GFL and VSG branches.
2. Implement exact mode validation.
3. Implement sourced inactive-state behavior.
4. Implement `gfl -> GFM`, `GFM -> gfl`, and `any -> tripped` transitions.
5. Add pending-mode, delay, guard, and lockout metadata.
6. Assert current injection and algebraic residual continuity.
7. Test repeated switching without state-size or range changes.

### Exit gate

- state dimension/order is invariant;
- both switch directions pass reset-map oracles;
- no NaN/Inf/current jump beyond the declared contract;
- premature and illegal transitions fail closed.

---

## Phase 7 — Mixed IEEE14 composite equilibrium

### Work

1. Assemble `SG1 + IBR2 + IBR3 + IBR6 + IBR8` through the Track A composite.
2. Verify deterministic external-bus mapping and device ordering.
3. Verify bus-by-bus KCL.
4. Verify reference-row replacement exactly once.
5. Build pre-fault, SG-off, and SG-on candidate equilibria.
6. Verify P/Q/current/headroom constraints for every candidate.

### Exit gate

- all declared candidate equilibria either pass with evidence or fail with a
  stable error ID;
- pure-GFL SG-off configuration is rejected;
- shuffled device order produces mapped-equivalent results.

---

## Phase 8 — Mixed SSSA and automatic configuration selector

### Work

1. Build SSSA models from the same composite equations.
2. Enumerate ordered mode configurations for `SG_OFF` and `SG_ON`.
3. Apply feasibility gates before eigenanalysis.
4. Compute `Omega` and full eigenvalue evidence.
5. Implement the approved lexicographic selection policy.
6. Store deterministic lookup tables keyed by topology/status and equilibrium
   fingerprint.
7. Add negative tests for no feasible/stable target, singular Schur, duplicate
   device IDs, and stale fingerprints.

### Exit gate

- analytic/synthetic selector oracle passes;
- candidate order and device-list shuffle do not change selected IDs;
- no manual eigenvalue deletion;
- the selector fails closed when all candidates violate the required margin.

---

## Phase 9 — Fixed-step no-fault hybrid TS

### Work

1. Run the mixed pre-fault equilibrium with all IBRs `gfl` and SG online.
2. Run fixed-step no-disturbance TS.
3. Exercise scheduled `gfl <-> GFM` switching while SG remains online.
4. Verify left/right event samples, delay enforcement, state transfer, and
   algebraic re-solve.
5. Verify exact legacy SG paths remain unchanged when the mixed bundle is absent.

### Exit gate

- equilibrium hold and scheduled-switch tests pass;
- no duplicate timestamps;
- no early switch;
- right-limit output and residual contracts pass.

---

## Phase 10 — Fault, SG trip, automatic GFM activation

### Work

1. Add named fault and SG-trip events.
2. Use the prevalidated `SG_OFF` selector result.
3. Enforce sourced `T_up` and coordinated activation/opening semantics.
4. Commit selected `gfl -> GFM` modes and move reference ownership atomically.
5. Re-solve algebraic state under the right topology/mode.
6. Verify nonselected IBR modes remain unchanged.
7. Exercise failure paths: no candidate, stale index, delayed activation,
   infeasible dispatch, and event collision.

### Exit gate

- fixed-step structural TS reaches the post-trip interval;
- at least one VSG/reference exists whenever SG is disconnected;
- selected IDs match the SSSA table;
- no hard-coded bus selection;
- this phase makes no physical fault-ride-through PASS claim without limiter.

---

## Phase 11 — SG synchronism, reclose, and index-based reselection

### Work

1. Preserve SG disconnected-state dynamics according to the approved contract.
2. Enable synchronism checks only after minimum off-time.
3. Enforce voltage, frequency/slip, phase-angle, dwell, timeout, and breaker-close
   contracts.
4. Reclose SG without resetting angle/speed to the bus.
5. Return the single algebraic reference to SG atomically.
6. Select the `SG_ON` target mode vector from the index table.
7. Derive/apply `T_down` from the approved current-mode `Omega`, `rho`, hold,
   guard, and lockout rules.
8. Commit only the index-selected IBR transitions.
9. Test all-`gfl`, one-GFM, and multi-GFM post-return outcomes.

### Exit gate

- SG never recloses outside synch-check limits;
- index, not a hard-coded policy, determines post-return modes;
- no IBR changes before delay/dwell;
- sync timeout and unstable-target paths fail closed;
- reference ownership is replaced exactly once.

---

## Phase 12 — Current limiting, anti-windup, and physical fault acceptance

### Work

1. Implement the exact sourced current-limit algorithm.
2. Implement P/Q priority and transient limiting on correct bases/frames.
3. Implement source-backed anti-windup and recovery.
4. Integrate limiter state/events with both GFL and VSG modes.
5. Re-run the fault/trip/reconnect sequence.
6. Add current, voltage, energy, and controller-state diagnostics.

### Exit gate

- current never silently exceeds the declared contract;
- limiter engagement/release is deterministic and rollback-safe;
- anti-windup tests pass;
- the fixed-step fault scenario may be considered a production candidate only
  after all source/limit/energy gates pass.

---

## Phase 13 — Multiple-GFM automatic subset selection

### Work

1. Enumerate all permitted nonempty `SG_OFF` GFM subsets and permitted `SG_ON`
   subsets.
2. Verify multiple-VSG droop/equilibrium sharing.
3. Ensure exactly one algebraic reference while multiple physical GFMs operate.
4. Apply the same feasibility/index/delay policy.
5. Test leader loss and reselection.

### Exit gate

- selected subset is deterministic and satisfies the required margin;
- sharing follows equations, not hard-coded targets;
- no multiple-slack or hidden-PV approximation is claimed as a droop equilibrium.

---

## Phase 14 — Adaptive-step hybrid TS

### Work

1. Route the verified mixed bundle through the canonical adaptive driver.
2. Preserve exact event landing and named/atomic event semantics.
3. Verify rollback of modes, pending commands, delays, limiter states, and
   diagnostics on rejected trials.
4. Compare fixed/adaptive accepted public trajectories without changing
   tolerances or event definitions.

### Exit gate

- structural and numerical adaptive tests pass;
- rejected trials cause no external state mutation;
- production default remains fixed unless separately approved;
- no adaptive-default readiness claim is inferred from this phase.

---

## Phase 15 — Independent validation, report, and readiness derivation

### Work

1. Run fresh targeted tests and the full repository regression.
2. Run timestep and FD convergence studies declared a priori.
3. Validate PF/SSSA/TS consistency and event residuals.
4. Compare against an independent analytical, literature, or EMT/validated
   reference only after exact input-contract mapping.
5. Generate code-produced tables/figures and provenance manifests.
6. Document mismatches honestly.
7. Audit production path for external solver dependencies.
8. Audit changed files against the approved allowlist.

### Exit gate

- full regression: zero failed, zero incomplete;
- legacy SG mechanical equivalence gates remain AbsTol=0 where declared;
- every production equation and parameter is source/derivation traceable;
- every selection and delay decision is reproducible;
- no external solver is on the production path;
- final readiness statuses are computed from evidence, not predeclared.

---

## 15. Required test matrix

### 15.1 Model-level

- GFL PLL lock and P/Q sign;
- VSG equilibrium and voltage-source current identity;
- per-unit base conversions;
- analytic/FD Jacobian agreement;
- inactive-state behavior;
- both bumpless transfer directions;
- exact mode-schema validation;
- current limiter and anti-windup.

### 15.2 PF/equilibrium

- pre-fault IEEE14 equilibrium;
- every `SG_OFF` candidate;
- every permitted `SG_ON` candidate;
- P/Q/V/current/headroom limits;
- pure-GFL island rejection;
- infeasible dispatch rejection;
- external bus-ID mapping;
- shuffled device order.

### 15.3 SSSA/index

- synthetic analytic eigenvalue oracle;
- `Omega` calculation;
- explicit reference-mode reduction;
- deterministic tie-break;
- mode-vector enumeration;
- stale lookup fingerprint rejection;
- all-unstable/no-feasible fail-closed;
- one- and multi-GFM selection.

### 15.4 TS/events

- no-disturbance hold;
- fault landing and clearing;
- no event-time perturbation;
- SG trip and GFM handoff;
- no early switch before `T_up`;
- SG sync pass/fail/timeout;
- no forced SG state reset;
- index-based post-return mode target;
- eigenvalue-derived `T_down`;
- dwell and lockout;
- right-limit public sample;
- exact one-time reference replacement;
- limiter engagement/release;
- fixed/adaptive parity and rollback.

### 15.5 Negative/fail-closed

- unknown mode string or wrong case;
- duplicate device ID or bus ownership;
- missing GFM candidate while SG off;
- PF converges only by violating device limits;
- singular/ill-conditioned reduced `Jyy`;
- no target satisfying `gamma_req`;
- coincident unordered events;
- stale or mismatched index table;
- reconnect outside sync limits;
- delay/guard metadata missing;
- nonfinite/reset-map output;
- state dimension changes at an event;
- external solver dependency.

---

## 16. Verification commands

Final commands must be adapted to the approved integration worktree, but the
minimum gate is:

```matlab
restoredefaultpath;
cd('<approved-integration-worktree>');
pf_init_paths;

r_target = runtests({ ...
    'tests/test_ibr_gfl_model.m', ...
    'tests/test_ibr_regfm_b1_vsg.m', ...
    'tests/test_ibr_dual_mode_transfer.m', ...
    'tests/test_ieee14_ibr_pf_feasibility.m', ...
    'tests/test_ieee14_ibr_sssa_selector.m', ...
    'tests/test_ieee14_ibr_ts_trip_handoff.m', ...
    'tests/test_ieee14_ibr_sg_reconnection.m', ...
    'tests/test_ieee14_ibr_switch_delay.m'});

r_all = runtests('tests','IncludeSubfolders',true);
```

Also run:

```matlab
r_ext = runtests('tests/test_no_external_solver_dependency.m');
```

Required result: zero failed and zero incomplete. Counts must be reported from
the fresh run and never copied from an old handoff.

---

## 17. Commit strategy

Commit names are illustrative; exact hashes are never predeclared.

1. source/provenance contract and decision record;
2. clean integration ABI alignment;
3. IEEE14 case/dispatch contract;
4. source-backed GFL model and tests;
5. REGFM_B1-derived VSG model and tests;
6. fixed-layout dual-mode device and transfer tests;
7. composite PF/equilibrium integration;
8. mixed SSSA selector/index;
9. fixed no-fault TS switching;
10. fault/SG-trip/GFM handoff;
11. SG synchronism/reclose/index-based return modes;
12. limiter/anti-windup fault acceptance;
13. multi-GFM selection;
14. adaptive hybrid path;
15. regression, provenance, report, and handoff.

Mechanical ABI moves must remain separate from new numerical behavior. Do not
amend/rewrite established Track A/Track B history.

---

## 18. Stop conditions

Stop and ask the user when:

- the SG/IBR bus mapping is not explicitly approved;
- the post-trip dispatch/energy contract is infeasible or unsourced;
- a GFL/VSG/current-limit/reset equation lacks a verified source/derivation;
- a required delay or threshold would have to be guessed;
- SG “return” requires a true cold-start model rather than breaker reclose;
- a mode transition changes state dimension/order;
- all candidate configurations fail PF or the required SSSA margin;
- reference ownership cannot be square/full rank;
- event ordering cannot be represented atomically/deterministically;
- a change overlaps another worktree/agent's shared-file ownership;
- a legacy SG path changes by AbsTol greater than zero where exact equivalence
  is required;
- agreement improves only after changing physical/numerical parameters;
- a requested action expands beyond the approved allowlist;
- origin/main advances during final verification.

Do not relax a threshold, alter a source value, change a timestep, or hide a
failure to continue.

---

## 19. Non-goals

- EMT semiconductor/PWM switching;
- harmonic studies;
- vendor-specific black-box reproduction;
- true SG cold start and turbine startup sequencing;
- automatic relay-setting design without a sourced protection mission;
- incrementally patching or promoting the historical five-state Track B VSG
  prototype as the new production model;
- parameter optimization against desired plots;
- external solver use in production;
- adaptive-step default switch;
- unqualified equivalence to PSAT/PGAz or a paper plot;
- claiming a PF `REF` assignment alone implements GFM behavior.

---

## 20. Readiness milestones

Readiness must be derived in stages:

```text
IEEE14_IBR_EQUATION_CONTRACT_READY
IEEE14_MIXED_PF_SSSA_READY
IEEE14_AUTO_GFM_FIXED_TS_STRUCTURAL_READY
IEEE14_SG_RECONNECTION_AND_INDEX_RETURN_READY
IEEE14_CURRENT_LIMITED_FAULT_RIDE_THROUGH_READY
IEEE14_MULTI_GFM_SELECTION_READY
IEEE14_ADAPTIVE_HYBRID_READY
IBR_PRODUCTION_INTEGRATION_READY
```

No earlier milestone implies a later one. In particular:

- structural fixed-step switching without a limiter is not fault-ride-through
  readiness;
- synthetic/diagnostic parameters are not production readiness;
- an SSSA-stable configuration does not imply transient stability;
- visually similar curves do not establish validation equivalence.

---

## 21. Definition of done

The complete mission is done only when a clean, committed, in-house run can:

1. initialize the declared IEEE14 one-SG/four-IBR operating point;
2. produce the complete PF-feasible SSSA mode-index table;
3. simulate the declared fault with exact event landing;
4. trip/disconnect the SG according to the case contract;
5. automatically select and activate the required VSG subset by index after
   sourced delay/coordination;
6. maintain exactly one algebraic reference with correct physical GFM modes;
7. enforce current/energy/controller limits;
8. enable SG reconnection only after synchronism checks and dwell;
9. reclose SG without forcing its dynamic state;
10. select the SG-online IBR target configuration by index;
11. enforce eigenvalue/source-based delay, guard dwell, and lockout before
    committing post-return IBR mode changes;
12. continue fixed-step TS with finite states and accepted residuals;
13. reproduce the behavior deterministically;
14. pass targeted and full regressions with zero failed/incomplete;
15. preserve all legacy SG numerical contracts;
16. provide equation, parameter, event, index, delay, result, and Git provenance;
17. report every remaining limitation honestly;
18. derive, rather than assume, final production readiness.
