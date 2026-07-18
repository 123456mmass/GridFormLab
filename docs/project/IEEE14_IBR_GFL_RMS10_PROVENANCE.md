# IEEE14 IBR GFL-RMS10 — Source Provenance Register

Date: 2026-07-18
Branch: `main`
Status: `PHASE_0_SOURCE_REGISTER_FROZEN`
       `SOURCE_DEFINED_NONLINEAR_CORE_CLOSED = YES`
       `FULL_SOURCE_DEFINED_GFL_MODEL = NO`
       `APPROVED_PROJECT_DERIVED_RMS10_SLICE = YES`
       `NUMERICAL_PARAMETER_PROFILE_FROZEN = NOT_YET` (see PARAMETER_MANIFEST)

This document records the per-state source register and classification for the
GFL-RMS10 device (`+ibr/gfl_rms10_model.m`). It is read-only provenance; it does
not edit production code. All citations were verified by direct `pdftotext`
extraction from the cached PDFs in `docs/text/`, not by Vision agent triage
(which hallucinated identity for two earlier candidates).

## Source identity (verified)

| Tag | File | Title | Authors | Year | ISBN/DOI | Pages |
|-----|------|-------|---------|------|----------|-------|
| A | `docs/text/6739364.pdf` | Voltage-Sourced Converters in Power Systems: Modeling, Control, and Applications | Amirnaser Yazdani, Reza Iravani | 2010 | ISBN 978-0-470-52156-4 | 473 |
| B | `docs/text/grid-converters-for-photovoltaic-and-wind-power-systems.pdf` | Grid Converters for Photovoltaic and Wind Power Systems | Remus Teodorescu, Marco Liserre, Pedro Rodríguez | 2011 | ISBN 978-0-470-05751-3 | 407 |
| C | `docs/text/978-1-4471-5478-5.pdf` | Power Electronic Converters Modeling and Control | Seddik Bacha, Iulian Munteanu, Antoneta Iuliana Bratcu | 2014 | DOI 10.1007/978-1-4471-5478-5 | — |

Identity confirmed by direct text extraction (title page, copyright page, ISBN).
No Vision agent was used for identity claims.

## State register (10 states, frozen order)

| # | State | ODE | Source | Ch/§/page/eq | Classification |
|---|-------|-----|--------|--------------|----------------|
| 1 | `delta_PLL` | dot = ω_b·(kp_PLL·v_q + ki_PLL·xi_PLL) | A eq 8.22-8.25 (printed p.211) + B §4.2.2 eq 4.31 | SOURCE_DEFINED |
| 2 | `xi_PLL` | dot = v_q | A Fig 8.4 VCO integrator (p.212) + B eq 4.30-4.31 | SOURCE_DEFINED |
| 3 | `P_f` | T_P·dot = P - P_f | PROJECT_DERIVED (REGFM_B1 Eq.1 filter pattern, `regfm_b1_vsg_model.m:654`) | PROJECT_DERIVED |
| 4 | `Q_f` | T_Q·dot = Q - Q_f | PROJECT_DERIVED (REGFM_B1 Eq.3 pattern, `regfm_b1_vsg_model.m:656`) | PROJECT_DERIVED |
| 5 | `xi_P` | dot = AW_P(P_ref - P_f) | PROJECT_DERIVED (user §5.4 ODE) | PROJECT_DERIVED |
| 6 | `xi_Q` | dot = AW_Q(Q_ref - Q_f) | PROJECT_DERIVED (user §5.4 ODE) | PROJECT_DERIVED |
| 7 | `xi_id` | dot = AW_id(i_d_ref - i_d) | A eq 8.53 (printed p.221, PI: kp·s+ki/s) + B §9 | SOURCE_DEFINED |
| 8 | `xi_iq` | dot = AW_iq(i_q_ref - i_q) | A eq 8.53 + B §9 | SOURCE_DEFINED |
| 9 | `i_d` | L·dot = L·ω_PLL·i_q - R_t·i_d + v_td - v_d | A eq 8.45 (printed p.219) + B §9 | SOURCE_DEFINED |
| 10 | `i_q` | L·dot = -L·ω_PLL·i_d - R_t·i_q + v_tq - v_q | A eq 8.46 (printed p.219) | SOURCE_DEFINED |

**Count: 6 SOURCE_DEFINED / 4 PROJECT_DERIVED.**

No PLL freeze state (LV is fail-closed — see plan §"Low-voltage policy").

## Frame, base, and dimensional contract

- **dq frame**: the PLL angle `delta_PLL` is the network→dq transformation angle
  (A eq 8.18-8.19: `v_sd = |V|·cos(θ-ρ)`, `v_sq = |V|·sin(θ-ρ)`; locked PLL → `v_sq=0`).
- **Network injection**: inverter dq current `(i_d, i_q)` is rotated to the
  network common-xy frame by `exp(1i·delta_PLL)` and divided by `kappa = Sbase/Mbase`
  (mirrors WECC `I = (Ip-1i·Iq)·exp(1i·angle(V))/kappa` and GFM `I_dq` inversion).
- **Power sign**: generator convention `S = V·conj(I_net)`, system base. `P>0`
  into the network; `Q>0` into the network.
- **ω_PLL dimensional contract (must freeze)**:
  `ω_PLL = ω_b·(1 + Δω_PLL) = ω_b + dot(delta_PLL)` [rad/s],
  where `Δω_PLL = kp_PLL·v_q + ki_PLL·xi_PLL` [pu], `ω_b = 2·π·fbase` [rad/s].
  The `L·ω_PLL` coupling term in eq 8.45/8.46 uses the instantaneous PLL frequency;
  `L` must be frozen so `ω_b·L` is the per-unit coupling reactance (see PARAMETER_MANIFEST).
- **V_t modulation (factor 1/2 absorbed by base convention)**: Yazdani eq 8.47
  `v_td = (V_DC/2)·m_d` in SI. In the project per-unit system `Vdc0` is stored in
  per-unit AC-voltage base (Yazdani Appendix B Table B.2: DC base = 2·AC base, so
  1.0 pu DC = 1.0 pu AC at unity modulation after the /2). The modulation clamp is
  `V_t_max = m_max·Vdc0` (the /2 is already absorbed by the base convention).
- **L convention**: `L` is the per-unit coupling **reactance** `X = ω_b·L_SI`
  (NOT per-unit inductance in seconds), matching the PF/WECC convention. The ODE
  uses `omega_PLL_pu·L` as the per-unit coupling term (`omega_PLL_pu = 1+Δω_PLL`)
  and divides by `L/ω_b` for the time derivative.
- **Current-controller feedforward (verified zero at equilibrium)**: includes
  `R_t·i` in addition to `v` and `ω·L·i`: `v_td = v_d + R_t·i_d - ω_PLL·L·i_q`,
  `v_tq = v_q + R_t·i_q + ω_PLL·L·i_d`. Verified: at the equilibrium initial
  state, the current-plant derivatives `dot(i_d)`, `dot(i_q)` are exactly zero
  (machine-epsilon residual ~1e-15), confirming the feedforward is complete and
  consistent with Yazdani eq 8.45/8.46.

## Limiter register (all PROJECT_DERIVED)

| Limiter | Realization | Source of pattern |
|---------|-------------|-------------------|
| Current magnitude (I_max) + P-priority | P-priority default; `i_d` capped, `i_q = ±sqrt(I_max²-i_d²)` | User §5.5; WECC REGC_A/REEC_A `PQFlag=1` analog |
| Anti-windup AW_P, AW_Q | One-sided conditional hold: outward hold, inward release. `AW_P(e_P)=0` when current limiter active AND `(P_cmd-P_lim)·e_P > aw_tol` | Bacha p.286 "disable integrator during limitation"; exact directional form PROJECT_DERIVED from REGFM_B1 `conditional_hold` (`regfm_b1_vsg_model.m:889-895`) |
| Anti-windup AW_id, AW_iq | `AW_id(e_d)=0` when voltage clamped AND `dot(r_v,[ki_i·e_d;0]) > aw_tol` | same |
| v_t vector clamp | `[v_td; v_tq]` scaled radially to `m_max·V_dc0/2` when exceeded | User §5.6; A eq 8.47-8.48 |
| Equilibrium init | `delta_PLL0=angle(V0)`, `xi_PLL0=0`, `v_d0=\|V0\|`, `v_q0=0`, `P_f0=P_ref_inv`, `Q_f0=Q_ref_inv`, `xi_P0=xi_Q0=0`, `i_d0=P_ref_inv/v_d0`, `i_q0=-Q_ref_inv/v_d0`, `xi_id0=xi_iq0=0` | PROJECT_DERIVED from ODEs set to zero (feedforward makes zero integrators exact) |
| Low-voltage | NO PLL freeze. Require `\|V\| >= V_valid_min` AND `D_V = v_d²+v_q² >= V_div_min²` before evaluating PLL/PQ-inversion/current-control; else fail-closed `ibr:gfl_rms10_model:voltageOutsideValidityDomain` / `lowVoltagePowerInversion` | User decision (unsourced in all 3 texts); LV freeze explicitly REJECTED |

`aw_tol` is a frozen NUMERICAL_METHOD comparison tolerance (not tuning).

## Per-unit base conversion (kappa = Sbase/Mbase)

Yazdani's per-unit system (Appendix B, PDF p.426-429) uses **peak line-to-neutral**
voltage base and rated three-phase power. The project uses the standard power-system
convention (rms line-to-neutral, system Sbase=100 MVA). The GFL-RMS10 device
follows the **same kappa boundary contract as WECC and REGFM_B1**:
`P_inv = kappa·P_sys`, `I_inv = kappa·I_sys`, where `kappa = Sbase/Mbase`.
All device-internal states run on the inverter base; `current_injection` and
`electrical_power` return system-base quantities. No double conversion. This
mirrors `wecc_regca_reeca_model.m:11-14` and `regfm_b1_vsg_model.m:33-39` exactly.

## Source-gap closure status (honest)

- `SOURCE_DEFINED_NONLINEAR_CORE_CLOSED = YES` — PLL angle+integrator (delta_PLL,
  xi_PLL), current plant (i_d, i_q), current PI integrators (xi_id, xi_iq): 6 of
  10 states sourced from Yazdani eq 8.22-8.25, 8.45-8.46, 8.53, cross-checked
  against Teodorescu §4.2.2 / §9.
- `FULL_SOURCE_DEFINED_GFL_MODEL = NO` — P/Q filters (P_f, Q_f), outer-loop
  realization (xi_P, xi_Q), all limiters, anti-windup directional logic, LV
  fail-closed, and equilibrium init remain PROJECT_DERIVED (user-authorized).
- `APPROVED_PROJECT_DERIVED_RMS10_SLICE = YES` — user approved the composite.
- `NUMERICAL_PARAMETER_PROFILE_FROZEN = NOT_YET` — see PARAMETER_MANIFEST.
  Production routing to `build_ieee14_ibr_devices` / `dual_mode_ibr_model` stays
  blocked until every numerical parameter is frozen.

This REOPENS Phase 0B by explicit user authorization of a PROJECT_DERIVED RMS10
composite. It is NOT a discovery of a complete source-defined GFL model. The
historical "no complete source-defined GFL model was found" (Phase 0B audit)
remains true; this is the user-authorized PROJECT_DERIVED alternative path.

## Generic-ABI integration (user-mandated)

GFL-RMS10 integrates through the existing generic composite-device ABI used by
SG EMF6 (nx=6) and REGFM_B1 GFM (nx=13). No GFL-specific PF/equilibrium/SSSA-A/TS
solvers. The device supplies only `f`, `current_injection`, `electrical_power`,
`reconstruct`, `equilibrium_initialize`, `state_names`, `input_names`, `nx`,
`nu`, `active_state_indices`. SSSA differentiates the SAME production equations
integrated by TS. Profile B assembles
`x = [x_SG1(6); x_GFM_IBR2(13); x_GFL_IBR3(10); x_GFL_IBR6(10); x_GFL_IBR8(10)]`
(nx≈49) via composite_dae global indexing.

## Vision agent hallucination note (carried from Phase 0B audit)

Two Vision agent triages hallucinated document identity and must not be trusted
without independent verification:
- IBR1.pdf: claimed IEEE PES-TR71 2024 — actually Engler & Hardt IECON 2000.
- Bao et al.: claimed Rangarajan et al. 2024 PEMC — actually NAPS 2025 EMT.

All material findings in this register were verified by direct `pdftotext`
extraction, NOT by unverified Vision agent claims.
