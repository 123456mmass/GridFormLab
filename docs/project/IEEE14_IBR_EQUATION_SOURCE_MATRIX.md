# IEEE14 1-SG + 4-IBR Mission — Equation/Source Matrix (Phase 1)

**Status:** `IEEE14_IBR_EQUATION_CONTRACT_READY` = `PARTIAL` (see gap summary);
`IBR_PRODUCTION_INTEGRATION_READY` = `NOT_STARTED`.
**Branch:** `feature/ieee14-auto-vsg-switching`. **Date:** 2026-07-13.

This matrix records the per-equation, per-parameter provenance for the IEEE14
1-SG + 4-IBR automatic GFL/VSG switching mission, traced from primary-source
PDFs the user provided. Bibliographic identity and equation-level coverage
are kept strictly separate. Labels: `SOURCE_VERBATIM` (equation copied
verbatim with exact location), `SOURCE_TRANSFORMED` (cited source, notation
transformed), `CASE_DEFINED` (determined by IEEE14 case), `PROJECT_DERIVED`
(derived in-repo from a sourced law), `NUMERICAL_METHOD`, `UNSOURCED`,
`DECISION_REQUIRED`. Only the first five support production claims.

## Source PDFs (SHA-256 provenance)

| File | Document | SHA-256 |
|------|----------|---------|
| 90260.pdf | REGFM_B1 VSM GFM Inverter Model Spec (Du et al., PNNL, 2024) | de52a0b7c8beec6d16d8e10b53a565d902ab1a79ef093ba3d6d80260a9287d50 |
| 83340.pdf | Ding et al., Dynamically Configurable GFM/GFL (NREL/Temple, 2022) | 2aeded379710e3f93e5f47e79a9eb98a2b9fd05e2b79d1fc1713f5d50a995727 |
| 1110-2002.pdf | IEEE Std 1110-2002, SG Modeling Practices (ANSI, 81pp) | 2eb08ed83ea8c5d728a482d17777406ab37d01638f0eadb9848f01f9fb24b6c3 |
| DynamicIEEETestSystems...pdf | Demetriou et al., Dynamic IEEE Test Systems (2015) | e5dd31403e2d375b8d0cab6005937fd3884e5a6e365cf936d5362f2f1cf047a8 |
| MODELING...IEEE14BUS...pdf | Kodsi, IEEE 14 Bus Modeling with FACTS (U.Waterloo TR 2003-3) | cf7d2120661e4050f96675378a4fca3601dd64fe1086ceead1d0c5d43db0a610 |
| Research_on_the_ratio_configuration_of_GFL_and_GFM.pdf | Zhang et al., GFL/GFM Ratio Config (J.Phys. 2025) | 8025d27d6ca834b77434caef952ae9db388722853e7f30b84aaa9c969b68501e |
| 2019-5.pdf | IEEE PSRC Meeting Minutes, Cincinnati May 2019 (91pp) | 23a1d63e2e77fa6ed65d3b33262dc568413446860181fc11b76de5f25e8d2445 |
| Synthetic_Benchmarks...pdf | Mohammadi & Saleh, Synthetic Benchmarks (IEEE Access 2021) | 417fa6c3fb35418ffa9ae87a04e50c87699d63a2d937029e75a3560751eb86f7 |
| IEEE 14-Bus System.zip | PowerWorld + PSS/E raw (UW archive 1993, flow only) | 94f873baf5ec07693a442bfdf1ef5e33326bfeeb837b31d9d968b4fb15bb7bcc |

## Per-item source-closure status

### Item 1 — GFL positive-sequence model + state order

- **Ding 83340 §II-B (pp. 3-4), Eqs. 8-10 + shared 3-6:** GFL model is a
  FULL EMT/LCL model (14-state: ε_L, δ_inv, P_inv, Q_inv, ϕ'_d, ϕ'_q, γ_d,
  γ_q, i_ld, i_lq, v_od, v_oq, i_od, i_oq). SRF-PLL (Eq. 8), power-tracking
  loop (Eqs. 9-10), inner voltage/current PI cascades + LCL filter (Eqs. 3-6).
  **SOURCE_VERBATIM** at equation level. GFL controller params (K_ps, K_is,
  K_pL, K_iL) NOT in Ding Table I.
- **Gap:** Ding's GFL is an EMT/LCL model, NOT a positive-sequence RMS model.
  The canonical plan requires "the smallest source-closed positive-sequence
  RMS GFL profile compatible with the project's DAE." A reduced-order
  positive-sequence GFL (current-source with PLL-synchronized angle) is the
  standard utility representation, but no inspected source states its
  reduced-order state equations explicitly. The RMS reduction (ideal inner
  loop + LCL elimination) is **PROJECT_DERIVED** (documented in
  `docs/project/IEEE14_IBR_GFL_PHASE5_PROVENANCE.md`); it is NOT claimed
  source-closed verbatim. Kps/Kis are **ASSUMED_DIAGNOSTIC** (Ding Table I
  lacks them; a-priori critically-damped rationale) and are excluded from
  production acceptance.
- **Status: STRUCTURAL_ONLY (Phase 5 done).** Full EMT GFL sourced; the
  positive-sequence RMS reduction is PROJECT_DERIVED (not source-closed
  verbatim); Kps/Kis are ASSUMED_DIAGNOSTIC. Production readiness pending
  source-closing the ASSUMED_DIAGNOSTIC gains and the Phase 9 mixed-
  equilibrium integration.

### Item 2 — VSG/VSM profile from REGFM_B1

- **REGFM_B1 90260:** VSM swing-equation block (Figure 2, GRAPHICAL →
  SOURCE_TRANSFORMED — must reconstruct ODEs from block diagram);
  voltage-source-behind-impedance (Eq. 13, VERBATIM: I∠φ=(EVSM∠δVSM−V∠δV)/
  (Re+jXL)); measurement filters (Eqs. 1-5, VERBATIM, 1st-order LPF with
  S_base/M_base conversion); Q-V droop + voltage PI (Figure 3, GRAPHICAL);
  PQ priority + transient current limiting (Eqs. 10-13, Figures 5-7, VERBATIM);
  full parameter table (Table 1, VERBATIM). GFM-only (no GFL).
- **IEEE 1110-2002:** electromagnetic torque Te=ψ_d·i_q−ψ_q·i_d (Eq. 12/C.1,
  VERBATIM) — the physical ancestor the VSM mimics. Does NOT define H, D, or
  the swing equation (delegates to Kundur [B54], NOT locally available).
- **Gaps (closed in Phase 6):** (a) REGFM_B1 gives no explicit state vector
  — reconstructed as 11 states (PROJECT_DERIVED, frozen); (b) initialization
  derived (PROJECT_DERIVED warm-start); (c) anti-windup deferred to Phase 14;
  (d) swing ODE reconstructed as SOURCE_TRANSFORMED under frozen flag profile
  ωFlag=0, FFlag=1, ωref=1 pu: 2H·dωm/dt = P_ref_inv − Pinv_f − (1/mp+D1)·ωm
  − D2·(ωm − x_washout).
- **Status: CLOSED (Phase 6).** Implemented in `+ibr/regfm_b1_vsg_model.m`
  (11 states, STRUCTURAL_ONLY). Per-unit base contract (user-confirmed,
  FROZEN): external ABI on system base; internal swing/filters on inverter
  base (kappa=Sbase/Mbase); P_ref_inv=kappa·P_ref_sys (no double conversion).
  All params SOURCE_VERBATIM from Table 1; NO ASSUMED_DIAGNOSTIC. 18/18 tests
  pass. See `docs/project/IEEE14_IBR_GFM_PHASE6_PROVENANCE.md`.
- **Phase 7 (dual-mode):** superset 15-state fixed-layout device
  (`+ibr/dual_mode_ibr_model.m`) reuses GFL (Phase 5) + GFM (Phase 6) as
  single source of truth. Inactive branches decay-to-warmstart (lambda=1e-3,
  NUMERICAL_METHOD) to keep the coupled Newton Jacobian full-rank while
  holding inactive states at warm-start. 9/9 tests pass.
- **Phase 8 (IEEE14 builder):** `+ibr/build_ieee14_ibr_devices.m` builds
  real devices (IBR2@2, IBR3@3, IBR6@6, IBR8@8) with CASE_DEFINED Mbase
  nameplate proxy (IBR2=140, IBR3/6/8=100 MVA). mixed_equilibrium_solve
  works with real devices (SG_ON and SG_OFF+GFM converge; pure-GFL SG_OFF
  fails closed). 6/6 tests pass.

### Item 3 — GFL↔VSG transfer maps + inactive-state rule  ⛔ GENUINE STOP

- **Ding 83340 §IV-B (p. 5):** ONLY the concept "freeze the integral values
  in the inner loops at the time when the operation mode transition occurs.
  The frozen values will be used as the initial ones when the new operation
  mode starts." No equations. No bumpless transfer map. No shadow/tracking
  controller. No synchronism check. No inactive-state evolution rule.
  Different state dimensions (GFL 14 vs GFM 13) with no remapping formula.
- **REGFM_B1 90260:** no mode switching at all.
- **Status: UNSOURCED — GENUINE STOP CONDITION.** A bumpless GFL↔VSG
  transfer map and an inactive-state evolution rule (frozen / tracking /
  shadow-controller) cannot be sourced without inventing a semantic choice.
  This blocks the GFL↔GFM transfer / mode-switching missions (Phases 10-11).
  It does NOT block Phase 6 (the GFM/VSG model, which proceeds from item 2).
  Per user directive: "GFL↔GFM transfer or inactive-state behavior would have
  to be invented" = stop.

### Item 4 — Current limiter + anti-windup

- **REGFM_B1 90260, Eqs. 10-13, Figs. 5-7:** steady-state PQ priority
  (ImaxSS, IdmaxSS, IqmaxSS, kf, PQFlag); transient current limiting (ImaxF,
  algebraic circular saturation, Eq. 13); active-current limit via δIT
  integrator (Fig. 6, Eq. 12). **SOURCE_VERBATIM.**
- **Gap:** anti-windup logic for the voltage PI and the active-current
  integrator is NOT specified. Reset-to-zero described; no back-calculation
  or conditional-integration formula.
- **Status: PARTIAL.** Limiter sourced; anti-windup UNSOURCED.

### Item 5 — SG synchronism thresholds/dwell/timeout  ⛔ GENUINE STOP

- **2019-5.pdf:** IEEE PSRC committee MINUTES (not IEEE TR-121 itself).
  Mentions synchronism/out-of-step/auto-reclose conceptually (C37.242 PMU
  sync guide, out-of-step tripping tutorials, autoreclosing for distribution
  §5 "needs work"). No numerical thresholds (ΔV, Δf/slip, Δθ), no dwell, no
  timeout, no breaker-close-time prediction.
- **IEEE TR-121 itself:** NOT available locally.
- **Status: UNSOURCED — GENUINE STOP CONDITION.** Synchronism thresholds
  cannot be sourced. Blocks Phase 11 (SG synchronism/reclose). Per user
  directive: "synchronism thresholds/dwell/delays cannot be sourced" = stop.

### Item 6 — Delays (T_up, T_sg_min_off, T_settle, T_minimum_hold, T_guard, T_lockout, ρ)  ⛔ GENUINE STOP

- **No inspected source** provides protection/controller switching delays,
  T_sg_min_off, ρ, T_minimum_hold, T_guard, or T_lockout. Ding has none;
  REGFM_B1 has none; IEEE 1110-2002 has none; the GFL/GFM ratio paper has
  none.
- **Status: UNSOURCED — GENUINE STOP CONDITION.** Per user directive:
  "a required delay or threshold would have to be guessed" = stop.

### Item 7 — IEEE14 SG dynamic data (H, D, X'd or full EMF6)

- **Case file `case_matpower6_case14.m`:** NO `.machines` field. Classical
  defaults H=5.0/D=0/X'd=0.30 in `expand_machines_classical` are UNSOURCED
  textbook guesses. EMF6 path errors without `.machines`.
- **IEEE 1110-2002 (authoritative):** permits "typical data" for preliminary
  planning (Clause 5.1, 7.1) but mandates manufacturer data when available;
  does NOT endorse Anderson & Fouad (absent from bibliography). Provides
  Model 2.2 structure (6th-order) but no IEEE14-specific values.
- **Two CONFLICTING typical datasets, both tracing to Anderson & Fouad:**
  - Demetriou: 50 Hz, Gen1 448 MVA H=2.656, bus 3 = condenser 40 MVA.
    INCONSISTENT with our 60 Hz case.
  - Kodsi: 60 Hz (likely), Gen1 615 MVA H=5.148, bus 3 = generator (=bus2
    60 MVA).
  - Bus-3 identity conflict (condenser vs generator); our case has bus 3 as
    PV with Pg=0 (condenser-like).
- **Autonomous hierarchy (a) "IEEE14-specific published profile with complete
  dynamic data":** BOTH Demetriou and Kodsi qualify as published IEEE14
  dynamic profiles, but they are materially different (50 vs 60 Hz, 448 vs
  615 MVA, bus-3 identity). The 60 Hz case fact resolves frequency but not
  the MVA/identity conflict. Hierarchy does not identify ONE unambiguously.
- **Status: UNSOURCED — GENUINE STOP CONDITION.** Per user directive:
  "IEEE14 SG dynamic data cannot be sourced" and "candidate profiles are
  materially different and the hierarchy does not identify one
  unambiguously" = stop.

### Item 8 — Dispatch/energy contract resolving 219 MW post-trip deficit  ⛔ GENUINE STOP

- **Case facts (recomputed):** load 259 MW, bus-1 Pg 232.4 MW, buses 2-8
  Pg 40 MW → 219 MW deficit after SG trip. Buses 2-8 Pmax 440 MW (aggregate
  feasible) but buses 3,6,8 at Pg=0 pre-trip.
- **No inspected source** provides a sourced post-trip reserve/participation/
  ramp/load-shed policy for IEEE14 with 4 IBRs.
- **Status: UNSOURCED — GENUINE STOP CONDITION.** Per user directive: "the
  219 MW post-trip dispatch/energy/ramp contract cannot be closed" = stop.

### Item 9 — Selection margin γ_req

- **Ding 83340:** Ω_m = max Re(λ_i) excluding λ_1 (manual zero-eigenvalue
  deletion, not reference reduction). States only "sufficiently negative" —
  no normative γ_req value.
- **GFL/GFM ratio paper:** PM ≥ 30° as design criterion (impedance-based
  phase margin, NOT eigenvalue-based). Table 3: GFM ratio vs SCR (10%/5%/0%
  for SCR 1.2-1.8/1.9-2.9/≥3). Different domain (MMC-HVDC, not IEEE14).
- **Gap:** no eigenvalue-based γ_req normative value. Converting PM ≥ 30° to
  an eigenvalue margin requires a semantic choice (different stability
  theory domains).
- **Status: UNSOURCED — GENUINE STOP CONDITION** for eigenvalue-based γ_req.
  Per user directive: "only a source range exists with no normative/default
  selection" = stop.

## Summary: 1/9 fully source-closed (Phase 6 closed item 2)

| # | Item | Status |
|---|------|--------|
| 1 | GFL positive-sequence model | STRUCTURAL_ONLY (Phase 5 done; RMS reduction PROJECT_DERIVED, Kps/Kis ASSUMED_DIAGNOSTIC) |
| 2 | VSG/VSM from REGFM_B1 | CLOSED (Phase 6 done; 11-state model, all params SOURCE_VERBATIM, NO ASSUMED_DIAGNOSTIC) |
| 3 | GFL↔VSG transfer maps | ⛔ UNSOURCED — STOP (Phase 7 dual-mode uses decay-to-warmstart as interim; full transfer Phase 10-11) |
| 4 | Current limiter + anti-windup | PARTIAL (limiter sourced; anti-windup UNSOURCED; deferred to Phase 14) |
| 5 | SG synchronism thresholds | ⛔ UNSOURCED — STOP |
| 6 | Delays | ⛔ UNSOURCED — STOP |
| 7 | IEEE14 SG dynamic data | ⛔ UNSOURCED (conflicting typical data) — STOP |
| 8 | 219 MW dispatch/energy contract | ⛔ UNSOURCED — STOP |
| 9 | γ_req eigenvalue margin | ⛔ UNSOURCED — STOP |

**Six items (3, 5, 6, 7, 8, 9) are genuine stop conditions.** Per the user's
retained stop conditions, the mission STOPS at Phase 1 for these items.
Independent generic work (Phase 2 event architecture, Phase 3 hybrid-state)
that does NOT assume the missing decisions MAY proceed with synthetic
fixtures. Phase 4 (mixed equilibrium) is blocked by item 8; Phase 5 (GFL
model) is STRUCTURAL_ONLY (done); Phase 6 (GFM/VSG model) proceeds from item 2
(PARTIAL-TO-CLOSEABLE); the GFL↔GFM transfer / mode-switching missions
(Phases 10-11) are blocked by item 3; Phases 10-13 are blocked by items 3/5/6.

## Conventions that ARE source-closed (reusable)

- KCL form `g = Y·V − I_inj` (Padiyar Eq.5.27 p.157) — SOURCE-backed.
- Per-unit system base (Padiyar Sec 3.5 p.62) — SOURCE-backed.
- Current direction: positive INTO network / out of generator (Padiyar
  Sec 3.2.2 p.47; IEEE 1110-2002 Clause 4.1 generator notation) — SOURCE-backed.
- VSM electromagnetic torque Te=ψ_d·i_q−ψ_q·i_d (IEEE 1110-2002 Eq. 12/C.1).
- REGFM_B1 voltage-source-behind-impedance output (Eq. 13).
- REGFM_B1 measurement filters (Eqs. 1-5).
- REGFM_B1 PQ priority + transient current limiting (Eqs. 10-13).
- REGFM_B1 full parameter table (Table 1, with example values — these are
  the spec's EXAMPLE values, usable as CASE_DEFINED if the IEEE14 IBR
  converters adopt the REGFM_B1 default profile).
- Ding spectral-abscissa Ω = max Re(λ_i) (Eq. 19), with manual λ_1 deletion
  (the mission's reference-reduction improvement over Ding is PROJECT_DERIVED).
- Ding 1-SG + 5-inverter test system parameter set (Table I) — a published
  parameter set, but for a DIFFERENT network than IEEE14.

## What can proceed autonomously (generic, no missing decision)

- **Phase 2** — generic scheduled+guard event architecture with synthetic
  fixtures (does not require GFL/VSG models or dispatch contract).
- **Phase 3** — persistent hybrid-state/rollback contract with synthetic
  fixtures.

## What is blocked (genuine stop)

- **Phase 4** (mixed equilibrium) — needs dispatch/energy contract (item 8).
- **Phase 5** (GFL model) — STRUCTURAL_ONLY (done; RMS reduction PROJECT_DERIVED,
  Kps/Kis ASSUMED_DIAGNOSTIC; production readiness pending source-closing the
  ASSUMED_DIAGNOSTIC gains and the Phase 9 mixed-equilibrium integration).
- **Phase 6** (GFM/VSG model) — proceeds from item 2 (PARTIAL-TO-CLOSEABLE);
  the GFL↔GFM transfer maps (item 3) are NOT required for Phase 6.
- **Phases 7-17** — depend on 5/6.
- **Phases 10-13** — need synchronism (item 5), delays (item 6).
