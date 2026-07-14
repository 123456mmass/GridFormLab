# IEEE14 IBR Phase 6–9 Fast-Track Handoff

**Date:** 2026-07-14
**Agent:** A (sole implementation owner on `main`)
**Base:** 710950c (Phase 5 GFL STRUCTURAL_ONLY checkpoint)
**Head:** (after F1–F5 commits)
**Status:** Phase 6–8 complete; full regression 616/616 passed; 0 failed; 0 incomplete.

## What was delivered

A real IBR vertical slice `sourced equations → real GFM device → composite → mixed
equilibrium`, where GFL and GFM use real `+ibr` models (not the synthetic Phase 4
fixture), state dimension is constant across gfl/GFM/tripped, and IEEE14 SG_ON and
SG_OFF+GFM equilibria converge.

### F1 — REGFM_B1 GFM/VSG model (`+ibr/regfm_b1_vsg_model.m`)
- 11-state VSM grid-forming inverter derived from REGFM_B1 NREL/TP-5D00-90260
  (`docs/paper/90260.pdf`, SHA-256 verified).
- Voltage-source-behind-impedance output (Eq.13 linear branch), VSM swing (Fig.2
  SOURCE_TRANSFORMED, frozen under ωFlag=0/FFlag=1/ωref=1), measurement filters
  (Eqs.1-5), voltage PI (Fig.3), PLL (Fig.4). STRUCTURAL_ONLY: limiters/FRT deferred.
- Per-unit base contract (user-confirmed, FROZEN): external ABI on system base;
  internal swing/filters on inverter base (kappa=Sbase/Mbase); P_ref_inv=kappa·P_ref_sys
  (no double conversion); current injection returns on system base. Mbase=CASE_DEFINED
  unity-PF nameplate proxy. All params SOURCE_VERBATIM from Table 1; NO ASSUMED_DIAGNOSTIC.
- Tests: 18/18 pass (equilibrium, κ≠1 falsification, poles, source guards, fail-closed).

### F2 — Dual-mode fixed-layout device (`+ibr/dual_mode_ibr_model.m`)
- 15-state CONSTANT-dimension superset across 'gfl'|'GFM'|'tripped'.
- Reuses GFL (Phase 5) + GFM (Phase 6) as single source of truth (no equation duplication).
- Inactive branches decay-to-warmstart (lambda=1e-3 NUMERICAL_METHOD) to keep the coupled
  Newton Jacobian full-rank while holding inactive states at warm-start.
- Tests: 9/9 pass.

### F3 — IEEE14 real-device builder (`+ibr/build_ieee14_ibr_devices.m`)
- Builds IBR2@2, IBR3@3, IBR6@6, IBR8@8 using dual_mode_ibr_model with PF warm-start V0
  per bus (in-house Newton) and CASE_DEFINED Mbase (IBR2=140, IBR3/6/8=100 MVA).
- SG1 (bus 1) is NOT a device (slack via PF). No synthetic fixture, no auto-discovery.
- Tests: 6/6 pass (SG_ON + SG_OFF+GFM equilibria converge; pure-GFL SG_OFF fails closed).

### F4 — Contract doc updates
- `IEEE14_IBR_EQUATION_SOURCE_MATRIX.md`: Item 2 CLOSED (0/9 → 1/9 source-closed).
- `IEEE14_IBR_FROZEN_CONTRACT.md`: GFM section + dual-mode section updated.
- `IEEE14_IBR_GFM_PHASE6_PROVENANCE.md`: full equation→source→code→test mapping; fixes
  docs/text→docs/paper path discrepancy from Phase 5.

### F5 — Full regression
- 616/616 passed, 0 failed, 0 incomplete.

## Test evidence

| Suite | Passed | Failed | Incomplete |
|-------|--------|--------|------------|
| test_ibr_regfm_b1_vsg_model | 18 | 0 | 0 |
| test_ibr_dual_mode_model | 9 | 0 | 0 |
| test_ieee14_1sg_4ibr_phase8_real | 6 | 0 | 0 |
| Full regression (all tests) | 616 | 0 | 0 |

**MATLAB R2026a path note:** batch-mode `runtests` requires `path(path,pwd); pf_init_paths;
rehash; clear functions; clear classes; rehash; rehash path; rehash toolbox` BEFORE
runtests. Without `pf_init_paths` before `clear`, `pf_build_b_matrices` (in `internal/core/`)
does not resolve, causing spurious PF/BFS/routing failures. This is a MATLAB R2026a
path-cache quirk, NOT a regression. The test files' `setupOnce` calls
`addpath(...); pf_init_paths();` which handles the interactive case.

## Acceptance criteria (vs fast-track gates)

- ✅ GFL/GFM use real +ibr models (not synthetic) in Phase 8 tests
- ✅ State dimension constant (15) across gfl/GFM/tripped
- ✅ Current injection sign/base/frame tests pass
- ✅ Single-device GFM equilibrium passes (residual<1e-6)
- ✅ IEEE14 SG_ON real-device equilibrium passes
- ✅ IEEE14 SG_OFF has ≥1 GFM and equilibrium passes
- ✅ Pure-GFL SG_OFF fails closed (`noVoltageFormingSource`)
- ✅ No-external-solver scanner passes (word-boundary grep avoids `pfsolver` false positive)
- ✅ Legacy tests don't regress (616/616)
- ✅ Full regression 0 failed; 0 incomplete
- ✅ κ≠1 tests pass, no double conversion
- ✅ Readiness claim separated: STRUCTURAL_ONLY; IBR_PRODUCTION_INTEGRATION_READY = NOT_READY

## Key technical decisions (frozen before results)

1. **VSM swing ODE (Fig.2 SOURCE_TRANSFORMED):** `2H·dωm/dt = P_ref_inv − Pinv_f −
   (1/mp+D1)·ωm − D2·(ωm − x_washout)`; steady state ωm = mp·(P_ref_inv − Pinv_f) = P-f
   droop. Frozen under flag profile ωFlag=0, FFlag=1, ωref=1 pu.
2. **Per-unit base contract:** external=system base; internal swing/filters=inverter base
   (kappa=Sbase/Mbase); no double conversion.
3. **Mbase:** CASE_DEFINED unity-PF nameplate proxy (IBR2=140, IBR3/6/8=100 MVA; NOT
   Pmax-MW proven).
4. **Inactive-state rule (interim):** decay-to-warmstart (lambda=1e-3) to keep Newton
   Jacobian full-rank. Full bumpless transfer deferred to Phase 10-11 (item 3 STOP).

## What is NOT done (deferred)

- TS integration (composite_dae not wired to ts_simulate/ts_step_kernel).
- Limiters/FRT (Phase 14): Δω/ΔωPLL limits, Emax/Emin, δmax, ImaxF piecewise clamp,
  active-current limiter (Fig.6), PLL freeze (VPLLfrz).
- Full bumpless GFL↔GFM transfer (Phase 10-11; item 3 UNSOURCED STOP).
- SSSA dispatch to composite_dae.
- `IBR_PRODUCTION_INTEGRATION_READY` stays NOT_READY.

## Commit sequence

- F1 (`44556b0`): GFM model + tests + provenance
- F2 (`98773ef`): dual-mode fixed-layout device + tests
- F3 (`31f819e`): dual-mode decay-to-warmstart rev + IEEE14 real-device builder
- F4 (`6c35c89`): contract doc updates
- F5: this handoff

## Source-cited equation provenance

All GFM equations sourced from REGFM_B1 NREL/TP-5D00-90260 (Eqs.1-13, Table 1, Figs.2-7).
See `docs/project/IEEE14_IBR_GFM_PHASE6_PROVENANCE.md` for the full
equation→source→code→test mapping.
