# IEEE14 1-SG + 4-IBR Mission — Frozen Mathematical Contract (Phase 1)

**Status:** `IEEE14_IBR_EQUATION_CONTRACT_READY` = `PARTIAL` (6 genuine stop
gaps remain; see source matrix).
**Branch:** `feature/ieee14-auto-vsg-switching`. **Date:** 2026-07-13.

This document freezes the mathematical profile that CAN be source-closed
from the primary sources the user provided, and explicitly fences the items
that remain genuine stop conditions. Per the user directive, autonomous
selection used the predeclared hierarchy where alternatives existed.

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

## VSG/GFM model (item 2 — FROZEN, source-closable)

- **Profile:** REGFM_B1 (NREL 90260). VSM swing-equation block (Fig. 2) +
  voltage-source-behind-impedance (Eq. 13) + measurement filters (Eqs. 1-5)
  + Q-V droop + voltage PI (Fig. 3) + PQ priority + transient current
  limiting (Eqs. 10-13, Figs. 5-7). GFM-only.
- **State vector (reconstructed from REGFM_B1 block diagrams,
  PROJECT_DERIVED):** x_vsg ≈ [Δωm, δIT, x_Eint (voltage PI integral),
  x_PLL_int, δPLL, Pinv_f, Idinv_f, Qinv_f, Vinv_f, Iqinv_f, x_washout (D2),
  x_Idlim (active-current integrator)] — ~12-13 states. Exact dimension
  finalized in Phase 6 after state-layout design. CONDITIONAL on Tp>0 adds
  one LPF state.
- **Output stage (Eq. 13, VERBATIM):** I∠φ = (EVSM∠δVSM − V∠δV)/(Re+jXL)
  for |I|<ImaxF; I∠φ = ImaxF∠φ (transient limit) otherwise.
- **Parameters (REGFM_B1 Table 1 example values, CASE_DEFINED if IEEE14
  IBR converters adopt the REGFM_B1 default profile):** H=0.5, D1=0, D2=100,
  ωD=50, mp=0.02, mq=0.05, kpv=0, kiv=5, Re=0, XL=0.1, ImaxSS=1.0, ImaxF=1.5,
  kf=0.9, kI=2, PQFlag=1, plus measurement filter time constants TPf=TQf=
  TVf=TIf=0.02s. (These are the spec's EXAMPLE values; using them as the
  IEEE14 IBR converter profile is a CASE_DEFINED engineering choice, not
  fitting, since they come from the authoritative spec's recommended
  defaults.)
- **Initialization:** PROJECT_DERIVED from the model structure (REGFM_B1
  gives only flag-dependent notes, no equations). To be derived in Phase 5.
- **GAPS (fenced, not production):** no explicit anti-windup; no mode
  switching (REGFM_B1 is GFM-only).

## GFL model (item 1 — PARTIAL, reduction decision required)

- **Full EMT GFL (Ding 83340 §II-B, Eqs. 8-10 + 3-6):** 14-state LCL model
  with SRF-PLL. SOURCE_VERBATIM. BUT this is an EMT/LCL model, not a
  positive-sequence RMS model compatible with the project DAE.
- **Positive-sequence RMS GFL (target):** standard utility representation
  = current-source behind coupling reactance with PLL-synchronized angle.
  ⛔ No inspected source states its reduced-order state equations
  explicitly. The reduction from Ding's EMT to RMS is a DECISION_REQUIRED
  semantic choice. → Blocks Phase 5 (GFL model) until resolved.

## GFL↔VSG transfer + inactive-state rule (item 3 — ⛔ STOP)

- Ding §IV-B gives ONLY the "freeze integrals" concept (no equations, no
  map, no shadow controller, no synchronism check, no inactive-state
  evolution). REGFM_B1 has no mode switching.
- ⛔ A bumpless transfer map and inactive-state rule cannot be sourced
  without inventing a semantic choice. → Blocks Phase 6 and mode-switching
  missions (Phases 10-11).

## Current limiter + anti-windup (item 4 — PARTIAL)

- REGFM_B1 Eqs. 10-13 + Figs. 5-7: steady-state PQ priority + transient
  circular saturation. SOURCE_VERBATIM.
- ⛔ Anti-windup logic NOT specified. → Blocks Phase 12 (physical FRT)
  until sourced or derived.

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
- **Phase 5** (GFL model) — item 1 (RMS reduction decision).
- **Phase 6** (dual-mode transfer) — item 3.
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
