# IEEE14 IBR Phase 5 — GFL Model Provenance (STRUCTURAL_ONLY)

**Status:** `IEEE14_IBR_GFL_MODEL_READY` = STRUCTURAL_ONLY (not production-ready).
`IBR_PRODUCTION_INTEGRATION_READY` = NOT_READY.
**Phase:** 5 — sourced GFL (grid-following) inverter model, structural-only.
**Base:** `main` @ `652eaa0` (descendant of `2c2cd6e`).
**Date:** 2026-07-13.

This document records the equation→source map, parameter freeze, equilibrium
initialization, pole oracles, and honest limitations for the Phase 5 GFL
device (`+ibr/gfl_model.m`). It is written BEFORE the model code per
AGENTS.md "equation-first in-house implementation."

## Source material (verified)

Primary sources, SHA-256 verified against
`docs/project/IEEE14_IBR_EQUATION_SOURCE_MATRIX.md`:

| File | Document | SHA-256 | Location |
|------|----------|---------|----------|
| 83340.pdf | Ding et al., Dynamically Configurable GFM/GFL (NREL/CP-6A40-83340, 2022) | `2aeded379710e3f93e5f47e79a9eb98a2b9fd05e2b79d1fc1713f5d50a995727` | `docs/text/83340.pdf` (local, NOT committed); URL https://www.nrel.gov/docs/fy23osti/83340.pdf |
| 90260.pdf | REGFM_B1 VSM GFM Inverter Model Spec (NREL/TP-5D00-90260, 2024) | `de52a0b7c8beec6d16d8e10b53a565d902ab1a79ef093ba3d6d80260a9287d50` | `docs/text/90260.pdf` (local, NOT committed); URL https://www.nrel.gov/docs/fy24osti/90260.pdf |
| 1110-2002.pdf | IEEE Std 1110-2002 (different version than matrix's hash) | `90ee662b...` (mismatch) | NOT used in Phase 5; flagged for SG-model work |

Per the v3 scope, the source PDFs are NOT committed to the repo; their URL +
verified SHA-256 are recorded here as provenance.

## Reduced GFL state vector (6 states, PROJECT_DERIVED interface order)

```
x_gfl = [delta_pll, eps_pll, P_f, Q_f, phi_P, phi_Q]^T
```

Reduced from Ding's 14-state EMT GFL (`[Phi_L, delta_inv, Pinv_f, Qinv_f,
phi_d, phi_q, i_ld, i_lq, v_od, v_oq, i_od, i_oq]` plus inner-loop
integrators, Ding line 309) by eliminating the LCL filter (`v_od, v_oq, i_od,
i_oq`) and treating the inner current loop (`i_ld, i_lq`) as algebraic
references under the positive-sequence ideal-inner-loop reduction.

| # | Name | Meaning | Units | Base | Classification |
|---|------|---------|-------|------|----------------|
| 1 | delta_pll | PLL angle (network frame, rel. to synchronous ref) | rad | rad | SOURCE_TRANSFORMED (Ding Eq.8, deviation form) |
| 2 | eps_pll | PLL PI integrator | pu·s | S_base | SOURCE_TRANSFORMED (Ding Eq.8) |
| 3 | P_f | filtered measured active power | pu | S_base=100 MVA | SOURCE_VERBATIM (Ding Eq.2) |
| 4 | Q_f | filtered measured reactive power | pu | S_base | SOURCE_VERBATIM (Ding Eq.2) |
| 5 | phi_P | power-loop d-axis PI integrator | pu·s | S_base | SOURCE_TRANSFORMED (Ding Eq.9) |
| 6 | phi_Q | power-loop q-axis PI integrator | pu·s | S_base | SOURCE_TRANSFORMED (Ding Eq.9) |

Algebraic outputs (NOT states): `i_d*`, `i_q*` (Ding Eq.10, SOURCE_TRANSFORMED),
`I_gfl` (PROJECT_DERIVED mapping). Inputs: `u = [Pref; Qref]` (nu=2).

## Governing equations (frozen)

```
% Inputs: u = [Pref; Qref]  (nu=2, exogenous device inputs)
% DQ transform (network frame -> PLL frame)
Vd_pll =  cos(delta_pll)*Re(V_bus) + sin(delta_pll)*Im(V_bus)
Vq_pll = -sin(delta_pll)*Re(V_bus) + cos(delta_pll)*Im(V_bus)

% PLL (Ding Eq.8, deviation form; omega0 multiplier PRESENT)
d(eps_pll)/dt  = Vq_pll                                    (P1)
d(delta_pll)/dt = omega0*(kpPLL*Vq_pll + kiPLL*eps_pll)    (P2)

% Power measurement filter (Ding Eq.2; omega_c source-closed)
Pinv_meas = Re(V_bus*conj(I_gfl))   (generator convention S = V*conj(I))
Qinv_meas = Im(V_bus*conj(I_gfl))
d(P_f)/dt = omega_c*(Pinv_meas - P_f)                      (P3)
d(Q_f)/dt = omega_c*(Qinv_meas - Q_f)                      (P4)

% Power-loop PI integrators (Ding Eq.9)
d(phi_P)/dt = +(Pref - P_f)                                 (P5)
d(phi_Q)/dt = +(Qref - Q_f)                                 (P6)

% Algebraic current references (Ding Eq.10; Q-sign CORRECTED)
i_d* = +Kps*(Pref - P_f) + Kis*phi_P                       (P7)
i_q* = -Kps*(Qref - Q_f) - Kis*phi_Q                       (P8)   [Q negative]

% Current injection (RMS reduction; SYSTEM base, no Mbase factor)
I_gfl = (i_d* + j*i_q*)*exp(j*delta_pll)                   (I1, positive INTO network)
```

**Q-sign rationale (v3 fix 1):** at PLL lock `S = V*conj(I) = |V|*(i_d* - j*i_q*)`
so `P = |V|*i_d*` (positive) but `Q = -|V|*i_q*` (negative coefficient on i_q*).
For positive Qref, `i_q* = -Qref/|V|`. The Q-axis PI therefore carries a
negative sign on both the proportional and integral terms.

## Parameter freeze (all frozen BEFORE results)

| # | Param | Value | Classification | Source |
|---|------|-------|----------------|--------|
| 1 | omega0 | 376.99 rad/s (2*pi*60) | SOURCE_VERBATIM | REGFM_B1 Table 1 (omega0); IEEE14 60 Hz case |
| 2 | S_base | 100 MVA | SOURCE_VERBATIM | Ding Table I footnote; IEEE14 baseMVA |
| 3 | omega_c (P/Q filter cutoff) | 10 rad/s | SOURCE_VERBATIM | Ding Table I: omega_c = 10 rad/s |
| 4 | kpPLL | 0.265 pu | SOURCE_VERBATIM (value) / CASE_DEFINED+PROJECT_MAPPED (application to GFL) | REGFM_B1 Table 1 |
| 5 | kiPLL | 2.65 pu/s | SOURCE_VERBATIM (value) / CASE_DEFINED+PROJECT_MAPPED (application) | REGFM_B1 Table 1 |
| 6 | Kps | 1.0 | ASSUMED_DIAGNOSTIC | Ding Table I lacks; a-priori critically-damped rationale |
| 7 | Kis | 10.0 s^-1 | ASSUMED_DIAGNOSTIC | Ding Table I lacks; a-priori (see pole oracle) |
| 8 | Pref | per-IBR pu (input u(1)) | CASE_DEFINED | IEEE14 dispatch contract |
| 9 | Qref | per-IBR pu (input u(2)) | CASE_DEFINED | IEEE14 case (default 0) |

**No ASSUMED_DIAGNOSTIC value enters production acceptance.** Kps/Kis being
ASSUMED_DIAGNOSTIC makes Phase 5 structural-only. System base only (no Mbase,
no Sbase/Mbase factor — v3 fix 2).

## Equilibrium initialization (v3 fix 1)

From the PF warm-start (V_bus, Pref, Qref), with V0 = |V_bus| carried in the
constructor:

```
delta_pll0 = angle(V_bus);  eps_pll0 = 0;             (Vq_pll = 0 at lock)
P_f0 = Pref;  Q_f0 = Qref;                            (filter at steady state)
phi_P0 = +Pref/(V0*Kis);  phi_Q0 = +Qref/(V0*Kis);   (so Kis*phi_P0 = Pref/V0, Kis*phi_Q0 = Qref/V0)
i_d*0 = +Pref/V0;  i_q*0 = -Qref/V0;                  (from P = V0*i_d*, Q = -V0*i_q* at lock)
```

Verification: `i_d*0 = Kps*0 + Kis*phi_P0 = Kis*Pref/(V0*Kis) = Pref/V0` ✓.
`i_q*0 = -Kps*0 - Kis*phi_Q0 = -Kis*Qref/(V0*Kis) = -Qref/V0` ✓. All f=0.

## Pole oracles (predeclared, frozen BEFORE results)

**PLL (linearized about V0):** `s^2 + omega0*V0*kpPLL*s + omega0*V0*kiPLL = 0`.
At V0=1: `s^2 + 99.90*s + 994.0 = 0` → poles {-11.27, -88.63} s^-1.

**Power loop (linearized about V0):** `chi(s) = s^2 + omega_c*(1+V0*Kps)*s + omega_c*V0*Kis`.
- V0=1.0, omega_c=10, Kps=1, Kis=10: `s^2 + 20s + 100 = (s+10)^2` → {-10,-10} (critically damped).
- General (V0>0): `chi(s) = (s+omega_c)*(s+omega_c*V0*Kps)` form via the chosen gains: V0=0.8 → {-8,-10}; V0=1.2 → {-10,-12}.

These are asserted by the pole-oracle tests BEFORE the model is exercised.

## Sign/base/frame conventions (frozen)

- Per-unit base: S_base = 100 MVA (system base; no inverter-base conversion).
- Frequency base: f_base = 60 Hz, omega0 = 2*pi*60 = 376.99 rad/s.
- Current direction: positive INTO network / OUT of inverter (generator convention).
- Complex power: S = V*conj(I) (generator convention).
- Network KCL: g = Y*V - I_inj (composite canonical YV-I).
- Shared y: [Re(V1), Im(V1), ..., Re(Vnb), Im(Vnb)]^T interleaved.
- Reference frame: network common xy; PLL-rotated dq for inverter internals.
- GFL is a current source (no coupling reactance XL in I_gfl; Thevenin = GFM).

## Honest limitations (structural-only)

1. Kps/Kis are ASSUMED_DIAGNOSTIC — excluded from production acceptance.
2. kpPLL/kiPLL are SOURCE_VERBATIM values from REGFM_B1 but their application
   to the Ding-derived GFL is CASE_DEFINED/PROJECT_MAPPED, not SOURCE_VERBATIM
   GFL.
3. No catalog/runtime registration; no production-readiness claim.
4. The RMS/PCC reduction (ideal inner loop, LCL elimination) is PROJECT_DERIVED
   (unsourced verbatim); not claimed source-closed.
5. The mixed-equilibrium / pure-GFL-island-via-solver / SSSA-sharing gates
   are deferred to Phase 9 (require `mixed_equilibrium_solve` u-passing
   changes that are out of scope for this round; no `+stability/**` edits).
6. REGFM_B1 PLL output limits and low-voltage freeze behavior are deferred
   to the FRT phase (Phase 14).
7. Production readiness requires source-closing the ASSUMED_DIAGNOSTIC gains
   in a separate later task.

## Corrective patch (post-Phase-5 re-review)

Independent re-review by the user and Agent B surfaced 5 findings (3 High,
2 Medium). A compact corrective patch was applied (no model rebuild, no
gain/tolerance change):

1. **Complex V0 initialization (F1, High):** the constructor now accepts the
   complex PF-solved bus voltage `V0`; `delta_pll0 = angle(V0)` (was hard-coded
   0). The PLL now initializes locked at any bus angle, not just 0.
2. **Fail-closed input (F2, High):** `refs_from_u` requires a 2-element finite
   `u_dev`; empty → `:missingInput`, non-finite/wrong-size → `:badInput`. The
   silent `[P_f, Q_f]` fallback is removed.
3. **Bus mapping validation (F3, High):** the constructor takes `bus_ids` and
   validates `bus_ids(bus_position) == bus_id` (else `:busMappingMismatch`).
   `bus_position` (voltage measurement) and `bus_id` (injection mapping) now
   cannot silently refer to different buses.
4. **Parameter override + provenance (F4, Medium):** every parameter is
   validated (finite, positive); any override reclassifies that parameter to
   `DIAGNOSTIC_ONLY` in `dev.provenance.param_classifications` and sets
   `dev.provenance.param_overridden.<name> = true`. Frozen defaults keep
   their original classification.
5. **Source Matrix status (F5, Medium):** Item 1 status updated to
   STRUCTURAL_ONLY; Phase 5 removed from the "blocked" list.

New falsification tests (T17-T21): nonzero-angle equilibrium + common-angle
rotation invariance; empty/wrong/nonfinite u fails; noncontiguous bus IDs +
deliberate mapping mismatch; invalid/nonfinite parameters fail; numerical
linearization of `dev.f` for the PLL eigenvalues (replaces hard-coded
constants in the pole tests).

The 6-state structure, equations, and frozen gains are unchanged. The
corrective patch is additive on top of the three Phase 5 commits
(`9abb5d7`, `41085f6`, `60d8337`).

