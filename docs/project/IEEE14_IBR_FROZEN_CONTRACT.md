# IEEE14 1-SG + 4-IBR Mission — Frozen Mathematical Contract (Phase 1)

**Status:** `IEEE14_IBR_EQUATION_CONTRACT_READY` = `PASS` for the implemented
structural slice; `IBR_PRODUCTION_INTEGRATION_READY = NOT_READY`.
**Branch:** `main`. **Last corrective update:** 2026-07-15.

This document freezes the mathematical profile that CAN be source-closed
from the primary sources the user provided, and explicitly fences the items
that remain genuine stop conditions. Per the user directive, autonomous
selection used the predeclared hierarchy where alternatives existed.

## 2026-07-15 authoritative corrective addendum

This section supersedes older phase/deferred statements below where they
conflict. The canonical acceptance classes are `SOURCE_DEFINED`,
`CASE_DEFINED`, `PROJECT_DERIVED`, `NUMERICAL_METHOD`, and
`ASSUMED_DIAGNOSTIC`. Legacy `SOURCE_VERBATIM` and `SOURCE_TRANSFORMED` labels
are documentary sublabels of `SOURCE_DEFINED`, not additional readiness
classes.

### Physical reference and KCL contract

- A gauge removes a voltage coordinate; it never removes a physical KCL row.
- Every equilibrium, audited SSSA, and audited TS point retains all `2*nb`
  rectangular rows of `g = Y*V - Iinj`.
- Online SG REF:
  `z=[x_active; y except Re/Im(Vref); Tm; Efd]`,
  `R=[f_active; all KCL]`; the case REF magnitude and angle are fixed.
- SG_OFF GFM REF:
  `z=[x_active; y except Im(Vref); P_ref_reference]`,
  `R=[f_active; all KCL]`.
- `u_eq`, the immutable hybrid context, and authenticated state maps are shared
  by equilibrium, SSSA, and TS. Solved reference controls are held constant in
  TS; there is no per-step re-slack.

### Exact selected-GFM contract

- `n_gfm_required` is explicit and may be 1, 2, 3, or larger.
- `selected_gfm_indices` must equal the complete online runtime GFM set.
- Exactly one selected member is `reference_resource_index`; the other
  selected resources remain physical GFMs.
- The tuple is atomic and owned by the hybrid snapshot. Conflicting duplicate
  metadata, offline/incapable members, count drift, order drift, or a reference
  outside the set fails closed.
- When an SG is online it owns the case REF; the committed GFM reference becomes
  the numerical reference only on the SG_OFF right limit.

### Current implementation boundary

- SG1 uses the approved Kodsi 60 Hz CASE_DEFINED profile. `Tpq0=0` is treated
  as the sourced singular limit with `Edp=0` frozen before Newton/eig.
- SG device input ABI is `u=[Tm;Efd]`. At the REF equilibrium both are solved
  outputs. The old PF `Pg=232.4 MW` is not frozen as an input.
- Phase-G1 implements REGFM_B1 Eq.13 transient clamp and Fig.4 PLL freeze:
  `Z_sys=kappa*(Re+jXL)`, `ImaxF_sys=ImaxF/kappa`, circular current clamp, and
  `|V|<VPLLfrz=0.05` freezes both PLL derivatives.
- Phase-G2 still defers Emax/Emin actuator behavior, anti-windup, PQ priority,
  Fig.6 `kI/s`, and Eqs.10-11.
- Inactive online dual-mode states are exact holds (`dx=0`). Offline SG states
  are excluded only from equilibrium/SSSA and evolve through breaker-open
  coast/open-circuit equations in TS while injecting zero current.
- Composite Ybus includes `diag((GS+j*BS)/baseMVA)`.

## Conventions (all SOURCE-backed, frozen)

- **Per-unit base:** system base S_base = 100 MVA (IEEE14 case baseMVA);
  f_base = 60 Hz (case frequency, corrected from any 50 Hz default per AGENTS
  rule 7). ω_base = 2π·f_base = 120π rad/s. Inverter-base conversion factor
  S_base/M_base for REGFM_B1 measurement filters (REGFM_B1 Eqs. 1-5).
- **Current direction:** positive INTO network / OUT of generator/inverter
  (generator convention; Padiyar Sec 3.2.2 p.47; IEEE 1110-2002 Clause 4.1).
  This matches the Track A composite canonical `g = Y·V − Ibus` (positive
  injection). NO production sign adapter.
- **Complex power:** S = V·conj(I) (generator convention; Padiyar p.47 prose).
- **Network KCL:** g = Y·V − I_inj (residual form; Padiyar Eq.5.27 p.157).
- **Shared y:** y = [Re(V1), Im(V1), ..., Re(Vnb), Im(Vnb)]^T (interleaved;
  Track A composite-owned).
- **Reference frame:** network common xy frame; PLL-rotated dq for inverter
  internal quantities (REGFM_B1 Eqs. 6-9). The composite holds y in the
  network frame; devices convert internally.

## SG1 dynamic model (item 7 — FROZEN STRUCTURE, VALUES PENDING)

- **Model:** IEEE 1110-2002 Model 2.2 (round-rotor, 6th-order subtranscent;
  Clause 5.3.2 p.20; d-axis Eq. 13/20-23, q-axis Eq. 24-26). Equivalent to
  the project's existing `emf6_dae`. Stator voltage Eqs. (C.4)-(C.5);
  electromagnetic torque Eq. (C.1).
- **Swing equation:** `2H·dω/dt = Pm − Pe − D·(ω − ω_ref)`; `dδ/dt = ω − ω_ref`.
  IEEE 1110-2002 delegates H/D/swing to Kundur [B54] (NOT locally available).
  The project's existing `classical_dae`/`emf6_dae` already implement this
  form; the swing-equation STRUCTURE is sourced via the existing SG path
  (Padiyar/Kundur provenance already in repo).
- **VALUES:** ⛔ STOP. IEEE14 case has no `.machines`. Two conflicting typical
  datasets (Demetriou 50 Hz/448 MVA vs Kodsi 60 Hz/615 MVA, both Anderson &
  Fouad). IEEE 1110-2002 permits typical data for planning but does NOT
  endorse Anderson & Fouad. Hierarchy does not identify one unambiguously.
  → Requires a user-provided sourced IEEE14 dynamic dataset OR explicit
  approval of one typical dataset as CASE_DEFINED.

## VSG/GFM model (item 2 — CLOSED, Phase 6 implemented)

- **Profile:** REGFM_B1 (NREL 90260). VSM swing-equation block (Fig. 2) +
  voltage-source-behind-impedance (Eq. 13) + measurement filters (Eqs. 1-5)
  + Q-V droop + voltage PI (Fig. 3) + PQ priority + transient current
  limiting (Eqs. 10-13, Figs. 5-7). GFM-only.
- **State vector (11, PROJECT_DERIVED, FROZEN):** x_gfm = [omega_m, delta_VSM,
  x_washout, x_Eint, delta_PLL, x_PLL_int, Pinv_f, Idinv_f, Qinv_f, Vinv_f,
  Iqinv_f]. Implemented in `+ibr/regfm_b1_vsg_model.m`.
- **Per-unit base contract (user-confirmed, FROZEN before results):** external
  ABI on SYSTEM base (Sbase=100 MVA); internal swing/filters on INVERTER base
  (kappa=Sbase/Mbase); P_ref_inv=kappa·P_ref_sys (NO double conversion);
  current_injection + reconstructed P/Q return on system base. Mbase =
  CASE_DEFINED unity-PF nameplate proxy (IBR2=140, IBR3/6/8=100 MVA; NOT
  Pmax-MW proven).
- **VSM swing (Fig. 2, SOURCE_TRANSFORMED, FROZEN under flag profile
  ωFlag=0, FFlag=1, ωref=1 pu):** 2H·dωm/dt = P_ref_inv − Pinv_f −
  (1/mp+D1)·ωm − D2·(ωm − x_washout); dx_washout/dt = ωD·(ωm − x_washout);
  dδVSM/dt = ω0·ωm. Steady state ωm = mp·(P_ref_inv − Pinv_f) = P-f droop.
- **Output stage (Eq. 13, Phase-G1 implemented):** on the system base,
  `I_unc=(EVSM*exp(j*deltaVSM)-Vbus)/(kappa*(Re+jXL))` and
  `ImaxF_sys=ImaxF/kappa`. Below the threshold `Iout=I_unc`; at/above it the
  output is the angle-preserving circular clamp. One shared helper supplies
  RHS filters, network current, electrical power, and reconstruct.
- **Parameters (REGFM_B1 Table 1 example values, CASE_DEFINED):** H=0.5, D1=0,
  D2=100, ωD=50, mp=0.02, mq=0.05, kpv=0, kiv=5, Re=0, XL=0.1, ImaxSS=1.0,
  ImaxF=1.5, kf=0.9, kI=2, PQFlag=1, TPf=TQf=TVf=TIf=0.02s. All SOURCE_VERBATIM
  from Table 1; NO ASSUMED_DIAGNOSTIC (unlike GFL Kps/Kis).
- **Inputs (nu=2):** u=[P_ref; V_ref] (pu, system base), SOURCE_TRANSFORMED/
  PROJECT_MAPPED (frozen flags VdrpFlag=0, QVFlag=1).
- **Initialization (PROJECT_DERIVED, warm-start; Newton refines):** ωm0=0,
  x_washout0=0, δVSM0=angle(V0), x_Eint0=0, δPLL0=angle(V0), x_PLL_int0=0,
  Pinv_f0=κ·P_ref_sys, Qinv_f0=0, Vinv_f0=|V0|, Idinv_f0/Iqinv_f0=0.
- **STATUS:** `PHASE_G1_LIMITER_READY = IMPLEMENTED_STRUCTURAL_ONLY`.
- **GAPS (fenced, not production):** no Emax/Emin actuator handling,
  anti-windup, steady-state PQ-priority limiter, Fig.6 integrator, or complete
  event-driven FRT. These remain Phase-G2 work.

## Dual-mode fixed-layout device (item 3 interim — Phase 7 implemented)

- **Superset (15, CONSTANT across 'gfl'|'GFM'|'tripped'):** shared PLL (2:
  delta_PLL, x_PLL_int) + GFM-unique (9) + GFL-unique (4). Implemented in
  `+ibr/dual_mode_ibr_model.m`. Reuses GFL (Phase 5) + GFM (Phase 6) as
  single source of truth (no equation duplication).
- **Inactive-state rule:** inactive online mode-unique states are exact holds
  (`dx=0`, PROJECT_DERIVED). Explicit active-state reduction removes their
  rows/columns before Newton and eig; no artificial decay pole remains.
- **Inputs (nu=3):** u=[P_ref; Q_ref; V_ref]; mode selects subset.

## GFL model (item 1 — STRUCTURAL_ONLY, Phase 5 frozen)

- **Full EMT GFL (Ding 83340 §II-B, Eqs. 8-10 + 3-6):** 14-state LCL model
  with SRF-PLL. SOURCE_VERBATIM. BUT this is an EMT/LCL model, not a
  positive-sequence RMS model compatible with the project DAE.
- **Positive-sequence RMS GFL (Phase 5 freeze, PROJECT_DERIVED reduction):**
  current-source (NOT behind coupling reactance) with PLL-synchronized angle,
  the standard utility representation. The reduction from Ding's EMT to RMS
  is PROJECT_DERIVED (ideal-inner-loop + LCL elimination); see
  `IEEE14_IBR_GFL_PHASE5_PROVENANCE.md`.
- **State vector (frozen, 6 states, PROJECT_DERIVED order):**
  `x_gfl = [delta_pll, eps_pll, P_f, Q_f, phi_P, phi_Q]^T`.
  The earlier "~6-8 states" range is CLOSED at 6. Ding Eq.9 defines phi_P/phi_Q
  as differential PI-integrator states; Ding Eq.10 defines i_d*/i_q* as
  ALGEBRAIC current references (NOT states). No current-reference filter
  states, no new time constant.
- **PLL equation form (frozen):** `d(eps_pll)/dt = Vq_pll`,
  `d(delta_pll)/dt = omega0*(kpPLL*Vq_pll + kiPLL*eps_pll)` (omega0 multiplier
  PRESENT; relative network frame so the omega_n term drops). REGFM_B1 PLL
  output limits and low-voltage freeze deferred to Phase 14 (FRT).
- **Q-sign (frozen):** `i_q* = -Kps*(Qref - Q_f) - Kis*phi_Q` (negative,
  because Q = -V0*i_q* at lock). `i_d* = +Kps*(Pref - P_f) + Kis*phi_P`.
- **Base (frozen):** system base only (S_base = 100 MVA); NO Mbase, NO
  Sbase/Mbase conversion factor. IEEE14 IBRs are grid-connected on the
  system base.
- **Parameters (frozen BEFORE results):**
  - `omega0 = 376.99 rad/s` (SOURCE_VERBATIM, REGFM_B1 Table 1 omega0);
  - `omega_c = 10 rad/s` (SOURCE_VERBATIM, Ding Table I);
  - `kpPLL = 0.265 pu`, `kiPLL = 2.65 pu/s` (SOURCE_VERBATIM values from
    REGFM_B1 Table 1; CASE_DEFINED/PROJECT_MAPPED application to the GFL);
  - `Kps = 1.0`, `Kis = 10.0 s^-1` (ASSUMED_DIAGNOSTIC — Ding Table I lacks;
    a-priori critically-damped rationale; excluded from production acceptance).
- **Constructor inputs (corrective patch):**
  `gfl_model(device_id, bus_id, bus_position, bus_ids, V0, params, P_ref_pu, Q_ref_pu)`,
  `nu=2`, `u=[Pref;Qref]`. `V0` is the **complex** PF-solved bus voltage
  (`delta_pll0 = angle(V0)`, `|V0|` for PI init). `bus_ids` is the network's
  external bus-ID vector; `bus_ids(bus_position) == bus_id` is validated
  (else `:busMappingMismatch`). A real `V0` is accepted (angle 0).
- **Fail-closed input contract (corrective patch):** `u_dev` MUST be a
  2-element finite vector; empty → `:missingInput`, non-finite/wrong-size →
  `:badInput`. No silent fallback.
- **Parameter override (corrective patch):** any overridden parameter is
  validated (finite, positive) and reclassified `DIAGNOSTIC_ONLY` in the
  provenance; frozen defaults keep their original classification.
- **Status:** `IEEE14_IBR_GFL_MODEL_READY = STRUCTURAL_ONLY`. Runtime
  equilibrium/SSSA/TS sharing is now implemented, but `Kps/Kis` remain
  `ASSUMED_DIAGNOSTIC`; therefore this cannot support production readiness.

## GFL↔VSG transfer + inactive-state rule (item 3 — ⛔ STOP)

- Ding §IV-B gives ONLY the "freeze integrals" concept (no equations, no
  map, no shadow controller, no synchronism check, no inactive-state
  evolution). REGFM_B1 has no mode switching.
- ⛔ A bumpless transfer map and inactive-state rule cannot be sourced
  without inventing a semantic choice. → Blocks the GFL↔GFM transfer /
  mode-switching missions (Phases 10-11). This does NOT block Phase 6 (the
  GFM/VSG model, which proceeds from item 2).

## Current limiter + anti-windup (item 4 — G1 PARTIAL IMPLEMENTATION)

- G1 implemented the SOURCE_DEFINED Eq.13 transient circular saturation and
  sourced Fig.4 `VPLLfrz` behavior with PROJECT_DERIVED base conversion.
- G2 defers Eqs.10-11 steady-state PQ priority, Fig.6 active-current
  integrator, Emax/Emin actuator logic, and PROJECT_DERIVED anti-windup.

## SG synchronism (item 5 — ⛔ STOP)

- 2019-5.pdf = IEEE PSRC minutes (not TR-121). No numerical thresholds.
- ⛔ IEEE TR-121 itself not available. → Blocks Phase 11.

## Delays (item 6 — ⛔ STOP)

- No inspected source. → Blocks Phases 10-11.

## Dispatch/energy contract (item 8 — ⛔ STOP)

- 219 MW post-trip deficit. No sourced reserve/participation/ramp/load-shed
  policy. → Blocks Phase 4 (mixed equilibrium) and Phase 8 (case/dispatch).

## Selection margin γ_req (item 9 — ⛔ STOP)

- Ding: "sufficiently negative" only. GFL/GFM ratio paper: PM ≥ 30°
  (impedance-based, different domain). No eigenvalue-based normative value.
  → Blocks Phase 8 (selector) until resolved.

## Autonomous selections made (hierarchy applied)

1. **VSG profile = REGFM_B1** (hierarchy b: complete standard profile
   applicable to the GFM device class). Rejected: Ding's droop GFM (not
   VSG), Zhong & Weiss synchronverter (conceptual, no verbatim match).
2. **SG model structure = IEEE 1110-2002 Model 2.2** (hierarchy b: complete
   standard profile; the project's existing emf6_dae already implements
   this). Values PENDING (hierarchy a not satisfiable — conflicting data).
3. **KCL/sign/per-unit conventions** = Track A composite canonical (YV-I,
   positive injection, system base) — consistent with all sources.

## What proceeds autonomously (generic, no missing decision)

- **Phase 2** — generic scheduled+guard event architecture (synthetic
  fixtures; does not require GFL/VSG models or dispatch contract).
- **Phase 3** — persistent hybrid-state/rollback contract (synthetic
  fixtures).

## What is blocked (genuine stop, evidence-backed handoff)

- **Phase 4** (mixed equilibrium) — item 8.
- **Phase 5** (GFL model) — STRUCTURAL_ONLY (done; RMS reduction
  PROJECT_DERIVED, Kps/Kis ASSUMED_DIAGNOSTIC). Production readiness pending
  source-closing the ASSUMED_DIAGNOSTIC gains and the Phase 9 mixed-
  equilibrium integration.
- **Phase 6** (GFM/VSG model) — proceeds from item 2 (PARTIAL-TO-CLOSEABLE);
  NOT blocked by item 3.
- **GFL↔GFM transfer / mode-switching** (Phases 10-11) — item 3.
- **Phases 7-17** — depend on 5/6.
- **Phases 10-13** — items 5, 6.

## Smallest user decisions needed (to unblock)

1. **IEEE14 SG dynamic dataset** (item 7): provide a sourced dataset OR
   explicitly approve one typical dataset (Demetriou or Kodsi) as
   CASE_DEFINED with documented limitations.
2. **GFL positive-sequence RMS reduction** (item 1): approve a specific
   reduced-order GFL state vector (e.g., PLL angle + frequency + P/Q
   current references) sourced from the standard utility representation,
   OR provide a source that states it explicitly.
3. **GFL↔VSG transfer map + inactive-state rule** (item 3): approve a
   specific sourced or derived policy (e.g., frozen inactive states with
   documented zero-eigenvalue handling per correction 6).
4. **SG synchronism thresholds** (item 5): provide IEEE TR-121 or approve
   sourced thresholds (ΔV, Δf/slip, Δθ, dwell, timeout).
5. **Delays** (item 6): provide sourced T_up, T_sg_min_off, ρ, T_minimum_hold,
   T_guard, T_lockout values OR approve a sourced standard.
6. **Dispatch/energy contract** (item 8): provide a sourced post-trip
   reserve/participation/ramp/load-shed policy resolving the 219 MW
   deficit.
7. **γ_req** (item 9): provide a sourced eigenvalue-based margin OR approve
   converting PM ≥ 30° to an equivalent eigenvalue criterion with
   documented assumptions.
