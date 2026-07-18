# IEEE14 1-SG + 4-IBR Mission — Equation/Source Matrix (Phase 1)

**Status:** implemented structural contracts are source/classification mapped;
`IBR_PRODUCTION_INTEGRATION_READY = NOT_READY`.
**Branch:** `main`. **Last corrective update:** 2026-07-15.

This matrix records the per-equation, per-parameter provenance for the IEEE14
1-SG + 4-IBR automatic GFL/VSG switching mission, traced from primary-source
PDFs the user provided. Bibliographic identity and equation-level coverage
are kept strictly separate. Labels: `SOURCE_VERBATIM` (equation copied
verbatim with exact location), `SOURCE_TRANSFORMED` (cited source, notation
transformed), `CASE_DEFINED` (determined by IEEE14 case), `PROJECT_DERIVED`
(derived in-repo from a sourced law), `NUMERICAL_METHOD`, `UNSOURCED`,
`DECISION_REQUIRED`. Only the first five support production claims.

Canonical acceptance classes in the current `AGENTS.md` are
`SOURCE_DEFINED`, `CASE_DEFINED`, `PROJECT_DERIVED`, `NUMERICAL_METHOD`, and
`ASSUMED_DIAGNOSTIC`. In this historical matrix, `SOURCE_VERBATIM` and
`SOURCE_TRANSFORMED` are sublabels of `SOURCE_DEFINED`.

## 2026-07-15 implementation reconciliation

- Correct SG_ON and SG_OFF equilibria retain all physical KCL rows. A voltage
  gauge removes coordinates, never network equations.
- SG REF fixes the case voltage and solves `[Tm;Efd]`; SG_OFF solves one
  selected reference-GFM P input. These are PROJECT_DERIVED closures of the
  SOURCE_DEFINED network/device equations.
- Exact index-selected sets with 1, 2, and 3 GFMs pass; exactly one selected
  member is the numerical reference and other selected members remain GFMs.
- G1 implements REGFM_B1 Eq.13 transient clamp and sourced PLL freeze. G2 now
  implements Fig.5 PQ priority, Eqs.10-11 Emax/Emin behavior, the Fig.6
  upper/lower angle-bound controllers, and PROJECT_DERIVED conditional
  anti-windup through the generic active-bound equilibrium contract.
- Equilibrium returns `u_eq`, context, and authenticated state maps used by the
  same f/g closures in fixed-step TS and SSSA.
- The selector now evaluates each candidate against branch/shunt Ybus SCR,
  physical all-KCL equilibrium, and full-state SSSA using the exact solved
  `u_eq`, event context, and active-state map. It still fails closed and keeps
  `ready_to_commit=false` when any evidence layer is absent or rejected.
- The former six-state Ding reduction and its `Kps/Kis` assumptions have been
  removed from the canonical path. The canonical GFL is the sourced WECC
  REGC_A/REEC_A positive-sequence model. Overall production readiness remains
  NOT_READY until selector, event-driving TS, plotting, and final regression
  gates close on one runtime tree.

## Source PDFs (SHA-256 provenance)

| File | Document | SHA-256 |
|------|----------|---------|
| WECC-Second-Generation-Wind-Turbine-Model Spec-012314.pdf | WECC/EPRI, Second Generation Generic WTG Models (2014) | aef13405133f110351eeb341ffb4c674af5b498bd7881a936c03521e3584caea |
| WECC Wind Plant Dynamic Modeling Guidelines.pdf | WECC Wind Plant Dynamic Modeling Guidelines | 077f6c8e295a7e5914f962981bb3782d3ae6575d6e929e227bb7131f0883f94d |
| Converting REEC_B to REEC_A for Solar PV Generators.pdf | WECC conversion guidance and Table 2 example | a6fe566afec39b22368d1227d8b6145ee7d4350d1ae5dd100d415d2e4381c10c |
| 90260.pdf | REGFM_B1 VSM GFM Inverter Model Spec (Du et al., PNNL, 2024) | de52a0b7c8beec6d16d8e10b53a565d902ab1a79ef093ba3d6d80260a9287d50 |
| 83340.pdf | Ding et al., Dynamically Configurable GFM/GFL (NREL/Temple, 2022) | 2aeded379710e3f93e5f47e79a9eb98a2b9fd05e2b79d1fc1713f5d50a995727 |
| 1110-2002.pdf | IEEE Std 1110-2002, SG Modeling Practices (two byte-distinct copies) | historical recorded copy, not present locally: `2eb08ed83ea8c5d728a482d17777406ab37d01638f0eadb9848f01f9fb24b6c3`; current local validation copy: `90ee662b4e099dccf2154ead223a568831fb88ff45a99b15e2dcc05d4e62434f` |
| DynamicIEEETestSystems...pdf | Demetriou et al., Dynamic IEEE Test Systems (2015) | e5dd31403e2d375b8d0cab6005937fd3884e5a6e365cf936d5362f2f1cf047a8 |
| MODELING...IEEE14BUS...pdf | Kodsi, IEEE 14 Bus Modeling with FACTS (U.Waterloo TR 2003-3) | cf7d2120661e4050f96675378a4fca3601dd64fe1086ceead1d0c5d43db0a610 |
| Research_on_the_ratio_configuration_of_GFL_and_GFM.pdf | Zhang et al., GFL/GFM Ratio Config (J.Phys. 2025) | 8025d27d6ca834b77434caef952ae9db388722853e7f30b84aaa9c969b68501e |
| 2019-5.pdf | IEEE PSRC Meeting Minutes, Cincinnati May 2019 (91pp) | 23a1d63e2e77fa6ed65d3b33262dc568413446860181fc11b76de5f25e8d2445 |
| Synthetic_Benchmarks...pdf | Mohammadi & Saleh, Synthetic Benchmarks (IEEE Access 2021) | 417fa6c3fb35418ffa9ae87a04e50c87699d63a2d937029e75a3560751eb86f7 |
| IEEE 14-Bus System.zip | PowerWorld + PSS/E raw (UW archive 1993, flow only) | 94f873baf5ec07693a442bfdf1ef5e33326bfeeb837b31d9d968b4fb15bb7bcc |

The two IEEE-1110 hashes identify different file copies. The current local
copy is not claimed byte-identical to the historical recorded copy; equation
citations identify IEEE Std 1110-2002, while pagination-sensitive claims must
state which copy was inspected.

## Per-item source-closure status

### Item 1 — GFL positive-sequence model + state order

- **WECC Second Generation Generic WTG Models (2014), §§3.2-3.3 and
  Appendices A-B:** REGC_A converter-current lags, LVPL, low-voltage active
  current management, high-voltage reactive-current management, REEC_A
  electrical control, voltage-dip reactive-current injection, and P/Q
  priority current-limit logic are SOURCE_DEFINED block diagrams and tables.
- **WECC REEC_B-to-REEC_A conversion guidance, Table 2:** supplies the
  official example parameter profile used as the source-mapped starting
  point. The IEEE14 option selects constant P/Q control and P priority as
  CASE_DEFINED flags; it does not claim every example flag describes an
  actual plant.
- **Implemented state order (7, SOURCE_TRANSFORMED):**
  `[Vt_f,P_f,Iq_cmd_f,Pord,Vlvpl_f,Ip_reg,Iq_reg]`. Internal currents and
  powers use inverter base; the device ABI uses system base with
  `kappa=Sbase/Mbase`. The network current convention is positive injection
  and `S=V*conj(I)`.
- **Status: SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES.** The canonical
  implementation is `+ibr/wecc_regca_reeca_model.m`; `+ibr/gfl_model.m` is a
  compatibility wrapper. The former Ding-derived six-state model and
  `Kps/Kis` assumptions are off the runtime path. REGC_A remains a
  strong-grid current-source model, so the integrated selector must reject a
  GFL assignment when the implemented SCR contract is not satisfied.

#### Item 1b — GFL-RMS10 opt-in PROJECT_DERIVED composite (2026-07-18/19)

- **Yazdani & Iravani 2010** (`docs/text/6739364.pdf`, ISBN 978-0-470-52156-4):
  nonlinear SRF-PLL (eq 8.18-8.25, printed p.210-212), dq current plant
  (eq 8.45-8.46, p.219), current PI compensator (eq 8.53, p.221), V_t
  modulation (eq 8.47-8.48), per-unit bases (Appendix B Table B.1/B.2). Supplies
  6 of 10 states SOURCE_DEFINED.
- **Teodorescu, Liserre, Rodríguez 2011**
  (`docs/text/grid-converters-for-photovoltaic-and-wind-power-systems.pdf`,
  ISBN 978-0-470-05751-3): simple-PI SRF-PLL tuning (eq 4.37-4.38, §4.2.2);
  L-filter dq model with cross-coupling (eq 9.8, §9.2.1).
- **Bacha, Munteanu, Bratcu 2014** (`docs/text/978-1-4471-5478-5.pdf`,
  DOI 10.1007/978-1-4471-5478-5): anti-windup concept (p.286 "disable
  integrator during limitation").
- **Implemented state order (10, opt-in via `params.gfl_family='rms10'`):**
  `[delta_PLL, xi_PLL, P_f, Q_f, xi_P, xi_Q, xi_id, xi_iq, i_d, i_q]`.
  6 SOURCE_DEFINED (delta_PLL, xi_PLL, xi_id, xi_iq, i_d, i_q) + 4
  PROJECT_DERIVED (P_f, Q_f from REGFM_B1 Eq.1/3 filter pattern; xi_P, xi_Q
  from user §5.4 ODE).
- **LV policy (FROZEN):** no PLL freeze. Equilibrium requires
  `|V| >= V_valid_min`; balanced positive-sequence fault TS continues down to
  `V_div_min` using Teodorescu Ch.7 reactive-current-priority FRT structure and
  the frozen WECC REGC_A/REEC_A LVPL/current characteristic. Near-zero remains
  fail-closed with `ibr:gfl_rms10_model:lowVoltagePowerInversion`.
- **Generic-ABI integration:** plugs into the existing composite-device ABI
  (same closures as WECC/REGFM_B1). No GFL-specific PF/equilibrium/SSSA-A/TS
  solvers. `ibr_gfl_rms10` (10/2 standalone) + `ibr_dual_mode_rms10`
  (23-state dual, distinct device_type from legacy `ibr_dual_mode` 20-state).
- **Status:** `GFL_RMS10_NORMAL_OPERATION_READY = READY` (Profile B verified:
  equilibrium kcl~1e-14, 48 active SSSA states, event-free TS no-drift).
  `GFL_RMS10_BALANCED_POSITIVE_SEQUENCE_LVRT_READY = SOURCE_IMPLEMENTED_PENDING_FINAL_GATES`.
  `GFL_RMS10_UNBALANCED_OR_ZERO_VOLTAGE_LVRT_READY = NOT_READY`. Full provenance:
  `docs/project/IEEE14_IBR_GFL_RMS10_PROVENANCE.md`; frozen parameter
  manifest: `docs/project/IEEE14_IBR_GFL_RMS10_PARAMETER_MANIFEST.md`.

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
- **Gaps closed by the implemented contract:** (a) REGFM_B1 gives no explicit
  state vector — reconstructed as 13 states (PROJECT_DERIVED, frozen);
  (b) initialization is a PROJECT_DERIVED algebraic warm-start; (c) the
  Fig.6 upper/lower controllers are SOURCE_TRANSFORMED into two differential
  bound states; (d) conditional anti-windup is PROJECT_DERIVED because the
  source supplies limit blocks but no back-calculation law; and (e) the swing
  ODE is SOURCE_TRANSFORMED under frozen flag profile
  ωFlag=0, FFlag=1, ωref=1 pu: 2H·dωm/dt = P_ref_inv − Pinv_f − (1/mp+D1)·ωm
  − D2·(ωm − x_washout).
- **Status: SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES.** Implemented in
  `+ibr/regfm_b1_vsg_model.m` (13 states). Per-unit base contract
  (user-confirmed,
  FROZEN): external ABI on system base; internal swing/filters on inverter
  base (kappa=Sbase/Mbase); P_ref_inv=kappa·P_ref_sys (no double conversion).
  All REGFM parameters use the Table 1 example profile unless explicitly
  overridden for diagnostics. See
  `docs/project/IEEE14_IBR_GFM_PHASE6_PROVENANCE.md`.
- **Dual-mode ABI:** the superset is 20 states: REGFM G2 states 1:13 and WECC
  GFL states 14:20. No state is artificially shared because REGC_A/REEC_A has
  no PLL state. Inactive mode-unique states are exact holds (`dx=0`,
  PROJECT_DERIVED); explicit active-state reduction handles Newton and SSSA.
- **Phase 8 (IEEE14 builder):** `+ibr/build_ieee14_ibr_devices.m` builds
  real devices (IBR2@2, IBR3@3, IBR6@6, IBR8@8) with CASE_DEFINED Mbase
  nameplate proxy (IBR2=140, IBR3/6/8=100 MVA). The corrected solver checks
  every KCL row, solves explicit SG/GFM reference controls, supports exact
  one/two/three-GFM sets, and rejects a pure-GFL SG_OFF island.

### Item 3 — GFL↔VSG transfer maps + inactive-state rule — PROJECT_DERIVED IMPLEMENTED

- **Ding 83340 §IV-B (p. 5):** ONLY the concept "freeze the integral values
  in the inner loops at the time when the operation mode transition occurs.
  The frozen values will be used as the initial ones when the new operation
  mode starts." No equations. No bumpless transfer map. No shadow/tracking
  controller. No synchronism check. No inactive-state evolution rule.
  Different state dimensions (GFL 14 vs GFM 13) with no remapping formula.
- **REGFM_B1 90260:** no mode switching at all.
- **Status: PROJECT_DERIVED IMPLEMENTED.** The 20-state device owns the
  transfer callback. It measures the left-limit terminal current and power,
  calls the target mode's sourced equilibrium initializer, preserves the
  inactive branch exactly, and enforces `|I(t+)-I(t-)|<=1e-10`. There is no
  PLL carryover because WECC REGC_A/REEC_A has no PLL state. Integrated
  event-driving TS is still a separate readiness gate.

### Item 4 — Current limiter + anti-windup

- **REGFM_B1 90260, Eqs. 10-13, Figs. 5-7:** steady-state PQ priority
  (ImaxSS, IdmaxSS, IqmaxSS, kf, PQFlag); transient current limiting (ImaxF,
  algebraic circular saturation, Eq. 13); active-current limit via δIT
  integrator (Fig. 6, Eq. 12). **SOURCE_VERBATIM.**
- **Gap:** anti-windup logic for the voltage PI and the active-current
  integrator is NOT specified. Reset-to-zero described; no back-calculation
  or conditional-integration formula.
- **Status: G1+G2 IMPLEMENTED_PENDING_INTEGRATION_GATES.** G1 implements
  Eq.13 circular saturation, correct base conversion, and sourced Fig.4 PLL
  freeze. G2 implements PQ priority, Eqs.10-11, two Fig.6 dynamic angle-bound
  states, Emax/Emin behavior, and PROJECT_DERIVED conditional anti-windup.

### Item 5 — SG synchronism thresholds/dwell/timeout — CASE_DEFINED / INTEGRATION DEFERRED

- **2019-5.pdf:** IEEE PSRC committee MINUTES (not IEEE TR-121 itself).
  Mentions synchronism/out-of-step/auto-reclose conceptually (C37.242 PMU
  sync guide, out-of-step tripping tutorials, autoreclosing for distribution
  §5 "needs work"). No numerical thresholds (ΔV, Δf/slip, Δθ), no dwell, no
  timeout, no breaker-close-time prediction.
- **IEEE TR-121 itself:** NOT available locally.
- **Status: CASE_DEFINED, FROZEN; INTEGRATED RECLOSE DEFERRED.** Decision
  Ledger Item 5 freezes `ΔV_max=0.05 pu`, `Δf_max=0.001 pu`, `Δθ_max=10 deg`,
  `T_sync_dwell=0.5 s`, and `T_sync_timeout=5.0 s`. These are project design
  values, not SOURCE_DEFINED IEEE-TR-121 values. The guard primitive exists,
  but synchronism-enforced reclose in an event-driving TS is not complete and
  remains a NOT_READY blocker.

### Item 6 — Delays — CASE_DEFINED / PROJECT_DERIVED, INTEGRATION DEFERRED

- **No inspected source** provides protection/controller switching delays,
  T_sg_min_off, ρ, T_minimum_hold, T_guard, or T_lockout. Ding has none;
  REGFM_B1 has none; IEEE 1110-2002 has none; the GFL/GFM ratio paper has
  none.
- **Status: CASE_DEFINED / PROJECT_DERIVED, FROZEN.** Decision Ledger Item 6
  freezes `T_detect=0.05 s`, `T_logic=0.02 s`, `T_controller=0.05 s`,
  `T_up=0.12 s`, `T_sg_min_off=0.5 s`, `rho=0.05`,
  `T_minimum_hold=1.0 s`, `T_guard=0.3 s`, and `T_lockout=2.0 s`.
  `T_settle=ln(1/rho)/(-Omega_current)` is PROJECT_DERIVED. Integrated
  event-time enforcement and rollback remain deferred.

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
- **Approved resolution:** Decision Ledger Item 7 explicitly selects the Kodsi
  60 Hz Table A.2 profile for SG1, on its 615 MVA machine base, with no dataset
  mixing. This is a CASE_DEFINED choice; it does not claim that the source
  hierarchy selected one dataset unambiguously.
- **Status: CASE_DEFINED / IMPLEMENTED STRUCTURAL SG PROFILE.** The mission
  case and SG composite device use the selected Kodsi data. IEEE 1110-2002
  supplies model-structure, typical-data, and base-conversion guidance; Kodsi
  supplies the numerical profile. This resolution does not imply production
  readiness.

### Item 8 — Dispatch/energy contract resolving the post-trip deficit — CASE_DEFINED / EQUILIBRIUM-INTEGRATED

- **Case facts (recomputed):** load 259 MW, bus-1 Pg 232.4 MW, buses 2-8
  Pg 40 MW → 219 MW deficit after SG trip. Buses 2-8 Pmax 440 MW (aggregate
  feasible) but buses 3,6,8 at Pg=0 pre-trip.
- **No inspected source** provides a sourced post-trip reserve/participation/
  ramp/load-shed policy for IEEE14 with 4 IBRs.
- **Status: CASE_DEFINED / EQUILIBRIUM-INTEGRATED.** Decision Ledger Item 8
  freezes the Pmax-proportional schedules `109.7/49.8/49.8/49.8 MW`.
  In `6f48eff`, non-reference GFM active powers remain scheduled while exactly
  one selected reference-GFM P is solved as an equilibrium output to balance
  load and losses; every physical KCL row is retained. Pmax compliance alone
  does not prove `ImaxSS` compliance. G2 steady-state limiting and integrated
  ramp/energy/event validation remain deferred.

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
- **Status: CASE_DEFINED / STRUCTURAL CONTRACT IMPLEMENTED; EVIDENCE
  EVALUATION DEFERRED.** Decision Ledger Item 9 freezes `gamma_req=0.1 s^-1`
  before candidate evaluation. The selector carries this contract and
  enumerates deterministic exact-size subsets, but currently does not compute
  real topology/equilibrium/SSSA evidence; therefore `sssa_evaluated=false`
  and `ready_to_commit=false` remain mandatory.

## Summary: source closure is distinct from approved implementation

| # | Item | Status |
|---|------|--------|
| 1 | GFL positive-sequence model | WECC REGC_A/REEC_A 7-state SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES; strong-grid SCR applicability enforced by selector |
| 2 | VSG/VSM from REGFM_B1 | REGFM G2 13-state SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES |
| 3 | GFL↔VSG transfer maps | PROJECT_DERIVED 20-state physical transfer implemented and current-continuity tested; event-runner integration pending |
| 4 | Current limiter + anti-windup | G1 Eq.13/VPLL freeze and G2 Fig.5/Eqs.10-11/Fig.6/conditional anti-windup implemented pending integration gates |
| 5 | SG synchronism thresholds | CASE_DEFINED and frozen; guard primitive exists; integrated reclose deferred |
| 6 | Delays | CASE_DEFINED/PROJECT_DERIVED and frozen; event-time integration deferred |
| 7 | IEEE14 SG dynamic data | CASE_DEFINED Kodsi 60 Hz profile implemented for SG1 |
| 8 | Post-trip dispatch/energy contract | CASE_DEFINED schedule; physical all-KCL equilibrium and G2 limits implemented; integrated ramp/energy validation pending |
| 9 | `gamma_req` eigenvalue margin | CASE_DEFINED at `0.1 s^-1`; real topology/SCR/equilibrium/full-state-SSSA candidate evaluation implemented |

Historical source gaps were resolved where authorized through explicit
CASE_DEFINED or PROJECT_DERIVED decisions in the Decision Ledger. This does
not make them source-verbatim and does not imply production readiness. Mixed
equilibrium and equation-shared fixed-step TS/SSSA are implemented. The
remaining runtime closure is integrated automatic event driving, synchronism-
enforced SG reclose, selector/plot end-to-end verification, and independent
multi-case validation.

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

## Implemented generic foundations

- Phase 2 scheduled/guard event primitives are implemented.
- Phase 3 persistent hybrid-state and rollback primitives are implemented.
- The fixed-step automatic event driver, device-owned transfer, exact event
  landing, atomic right-limit rollback, synchronism transaction, status log,
  and two audited plots are integrated. This does not establish production
  readiness.

## Remaining readiness blockers

- The real-topology SCR/equilibrium/full-state-SSSA selector is connected and
  fail-closed, but no current IEEE14 post-trip subset passes frozen
  `gamma_req=0.1 s^-1`. Diagnose the sourced model/case result; do not tune the
  threshold after viewing outcomes.
- Adaptive IBR event stepping remains outside this fixed-step checkpoint.
- Obtain natural (non-override) synchronism/reclose and longer-horizon TS
  evidence for a feasible post-trip configuration.
- Complete independent multi-case validation and readiness derivation.
