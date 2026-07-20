# GFM-VSG without PLL — Source-to-Equation Contract (FROZEN)

Date: 2026-07-20. Branch: `main`. Status: `GFM_NO_PLL_SOURCE_CONTRACT = PASS`
(after user-approved VFlag=0 4-state contract reconciliation).

This document is the frozen source-to-equation register for the new
positive-sequence RMS GFM-VSG model without PLL
(`+ibr/gfm_vsg_no_pll_model.m`). It is the authority for the state order,
ODEs, bases, signs, initialization, limits, and source classifications. It
must not be edited after results are produced; any material change requires
re-planning.

## 1. Model identity

- File: `+ibr/gfm_vsg_no_pll_model.m`
- `device_type = 'ibr_gfm_vsg_no_pll'`
- `mode = 'GFM'` (shared runtime vocabulary; the new device is distinguished
  by `device_type` and `provenance.model`, not by `mode`)
- `provenance.model = 'GFM_VSG_NO_PLL_PROJECT_DERIVED_SOURCE_MAPPED'`
- `nx = 4`, `nu = 2`
- `state_names = {'delta_vsm','delta_omega_vsm','P_f','Q_f'}`
- `input_names = {'P_ref','V_ref'}`

## 2. State vector (4 states, fixed order)

`x_gfm = [delta_vsm; delta_omega_vsm; P_f; Q_f]`

| # | Symbol | Name | ODE | Unit | Frame | PU base | Init | Limit | Source | Classification |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `delta_vsm` | virtual-rotor angle | `dot(delta_vsm) = omega_base * delta_omega_vsm` | rad | network-common xy | base-independent | `angle(E_internal)` from output-stage inversion (constructor seed may use `angle(V0)` per Sakimoto Sec.5.1 startup) | none in first slice | Sakimoto 2015 p.464 Eq.5; Avila-Martinez 2025 (angle = `omega_b/s * omega`) | SOURCE_DEFINED equation; PROJECT_DERIVED phasor-equilibrium init |
| 2 | `delta_omega_vsm` | virtual-rotor speed deviation | `dot(delta_omega_vsm) = (P_ref_inv - P_f - D_GFM*delta_omega_vsm)/(2*H_GFM)` | pu speed deviation | virtual-rotor | inverter | 0 | none | Avila-Martinez 2025 Eq.9/10 (VSM-noPLL 2H form); Sakimoto 2015 Eq.4 (no-PLL rotor dynamics) | SOURCE_DEFINED equation; PROJECT_DERIVED_SOURCE_MAPPED realization |
| 3 | `P_f` | filtered active power | `T_P * dot(P_f) = kappa*P_meas - P_f` | pu active power | device-local | inverter | `kappa*P` | none | PNNL-35110 p.4 Eq.4 | SOURCE_DEFINED |
| 4 | `Q_f` | filtered reactive power | `T_Q * dot(Q_f) = kappa*Q_meas - Q_f` | pu reactive power | device-local | inverter | `kappa*Q` | none | PNNL-35110 p.4 Eq.5 | SOURCE_DEFINED |

`P_f` drives the active-power imbalance in the swing equation. `Q_f` drives
the algebraic Q-V/voltage-magnitude law. Neither is an unused reporting state.

## 3. Algebraic voltage law (PNNL VFlag=0 Q-V droop)

```
E_vsm = V_ref - m_q*(Q_f - Q_ref),   Q_ref = 0  (PNNL QVFlag=1 init branch)
```

Source: PNNL-35110 pp.2-4, Table 1, Fig.3(b) VFlag=0 path. Classification:
SOURCE_DEFINED equation. The cross-source assembly (Sakimoto swing + PNNL
droop/filters) is `PROJECT_DERIVED_SOURCE_MAPPED`.

## 4. Output stage (Thevenin behind pure jX_L)

```
E_internal = E_vsm * exp(1i*delta_vsm)
I_inv = (E_internal - V_bus) / (1i*X_L)      % inverter base
I_sys = I_inv / kappa                          % system base
S = V_bus * conj(I_sys)                        % generator convention
P_meas = real(S); Q_meas = imag(S)
```

Source: PNNL-35110 Eqs.8-9 (Norton), Du 2024 Eqs.14-15. `X_L = 0.15 pu`
(PNNL Table 1, txt line 152), `SOURCE_DEFINED_STUDY_VALUE`. No Sakimoto
`r+jx` mixing. No dq transform in the RHS; the Thevenin current is evaluated
directly in the network xy frame. dq components are exposed only as
diagnostic reconstruction.

## 5. Sourced study parameters (FROZEN, SOURCE_DEFINED_STUDY_VALUE)

From Avila-Martinez 2025 Table (txt line 1091), Strategy 1: VSM-noPLL:
- `H_GFM = 5 s`
- `D_GFM = 20 pu` (also `K_PFR = D_GFM = 20 pu`, PFR implicit, txt line 1094)
- `f_base = 50 Hz`, `omega_base = 2*pi*50 rad/s`
- Study base: 100 MVA (Avila Appendix)

From PNNL-35110 Table 1 (verified against txt line 152-178):
- `X_L = 0.15 pu` (inverter coupling reactance, txt line 152)
- `m_q = 0.05 pu` (Q-V droop gain, txt line 153)
- `T_P = T_Q = 0.01 s` (LPF time constants, txt line 174-175)
- `VFlag = 0` (algebraic Q-V droop mode selected for this model)
- `QVFlag = 1` (init sets `Q_ref = 0`, txt line 262)

`kappa = Sbase/Mbase`. For the source-reproduction SMIB gate,
`Sbase = Mbase = 100 MVA` (unity, so `kappa = 1`) to match Avila's 100 MVA
study base.

## 6. Per-unit base contract (frozen, identical to GFL-RMS10/REGFM_B1)

`kappa = Sbase/Mbase`. External ABI = system base; internal states/inputs =
inverter base. Boundary conversion exactly once: `P_ref_inv = kappa*P_ref_sys`,
`I_sys = I_inv/kappa`. `current_injection`/`electrical_power` return system
base (no double conversion).

## 7. Equilibrium initialization

Exact output-stage inversion. Given terminal `(V, P, Q)` on system base and a
`V_ref`:

1. `I_sys = conj((P + 1i*Q)/V)`
2. `I_inv = kappa*I_sys`
3. `E_internal = V + 1i*X_L*I_inv`
4. `delta_vsm = angle(E_internal)`, `delta_omega_vsm = 0`
5. `P_f = kappa*P`, `Q_f = kappa*Q`
6. Require the algebraic voltage law to reproduce `abs(E_internal)` within
   `eq_tol` (default 1e-9); fail-closed otherwise
   (`ibr:gfm_vsg_no_pll_model:infeasibleEquilibriumVoltageLaw`).

The initializer distinguishes:
- **case-specified `V_ref`**: verify the voltage-law residual and fail closed
  when inconsistent;
- **fixture-derived `V_ref`** (`V_ref = |E_internal| + m_q*(Q_f - Q_ref)`):
  label `PROJECT_DERIVED_TEST_FIXTURE`; not a production-readiness claim.

## 8. Omitted fast states and RMS reduction

| Omitted element | Treatment |
|---|---|
| Sakimoto current-controller PI (`K_IP=1.49`, `K_II=71.95`) | Omitted under positive-sequence RMS fast-loop reduction (bandwidth >> swing); inverter represented as controlled internal voltage behind `jX_L`. PROJECT_DERIVED reduction, documented. |
| Sakimoto damper lead (Eqs.12-15, `K_tau_d=10`, `tau_d=0.01`) | Omitted; damping represented by the sourced `D_GFM` term. Do NOT claim Sakimoto damper dynamics implemented. |
| Sakimoto governor PI + turbine (`K_GP`, `K_GI`, `T_tur=0.12`) | Omitted; `P_ref` enters swing directly. OUT-OF-SCOPE future extension. |
| Sakimoto AVR integral (`K_AI=20`) / PNNL VFlag=1 voltage PI (`k_pv`, `k_iv`, `xi_E`, `V_f`) | OUT-OF-SCOPE future model extension. This first model uses PNNL VFlag=0 algebraic Q-V droop only. Do NOT describe AVR as pending functionality of this model. |
| Current limiter / anti-windup | Omitted in first slice; fault/LVRT readiness = NOT_READY. |
| dq transform in RHS | Omitted; Thevenin current evaluated directly in xy frame. dq exposed only in `reconstruct` as diagnostic. |

## 9. No-PLL contract (negative contract, enforced by tests)

The model must contain NONE of: `delta_PLL`, `xi_PLL`/`x_PLL_int`, PLL PI
gains, PLL freeze/reset, PLL-estimated frequency, runtime `angle(V)` tracking,
or any state relabelled to hide PLL origin. Runtime rotor angle is obtained
ONLY from `dot(delta_vsm) = omega_base * delta_omega_vsm`.

Construction-time enforcement: `reject_unsupported_options` rejects any dormant
PLL/limiter/voltage-PI parameter fields (`kp_PLL`, `ki_PLL`, `VPLLfrz`,
`k_pv`, `k_iv`, `xi_E`, `V_f`, `VFlag`, `QVFlag`, `ImaxF`, `Emax`, `Emin`,
`kpqmax`, `Kiqmax`, `Pmax`, `Pmin`, `Qmax`, `Qmin`) rather than storing
ambiguous unsupported controls.

Behavioral enforcement (tests):
- `d(dot(delta_vsm))/dy = 0`, `d(dot(delta_vsm))/d(delta_vsm) = 0`,
  `d(dot(delta_vsm))/d(delta_omega_vsm) = omega_base`.
- Terminal-angle independence: perturb `angle(V)` with rotor states fixed;
  `dot(delta_vsm)` must not change.
- Rigid-frame covariance: rotate `V` and `delta_vsm` by the same constant
  angle; current rotates correspondingly; P, Q, rotor RHS remain invariant.

## 10. OUT-OF-SCOPE future model extensions

- AVR / dynamic voltage PI: Sakimoto AVR integral (`K_AI=20`) and PNNL VFlag=1
  dynamic voltage PI (`k_pv`, `k_iv`, `xi_E`, `V_f` from Eq.6) are NOT part of
  this first model. A future VFlag=1 model would require the 6-state order
  `[delta_vsm, delta_omega_vsm, P_f, Q_f, V_f, xi_E]` and a separately
  source-traced voltage-controller contract.
- Current limiter / anti-windup / fault LVRT: NOT_READY; requires a separate
  sourced limiter + recovery contract (PNNL Eq.7 vs Du virtual-resistor are
  different nonlinear contracts).
- Sakimoto governor/turbine, damper lead: future extensions; not in this model.
- IEEE14 60 Hz mapping of `H_GFM`, `D_GFM`, `X_L`, `m_q`: pending separate
  approval (`BLOCKED_CASE_MAPPING`). The SMIB source-reproduction gate runs
  on the source's 50 Hz / 100 MVA base and needs no 50->60 Hz transform.

## 11. Sources

- Sakimoto et al. 2015, "Virtual Synchronous Generator without Phase Locked
  Loop based on Current Controlled Inverter and its Parameter Design,"
  IEEJ Trans. PE Vol.135 No.7, pp.462-471.
  `docs/text/gfm_no_pll/sakimoto-2015-vsg-without-pll.pdf`
- PNNL-35110, "Model Specification of Droop-Controlled, Grid-Forming
  Inverters," Sept 2023.
  `docs/text/gfm_no_pll/pnnl-35110-regfm-a1.pdf`
- Du et al. 2024, "Positive-Sequence Modeling of Droop-Controlled
  Grid-Forming Inverters for Transient Stability Simulation of Transmission
  Systems," IEEE Trans. Power Delivery, vol.39 no.3, pp.1736-1748.
  `docs/text/gfm_no_pll/du-2024-positive-sequence-gfm.pdf`
- Avila-Martinez et al. 2025, "Impact on transient stability of
  self-synchronisation control strategies in grid-forming VSC-based
  generators," arXiv:2509.04388v1.
  `docs/text/gfm_no_pll/avila-martinez-2025-self-synchronisation-gfm.pdf`
- NREL/TP-5D00-90260 REGFM_B1 (legacy WITH PLL, comparison only, NOT a source
  for this model): `docs/text/gfm_no_pll/nrel-90260-regfm-b1-legacy-comparison.pdf`
