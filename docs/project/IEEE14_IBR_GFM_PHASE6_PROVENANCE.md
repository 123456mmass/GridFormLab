# IEEE14 IBR GFM Phase 6 Provenance (REGFM_B1 VSM)

## Source material

| Document | Path | SHA-256 |
|----------|------|---------|
| REGFM_B1 spec (NREL/TP-5D00-90260, UNIFI-2024-6-1, June 2024) | `docs/paper/90260.pdf` | `de52a0b7c8beec6d16d8e10b53a565d902ab1a79ef093ba3d6d80260a9287d50` |

**Path note:** Phase 5 handoff/provenance cited `docs/text/90260.pdf` (absent). The
canonical committed file is `docs/paper/90260.pdf`. This doc corrects the path.

## State vector (11, fixed order)

| # | Name | Unit | Source | Meaning |
|---|------|------|--------|---------|
| 1 | `omega_m` | pu | SOURCE_TRANSFORMED (Fig.2) | VSM speed deviation (inv base) |
| 2 | `delta_VSM` | rad | SOURCE_TRANSFORMED (Fig.2) | VSM angle |
| 3 | `x_washout` | pu | SOURCE_VERBATIM (Fig.2 D2·s/(s+ωD)) | transient damping washout |
| 4 | `x_Eint` | pu·s | SOURCE_TRANSFORMED (Fig.3) | voltage PI integral |
| 5 | `delta_PLL` | rad | SOURCE_VERBATIM (Fig.4) | PLL angle |
| 6 | `x_PLL_int` | pu·s | SOURCE_VERBATIM (Fig.4) | PLL PI integrator |
| 7 | `Pinv_f` | pu | SOURCE_VERBATIM (Eq.1) | filtered active power (inv base) |
| 8 | `Idinv_f` | pu | SOURCE_VERBATIM (Eq.2) | filtered active current (inv base) |
| 9 | `Qinv_f` | pu | SOURCE_VERBATIM (Eq.3) | filtered reactive power (inv base) |
| 10 | `Vinv_f` | pu | SOURCE_VERBATIM (Eq.4) | filtered voltage |
| 11 | `Iqinv_f` | pu | SOURCE_VERBATIM (Eq.5) | filtered reactive current (inv base) |

## Inputs (nu=2): `u = [P_ref; V_ref]` (pu, system base) — SOURCE_TRANSFORMED/PROJECT_MAPPED

## Per-unit base contract (user-confirmed, FROZEN before results)
- External ABI: `u(1)=P_ref` on SYSTEM base (Sbase=100 MVA).
- Internal REGFM: `kappa = Sbase/Mbase`; `P_ref_inv = kappa*P_ref_sys`.
- Swing + filters run on INVERTER base (REGFM_B1 Eq.1 semantics).
- `current_injection` and reconstructed P/Q return on SYSTEM base (composite KCL).
- NO double conversion: P_ref converted once at the boundary.
- Mbase = CASE_DEFINED unity-PF nameplate proxy (NOT Pmax-MW proven):
  IBR2=140, IBR3=100, IBR6=100, IBR8=100 MVA.

## Governing equations (frozen)

Filters (Eqs.1-5), `kappa=Sbase/Mbase`:
- `Tpf·dPinv_f/dt = kappa·P_meas - Pinv_f` (Eq.1)
- `TIf·dIdinv_f/dt = kappa·Id - Idinv_f` (Eq.2)
- `TQf·dQinv_f/dt = kappa·Q_meas - Qinv_f` (Eq.3)
- `TVf·dVinv_f/dt = |V| - Vinv_f` (Eq.4)
- `TIf·dIqinv_f/dt = kappa·Iq - Iqinv_f` (Eq.5)

dq (Eqs.6-9, via δPLL); `P_meas=Re(V·conj(I))`, `Q_meas=Im(V·conj(I))` (system base).

PLL (Fig.4; ΔωPLL limits + freeze deferred):
- `dx_PLL_int/dt = Vq`
- `dδPLL/dt = ω0·(kpPLL·Vq + kiPLL·x_PLL_int)`

VSM swing (Fig.2, SOURCE_TRANSFORMED, FROZEN under flag profile ωFlag=0, FFlag=1, ωref=1 pu; inverter base):
- `2H·dωm/dt = P_ref_inv - Pinv_f - (1/mp + D1)·ωm - D2·(ωm - x_washout)`
- `dx_washout/dt = ωD·(ωm - x_washout)`
- `dδVSM/dt = ω0·ωm`

Steady state: `ωm = (P_ref_inv - Pinv_f)/(1/mp + D1)`; with D1=0 → `ωm = mp·(P_ref_inv - Pinv_f)` = P-f droop.

Voltage PI (Fig.3; Emax/Emin deferred):
- `dx_Eint/dt = V_ref - Vinv_f`
- `EVSM = V_ref - mq·Qinv_f + kpv·(V_ref - Vinv_f) + kiv·x_Eint`

Output (Eq.13 linear branch; ImaxF piecewise clamp deferred):
- `I = (EVSM·exp(j·δVSM) - V_bus)/(Re + j·XL)` (positive INTO network, system base)

`electrical_power`: `Pe = Re(V_bus·conj(I))` (S=V·conj(I), generator convention).

## Parameter table (REGFM_B1 Table 1 example = CASE_DEFINED)
ω0=376.99, H=0.5, D1=0, D2=100, ωD=50, mp=0.02, mq=0.05, kpv=0, kiv=5, Re=0, XL=0.1,
kpPLL=0.265, kiPLL=2.65, Tpf=TQf=TVf=TIf=0.02, ImaxSS=1.0, ImaxF=1.5, kf=0.9, kI=2,
Ke=1, VPLLfrz=0.05, Δωmax/min=±0.05, ΔωPLLmax/min=±0.2. All SOURCE_VERBATIM from Table 1.
Mbase=CASE_DEFINED nameplate proxy. **NO ASSUMED_DIAGNOSTIC** (unlike GFL Kps/Kis).

## Frozen flag profile (before results)
ωFlag=0, FFlag=1, ωref=1 pu, VdrpFlag=0, QVFlag=1, PQFlag=1, ESFlag=1.

## Limiter-disabled structural slice (deferred to Phase 14)
Δω limits, ΔωPLL limits, Emax/Emin, δmax (Eq.12), ImaxF piecewise clamp (Eq.13 branch 2),
active-current limiter (Fig.6, delta_IT), PLL freeze (VPLLfrz).

## Initialization (PROJECT_DERIVED, warm-start; Newton refines)
ωm0=0, x_washout0=0, δVSM0=angle(V0), x_Eint0=0, δPLL0=angle(V0), x_PLL_int0=0,
Pinv_f0=κ·P_ref_sys (inv base), Qinv_f0=0, Vinv_f0=|V0|, Idinv_f0/Iqinv_f0=0.

## Tests (`tests/test_ibr_regfm_b1_vsg_model.m`, 18 tests, oracles declared before results)
- state_count, pq_sign, current_into_network, equilibrium_residual (<1e-6)
- jacobian_fd_agreement (coupled (x,y) Jacobian; Jxx structurally rank-deficient at
  equilibrium because Pinv_f/Idinv_f and Qinv_f/Iqinv_f share TIf and are driven by
  the same Id/Iq at constant V — the coupled Jacobian is full-rank)
- pll_poles {-11.27,-88.63}, vsm_poles (stable, Re<0)
- no_external_solver (grep), provenance_complete (NO ASSUMED_DIAGNOSTIC, Mbase=CASE_DEFINED)
- source_guards (omega0 multiplier, Eq.13 form, 1/mp droop, kappa boundary)
- fail_closed_v0/bus_mapping/params/u
- numerical_linearization (FD eigenvalues vs analytic, AbsTol 5e-2)
- mbase_validation (kappa=Sbase/Mbase, P_ref_inv=kappa·P_ref)
- kappa_neq1_equilibrium (IBR2 κ=100/140 AND IBR3/6/8 κ=1 both give ωm=0, P_sys=P_ref_sys)
- flag_profile_frozen (grep guard)

Predeclared tolerances: residual 1e-6, FD Richardson 1e-4, poles RelTol 1e-3,
linearization AbsTol 5e-2, rcond 1e-10.

## STATUS
`IEEE14_IBR_GFM_MODEL_READY = STRUCTURAL_ONLY`. No catalog/runtime registration, no
production-readiness claim. Limiters/FRT deferred (Phase 14). TS integration deferred.
`IBR_PRODUCTION_INTEGRATION_READY` stays NOT_READY.

## Equation → source → code → test mapping
| Equation | Source | Code (`+ibr/regfm_b1_vsg_model.m`) | Test |
|----------|--------|-----------------------------------|------|
| Eq.1 (Pinv filter) | 90260 p.1 | `gfm_f` dPinv_f | equilibrium_residual, kappa_neq1 |
| Eq.2 (Idinv filter) | 90260 p.1 | `gfm_f` dIdinv_f | equilibrium_residual |
| Eq.3 (Qinv filter) | 90260 p.2 | `gfm_f` dQinv_f | equilibrium_residual |
| Eq.4 (Vinv filter) | 90260 p.2 | `gfm_f` dVinv_f | equilibrium_residual |
| Eq.5 (Iqinv filter) | 90260 p.2 | `gfm_f` dIqinv_f | equilibrium_residual |
| Eq.6-9 (dq) | 90260 p.2 | `gfm_f` Id/Iq/Vq | numerical_linearization |
| Fig.2 (VSM swing) | 90260 p.1 | `gfm_f` dωm/dx_washout/dδVSM | vsm_poles, source_guards |
| Fig.3 (voltage PI) | 90260 p.2 | `gfm_f` dx_Eint, EVSM | equilibrium_residual |
| Fig.4 (PLL) | 90260 p.2 | `gfm_f` dx_PLL_int/dδPLL | pll_poles |
| Eq.13 (output) | 90260 p.4 | `gfm_current_injection` | current_into_network, source_guards |
| Table 1 (params) | 90260 p.5 | parameter block | provenance_complete |
