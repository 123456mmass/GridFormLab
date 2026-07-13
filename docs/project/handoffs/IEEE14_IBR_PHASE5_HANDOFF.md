# IEEE14 1-SG + 4-IBR Mission — Phase 5 Handoff (STRUCTURAL_ONLY)

**Status:** `IEEE14_IBR_GFL_MODEL_READY` = STRUCTURAL_ONLY.
`IBR_PRODUCTION_INTEGRATION_READY` = NOT_READY.
**Branch:** `main`. **Date:** 2026-07-14.
**Base:** `652eaa0` (Phase 0–4 merged). **Phase 5 HEAD:** `d811c30`
(includes round-1 corrective patch `321d98c` + round-2 corrective patch
`d811c30`).

## What was completed

Phase 5 — sourced GFL (grid-following) inverter model, structural-only. The
first production IBR device of the mission, conforming to the `composite_dae`
ABI (R3 Rev 2, frozen) and consumed by `mixed_equilibrium_solve` via
`config.devices` (the mixed-equilibrium gate itself is deferred to Phase 9).

### Commits

| Commit | Content |
|--------|---------|
| `9abb5d7` | Phase 5 (1/2): GFL provenance + frozen-contract doc revisions |
| `41085f6` | Phase 5 (2/2): GFL model + structural tests |
| `60d8337` | Phase 5 handoff |
| `321d98c` | Phase 5 corrective patch (round 1): complex V0, fail-closed u, bus mapping, param provenance |
| `75a06b9` | Phase 5 handoff: record round-1 corrective patch + fresh test counts |
| `d811c30` | Phase 5 corrective patch (round 2): oversized-u, ref validation, integer bus_position, doc consistency |

### Files

- `+ibr/gfl_model.m` (new) — production GFL device factory.
- `tests/test_ibr_gfl_model.m` (new) — 16 structural tests.
- `docs/project/IEEE14_IBR_GFL_PHASE5_PROVENANCE.md` (new) — equation→source map.
- `docs/project/IEEE14_IBR_FROZEN_CONTRACT.md` (revised) — GFL item closed at 6 states.
- `docs/project/IEEE14_IBR_DECISION_LEDGER.md` (revised) — Item 1 updated.

No `+stability/**` edits. No `+cases/case_ieee14_1sg_4ibr_auto_vsg.m` edits.
No synthetic-fixture edits. No PDF commit (URL+SHA-256 in provenance).

## Model summary

Reduced positive-sequence RMS GFL (PROJECT_DERIVED reduction from Ding
NREL/CP-6A40-83340 Sec II-B Eqs.7-10). 6 states:
`x_gfl = [delta_pll, eps_pll, P_f, Q_f, phi_P, phi_Q]^T`. Inputs `u=[Pref;Qref]`
(nu=2). System base only (no Mbase factor).

Governing equations (frozen, see provenance doc):
```
d(eps_pll)/dt   = Vq_pll
d(delta_pll)/dt = omega0*(kpPLL*Vq_pll + kiPLL*eps_pll)   % omega0 PRESENT
d(P_f)/dt = omega_c*(Pinv_meas - P_f);  d(Q_f)/dt = omega_c*(Qinv_meas - Q_f)
d(phi_P)/dt = +(Pref - P_f);  d(phi_Q)/dt = +(Qref - Q_f)
i_d* = +Kps*(Pref - P_f) + Kis*phi_P
i_q* = -Kps*(Qref - Q_f) - Kis*phi_Q        % Q-sign corrected
I_gfl = (i_d* + j*i_q*)*exp(j*delta_pll)     % positive INTO network
```

Equilibrium init: `phi_P0 = Pref/(V0*Kis)`, `phi_Q0 = Qref/(V0*Kis)`,
`i_d*0 = Pref/V0`, `i_q*0 = -Qref/V0`.

## Parameter freeze (all frozen BEFORE results)

| Param | Value | Classification |
|------|-------|----------------|
| omega0 | 376.99 rad/s | SOURCE_VERBATIM (REGFM_B1 Table 1) |
| omega_c | 10 rad/s | SOURCE_VERBATIM (Ding Table I) |
| kpPLL | 0.265 pu | SOURCE_VERBATIM value / CASE_DEFINED+PROJECT_MAPPED application |
| kiPLL | 2.65 pu/s | SOURCE_VERBATIM value / CASE_DEFINED+PROJECT_MAPPED application |
| Kps | 1.0 | ASSUMED_DIAGNOSTIC |
| Kis | 10.0 s^-1 | ASSUMED_DIAGNOSTIC |

No ASSUMED_DIAGNOSTIC value enters production acceptance.

## Fresh verification evidence (MATLAB R2025a, this host, after corrective patch)

```matlab
restoredefaultpath; cd('C:\Users\User\Desktop\Power-flow'); pf_init_paths;
runtests('tests/test_ibr_gfl_model.m');              % 21 passed / 0 failed / 0 incomplete
runtests('tests','IncludeSubfolders',true);         % 579 passed / 0 failed / 4 incomplete
runtests('tests/test_no_external_solver_dependency.m'); % 12 passed / 0 failed
```

- Phase 5 suite: **21 passed / 0 failed / 0 incomplete** (was 16 before the
  corrective patch; +5 new falsification tests T17-T21).
- Full regression: **579 passed / 0 failed / 4 incomplete**.
  - The 4 incomplete are `test_pgaz_conversion_contract` sub-tests, filtered
    by assumption because **PSAT is not installed on this host** (verified:
    `psat_version` unrecognized). Environment limitation, NOT a regression.
- External-solver guard: **12 passed / 0 failed**.
- `+stability/**` unchanged (verified: `git diff --name-only 60d8337..HEAD -- +stability/` empty).
- Frozen gains unchanged (grep guard: omega0=376.99..., omega_c=10, kpPLL=0.265,
  kiPLL=2.65, Kps=1.0, Kis=10.0 in `gfl_model.m` defaults).

### Pole oracles (predeclared, frozen BEFORE results, all PASS)

- PLL @ V0=1: {-11.27, -88.63} s^-1 (rel-tol 1e-3).
- Power-loop @ V0=1: {-10, -10} (critically damped).
- Power-loop @ V0=0.8: {-8, -10}.
- Power-loop @ V0=1.2: {-10, -12}.
- Direct feedthrough: Pref step → i_d* jumps +Kps·ΔPref; Qref step → i_q* jumps -Kps·ΔQref.

## Honest limitations (structural-only)

1. **Kps/Kis are ASSUMED_DIAGNOSTIC** — excluded from production acceptance.
   Production readiness requires source-closing these gains in a separate task.
2. **kpPLL/kiPLL are SOURCE_VERBATIM values from REGFM_B1** but their application
   to the Ding-derived GFL is CASE_DEFINED/PROJECT_MAPPED, not SOURCE_VERBATIM GFL.
3. **No catalog/runtime registration** — the GFL device is built by `ibr.gfl_model`
   but not registered in any dispatcher or auto-discovery path.
4. **The RMS/PCC reduction (ideal inner loop, LCL elimination) is PROJECT_DERIVED**
   (unsourced verbatim); not claimed source-closed.
5. **Mixed-equilibrium / pure-GFL-island-via-solver / SSSA-sharing gates deferred
   to Phase 9** — `mixed_equilibrium_solve` still passes empty `u` in some code
   paths, which would break the nu=2 contract. Phase 5 uses `ts_step_kernel`
   directly and a standalone coupled-Newton solve (built in-test). No
   `+stability/**` edits this round.
6. **REGFM_B1 PLL output limits and low-voltage freeze deferred to Phase 14** (FRT).
7. **PSAT not installed on this host** — 4 pgaz tests skip (environment, not regression).

## Source material

Primary-source PDFs (NREL 83340 Ding, NREL 90260 REGFM_B1, IEEE 1110-2002) are
at `docs/text/` (local, NOT committed per v3 scope). SHA-256 verified against
the Equation Source Matrix:
- `83340.pdf` = `2aeded37...5d50a995727` ✓
- `90260.pdf` = `de52a0b7...8a9287d50` ✓
- `1110-2002.pdf` = `90ee662b...` (DIFFERENT hash from matrix's `2eb08ed8...` —
  different file version; flagged for SG-model work in later phases; NOT used in Phase 5).

URLs + verified SHA-256 are recorded in `IEEE14_IBR_GFL_PHASE5_PROVENANCE.md`.

## Reviewer protocol

Agent B and Codex are read-only reviewers. They should review the committed
diff (`9abb5d7` + `41085f6`) against:
- the frozen contracts (Decision Ledger Item 1, Frozen Contract GFL item);
- the provenance doc equation→source map;
- the v3 plan amendments (Q-sign, system base, bus_position+V0 constructor,
  mixed-equilibrium gate deferred to Phase 9, no `+stability/**` edits).

## Round-2 corrective patch (commit `d811c30`)

A second independent re-review surfaced 4 residual findings (2 High, 2
Medium). Compact REVISE_MINIMAL patch — no model rebuild, no
gain/tolerance/equation change:

1. **F1 (High) — oversized `u_dev`:** `refs_from_u` now requires
   `numel(u_dev)==2` exactly (was `<2`, which silently truncated 3+ element
   inputs). Oversized → `:badInput`.
2. **F2 (Medium) — non-finite refs:** constructor validates `P_ref_pu`/
   `Q_ref_pu` finite before `x0`/`u0` assembly (was silently accepting
   NaN/Inf). Non-finite → `:badRef`.
3. **F3 (Medium) — fractional `bus_position`:** constructor requires a finite
   integer (was falling through to `MATLAB:badsubscript`). Fractional →
   `:busMappingMismatch`.
4. **F4 (High doc contract):** Source Matrix, Frozen Contract, Decision
   Ledger were internally inconsistent on Phase 5/6 status. Item 1 detail →
   STRUCTURAL_ONLY (was DECISION_REQUIRED/PARTIAL); Phase 6 relabeled
   "GFM/VSG model" (was "dual-mode transfer"); GFL↔GFM transfer (item 3)
   scoped to Phases 10-11, NOT Phase 6.

Extended T18/T19/T20 (no new test functions; count stays 21).

### Fresh verification evidence (MATLAB R2025a, after round-2 patch)

```matlab
restoredefaultpath; cd('C:\Users\User\Desktop\Power-flow'); pf_init_paths;
runtests('tests/test_ibr_gfl_model.m');              % 21 passed / 0 failed / 0 incomplete
runtests('tests','IncludeSubfolders',true);         % 579 passed / 0 failed / 4 incomplete
runtests('tests/test_no_external_solver_dependency.m'); % 12 passed / 0 failed
```

- Phase 5 suite: **21 passed / 0 failed / 0 incomplete**.
- Full regression: **579 passed / 0 failed / 4 incomplete** (PSAT not
  installed; environment, not regression).
- External-solver guard: **12 passed / 0 failed**.
- `+stability/**` unchanged (`git diff --name-only 75a06b9..d811c30 -- +stability/` empty).
- Frozen gains unchanged (grep guard: omega0=376.99..., omega_c=10, kpPLL=0.265,
  kiPLL=2.65, Kps=1.0, Kis=10.0 in `gfl_model.m` defaults).
- `git diff --check` clean.
- Probe re-run: oversized u → `:badInput`; NaN/Inf refs → `:badRef`;
  fractional bus_position → `:busMappingMismatch` (all 3 findings closed).

The 6-state structure, equations, and frozen gains are unchanged. The
round-2 patch is additive on top of the round-1 corrective patch (`321d98c`).

## Next phase

**Phase 6 — REGFM_B1-derived GFM/VSG model.** Build the GFM device
(`+ibr/regfm_b1_vsg_model.m`) from REGFM_B1 90260 (voltage-source-behind-
impedance Eq.13, VSM swing block Fig.2, measurement filters Eqs.1-5, Q-V droop
+ voltage PI Fig.3). The GFM is the voltage-forming source required for SG_OFF
equilibria. It will share the composite_dae ABI and the system-base conventions
established in Phase 5. Phase 7 will construct the fixed dual-mode superset
layout (GFL+GFM in one device) separately — it must not force unsourced GFL
dynamics into the Phase 5 GFL.

Before Phase 6: inspect current `main` (`d811c30`), trace the REGFM_B1 source
equations from `docs/text/90260.pdf`, freeze the GFM state vector + parameter
table, declare acceptance criteria before results, and obtain user approval.
