# IEEE14 IBR dynamic-equation contract — GFM-VSG + GFL-PLL (DESIGN contract)

Status: `SOURCE_INSUFFICIENT_FOR_NONLINEAR_GFL` (read-only design contract).
`IBR_PRODUCTION_INTEGRATION_READY = NOT_READY`. No VALIDATED or PRODUCTION_READY
claim is made by this document.

Approved plan:
`C:\Users\User\.claude\plans\task-ibr-dynamic-equation-contract-zany-pony.md`
(Phase 0A deliverable). This document is the durable Phase 0A artifact that
freezes the source verdict, the equation register, the existing GFM/GFL state
tables, and the Section H index/traceability contract. It does NOT define or
approve a nonlinear PLL-resolved GFL model, does NOT freeze a candidate GFL
state order, does NOT invent equations, and does NOT route any Fu realization
into PF or TS.

The `Explore`, `Plan`, and `custom-advisor` agents were consulted under the
mandatory Plan-Mode workflow. Material advisor findings verified against the
repository are incorporated (Fu Table I has numeric values; Appendix A closes
the linear network transfer model but not nonlinear GFL dynamics;
`attach_physical_decision_spectrum` creates a second modal domain
`sssa.physical_A`; REGFM angle identity is regime-dependent at bounds; "all 7
GFL poles real" is operating-point evidence, not structural).

---

## 1. Executive conclusion

```text
PAPER_SUFFICIENT_FOR_NONLINEAR_GFL                = NO
PAPER_SUFFICIENT_FOR_LINEAR_SSSA_ONLY             = YES
PAPER_REQUIRES_SECONDARY_SOURCE_FOR_NONLINEAR_GFL = YES
NREL_90260_SATISFIES_NONLINEAR_GFL_SOURCE_GAP     = NO
IBR_PRODUCTION_INTEGRATION_READY                   = NOT_READY
```

Primary source: Fu et al., *A General [P,Q]-[V] Model of Hybrid GFM/GFL
Multi-VSC Systems: Power Oscillation Analysis and Suppression Method*, IEEE
JESTIE, vol. 5, no. 4, Oct. 2024, pp. 1362-1375
(`docs/text/A_General_P_Q-_V_Model_of_Hybrid_GFM_GFL_Multi-VSC_Systems_Power_Oscillation_Analysis_and_Suppression_Method.pdf`).
Fu supplies a coherent **linear small-signal transfer-function** hybrid
GFM/GFL model (eqs 1, 12, 8-10, 18, A.1-A.6). It does not supply nonlinear GFL
PF initialization, TS integration, PLL freeze/limits, current saturation,
anti-windup, current-loop dynamics, or mode-transfer init.

Secondary source: NREL/TP-5D00-90260, REGFM_B1
(`docs/text/90260.pdf`) — a **GFM-only** specification. Its Table 1 PLL
gains/filters/limits are GFM-applicable and **cannot silently become GFL
parameters** without an explicit `PROJECT_MAPPED`/`CASE_DEFINED` classification
decision. It does not close the nonlinear GFL source gap.

A realization of Fu's `G_a(s)`, `Y_a(s)`, or `G_p(s)` may serve as a separate
linear analytical diagnostic only — it is **non-unique**, must be classified
`PROJECT_DERIVED` + `LINEAR_DIAGNOSTIC_ONLY`, its states named as perturbation
states, and must never be represented as the nonlinear production GFL.

The correct next step is **NOT to write a GFL immediately** — it is Phase 0B:
locate an authoritative nonlinear positive-sequence GFL source that supplies
the complete checklist in §10 (PLL angle + integrator ODE; PLL gains/base/
freeze/limits; P/Q measurement + controller equations; current command/
dynamics; dq/network transformations; current limit/priority/anti-windup;
equilibrium initialization; low-voltage behavior; parameter table; valid
timescale/domain). Until that source is approved, the current system's SSSA may
be run, but reports must state plainly:

- **GFM:** explicit VSG and PLL states available.
- **GFL:** WECC dynamic states available; explicit PLL state absent.
- **GFL PLL participation:** **NOT APPLICABLE TO CURRENT PRODUCTION MODEL.**

No report may claim, plot, or attribute a "GFL PLL mode" or "GFL PLL
participation" against the current WECC production model.

---

## 2. Primary-source equation register

Tildes denote small-signal perturbations. Sign convention throughout Fu is
generator (positive `S̃_i` injected into node `i`; `S̃_Li` out of node). Frame:
steady phase aligned to d-axis; **dq lead/lag not explicitly named** in Fu;
per-unit base **unstated** in Fu. Inner current loop and LCL **explicitly
neglected** (p.1363 GFM, p.1365 GFL: `i_id = i_idref`).

| Eq | Page | Symbols | Meaning | I/O | Frame/sign/base | GFM/GFL/Net | Type |
|---|---|---|---|---|---|---|---|
| (1) | 1363 | `ṽ_p = G_b(s) ṽ_i* − Z_b(s) S̃` | GFM small-signal [P,Q]-[ω,V] coupling | ref + injected power → terminal ω,V | device VSG DQ; gen sign; pu unstated | GFM | linearized |
| T-II | 1364 | `Z_b=diag(1/(Js+Dp), 1/(Ks+Dq))`, `G_b=diag(Dp/(Js+Dp), Dq/(Ks+Dq))` | VSG swing + voltage-droop channels | P̃,Q̃ → ω̃,Ṽ | symbolic params | GFM | linear TF |
| (12) | 1365 | `S̃ = G_a(s) S̃* − Y_a(s) ṽ_p` | GFL small-signal [P,Q]-[ω,V] coupling | power refs + terminal ω,V → injected S | PLL DQ; gen sign; pu unstated | GFL | linear TF |
| (12)def | 1365 | `G_a(s)=I_2`, `Y_a(s)` 2×2 rational | MIMO transfer; **realization non-unique** | [P̃*,Q̃*], ṽ_p → [P̃,Q̃] | polar small-signal | GFL | linear TF |
| (8) | 1365 | `ω̃_si = (1/s) φ̃_si`, `φ̃_si = (k_p,l + k_i,l/s) V_pi0 (φ_pi − φ_si)` | PLL perturbation relation (no limits/init/wrap) | phase error → conv phase/freq | PLL DQ | GFL PLL | small-signal TF |
| (9) | 1365 | `G_p(s) = ((k_p,l s + k_i,l) V_pi0)/(s² + (k_p,l s + k_i,l) V_pi0)` | closed-loop PLL TF | phase pert → sync'd phase | PLL DQ | GFL PLL | linear TF |
| (10) | 1365 | `ĩ_id = (1/(1.5 V_pid0)) P̃_i* − (k_df s/(s+c) + k_pf) ω̃_si`, `ĩ_iq = −(1/(1.5 V_pid0)) Q̃_i* − k_Q Ṽ_pi` | GFL current command; **inner loop neglected** | refs + ω̃,Ṽ → ĩ_dq | device PLL DQ | GFL | linearized algebraic |
| (11) | 1365 | `P̃ = P̃* + (P/V0)Ṽ − G_11(s) φ̃`, `Q̃ = Q̃* − k_Q Ṽ − (Q/V0)Ṽ + (P(1−G_p)/s) φ̃` | GFL output power from (6)+(9)+(10) | refs, Ṽ, φ̃ → P̃,Q̃ | PLL DQ | GFL | linear TF |
| (18) | 1366 | `S̃_i + Σ S̃_it − Σ S̃_ti − S̃_Li = 0` | node KCL in **power variables** | flows → balance | global DQ | Network | algebraic |
| (3),(15) | 1364,1366 | RL load/line nonlinear ODEs | branch dynamics (not converter states) | Vdq → idq | global DQ | Network | nonlinear ODE |
| (A.1-A.6) | 1373 | `C_i`, `D_ij`, `C_ij`, `Y_line(s)` | load + line + network [P,Q]-[ω,V] port matrices | ṽ_p → S̃ | global DQ | Network | linear TF |

Fu Table I (p.1369) provides numeric study parameters (controller coefficients,
filters, line impedances, loads) for the paper's four-VSC study. These are
**study-context values**, not a transferable GFL dynamic-data set, and using them
outside that context requires an explicit classification decision.

### 2.1 Fu network model vs production (network-contract constraint)

Fu's `Y_line(s)` (eqs A.1-A.6, p.1373) **includes dynamic RL line/load states**
(eqs 3, 15 are nonlinear inductor ODEs), whereas the production positive-sequence
composite DAE uses an **algebraic network** (algebraic Ybus / KCL, no dynamic line
states). The two network models are therefore not directly comparable. Therefore:

- whole-system eigenvalues from Fu are **REFERENCE_ONLY**;
- numerical comparison is permitted only for **isolated converter port transfer
  matrices** under identical operating point, base, frame, and network assumptions;
- a quasi-steady reduction `Y_line(s) -> Y_line(0)` requires a separately
  documented `PROJECT_DERIVED` derivation (must state the timescale separation,
  which RL states are eliminated, and the resulting error bound);
- **Fu whole-system eigenvalues must never be acceptance targets for the
  production algebraic-network SSSA.**

### 2.2 Fu GFM port model vs REGFM_B1 (converter-contract constraint)

Fu's GFM transfer matrix is a **reduced VSG port representation** (eq 1 + Table II
Case 3) and is **not equation-identical to REGFM_B1**, which adds PLL (states
5-6), washout (state 3), voltage PI (state 4), five measurement filters (states
7-11), PQ-priority + magnitude current limiting (`limited_current`,
`pq_limits`, `voltage_limits`), and dynamic moving angle bounds (states 12-13).
It may validate:

- channel direction and signs;
- qualitative P-ω and Q-V coupling;
- low/medium-frequency port behavior.

It may **not** validate:

- exact REGFM_B1 pole locations;
- PLL/filter/current-limit modes;
- bound-state participation;
- nonlinear or large-disturbance behavior.

---

## 3. Existing GFM 13-state table (REGFM_B1)

Source: `+ibr/regfm_b1_vsg_model.m:42-44, 330-393, 580-727`. Frozen state order:

```
[omega_m, delta_IT, x_washout, x_Eint, delta_PLL, x_PLL_int,
 Pinv_f, Idinv_f, Qinv_f, Vinv_f, Iqinv_f, delta_ITmax, delta_ITmin]
```

External ABI on system base (Sbase=100 MVA); swing + filters on inverter base
via `kappa = Sbase/Mbase`. Generator convention `S = V*conj(I)`.

| # | State | ODE (source) | Unit | Init | Status/limit | Category |
|---|---|---|---|---|---|---|
| 1 | `omega_m` | `(P_ref_inv − Pinv_f − (1/mp+D1)ω_m − D2(ω_m−x_w))/2H` (Fig.2) L629 | pu/s | 0 | active | VSG swing |
| 2 | `delta_IT` | `omega0*ω_m − dot(delta_PLL)`, conditional_hold at [lb, delta_ITmax] L631-632 | rad/s | angle(E)−angle(PLL) | bounded; moving bound | VSG angle |
| 3 | `x_washout` | `wD*(ω_m − x_w)` (Fig.2) L630 | pu/s | 0 | active | washout |
| 4 | `x_Eint` | `V_ref − Vinv_f`, held when EVSM at limit + outward error L635-640 | pu*s | solve voltage PI | anti-windup | voltage PI |
| 5 | `delta_PLL` | `omega0*(kpPLL*Vq + kiPLL*x_PLL_int)`, frozen when |V|<VPLLfrz L620-626 | rad/s | angle(V0) | freeze; Δω limits deferred | PLL angle |
| 6 | `x_PLL_int` | `Vq`, frozen when |V|<VPLLfrz L624 | pu*s | 0 | freeze | PLL integrator |
| 7 | `Pinv_f` | `(kappa*P_meas − Pinv_f)/Tpf` (Eq.1) L654 | pu/s | kappa*P | active | filter |
| 8 | `Idinv_f` | `(kappa*Id − Idinv_f)/TIf` (Eq.2) L655 | pu/s | kappa*Id | active | filter |
| 9 | `Qinv_f` | `(kappa*Q − Qinv_f)/TQf` (Eq.3) L656 | pu/s | kappa*Q | active | filter |
| 10 | `Vinv_f` | `(|V| − Vinv_f)/TVf` (Eq.4) L657 | pu/s | |V0| | active | filter |
| 11 | `Iqinv_f` | `(kappa*Iq − Iqinv_f)/TIf` (Eq.5) L658 | pu/s | kappa*Iq | active | filter |
| 12 | `delta_ITmax` | `kI*(IdmaxSS − Idinv_f)`, conditional_hold [0, delta_max] L644-645 | rad/s | asin(XL*ImaxSS) | bounded | current-angle bound |
| 13 | `delta_ITmin` | `kI*((−Ke*IdmaxSS) − Idinv_f)`, conditional_hold [−delta_max,0]; `dx=0` when ESFlag=0 L647-651 | rad/s | ternary(ESFlag, −delta_max, 0) | frozen out if ESFlag=0 | current-angle bound |

`active_state_indices = 1:13` (or `1:12` when `ESFlag=0`, state 13 frozen out),
`regfm_b1_vsg_model.m:355-358`.

**Angle identity (regime-dependent, verified):**
`delta_VSM = delta_PLL + clamp(delta_IT, used_lb, delta_ITmax)`
(`regfm_b1_vsg_model.m:599, 685, 725`). At an **interior, unclamped** `delta_IT`:
`dot(delta_VSM) = dot(delta_PLL) + (omega0*omega_m − dot(delta_PLL)) = omega0*omega_m`
(L631-632). The conditional hold blocks *outward* motion only; **inward release
is allowed**, and at a stationary bound `dot(delta_VSM) = dot(delta_PLL)` (not
`omega0*omega_m`). Because the bounds are dynamic states, a clamped angle may
also track a moving bound. The piecewise behavior (interior /
upper-outward-hold / lower-outward-hold / inward-release / moving-bound) must be
reported as a fixed active-set regime, not a smooth identity. Tests must cover
all five regimes.

dq transform (`L611-615`): `Id = Ix cos δ_PLL + Iy sin δ_PLL`,
`Iq = −Ix sin δ_PLL + Iy cos δ_PLL`, `Vq = −Vx sin δ_PLL + Vy cos δ_PLL`.
Current injection: REGFM_B1 Eq.13 voltage-behind-impedance + circular `ImaxF`
clamp (`limited_current` L522-544) + PQ priority (`pq_limits`) + voltage limits
+ `delta_max = asin(XL*ImaxSS)` angle bounds.

Source-to-code mismatches (documentation, not numerical):

| Area | Code | Doc | Determination |
|---|---|---|---|
| GFM state count | 13 (`regfm_b1_vsg_model.m:340-357`) | `IEEE14_IBR_FROZEN_CONTRACT.md:117-125` claims 11 | documentation stale (Phase-5 text); correct separately, do not change production count |
| Dual-mode count | 20-state disjoint (`dual_mode_ibr_model.m:16-17,85-96`) | FROZEN_CONTRACT describes 15 | documentation stale; correct only after contract re-approval |
| GFM `Vd` | transform documented `L66-70`, only `Vq` computed `L613-615` | — | doc/impl drift; document `Vd` as contract-only or compute only if a consumer is approved |
| PLL Δω limits | deferred `regfm_b1_vsg_model.m:83-85` | provenance notes deferral | known gap; do not invent; require source-backed design |
| Dormant flags | `omegaFlag`, `VdrpFlag`, `FFlag` stored `L195, 371-386`, no branch reads them | frozen profile says active | dormant config surface; document frozen values or remove under separate review |

---

## 4. Existing GFL 7-state table (WECC REGC_A/REEC_A)

Source: `+ibr/wecc_regca_reeca_model.m:16-33, 85-164`. Frozen state order
(`SOURCE_TRANSFORMED`):

```
[Vt_f, P_f, Iq_cmd_f, Pord, Vlvpl_f, Ip_reg, Iq_reg]
```

| # | State | ODE (L135-164) | Init | Category |
|---|---|---|---|---|
| 1 | `Vt_f` | `(|V| − Vt_f)/Trv` L144 | `abs(V0)` | measurement filter |
| 2 | `P_f` | `(kappa*P_meas − P_f)/Tp` L145 | `kappa*P0` | measurement filter |
| 3 | `Iq_cmd_f` | `(iq_cmd − Iq_cmd_f)/Tiq` L150 | steady Iq0 | command/regulator lag |
| 4 | `Pord` | `rate_limit((clamp(P_ref,Pmin,Pmax) − Pord)/Tpord, dPmin,dPmax)` L146-147 | `kappa*P0` | command/order (rate-limited) |
| 5 | `Vlvpl_f` | `(|V| − Vlvpl_f)/Tfltr` L151 | `abs(V0)` | measurement filter (LVPL) |
| 6 | `Ip_reg` | `(ip_target − Ip_reg)/Tg`, upward deriv ≤ `rrpwr` L154-157 | steady Ip0 | regulator (runback-limited) |
| 7 | `Iq_reg` | `(Iq_cmd_f − Iq_reg)/Tg`, directional `Iqrmax/min` L158-163 | steady Iq0 | regulator (directional-limited) |

**Explicit PLL determination:** filters = {1, 2, 5}; command/regulator = {3, 4, 6, 7}.
**No PLL state** — no `delta_PLL`, no PLL integrator, no frequency-error
integration, no PLL freeze/clamp/reset. Current orientation is **algebraic** to
`angle(V)`: `I = (Ip − 1i*Iq)*exp(1i*angle(V))/kappa` (L188). D15 confirms this
contract (`IEEE14_IBR_DECISION_LEDGER.md:103-114`).

Each individual block is a first-order lag (real pole). Whether the interconnected
reduced matrix has only real eigenvalues is **operating-point evidence**, not a
structural guarantee — the WECC GFL still couples to network angle/voltage
through `angle(V)`. The correct statement is: **the WECC model cannot produce an
*explicit PLL-state* participation mode** (the participation factor for a
nonexistent `delta_PLL` state is identically zero for every eigenvalue). It does
not preclude angle-mediated network coupling modes. This is a feature of the
frozen D15 WECC contract, not a code/source mismatch.

**GFL PLL participation status (frozen reporting contract):** until an
explicit-state GFL source is approved (Phase 0B), every SSSA report on the
current production model must state plainly:

- **GFM:** explicit VSG and PLL states available.
- **GFL:** WECC dynamic states available; explicit PLL state absent.
- **GFL PLL participation:** **NOT APPLICABLE TO CURRENT PRODUCTION MODEL.**

No report may claim, plot, or attribute a "GFL PLL mode" or "GFL PLL
participation" against the current WECC production model.

---

## 5. Proposed PLL-resolved GFL state table (ILLUSTRATIVE, UNFROZEN)

```text
CANDIDATE_MODEL_FAMILY   = UNFROZEN
CANDIDATE_STATE_SET      = UNFROZEN
CANDIDATE_STATE_ORDER    = UNFROZEN
PRODUCTION_ROUTING       = BLOCKED on source approval
```

This is a **source-acquisition checklist**, not a frozen model. The prior
Ding-derived 6-state model was removed because its reduction and `Kps/Kis` gains
were not adequately sourced; the same unsupported reduction must not be
reintroduced under new names. For blocked rows, "exact ODE not defined" is the
required statement — an equation must not be invented to populate the table.

| Candidate state | ODE status | I/O | Equilibrium/limits | Source / classification |
|---|---|---|---|---|
| `delta_tilde_PLL` | **linear diagnostic only** — optional realization of Fu (8)-(9); symbol mapping must be visually verified first. No nonlinear `delta_PLL` ODE defined. | phase pert → sync'd phase pert | perturbation equilibrium = 0; no nonlinear init/wrap/freeze/clamp | Fu pp.1365; `PROJECT_DERIVED` + `LINEAR_DIAGNOSTIC_ONLY`; non-unique |
| `xi_tilde_PLL` | optional realization state for Fu TF; realization-dependent, not production | phase-error pert → PLL PI pert | zero pert; no nonlinear anti-windup/limits | `PROJECT_DERIVED` + `LINEAR_DIAGNOSTIC_ONLY` |
| nonlinear `delta_PLL` | **NOT DEFINED** | requires terminal dq V + phase-detector contract | init, wrap, freeze, reset, limits all missing | `BLOCKED_MISSING_SOURCE` |
| nonlinear `xi_PLL` | **NOT DEFINED** | requires exact PLL error + PI law | equilibrium, anti-windup, reset, freeze missing | `BLOCKED_MISSING_SOURCE` |
| `P_f` | **NOT DEFINED for the new model**; existing WECC `P_f` must not be silently reused | measured P → active controller | filter constant + base required | `BLOCKED_MISSING_SOURCE` |
| `Q_f` | **NOT DEFINED** | measured Q → reactive controller | filter constant + base required | `BLOCKED_MISSING_SOURCE` |
| `xi_P` | **NOT DEFINED** | active-power error → d-current/V command | gain, clamp, anti-windup, init missing | `BLOCKED_MISSING_SOURCE` |
| `xi_Q` | **NOT DEFINED** | reactive error → q-current command | sign, gain, clamp, anti-windup missing | `BLOCKED_MISSING_SOURCE` |
| `I_d` | Fu (10) supplies a **linear algebraic perturbation**, not a nonlinear ODE | P̃*, ω̃_si → ĩ_d | no saturation / nonlinear equilibrium | Fu p.1365 (10); `SOURCE_DEFINED` as linear-algebraic only |
| `I_q` | Fu (10) linear algebraic perturbation, not nonlinear ODE | Q̃*, Ṽ → ĩ_q | no saturation | Fu (10); `SOURCE_DEFINED` linear-algebraic only |
| dynamic `I_d`, `I_q` | **NOT DEFINED** | current cmds → converter injection | current-loop timescale, saturation, init missing | `BLOCKED_MISSING_SOURCE` |
| LCL / inner-loop states | omitted unless approved source + timescale contract require them | bridge → terminal current | EMT-to-positive-sequence reduction required | `BLOCKED_MODEL_CHOICE`; not implied by Fu |

A future source must explicitly define (or permit a traceable transform to):
`V_d = Vx cos δ_PLL + Vy sin δ_PLL`, `V_q = −Vx sin δ_PLL + Vy cos δ_PLL`,
`Ix = Id cos δ_PLL − Iq sin δ_PLL`, `Iy = Id sin δ_PLL + Iq cos δ_PLL`, with
generator convention `S = V*conj(I)`, an explicit inverter/system base +
`kappa=Sbase/Mbase` conversion, current injection before/after limiting, exact
equilibrium for every state, low/zero-voltage behavior, current-priority +
anti-windup + failure semantics, and mode-transfer initialization if used in the
dual-mode device.

---

## 6. Missing-equation / parameter table

| Missing item | Fu | 90260 | Required source |
|---|---|---|---|
| Nonlinear GFL PLL ODE | no | no (GFM-only) | new authoritative GFL source |
| GFL PLL gains (applicable base) | symbols only; Table I numeric = study-context | GFM values only | new GFL source/case |
| Low-voltage PLL freeze | no | GFM-only | new GFL source |
| PLL frequency/phase limits | no | GFM-only / deferred | new GFL source |
| Nonlinear P/Q outer loops | no complete contract | GFM-only | new GFL source |
| Dynamic current loop | explicitly neglected | GFM voltage-source route | new GFL source |
| Saturation + P/Q priority | no | GFM-only | new GFL source |
| Anti-windup / reset | no | GFM-only portions | new GFL source |
| Equilibrium initialization | no | GFM-only | new GFL source + project mapping |
| GFL mode-transfer init | no | no | new GFL source + approved project-derived map |
| dq lead/lag convention | unstated | REGFM_B1 GFM only | new GFL source or proved transform |
| P/Q sign mapping | generator inferable | GFM-only | must be explicitly mapped |
| Per-unit base conversion | unstated | GFM internal/external contract | new GFL source + case contract |
| LCL parameters | outside Fu's reduced controller | no GFL LCL | only if selected GFL source requires LCL |
| Positive-sequence/EMT reduction | not supplied | n/a for GFL | approved derivation only if an EMT source is chosen |

---

## 7. PF / SSSA / TS compatibility assessment

**Common production-equation rule:** for any future nonlinear GFL, equilibrium
init calls the same device equations used by production; SSSA differentiates those
exact equations at the equilibrium and fixed active regime; TS integrates those
exact continuous equations between transactions. No "SSSA-only production model"
may masquerade as the TS model. Fu's linear reference model remains separate
unless numerical equivalence to the production linearization is independently
established.

**PF/equilibrium:** no fault/trip/switching/topology transaction; initialize every
active *and* frozen state explicitly; solve full physical KCL; preserve bus-type
semantics + generator injection sign; record active limit regime; fail closed for
infeasible current, undefined low-voltage orientation, inconsistent bases, or
nonfinite residuals.

**SSSA:** event-free operating point; linearize the same production equations +
fixed active set; `A_full = fx − fy*(gy\gx)` then `A_red = A_full(active,active)`
(`composite_sssa_model.m:212-213`); no eigenvalue deletion; publish BOTH
`FULL_STATE_EIGENVALUES` (on `sssa.A`) and `PHYSICAL_DECISION_EIGENVALUES`
(on `sssa.physical_A`, after fixed-active-bound tangent elimination + common-GFM-PLL
gauge quotient, `composite_sssa_model.m:257-357`); retain frozen/inactive states
in the inventory marked `not_in_Ared`. Note: participation on `physical_A` is in
tangent/quotient coordinates and requires lifting through `Tbound`/`Lbound` and
`coordinate_quotient_left_map`/`_right_map` to map back to global states.

**Network-contract constraint (Fu vs production):** the production SSSA uses an
**algebraic network** (no dynamic line/load states). Fu's `Y_line(s)` (eqs A.1-A.6)
**includes dynamic RL line/load states** (eqs 3, 15). Therefore Fu whole-system
eigenvalues are **REFERENCE_ONLY** and **must never be acceptance targets** for
the production algebraic-network SSSA. Numerical comparison is permitted only for
isolated converter port transfer matrices under identical operating point, base,
frame, and network assumptions; a quasi-steady `Y_line(s) -> Y_line(0)` reduction
requires a separately documented `PROJECT_DERIVED` derivation.

**Converter-port constraint (Fu GFM vs REGFM_B1):** Fu's GFM transfer matrix is
a reduced VSG port representation, **not equation-identical to REGFM_B1**. It may
validate channel direction/signs, qualitative P-ω and Q-V coupling, and
low/medium-frequency port behavior. It may **not** validate exact REGFM_B1 pole
locations, PLL/filter/current-limit modes, bound-state participation, or
nonlinear/large-disturbance behavior. Do not expect eigenvalue agreement.

**Modal-math (no `inv(V)` in production):**
`A V = V Λ`, `A^H U = U Λ*`; after deterministic pairing, normalize `u_i^H v_i = 1`,
so `W^H V ≈ I` with `W^H = U^H`; signed complex participation
`p_ki = conj(u_ki) * v_ki`, `Σ_k p_ki ≈ 1`; a separate nonnegative display ranking
`ρ_ki = |p_ki| / Σ_j |p_ji|` must not be mislabeled as signed participation. For
repeated/clustered/defective/ill-conditioned eigenvalues: preserve + publish the
eigenvalues, mark individual-state participation `UNAVAILABLE_ILL_CONDITIONED`,
prefer invariant-subspace / cluster-level device participation, never fabricate a
stable dominant-state ranking.

**GAP (single-owner shared SSSA):** `composite_sssa_model.m:211-240` returns
`sssa.eigenvalues` but NO left/right eigenvectors or participation factors (those
exist only in `+smib/smib_analyze.m:32-57`, which uses `inv(V)`, and legacy
`+stability/multimachine_ssa.m:165`, neither on the mixed-resource production
path). **Safer minimal fix:** a new standalone generic `+stability` modal helper
that consumes `sssa.A` (and separately `sssa.physical_A`) + coordinate metadata
and returns eigenvectors, pairing, conditioning, signed participation, and
fingerprints — *without* modifying `composite_sssa_model.m` or
`Ared`/`A_full`/`physical_A` construction. Closing this gap touches single-owner
shared SSSA logic and requires explicit ownership assignment.

**TS:** same continuous equations as equilibrium/SSSA; faults, clearing, SG
trip/reclose, GFL/GFM switching only as explicit atomic transactions; left/right
samples distinguished; state+topology+mode+provenance committed atomically;
rollback/fail-closed when right-limit KCL or transfer init fails. Nonsmooth
current-limit boundaries require a declared fixed-active-set or one-sided SSSA
derivative.

---

## 8. Section H — Mandatory Index and Traceability Contract

Every PF/equilibrium/SSSA/TS result must expose explicit indices and mappings.
**Mode No. ≠ state index.** Never show a value/eigenvalue/trajectory/signal
without identifying its source bus, device, state, equation, and array position.
"Index" is never ambiguous — every index field states its index space.

**Bus:** `bus_position` (contiguous 1:nb) vs `bus_id` (external, may be
non-contiguous) vs `y_vr_index=2k−1` / `y_vi_index=2k` vs `kcl_real_row=2k−1` /
`kcl_imag_row=2k`. Never assume `bus_position == bus_id`.

**Resource/device:** `resource_index` (scenario.resources) vs `device_index`
(dae.devices) vs `device_id` (stable string, e.g. SG1/IBR2) vs `bus_position` vs
`bus_id` vs `device_type` vs `operating_mode` (synchronous/gfm/gfl/tripped/offline)
vs `online`. Never assume `resource_index == device_index`; print the map.

**State inventory (one row per state, active OR frozen — never silently omit):**
`local_state_index`, `global_state_index`, `active_state_position`,
`reduced_state_index` (row/col in `sssa.A`), `physical_coordinate_index` (in
`sssa.physical_A`), `state_name`, `state_symbol`, `equation_source` (doc+page+eq),
`equation_classification`, `state_status` (`ACTIVE_IN_ARED` /
`FROZEN_NOT_IN_ARED` / `INACTIVE_MODE_NOT_IN_ARED` / `OFFLINE_NOT_IN_ARED` /
`FIXED_ACTIVE_SET_ELIMINATED` / `COORDINATE_GAUGE_ELIMINATED`), `unit`, `frame`
(network / PLL DQ / VSG DQ / device-local), `in_Ared`. Publish
`nx_total / nx_active / nx_frozen / nx_inactive_anchor` and verify
`size(Ared,1) == numel(active_state_indices)`.

**Input:** `local_input_index`, `global_input_index`, `input_name`, `device_id`,
`source`, `unit`, `current value`, `equilibrium value`, `event-mutability`. Never
resolve `Tm/Efd/P_ref/Q_ref` by hard-coded offset — resolve through `input_names`
and publish resolved local/global indices.

**PF tables:** bus (pos+id, type, source load/gen rows, devices connected,
specified+solved P/Q/V/angle, residual row, limit/status); branch (row, from/to
pos+id, P/Q from/to, loss, status); execution counters (`pf_invocation_index`,
Newton iteration index, mismatch-history index, PV/PQ switching iteration, final
convergence gate + failure ID).

**Equilibrium:** `equilibrium_invocation_index`, Newton iteration index,
differential residual row ↔ global state, algebraic residual row ↔ KCL
bus/component, active-bound constraint index + constrained device/local/global
state + bound regime (interior/upper/lower), `u_eq` version/dispatch stage.

**SSSA mode indices:** `raw_eigen_index` (native `eig` column; never a stable
public id) vs `display_mode_number` (deterministically sorted table number) vs
`conjugate_pair_id` (shared by a complex pair; singleton for real roots) vs
`eigenvalue_index` (column in V / row-col in Λ after sorting) vs
`dominant_state_global_index` / `dominant_state_local_index` /
`dominant_device_index` / `participation_rank`.

**Frozen sorting contract (frozen before viewing results):** (1) descending real
part; (2) positive-imaginary member before negative; (3) descending `|imag|`;
(4) deterministic original/state tie-break.

**FULL_STATE_EIGENVALUES table** — print EVERY active-state eigenvalue, no
truncation by stability/damping/frequency; two-digit scientific notation
(e.g. `-3.99e+01 + 0.00e+00j`, `-7.55e-01 + 7.32e+00j`); both members of each
complex pair retained; repeated/real roots retained; full-precision machine values
kept in stored data. Verify `eigenvalue_count == size(Ared,1)`.

**PHYSICAL_DECISION_EIGENVALUES table** — published ALONGSIDE, never replacing,
the full table; states source matrix, dimension, removed constraints/gauge
coordinates, reduction method, global-state membership; row count
`== size(physical_A,1)` (may differ from `size(Ared,1)`).

**Participation table:** `display_mode_number`, `eigenvalue_index`,
`reduced_state_index`, `active_state_position`, `global_state_index`, `device_id`,
`local_state_index`, complex signed participation, normalized participation %,
participation rank, equation source. Verify `W'*V ≈ I`, participation sum ≈ 1 per
mode, state-ownership count == Ared dimension, conjugate members have consistent
aggregated device participation. For `physical_A` participation, also publish the
lift-map composition back to global states.

**Mode No. ≠ state index (the key point):** every SSSA mode entry must trace back
to device → state → equation → source, e.g.

```
Mode 09
  λ = -7.55e-01 + 7.32e+00j
  dominant global state x(27)
  device IBR3
  local state x_dev(1)
  state delta_PLL
  participation 43.2%
```

The gate "display_mode_number ≠ raw_eigen_index" is **NOT arithmetic** — the
integers may coincide by chance. The valid gate is: separate fields; no display
number used to index eigenvectors/states; permutation tests proving display
sorting does not alter raw eigenvector association.

**TS:** every sample exposes `time_sample_index`, `time`, `sample_side`
(ordinary/left/right), `event_index`, `transaction_id`, `topology_version`,
`dispatch_version`, `active_state_set_version`, `device online/mode status`,
state/global-index mapping version. Every event exposes `event_index`, type,
requested/actual landing time, `transaction_id`, affected `bus_position`/`bus_id`,
affected resource/device index + `device_id`, pre-event KCL norm, right-limit KCL
norm, applied/failure status, `failure_id`. Every plotted signal retains metadata:
plot series index, `device_id`/`bus_id`, global/local state index, symbol,
absolute/relative reference, unit, online interval, mode interval.

**Execution counters (distinguish invocation from iteration):**
`pf_invocations`, `pf_newton_iterations`, `equilibrium_invocations`,
`equilibrium_newton_iterations`, `sssa_invocations`, `Jacobian_evaluations`,
`eigenvalue_decompositions`, `selector_candidates_evaluated`, `ts_invocations`,
`ts_steps_attempted/accepted`, `ts_Newton_iterations`, `event_transactions`,
`failed_transactions`.

**Cross-analysis identity:** PF/equilibrium/SSSA/TS use the SAME bus map,
resource/device map, state order, input order, algebraic-y order, baseMVA/ω0, and
operating-point fingerprint. Publish a common `analysis_fingerprint` containing
at least: `case_id`, resource configuration, device modes, bus-map hash, state-map
hash, input-map hash, equilibrium fingerprint, topology version, dispatch version,
matrix domain + matrix hash, active-bound regime, gauge quotient, transformation
maps, ordering + conjugate-pair policy, modal algorithm version. SSSA and TS state
which PF/equilibrium fingerprint initialized them.

**Twelve mandatory human-readable log sections (in order):** (1) CASE AND BASE;
(2) RESOURCE/DEVICE INDEX MAP; (3) STATE INVENTORY; (4) INPUT INVENTORY;
(5) PF RESULTS; (6) EQUILIBRIUM RESULTS; (7) FULL STATE EIGENVALUES (SSSA);
(8) PARTICIPATION FACTORS (SSSA); (9) TS EVENT TRANSACTIONS (TS);
(10) TS SIGNAL INDEX (TS); (11) EXECUTION COUNTERS; (12) CONVERGENCE/FAILURE
SUMMARY. Absent data printed `NOT_RUN`/`NOT_APPLICABLE`/fail-closed — never
silently omitted.

**Present vs missing (verified):** present — `bus_position`/`bus_id`,
`device_index`, `state_start`/`state_end`, active local/global indices,
`device_offsets`, `active_state_indices`, `frozen_state_indices`, three
fingerprints (selector/committed/pre_event). Missing — `display_mode_number` vs
`raw_eigen_index` separation, `conjugate_pair_id`, single resource↔device↔device_id
printed map, plot signal metadata, common `analysis_fingerprint`, left/right
eigenvectors + participation on the composite path, explicit 12-section log
checklist.

---

## 9. Recommended implementation phases

| Phase | Type | Content | Gate |
|---|---|---|---|
| 0A | read-only/design | freeze Fu/90260 equation register + insufficiency verdict; preserve D15 + WECC routing; record requirements for an acceptable nonlinear GFL source (THIS DOCUMENT) | no statement implies Fu supplies a nonlinear GFL |
| 0B | user/source decision (no mutation) | locate an authoritative nonlinear positive-sequence GFL source covering checklist (a)-(j) in §10; then approve that source OR freeze Fu as linear-SSSA-only | approved source covers all ten checklist items |
| 1 | implementation (IBR-owned; approve) | freeze device/state/input/active-frozen/reduced-state maps; retain frozen states in inventory; add equation-source + ownership metadata | state-map cardinality + 1-to-1 ownership checks pass |
| 2 | implementation (single-owner shared; approve) | new standalone `+stability` modal helper consuming `sssa.A` and separately `sssa.physical_A` + coordinate metadata; right/left eigensolves, deterministic pairing, biorthogonal normalization, signed participation vs display ranking, residual/conditioning/biorthogonality; **Ared/A_full/physical_A construction unchanged** | eigen/participation gates pass OR participation fails closed `UNAVAILABLE_ILL_CONDITIONED`; Ared numerically bit-identical |
| 3 | implementation (approve) | Section H reporting: raw/display/conjugate identities, full+physical spectrum tables, common fingerprint, counters, TS signal metadata, 12 log sections | permutation, count, fingerprint, consumer-compatibility tests pass |
| 4 | implementation (BLOCKED on 0B) | explicit-state nonlinear GFL: freeze model family, equations, state order, parameters, bases, limits, init; new model file (do not mutate WECC semantics) | complete source→equation→state traceability; no invented quantity |
| 5 | implementation (BLOCKED on 4; single-owner shared) | PF/SSSA/TS routing of the new GFL through the SAME equations; atomic switching/transfer if approved; targeted + final regression | all predeclared numerical/physical/compatibility/regression gates pass |

Phases 0A/0B are design/decision only. Phases 1-5 are implementation and each
requires a separate approved plan and ownership assignment before mutation.
Source-contract closure (0A/0B) and modal/reporting implementation (2/3) are
**separate approval units** with different ownership, risks, and evidence.

### Phase 0B — authoritative nonlinear GFL source checklist

A future source must supply, at minimum:

- (a) PLL angle + integrator ODE (nonlinear, with named integral state);
- (b) PLL gains, base, freeze, limits (with numeric values or sourced formulas);
- (c) P/Q measurement + controller equations (nonlinear ODEs);
- (d) current command/dynamics (ODE or declared-neglected with timescale);
- (e) dq/network transformations (explicit lead/lag convention);
- (f) current limit/priority/anti-windup (with saturation semantics);
- (g) equilibrium initialization (every state);
- (h) low-voltage behavior (freeze/fail-closed contract);
- (i) parameter table (numeric values + provenance);
- (j) valid timescale/domain (positive-sequence RMS, not EMT/LCL unless reduced).

### Phase 0B — source-type recommendation (no arbitrary parameter search)

Per task policy (`Do not search for arbitrary parameters. Recommend only what type
of authoritative source is needed`), this section recommends the *type* of
authoritative source required. It does NOT cite specific values or fit parameters.

The gap is a **nonlinear positive-sequence RMS grid-following inverter model with
explicit PLL state and current-source interface**, suitable for phasor-based
PF/equilibrium, full-state SSSA, and fixed-step nonlinear TS. Candidate
authoritative source types, in descending order of preference:

1. **A published positive-sequence RMS GFL inverter specification with full
   state-space ODEs** (PLL angle + integrator, P/Q outer-loop PI, current-command
   lags, current-limit/priority, anti-windup, equilibrium init, low-voltage
   freeze), explicit dq/network transformation and P/Q sign convention, per-unit
   base, and a parameter table. This is the ideal close — analogous to what
   NREL/TP-5D00-90260 provides for REGFM_B1 GFM, but for a GFL.

2. **A WECC/IEEE generic positive-sequence GFL model extension** that adds an
   explicit PLL state to the existing REGC_A/REEC_A structure (currently PLL-less
   per D15). If such an extension exists as a documented specification with
   sourced ODEs and parameters, it would preserve compatibility with the existing
   7-state WECC base.

3. **A peer-reviewed paper with complete nonlinear GFL state equations** (not
   small-signal transfer functions) covering all ten checklist items (a)-(j),
   with explicit dq convention, per-unit base, and a reproducible parameter table.
   The Fu paper is explicitly NOT sufficient (small-signal only; inner loop
   neglected; no nonlinear PLL/limits/saturation/init).

4. **A documented `PROJECT_DERIVED` reduction from an EMT GFL source** (e.g.
   Ding 83340 §II-B EMT model) to positive-sequence RMS, IF the user explicitly
   approves the reduction and the timescale-separation derivation is documented
   with eliminated states and error bounds. This was the prior Ding route; it was
   removed because the reduction and `Kps/Kis` gains were unsourced. Re-approval
   requires the reduction derivation to be written and falsification-tested before
   the model code (per D16 transfer-map precedent and AGENTS.md test-first rule).

Sources that are **NOT acceptable** as the sole basis:

- Fu et al. primary paper (small-signal transfer functions only; non-unique
  realization; no nonlinear ODEs/limits/init);
- NREL/TP-5D00-90260 (GFM-only; no GFL equations);
- standard textbook "positive-sequence GFL practice" without a named
  equation-level source (unsourced);
- EMT/LCL models without an approved timescale reduction (incompatible with the
  phasor composite DAE).

**Decision required from the user (Phase 0B):**

- (1) Approve a specific source of type 1/2/3 above (user supplies or authorizes
  the source; the source must cover all ten checklist items), OR
- (2) Explicitly freeze Fu usage as linear-SSSA-only and abandon the nonlinear
  explicit-state GFL until a source is available, OR
- (3) Authorize a `PROJECT_DERIVED` reduction (type 4) with a separate approved
  plan that writes the reduction derivation and falsification tests before model
  code.

Until one of (1)/(2)/(3) is chosen, Phase 4 (explicit-state nonlinear GFL) and
Phase 5 (PF/SSSA/TS routing) remain **BLOCKED**. Phase 1 (Section H core
mappings) and Phase 2 (modal helper) are NOT blocked by Phase 0B and may proceed
under their own separate approved plans.

---

## 10. File allowlist for the future implementation

No file may be edited before explicit plan approval. Discovery of a necessary file
outside the allowlist is a stop condition.

**Track-B-owned IBR scope:** `+ibr/**`, `tests/test_ibr_*.m`, `docs/ibr/**`,
`scripts/ibr/**`. Likely symbols: `ibr.gfl_model`, `ibr.wecc_regca_reeca_model`,
`ibr.regfm_b1_vsg_model`, `ibr.dual_mode_ibr_model`. A new nonlinear GFL should
be a new model file, not a silent change to WECC semantics.

**Single-owner shared scope (requires ownership transfer before edit):**
`solve_case.m`, `run_pf.m`, `run_ssa.m`, `run_ts.m`, `pf_init_paths.m`,
`+stability/composite_sssa_model.m`, `+stability/multicase_sssa.m`,
`+stability/multimachine_ssa.m`, `+stability/composite_dae.m`,
`+stability/mixed_equilibrium_solve.m`, `+stability/ts_simulate.m`, and applicable
shared DAE/TS kernel/algebraic/topology/event helpers. Phase 2 modal helper is a
new file under `+stability/` (not an edit to `composite_sssa_model.m`), but still
single-owner shared stability mathematics.

**Coordination/contract docs:** `docs/project/TRACK_COORDINATION.md`,
`docs/project/AGENT_HANDOFF.md`, `docs/project/IEEE14_IBR_DECISION_LEDGER.md`,
`docs/project/IEEE14_IBR_FROZEN_CONTRACT.md`, GFM/GFL provenance docs. The stale
11-state GFM and 15-state dual-mode descriptions in FROZEN_CONTRACT must be
corrected separately from any new mathematical contract unless the approved plan
explicitly combines them.

---

## 11. Predeclared numerical and physical verification gates

**Equilibrium/KCL:** every active-state derivative finite; active-`f` residual
∞-norm < tolerance; full physical KCL ∞-norm < tolerance; every state has an
initialization producer; active/frozen regime reported; infeasible current fails
closed.

**Equation/Jacobian:** independent equation-level derivative checks; analytical
or complex-step Jacobian comparison where equations permit; centered FD where
nonsmooth logic inactive; fixed-active-set/one-sided checks at declared limit
regimes; Schur reconstruction `A_full ≈ fx − fy*(gy\gx)`; `Ared` equals approved
active projection of `A_full`; **no `inv` or `pinv`**; no external solver/loaded
solution in production.

**Eigenvector/participation:** for every eigenpair,
`||A v_i − λ_i v_i|| / max(1,||A||·||v_i||) ≤ τ_R` and
`||A^H u_i − conj(λ_i) u_i|| / max(1,||A||·||u_i||) ≤ τ_L`; deterministic
left/right pairing; `W'*V ≈ I`; `u_i'*v_i ≈ 1`; `Σ_k p_ki ≈ 1`; conjugate-pair
consistency; deterministic failure for ambiguous pairing;
`UNAVAILABLE_ILL_CONDITIONED` for defective/unresolved clusters; lift-map
composition residual for `physical_A` participation back to global states.

**Section-H gates:** state-inventory cardinality == total device-state count;
count marked `ACTIVE_IN_ARED` == `size(Ared,1)`; frozen states retained in
inventory marked `not_in_Ared`; every reduced state maps to exactly one global
state/device/equation; every mode's dominant state maps to a device+source;
separate raw/display fields exist; permutation test proves display sort does not
alter raw eigenvector association; `FULL_STATE_EIGENVALUES` row count ==
`size(Ared,1)`; `PHYSICAL_DECISION_EIGENVALUES` row count == `size(physical_A,1)`;
full precision retained despite scientific-notation display; `analysis_fingerprint`
stable under identical input, changes under material contract change.

**Permutation invariance:** under a controlled device/state permutation —
eigenvalue multiset invariant within tolerance; eigenvectors stay associated
through raw indices/maps; aggregate device participation invariant; display order
changes only per its declared sort; state ownership correct after inverse
permutation.

**PF/SSSA/TS compatibility:** identical state names + order at PF equilibrium,
SSSA init, TS start; identical parameter/base/frame contract; SSSA differentiates
the same production RHS/current injection used by TS; event-free TS initial
derivatives match equilibrium residuals; current-limit + active-regime choices
identical at the common operating point.

**Limits/events:** low/zero-voltage fails closed or follows approved source;
current-priority tests cover P- and Q-binding; anti-windup tests cover
entry/hold/release/opposite-direction recovery; transaction tests cover
accepted/rejected/rollback; left/right sample + transaction identities consistent.

**Regression:** if implementation changes production equations, shared
dispatch/schema, composite DAE, SSSA, TS, topology/events, or path integration,
run once on the final unchanged tree:

```matlab
pf_init_paths; r = runtests('tests','IncludeSubfolders',true);
```

Record branch, tested commit/tree, MATLAB environment, exact commands,
passed/failed/incomplete counts, targeted metrics + limitations, whether full
regression was required, and post-test source-tree identity.

---

## 12. Risks and stop conditions

| Risk / stop condition | Required action |
|---|---|
| Fu symbol interpretation (esp. (8)-(9)) cannot be visually verified | stop; inspect primary paper before publishing a realization |
| nonlinear state/gain/base/limit/init/dq sign lacks authoritative source | stop; return to Plan Mode and request/obtain the source |
| source supplies only a transfer function with multiple realizations | keep linear-diagnostic only, or obtain approval for a specifically classified `PROJECT_DERIVED` realization |
| selected source is EMT/LCL while runtime is positive-sequence phasor TS | stop; obtain an approved timescale reduction + compatibility contract |
| proposal relabels a WECC state as PLL | reject immediately |
| proposal restores Ding `Kps/Kis` or equivalent unsourced gains | reject; require re-approval + authoritative evidence |
| new model conflicts with D15 or changes the frozen 20-state dual layout | stop; return to Plan Mode and request frozen-contract re-approval |
| state order / active-frozen semantics / mode-transfer behavior changes | stop and re-plan |
| shared SSSA/DAE/TS ownership not assigned | do not edit shared files; request ownership transfer |
| participation work changes `Ared`/`A_full`/`physical_A` | roll back the modal change and diagnose before proceeding |
| left/right pairing, residual, conditioning, or biorthogonality gate fails | preserve eigenvalues; mark participation unavailable; do not publish dominant-state claims |
| repeated/defective modes make individual participation non-unique | publish cluster/subspace result or unavailable status |
| ambiguity whether analysis targets `sssa.A` or `sssa.physical_A` | stop; declare the domain before computing participation |
| missing/dimensionally inconsistent tangent/quotient lift maps | stop; do not publish physical-coordinate participation without lift |
| Section-H schema reveals unlisted consumers/files | stop and expand the plan allowlist with approval |
| PF, SSSA, and TS found to use different equations/regimes | stop; reconcile the common production contract before results |
| implementation attempts `inv`/`pinv`/external solver/generated model/loaded solution | reject and return to allowed project-owned MATLAB primitives (`\`, `lu`, `qr`, `eig`) |
| `main` advances or ownership changes before implementation | reinspect diff, ownership, gates; re-plan if material |
| a gate fails unexpectedly | preserve evidence, create/update defect record, ask before scope expansion |
| user authorizes a `PROJECT_DERIVED` nonlinear GFL | does not change the source verdict; triggers a NEW plan with revised classification, allowlist, equations, failure semantics, gates |
| Fu whole-system eigenvalues used as acceptance targets for production algebraic-network SSSA | reject immediately; Fu network has dynamic RL states, production is algebraic — not directly comparable |
| Fu GFM port model expected to match REGFM_B1 eigenvalues | reject; Fu is a reduced VSG port, not equation-identical to REGFM_B1 |
| a quasi-steady `Y_line(s) -> Y_line(0)` reduction used without a documented `PROJECT_DERIVED` derivation | stop; document the timescale separation, eliminated RL states, and error bound first |
| a report claims/attributes a "GFL PLL mode" or "GFL PLL participation" against the current WECC production model | reject; GFL PLL participation is NOT APPLICABLE TO CURRENT PRODUCTION MODEL until an explicit-state GFL source is approved |
| writing a new GFL before Phase 0B approves an authoritative source | reject; the next step is source acquisition, not implementation |

---

## Final status

`IBR_PRODUCTION_INTEGRATION_READY` remains `NOT_READY`. This design produces a
source-traceable contract and identifies the source gap; it does NOT define or
approve a nonlinear PLL-resolved GFL model, does NOT freeze a candidate state
order, does NOT invent equations, and does NOT route any Fu realization into PF
or TS. No VALIDATED or PRODUCTION_READY claim is made.

Phase 0A deliverable complete. Phases 0B/1-5 remain pending; each implementation
phase requires a separate approved Plan Mode cycle and ownership assignment before
mutation per `AGENTS.md` and `TRACK_COORDINATION.md`.
