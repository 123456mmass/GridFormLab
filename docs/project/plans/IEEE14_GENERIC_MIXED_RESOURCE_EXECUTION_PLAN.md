# Case-Agnostic Mixed-Resource IBR Engine — IEEE14 First Mission + Generic Layer

## Context

This is a **substantial revision** of the IEEE14 1-SG + 4-IBR mission plan. Three drivers
force the re-architecture (all surfaced this session):

1. **Singular-Jacobian root cause is NOT the angle reference.** Phase B diagnostics (Explore
   agent) proved RCOND=NaN (not RCOND≈0). A rank-deficient but finite matrix gives RCOND≈1e-16,
   never NaN. NaN means the Jacobian matrix contains NaN entries propagated from the residual
   evaluation. The most concrete demonstrable bug is a **struct provenance subfield mismatch**
   at `build_ieee14_sg_ibr_devices.m:53` — `sg_composite_device.provenance` has 8 fields,
   `dual_mode_ibr_model.provenance` has 10 different fields; MATLAB struct-array stacking with
   mismatched subfield names either errors or silently corrupts fields. The angle-only vcon is
   structurally sound (SG1 delta = internal-EMF rotor angle relative to bus voltage, NOT the
   bus angle itself — no redundancy with Im(V1)=0).

2. **User architectural directive: case-agnostic + heterogeneous mixed-resource + index-based.**
   The engine must NOT embed IEEE14 bus IDs, one-SG, four-IBR, fixed-bus-IDs, "SG_ON→all-GFL",
   or "SG_OFF→need GFM" assumptions. It must support an arbitrary mixture at one time: multiple
   online/offline SGs, GFL-only IBRs, GFM-only IBRs, dual-mode IBRs, tripped/limited resources.
   Mode selection must be decided by **real resource indices**, not caller-supplied modes or
   fixed bus numbers. After IEEE14 passes, sequential validation profiles (IEEE9, RTS-24,
   Padiyar) are a **separate future mission** — but the engine must be case-agnostic now.

3. **User directive: add an IBR Simulation route to `solve_case.m`.** A 4th analysis type
   (after pf/sssa/ts) with interactive dialog + non-interactive form. Immutable case data
   (network/resources/capabilities/limits) is separated from runtime scenario options (count,
   selection, modes, fault, SG trip, timestep). Reconnect is requested-time (earliest) +
   synchronism gates → actual reclose, not a forced time-based close.

**User decisions (this session):** Generic-first ordering; "24 bus" = RTS-24
(`case_ieee_rts24_pgaz`, sourced classical dynamics IEEE RTS-1996 Table 15); multi-case
validation is a separate future mission but engine must be ready for it.

**Verified state on `main` HEAD `42e2dea` (synced to origin, 616/616 regression):**
- Generic core ALREADY arbitrary-N: `composite_dae.m` (bus_map via `find(bus_ids==dev.bus_id)`,
  per-device state offsets, current-injection loop over device index), `ts_hybrid_state_init.m`
  (keyed by string device_id, reads `device.initial_mode/initial_online`, loop over devices),
  `multimachine_ssa.m` (case-agnostic Schur + COI `reduce_coi` loops `k=2:ng`),
  `composite_newton.m` (agnostic `residual_fn(z)`).
- Phase 5–9 DONE & committed: `gfl_model.m` (6-state), `regfm_b1_vsg_model.m` (11-state,
  SOURCE_VERBATIM), `dual_mode_ibr_model.m` (15-state superset, decay-to-warmstart λ=1e-3),
  `build_ieee14_ibr_devices.m` (4 IBRs).
- Phase B code WRITTEN but UNCOMMITTED + not passing: `sg_composite_device.m`,
  `sg_stator_current.m`, `composite_newton.m`, `build_ieee14_sg_ibr_devices.m` (untracked);
  `mixed_equilibrium_solve.m`, `dual_mode_ibr_model.m`, `test_ieee14_1sg_4ibr_phase4.m` (modified).
- 6 files DO NOT EXIST: `ts_simulate_composite`, `composite_sssa_model`, `ibr_config_selector`,
  `transfer_maps`, `synchronism_guard`, `resource_*` selector.
- Event/hybrid infra MERGED + tested (32 tests): `ts_evaluate_guards`, `ts_event_transition`,
  `ts_apply_transition`, `ts_prevalidate_transitions`, `ts_hybrid_state_init`,
  `ts_hybrid_state_snapshot`, `ts_topology_at`.
- `solve_case.m` is a clean dispatcher (pf/sssa/ts with uniform pattern: analysis types →
  `case_registry(analysis)` → `merge_options` → `prompt_*_options`/`parse_*_dialog` →
  non-interactive form `solve_case('analysis','ts','case',id,'options',opt)`).
- Sourced dynamic data EXISTS for: RTS-24 (classical), Padiyar 2-area (model 1.1+AVR),
  Kundur 2-area (6th-order). IEEE9 (WSCC) has NO sourced dynamics. No IEEE24 case exists.

**AGENTS.md/CLAUDE.md mandate:** equation-first in-house MATLAB; no external solver in
production; no tuning after results; fixed state dimension across events; one numerical angle
gauge per connected island; rejected adaptive trials do not advance state; preserve legacy
bit-identity; single-owner shared files.

## Architecture: 3 layers

### Layer 1 — Generic engine (arbitrary-N, heterogeneous, index-based)

No IEEE14 IDs, no one-SG, no four-IBR, no fixed-bus, no "SG_ON→all-GFL" assumptions anywhere.
Files live in `+stability/` (runtime) and `+ibr/` (device models).

**Resource table contract** (serializable, one entry per physical resource):
```
resources(k) = struct(
  'resource_id',         "IBR2",       % unique string ID
  'bus_id',              2,            % external bus ID (network mapping only)
  'resource_type',       "ibr",        % "sg" | "ibr"
  'model_id',            "regfm_b1_dual",  % dispatches device factory
  'supported_modes',     ["gfl","gfm","tripped"],   % for ibr; ["synchronous","breaker_open"] for sg
  'voltage_forming_modes',"gfm",       % modes that form voltage
  'initial_mode',        "gfl",
  'initial_online',      true,
  'can_switch_mode',     true,
  'can_switch_online',   true,
  'has_current_limiter', true,
  'has_frt',             true,
  'can_black_start',     false,
  'limits',              struct(...),  % ImaxSS/ImaxF/Pmax/Qmax/Emax/Emin
  'ratings',             struct(...),  % Mbase/Sbase
  'dynamic_params',      struct(...),   % model params (model_id-dependent)
  'provenance',          struct(...))   % source citation, classification
```
**Committed configuration** = arrays aligned with resource index:
```
config.resource_ids = ["SG1","IBR2","IBR3","IBR6","IBR8"];
config.online        = [true, true, true, true, true];
config.mode          = ["synchronous","gfl","gfl","gfl","gfl"];
config.hold          = [...];  config.lockout = [...];
```
Validate `resource_ids` against `resources.resource_id` before use (index-drift guard).

**Derived indices** (the "real index" decision mechanism the user demands):
```
sg_idx              = find(resource_type == "sg");
switchable_idx      = find(online & can_switch_mode & ~locked);
bus_idx(k)          = find(network_bus_ids == resources(k).bus_id);
island_membership   = from current topology (connected components of Y);
voltage_forming_idx = find(online & ismember(mode, voltage_forming_modes));
```

**Generic entry points:**
- `stability.build_mixed_resource_devices(case_data, resource_spec, scenario_opt)` — iterates
  resource table, dispatches model factories by `model_id` + `capability`, emits a **UNIFORM
  device struct schema** (same field names for SG and IBR — fixes the provenance-mismatch
  singular-Jacobian root cause). SG via `sg_composite_device`, dual-mode IBR via
  `dual_mode_ibr_model`; future single-mode IBRs via their own factories.
- `stability.run_hybrid_case(scenario, opt)` — top-level: PF init → mixed equilibrium →
  composite TS with events → result + metadata. Thin orchestrator; no equations.
- `stability.ts_simulate_composite(model_bundle_or_scenario, opt)` — fixed/adaptive composite
  TS driver (event transaction correction 4; trapezoidal residual correction 7).

### Layer 2 — Scenario profile (per-case data, thin, no logic)

A scenario struct with the reusable **shape** already carried by
`case_ieee14_1sg_4ibr_auto_vsg.m`, generalised:
```
scenario.network_case   = case loader / case_data
scenario.resources      = resource table (Layer 1 contract)
scenario.dynamic_data   = per-resource sourced params + provenance
scenario.dispatch       = default dispatch policy
scenario.events         = scheduled event chronology + topologies
scenario.load_model     = cz_p_cz_q | ...
scenario.synchronism    = ΔV/Δf/Δθ/dwell/timeout
scenario.delays         = T_up/T_sg_min_off/ρ/T_min_hold/T_guard/T_lockout
scenario.selector       = γ_req + policy
scenario.reference_policy = angle-gauge policy (one per island)
scenario.metadata       = case fingerprint
```
IEEE14-specific values stay inside the IEEE14 profile only. A future `cases/` (NOT
`network_case_catalog.m`) profile set holds IEEE9/RTS-24/Padiyar (separate mission).

### Layer 3 — Public runner (thin wrapper)

- `solve_case.m` gains `'ibr'` as 4th analysis type (interactive dialog + non-interactive).
- `scripts/run_ieee14_1sg_4ibr_auto_switching.m` = thin one-command wrapper calling
  `run_hybrid_case` with the IEEE14 profile + default scenario_opt.

## 9 binding corrections (preserved, refined for generic layer)

1. **Angle-only vcon (CORRECTION 1), generalised to one-gauge-per-island.** Fix `Im(Visland_ref)=0`
   (angle reference) at ONE bus per connected island that has an online voltage-forming source;
   leave `Re(V)` free (solved by KCL/power balance). When an island's only voltage-forming
   source trips and no GFM commits, that island's `|V|` cannot be sustained → fail closed
   `noVoltageFormingSource`. Constant numerical gauge across modes within an island.
   - **Proof tests:** SG current perturbs bus-1 Re-KCL residual; SG_OFF has no hidden ideal
     source; omitted physical KCL row ≈0 after convergence. (IEEE14 single-island: gauge at
     bus 1 = `vars=2, rows=2, ref=0`, exactly as written in current code.)
2. **SG stator current from EMF6 Id/Iq (CORRECTION 2).** Via shared audited helper
   `sg_stator_current.m`; sign I INTO network; `S=V·conj(I)`.
3. **Algebraic transfer maps (CORRECTION 3).** GFL→GFM: `E_target=Vbus+(Re+jXL)·I_left`,
   `delta_VSM=angle(E_target)`, solve `x_Eint` for current continuity; fail closed on `Emax/Emin`.
   GFM→GFL: preserve shared `delta_PLL`, solve `phi_P/phi_Q` in existing PLL frame. Complex
   current preserved both directions. (Generic — operates on any switchable IBR by index.)
4. **Single right-limit event transaction (CORRECTION 4).** Capture left → metadata+topology
   (NO solve) → x reset + frozen anchors → ONE right-limit solve `g_free` → publish ONE sample.
   Do NOT call `ts_apply_transition`'s pre-reset solve; inline hybrid_commit+topology + own solve.
5. **hybrid_state anchor + synchronism + SG breaker physics (CORRECTION 5).** Add
   `device_frozen_anchor`. Offline SG: Id=Iq=0, Te=0, open-circuit flux, frozen Tm coast.
   Synchronism: signed margin `min(ΔV_max−|ΔV|, Δf_max−|Δf|, Δθ_max−|Δθ_wrapped|)`, sustained
   dwell. Reclose preserves ALL SG states, no forced reset. Per-SG (not global).
6. **Limiter/FRT (CORRECTION 6).** SOURCED REGFM_B1 Eqs.10-13 (ImaxSS/ImaxF PQ priority +
   transient circular saturation) + conditional-integration anti-windup on EXISTING states.
   Preserve 15-state layout; NO `deltaIT`. Consistent across RHS/current/reconstruct.
7. **Coupled trapezoidal residual (CORRECTION 7).** `R_x=x1−x0−h/2(f0+f1)`, `R_g=g_free(x1,y1)`;
   Jacobian `[I−h/2·df/dx, −h/2·df/dy; dg/dx, dg/dy]`. One `composite_newton` owner.
8. **Selector ordering + active-state reduction (CORRECTION 8), generalised to resource-config.**
   Enumerate candidate configurations by resource index. Filter: feasibility gates + γ_req. Then
   min-mode-changes → min-GFM (subject to reserve) → max-margin → deterministic resource-ID
   tie-break. Active-state REDUCTION before eig (Galerkin projection); NEVER eig-then-delete.
   No assumption that SG_ON→all-GFL or SG_OFF→all-GFM.
9. **Catalog separation (CORRECTION 9).** Runner in `scripts/`; `network_case_catalog.m`
   untouched. IBR-eligible cases exposed via a separate registry in `solve_case.m` (cases that
   carry a resource table), not the PF/SSSA/TS catalog.

## IBR Simulation route in solve_case.m (user directive)

Add `'ibr'` as 4th analysis type. Flow (interactive):
1. Select analysis = IBR Simulation.
2. Select network case (IBR-eligible: must expose resource table).
3. Read case's indexed resource table + capabilities.
4. Prompt (`prompt_ibr_options`) in 4 groups:
   - **IBR configuration:** selection policy (case default/automatic/manual), number of
     participating IBRs (≤ eligible), manual resource IDs when manual, initial GFL/GFM per
     selected IBR, automatic GFM switching on/off.
   - **Fault configuration:** fault bus, start time, clearing time, Rfault, Xfault — SAME
     contract as TS (`parse_ts_dialog` fault fields reused).
   - **SG event configuration:** SG resource IDs/count to trip, trip time, earliest reconnect-
     request time, minimum off-time, synchronism timeout.
   - **Simulation configuration:** end time, timestep, fixed/adaptive, verbose/plots.
5. `parse_ibr_dialog` validates; automatic selection uses eligible resource indices + records
   chosen IDs; manual explicitly asks IDs/buses. Count ≠ silent physical choice.

**Separation principle:** `case_data` (immutable: network/resources/capabilities/limits/
params/provenance/defaults) vs `scenario_opt` (runtime: count/selection/modes/fault/SG-trip/
timestep). NEVER mutate or write runtime choices back into case_data.

**Reconnect semantics:** requested reconnect time = earliest time synchronism checking MAY
permit reclose. Actual breaker reclose REQUIRES ΔV/Δf/Δθ pass + dwell + minimum-off + no
lockout. Return BOTH `requested_reconnect_time` and `actual_reclose_time` + `reclose_status`
+ `synchronism_metrics`. Forced-time reclose (if ever) = separate diagnostic option with warning.

**Non-interactive form first** (so tests can call):
`solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',ibr_opt)`. Dispatcher case:
```
case 'ibr'
    case_data = entry.loader();
    scenario_opt = prompt_or_merge_ibr_options(case_data, user_opt, interactive);
    scenario = stability.build_hybrid_scenario(case_data, scenario_opt);
    result = stability.run_hybrid_case(scenario, scenario_opt);
```
`solve_case.m` must NOT: build device equations, select GFM subset, hard-code IEEE14 buses,
mutate case_data, or do equilibrium/SSSA/TS logic.

## Tpq0=0 frozen-state decision (approved by user, inserted at transfer)

Kodsi SG1 (case_ieee14_1sg_4ibr_auto_vsg) has Tpq0=0 and Xq=Xqp=0.646 (round-rotor,
no q-axis transient saliency). The EMF6 equation for Edp:
    dEdp/dt = (c_q*Edpp - d_q*Edp) / Tpq0
evaluates to 0/0 = NaN at equilibrium because:
    c_q = (Xq - Xqp)/(Xqp - Xqpp) = 0/0.39 = 0
    d_q = (Xq - Xqpp)/(Xqp - Xqpp) = 0.39/0.39 = 1
    Edp = 0 at equilibrium
This produces NaN in the Jacobian via FD, NOT a zero eigenvalue.

**Approved solution (user, singular-limit decision):**
For exact source value Tpq0 == 0, derive the singular limit 0 = c_q*Edpp - d_q*Edp.
For Kodsi, c_q=0 and d_q=1, therefore Edp=0.

Preserve the public six-state SG storage layout, but declare Edp as an
algebraically eliminated/frozen state slot:
- initialize and reconstruct Edp at its algebraic value, here exactly zero;
- return dEdp=0 during TS;
- fail closed if a TS initial state violates Edp=0 beyond the predeclared
  consistency tolerance;
- exclude Edp from mixed-equilibrium unknowns and reconstruct it as zero;
- exclude Edp through active-state matrix reduction before SSSA eig;
- do not leave a zero residual row in equilibrium Newton;
- do not retain a spurious zero eigenvalue and delete it afterward;
- do not replace Tpq0 with epsilon.

Add device metadata such as:
    frozen_state_indices = 4;
    frozen_state_values  = 0;
    frozen_state_source  = 'Tpq0=0 singular limit: Edp=0';

Generic equilibrium/SSSA code must derive active indices from this metadata,
not hard-code SG state index 4.

**Tests:**
1. Kodsi initialization gives Edp=0 exactly;
2. RHS/equilibrium contain no NaN/Inf;
3. equilibrium Jacobian after active-state reduction is finite and conditioned;
4. perturbing the supplied TS initial Edp fails the consistency gate;
5. TS preserves Edp=0;
6. SSSA reduction occurs before eig and contains no artificial Edp zero mode;
7. a machine with Tpq0>0 retains the original sixth-order Edp dynamics
   bit-identically.

Corrected diagnosis: the demonstrated numerical NaN comes from the Tpq0=0
division. A MATLAB struct-schema mismatch may cause construction errors, but
it is not evidence that numeric Jacobian entries were silently corrupted.

## File allowlist (new + edited)

**New generic engine (Layer 1):**
- `+stability/resource_table.m` — build/validate the serializable resource table + capability
  flags + uniform device struct schema contract.
- `+stability/build_mixed_resource_devices.m` — generic builder: iterate resource table,
  dispatch factories by `model_id`, emit uniform-schema device array (fixes provenance mismatch).
- `+stability/build_hybrid_scenario.m` — bind case_data + resource table + scenario_opt into a
  scenario struct (immutable case_data; runtime opt separate).
- `+stability/run_hybrid_case.m` — top-level orchestrator (PF init → equilibrium → composite
  TS → result). Thin; no equations.
- `+stability/ts_simulate_composite.m` — fixed/adaptive composite TS driver (corrections 4,7).
- `+stability/sg_composite_device.m` — emf6→5-arg ABI; uniform provenance schema; correction 2.
- `+stability/sg_stator_current.m` — EMF6 stator Id/Iq + network-frame (correction 2).
- `+stability/composite_newton.m` — one damped-Newton owner, `residual_fn(z)`.
- `+stability/composite_sssa_model.m` — 5-arg→2-arg binding, FD Jacobian, vcon,
  reduction-before-eig (correction 8).
- `+stability/ibr_config_selector.m` — index-based resource-config selector (correction 8);
  enumerate by resource index, per-island voltage-forming check; fingerprint fail-closed.
- `+stability/synchronism_guard.m` — signed-margin predicate, per-SG (correction 5).
- `+stability/transfer_maps.m` — algebraic GFL↔GFM continuity (correction 3).

**New scenario profile (Layer 2) — IEEE14 first:**
- `+cases/scenario_ieee14_1sg_4ibr.m` — IEEE14 scenario profile (resource table + dynamic
  data + dispatch + events + synchronism + delays + selector + reference_policy). IEEE14 IDs
  live HERE only.
- `scripts/run_ieee14_1sg_4ibr_auto_switching.m` — thin one-command wrapper.

**Edited (minimal, additive):**
- `solve_case.m` — add `'ibr'` analysis type + `case_registry('ibr')` (IBR-eligible registry) +
  `prompt_ibr_options`/`parse_ibr_dialog`/`merge_ibr_options` (reuse TS fault fields).
- `+stability/ts_hybrid_state_init.m` — add `device_frozen_anchor` field (correction 5).
- `+ibr/dual_mode_ibr_model.m` — uniform provenance schema; emit capability flags; closures
  read mode+frozen_anchor from `event_context.hybrid_state` (fallback construction).
- `+stability/mixed_equilibrium_solve.m` — REPLACE global `sg_status` rule (L55-63) with
  per-island voltage-forming index check; generalise vcon to one-gauge-per-island (IEEE14 =
  single island, gauge at bus 1); index-based fingerprint; remove `config.sg_status` dependence.
- `+ibr/build_ieee14_ibr_devices.m` + `+ibr/build_ieee14_sg_ibr_devices.m` — demote to thin
  scenario wrappers around `build_mixed_resource_devices` (IEEE14 IDs confined here).
- `+ibr/regfm_b1_vsg_model.m` — limiter/FRT sourced edit (correction 6; Phase G).
- `tests/test_ieee14_1sg_4ibr_phase4.m` — update assertions for index-based config (remove
  `sg_status` global rule tests; replace with per-island voltage-forming tests).
- `docs/project/AGENT_HANDOFF.md` + `EQUATION_SOURCE_MATRIX.md` + `FROZEN_CONTRACT.md` +
  decision ledger — Phase J refresh.

**Forbidden (no touch without re-approval):** `ts_simulate.m`, `ts_step_kernel.m`,
`ts_model_strategy.m`, `ts_algebraic_solve.m`, `ts_algebraic_solve_u.m`, `ts_adaptive_driver.m`
core logic, `composite_dae.m` ABI/schema (already arbitrary-N), `multimachine_ssa.m` Schur
logic, `gfl_model.m` equations/params, `regfm_b1_vsg_model.m` equations (only limiter edit),
case dispatch/physical values, report artifacts, `tests/+fixtures/`,
`+cases/network_case_catalog.m` (correction 9).

## Phases (generic-first; commits per phase with targeted tests; do NOT stop mid-phase)

**Phase A — Audit + baseline (DONE).** 616/616 at HEAD 42e2dea. Gap map + 3-agent findings
recorded above.

**Phase B0 — Generic foundation (resource table + capability + uniform schema).**
- `+stability/resource_table.m` (contract + validation + capability flags).
- `+stability/build_mixed_resource_devices.m` (factory dispatch + uniform device schema —
  THE fix for the singular-Jacobian root cause).
- `+stability/build_hybrid_scenario.m` (case_data + resource table + scenario_opt binding).
- `+cases/scenario_ieee14_1sg_4ibr.m` (IEEE14 profile: resource table from Kodsi SG1 +
  IBR2/3/6/8; IEEE14 IDs confined here).
- Demote `build_ieee14_ibr_devices` + `build_ieee14_sg_ibr_devices` to thin wrappers.
- Tests: `test_resource_table` (schema validation, capability flags, index-drift guard),
  `test_build_mixed_resource_devices` (uniform provenance schema, SG+IBR stack cleanly,
  arbitrary-N), `test_scenario_ieee14` (profile produces valid resource table + scenario).

**Phase B1 — Singular-Jacobian fix + generic equilibrium + angle-only vcon proof.**
- `+stability/sg_composite_device.m` (uniform provenance, correction 2).
- `+stability/sg_stator_current.m` (correction 2).
- `+stability/composite_newton.m` (residual_fn owner).
- `+stability/mixed_equilibrium_solve.m` edits: replace `sg_status` rule with per-island
  voltage-forming index check; generalise vcon; index-based fingerprint.
- Tests: `test_sg_stator_current`, `test_sg_composite_device` (5-arg ABI), `test_angle_only_vcon`
  (Im(V1)=0 fixed, Re(V1) free, SG current affects residual row 1, omitted KCL row ≈0),
  `test_mixed_equilibrium_sg_on` (5-device converges — THE singular-Jacobian fix),
  `test_mixed_equilibrium_sg_off_gfm`, `test_no_voltage_forming_source_rejected` (per-island,
  not global sg_status), `test_equilibrium_fingerprint_index_based`.
- **Gate:** 5-device (SG1 online + 4 GFL) equilibrium converges, rcond>1e-10, no NaN. This is
  the proof the uniform-schema fix resolved the root cause.

**Phase B2 — Fixed-step composite TS vertical slice (no events).**
- `+stability/ts_simulate_composite.m` (trapezoidal coupled residual, correction 7; init from
  `mixed_equilibrium_solve`).
- Tests: `test_ts_composite_no_event_equilibrium` (holds equilibrium, residual<1e-6),
  `test_ts_composite_bit_identity` (legacy SG-only path unchanged).

**Phase C — Runtime mode-switch + transfer maps + frozen anchor.**
- `+ibr/dual_mode_ibr_model.m` edit (mode+frozen_anchor from hybrid_state; capability flags).
- `+stability/ts_hybrid_state_init.m` edit (device_frozen_anchor).
- `+stability/transfer_maps.m` (correction 3).
- `ts_simulate_composite` event transaction (correction 4).
- Tests: dimension constant (15 across modes + live switch), GFL→GFM & GFM→GFL current
  continuity, transfer residual finite, inactive frozen at anchor, repeated switching,
  invalid mode fail-closed, hybrid_commit round-trips new field. Report discontinuity honestly.

**Phase D — Index-based resource-configuration selector + composite SSSA.**
- `+stability/composite_sssa_model.m` (reduction-before-eig, correction 8).
- `+stability/ibr_config_selector.m` (enumerate by resource index; per-island voltage-forming
  check; correction 8 ordering; fingerprint).
- Tests: single-GFM, multi-GFM, deterministic resource-ID tie-break, stale fingerprint reject,
  per-island no-voltage-forming reject, selector_rejects_marginal (Ω=−0.05),
  selector_accepts_stable (Ω=−0.2), fail-closed-all-unstable, γ_req frozen (grep),
  reduce-before-eig (grep), min-mode-changes-before-max-margin ordering, heterogeneous-mix
  (SG+GFL+GFM simultaneously) selection works, no SG_ON→all-GFL assumption (grep).

**Phase E — SG trip + automatic GFM commitment (per-SG, per-island).**
Scheduled `sg_trip_request` → `sg_open_and_gfm_mode_commit` (correction 4); coincident fault
ordering; one public sample; no duplicate timestamps. Tests: power rebalance, post-trip
current≤ImaxSS, coincident ordering, no duplicate timestamps, one right-limit sample,
multi-SG partial-trip (heterogeneous: SG2 online while SG1 tripped).

**Phase F — SG synchronism + reclose (per-breaker).**
`+stability/synchronism_guard.m` (signed margin); dwell; timeout→SYNC_TIMEOUT (SG stays
disconnected); `sg_reclose_and_mode_commit` (preserve SG state); T_sg_min_off + T_lockout.
Tests: sync_pass, sync_fail_voltage/slip/angle, sync_timeout, hold/lockout prevents chatter,
no_forced_sg_reset, requested-vs-actual reclose time returned.

**Phase G — Limiter + anti-windup + FRT.**
SOURCED edit to `regfm_b1_vsg_model.m` (REGFM_B1 Eqs.10-13) consistent across
RHS/current/reconstruct (correction 6). Anti-windup conditional-integration freeze. Tests:
limiter_transient_cap (|I|≤ImaxF), limiter_pq_priority, anti_windup_freeze, anti_windup_recovery,
fault no NaN/Inf/divergence.

**Phase H — Adaptive hybrid TS (rollback).**
`ts_simulate_composite` adaptive variant: rejected trials cannot advance
timers/modes/logs (LTE/accept-reject PATTERN as separate impl; do NOT edit
`ts_adaptive_driver`). Exact landing at events. Tests: rejected-trial rollback, immutable
snapshot enforcement, fixed/adaptive agree within tolerance, guard dwell only on committed steps.

**Phase I — solve_case.m IBR route + public runner.**
- `solve_case.m` edits: `'ibr'` analysis type, `case_registry('ibr')` (IBR-eligible registry),
  `prompt_ibr_options`/`parse_ibr_dialog`/`merge_ibr_options` (4 groups; reuse TS fault fields),
  non-interactive form, requested-vs-actual reclose in result.
- `scripts/run_ieee14_1sg_4ibr_auto_switching.m` (thin wrapper).
- Tests: `test_solve_case_ibr_noninteractive` (calls solver without dialog), `test_ibr_dialog`
  (automatic/manual selection records IDs; count≤eligible; count≠silent choice),
  `test_reconnect_gates` (actual reclose requires synchronism gates; forced-time rejected),
  `test_immutable_case_data` (runtime opt does not mutate case_data). Catalog NOT touched.

**Phase J — Final verification + delivery.**
Full regression + `test_no_external_solver_dependency` + targeted; 0 failed/0 incomplete.
Refresh STALE `AGENT_HANDOFF.md` + source matrix + frozen contract + decision ledger + new
handoff/provenance. `git diff --check`; explicit-path stage; commit; fetch; verify no divergence;
fast-forward push (pre-authorized); verify HEAD==origin/main.

## Event transaction (correction 4) + transfer ordering (correction 3)

Composite driver event handler, per coincident group (one public sample):
1. **Capture left:** `(x_left, y_left)` + per-device left complex current.
2. **Metadata + topology (NO solve):** `hybrid_commit` (per-resource mode/online/config_id/
   frozen anchors) + select `Y_right`. No algebraic solve.
3. **x reset + frozen anchors:** `transfer_maps` on newly-active branch's x slice; set
   `frozen_anchor` for newly-INactive branch = last active value.
4. **ONE final right-limit solve:** `g_free(x_reset, y_right)=0` (island angle gauge fixed)
   via `composite_newton`. Single public right-limit sample.
5. **Publish:** `(x1=x_reset, y1=y_right)` as the one public sample.

## Verification (end-to-end)

```matlab
restoredefaultpath; cd('/home/birds/Documents/Power-flow');
pf_init_paths;  % before clear (R2026a path quirk)
r = runtests('tests','IncludeSubfolders',true);   % 0 failed / 0 incomplete
runtests('tests/test_no_external_solver_dependency.m');
% Non-interactive IBR route:
result = solve_case('analysis','ibr','case','ieee14_1sg_4ibr', ...
    'options',struct('automatic_gfm_switching',true,'t_end',5.0,'dt',1e-3));
% One-command runner:
result2 = run_ieee14_1sg_4ibr_auto_switching();
```

**Acceptance gates (before results):** 0 failed/0 incomplete; no NaN/Inf; deterministic
repeat; no duplicate public timestamps; deterministic event order; equilibrium+algebraic
residual within gates (1e-6/1e-10); rcond>1e-10 (singular Jacobian RESOLVED); current within
declared limit tolerance; selector chooses validated config (index-based, correction-8);
SG reclose only after synchronism dwell; angle-only vcon proven; fixed/adaptive agree within
tolerance; legacy bit-identical; real devices in production route; no external solver;
IBR route in solve_case.m works (interactive + non-interactive); case_data immutable;
requested-vs-actual reclose returned.

`IBR_PRODUCTION_INTEGRATION_READY` flips to READY only after: real devices in production TS
route, automatic switching works, SG trip/reclose+sync gate pass, limiter/FRT passes,
fixed/adaptive hybrid semantics pass, full regression 0 failed/0 incomplete, public runner +
solve_case IBR route work from clean checkout. Multi-case validation (IEEE9/RTS-24/Padiyar)
is a SEPARATE future mission; engine case-agnostic now but not multi-case-validated.

## Frozen CASE_DEFINED/PROJECT_DERIVED values (before results)

SG1=Kodsi 60Hz emf6 (H=5.148); Tpq0=0 frozen-state singular limit (Edp=0); transfer
maps=PROJECT_DERIVED algebraic continuity (correction 3); limiter=REGFM_B1 Eqs.10-13 +
conditional-integration; synchronism ΔV0.05/Δf0.001/Δθ10deg/dwell0.5/timeout5; delays
T_up0.12/T_sg_min_off0.5/ρ0.05/T_min_hold1.0/T_guard0.3/T_lockout2.0; dispatch Pmax-proportional
(IBR2=109.7/IBR3,6,8=49.8 post-trip); γ_req=0.1 rad/s; λ=1e-3 (NUMERICAL_METHOD). "24 bus"=RTS-24
(future mission). No value changes after viewing results.

## Genuine stop conditions only

Stop + ask when: governing equations have multiple sourced-irresolvable interpretations;
public case/schema semantics must change (angle-only vcon is a vcon-layer change, NOT a schema
change — approved); fixed state dimension must change; numerical angle gauge must move
dynamically per-mode (it does NOT — one constant gauge per island); dispatch infeasible for ALL
candidate configs (after units/signs/bases checked); external solver required; two sources
conflict on a benchmark-mandated value; an active-owner shared file outside allowlist must be
touched; remote divergence conflict; acceptance passes only by changing a value after seeing
results; IBR-eligible case lacks a resource table (a case must be upgraded to a scenario
profile first — not silently auto-built). "No exact source threshold" is NOT a stop.
