# IEEE14 1-SG + 4-IBR Mission — Phase 1 Source-Gate BLOCKED

**Status:** `IEEE14_IBR_EQUATION_CONTRACT_READY` = `NOT_READY`;
`IBR_PRODUCTION_INTEGRATION_READY` = `NOT_STARTED`.

**Branch:** `feature/ieee14-auto-vsg-switching`
**Worktree:** `/home/birds/Documents/Power-flow-ieee14-ibr`
**Base:** immutable Track A commit `31a211d` (origin/main `f59076f`, 16 ahead)
**HEAD after this handoff:** `e37a147` (C0 canonical plan/prompt checkpoint)
**Date:** 2026-07-13

## What was authorized and attempted

Full unattended Phase 0–17 execution was authorized with:
- `PHASES_0_TO_17 = AUTHORIZED`
- `MANDATORY_PHASE_1_USER_PAUSE = REMOVED`
- `SOURCE_AND_NUMERICAL_STOP_GATES = RETAINED`
- `ASSUMED_DIAGNOSTIC_PRODUCTION_VALUES = FORBIDDEN`
- `PUSH_OR_MERGE = FORBIDDEN`

Phase 0 completed cleanly (see below). Phase 1 (source audit + mathematical
contract freeze) hit a genuine, unavoidable source-gate blocker and STOPPED
per the retained stop conditions. No production model code was written.

## Phase 0 — COMPLETED (e37a147)

1. Read-only audit recorded: `origin/main` = `main` = `f59076f`; Track A
   `31a211d` 16 ahead / 0 behind; merge-base `f59076f`; no race; no branch
   `feature/ieee14-auto-vsg-switching`; no path
   `/home/birds/Documents/Power-flow-ieee14-ibr`; stash `eae0bcd` intact.
2. Created worktree `feature/ieee14-auto-vsg-switching` at
   `/home/birds/Documents/Power-flow-ieee14-ibr` from immutable `31a211d`.
3. Copied the two canonical planning files (hash-verified):
   - `docs/project/plans/IEEE14_1SG_4IBR_AUTO_VSG_SWITCHING_PLAN.md`
     SHA-256 `8823738a67b58b45833af8911d536d161d29a9f6b73e12d14df0807e4756b81e`
   - `docs/project/plans/CLAUDE_PROMPT_IEEE14_AUTO_VSG_SWITCHING.md`
     SHA-256 `87a2bac0dce72fdedcf3f73ab04ee29adcd9dac2920be9bba720561c560de1f7`
4. Committed C0 `e37a147` (canonical plan/prompt checkpoint, 1534 insertions).
5. Fresh Track A baseline regression: **454 / 454 / 0 / 0** (passed/failed/
   incomplete; MATLAB via `pf_init_paths; runtests('tests','IncludeSubfolders',true)`).
6. No user work disturbed; no push/merge/history rewrite.

## Phase 1 — BLOCKED at source-gate (genuine stop condition)

### Root cause: required primary sources are unreachable

The host has NO outbound network access. Verified three independent ways:

1. `curl -sSL https://www.nrel.gov/docs/fy24osti/90260.pdf` →
   `curl: (6) Could not resolve host: www.nrel.gov` (DNS resolution fails).
   Same for all NREL/WECC/IEEE URLs. Persists with `dangerouslyDisableSandbox`.
2. `WebFetch` tool → `PROXY_REJECTED (HTTP 502)` for both the PDF and the
   HTML landing page.
3. Wide filesystem search for cached copies found NONE of the required
   primary sources (only the Padiyar textbook, a Kundur cross-validation
   report, and `/tmp/synchronverters.pdf` = Zhong & Weiss 2011).

### Primary sources required by Phase 1 but UNREACHABLE

| # | Required source | URL | Local cache | Phase-1 role |
|---|-----------------|-----|-------------|--------------|
| 1 | UNIFI/WECC REGFM_B1 VSM GFM spec | https://www.nrel.gov/docs/fy24osti/90260.pdf | NONE | VSG/VSM model profile, voltage-source-behind-impedance, VSM control block, measurement filters, voltage control, current limiting |
| 2 | Ding et al., dynamically configurable GFM/GFL | https://www.nrel.gov/docs/fy23osti/83340.pdf | NONE | GFL positive-sequence model, GFL↔GFM transition concept, spectral-abscissa margin, frozen integral-state transfer |
| 3 | WECC generic renewable models (REGC/REEC/REPC) | https://www.wecc.org/.../Summary%20of%202nd%20Generation%20Generic%20RES%20Models%20%20Rev5.pdf | NONE | REGC current-source converter-interface role, REEC electrical controls, REPC plant-level control |
| 4 | IEEE PES TR-121 generator synchronizing practices | https://resourcecenter.ieee.org/.../pes_tp_tr121_psrc_42924 | NONE | SG synchronism check thresholds (ΔV, Δf/slip, Δθ), dwell, timeout, breaker-close-time prediction |
| 5 | NREL GFM dispatch (grid-connected/islanded) | https://www.nrel.gov/docs/fy24osti/87959.pdf | NONE | GFM/SG/GFL coexistence, power-sharing context |

### Available local sources (insufficient)

- Padiyar, *Power System Dynamics: Stability and Control*, 2nd ed.
  (`/home/birds/Documents/textbook/`). Covers SG conventions (KCL form
  Eq.5.27 p.157, per-unit Sec 3.5 p.62, current direction Sec 3.2.2 p.47).
  Does NOT cover GFL/VSG/REGFM_B1, current limiting, synchronism, or IEEE14
  IBR dynamics.
- `/tmp/synchronverters.pdf` = Zhong & Weiss 2011, "Synchronverters: Inverters
  That Mimic Synchronous Generators," IEEE TIE 58(4):1259–1267. This is the
  synchronverter CONCEPT paper. The historical Track B audit already
  inspected it and concluded: **"No project VSG equation is a verbatim match
  to Zhong & Weiss 2011"** — it uses a torque-form swing equation
  (`J·θ̈=Tm−Te−Dp·θ̇`), not the project's first-order-in-pu-speed-deviation
  form, and a different voltage-controller structure. It is a conceptual
  ancestor, not a source-closed REGFM_B1 profile.

### 9-item source-closure checklist — status

| # | Item | Source-closed? | Reason |
|---|------|----------------|--------|
| 1 | GFL positive-sequence model + state order | NO | Requires Ding (83340) / WECC REGC_B1+REEC_B1 — unreachable |
| 2 | VSG/VSM profile from REGFM_B1 | NO | Requires NREL 90260 — unreachable; Zhong & Weiss 2011 is NOT a verbatim match (historical audit confirmed) |
| 3 | GFL↔VSG transfer maps (both directions) + inactive-state rule | NO | Requires Ding (83340) — unreachable; historical audit: anti-windup/recovery are DESIGN_PROPOSAL/DECISION_REQUIRED |
| 4 | Current limiter + anti-windup | NO | Requires REGFM_B1/WECC — unreachable; historical audit rows 18–20 are UNSOURCED |
| 5 | SG synchronism thresholds/dwell/timeout | NO | Requires IEEE PES TR-121 — unreachable |
| 6 | Delays (T_up, T_sg_min_off, T_settle, T_minimum_hold, T_guard, T_lockout, ρ) | NO | Requires protection/controller specs — no source; ρ and T_minimum_hold need a-priori declaration |
| 7 | IEEE14 SG dynamic data (H, D, X'd or full EMF6) | NO | Case file has NO `.machines`; classical defaults H=5.0/D=0/X'd=0.30 are UNSOURCED textbook guesses; EMF6 path errors without `.machines`; no sourced IEEE14 dynamic dataset available locally |
| 8 | Dispatch/energy contract resolving 219 MW post-trip deficit | NO | Case has 259 MW load, bus-1 Pg 232.4 MW, buses 2–8 Pg 40 MW → 219 MW deficit after SG trip; no sourced reserve/participation/ramp/load-shed policy |
| 9 | Selection margin gamma_req | NO | Requires source/requirement/a-priori study — none available |

**Result: 0 / 9 items source-closed.** The autonomous selection hierarchy
(directive 3) cannot be applied because no source-backed alternatives exist
to choose among — the candidate sources themselves are unreachable.

### Why this is a genuine stop (not a workaround opportunity)

- The user directive "ห้าม assumed" forbids ASSUMED_DIAGNOSTIC production
  values. Items 1–9 cannot be source-closed, and the forbidden fallback is
  exactly what would be required to proceed.
- The historical Track B audit already established that the available local
  sources (Padiyar, Zhong & Weiss 2011) do NOT provide equation-level
  coverage for the VSG/GFL/limiter/synchronism equations. Re-running that
  audit against the same local sources would reproduce the same UNSOURCED
  verdicts.
- No independent interface/test/documentation work can proceed past Phase 1
  without the frozen mathematical profile: Phases 2–4 (event architecture,
  hybrid-state, mixed equilibrium) are GENERIC but their TESTS require a
  real sourced device model to validate against; Phases 5–17 are entirely
  device-model work that cannot begin without sourced GFL/VSG equations.

### Smallest user decision needed

Restore outbound network access on this host (or provide the five primary-
source PDFs locally), so Phase 1 can fetch and inspect:

1. NREL 90260 (REGFM_B1 VSM GFM spec) — highest priority; closes items 2, 4.
2. NREL 83340 (Ding et al. configurable GFM/GFL) — closes items 1, 3.
3. WECC generic RES models summary — closes parts of item 4.
4. IEEE PES TR-121 — closes item 5.
5. NREL 87959 (GFM dispatch) — context for item 8.

PLUS a sourced IEEE14 dynamic dataset (item 7) and a sourced dispatch/
energy contract resolving the 219 MW deficit (item 8) — these are case-
data gaps, not just network gaps, and may require an explicit user-provided
contract even after network is restored.

## Track A interfaces verified at base (no changes)

The audit confirmed all Track A B1–B9 interfaces are present and correct at
`31a211d`: `composite_dae` (5-arg device ABI, `YV-I` KCL, FIXED y-only
vcon), `multimachine_ssa` (paired Schur, B6 checks, COI `pinv(T)`),
`multicase_sssa` (exclusive dispatch), `ts_simulate` (bundle dispatch,
default FIXED), `ts_event_transition` (9-arg, event_tol=1e-10, supports
ONLY fault_on/fault_off — the mission's 10-event vocabulary requires the
generic ordered named-event extension authorized in Phase 2).

## What was NOT done (and must not be done without sources)

- No `+ibr/**` production model code.
- No `+cases/case_ieee14_1sg_4ibr_auto_vsg*.m`.
- No `+stability/` event-system extension (Phase 2 work).
- No mixed-resource equilibrium solver (Phase 4 work).
- No push, merge, rebase, history rewrite, or main mutation.
- No modification of Track A / Padiyar / report / adaptive worktrees.
- No pop/drop of stash `eae0bcd`; no recreation of removed Track B worktree.

## Reproduce

```bash
git -C /home/birds/Documents/Power-flow fetch --all   # confirm no race
git -C /home/birds/Documents/Power-flow-ieee14-ibr log --oneline -5
git -C /home/birds/Documents/Power-flow-ieee14-ibr status --short --branch
```

```matlab
restoredefaultpath;
cd('/home/birds/Documents/Power-flow-ieee14-ibr');
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);   % 454/454/0/0
```

## Network-diagnostic commands (for the user to run if restoring access)

```bash
curl -sSL -o /tmp/NREL_90260.pdf https://www.nrel.gov/docs/fy24osti/90260.pdf
curl -sSL -o /tmp/NREL_83340.pdf https://www.nrel.gov/docs/fy23osti/83340.pdf
curl -sSL -o /tmp/IEEE_TR121.pdf https://resourcecenter.ieee.org/publications/technical-reports/pes_tp_tr121_psrc_42924
```
