# GFM VSM (no-PLL) — Source-to-Equation Design Contract (DRAFT, pre-implementation)

Status: DRAFT_FOR_APPROVAL. This is a read-only design contract. No production
code is written until this contract is reviewed and frozen (AGENTS.md:
"freeze choices before results"; README `docs/text/gfm_no_pll`: freeze 6 items
before implementation, do not splice blocks silently).

Purpose: define a NEW positive-sequence GFM device that realizes the whiteboard
3-block structure `GFM = [IBR, GFM, VSG]` as *dynamic states*, with **no PLL**,
symmetric in spirit with the 10-state GFL-RMS10. It does NOT replace the
existing 4-state `gfm_vsg_no_pll_model` (Avila-Martinez/PNNL reduced model),
which remains a validated reduced-order option.

## 0. Sources and verification status

| Tag | Source | Role |
|---|---|---|
| `SAKIMOTO` | Sakimoto et al., "Virtual Synchronous Generator without Phase Locked Loop based on Current Controlled Inverter and its Parameter Design," IEEJ Trans. PE, Vol.135 No.7, 2015 (`docs/text/gfm_no_pll/sakimoto-2015-vsg-without-pll.pdf`) | PRIMARY. Full no-PLL VSG: impedance model, current PI, AVR, rotor/swing, governor, damper. |
| `DARCO_SUUL` | D'Arco, Suul, Fosso, "A Virtual Synchronous Machine implementation...," EPSR 122 (2015) 180-197 (`docs/text/darco-suul-2015.txt`) | SUPPORTING only, for cascaded-controller/LC-filter equation *form*. **Its PLL-based damping (ωPLL) is NOT adopted** — replaced by the Sakimoto damper. |
| `PROJECT_DERIVED` | in-repo derivation | RMS reduction choices, base mapping, limits, init, anti-windup. |

Visual verification: Sakimoto eq (1)-(19) and the full control block diagram
Fig. 6 were rendered from the PDF (`output/diagnostics/sakimoto_pg-03.png`,
`sakimoto_pg-04.png`, 150 dpi) and read as images to confirm the layout-text
extraction despite the Adobe-Japan1 font warnings. The equations below are
VISUALLY CONFIRMED against the PDF unless marked
`NEEDS_PDF_VISUAL_VERIFICATION`.

Hard no-PLL contract (enforced at construction): no `delta_PLL`, no PLL
integrator, no PLL PI gains, no PLL freeze, no `angle(V)`/`atan2(vq,vd)`
frequency tracking. The rotor angle comes ONLY from the swing integrator.

Hard NO-AVR / NO-PSS contract (user decision 2026-07-22): no automatic voltage
regulator state/integrator, no field-winding lag, no power system stabilizer.
Voltage magnitude reference `E_q` is algebraic only (§2 GFM block). Construction
must reject any AVR/PSS option field fail-closed.

## 1. Blocks and proposed state order

Fig. 6 (Sakimoto) shows the complete signal flow, confirming every block below
is a dynamic element (not algebraic). Proposed 3-block partition, 10 states:

```
x_gfm_vsm = [ IBR block  :  i_d, i_q, xi_id, xi_iq         (4)
              GFM block  :  E_q                             (1)
              VSG block  :  omega_R, delta, x_gov, T_m, x_d (5) ]
```

| # | state | block | meaning | source |
|---|---|---|---|---|
| 1 | `i_d` | IBR | d-axis filter/converter current | SAKIMOTO Fig.6 (`1/(R_F+sL_F)`) |
| 2 | `i_q` | IBR | q-axis filter/converter current | SAKIMOTO Fig.6 |
| 3 | `xi_id` | IBR | d-axis current-PI integrator | SAKIMOTO Fig.6 (`K_IP+K_II/s`) |
| 4 | `xi_iq` | IBR | q-axis current-PI integrator | SAKIMOTO Fig.6 |
| 5 | `omega_R` | VSG | rotor speed (pu) | SAKIMOTO eq (4) |
| 6 | `delta` | VSG | load angle = theta_R - theta_g | SAKIMOTO eq (5),(7) |
| 7 | `x_gov` | VSG | governor PI integrator | SAKIMOTO Fig.6 (`K_GP+K_GI/s`) |
| 8 | `T_m` | VSG | turbine 1st-order output (prime-mover torque) | SAKIMOTO §2.2 (`1/(1+sT_tur)`, T_tur=120ms) |
| 9 | `x_d` | VSG | damper washout/lead state | SAKIMOTO eq (12), `1+K*tau_d*s/(1+tau_d*s)` |

GFM block: **NO dynamic state** — voltage-forming is ALGEBRAIC (no AVR, no PSS
per user decision 2026-07-22). `E_q` is set by a static reactive-power droop
(see §2 GFM block), not by an integral AVR. The GFM "voltage-forming" identity
is realized through the current loop + L-filter (IBR states), driven by the
algebraic `E_q` reference.

Notes:
- **NO AVR, NO PSS** (user decision). The Sakimoto AVR integral state `E_q` is
  removed; `E_q` becomes an algebraic reference. This is a PROJECT_DERIVED
  reduction of the Sakimoto structure (Sakimoto's own model includes an AVR).
- State count is 9, Sakimoto-derived (NOT forced to 4/13).
- `delta` (not absolute `theta_R`) is the modelled angle so the equilibrium is
  stationary on the infinite bus, mirroring the existing no-PLL GFM and the
  DARCO_SUUL `δθVSM` convention (eq 5).
- The **impedance model** (Sakimoto eq 1-2) that produces the current *commands*
  `i_d*, i_q*` is ALGEBRAIC (not a state); see §6.

## 2. Governing equations (per block) with source

### IBR block — impedance model + current controller + filter
Algebraic current command (SAKIMOTO eq 1-2), r+jx synchronous impedance:
```
[i_q*]   1        [ r   x ] [E_q - V_gq]
[i_d*] = ----- *  [-x   r ] [   -V_gd  ]          (SAKIMOTO eq 2)
         r^2+x^2
```
Current PI + decoupling → converter voltage command, then L-filter plant
(SAKIMOTO Fig.6; DARCO_SUUL eq 21-22,26 give the same decoupled SRF form):
```
v_d* = K_IP*(i_d*-i_d) + K_II*xi_id - omega*L_F*i_q + V_gd
v_q* = K_IP*(i_q*-i_q) + K_II*xi_iq + omega*L_F*i_d + V_gq
d(xi_id)/dt = i_d* - i_d
d(xi_iq)/dt = i_q* - i_q
L_F d(i_d)/dt = -R_F*i_d + omega*L_F*i_q + v_d* - V_gd   (per-unit: *omega_b)
L_F d(i_q)/dt = -R_F*i_q - omega*L_F*i_d + v_q* - V_gq
```
`SIGN/DECOUPLING`: signs to be frozen to ONE dq convention in §3;
DARCO_SUUL eq (26) `di_cv/dt = (omega_b/l_f)(v_cv - v_o) - (r_lf*omega_b/l_f + j*omega_g*omega_b) i_cv` is the cross-check.

### GFM block — voltage-forming reference (NO AVR, NO PSS)
`E_q` is NOT a state. Voltage magnitude reference is set ALGEBRAICALLY. Two
frozen options (user to pick one; default (a)):

```
(a) static reactive-power droop (PROJECT_DERIVED, GFM-standard):
    E_q = E_0 + K_q * (Q_ref - Q)          Q = V_gq*i_q + V_gd*i_d (instantaneous, algebraic)
(b) constant field EMF (simplest voltage-source-behind-impedance):
    E_q = E_0                              (no voltage support)
```
No integral regulator, no PI, no field-winding lag, no PSS. This is a
PROJECT_DERIVED reduction of Sakimoto (Sakimoto's own model has an integral
AVR; the user removes it). `E_q` feeds the impedance model (eq 2) that sets the
current command, so the converter still forms a voltage behind `r+jx`.
`DEFAULT`: option (a), algebraic Q-V droop with instantaneous Q (no filter
state, keeps the model at 9 states). If the user prefers (b), `K_q=0`.

### VSG block — rotor swing + governor + damper (NO PLL)
Electrical torque, swing, angle (SAKIMOTO eq 3,4,5,7):
```
T_e = E_q * i_q / omega_R                                  (eq 3)
J d(omega_R)/dt = T_m - T_e - T_d - D_g*omega_R            (eq 4)
d(delta)/dt = omega_b * (omega_R - omega_g)                (from eq 5-7; omega_b=377)
```
Damper (SAKIMOTO eq 12, first-order-delay washout form from Fig.6
`1 + K*tau_d*s/(1+tau_d*s)`):
```
T_d = K_tau_d * d(T_e)/dt   realized as washout state x_d:
d(x_d)/dt = ( T_e - x_d ) / tau_d
T_d = (K_tau_d/tau_d) * ( T_e - x_d )
```
This is the **no-PLL damping** — it uses d(T_e)/dt, NOT a grid-frequency
estimate, so no PLL is required (this is exactly why Sakimoto is chosen over
D'Arco-Suul). Equivalence D = K_tau_d * x/(r^2+x^2) (SAKIMOTO eq 14-15,18).

Governor: droop + PI + turbine (SAKIMOTO §2.2, Fig.6):
```
P_gov = K_gd*(omega* - omega_R) + P*        (droop, K_gd=5%)
d(x_gov)/dt = K_GI * (P_gov - P)            (governor PI integral)
T_m command = K_GP*(P_gov - P) + x_gov  -> turbine 1st order:
d(T_m)/dt = ( [K_GP*(P_gov-P)+x_gov] - T_m ) / T_tur     (T_tur=120ms)
```
`NEEDS_PDF_VISUAL_VERIFICATION`: whether `P` (measured power) feeds the governor
error directly or via a filter, and the exact P* / omega* injection points
(Fig.6 shows K_gd on P* path and K_GP+K_GI/s then 1/(1+sT_tur)).

## 3. dq orientation, sign, base, initialization

- `dq FRAME`: SRF aligned so q-axis is parallel to E_q, d-axis at right angle
  (SAKIMOTO §2.1). DARCO_SUUL uses d aligned to voltage, q leading 90° (eq 1).
  **DECISION (PROJECT_DERIVED):** adopt the Sakimoto orientation
  (`V_gd=-V_g sin δ, V_gq=V_g cos δ`, eq 8) as the single frozen convention;
  all controller signs derived consistently from it. FREEZE at approval.
- `INJECTION SIGN`: generator convention `S = V*conj(I)` (matches repo GFL/GFM
  and DARCO_SUUL eq 2). Positive P,Q flow converter→grid.
- `PER-UNIT BASE`: same as repo — `kappa=Sbase/Mbase`; internal states inverter
  base; `current_injection`/`electrical_power` return system base;
  `omega_b=377 rad/s` (60 Hz) per Fig.6 `377/s`.  (Repo standard is 60 Hz;
  Sakimoto is 50 Hz nominal — `ASSUMED_DIAGNOSTIC` mapping to 60 Hz to be
  documented in the parameter manifest.)
- `INIT`: `theta_R0 = theta_g0` at start (SAKIMOTO eq 5 note, §5.1). Algebraic
  equilibrium: solve impedance model (eq 2) + swing stationarity
  (T_m=T_e+D_g*omega_R, omega_R=1) for `E_q, delta, i_d, i_q`; integrators seeded
  so all `dx/dt=0` (mirrors existing device `equilibrium_initialize`).

## 4. Current limiting, anti-windup, low-voltage

- `CURRENT LIMIT`: SAKIMOTO Fig.6 shows a **Current Limiter** block on
  `i_d*, i_q*` (before the current PI). Adopt a magnitude clamp
  `hypot(i_d*,i_q*)<=Imax` (PROJECT_DERIVED priority rule; default P-priority as
  in GFL-RMS10 for consistency). FREEZE priority at approval.
- `ANTI-WINDUP`: conditional-hold on `xi_id/xi_iq` when the limiter is active
  and pushing further into the limit (PROJECT_DERIVED, same one-sided pattern as
  GFL-RMS10). Governor/AVR integrators: standard conditional hold at their
  saturation. Marked PROJECT_DERIVED — Sakimoto does not specify AW.
- `LOW-VOLTAGE`: positive-sequence balanced validity floor `V_div_min`
  (PROJECT_DERIVED, reuse repo convention). Fail-closed below floor; **no PLL to
  freeze** (angle from swing continues). Unbalanced/zero-voltage out of scope.

## 5. Fast-state retain/remove (RMS reduction)

Sakimoto Fig.6 current loop and D'Arco-Suul add fast states. Decision for the
positive-sequence RMS device:

| candidate fast state | decision | rationale |
|---|---|---|
| current-PI integrators `xi_id,xi_iq` | **RETAIN** | define the IBR block the user requires; slow enough for RMS |
| filter/converter current `i_d,i_q` (L-filter) | **RETAIN** | the "IBR" dynamic states; give the fast current mode |
| LC-filter capacitor voltage `v_o` (DARCO_SUUL) | **REMOVE** (algebraic) | very fast; Sakimoto already lumps filter as `R_F+sL_F` (L-filter only), no capacitor state |
| active-damping LPF `phi` (DARCO_SUUL eq 24) | **REMOVE** | only needed for LC-cap oscillation; not present in Sakimoto L-filter model |
| grid-side inductor `i_o` (DARCO_SUUL) | **REMOVE** | network handled by composite KCL, not a device state |
| damper delay `tau_d` | **RETAIN as x_d** | Sakimoto keeps it as the no-PLL damping mechanism |
| turbine `T_tur` | **RETAIN as T_m** | governor dynamics, 120 ms |

Net: 10 states (§1). This is an L-filter (not LC) positive-sequence RMS
reduction, consistent with Sakimoto's own `1/(R_F+sL_F)` filter representation
and the repo's composite-KCL network handling.

## 6. One equation set for equilibrium / SSSA / TS

The SAME nonlinear `f(x,y,u)` (§2) + algebraic impedance command (eq 2) is used
by all three analyses, exactly like GFL-RMS10:
- `equilibrium_initialize` seeds `x` so `f=0` at the PF voltage; composite KCL
  closes `g=0`.
- SSSA uses the shared `composite_sssa_model` Schur reduction `A=fx-fy(gy\gx)`
  (NO hand-built A) — same path that exposed and fixed the GFL PLL sign defect.
- TS uses shared `ts_simulate_composite`. No device-specific solver.

## 7. Open items to freeze at approval (blocking)

1. Governor P-measurement path + P*/omega* injection points
   (`NEEDS_PDF_VISUAL_VERIFICATION`, Fig.6).
2. GFM voltage-forming law: pick (a) static Q-V droop `E_q=E_0+K_q(Q_ref-Q)`
   or (b) constant `E_q=E_0`; and freeze `E_0, K_q` — `PROJECT_DERIVED`.
   (AVR/PSS removed per user decision; no integral regulator.)
3. Current-limiter priority rule (P vs Q) and Imax value — `PROJECT_DERIVED`.
4. 50 Hz→60 Hz parameter mapping and Mbase — `ASSUMED_DIAGNOSTIC`, to be
   frozen in a parameter manifest before results.
5. Exact numeric parameter set (J=4 s, r+jx=0.2+j0.4, K_gd=5%,
   T_tur=120 ms confirmed; K_GP,K_GI,K_IP,K_II,L_F,R_F,K_tau_d,tau_d,D_g from
   Sakimoto §3 parameter design / stability eq 19-25; plus voltage-forming
   `E_0,K_q` — to be tabulated). AVR gains (K_ad,K_AI) are DROPPED (no AVR).

## 8. Deliverables after approval (NOT started)

- `+ibr/gfm_vsm_sakimoto_model.m` (new device, ABI-conform, hard no-PLL guard)
- `docs/project/GFM_VSM_SAKIMOTO_PARAMETER_MANIFEST.md` (frozen params)
- register `device_type` in `+ibr/device_contract_metadata.m`
- new SMIB case + launcher option
- tests + SSSA/TDS oracle (equilibrium residual, FD Jacobian, no-PLL behavior,
  P+jQ=V·conj(I), stability)
- existing 4-state `gfm_vsg_no_pll_model` left unchanged (reduced-order option)

---

## 7b. FROZEN DECISIONS AND PARAMETERS (user-approved 2026-07-22; supersedes the open-item list in section 7)

Verified from Sakimoto Table 1 & Table 2 and Fig.6/Fig.8 (rendered images
output/diagnostics/sakimoto_tbl-05.png, sakimoto_pg-03/04.png).

Decisions:
- Voltage-forming = (a) static Q-V droop: E_q = E_0 + K_q*(Q_ref - Q), default K_q = 0.05 (reuse Sakimoto AVR droop gain K_ad; PROJECT_DERIVED). NO AVR, NO PSS.
- Delivery = NEW separate SMIB case + NEW model file; existing 4-state gfm_vsg_no_pll_model untouched.
- omega_b = 377 rad/s (60 Hz) CONFIRMED from Fig.6 "377/s". No 50->60 mapping needed.

Frozen parameters (Sakimoto Table 1 & 2):
- Impedance model: r = 0.2 pu, x = 0.4 pu
- Governor: K_gd = 0.05, K_GP = 20, K_GI = 100, T_tur = 0.12 s
- Current PI: K_IP = 1.49, K_II = 71.95 pu
- Filter (L-filter): R_F = 0.22% (0.0022 pu), omega*L_F = 8.8% (0.088 pu)
- Damper: K = 10, tau_d = 0.01 s   (note paper: K=10 => D=0.2; verify washout gain so D=K*x/(r^2+x^2) form holds, eq 15/18)
- Rotor: J = 4.0 s, D_g = 1.0 pu
- Voltage-forming (added): K_q = 0.05 (PROJECT_DERIVED)
- Command: P* = 0.0, Q* = 0.0 pu; base 10 kW / 460 V

DROPPED (no AVR): K_ad = 0.05, K_AI = 20.
DROPPED (L-filter RMS reduction): filter capacitor C = 10 uF, transformer R_tr = 2.1% / omega*L_tr = 9.1% (network handled by composite KCL / SMIB Z_line).

Remaining to confirm at implementation (from already-rendered Fig.6/Fig.8):
1. Governor: droop relation omega*-omega = -K_gd(P*-P) (Sakimoto eq 26 confirms); use instantaneous P (no extra filter state) unless Fig.8 shows a filter.
2. Damper washout: 1 + K*tau_d*s/(1+tau_d*s) on T_e -> state x_d; pin washout gain so D=K*x/(r^2+x^2).
3. Current-limiter priority (P vs Q) + Imax: PROJECT_DERIVED, default P-priority (consistent with GFL-RMS10).
