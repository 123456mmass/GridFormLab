# GFM VSM Sakimoto (no-PLL, no-AVR, no-PSS) — Parameter Manifest

Status: FROZEN before code (per user approval 2026-07-22). This manifest is
the single source of numeric truth for `+ibr/gfm_vsm_sakimoto_model.m`. See
`docs/project/GFM_VSM_SAKIMOTO_SOURCE_CONTRACT.md` for equations/state order.

## 1. Identity

- `device_type = 'ibr_gfm_vsm_sakimoto'`
- `nx = 9`, `nu = 2` (`u = [P_ref; Q_ref]`, pu, system base)
- NO PLL, NO AVR, NO PSS (hard construction-time guard)
- Separate device from the existing 4-state `ibr_gfm_vsg_no_pll` (unchanged)

## 2. State order (9, fixed)

| # | name | block | units |
|---|---|---|---|
| 1 | `i_d` | IBR | pu (inverter base) |
| 2 | `i_q` | IBR | pu (inverter base) |
| 3 | `xi_id` | IBR | pu*s |
| 4 | `xi_iq` | IBR | pu*s |
| 5 | `omega_R` | VSG | pu |
| 6 | `delta` | VSG | rad |
| 7 | `x_gov` | VSG | pu |
| 8 | `T_m` | VSG | pu |
| 9 | `x_d` | VSG (damper washout) | pu |

GFM block (voltage-forming) has NO state — algebraic Q-V droop (§4).

## 3. Frozen numeric parameters (SOURCE: Sakimoto 2015, Table 1 & Table 2)

| Symbol | Value | Units | Block | Classification |
|---|---|---|---|---|
| `r` | 0.2 | pu | Impedance model | SOURCE_DEFINED |
| `x` | 0.4 | pu | Impedance model | SOURCE_DEFINED |
| `K_gd` | 0.05 | pu | Governor droop | SOURCE_DEFINED |
| `K_GP` | 20 | pu | Governor PI prop | SOURCE_DEFINED |
| `K_GI` | 100 | pu | Governor PI int | SOURCE_DEFINED |
| `T_tur` | 0.12 | s | Turbine 1st order | SOURCE_DEFINED |
| `K_IP` | 1.49 | pu | Current PI prop | SOURCE_DEFINED |
| `K_II` | 71.95 | pu | Current PI int | SOURCE_DEFINED |
| `R_F` | 0.0022 | pu (0.22%) | L-filter resistance | SOURCE_DEFINED |
| `omega*L_F` (`X_F`) | 0.088 | pu (8.8%) | L-filter reactance | SOURCE_DEFINED |
| `K` (damper gain) | 10 | pu | Damper | SOURCE_DEFINED |
| `tau_d` | 0.01 | s | Damper time constant | SOURCE_DEFINED |
| `J` | 4.0 | s | Rotor inertia | SOURCE_DEFINED |
| `D_g` | 1.0 | pu | Rotor mech damping | SOURCE_DEFINED |
| `omega_b` | 377.0 | rad/s (60 Hz) | base | SOURCE_DEFINED (Fig.6 "377/s") |
| `P*` | 0.0 | pu | command default | SOURCE_DEFINED |
| `Q*` | 0.0 | pu | command default | SOURCE_DEFINED |

DROPPED from Sakimoto (user decision, no AVR/PSS): `K_ad=0.05`, `K_AI=20`.
DROPPED (L-filter RMS reduction, no LC capacitor / transformer stage):
`C=10uF`, `R_tr=2.1%`, `omega*L_tr=9.1%` — network coupling handled by the
SMIB `Z_line` / composite KCL, not by the device.

## 4. Added / project-derived parameters

| Symbol | Value | Units | Purpose | Classification |
|---|---|---|---|---|
| `K_q` | 0.05 | pu | Static Q-V droop replacing the removed AVR (`E_q = E_0 + K_q*(Q_ref-Q)`) | PROJECT_DERIVED (reuses Sakimoto's `K_ad` numeric value as a starting point; no AVR dynamics) |
| `E_0` | 1.0 | pu | Nominal internal EMF at `Q=Q_ref` | PROJECT_DERIVED |
| `Imax` | 1.2 | pu | Current-limiter magnitude bound | PROJECT_DERIVED (consistent with GFL-RMS10 `Imax` order of magnitude) |
| limiter priority | P-priority | — | Current-priority rule when `hypot(i_d*,i_q*)>Imax` | PROJECT_DERIVED (matches GFL-RMS10 default) |
| `V_div_min` | 0.1 | pu | Balanced positive-sequence LV fail-closed floor | PROJECT_DERIVED (matches repo convention) |
| `eq_tol` | 1e-9 | — | Equilibrium/voltage-law feasibility tolerance | NUMERICAL_METHOD |
| `aw_tol` | 1e-9 | — | Anti-windup directional-test tolerance | NUMERICAL_METHOD |

## 5. Base contract

- `kappa = Sbase/Mbase`; `Sbase=100 MVA` default (repo standard), `Mbase`
  CASE_DEFINED per device (mirrors GFL-RMS10/REGFM_B1/existing GFM-no-PLL).
- Device-internal states run on INVERTER base; `current_injection` and
  `electrical_power` return SYSTEM base. No double conversion.
- `omega_b = 377 rad/s` (60 Hz) — matches repo default; Sakimoto's own figure
  uses `377/s`, so NO 50→60 Hz retuning is required (unlike a literal reading
  of the paper's nominal grid, the block diagram itself is already in 377).

## 6. Governor and damper realization notes (implementation-level, non-blocking)

- Governor droop: `omega* - omega_R = -K_gd*(P*-P)` reproduces Sakimoto eq
  (26); implemented as `P_gov_err = (P* + K_gd*(omega* - omega_R)) - P_meas`
  feeding the PI (`K_GP,K_GI`) then the turbine 1st order (`T_tur`) to `T_m`.
  Uses INSTANTANEOUS measured P (no extra filter state; Sakimoto Fig.8 shows
  no governor-side P filter).
- Damper washout state `x_d` realizes `T_d = K*x/(tau_d)*(...)` such that the
  steady-gain identity `D = K*x_imped/(r^2+x^2)` (Sakimoto eq 15/18) holds
  with the frozen `K=10, r=0.2, x=0.4` giving `D=10*0.4/(0.2^2+0.4^2)=10`
  — NOTE: this is the damping-TORQUE gain used inside the swing RHS, not to
  be confused with the reported paper value "K=10 ⇒ D=0.2" which used a
  per-paper-Table-1 different `x` normalization; the implementation derives
  `D` directly from the frozen `r,x,K` via eq 15 rather than re-deriving the
  paper's illustrative D=0.2 statement. This is flagged
  `NEEDS_IMPLEMENTATION_CROSSCHECK` and must be verified by the FD-Jacobian
  oracle (does not block first implementation; the washout ODE form itself is
  frozen).

## 7. Readiness

`STATUS: SOURCE_IMPLEMENTED_PENDING_SMIB_GATES` (same convention as the
existing GFM-no-PLL device). Not registered for IEEE14 mixed-resource
integration in this delivery; SMIB-only.

---

## 8. IMPLEMENTATION RESOLUTIONS (verified 2026-07-22, SSSA/oracle)

The items flagged NEEDS_IMPLEMENTATION_CROSSCHECK in section 6 are resolved and
verified by the independent oracle (output/diagnostics/oracle_gfm_vsm_sakimoto.m)
and tests/test_ibr_gfm_vsm_sakimoto.m (8/8 PASS). Final SMIB SSSA:
ASYMPTOTICALLY STABLE, max_real = -3.15 (swing -6.22 +/- 12.04j ~1.9 Hz;
current loop -9342 +/- 1141j); equilibrium ||f||inf = 8.8e-10.

1. Damper washout: T_d = K_damp*(T_e - x_d), x_d = lowpass(T_e),
   d(x_d)/dt = (T_e - x_d)/tau_d. This is the Fig.6 block K*tau_d*s/(1+tau_d*s)
   applied to T_e (= K*(T_e - lowpass(T_e))), matching eq 12 (K_tau_d=K*tau_d=0.1)
   and eq 15/18 (D=K_tau_d*x/(r^2+x^2)=0.2 for K=10). It is NOT (K_damp/tau_d)*(...).
   Verified stabilizing: increasing K_damp reduces max_real (ablation).

2. dq frame (Sakimoto eq 8): V_rot = V*exp(-1i*delta), q=real, d=imag, so
   V_gq=Vg*cos(delta), V_gd=-Vg*sin(delta). Current phasor i_q + j*i_d =
   I_inv*exp(-1i*delta). An earlier exp(-1i*(delta-pi/2)) convention flipped
   the V_gd sign and inverted the synchronizing torque (unstable); corrected.

3. Governor is SPEED-primary (Sakimoto eq 19/23/26): e_gov = (1 - omega_R) +
   K_gd*(P_ref_inv - P_inv_meas). The PI (K_GP,K_GI) acts primarily on the
   speed error; the active-power setpoint enters only as the weak droop bias
   K_gd. Regulating the power error with unit weight (a power loop) instead
   destabilizes the swing (ablation: power-primary -> +7.45 unstable;
   speed-primary -> -3.15 stable).

Equilibrium construction: delta0 solved by bisection on the Sakimoto
synchronizing-power residual (Id_cmd(delta0) - i_d0 with E_q from the eq-2
q-component inversion); the Q-V droop reference Q_ref is back-solved for
consistency and stored as u0(2). Current-PI integrators seeded as
xi_id0 = (R_F*i_d0 - K_IP*e_d0)/K_II to keep d_i_d=0 exactly (avoids the
omega_b/X_F ~ 4284 amplification of any residual).
