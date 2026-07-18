# IEEE14 IBR Phase 0B — GFL Source Audit Record

Date: 2026-07-18
Status: `PHASE_0B_SOURCE_DECISION = NO_SOURCE_APPROVED`
       `PHASE_0B_STATUS = SOURCE_GAP_BLOCKED`
       `PHASE_4_EXPLICIT_STATE_NONLINEAR_GFL = BLOCKED`
       `PHASE_5_PF_SSSA_TS_ROUTING = BLOCKED`
Branch: `main`

This record documents the bounded authoritative search for a nonlinear
positive-sequence/average-model GFL (grid-following inverter) source with
explicit PLL and controller states, covering the frozen 10-item Phase 0B
checklist in `IEEE14_IBR_DYNAMIC_EQUATION_CONTRACT.md` §10.

## Decision

No authoritative nonlinear positive-sequence PLL-resolved GFL source or
compatible authoritative source set was found that jointly supplies the
frozen ten-item contract. Phase 0B ends `NO_SOURCE_APPROVED /
SOURCE_GAP_BLOCKED`. Phases 4 and 5 remain blocked.

## The 10-item checklist (frozen)

1. nonlinear SRF-PLL angle and integrator ODEs
2. phase detector and dq convention
3. PLL gains, base, limits, low-voltage freeze/reset behavior
4. P/Q measurement dynamics (LPF)
5. active/reactive outer-controller ODEs
6. current-command/current-controller dynamics
7. network-frame current injection
8. current magnitude limit and P/Q priority
9. anti-windup and recovery
10. equilibrium initialization for every state

(plus: system/device per-unit conversion, complete parameter table,
positive-sequence/average-model validity domain, PF/SSSA/nonlinear TS
compatibility)

## Candidate audit matrix

| # | Source | Identity verified | Domain | Verdict | Reason |
|---|--------|-------------------|--------|---------|--------|
| 1 | Yazdani & Iravani 2010 (textbook, ISBN 978-0-470-52156-4) | YES (pdftotext direct) | dq-frame, nonlinear actual-variable, positive-sequence-compatible | **STRONG_SECONDARY_SOURCE_ONLY** — FAIL as sole source | 4 PASS / 2 PARTIAL / 4 NOT FOUND; missing P/Q LPF, I_max+priority, anti-windup, equilibrium init, LV freeze |
| 2 | Alassaf et al. MDPI Sustainability 2023, 15, 8400 | YES | SI units, device-on-stiff-source | FAIL | no P/Q outer loop, no I_max/priority/anti-windup, no PF init, no network coupling, not positive-sequence |
| 3 | Li et al. Global Energy Interconnection 2023 (DOI 10.1016/j.gloei.2023.06.010) | YES | linearized Δ-variables | FAIL | LINEARIZED-ONLY — no nonlinear actual-variable ODEs; cannot serve nonlinear TS/PF |
| 4 | IBR1.pdf | REFUTED (was claimed IEEE PES-TR71) | actually Engler & Hardt IECON 2000, algebraic droop GFM | REJECT | not a GFL source; Vision agent hallucinated identity (title/authors/venue/year/DOI all wrong) |
| 5 | Bao, Fan, Miao, Ramasubramanian NAPS 2025 (DOI 10.1109/NAPS58625.2025.11273377) | YES | EMT/SimPowerSystems | FAIL | no GFL equations (eqs 1-2 are GFM current saturation, not GFL PLL); Vision agent hallucinated identity & equations |
| 6 | Ding et al. NREL/CP-6A40-83340 2022 | YES | EMT/LCL 14-state | REJECT | EMT/LCL not positive-sequence; D15 removed unsourced RMS reduction; user policy forbids restoring Kps/Kis |
| 7 | REGFM_B1 NREL/TP-5D00-90260 2024 | YES | GFM voltage-source-behind-impedance | REJECT | GFM-only; user policy forbids reusing GFM PLL gains as GFL parameters |
| 8 | Fu et al. IEEE JESTIE 2024 | YES | linear small-signal | REJECT | LINEAR_DIAGNOSTIC_ONLY; user policy freezes this |
| 9 | IEEE Std 1110-2002 | YES | SG modeling | REJECT | SG-only, no GFL |

## Yazdani & Iravani 2010 — detailed audit (verified via pdftotext)

Identity confirmed by direct text extraction (not Vision agent, to avoid
hallucination observed in other candidates):

- Title: "VOLTAGE-SOURCED CONVERTERS IN POWER SYSTEMS: Modeling, Control, and Applications"
- Authors: Amirnaser Yazdani (University of Western Ontario), Reza Iravani (University of Toronto)
- Publisher: IEEE Press / John Wiley & Sons, 2010
- ISBN: 978-0-470-52156-4 (cloth)
- 473 pages

### Per-item verdict (with page/equation evidence)

| Item | Verdict | Evidence |
|------|---------|----------|
| 1. nonlinear SRF-PLL ODEs | **PASS** | eq (8.11)-(8.13) p.210-211: `L·di_d/dt = L·ω(t)·i_q − (R+r_on)·i_d + V_td − Ṽ_s·cos(ω_0 t+θ_0−ρ)`, `dρ/dt = ω(t)`; "The system described by (8.11)-(8.13) is nonlinear" (p.210) |
| 2. phase detector & dq | **PASS** | eq (8.18)-(8.19) V_sd=Ṽ_s·cos(...), V_sq=Ṽ_s·sin(...); eq (8.23) ω(t)=H(p)·V_sq(t); §8.3.4 PLL |
| 3. PLL gains/base/limits/LV freeze | **PARTIAL** | gains+saturation ✓ (eq 8.25, Fig 8.4 "Saturation" block, compensator eq 8.38); Appendix B per-unit ✓ (p.426-430); **LV freeze NOT FOUND** |
| 4. P/Q measurement LPF | **NOT FOUND** | pdftotext search "measurement filter"/"measured P"/"measured Q" — no LPF on measured P_s/Q_s (LPFs found are for harmonic filter and PLL, not P/Q) |
| 5. P/Q outer-controller ODEs | **PARTIAL** | dq-frame reduces P/Q to algebraic references: eq (8.41)-(8.44) i_dref=2·P_sref/(3·V_sd), i_qref=−2·Q_sref/(3·V_sd); no differential outer-loop state |
| 6. current-controller + L_f | **PASS** | eq (8.45)-(8.46) RL plant; eq (8.53) PI compensator k_d(s)=(k_p·s+k_i)/s; eq (8.55)-(8.57) pole placement |
| 7. network current injection | **PASS** | eq (8.86)-(8.87) Z̲·i_dq = V_tdq − V_sdq; eq (8.88)-(8.89) phasor power |
| 8. I_max + P/Q priority | **NOT FOUND** | "saturation blocks on i_dref/i_qref" mentioned (p.208) but NO priority logic, NO I_max value; footnote p.371 "saturation limit on current amplitude is picked 10-20% higher than rated value" — concept only, no equation |
| 9. anti-windup & recovery | **NOT FOUND** | pdftotext search "anti-windup"/"windup"/"back-calc"/"clamping"/"conditional integration" — **0 results** in entire 473-page book |
| 10. equilibrium init | **NOT FOUND** | only start-up transient examples (Fig 3.5, 8.7); no closed-form init mapping P_ref,Q_ref,V → i_d0,i_q0,m_d0,m_q0,V_DC0,integrator states |

**Count: 4 PASS / 2 PARTIAL / 4 NOT FOUND.**

### Chapter map

| Topic | Chapter | Pages |
|---|---|---|
| αβ-frame grid-imposed VSC | Ch. 7 | 160-203 |
| dq-frame grid-imposed VSC (GFL) | Ch. 8 | 204-244 |
| PLL (SRF-PLL) | Ch. 8 §8.3.4 | 211-217 |
| Current controllers (dq) | Ch. 8 §8.4.1 | 217-223 |
| Per-unit bases | Appendix B | 426-430 |

Note: §7.3.4 in Chapter 7 is "Selection of DC-Bus Voltage Level", NOT a PLL
(Chapter 7 is grid-imposed frequency; no PLL needed). A prior Vision audit
incorrectly claimed a PLL ODE on p.173; that was REFUTED by direct
extraction. The PLL is exclusively in Chapter 8.

## Why no composite source set works

The 4 missing items (I_max+priority, anti-windup, P/Q LPF, equilibrium
init) plus LV freeze are the "implementation/protection" layer. A natural
companion would be WECC REGC_A/REEC_A (which has current limit + P/Q
priority + anti-windup), but:

- WECC REGC_A/REEC_A is **PLL-less** — its current aligns algebraically
  to `angle(V)`.
- Yazdani's GFL uses the **PLL angle ρ** as the dq/network transformation
  angle.
- Neither source defines how WECC current commands, limiting, priority,
  low-voltage response, and anti-windup should operate while the PLL angle
  differs from terminal-voltage angle.
- Resolving frame ownership, rotation of limited current commands,
  low-voltage behavior, bases, and initialization would be a NEW
  `PROJECT_DERIVED` model design — not a source-defined composite.

IEEE 2800 is likewise insufficient: it is a performance/interconnection
standard, not a complete nonlinear state-equation, anti-windup,
initialization, and parameter specification.

## Stopping rule (satisfied)

- All 5 local unknown PDFs have evidence-backed verdicts (Bao, IBR1, BES
  comparison, GFL-GFM MPC, Thai note — all audited).
- Bounded MDPI/IEEE retrieval complete (MDPI 403 but user supplied full
  text; ScienceDirect 403 but user supplied full text; arXiv abstract
  retrieved).
- The governing-reference one-hop (Yazdani & Iravani, cited by both MDPI
  Ref [23] and Bao Ref [13]) was checked and audited directly.
- All 8 candidates failed as sole sources.
- No compatible authoritative composite passed (WECC companion rejected
  for demonstrated PLL/frame/interface incompatibility).

## Vision agent hallucination note

Two Vision agent triages hallucinated document identity and must not be
trusted without independent verification:
- IBR1.pdf: claimed "IEEE PES-TR71 2024 Units 1&2 (DOI 10.1109/PES-TR71-2024)"
  — actually Engler & Hardt IECON 2000 "Microgrid Power Flow" (1-page
  algebraic droop GFM paper, no DOI, © 2000 IEEE).
- Bao et al. paper: claimed "Rangarajan et al. 2024 PEMC, 10-state GFL
  with Eqs 1-2 PLL, Eq 3 outer, Eq 4 current, Table I parameters" —
  actually Bao/Fan/Miao/Ramasubramanian NAPS 2025, EMT/SimPowerSystems,
  no GFL equations (eqs 1-2 are GFM current saturation).

All material findings in this record were verified by direct pdftotext
extraction or independent Read-tool inspection, NOT by unverified Vision
agent claims.

## Reopening criteria

A future user-supplied source may reopen Phase 0B only if it is an
equation-level positive-sequence RMS PLL-resolved GFL specification
covering the complete 10-item checklist (including current limit+priority,
anti-windup, P/Q measurement LPF, equilibrium init, and LV freeze).

Alternatively, the user could separately authorize a `PROJECT_DERIVED`
composite or EMT-to-RMS reduction plan — but that is a NEW plan with
revised classification, not a continuation of this source audit. Merely
supplying a limiter block, performance standard, or WECC aggregation would
not close the gap.

## Search artifacts (transient, not committed provenance)

The following files were transient extraction artifacts created during the
audit and are NOT committed provenance:
- `docs/text/pages_210_212.txt`
- `docs/text/pages_217_221.txt`
- `docs/text/sustainability-15-08400.xml`

These are removed before commit; their relevant citations are incorporated
into this audit record.
