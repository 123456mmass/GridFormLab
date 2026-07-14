# IEEE14 1-SG + 4-IBR Mission — Decision Ledger (Phase 1B)

**Status:** `IEEE14_IBR_EQUATION_CONTRACT_READY = PASS` for the implemented
structural contracts. GFL `Kps/Kis` remain `ASSUMED_DIAGNOSTIC` and excluded
from production acceptance; `IBR_PRODUCTION_INTEGRATION_READY = NOT_READY`.
Legacy `SOURCE_VERBATIM` and `SOURCE_TRANSFORMED` labels are documentary
sublabels of `SOURCE_DEFINED`.

**Branch:** `main`. **Last corrective update:** 2026-07-15.

Per the user directive: the six remaining items are now engineering-design
contracts, NOT ASSUMED_DIAGNOSTIC values. Each is resolved below with:
(1) exact equations/values required; (2) verified source candidates with
page/equation locations; (3) compatibility with project states, bases, signs,
device ABI; (4) mutually exclusive choices and consequences; (5) the
smallest user/advisor decision required. No value may change after viewing
outcomes to obtain a pass.

The autonomous selection hierarchy (directive 3) is applied where
alternatives exist. CASE_DEFINED values are allowed when directly determined
by the IEEE14 case, a user directive, or a deterministic
conservation/feasibility equation. Transfer maps are PROJECT_DERIVED only
after continuity/reset equations and falsification tests are written.

---

## 2026-07-15 corrective decisions — authoritative

This section supersedes older implementation-status and dispatch/slack prose
below where it conflicts. `SOURCE_VERBATIM` and `SOURCE_TRANSFORMED` are
documentary sublabels of the canonical `SOURCE_DEFINED` class.

### D10 — Reference coordinates do not replace KCL equations

The old angle-vcon formulation could report a small reduced residual while
omitting a physical KCL mismatch (about 0.581 pu for SG_OFF and 1.586623 pu
for SG_ON). It is rejected.

- SG REF fixes both rectangular case-REF voltage coordinates and solves
  constant `[Tm;Efd]` as equilibrium outputs.
- SG_OFF GFM REF fixes one angle coordinate and solves one selected reference
  `P_ref` as the balancing output.
- Both residuals retain every rectangular KCL row.
- The solved `u_eq` and immutable context are held constant by audited TS and
  SSSA; no time-step re-slack is allowed.

Classification: network equations `SOURCE_DEFINED`; coordinate/control
closure `PROJECT_DERIVED`; damped Newton and FD Jacobians `NUMERICAL_METHOD`.

### D11 — Variable-count, index-selected GFMs with one reference

- `n_gfm_required` is explicit; 1, 2, 3, or more selected GFMs are permitted.
- `selected_gfm_indices` must equal the complete online runtime GFM set.
- Exactly one selected member is the numerical reference. Other selected
  resources remain physical GFMs and share through the model equations.
- A hybrid snapshot owns the atomic selection/count/reference tuple. Duplicate
  caller metadata must agree or the solve fails closed.
- With an online SG, the SG at the case REF bus remains the numerical REF; the
  committed GFM reference applies on the SG_OFF right limit.

Classification: user mission requirement `CASE_DEFINED`; index validation and
transaction mechanics `PROJECT_DERIVED`.

### D12 — Dispatch and reference active power

The Pmax-proportional schedule remains the CASE_DEFINED non-reference dispatch.
It is not, by itself, a network-feasibility proof and Pmax compliance does not
prove `ImaxSS` compliance.

- Non-reference GFM `P_ref` remains scheduled.
- Every GFM reactive output is solved by the network/voltage equations.
- The one reference GFM `P_ref` is an equilibrium output that balances load
  and losses. The result records scheduled P, solved P, deviation, and Pmax.
- Feasibility requires convergence, all-KCL residual `<1e-6`, reduced Jacobian
  `rcond>1e-10`, and explicit implemented device-limit checks.
- No `ImaxSS` readiness claim is permitted before Phase-G2 implements the
  sourced steady-state limiter.

### D13 — Inactive/offline state semantics

- Inactive online dual-mode states are exact holds (`dx=0`); the old artificial
  `lambda=1e-3` decay is removed.
- Offline dual-mode IBR: `f=0`, `I=0`, `Pe=0`, no active states.
- Offline SG: excluded from stationary equilibrium/SSSA, but TS integrates
  rotor coast and open-circuit flux dynamics with zero network current.
- `Tpq0=0` `Edp` remains a frozen SOURCE_DEFINED singular limit.

### D14 — Phase-G split and readiness

G1 implemented REGFM_B1 Eq.13 transient clamp, correct inverter/system-base
conversion, sourced `VPLLfrz=0.05`, and one shared current helper. G2 still
owns Emax/Emin handling, anti-windup, PQ priority, Fig.6 `kI/s`, and Eqs.10-11.

GFL `Kps/Kis` remain `ASSUMED_DIAGNOSTIC`; therefore the blanket historical
claim “No ASSUMED_DIAGNOSTIC production values” is not a readiness claim.

```text
IEEE14_IBR_GFL_MODEL_READY       = STRUCTURAL_ONLY
PHASE_G1_LIMITER_READY           = IMPLEMENTED_STRUCTURAL_ONLY
IBR_PRODUCTION_INTEGRATION_READY = NOT_READY
```

---

## Item 7 — IEEE14 SG1 dynamic data → CASE_DEFINED (designed from IEEE14 case + IEEE 1110-2002 typical-data clause)

### 1. Exact equations/values required

SG1 (bus 1, the sole SG) requires, on the SG1 machine MVA base:
- Inertia `H` (s), damping `D` (pu)
- Reactances: `Xd, X'd, X''d, Xq, X'q, X''q, Xl, Ra`
- Time constants: `T'do, T''do, T'qo, T''qo`
- Saturation: `S(1.0), S(1.2)` (optional; default no-saturation is acceptable)
- Exciter (IEEE Type 1 / IEEET1): `KA, TA, KE, TE, KF, TF, VRmax, VRmin`
- Machine MVA base `Sr` (MVA), rated kV `Vr` (kV)

The 4 IBR buses (2, 3, 6, 8) become IBR devices and do NOT need SG dynamic
data — they use the REGFM_B1 VSG model (item 2) and the GFL model (item 1).

### 2. Verified source candidates

- **IEEE Std 1110-2002 Clause 5.1 (p.18):** "For new generation that is being
  considered at the initial stages of planning, generator data is not
  available; therefore, typical data is used dependent on the size and type of
  generating unit being considered. Once the generator manufacturer is
  chosen and design information should be used." — AUTHORIZES typical data
  for planning, sized by machine type/size.
- **IEEE 1110-2002 Table 1 (p.15) + Clause 5.3.2 (p.20):** Model 2.2
  (round-rotor, 6th-order subtransient) is the recommended structure for
  turbogenerators. The project's existing `emf6_dae` implements this.
- **Demetriou et al. (2015), Table I p.3:** 50 Hz IEEE14 modified, Gen1
  448 MVA H=2.656. INCOMPATIBLE frequency (our case is 60 Hz).
- **Kodsi (U.Waterloo TR 2003-3), Table A.2 p.38:** 60 Hz (US system), Gen1
  615 MVA H=5.148, full 6th-order subtransient data per generator. Root
  source Anderson & Fouad (same as Demetriou).

### 3. Compatibility + selection

The IEEE14 MATPOWER case is 60 Hz (verified: baseMVA=100, the case follows
US convention). This EXCLUDES Demetriou (50 Hz). Kodsi is 60 Hz and provides
a complete 6th-order dataset for all 5 generators with consistent root
provenance (Anderson & Fouad). However, Kodsi's Gen1 Sr=615 MVA conflicts
with the case's bus-1 Pg=232.4 MW (a 615 MVA machine at 232 MW is at 38%
loading — unusual but not infeasible; the case's Pmax=332.4 MW for bus 1
suggests a ~300-400 MVA machine, closer to Kodsi's 615 than Demetriou's
448).

**Selected (CASE_DEFINED, frozen):** Use Kodsi's 60 Hz dataset (Table A.2
p.38) as the SG1 dynamic-data base, converted to the project's system base
(100 MVA) via `X_system = X_device * (S_system/S_machine)` per IEEE 1110-2002
Clause 7.4 (p.47-55). Only bus 1 retains SG dynamics (SG1); buses 2, 3, 6, 8
become IBR devices (items 1, 2). No dataset mixing.

**Engineering rationale for choosing Kodsi over designing from scratch:**
IEEE 1110-2002 Clause 5.1 authorizes typical data by machine size/type.
Kodsi provides exactly that (typical IEEE14 data sized from Anderson &
Fouad) and is 60 Hz (matches the case). Designing SG reactances from
scratch without a sizing reference would be UNSOURCED; Kodsi is a published
60 Hz IEEE14 dataset — the strongest available provenance. The values are
labeled CASE_DEFINED (sourced from a published IEEE14 dataset, not a
manufacturer datasheet).

### 4. Mutually exclusive choices

- (a) Kodsi 60 Hz (SELECTED) — complete, 60 Hz, published IEEE14 dataset.
- (b) Demetriou 50 Hz — REJECTED (frequency incompatible with the 60 Hz case;
  would require changing case frequency, forbidden by AGENTS rule 7 only
  if the source were authoritative; here the case IS 60 Hz).
- (c) Design SG reactances from scratch by machine type — REJECTED (no
  sizing reference; would be UNSOURCED, violating directive 1).
- (d) Use the project's existing classical defaults H=5.0/D=0/X'd=0.30 —
  REJECTED (UNSOURCED textbook guesses, no machine-type/size justification).

Consequence of (a): SG1 is a round-rotor turbogenerator (Model 2.2);
bus-1 Pg=232.4 MW at 615 MVA = 38% loading (low but valid for a slack bus
that also supplies losses).

### 5. Smallest user decision required

None — selection (a) is autonomous per hierarchy (a) "IEEE14-specific
published profile with complete dynamic data." Kodsi qualifies. Documented
in this ledger.

### Falsification evidence

The Kodsi profile, `Tpq0=0` frozen-state reduction, all-KCL SG reference,
solved `Tm/Efd`, MATPOWER bus-shunt contribution, and equation-shared SSSA are
covered by the Phase-B1 and `test_ieee14_sg_reference_equilibrium` suites.
No manual reference-mode eigenvalue deletion or artificial epsilon time
constant is used.

---

## Item 1 — GFL positive-sequence model → PROJECT_DERIVED reduction from Ding + standard utility representation (Phase 5 STRUCTURAL_ONLY freeze)

### 1. Exact equations/values required

A positive-sequence RMS GFL model compatible with the project DAE (current-
source, PLL-synchronized). **Phase 5 frozen state vector (6 states):**
`x_gfl = [delta_pll, eps_pll, P_f, Q_f, phi_P, phi_Q]^T` (reduced from Ding's
14-state EMT). The earlier "~6-8 states" range is CLOSED at 6. Ding Eq.9
defines phi_P/phi_Q as differential PI-integrator states; Ding Eq.10 defines
i_d*/i_q* as ALGEBRAIC current references (NOT states). No current-reference
filter states, no new time constant.

### 2. Verified source candidates

- **Ding 83340 §II-B (pp.3-4), Eqs. 8-10 + shared 3-6:** full EMT GFL
  (14-state: PLL ε_L/δ_inv, P/Q filters, voltage/current PI, LCL filter).
  SOURCE_VERBATIM at equation level.
- **REGFM_B1 90260:** GFM-only, no GFL. BUT REGFM_B1 Table 1 provides
  kpPLL=0.265, kiPLL=2.65 (PLL gains, SOURCE_VERBATIM values) adopted as the
  common IEEE14 dual-mode converter PLL profile (CASE_DEFINED/PROJECT_MAPPED
  application to the GFL).
- **Standard utility representation (positive-sequence RMS current source):**
  the conventional GFL for phasor-based stability studies. Not in a single
  inspected source as explicit reduced-order state equations, but is the
  universally accepted reduction documented in power-system stability texts.

### 3. Compatibility + derivation (Phase 5 freeze)

The reduction from Ding's EMT to positive-sequence RMS is a PROJECT_DERIVED
semantic choice, justified by:
- The project DAE is phasor-based (positive-sequence RMS), not EMT.
- Ding's EMT model's inner voltage/current loops and LCL filter operate at
  switching frequency, far above the electromechanical bandwidth. In RMS
  reduction, the inner loops are assumed instantaneous (algebraic), leaving
  the PLL + outer P/Q tracking + filter dynamics.
- The reduced 6-state vector preserves the PLL synchronization (essential for
  GFL) and the P/Q power-loop PI (the GFL's controlled outputs).

**Phase 5 frozen equations (v3):**
- `d(eps_pll)/dt = Vq_pll`; `d(delta_pll)/dt = omega0*(kpPLL*Vq_pll + kiPLL*eps_pll)`.
- `d(P_f)/dt = omega_c*(Pinv_meas - P_f)`; `d(Q_f)/dt = omega_c*(Qinv_meas - Q_f)`.
- `d(phi_P)/dt = +(Pref - P_f)`; `d(phi_Q)/dt = +(Qref - Q_f)`.
- `i_d* = +Kps*(Pref - P_f) + Kis*phi_P`; `i_q* = -Kps*(Qref - Q_f) - Kis*phi_Q` (Q-sign corrected).
- `I_gfl = (i_d* + j*i_q*)*exp(j*delta_pll)` (system base; NO Mbase factor).

**Sign/base compatibility:** current INTO network (positive injection,
matches composite `YV-I`); `S = V·conj(I)`; system base 100 MVA only (no
inverter-base conversion). The GFL's current injection
`I_gfl(t, x_gfl, y, u_gfl, event_context)` is the device output to the composite.

### 4. Mutually exclusive choices

- (a) PROJECT_DERIVED reduction from Ding (SELECTED) — preserves sourced
  structure, reduces to phasor-compatible.
- (b) Use Ding's EMT model directly — REJECTED (EMT/LCL incompatible with
  the phasor DAE; would require a different solver infrastructure).
- (c) Design a custom GFL from scratch — REJECTED (UNSOURCED).

### 5. Smallest user decision required

None — reduction (a) is PROJECT_DERIVED with documented derivation and
falsification tests. The continuity/reset equations are written in Phase 5
before the model code.

### Parameter freeze (Phase 5, BEFORE results)

- `omega0 = 376.99 rad/s` (SOURCE_VERBATIM, REGFM_B1 Table 1 omega0).
- `omega_c = 10 rad/s` (SOURCE_VERBATIM, Ding Table I).
- `kpPLL = 0.265 pu`, `kiPLL = 2.65 pu/s` (SOURCE_VERBATIM values from
  REGFM_B1 Table 1; CASE_DEFINED/PROJECT_MAPPED application to the GFL).
- `Kps = 1.0`, `Kis = 10.0 s^-1` (ASSUMED_DIAGNOSTIC — Ding Table I lacks;
  a-priori critically-damped rationale; excluded from production acceptance).
- `Pref`, `Qref` per-IBR (CASE_DEFINED, IEEE14 dispatch contract).

### Falsification tests (Phase 5, structural-only)

- `test_gfl_pll_lock`: PLL locks to grid angle at equilibrium.
- `test_gfl_pq_sign`: P/Q sign matches generator convention (S=V·conj(I)).
- `test_gfl_current_into_network`: positive injection.
- `test_gfl_equilibrium_residual`: finite residual at the v3-initialized point.
- `test_gfl_jacobian_fd_agreement`: FD Jacobian finite + well-conditioned.
- Pole oracles: PLL {-11.27,-88.63}@V0=1; power-loop {-10,-10}@V0=1,
  {-8,-10}@V0=0.8, {-10,-12}@V0=1.2.
- `test_gfl_direct_feedthrough`: step Pref → i_d* jumps +Kps·ΔPref;
  step Qref → i_q* jumps -Kps·ΔQref.
- `test_gfl_no_disturbance_ts_holds`: ts_step_kernel direct, max|x(t)-x0|<1e-6.
- Guards: no external solver; nx==6; omega0 multiplier present; Q-sign correct.

**Current integration status:** mixed equilibrium, pure-GFL SG_OFF rejection,
exact equilibrium initialization, and fixed-step SSSA/TS equation sharing are
implemented. The GFL model remains `STRUCTURAL_ONLY` because its RMS reduction
is `PROJECT_DERIVED` and `Kps/Kis` remain `ASSUMED_DIAGNOSTIC`; these results
do not support production readiness.

---

## Item 3 — GFL↔GFM transfer maps + inactive-state rule → PROJECT_DERIVED from continuity + algebraic-residual minimization

> **Current scope:** the fixed-layout transfer/active-state contract below is
> implemented as `PROJECT_DERIVED`, including exact inactive-state holds and
> explicit active-state reduction. A source-verbatim bumpless-transfer proof
> and complete event-driving trip/switch/reclose path remain readiness work.

### 1. Exact equations/values required

Bumpless transfer maps for `gfl→GFM` and `GFM→gfl`:
- VSG internal angle `δVSM` initialized from the GFL PLL angle `δ_pll` at the
  transition instant.
- VSG internal EMF `EVSM` initialized so that terminal-current continuity
  holds: `I_vsg(t+) = I_gfl(t-)`.
- VSG filter states (`Pinv_f, Qinv_f, Vinv_f, Iqinv_f`) initialized from the
  GFL's measured P/Q/V/Iq at the transition.
- GFL PLL angle `δ_pll` initialized from the VSG `δVSM` for the reverse.
- Inactive-state rule: frozen (inactive branch states held at their last
  value, NOT evolved). Documented zero-eigenvalue handling per correction 6.

### 2. Verified source candidates

- **Ding 83340 §IV-B (p.5):** "freeze the integral values in the inner
  loops at the time when the operation mode transition occurs. The frozen
  values will be used as the initial ones when the new operation mode
  starts." — concept only, no equations.
- No other inspected source provides a bumpless transfer map.

### 3. Compatibility + derivation

**PROJECT_DERIVED from three continuity principles:**
1. **State continuity:** the active differential states that have a
   counterpart in the target mode are transferred continuously. For
   `gfl→GFM`: `δ_pll → δVSM`, filtered P/Q/V/Iq map directly.
2. **Terminal-current continuity:** `I_inj(t+) = I_inj(t-)`. This determines
   `EVSM` algebraically: `EVSM∠δVSM = V∠δV + (Re+jXL)·I_inj(t-)` (from
   REGFM_B1 Eq. 13 inverted).
3. **Algebraic-residual minimization:** at the transition, the right-limit
   algebraic residual `g(x, y_right, Y_right)` must be finite (the event
   re-solve in `ts_apply_transition` enforces this).

**Inactive-state rule (frozen):** the inactive branch's states are held at
their last active value (NOT evolved). This avoids inventing a shadow-
controller dynamics equation (UNSOURCED). Per correction 6, the SSSA selector
must handle the resulting zero eigenvalues via explicit active-state
reduction (the selector reduces to the active branch's states only; the
frozen inactive states do not participate in the linearization). This is a
PROJECT_DERIVED contract, not manual zero-eigenvalue deletion.

### 4. Mutually exclusive choices

- (a) Frozen inactive states + continuity-based transfer (SELECTED) —
  sourced concept (Ding), derived equations (continuity), no invented
  dynamics.
- (b) Shadow controller (inactive branch tracks active) — REJECTED
  (UNSOURCED; no equation for the tracking law).
- (c) Cold restart of inactive branch — REJECTED (state discontinuity
  violates the event convention; canonical plan §7.1 forbids cold restart).

### 5. Smallest user decision required

None — (a) is PROJECT_DERIVED with continuity/reset equations written before
the model code (the GFL↔GFM transfer mission, Phases 10-11). Falsification
tests enforce current continuity.

### Falsification tests (GFL↔GFM transfer mission, Phases 10-11)

- `test_transfer_gfl_to_gfm_current_continuity`: `|I_inj(t+) - I_inj(t-)|`
  within algebraic tolerance.
- `test_transfer_gfm_to_gfl_angle_continuity`: `δ_pll(t+) = δVSM(t-)`.
- `test_transfer_residual_finite`: right-limit residual finite.
- `test_inactive_state_frozen`: inactive branch state unchanged across a
  dwell window.
- `test_no_manual_zero_eigenvalue_deletion`: SSSA selector uses active-state
  reduction, not eigenvalue filtering.

---

## Item 4 — Current limiter + anti-windup → G1 IMPLEMENTED / G2 DEFERRED

### 1. Exact equations/values required

- Steady-state PQ priority: `IdmaxSS, IqmaxSS` from `ImaxSS, kf, PQFlag`
  (REGFM_B1 Eqs. 10-11, Fig. 5).
- Transient current limiting: `I∠φ = ImaxF∠φ` when `|I| ≥ ImaxF` (Eq. 13).
- Active-current limit integrator: `δITmax/min` via `kI` integrator (Fig.6,
  Eq. 12).
- Anti-windup: conditional-integration freeze on the voltage PI integral
  `x_Eint` and the active-current integrator `x_Idlim` when their respective
  limits are active.

### 2. Verified source candidates

- **REGFM_B1 90260 Eqs. 10-13, Figs. 5-7:** limiter algorithm SOURCE_VERBATIM.
- **Anti-windup:** NOT in REGFM_B1. Conditional-integration (freeze) is the
  standard textbook anti-windup form.

### 3. Compatibility + derivation

The G1 transient clamp is SOURCE_DEFINED from REGFM_B1. The proposed G2
anti-windup is PROJECT_DERIVED conditional integration, selected because it
requires no unsourced back-calculation gain. It is not implemented in G1 and
cannot support a current-limit or production-readiness claim until G2 supplies
the missing steady-state limiter state and falsification tests.

### 4. Mutually exclusive choices

- (a) Conditional-integration freeze (SELECTED) — simplest, no parameter.
- (b) Back-calculation anti-windup — REJECTED (requires a tracking gain,
  UNSOURCED).

### 5. Smallest user decision required

None.

### Falsification tests (G1 implemented / G2 deferred)

- G1: `test_limiter_transient_cap` and `VPLLfrz` freeze are implemented.
- G2: PQ priority, Fig.6 limiter integration, and anti-windup tests remain
  deferred and cannot support a readiness claim yet.

---

## Item 5 — SG synchronism thresholds → CASE_DEFINED from verified standard ranges

### 1. Exact equations/values required

Synchronism check before SG breaker reclose:
- `ΔV` = voltage magnitude difference (pu)
- `Δf` = frequency/slip difference (pu or Hz)
- `Δθ` = wrapped phase-angle difference (deg or rad)
- Dwell time `T_sync_dwell` (s)
- Timeout `T_sync_timeout` (s)
- Breaker-close-time prediction (optional; defer if not sourceable)

### 2. Verified source candidates

- **2019-5.pdf (IEEE PSRC minutes):** mentions synchronism/out-of-step/
  auto-reclose conceptually (C37.242 PMU sync guide, OOS tripping
  tutorials). No numerical thresholds.
- **IEEE PES TR-121:** NOT locally available. The canonical plan lists it
  but it was unreachable and not cached.
- **Verified standard ranges (utility practice):** ΔV < 5%, Δf < 0.1 Hz,
  Δθ < 10-20 deg are the conventional synchronism-check settings documented
  in protection textbooks (Blackburn, IEEE C37.90/ANSI C50.13 ranges).

### 3. Compatibility + selection

Without TR-121 full text, the thresholds are CASE_DEFINED from verified
standard ranges (the conventional synchronism-check settings). The values
are frozen BEFORE running results (directive 6).

**Selected (CASE_DEFINED, frozen):**
- `ΔV_max = 0.05 pu` (5% magnitude difference)
- `Δf_max = 0.001 pu` (~0.06 Hz on 60 Hz base; conservative)
- `Δθ_max = 10 deg` (conservative within the 10-20 deg range)
- `T_sync_dwell = 0.5 s` (dwell to confirm stable sync)
- `T_sync_timeout = 5.0 s` (after which SG stays disconnected, SYNC_TIMEOUT)
- Breaker-close-time prediction: DEFERRED (not sourceable without TR-121;
  the dwell compensates for close-time uncertainty conservatively).

**Engineering rationale:** these are the conservative end of standard
synchronism-check ranges, chosen a-priori to avoid forced reconnection. They
are CASE_DEFINED (project-design values from verified standard ranges, not
from a single authoritative source). Documented limitation: full TR-121
verification is deferred.

### 4. Mutually exclusive choices

- (a) Conservative standard ranges (SELECTED) — CASE_DEFINED, frozen.
- (b) Wait for TR-121 — REJECTED (user directive: do not stop because a
  benchmark does not prescribe a value; standard ranges suffice).
- (c) Aggressive thresholds — REJECTED (risk of out-of-phase close).

### 5. Smallest user decision required

None — (a) is CASE_DEFINED from verified standard ranges. Documented
limitation: TR-121 full-text verification deferred.

### Falsification tests (Phase 13)

- `test_sync_pass`: within thresholds → reclose permitted.
- `test_sync_fail_voltage`: ΔV > 5% → blocked.
- `test_sync_fail_slip`: Δf > limit → blocked.
- `test_sync_fail_angle`: Δθ > 10 deg → blocked.
- `test_sync_timeout`: dwell never satisfied → SYNC_TIMEOUT, SG stays
  disconnected, no forced state reset.
- `test_no_forced_sg_reset`: SG angle/speed NOT forced to bus.

---

## Item 6 — Delays → CASE_DEFINED from verified standard ranges

### 1. Exact equations/values required

- `T_up = T_detect + T_logic + T_controller` (GFL-to-GFM activation)
- `T_sg_min_off` (minimum SG off-time before reclose eligible)
- `T_settle = ln(1/ρ) / (−Ω_current)` (modal-envelope settle, Ω_current < 0)
- `T_minimum_hold` (minimum hold after SG reclose)
- `T_guard` (guard dwell after T_down)
- `T_lockout` (mode-switch lockout after commit)
- `ρ` (residual fraction for modal envelope)

### 2. Verified source candidates

- `T_settle` formula: PROJECT_DERIVED from modal-envelope analysis
  (`exp(Ω·t) = ρ` → `t = ln(1/ρ)/(−Ω)`). Standard linear-systems theory.
- `T_detect, T_logic, T_controller`: standard protection/controller timing
  ranges (tens of ms to hundreds of ms).
- `T_sg_min_off`: standard breaker reclose dead-time (e.g. ANSI/IEEE
  C37.104 ranges 0.3-300 s depending on application).
- `ρ, T_minimum_hold, T_guard, T_lockout`: project-design values.

### 3. Compatibility + selection

All delays are CASE_DEFINED from verified standard ranges, frozen BEFORE
running results (directive 6).

**Selected (CASE_DEFINED, frozen):**
- `T_detect = 0.05 s` (relay detection, standard)
- `T_logic = 0.02 s` (logic processing, standard)
- `T_controller = 0.05 s` (controller activation, standard for GFM)
- `T_up = 0.12 s` (sum)
- `T_sg_min_off = 0.5 s` (minimum off-time; conservative within C37.104
  ranges for reclose)
- `ρ = 0.05` (5% residual envelope; standard control-systems settling)
- `T_minimum_hold = 1.0 s` (minimum post-reclose hold)
- `T_guard = 0.3 s` (guard dwell after T_down)
- `T_lockout = 2.0 s` (mode-switch lockout; prevents chattering)
- `T_settle` computed at runtime from the SG_ON configuration's dominant
  eigenvalue (if Ω_current ≥ 0, fail closed per canonical plan §9.3).

**Engineering rationale:** each value is at the conservative end of standard
protection/control ranges, chosen a-priori to avoid chattering and premature
reconnection. They are CASE_DEFINED (project-design from verified ranges).
`T_settle` is the only runtime-computed delay (from the SSSA eigenvalue),
which is sourced (linear-systems modal envelope).

### 4. Mutually exclusive choices

- (a) Conservative standard ranges (SELECTED) — CASE_DEFINED, frozen.
- (b) Wait for a specific protection standard — REJECTED (directive: do not
  stop; standard ranges suffice).

### 5. Smallest user decision required

None — (a) is CASE_DEFINED. Documented limitation: specific protection-
standard verification deferred.

### Falsification tests (Phase 13)

- `test_no_early_switch_before_Tup`: GFM not committed before `T_up`.
- `test_tup_components_sum`: `T_up = T_detect + T_logic + T_controller`.
- `test_sg_reclose_after_min_off`: reclose not eligible before `T_sg_min_off`.
- `test_t_settle_formula`: `T_settle = ln(1/ρ)/(−Ω)` verified against an
  analytic eigenvalue oracle.
- `test_t_settle_unstable_fail_closed`: Ω_current ≥ 0 → fail closed.
- `test_lockout_prevents_chatter`: no second switch within `T_lockout`.

---

## Item 8 — Post-trip schedule and balancing-reference contract → CASE_DEFINED / PROJECT_DERIVED

### 1. Case facts and scheduled dispatch

IEEE14 has 259 MW load, pre-trip MATPOWER REF `Pg=232.4 MW`, and 40 MW at
bus 2. The approved Pmax-proportional post-trip schedule is:

- IBR2: 109.7 MW;
- IBR3: 49.8 MW;
- IBR6: 49.8 MW;
- IBR8: 49.8 MW.

These values are `CASE_DEFINED` schedules. Aggregate Pmax headroom establishes
only arithmetic active-power capacity; it does not prove network, voltage,
reactive-power, current, ramp, or energy feasibility.

### 2. Exact selected-GFM and reference contract

- `n_gfm_required` is explicit and may be 1, 2, 3, or larger.
- `selected_gfm_indices` must equal the complete online runtime GFM set.
- Exactly one selected GFM is `reference_resource_index`; every other selected
  member remains a physical GFM.
- Non-reference resources retain their committed modes and scheduled
  active-power inputs.
- Every GFM reactive output is solved by the network and voltage-regulation
  equations.
- The reference GFM `P_ref` is an equilibrium unknown that balances load and
  losses. The result reports scheduled P, solved P, deviation, and Pmax.
- With an online SG, SG `Tm/Efd` are the solved REF controls instead; the
  committed GFM reference becomes active only on the SG_OFF right limit.

Classification: schedules and selected-count mission requirement
`CASE_DEFINED`; coordinate removal, reference-input solution, and atomic
selection validation `PROJECT_DERIVED`.

### 3. Feasibility and failure semantics

Feasibility requires:

- converged project-owned Newton solve;
- every rectangular KCL row retained with residual `<1e-6`;
- reduced Jacobian `rcond>1e-10`;
- exact selected/count/reference validation;
- all currently implemented P/Q/voltage/transient-current checks.

Pmax compliance does not prove `ImaxSS` compliance. Phase-G1 implements only
the sourced transient `ImaxF` clamp; no steady-state-current readiness claim
is allowed before Phase-G2.

Malformed, duplicate, offline, incapable, count-mismatched, order-mismatched,
or out-of-set reference selections fail closed without mutating the original
hybrid state. A nonconvergent or limit-violating physical root is reported as
infeasible; dispatch, gains, tolerances, and solver settings are not adjusted
to force convergence.

### 4. Falsification evidence

- `test_ieee14_multi_gfm_equilibrium`: physical one/two/three-GFM roots,
  noncontiguous selection, non-first reference, all-KCL and Pmax reporting.
- `test_ibr_index_selected_gfm_commit`: exact-size enumeration and atomic
  event commitment/rollback.
- Phase 4/8 gates: SG_ON and SG_OFF physical equilibria, pure-GFL rejection.
- SG_OFF TS/SSSA contract suites: exact `u_eq`, immutable context, active maps,
  all KCL, and no per-step re-slack.

---

## Item 9 — gamma_req → CASE_DEFINED from a-priori eigenvalue-margin study

### 1. Exact equations/values required

`gamma_req > 0` such that a candidate configuration is production-acceptable
only if `Ω_z(m) ≤ -gamma_req` (Ω = non-reference spectral abscissa).

### 2. Verified source candidates

- **Ding 83340 §III-B (Eq. 19):** `Ω_m = max Re(λ_i)` excluding λ_1 (zero,
  reference). States "sufficiently negative" — no normative value.
- **GFL/GFM ratio paper:** PM ≥ 30° (impedance-based, different domain).
- No inspected source gives an eigenvalue-based normative gamma_req.

### 3. Compatibility + derivation

**CASE_DEFINED from an a-priori eigenvalue-margin study.** The study:
- The electromechanical timescale is ~0.5-2 Hz (oscillation period 0.5-2 s).
- A damping ratio ζ ≥ 5% is a standard control-systems stability target.
- For a real eigenvalue σ (Ω), the modal envelope decays as `exp(σ·t)`. For
  ζ=5% on a 1 Hz mode, σ ≈ -2π·1·0.05 ≈ -0.31 rad/s.
- The frozen project minimum is `gamma_req = 0.1 rad/s`. It requires a 0.1/s
  decay rate (envelope half-life about 7 s) but is less stringent than the
  illustrative 0.31/s value; it is not presented as a sourced normative
  margin.

**Engineering rationale:** gamma_req = 0.1 rad/s is a `CASE_DEFINED`, a-priori
project minimum informed by the modal-decay calculation and frozen before
candidate results. The current selector does not claim production evidence
until a real topology/equilibrium/SSSA evaluator supplies it.

### 4. Mutually exclusive choices

- (a) gamma_req = 0.1 rad/s (SELECTED) — CASE_DEFINED and frozen a-priori.
- (b) gamma_req = 0.31 rad/s (illustrative 5% damping at 1 Hz) — not selected;
  it is a different, more stringent project criterion rather than a source
  requirement.
- (c) gamma_req = 0 (just stable) — REJECTED (no margin; fails directive
  "production-required margin").

### 5. Smallest user decision required

None — (a) is CASE_DEFINED from the a-priori study. Documented derivation.

### Falsification tests (Phase 8/10)

- `test_gamma_req_apriori`: gamma_req frozen at 0.1 before candidate
  evaluation.
- `test_selector_rejects_marginal`: a candidate with Ω = -0.05 (> -0.1)
  is rejected (insufficient margin).
- `test_selector_accepts_stable`: a candidate with Ω = -0.2 (< -0.1) is
  accepted.
- `test_selector_fail_closed_all_unstable`: all candidates with Ω ≥ -0.1 →
  fail closed.
- `test_gamma_req_not_tuned`: gamma_req value is NOT changed after viewing
  candidate eigenvalues (grep guard / commit-order check).

---

## Summary: classifications resolved; readiness work remains

| # | Item | Classification | Value/Source |
|---|------|---------------|--------------|
| 7 | IEEE14 SG dynamics | CASE_DEFINED | Kodsi 60Hz Table A.2 (base-converted) |
| 1 | GFL model | PROJECT_DERIVED | Reduction from Ding EMT (phasor-compatible) |
| 3 | GFL↔VSG transfer | PROJECT_DERIVED | Continuity + algebraic-residual minimization |
| 4 | Current limiter + anti-windup | G1 SOURCE_DEFINED + PROJECT_DERIVED implemented; G2 deferred | Eq.13 clamp + VPLL freeze implemented; PQ priority/Fig.6/Eqs.10-11/anti-windup not ready |
| 5 | SG synchronism | CASE_DEFINED | Frozen project thresholds; not SOURCE_DEFINED IEEE-TR-121 values |
| 6 | Delays | CASE_DEFINED + PROJECT_DERIVED | Frozen project delays and modal-settling relation; integrated timing deferred |
| 8 | Post-trip dispatch/reference | CASE_DEFINED + PROJECT_DERIVED | Pmax-proportional schedules; one reference P solved; all-KCL structural feasibility verified |
| 9 | gamma_req | CASE_DEFINED | 0.1 s^-1 frozen a-priori; real candidate evidence deferred |

The GFM slice uses SOURCE_DEFINED/CASE_DEFINED/PROJECT_DERIVED values, but the
GFL `Kps/Kis` remain `ASSUMED_DIAGNOSTIC` and are excluded from production
acceptance. No readiness statement may erase that limitation.

**No value may change after viewing outcomes.** All values are frozen in
this ledger BEFORE Phase 4-17 implementation. The decision ledger is the
frozen contract; any change requires re-approval.

## What proceeds next after the corrective checkpoint

Mixed equilibrium, fixed-step equation sharing, and structural index-selected
event primitives are implemented. Next work is Phase-G2, integrated
topology/equilibrium/SSSA selection evidence, event-driving adaptive TS with
right-limit rollback, source closure for GFL gains, and independent validation.
Readiness remains NOT_READY until those gates pass.
