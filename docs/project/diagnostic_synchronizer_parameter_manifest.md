# Diagnostic Synchronizer — Parameter Manifest

**Status:** FROZEN before the first controller-enabled dynamic run (binding
amendment #10). This manifest MUST be advisor-reviewed before any diagnostic
run that exercises the controller path.

**Classification:** Per binding amendment #2:
- Padiyar/Sauer-Pai equation structure → `PARTIAL_SOURCE`
- KA, TA, gains, limits, rates, initialization, IEEE14 mapping → `ASSUMED_DIAGNOSTIC`

**Provenance:** every row carries `SOURCE_DEFINED`, `CASE_DEFINED`,
`PROJECT_DERIVED`, `PARTIAL_SOURCE`, or `ASSUMED_DIAGNOSTIC`. No value is
invented without explicit classification.

---

## A. IEEE14 SG1 Plant (SOURCED / CASE_DEFINED — read-only, NOT a controller)

| Parameter | Value | Unit | Provenance |
|---|---|---|---|
| SG model | EMF6 6-state (GENTPJ) | — | IEEE 1110-2002 Model 2.2; in-repo audited |
| Inertia H | 5.148 | s (machine base) | Kodsi UW TR 2003-3 Table A.2; CASE_DEFINED |
| Damping D | 2 | pu (system base) | Kodsi; CASE_DEFINED |
| Rated power Sr | 615 | MVA | MATPOWER + Kodsi; CASE_DEFINED |
| System base Sbase | 100 | MVA | MATPOWER case14; CASE_DEFINED |
| Reactance set | Xd=0.8979 Xdp=0.2995 Xdpp=0.23 Xq=0.646 Xqp=0.646 Xqpp=0.4 Xl=0.2396 Ra=0.0 | pu (system base) | Kodsi; CASE_DEFINED |
| Time constants | Tpd0=7.4 Tppd0=0.03 Tpq0=0 Tppq0=0.033 | s | Kodsi; CASE_DEFINED |
| Tm (equilibrium) | ~0.378 | pu (system base, 232.4MW/615MVA) | mixed_equilibrium_solve; PROJECT_DERIVED from Kodsi |
| Efd (equilibrium) | solved | pu (system base) | mixed_equilibrium_solve; PROJECT_DERIVED |
| df_max (guard) | 0.001 | pu | CASE_DEFINED (case_ieee14...auto_vsg.m:116) |
| dV_max (guard) | 0.05 | pu | CASE_DEFINED (case_ieee14...auto_vsg.m:115) |
| dθ_max (guard) | 10.0 | deg | CASE_DEFINED (case_ieee14...auto_vsg.m:117) |
| dwell_min | 0.5 | s | CASE_DEFINED |
| T_sync_timeout | 5.0 | s | CASE_DEFINED |
| T_min_off | 0.5 | s | CASE_DEFINED |
| Phase 1 observation: Tm ramps slip monotonically | df ≈ [7.7e-4, 10.9e-4, 14.0e-4] at t=[0.06,0.07,0.08] | pu | MEASURED (Phase 1 diagnostics) |

---

## B. Governor / Speed Loop (ASSUMED_DIAGNOSTIC)

**Equation structure:** Sauer-Pai speed governor with droop (docs/sauer_pai.txt:4158-4189).
The underlying structure (steady-state droop + first-order valve) is PARTIAL_SOURCE.
All numeric values below are ASSUMED_DIAGNOSTIC.

| Parameter | Value | Unit | Classification |
|---|---|---|---|
| Governor type | PI speed controller + droop | — | PARTIAL_SOURCE (Sauer-Pai structure) |
| Droop R_D | 0.05 | pu | ASSUMED_DIAGNOSTIC (Sauer-Pai example §4.3.2, NOT SG1-specific) |
| Valve time constant T_SV | 0.2 | s | ASSUMED_DIAGNOSTIC (Sauer-Pai example) |
| Turbine time constant T_CH | 0.4 | s | ASSUMED_DIAGNOSTIC (Sauer-Pai example from textbook exercise) |
| Tm_max (P_SV^max) | 1.0 | pu | ASSUMED_DIAGNOSTIC (no source; 1.0 pu ceiling) |
| Tm_min | 0.0 | pu | ASSUMED_DIAGNOSTIC (runback to zero, no braking torque) |
| dTm/dt_max (valve rate) | 0.5 | pu/s | ASSUMED_DIAGNOSTIC (no source; chosen as 1.32×Tm_eq/s to allow fast runback) |
| Runback command | Tm_cmd → 0 at sg_trip+0.05s | — | ASSUMED_DIAGNOSTIC (not a sourced shutdown policy) |
| Speed PI: Kp | 1.0 / R_D = 20 | pu/pu | ASSUMED_DIAGNOSTIC (proportional only; Ki=0 until verified needed) |
| Speed PI: Ki | 0 | pu/pu/s | ASSUMED_DIAGNOSTIC (no integral until verified needed for steady-state slip) |
| Anti-windup | Clamping back-calculation, Kb = 1/T_CH | — | ASSUMED_DIAGNOSTIC |

**Independent oracle:** with runback Tm_cmd=0, offline swing equation
2H·dω/dt = Tm − D·ω decays to 0 with time constant 2H/D = 5.148 s.
At t≈3s after trip, ω ≈ ω(0)·exp(−3D/(2H)) ≈ 0.073·exp(−3·2/(2·5.148)) ≈ 0.073·0.559 ≈ 0.041 pu.
Rotor MUST cross zero slip (ω=0) when Tm_cmd reduces below D·ω;
the governor must demonstrate this in closed-loop simulation.

---

## C. Exciter / Voltage Loop (ASSUMED_DIAGNOSTIC)

**Decision:** Start with CONSTANT Efd (fixed at equilibrium value, no active AVR).
Phase 1 diagnostics show dV≈18 pu (V_open_circuit differs from V_bus because
Efd is frozen and the offline flux decays differently from the network).
If fixed Efd does NOT bring dV within the guard window:
— enable the active adapted Padiyar AVR below.

**Equation structure:** Padiyar single-time-constant AVR (PARTIAL_SOURCE).

| Parameter | Value | Unit | Classification |
|---|---|---|---|
| Exciter type | Fixed Efd (Padiyar AVR disabled) | — | ASSUMED_DIAGNOSTIC (reduced scope; enable only if dV gaps) |
| KA (if enabled) | 200 | — | ASSUMED_DIAGNOSTIC (Padiyar-sourced value, IEEE14 mapping is diagnostic) |
| TA (if enabled) | 0.02 | s | ASSUMED_DIAGNOSTIC (Padiyar-sourced value) |
| Efd_max | 3.0 | pu | ASSUMED_DIAGNOSTIC (no source; 3×Efd_eq ≈ ceiling) |
| Efd_min | 0.0 | pu | ASSUMED_DIAGNOSTIC |
| dEfd/dt_max | 10.0 | pu/s | ASSUMED_DIAGNOSTIC (no source) |
| V_ref | abs(V_bus) at equilibrium | pu | PROJECT_DERIVED from equilibrium |
| Anti-windup | Clamping, Kb = 1/TA | — | ASSUMED_DIAGNOSTIC |
| Bumpless activation | V_ref = V_open after activation, Efd output = Efd_eq | — | ASSUMED_DIAGNOSTIC |

**Independent oracle:** fixed Efd → open-circuit flux decay equations from
sg_composite_device.m:209-223. dV and dV_max can be compared directly.

---

## D. Phase-Matching / Synchronizer State Machine (ASSUMED_DIAGNOSTIC)

**No sourced phase-matching controller exists in the repository.** The passive
synchronism_guard is the only building block. Active slip control uses:

| Parameter | Value | Unit | Classification |
|---|---|---|---|
| Slip target | 0.0 (deadbeat to synchronism) | pu | ASSUMED_DIAGNOSTIC (no source) |
| Phase-crossing window | within dθ_max before close | deg | CASE_DEFINED (existing guard) |
| Phase-crossing prediction horizon | 1 sample (no prediction) | — | ASSUMED_DIAGNOSTIC (sample-grid sensitivity addressed by dwell) |
| Breaker operating delay | 0 (instant) | s | ASSUMED_DIAGNOSTIC (no source for IEEE14 SG1 breaker delay) |
| Close command | guard.passes && dwell_ok → attempt reclose | — | existing (sourced) |

**Wait-and-coast strategy**: runback Tm→0, wait for damping to reduce slip into
the guard window, then accumulate dwell. No active phase-alignment controller.
If dwell never accumulates (dV or dθ never enter window) → remain offline
→ SYNC_TIMEOUT.

---

## E. Control-Write Path (PROJECT_DERIVED architecture)

| Property | Value |
|---|---|
| Controller state ownership | `ts_simulate_ibr_hybrid` supervisory struct (not embedded in EMF6) |
| Measurements | previous accepted-sample SG reconstruct (causal: lag-1) |
| Tm/Efd update | per-step, before composite_dae step call; after controller evaluation |
| Atomic transaction | snapshot controller state + SG Tm/Efd slots → restore on reclose failure |
| Disabled-route | mode≠'diagnostic' → controller never instantiated → bit-identical |

---

## F. Freeze Gates

1. This manifest is frozen BEFORE the first controller-enabled dynamic run.
2. No post-run tuning to obtain PASS (binding amendment #10).
3. If a parameter must change: record the change, the evidence, and re-freeze
   before the next run.
4. advisor-review required before first dynamic run per CLAUDE.md mandatory
   workflow.

---

*Manifest created 2026-07-17 for Mission C diagnostic synchronizer workflow.*
*Classification: PROJECT_DERIVED diagnostic asset; NOT physical acceptance evidence.*
