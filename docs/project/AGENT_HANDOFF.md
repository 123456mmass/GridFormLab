# Agent handoff — IEEE14 mixed-resource IBR validation closure

Date: 2026-07-17 (Revision 5 corrective closure); 2026-07-18 IBR dynamic-equation contract Phases 0A/1/2/3; 2026-07-18/19 GFL-RMS10 reopening Phases 0/1/2/3/4; 2026-07-19/20 domain-preserving Newton globalization; 2026-07-20 GFM-VSG-no-PLL SMIB-first characterization; 2026-07-21 SSSA load sweep (SMIB loaded-IBR)
Branch: `main`
Tested working tree: `ea7150f` (uncommitted domain-preserving Newton fix on top of all-GFL equilibrium)

This is the current canonical handoff. Historical phase handoffs remain
provenance but do not override this runtime status.

## 2026-08-04 — ET-FCSPS core and paired BO baseline

Starting commit `6eeb05c`. An additive, production-isolated ET-FCSPS decision core is now
implemented under `+stability/et_fcs_*.m`. It validates/fingerprints an accepted value-state,
enumerates 16 four-IBR mode vectors (and 32 SG-off mode-owner pairs), applies dwell/lockout and
full-network evidence gates, validates an isolated prediction horizon, computes unmodified
dimensionless metrics, ranks deterministically, emits a fingerprint-bound `COMMIT_REQUEST`, and
revalidates it with a pure commit guard. The core never mutates hybrid state; existing atomic
event handling remains the only commit authority. A project-owned authenticated trial-table
provider interface is included so production policy rejects arbitrary callbacks.

The frozen IEEE14 prototype policy is `PROJECT_DERIVED`: `T_p=0.25 s`, AGSI++-aligned engineering
normalizers, voltage/current-dominant soft weights, and explicit provenance. It is frozen before
closed-loop results and does not alter AGSI++, thresholds, SG/IBR equations, case limits, or event
chronology. An in-house Base-MATLAB finite-set BO replay baseline uses an RBF Gaussian process and
expected improvement after the identical hard screen. It is explicitly
`ASSUMED_DIAGNOSTIC_OFFLINE_REPLAY`, budgeted at 8 predictions, never feeds ET-FCSPS/production,
and reports paired winner, regret, and prediction-evaluation reduction. With a full budget it is
required to recover the exhaustive winner.

Fresh gates: ET-FCSPS/BO unit-oracle suite 20/20 PASS; existing authenticated selector table 44/44
PASS; existing SG-ON integration 12/12 PASS; Code Analyzer zero issues for all new files. The full
repository regression was intentionally omitted under the risk policy because the new core is
unreachable from the default production runtime. Reports and PDFs were not edited. Remaining
production-integration gate: create and verify a nonlinear accepted-state trial-table producer
using the existing full-KCL state mapping/short-horizon runtime, then connect the returned request
to the existing atomic event transaction under a separate shared-runtime ownership plan. See
`docs/project/plans/ET_FCSPS_IMPLEMENTATION_PLAN.md` and defect record
`docs/project/defects/2026-08-04-et-fcs-provider-name-dispatch.md`.

## 2026-08-04 — detailed ET-FCSPS technical report

Documentation-only follow-on to the 18-slide proposal deck. A 14-page Thai A4 report now
documents the proposed Event-Triggered Finite-Control-Set Predictive Supervisor in technical
detail: the exact current bounded AGSI++ equation and local hysteresis/dwell behaviour, accepted
system snapshot, 16 mode vectors and up to 32 mode-owner pairs, event/candidate generation,
full-KCL and reserve hard gates, isolated short-horizon prediction, normalized objective,
deterministic tie-break, reference-owner transaction, fail-closed fallback, pseudocode,
complexity, expected outcomes as falsifiable hypotheses, fair BO role comparison, proposed
interfaces, phased implementation, verification matrix, examples, and technical Q&A. The report
marks existing behaviour `VERIFIED CURRENT` and the supervisor `PROJECT-DERIVED PROPOSAL / NOT
YET IMPLEMENTED`; it does not claim closed-loop improvements. AVR, LLM/BO online authority,
SG/IBR equations, thresholds, case data, numerical results, and production runtime are unchanged.
XeLaTeX builds twice with no error, overfull, undefined-reference, or missing-character warning;
all 14 rendered pages were visually inspected. Source:
`docs/source/report_et_fcs_predictive_supervisor_th.tex`. Final artifact:
`output/pdf/report_et_fcs_predictive_supervisor_th.pdf`. Full regression was intentionally omitted
because the change is documentation-only; static/build/render checks cover the changed scope.

## 2026-08-04 — ET-FCS predictive-supervisor proposal deck

Documentation-only follow-on at starting commit `f78ea00`: an 18-slide Thai Beamer deck proposes
an event-triggered finite-control-set predictive supervisor above the existing AGSI++ local state
machines. It separates verified current behaviour from the unimplemented `PROJECT_DERIVED`
proposal, enumerates all 16 four-IBR mode vectors, defines global measurements, hard feasibility
gates, short-horizon cost/ranking, reference-owner transactions, fail-closed fallback, expected
benefits with measurable falsification metrics, phased implementation, and predeclared gates. The
workflow is rendered as a non-overlapping numbered two-row sequence. The BO comparison is role-specific and does
not claim universal superiority or closed-loop improvement before identical-contract testing. AVR,
LLM/BO online switching, SG/IBR equations, thresholds, cases, and production runtime are unchanged.
XeLaTeX builds 18 pages with no overfull/error warnings; every rendered slide was visually checked.
Source: `docs/source/presentation_fcs_predictive_supervisor_th.tex`. Final artifact:
`output/pdf/presentation_fcs_predictive_supervisor_th.pdf`.

## 2026-08-04 — final 160-s REGFM_B1/EMF6 chronology

Starting HEAD was `d3e448c` on `main`. The IEEE14 1-SG + 4-IBR report chronology now runs through
the project-owned REGFM_B1 all-KCL hybrid engine for the full 0--160 s sequence. The primary
`dt=0.0125 s` run completed in 4820.172442 s with maximum accepted-step residual
`9.98175508801e-9`, maximum attempted parent residual `3.19889806266e-4`, and subdivision depth 1.
The SG passed `Delta V=0.012765179 pu`, `Delta f=0.000779556 pu`, and
`Delta theta=3.401986499 deg` at the synchronism guard, closed at 147.175 s, and the coordinated
transaction returned IBR1--IBR4 from GFM to GFL. At 160 s, voltage spans
0.984909456--1.055630216 pu, `P_e,SG=1.048198640 pu`, `P_m,SG=1.046208344 pu`, and
`f_SG=60.046773383 Hz`; its last-2-s slope remains `+0.007391996 Hz/s`, so exact steady state is
not claimed.

The closure uses frozen `PROJECT_DERIVED` post-trip dispatch, an `ASSUMED_DIAGNOSTIC` deterministic
offline phase planner/voltage matcher, and a project-owned two-state Sauer--Pai Type-A primary
governor. There is no Bayesian-optimisation controller. A `dt=0.025 s` comparison completed in
1853.621603 s but closed at 148.175 s, so the report exposes 1.000-s event-time sensitivity and
does not claim time-step-independent controller validation. Seeded band-limited ripple is a
display-only dotted overlay; solid raw traces remain visible and all solver/AGSI/timer/mode data
remain untouched.

Targeted production/consumer/failure-path verification is 108/108 PASS. The full repository
regression was intentionally omitted under the risk policy. Thai and English reports compile to
12 and 8 pages with no overfull/error warnings; all pages were rendered and visually reviewed.
The English report contains no example-report author/title reference. See
`docs/project/defects/2026-08-04-agsi-bounded-publication-evidence.md` for the historical failed
route and the diagnostic evidence boundary.

## 2026-08-04 — EECON49 full-state switch/reclose evidence

Historical intermediate status; superseded by the final REGFM_B1/EMF6 section above.

The EECON49 IEEE14 report route now uses the project operational six-state EMF6 SG and
source-mapped 12-state GFL/GFM switching supersets. A positive-feedback current-error defect
(`i-iref`) was corrected to `iref-i`; dedicated equilibrium and fixed-bus eigenvalue gates pass.
The compressed ideal-SG trip/reclose gate remains an internal software test only. The exact 160-s
chronology remains `OPEN_MODEL_LIMITATION`: it stops fail-closed at 36.040 s after SG trip because
the source does not publish the DC-energy law, post-trip active-power redistribution, command
dynamics, or multi-GFM sharing contract. The reports now include only the accepted prefix as
explicitly labelled diagnostic evidence, with separate IBR1--IBR4 modes and IBR+SG electrical
traces. A seeded synthetic measurement overlay affects display only; raw data and decisions are
unchanged. No full 145-s recovery claim is made. Proportional-sharing and aggregate-swing
diagnostic candidates were falsified and removed; details are in
`docs/project/defects/2026-08-04-agsi-bounded-publication-evidence.md`.
Fresh targeted verification: 25/25 PASS. EN/TH XeLaTeX builds pass and all 7+10 rendered pages
were visually reviewed. Full regression intentionally omitted under the risk policy; the only
open gate is the advisor-approved long-duration dispatch/energy/control law required for 160 s.

Continued 2026-08-04 diagnostics also rejected direct Sakimoto-governor splicing, a critically
damped secondary integrator, immediate GRA override, proportional dispatch, command lags, and
single-GFM arbitration on the legacy report driver. The reduced-6 wrapper was additionally found to
have split limiter semantics (clamped KCL current versus unclamped swing power), so it is not a
valid workaround. The production REGFM_B1/all-KCL engine remains the correct integration base, but
its present event schedule orders fault before SG trip and lacks the required later load/line
events; a 40-s SG-cycle performance probe exceeded 600 s without a terminal result. Experimental
runtime edits were removed; details remain in the linked defect record.

## 2026-07-21 — Separate SMIB TDS current and power plots

The ideal-SMIB TDS diagnostic now preserves the perturbed algebraic-voltage
trajectory and reconstructs four independent time-domain products:
`i_d(t)`, `i_q(t)`, `P(t)`, and `Q(t)`. GFL-RMS10 uses its native inverter-base
current states. GFM-noPLL has no current state, so its current traces are
explicitly classified as a reporting-only transform of `I_inv` into the VSM
rotor frame. Active/reactive power uses the system-base generator convention
`S=V*conj(I_sys)` and is checked at every sample with a `1e-10` pu numerical
identity gate. SSSA load-sweep plots remain separate and retain load increase
(%) on the horizontal axis; only TDS plots use time (s).

Targeted verification only per user instruction: the new signal/plot suite
passed 3/3 and the existing GFM/GFL SMIB oracle suites passed 15/15. Full
repository regression was intentionally not run.

## 2026-07-21 — SSSA load-sweep plot correction and dq/P/Q diagnostics

Starting commit `3379688`. The plot adapter now preserves the raw 10-mode GFL
and 4-mode GFM spectra, constructs cumulative one-to-one tracked-mode indices,
and includes the base case in `[0 20 40 60 80]`. Plot A is the complete linear
real/imaginary eigenvalue plane with unconnected markers; a labelled
low-frequency detail is additional only. Plots G--J publish accepted-equilibrium
`i_d`, `i_q`, `P`, and `Q` as four separate figures for each load level. GFL
currents are native states;
GFM-no-PLL currents are a labelled VSM-frame diagnostic transform because that
4-state model has no current state. Every point verifies
`P+jQ = V*conj(I)` within `1e-10` pu before publishing.
When `sssa_plot_visible=true`, generated desktop figures remain open after the
sweep returns; only `Visible='off'` headless figures are closed automatically.

Targeted verification only, per explicit user instruction not to run the full
suite: `tests/test_sssa_load_sweep.m` 31/31 PASS after the visible-figure gate;
the earlier launcher-consumer rerun was 21/21 PASS. Full repository regression
intentionally omitted.

## 2026-07-21 — SSSA load sweep (single GFL/GFM to infinite bus, shunt load)

**Starting commits:** `smib_starting_commit=83390db`,
`smib_delivery_commit=efa9617`, `load_sweep_starting_commit=efa9617`.

### Scope

A configurable SSSA load-sweep product that scales a shunt load at constant
power factor and re-solves equilibrium + full-KCL SSSA at every load level.
User redirected scope from IEEE14-mixed+SG to a SINGLE IBR (GFL-RMS10 OR
GFM-no-PLL — two separate cases) connected to an ideal infinite bus through
`Z_line`, with a shunt load at the IBR terminal bus. Default percentages
`[0 20 40 60 80]`, user-adjustable. New schema `smib_loaded_ibr/1.0`; the
existing ideal `smib_verification/1.0` fixture stays bit-identical.

### Files added

- `+cases/case_ibr_smib_loaded_gfl_rms10.m`, `+cases/case_ibr_smib_loaded_gfm_no_pll.m`
- `+ibr/smib_loaded_equilibrium.m` (dedicated Newton equilibrium solver; 2-stage init)
- `+ibr/smib_loaded_sssa_oracle.m` (SSSA oracle with load current term)
- `+stability/+load_sweep/route_smib_ibr.m` (route adapter)
- `tests/test_sssa_load_sweep.m` (31 tests after plot/visibility corrections, GFL+GFM)
- `docs/project/defects/2026-07-21-gfl-rms10-smib-unstable-mode.md`

### Files modified

- `+stability/sssa_load_sweep.m` (route `smib_ibr`; default `[0 20 40 60 80]`)
- `+stability/sssa_load_sweep_point.m` (accept `smib_ibr`; smib snapshot copy)
- `+stability/sssa_load_sweep_scale_case.m` (smib_loaded_ibr branch)
- `+stability/+load_sweep/applicability.m`, `fingerprint.m` (smib_loaded_ibr)
- `+wizard/defaults_for_method.m`, `discover_cases.m`, `validate_request.m`, `dispatch_analysis.m`
- `tests/test_wizard_smib_cases.m` (loaded-IBR discovery)
- `docs/project/SSSA_LOAD_SWEEP_CONTRACT.md`, `docs/project/defects/INDEX.md`

### Dispatch policy (ASSUMED_DIAGNOSTIC)

IBR references (`P_ibr_base`, `Q_ibr_base` for GFL; `P_ibr_base`+`V_ref` for
GFM) are held FIXED at base. The infinite bus is the slack that absorbs the
incremental load through `Z_line`. Terminal voltage decreases monotonically
with load (GFL: 0.994→0.975; GFM: 0.986→0.976). Setting IBR reference = load
would make line flow = 0 and degenerate to an isolated IBR+load.

### Fresh targeted metrics (R2025a-equivalent)

- GFL loaded-IBR sweep `[0 20 40 60 80]`: all 5 points SUCCESS, 10 eigenvalues
  each, equilibrium residual <5e-12, mode matching available. `max_real≈3.4e5`
  (UNSTABLE — same magnitude as the existing ideal-SMIB oracle 3.37e5; this
  is a GFL-RMS10 device-model property, NOT a load-sweep defect; see defect
  record `SWEEP-2026-07-21-01`).
- GFM loaded-IBR sweep `[0 20 40 60 80]`: all 5 points SUCCESS, 4 eigenvalues
  each, `max_real≈-0.56` (ASYMPTOTICALLY STABLE), mode matching available.
- Ideal SMIB (`smib_verification/1.0`) + `sssa_load_sweep` rejected with
  `wizard:validate_request:loadSweepSmibIncompatible` /
  `LOAD_SWEEP_NOT_APPLICABLE_TO_IDEAL_SMIB`.
- Final targeted verification: `tests/test_sssa_load_sweep.m` 31/31 PASS;
  `tests/test_wizard_smib_cases.m` + `tests/test_wizard_dispatch.m` 21/21 PASS.

### Readiness

`SSSA_LOAD_SWEEP_PRODUCTION_READY = DIAGNOSTIC_ONLY`. Production device
f/current_injection closures are used unchanged; no external solver; no
device-equation edits. The load-growth/dispatch study policy is
`ASSUMED_DIAGNOSTIC` (IBR-refs-fixed + infinite-bus-slack). No exact stability
boundary, CPF nose point, or production operating-limit approval is claimed.
Stability is an outcome, not an acceptance gate.

### Full regression

Intentionally not run per the user's explicit instruction. The proportional
targeted producer and launcher-consumer suites above were used instead.

## 2026-07-20 — Separate GFL/GFM SMIB launcher cases

The IBR case dialog now lists `gfl_rms10_smib` and `gfm_no_pll_smib`
separately. Each route supports PF/equilibrium, SSSA, event-free TDS, or Full
Verification using the existing device closures and independent SMIB oracles.
It does not expose IEEE14 mode counts, SG-cycle comparison, or events.

Fresh R2025a targeted metrics: GFL order/roots 10/10, `||f||inf=2.79e-13`,
`||g||inf=1.11e-16`, Schur/direct error `6.68e-15`; its positive PLL pole is
retained and classified UNSTABLE. GFM no-PLL order/roots 4/4,
`||f||inf=6.52e-14`, `||g||inf=2.08e-16`, Schur/direct error `8.10e-11`,
ASYMPTOTICALLY STABLE, event-free TDS drift zero. Figures are written beneath
`output/figures/smib/{gfl_rms10,gfm_no_pll}/`. IEEE14 integration readiness is
unchanged.

## 2026-07-20 — GFM-VSG without PLL (SMIB-first, source-traced)

**Starting repository checkpoint:** `4d8b015` (`HEAD` one commit ahead of
`origin/main`; source-set separation commit). No shared file edited.

### Scope

New opt-in positive-sequence RMS GFM-VSG with NO PLL:
`+ibr/gfm_vsg_no_pll_model.m` (4-state `[delta_vsm, delta_omega_vsm, P_f,
Q_f]`, algebraic PNNL VFlag=0 Q-V droop, Thevenin behind pure `jX_L`).
Source contract: `docs/project/GFM_NO_PLL_SOURCE_CONTRACT.md`. Sourced study
parameters (Avila-Martinez 2025 + PNNL-35110): `H_GFM=5 s`, `D_GFM=20 pu`,
50 Hz, 100 MVA, `X_L=0.15 pu`, `m_q=0.05`, `T_P=T_Q=0.01 s`.

### Hard no-PLL contract (enforced)

No `delta_PLL`, no `xi_PLL`/`x_PLL_int`, no PLL PI gains, no PLL freeze, no
PLL-estimated frequency, no runtime `angle(V)` tracking. Runtime rotor angle
ONLY from `dot(delta_vsm)=omega_base*delta_omega_vsm`. Construction-time
`reject_unsupported_options` rejects dormant PLL/AVR/limiter fields.
Behavioral tests: angle-derivative structure, terminal-angle independence,
rigid-frame covariance.

### DUAL SMIB verification (GFL + GFM as separate cases)

Generic `+ibr/smib_tds_oracle.m` (`ASSUMED_DIAGNOSTIC_SMIB_TDS_ORACLE`,
NOT a production TS solver) added alongside the existing
`+ibr/smib_sssa_oracle.m`. Both are generic over either device via runtime
metadata (`dev.nx`/`dev.active_state_indices`); no hard-coded state count.

Targeted gates (all PASS):
- Device ABI: `tests/test_ibr_gfm_vsg_no_pll_model.m` — 15/15.
- GFM SMIB: `tests/test_ibr_gfm_vsg_no_pll_smib.m` — 6/6 (equilibrium, SSSA,
  FD convergence, event-free TDS, small-perturbation consistency, no-PLL
  behavior).
- GFL SMIB: `tests/test_ibr_smib_sssa_oracle.m` — 9/9 (GFL control case
  extended with SSSA/TDS tests).

GFM-noPLL SMIB metrics: `f0=6.5e-14`, `g0=2.1e-16`, `gy_rcond=0.92`,
`eigenvalue_count=4`, `schur_direct_err=8.1e-11`, `max_real_eig=-0.556`
(stable), 4 eigenvalues (1 complex conjugate swing pair + 2 real filter
modes). Event-free TDS drift=0; nonlinear-vs-linear error=2.9e-5 at
amp=1e-3; perturbation-halving ratio=1.4e-5.

GFL control case: `f0=2.8e-13`, `g0=1.1e-16`, `gy_rcond=0.83`,
`eigenvalue_count=10`, `schur_direct_err=6.7e-15`. NOTE: GFL has an
unstable PLL eigenvalue (real part ~3.4e5) at this operating point; the
linear SSSA response overflows and is reported honestly as `Inf`
(`linear_overflow=true`). Stability is an outcome, not a gate. This is
pre-existing GFL behavior, not a defect of the GFM-no-PLL work.

### Verification plots

`scripts/ibr/smib_verification_plots.m` generates PF/equilibrium + SSSA
figures for both devices (separate directories) plus a 2x2 summary.
Diagnostics: `output/diagnostics/smib/{gfl_rms10,gfm_no_pll}_smib.txt`.
Figures: `output/figures/smib/{gfl_rms10,gfm_no_pll}/` + summary PNG.

```
GFL_SMIB_PF_EQUILIBRIUM_PLOT = PASS
GFL_SMIB_SSSA_PLOT = PASS
GFM_NO_PLL_SMIB_PF_EQUILIBRIUM_PLOT = PASS
GFM_NO_PLL_SMIB_SSSA_PLOT = PASS
```

### Delivery status

```
GFL_SMIB_SSSA_ORACLE = PASS
LEGACY_REGFM_B1_WITH_PLL_SMIB_COMPARISON = PASS
GFM_NO_PLL_SOURCE_CONTRACT = PASS
GFM_NO_PLL_SMIB_EQUILIBRIUM = PASS
GFM_NO_PLL_SMIB_SSSA = PASS
GFM_NO_PLL_EVENT_FREE_TS = PASS
GFM_NO_PLL_IEEE14_INTEGRATION_READY = NOT_READY
```

IEEE14 integration NOT_READY: `device_contract_metadata` registration,
`build_mixed_resource_devices` factory case, and IEEE14 60 Hz mapping of
`H_GFM`/`D_GFM`/`X_L`/`m_q` remain `BLOCKED_CASE_MAPPING` pending separate
approval. Phase 5 shared composite SSSA/TS comparison deferred (standalone
oracle is the first-milestone gate). AVR/dynamic voltage PI, current
limiter, fault LVRT: OUT-OF-SCOPE future extensions.

## 2026-07-19 — Domain-preserving Newton globalization (RESOLVED_PENDING_FINAL_REGRESSION)

**Starting repository checkpoint:** `ea7150f` (`HEAD == origin/main`).
Defect record: `docs/project/defects/2026-07-19-domain-preserving-newton-globalization.md`.

### User-visible symptom

The IEEE14 Profile-B `1-SG + 4-IBR` full-analysis run with `Zf=0.1i` died at
`t=3.25 s` — before `sg_trip=5 s` and `sg_on=8 s` — so the SG reclose workflow
was never reached. `dt=0.01` surfaced `ts_simulate_ibr_hybrid:stepNewton`
(residual `4.983e-4`); `dt=0.005` surfaced
`ibr:gfl_rms10_model:lowVoltagePowerInversion` from a `composite_newton`
line-search trial iterate.

### Root cause

`composite_newton` propagated any exception from the line-search trial
evaluation `residual_fn(z_new)` to the caller. The classified RMS10 runtime
domain exception is raised when a *trial* iterate leaves the balanced-LVRT
voltage domain, not when the *accepted* iterate does. Accepted-trajectory
instrumentation proved accepted IBR terminal voltages stayed above `0.48735`
(overall `0.45766`), far above `V_div_min=0.1` — a Newton-globalization
defect, not a physical LVRT violation. The throw bypassed
`trial.converged=false`, so `advance_with_subdivision` never bisected.

### Correction (opt-in, backward-compatible; TS trial path only)

- `+stability/composite_newton.m`: optional 7th input `opt`, always-returned
  7th output `info`. `try/catch` wraps only `r_new=residual_fn(z_new)` in the
  alpha-halving loop. Exact-ID classifier on
  `ibr:gfl_rms10_model:lowVoltagePowerInversion`; every other exception
  rethrows. Classified trial: increment counter, record bounded diagnostics,
  never assign accepted state from the trial, halve alpha via the existing
  `1..2^-19` sequence, continue. Legacy acceptance rule unchanged. Current
  residual, Jacobian/FD, and final reporting remain uncaught.
- `+stability/ts_step_composite.m`: policy on only when
  `step_opt.domain_preserving_trials=true` (sole caller:
  `ts_simulate_ibr_hybrid`). Pure voltage-reconstruction diagnostic (no
  DAE/device callbacks); reports every below-threshold online GFL device;
  reads `V_div_min` from device provenance (no hard-coded threshold).
- `+stability/ts_simulate_ibr_hybrid.m`: publishes
  `domain_rejected_trials`/`subdivision_depth` in `res`/`meta`/`empty_result`;
  extends `advance_with_subdivision.stats`; preserves subdivision invariants
  and scheduled-event boundaries; composes domain-specific failure messages
  only when terminal-leaf classified evidence exists.
- `+stability/run_hybrid_case.m`: copies counters to the public result and
  `execution_summary` on every path.
- `+ibr/dual_mode_ibr_model.m`: forwards `gfl_runtime_min_voltage` from
  standalone GFL provenance (additive metadata only).

No equation, parameter, threshold, tolerance, event timing, accepted-state
rule, or PF/equilibrium/SSSA result changed. Equilibrium, SSSA, and
`ts_simulate_composite` remain default-off and bit-identical.

### Verification

- `tests/test_composite_newton_contract.m`: **9/9 PASS** (6 new + 3 legacy).
- `tests/test_ts_domain_preserving_newton.m`: **5/5 PASS** (new).
- Numerical invariance gates (expected values unchanged): 96 passed, 2
  pre-existing failures in the `mixed_equilibrium_solve` path (confirmed by
  `git stash` baseline; unrelated — that path calls `composite_newton` with
  the 6-arg default form).
- End-to-end `Zf=0.1i`:
  - `dt=0.005` (PASSES): prior `lowVoltagePowerInversion` trial throw is
    now a rejected trial; the domain-preserving catch engaged **197 times**
    and the run completed all 3005 accepted samples to `t=15 s`, reaching
    `sg_trip=5 s`, `sg_on=8 s`, terminating at `sg_reclose_timeout=13 s`.
    Accepted IBR voltages stayed `min|V|=0.48825 >= V_div_min`;
    `domain_rejected_trials=197`, `subdivision_depth=4` published; event
    landings exact.
  - `dt=0.01` (STILL FAILS — separate defect IBR-2026-07-20-01): fails at
    `t=3.25 s` with `domain_rejected_trials=0` and `subdivision_depth=4`.
    No classified domain throw occurred, so the domain-preserving catch was
    never engaged; subdivision exhausted without rescue. Non-smooth
    residual trajectory and near-singular `rcond~7e-7` indicate a
    non-domain Newton/Jacobian stall (limiter discontinuity or
    conditioning), not a trial-voltage violation. Out of scope for this
    fix; tracked as a follow-up defect.
- Evidence: `output/diagnostics/verify_domain_preserving_fix_20260720.log`
  and `output/diagnostics/diagnose_dt01_t325_20260720.log`.
- Full repository regression: **1185 passed / 10 failed / 7 incomplete**
  (MATLAB R2026a, tested tree `ea7150f` with the fix applied). All 10
  failures confirmed pre-existing by `git stash` baseline (fail identically
  without the fix): 2 in `mixed_equilibrium_solve` (6-arg default
  `composite_newton`), 2 in `test_ibr_launcher_settings_ui` (UI dialog),
  2 in `test_ibr_ts_plotting_absolute` (figure creation), 1 in
  `test_ibr_equilibrium_initializer` (SG device), 1 in
  `test_ieee14_1sg_4ibr_phaseB1`, 1 in `test_wizard_characterization`, 1
  in `test_wizard_ibr_subanalysis`, 1 in
  `test_ieee14_sg_reference_equilibrium`. The 7 incomplete are the
  pre-existing `test_pgaz_conversion_contract` assumption filters (external
  pgaz tool not installed). None are caused by the domain-preserving
  change.

### Scope and follow-up

The domain-throw defect is resolved and verified by targeted tests. The
dt=0.01 end-to-end gate is **not** met and is tracked as a separate
non-domain Newton/Jacobian stall (IBR-2026-07-20-01); a full root-cause
fix (domain-aware FD, Jacobian regularization, or limiter smoothing) is a
separate numerical-method contract requiring its own plan and approval.

SG governor/reclose controller is **out of scope** for this slice per the
user decision; it is diagnosed separately after the TS fault path is
correct. At `dt=0.005` the run reaches the reclose workflow and reports
`SYNC_TIMEOUT` — a physical synchronism outcome, not a numerical failure.
`IBR_PRODUCTION_INTEGRATION_READY` remains `NOT_READY`.

## 2026-07-19 — all-GFL SSSA initialization (RESOLVED)

**Starting repository checkpoint:** `4cbf413` (`HEAD == origin/main`).
Resolution evidence was generated on MATLAB R2026a. See defect record
`docs/project/defects/2026-07-19-sg-on-all-gfl-equilibrium.md`.

### User-visible symptom

In the compact IBR launcher, choosing `SSSA` with `Initial GFM count = 0` and
`Initial GFL count = 4` (SG1 remains online) failed closed before eigenanalysis:

```matlab
o = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
o.ibr_analysis = 'sssa';
o.initial_gfm_count = 0; o.initial_gfl_count = 4;
o.initial_gfm_indices = []; o.initial_reference_resource_index = [];
o.ibr_events = struct('enabled',false); o.plot_results = false;
r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',o);
```

Observed route: `wizard:dispatch_analysis:ibrEquilibrium` wrapping
`mixed_equilibrium_solve:noConverge`.  It is correct that no eigenvalue/state
table is printed without a converged equilibrium.  Do not fabricate a spectrum,
silently convert a GFL to GFM, relax a tolerance, or alter any source/case
parameter to make this pass.

### Correction

The helper `+stability/mixed_ibr_sg_on_gfl_initialize.m` is a
`PROJECT_DERIVED` **warm-start only** for the narrow SG-on/all-online-GFL
configuration. It changes each online GFL terminal bus from the inherited PF
PV label to the effective PQ semantics implied by its actual `P_ref,Q_ref`,
runs the existing in-house PF, and calls device-owned
`equilibrium_initialize`. `+stability/sg_composite_device.m` now exposes an
EMF6 stationary initializer based on the same stator equations and derives its
constant `[Tm,Efd]` seed through the existing RHS. `mixed_equilibrium_solve`
then still solves and verifies the unmodified full DAE/KCL system at the
unchanged `1e-8` gate.

The diagnosis found stationary device states but a load-inconsistent network
seed: SG RHS was `1.62e-15`, every GFL RHS was below `2e-11`, while a physical
KCL component reached `0.164 pu`. The complete KCL error matched the difference
between constant-power PF loads and the composite DAE's frozen
constant-admittance loads. The helper now represents the unchanged loads with
the exact admittances frozen by `composite_dae` before its mode-aware PF.

### Closure evidence

- independent EMF6 stationary oracle: exact SG-state agreement; angle residual
  `2.78e-17`;
- corrected initial/coupled residual `9.63e-12`, physical KCL `8.43e-12`;
- SSSA publishes all 45 active states and 45 finite roots; the physical result
  is honestly classified `UNSTABLE` under the unchanged equations;
- event-free 15 s TS accepts `1500/1500` steps;
- scoped producer/consumer/launcher regression: `45/45` passed;
- wizard UI smoke: `24/24` passed;
- full repository regression was started, then stopped by explicit user
  instruction that it was unnecessary; no full-suite PASS is claimed.

### Report and TS follow-up

The report generator and `docs/source/report_ieee14_ibr_pf_sssa_ts_en.tex`
now publish the 14 solved PF bus rows, all 20 branch sending-end flow/loss
rows, and the complete 45-root SG1 + four-GFL SSSA table. Every numerical
table and plot in this report uses SG1 plus IBR2/3/6/8 in GFL-RMS10 mode; no
GFM resource is active in the reported operating point. The detailed GFM
state order, ODEs, and controls remain in the report as documentation of the
reserved inactive dual-mode branch. Regenerated R2026a evidence records
all-GFL equilibrium residual `9.6265e-12`, physical KCL `8.4308e-12`, and
event-free TS completion at 15 s with `1500/1500` accepted steps. The final
17-page PDF is A4 portrait throughout; PF, line-flow, resource, SSSA, and TS
result pages were visually inspected from rasterized output.

The PF resource-reporting path also now consumes the committed mode selection.
Previously, its presentation-only fallback interpreted an explicit empty
`initial_gfm_indices=[]` as missing and printed IBR2 as GFM despite the solved
all-GFL request. The numerical PF was unaffected; the corrected report prints
SG1 plus four GFL-RMS10 resources and active order 45.

The report operating-point tables were subsequently unified. Bus voltages,
bus generation/load/net injection, all 20 branch flows, and device injections
are now reconstructed from the same accepted SG1 plus four-GFL equilibrium
used by SSSA and TS. The source REF/PV/PQ PF is retained only as the frozen
constant-admittance load anchor and is not published beside the equilibrium
tables. The report producer independently checks
`Sgen + Sshunt - Sload - Sbranch_loss`; the regenerated balance norm is
`1.8610e-11 pu`. Table 5 bus generation equals the aggregation of Table 7
device injections by bus.

The user-observed TS failure at `20260719_082442` is not the normal-operation
route: the configured bus-4 fault reaches `fault_on` at 3 s and produces
`|V|=0.039238 pu`, below the unchanged GFL-RMS10
`V_div_min=0.1 pu` balanced-LVRT domain. Runtime therefore correctly rejects
the right-limit transaction with
`ibr:gfl_rms10_model:lowVoltagePowerInversion`. The compact launcher already
labels this choice `Fault only - fail-closed diagnostic (RMS10 LVRT not
ready)` and defaults its event-choice dialog to `No events`. Do not remove the
voltage-domain gate or reinterpret this configured-fault result as an
event-free TS regression.

### Scope already delivered and not to regress

- IBR menu separates `Power Flow`, `SSSA`, `Time-Domain Simulation (TS)`, and
  `Full Analysis`; do not collapse them again.
- GFM/GFL count UI is intended to be available for PF/SSSA/TS, with GFL being
  the complement of selected online IBRs and reference index automatic.
- The report is `docs/source/report_ieee14_ibr_pf_sssa_ts_en.tex`; figures are
  MATLAB-generated vector PDFs from
  `scripts/reporting/render_ieee14_ibr_pf_sssa_ts_matlab_figures.m`.
- Existing Profile B remains SG1 + IBR2 GFM13 + IBR3/6/8 GFL-RMS10, 48 active
  states. Its existing results are not evidence for the new all-GFL route.

## 2026-07-19 — IBR PF/SSSA/TS/Full launcher products

### SG trip-return PF/SSSA comparisons

The compact IBR submenu now also offers additive `Power Flow Comparison` and
`SSSA Comparison` products. Each solves and indexes three stationary points:
`PRE_TRIP`, `SG_TRIPPED`, and `SG_RETURNED`. They publish resource/device/bus
indices, online/mode status, active-state mappings, P/Q/terminal-voltage tables,
and a grouped P/Q/V figure. SSSA spectra are complete per point and explicitly
`NOT_MODE_MATCHED` across operating points. This is distinct from Full Analysis:
it is an operating-point comparison, not a fault/reclose trajectory or physical
acceptance claim.

The RMS10 registered dual-device type was also added to the explicit allowlist
in `mixed_ibr_reduced_initialize`; unknown device types remain fail-closed. No
ODE, state order, parameter, limiter, Jacobian, or numerical tolerance changed.
Targeted evidence on MATLAB R2025a: 14/14 comparison and RMS10 SG-off
equilibrium tests passed. Active dimensions were 48/52/57 and equilibrium KCL
infinity norms were respectively 5.218e-15, 4.582e-11, and 1.465e-14. The SSSA
classification was UNSTABLE at all three points and is retained as a physical
result rather than tuned away. Final broader regression evidence is recorded in
the delivery commit/test record.

The compact `solve_case` flow now selects IBR, the IEEE14 1-SG + 4-IBR case,
then Power Flow / SSSA / Time-Domain Simulation (TS) / Full Analysis. The
interactive IBR launcher defaults to RMS10 Profile B (IBR2 GFM13,
IBR3/6/8 GFL-RMS10), which produces 48 active states from a 98-state fixed
inventory. The GFM/GFL count remains editable; the UI reconciles count,
explicit indices, complementary GFL count, and reference index. Full Analysis
returns separate `pf`, `equilibrium`, `sssa`, and `ts` products, with SSSA and
TS sharing the same equilibrium.  Detailed PF reports, SG+IBR state/eigenvalue
tables with descriptions, and four TS plot products are enabled.  The legacy
WECC code remains only for explicit regression consumers and is not offered by
the compact launcher UI. RMS10 LVRT remains fail-closed/not ready.

PF reporting converts IEEE14 voltage using the in-repository 69-kV base, uses
a linear mismatch plot, and prints per-resource P/Q in pu and MW/MVAr with a
reconciliation against total generation. Targeted evidence: 22/22
numerical/report/plot/SSSA tests, 60/60 launcher tests before the final AUTO
field adjustment, and 14/14 final AUTO UI + IBR sub-analysis tests passed.
Full regression was intentionally not run at the user's request.

## IBR dynamic-equation contract — Phases 0A/1/2/3 (2026-07-18)

**Status:** Phases 0A (source verdict), 1 (Section H core mappings), 2
(standalone modal helper), and 3 (Section H reporting) complete and pushed
to `main` (`0cb65e9`). Phases 0B, 4, 5 remain BLOCKED.
**Branch:** `main`
**Tested commit:** `0cb65e9` (HEAD == origin/main after fast-forward push)

Source-traceable dynamic-equation and state-order contract for GFM-VSG
(REGFM_B1, 13-state) + GFL-PLL (WECC REGC_A/REEC_A, 7-state, PLL-less).
The primary paper (Fu et al. IEEE JESTIE 2024) supports LINEAR_SSSA only;
no nonlinear GFL source is approved. GFL PLL participation is reported as
`NOT APPLICABLE TO CURRENT PRODUCTION MODEL` until Phase 0B approves an
explicit-state GFL source.

### What was delivered (commits 5e7db6d..0cb65e9)

1. **Phase 0A** (`5e7db6d`): frozen source verdict + equation register +
   13/7-state tables + Section H contract + Phase 0B source checklist
   (`docs/project/IEEE14_IBR_DYNAMIC_EQUATION_CONTRACT.md`).

2. **Phase 1** (`d4d1c7d`): IBR-owned metadata registry
   (`+ibr/device_contract_metadata.m`) + state/input inventory snapshot
   (`+ibr/state_inventory_snapshot.m`). Strict device_type/nx/state_names
   registry; GFM 13-state (page+eq citations from NREL/TP-5D00-90260),
   GFL 7-state (WECC block-level provenance), dual 20-state composed.

3. **Phase 2** (`aba4ba2`): standalone no-inv modal helper
   (`+stability/modal_analysis.m`). Read-only consumer of `sssa.A` and
   separately `sssa.physical_A`. Left via `eig(A','vector')`, biorthogonal
   U/conj(alpha), signed participation, deterministic sort + conjugate
   pairs + cluster projectors + physical lift (map-dependent oblique
   attribution, NOT canonical eigenvectors of A). Does NOT modify
   `composite_sssa_model.m` or `Ared` construction.

4. **Phase 3** (`0cb65e9`): Section H report assembler
   (`+ibr/section_h_report.m`) + text renderer
   (`+ibr/render_section_h_report.m`). 12 mandatory log sections + full/
   physical spectrum tables + participation table + TS tables + execution
   counters + convergence summary + `analysis_fingerprint` (canonical
   serialization + SHA-256). Pure read-only consumer: no eig/inv/pinv/
   modal_analysis/state_inventory_snapshot/solver calls. Two shape-guard
   tests added to prevent the cell-array collapse regression.

5. **Cell-index bug fixes** (`0cb65e9`): five sites in
   `+stability/modal_analysis.m` (lines 334, 335, 497, 512, 656) used
   parentheses indexing on cell arrays, returning a cell instead of the
   string content; `strcmp` then mis-compared on ill-conditioned/clustered
   paths. Fixed to curly-brace indexing. Defect record:
   `docs/project/defects/2026-07-18-cell-array-collapse-and-indexing.md`.

### Verification (Phase 3 delivery, commit 80568cf)

- Phase 3 targeted (`test_ibr_section_h_report.m`): **23/23 PASS**
  (20 base + 3 hardening shape guards).
- Phase 2 targeted (`test_modal_analysis.m`): **24/24 PASS**.
- Phase 1+2+3 targeted: **77/77 PASS**.
- Full regression: **1024 passed / 0 failed / 4 incomplete** (the 4
  incomplete are pre-existing `test_pgaz_conversion_contract` assumption
  filters on the external pgaz validation tool, unrelated to this change).
- MATLAB R2026a Update 3 (glnxa64); `matlab -batch` with `pf_init_paths`.

### Phase 3 hardening (commit 80568cf)

Advisor review of the Phase 3 delivery identified four follow-up items;
three were applied in-scope (no contract change), one was deferred to a
new Phase 3.1 task:

1. `canonical_serialize` now errors fail-closed on unsupported types
   (`ibr:section_h_report:unsupportedType`) instead of returning an `'X'`
   placeholder — a fingerprint must not silently drop a value.
2. Fingerprint claims reduced to "change-detection" (not "durable" /
   "MATLAB-version-independent"); `mat2str`/`num2str` formatting can vary
   across MATLAB releases. Stability is asserted only for identical input
   on the same MATLAB version (`test_fingerprint_stable_identical_input`).
3. Three new shape-guard tests: unsupported-type fail-closed,
   `full_state_eigenvalues.rows` is a cell array, `participation.rows` is a
   cell array (regression guards for the `struct()` collapse bug).
4. Defect record corrected: the `struct()` collapse explanation now
   describes comma-separated-list semantics precisely.

Deferred to Phase 3.1 (task #8, separate plan + approval required):
NaN/Inf/−0 representation policy, nested struct depth/cycle handling,
cross-MATLAB-version canonicalization audit.

### Scope and ownership

- Track B owned: `+ibr/**`, `tests/test_ibr_*.m`, `docs/ibr/**`,
  `scripts/ibr/**`.
- Single-owner shared (new file, not an edit to existing shared kernel):
  `+stability/modal_analysis.m` (created in Phase 2 `aba4ba2`; cell-index
  fixes in `0cb65e9`). No edit to `composite_sssa_model.m`, `composite_dae.m`,
  `solve_case.m`, `run_pf.m`, `run_ssa.m`, `run_ts.m`, `pf_init_paths.m`,
  TS kernel/driver, topology/event, or launcher files.
- No production numerical equation, Ared, ABI, schema, or runtime contract
  changed. `IBR_PRODUCTION_INTEGRATION_READY` remains `NOT_READY`.

### GFL-RMS10 reopening + Phases 4/5/6 (2026-07-18/19)

**Status:** Phase 0B reopened as a user-authorized PROJECT_DERIVED RMS10
composite (NOT a complete source-defined GFL). Phases 4/5/6 complete for the
normal-operation slice. Tested commits `7ce08ae` → `5373921`.

The user supplied three textbooks (Yazdani 2010, Teodorescu 2011, Bacha 2014)
that close the nonlinear PLL/current-controller/L-filter core (6 of 10 GFL
states SOURCE_DEFINED). The remaining 4 states (P/Q filters, outer-loop
integrators) and all limiters/anti-windup/LV semantics are APPROVED_PROJECT_DERIVED.
Full provenance: `docs/project/IEEE14_IBR_GFL_RMS10_PROVENANCE.md`;
frozen numerical parameter manifest:
`docs/project/IEEE14_IBR_GFL_RMS10_PARAMETER_MANIFEST.md`.

Final source verdict (honest):
- `SOURCE_DEFINED_NONLINEAR_CORE_CLOSED = YES`
- `FULL_SOURCE_DEFINED_GFL_MODEL = NO`
- `APPROVED_PROJECT_DERIVED_RMS10_SLICE = YES`
- `NUMERICAL_PARAMETER_PROFILE_FROZEN = YES`

What was delivered (commits 7ce08ae → 5373921):

1. **Phase 0** (`7ce08ae`): parameter manifest + provenance doc frozen BEFORE
   production code (stop condition satisfied).
2. **Phase 1** (`7ce08ae`): `+ibr/gfl_rms10_model.m` — 10-state device mirroring
   the WECC/REGFM_B1 generic ABI. Equilibrium verified machine-zero residual
   (~1e-15). LV fail-closed (no PLL freeze). Anti-windup one-sided conditional
   hold. 25 device tests PASS.
3. **Phase 2** (`7ce08ae`): `tests/test_ibr_gfl_rms10_model.m` — 25 falsification
   tests (ABI, equilibrium, kappa, dq/sign, current-plant oracle, PLL ODE,
   P/Q filters, current-priority limit, anti-windup hold/release, vector clamp,
   LV fail-closed, Jacobian FD, no-external-solver grep, fail-closed IDs).
4. **Phase 3** (`dd3af91`): opt-in routing via `params.gfl_family`
   (construction-time). `gfl_model.m` dispatcher; `dual_mode_ibr_model.m`
   23-state layout with distinct `device_type='ibr_dual_mode_rms10'`;
   `device_contract_metadata.m` registers `ibr_gfl_rms10` (10/2) +
   `ibr_dual_mode_rms10` (23-state); `build_ieee14_sg_ibr_devices.m` forwards
   `device_modes(k).gfl_family`; `section_h_report.m` derives GFL-PLL
   applicability from state inventory (APPLICABLE_EXPLICIT_GFL_PLL_STATES when
   an active RMS10 delta_PLL/xi_PLL row is present). Legacy ibr_dual_mode
   (20-state) unchanged (G15); REGFM_B1 GFM unchanged (G16).
5. **Phase 3 tests + Phase 4** (`5373921`): routing/metadata/dual/sssa/ts
   integration tests. Profile B (SG1 + GFM_IBR2 + 3xRMS10) equilibrium
   converges (kcl=2.3e-14); full-KCL SSSA via shared `composite_sssa_model`
   (48 active states, no hand-built A); event-free TS no-drift via shared
   `ts_simulate_composite`; disturbance response finite; limiter transaction
   fail-closed. 133 targeted tests PASS.
6. **m_max fix** (`5373921`): default 1.10 → 1.30. At IEEE14 bus 8 (|V|=1.09)
   the v_t feedforward reached 1.099 > V_t_max=1.10, triggering the vector
   clamp and breaking equilibrium. 30% overmodulation headroom keeps the
   clamp inactive across the normal-operation domain.

Generic-ABI integration contract (user-mandated, FROZEN): GFL-RMS10 plugs
into the existing composite-device ABI used by SG EMF6 and REGFM_B1. No
GFL-specific PF/equilibrium/SSSA-A/TS solvers. PF→equilibrium→SSSA→TS reuse
the shared project-owned kernels. Shared files (composite_dae, composite_sssa,
ts_simulate_*) remain unchanged.

### Remaining (NOT blocked)

- **Phase 5 reporting**: this handoff + decision ledger D18 + frozen contract +
  source matrix + Phase 0B audit reopen + Thai TeX report (GFL-RMS10 as
  primary proposed model). In progress.
- **Phase 6**: full regression `pf_init_paths; r=runtests('tests','IncludeSubfolders',true)`
  once on the final tree (required: changes IBR equations + composite DAE
  routing + equilibrium + SSSA + TS). Then commit + fast-forward push.
- **Phase 3.1** (task #8, deferred): canonical serialization hardening.
- **LVRT/fault TS** is OUT OF SCOPE for this slice. A future LVRT route
  requires a separate authoritative source + approved contract.
  `GFL_RMS10_LOW_VOLTAGE_RIDE_THROUGH_READY` remains false.

### Historical Phase 0B BLOCKED record (superseded above)

The original Phase 0B bounded search (2026-07-18) ended SOURCE_GAP_BLOCKED:
no complete source-defined GFL was found. That remains true. The GFL-RMS10
slice reopens Phase 0B by explicit user authorization of a PROJECT_DERIVED
composite, NOT by discovery of a complete source. Full audit evidence stays in
`docs/project/IEEE14_IBR_PHASE0B_SOURCE_AUDIT.md` (now annotated as reopened
by the PROJECT_DERIVED path).

## Mission C — Characterization handoff (2026-07-17)

**Status:** Characterization phase complete (read-only). Controller-enabled run NOT yet performed.
**Branch:** `main`
**Tested commit:** pending full regression (targeted 18/18 GREEN on `d213d9c`)

Mission C aim: physical SG resync + IEEE14 demo close. Phase 0 audit found no sourced
IEEE14 governor/synchronizer/AVR → binding STOP for physical acceptance.
Proceeding with diagnostic workflow validation (opt-in, ASSUMED_DIAGNOSTIC, NOT VALIDATED).

### What was delivered in this commit

1. **Per-sample resync diagnostics** (`ts_simulate_ibr_hybrid.m:269-328`):
   Pure read-only measurement hook records synchronism state every accepted sample
   during offline coast. `res.resync_diagnostics` struct array with guard margins
   (dV, df, dtheta, signed_margin, limiting_gate), SG state (omega, delta,
   V_open_circuit, Tm, Te, Efd), bus voltage. Zero integration-logic dependency —
   disabled route bit-identical (all 16 prior tests GREEN).

2. **2 RED characterization tests** (`test_ieee14_ibr_sg_reclose_workflow.m:63-106`):
   Record hook fires, no sample eligible with strict guard, df > df_max throughout
   (Tm-frozen coast falsifies natural-reclose hypothesis), signed_margin<0 everywhere.
   18/18 GREEN including all 16 prior tests.

3. **Diagnostic parameter manifest** (`docs/project/diagnostic_synchronizer_parameter_manifest.md`):
   SG plant (Kodsi, EMF6, τ=5.148s). Governor P-only (Kp=20 from 1/R_D, Ki=0) —
   no integral/anti-windup. Exciter: fixed Efd default; Padiyar AVR deferred.
   All gains = ASSUMED_DIAGNOSTIC. Status: REQUIRES_REVISION per advisor.

### Characterization findings (physical)

| Gate | Tm FROZEN | Tm=0 Diagnostic | Verdict |
|---|---|---|---|
| A. Frequency | df>0.001 always FAIL | df<0.001 always PASS | Runback solves df |
| B. Voltage | dV≈0.064>0.05 FAIL | UNKNOWN (may converge) | ~0.014pu excess |
| C. Phase | dθ cycles 0.2s FAIL | dwell feasible at ω<0.00053 (~25s) | ~25s asymptotic |
| D. Base defects | NONE confirmed | NONE | V_open verified real |

- ω₀≈0.073 at sg_on=8.0s (3s coast), ω→∞≈0.164 asymptotically
- 0/501 samples all three margins >0 over 15s → SYNC_TIMEOUT is PHYSICAL
- Analytical ω verified to 1e-8 for Tm frozen; τ=5.148s confirmed
- dV≈0.064 NOT 18 pu (earlier margin/deg misinterpretation fixed)
- dθ = binding gate; Tm=0 alone needs ~25s for ω to decay below dwell threshold
  (ω·377·0.5 < 10° → ω<0.00053)

### Missing contracts

1. **Diagnostic timeout profile:** ~30s (τ·ln(ω₀/dwell_ω) + dwell + margin).
   Public sync_timeout=5s unchanged.
2. **Phase-synchronizer contract:** Tm=0 ω decay is asymptotic — active slip
   control or braking could accelerate phase capture.
3. **AVR contract:** Required only if fixed Efd does not converge dV below 0.05pu.

### Next steps

1. **Do NOT run controller-enabled reclose** before manifest revision.
2. **Tm=0 passive characterization run:** verify dV trajectory with fixed Efd
   over ~30s horizon, confirm ω matches analytical oracle, record dθ dwell stats.
3. If dV converges <0.05: no AVR. If not: integrate Padiyar AVR (diagnostic limits).
4. If ω/timing unacceptable: active slip control or separate opt-in timeout.
5. File allowlist: `ts_simulate_ibr_hybrid.m` + new controller files + tests.
   `sg_composite_device.m` is **read-only** (controller external to EMF6).
6. Before mutation: read `AGENTS.md`, `TRACK_COORDINATION.md`, this handoff,
   plan at `docs/project/plans/`, manifest.

### Flags

- `IBR_PRODUCTION_INTEGRATION_READY = NOT_READY`
- No VALIDATED milestone from diagnostic route
- All diagnostic = ASSUMED_DIAGNOSTIC / NOT PHYSICAL ACCEPTANCE

## Revision 5 — Corrective closure (2026-07-17)

The earlier "936 passed / 8 failed / full regression passed / zero new
regressions" claim was WRONG. `git stash` does NOT revert committed source, so
the 8 `test_ieee14_ibr_ts_event_runner` failures at `7c986f4` were incomplete
schema migration, not pre-existing. Revision 5 closes that gap and the remaining
Phase 4b/5 contracts:

- **Event-runner migration.** Two pinned authenticated tables in `setupOnce`;
  8 physical-intent tests migrated to `event_run_with_table`; 2 new missing-table
  tests assert `stability:gfm_selection:missingTable`. 14/14 GREEN.
- **Validator latent bugs fixed.** `fidi` nested-handle unreachable from
  `manual_branch`; early-return paths did not assign outputs. Both fixed; all
  failure IDs use string concatenation consistently.
- **Production `cand` field bug fixed.** `ts_simulate_ibr_hybrid.m:610` now
  reads the committed selection from the validator output with a schedule-literal
  fallback.
- **Real timers (Step 3).** `assemble_runtime_context` reads `hold_timers`/
  `lockouts` from `hybrid_state`; malformed values fail closed.
- **Validator parity (Step 4).** Identity check for ALL candidates + sanitized-
  key uniqueness; manual branch gains identity + hold/lockout checks;
  `runtime_n_mode_changes` reflects the post-sort winner.
- **Authenticated SG_ON routing (Step 5).** `reselection_transaction` consumes
  an authenticated candidate via `authenticate_sg_on_candidate`; `compute_tdown`
  derives `T_down` from the authenticated candidate's omega.
- **`N_exhaustive_max=4` guard (Step 6).** `ibr_selector_table.m` fails closed
  with `stability:gfm_selection:excessiveUniverse` before enumeration.
- **Unpinned automatic integration (Step 8).** New
  `test_unpinned_automatic_sg_off_integration` asserts the runtime-selected
  candidate + provenance come from the table; SG_ON reports zero feasible.

### Verification (Revision 5)

Targeted gates on the edited tree: selector unit 44/44, event runner 14/14,
reclose workflow 16/16, SG_ON integration 12/12 — **86/86 GREEN, 0 failed,
0 incomplete**. Full regression pending (run once on the final tree per
AGENTS.md risk policy).

### Limitations (Revision 5)

- Automatic selection (unpinned) picks candidate `[5]` (highest margin) on
  IEEE14, which can make post-trip dynamics fail to converge (stepNewton). This
  is an honest outcome of the frozen margin-based ranking policy, not a bug;
  the demo/comparison/solve_case defaults retain the known-stable manual
  `[2 3 4 5]` tuple. A ranking-policy review (margin vs dynamics stability) is
  a separate workstream.
- `IBR_PRODUCTION_INTEGRATION_READY = NOT_READY` (unchanged).



## Validation-closure summary (V0–V7)

All seven phases of the user-defined validation-closure mission completed at
Git HEAD. Evidence follows.

### V0 — Test-discovery diagnosis (root cause)

MATLAB R2026a `TestSuite.fromFile` reported `MATLAB:unittest:TestSuite:NonTestFile`
for `test_ibr_index_selected_gfm_commit`, `test_ieee14_ibr_ts_event_runner`,
and `test_ieee14_1sg_4ibr_phaseEF`. Root cause: a killed diagnostic agent had
run `pcode` from the repo ROOT, creating root-level `.p` shadows. After
deleting the `.p` files, MATLAB's function-resolution cache still held stale
references (`Which -all` pointed to ghost paths). The fix is:

```matlab
restoredefaultpath; cd(repo); pf_init_paths; addpath(fullfile(pwd,'tests'));
clear functions; rehash; rehash toolboxcache;
```

Verification: after the cache-clear sequence, `TestSuite.fromFile` discovered
all files correctly (15/13/12/6 tests). Confirmed zero `.p` files in the
repo (`find . -name '*.p'` = 0). The non-ASCII-comment and parentheses-in-
declaration hypotheses were dis proven (34 test files have UTF-8 comments and
all pass). Rule: NEVER run `pcode` from the repo root; if parse-checking is
needed, `pcode` into a temp dir.

MATLAB version: R2026a Update 3 (26.1.0.3276743) 64-bit (glnxa64).

### V1–V4 — New acceptance test files

Four test files totalling 60 tests created, all passing:

| File | Tests | Description |
|------|-------|-------------|
| `tests/test_ibr_selector_table_unit.m` | 22 | Synthetic authenticated table (hash, ranking, finger print, schema) |
| `tests/test_ieee14_ibr_sg_reclose_workflow.m` | 16 | Two-phase reclose transaction through public entry points |
| `tests/test_ieee14_ibr_sg_on_integration.m` | 10 | Real IEEE14 selector (SCR + equilibrium + SSSA gates) |
| `tests/test_ieee14_ibr_switching_comparison.m` | 12 | Comparison runner semantics + real 15 s runner |

### Production bugs detected and fixed (3 defects)

Validation tests detected three production defects:

1. **FNV-1a hash modular-multiply saturation** (`+stability/ibr_selector_table.m`):
   MATLAB `uint32 * uint32` is SATURATING (clamps at 0xFFFFFFFF), not modular.
   Fixed by using `uint64` intermediate: `product = uint64(h) * 16777619; h = uint32(bitand(product, uint64(4294967295)));`
   Independent oracle: FNV-1a specification (the FNV-1a non-cryptographic hash,
   distinct from RFC 4122 UUIDs). Gates confirmed
   fingerprint changes with topology/dispatch/resource-order, never `ffffffff`,
   deterministic.

2. **Undefined variable `event_context_history`** (`+stability/ts_simulate_ibr_hybrid.m`:
   line 363-364): local reference to `event_context_history` which was never
   defined. Fixed: `event_context_history` → `res.event_context_history`.

3. **Dead-code crash in comparison plot** (`+stability/plot_ibr_switching_comparison.m`:
   line 87): `fig.Children(k)` loop crashed under `tiledlayout` (only 1 child).
   Fixed: removed dead loop, direct axes handles `[ax1 ax2 ax3 ax4 ax5 ax6]`,
   `add_event_markers()` function with `scheduled/committed/rejected` colors/styles.

4. **Brace indexing test bug** (`tests/test_ieee14_ibr_switching_comparison.m`:
   line 242): `metrics{k}` on a struct object. Fixed: `fn = fieldnames(metrics);
   for k = 1:numel(fn), m = metrics.(fn{k}); end`. Also `metrics(2).* →
   metrics.(fn{2}).*` and `metrics(3).* → metrics.(fn{3}).*`.

### Corrective audit fixes (C0–C7, 2026-07-16)

An independent audit after V0–V7 closure found production defects and weak
tests. The corrective pass applied and verified:

- **C0** (`run_hybrid_case.m`): `automatic_gfm_switching` normalization/conflict/
  type validation moved BEFORE device build + equilibrium; non-scalar/non-boolean
  values fail closed (`run_hybrid_case:automaticGfmSwitchingInvalidType`);
  conflict returns `run_hybrid_case:automaticGfmSwitchingConflict` without
  wasting build work. Overrides (`synchronism_overrides`/`delays_overrides`)
  propagated from both top-level and nested `ibr_events` (nested precedence).
- **C1** (`ts_simulate_ibr_hybrid.m` + new `+stability/per_island_vf_check.m`):
  per-island VF check extracted into a pure helper (no algebraic solve, no
  composite-DAE dependency); `trip_transaction` calls it; Scenario-B bit-identity
  verified.
- **C4** (`ts_simulate_ibr_hybrid.m`): `mark_transaction_left` helper back-patches
  continuous→left + tx_id; reclose/reselection share group_tx_id with right
  sample; `NO_MODE_CHANGE_REQUIRED` publishes no right sample; `res.transaction_id`
  published.
- **C2** (`plot_ibr_switching_comparison.m`): returns `[plot_path,
  marker_metadata]`; `event_markers` typed by `log.type`; no fabricated timeout
  marker at `requested_sg_on_time`.
- **C5/C6**: weak `isfield` skip gates strengthened; tautological `unique(t)`
  replaced by composite-key `(t, sample_side, transaction_id)`; deterministic
  field names `metrics.B`/`metrics.C_natural`.
- **Phase 5 (C-workflow KCL)**: diagnosed via instrumentation
  (`reclose_left_state_diag`); relaxed guard passes at non-synchronous state
  (SG omega ~0.07 pu); right-limit KCL correctly fails closed (preserved, not a
  defect). Transaction-level equilibrium-consistent reclose mechanics proven
  separately (`right_kcl_norm < 1e-6`). No KCL solve added to the guard.
- **Phase 6 (Scenario-A metrics)**: no-event path now publishes `u_history`
  (= `eq.u_eq` repeated), `bus_voltage_magnitude` (read-only reconstruction),
  `sample_side`, `transaction_id`. Core fields bit-identical. Device-level
  diagnostics requiring device reconstruct remain a documented gap.

### Regression evidence

| Stage | Passed | Failed | Incomplete | Notes |
|-------|--------|--------|------------|-------|
| V5 targeted regression | 107 | 0 | 0 | 9 targeted files |
| V6 full regression | **914** | **0** | **0** | 673.5 s, all baseline incompletes resolved |
| Prior baseline (pre-push) | 800 | 0 | 4 | `2ac62d1` tree |

Baseline incomplete set resolved: the 4 previously documented baseline
incomplete tests were corrected during Phase 1-7 implementation commits
and no longer appear.

### Comparison runner metrics (V4 real runner)

`run_ieee14_ibr_switching_comparison()` executed under both V6 regression
(673.5 s wall-clock):

| Scenario | Converged | Failure ID |
|----------|-----------|------------|
| A (Normal) | true | — (voltage metrics finite; device-level metrics gap documented) |
| B (No firmware) | false | noVoltageFormingSource |
| C-natural | true | SYNC_TIMEOUT |
| C-workflow | false | recloseTransaction (right-limit KCL infeasible at non-synchronous state) |

Artifacts: 3 PNGs under `output/plots/` + 87 MB .mat under `output/comparison/`.
C-natural SYNC_TIMEOUT confirms the physical timeout claim. C-workflow
fail-closed at `recloseTransaction` is correct behavior. Observed at the
failed close: nonzero SG speed deviation, relaxed guard acceptance, and a
rejected right-limit KCL. Inferred from the EMF6 breaker/current-injection
equations: closing at that state introduces an incompatible stator-current
injection. **The current jump was not directly measured** (the transaction
was rejected, so no committed post-close state exists to measure against; the
diagnostic records rotor state, bus voltage, guard margins, and the right-limit
residual, but never computes stator current). This is NOT a defect. The
transaction-level equilibrium-consistent reclose mechanics are proven
separately in `test_ieee14_ibr_sg_reclose_workflow` (`right_kcl_norm < 1e-6`).

### MATLAB invocation note (observed, bounded)

In this environment, pipe-mode sessions (`cat script.m | matlab -nosplash
-nodesktop`) hung or crashed during shutdown, and a leftover GUI MATLAB session
could cause subsequent `matlab -batch` invocations to exit non-zero without
producing output. This is observed, bounded environment behavior, NOT a
confirmed MATLAB memory-corruption bug and NOT a logic defect. The working
invocation is `/home/birds/bin/matlab -nodesktop -nosplash -batch "run('script.m')"`
preceded by `pkill -9 -f matlab` when a GUI session is lingering. Every test
invocation begins with the cache-clear sequence (`restoredefaultpath; cd(repo);
pf_init_paths; addpath(fullfile(pwd,'tests')); clear functions; rehash; rehash
toolboxcache;`).

## Delivered runtime path

```text
case/resource table
  -> configurable initial GFL/GFM composition
  -> project-owned PF warm starts
  -> all-KCL mixed equilibrium
  -> optional SCR/equilibrium/full-state-SSSA selector
  -> shared coupled trapezoidal step
  -> exact event landing and atomic right-limit transaction
  -> device-owned GFL<->GFM transfer
  -> SG synchronism dwell/reclose or fail-closed timeout
  -> three comparison figures + index/work-count log
```

Implemented models/layouts are: WECC REGC_A/REEC_A GFL (7 states),
REGFM_B1 G2 GFM (13 states), and a 20-state dual-mode superset
(`GFM=1:13`, `GFL=14:20`). The IEEE14 mixed case has 6 SG states plus four
dual-mode IBRs, 86 states total.

The active-bound equilibrium layer uses its locked outer active set. The TS
event supervisor does not duplicate a trapezoidal residual/Jacobian: event and
no-event routes call `stability.ts_step_composite`.

## Configuration and log contract

The IBR launcher is available programmatically and through the analysis/case
dialogs in `solve_case`. IBR controls appear only for the IBR analysis. Users
may set normal-operation GFM/GFL counts, exact initial GFM indices/reference,
fault external bus and impedance, the independent `fault_on`, `fault_clear`,
`sg_trip`, `sg_on` times, exact post-trip GFM indices/reference, timestep/end
time, and plot options.

Count-only GFM selection calls the full selector; it never selects a first
device implicitly. Explicit indices are capability/cardinality checked. Every
initial/event/reclose snapshot logs online SG/GFM/GFL counts and indices,
device ID/external bus/mode/online flag, global state range, active local and
global indices, and all-KCL residual. The execution summary separates PF,
equilibrium, SSSA, and TS invocations from Newton iterations, TS step attempts,
accepted steps, and event transactions.

The SSSA launcher prints `FULL STATE EIGENVALUES` for every case. Rows use
two-digit numbering and two-decimal scientific notation. Display ordering
never changes the computed eigenvalue set.

## Event and plot contract

- Fault topology is `Yfault(fb,fb)=Ypre(fb,fb)+1/Zf`.
- Scheduled events land exactly and publish left/right samples.
- SG trip, mode transfer, and algebraic right limit are one atomic transaction;
  failure rolls back without a false right-side sample.
- The active-state partition is recomputed after every committed mode/online
  change.
- SG reclose preserves SG differential state and commits only after the
  phasor-voltage/pu-slip guard and dwell pass; otherwise it remains offline or
  times out explicitly.
- `plot_ibr_ts_results` creates exactly two PNGs from audited result fields:
  frequency/voltage and device P/Q/current, with labeled event times.

## Fresh focused evidence

- REGFM G2 differential-angle and physical-spectrum focused gates: `36/36`
  passed.
- Hybrid event, plot, and launcher/UI gates: `22/22` passed; plotting contract
  subsequently rechecked at `4/4` after timeout-marker clarification.
- IEEE14 IBR 15 s event run: `1500/1500` accepted steps, 4324 Newton
  iterations, maximum step residual `8.92e-9`, and `converged=true`.
- Four-GFM post-trip equilibrium KCL norm: `4.58e-11`; 52 complete raw roots
  and 43 physical decision roots, `Omega_physical=-1.48281 1/s`.
- MATPOWER case14 production launcher: PF converged in 5 iterations at
  `6.34e-15 pu` mismatch; SSSA printed all 10 roots; 15 s TS accepted
  `1500/1500` steps with zero non-converged steps and maximum corrector
  residual `5.84e-9`.

Fresh targeted delivery gates passed `84/84`; the partial-failure plotting and
launcher repair gate subsequently passed `26/26`. A repository-wide run on the
pre-repair tree reported `821 total`, `815 passed`, `2 failed`, and
`4 incomplete`. Both failures were stale launcher-test assumptions: one
incorrectly required SSSA evaluation after every selector candidate had
already failed the independently audited SCR/equilibrium gates, and one used
the newly approved 15 s launcher default while retaining a 10-step oracle.
Those tests were corrected against the selector trace and an explicit
0.1 s/0.01 s fixture, then passed in the targeted repair gate. Per explicit
user instruction, the full suite was not rerun after those test-only repairs.
The prior committed full baseline remains `804 total`, `800 passed`,
`0 failed`, `4 incomplete`.

## Honest limitations and readiness

The selector evaluates the correct post-trip context (SG breaker open) and the
four-GFM candidate satisfies frozen `gamma_req=0.1 s^-1` on the physical
tangent spectrum. The complete raw spectrum is still retained for reporting;
locked active-bound directions and the common PLL rotational gauge are
removed before the physical eigenproblem, never by deleting roots afterward.

The SG reclose / reference-handover workflow is now a two-phase transaction
(Phase 11 contract):
- **Phase 1** (synchronism-qualified breaker close): closes the SG breaker
  without resetting SG rotor angle/speed; restores the authenticated
  `pre_event_input`; returns reference ownership to the reclosed SG
  atomically (`reference_owner_indices` = SG; `gfm_reference_resource_indices`
  = empty); updates `committed_config_fingerprint` ONLY (never
  `selector_table_fingerprint` or `pre_event_input_fingerprint`); IBR modes
  unchanged; one right-limit solve; one right sample. Full-KCL TS
  formulation unchanged (reference handback is supervisory, not a KCL/slack
  change).
- **Phase 2** (delayed indexed reselection): looks up the precomputed
  authenticated SG_ON table; derives `T_down` from `Omega_target`
  (`T_settle = ln(1/rho)/(-Omega_target)`; `T_down = max(T_minimum_hold,
  T_settle)`); after hold/guard/lockout, applies the selector-chosen
  GFM->GFL transitions via device-owned transfer maps; one final right-limit
  solve; one right sample. No-mode-change case (`NO_MODE_CHANGE_REQUIRED`)
  skips transfer/right-limit/sample. Rejected Phase 2 does NOT roll back
  Phase 1.

Three distinct fingerprints (F1): `selector_table_fingerprint` (immutable for
the run), `committed_config_fingerprint` (atomic per accepted config),
`pre_event_input_fingerprint` (immutable). Multi-island reference-ownership
schema: `reference_owner_indices` / `gfm_reference_resource_indices` /
`reference_island_ids` (sorted by island ID, equal cardinality); legacy
`reference_resource_index` is a read-only single-island alias.

`sg_breaker_trip` / `optional_gfm_commit` split (C3/F2): when
`automatic_gfm_switching=false`, the SG breaker opens but no GFM is
committed; a per-island voltage-forming-source check runs before Newton; if
no online voltage-forming resource exists, fail closed
`noVoltageFormingSource`, publish NO right-limit sample, trajectory ends at
the event-left sample.

IEEE14 demo defaults updated: `fault_on=3.0`, `fault_clear=3.1`,
`sg_trip=5.0`, `sg_on=8.0` (earliest reconnect request), `t_end=15.0`.
Synchronism gating retained: SG must not close merely because `t=8.0 s`.

Natural IEEE14 synchronism is expected to time out (`SYNC_TIMEOUT`,
physical evidence). A separate C-workflow variant uses a declared relaxed
test-guard to exercise the full reclose/handback/reselection path; it is
labeled `ASSUMED_DIAGNOSTIC / NOT PHYSICAL ACCEPTANCE` and is never claimed
as natural IEEE14 reclose evidence. Under the relaxed guard
(`dV_max=10, df_max=10, dtheta_max=180` with angle wrapping), the dynamic
C-workflow reclose fires at a physically non-synchronous state (SG rotor
omega ~0.07 pu, i.e. ~4 Hz, after coasting offline for ~3 s); the atomic
right-limit KCL solve correctly rejects this and fails closed
(`ts_simulate_ibr_hybrid:recloseTransaction`). Observed at the failed close:
nonzero SG speed deviation, relaxed guard acceptance, and rejected KCL.
Inferred from the EMF6 breaker/current-injection equations: closing at that
state introduces an incompatible stator-current injection. **The current jump
was not directly measured.** This fail-closed behavior is preserved and is NOT
a defect. The transaction-level equilibrium-consistent reclose mechanics
(breaker close → right-limit KCL → commit → reference handback) are proven
separately in
`test_ieee14_ibr_sg_reclose_workflow` where reclose starts from a
synchronous state (`right_kcl_norm < 1e-6`). No KCL/Newton solve was
added to the synchronism guard (it remains a separate layer); no tolerance
or physical parameter was relaxed.

A four-trajectory comparison runner
(`scripts/run_ieee14_ibr_switching_comparison.m`) produces three audited
figures: main physical-evidence (A/B/C-natural), workflow-validation
(C-natural vs C-workflow), and delay comparison (C-workflow-delay-on vs
C-workflow-delay-off). Scenario B (no firmware) fails closed honestly at
its genuine failure point; its trajectory is NEVER extended to 15 s.

```text
IEEE14_IBR_GFL_MODEL_READY       = STRUCTURAL_ONLY
PHASE_G2_LIMITER_READY           = G2_IMPLEMENTED
IBR_EVENT_RUNNER_READY           = IMPLEMENTED_TWO_PHASE_RECLOSE_FAIL_CLOSED
IBR_PRODUCTION_INTEGRATION_READY = NOT_READY
```

Full-regression count after validation closure: **922 passed / 0 failed /
0 incomplete / 0 errored** (R2026a Update 3, `matlab -nodesktop -nosplash
-batch`, cache-clear sequence applied). The final numerical full-tree gate
was run on tested source SHA-A `df5f97d`: **922 passed / 0 failed / 0 incomplete
/ 0 errored**. Final delivery SHA-B `f928fd8` contains documentation-only
changes. This 922 is distinct from the targeted gates below:

- **V5 validation-closure targeted regression**: **107/0/0** across 9 targeted
  files (the final validation-closure gate, distinct from the full regression).
- **C0–C7 corrective-pass targeted regression**: **80/0/0** across 7 targeted
  files (`test_ieee14_ibr_switching_comparison`,
  `test_ieee14_ibr_sg_on_integration`, `test_ieee14_ibr_sg_reclose_workflow`,
  `test_ieee14_ibr_ts_event_runner`, `test_ieee14_1sg_4ibr_phaseEF`,
  `test_ibr_ts_plotting_absolute`, `test_no_external_solver_dependency`).

All four previously documented baseline incomplete tests are resolved.

Remaining blockers remain natural synchronism/reclose evidence and independent
validation (both out of scope for this validation-closure mission). No
external solver is reachable from production.

### Commits

- Implementation: 6 commits (`d7e7bcb`..`74b51e3`) implementing two-phase
  reclose, multi-island reference-ownership, precomputed selector table,
  `automatic_gfm_switching`, IEEE14 demo defaults, comparison runner.
- **Validation closure**: 1 commit fixing 3 production defects (FNV hash,
  `event_context_history`, dead-code plot) + brace-indexing test fix + 4 new
  test files (60 tests) + updated handoff.

Branch: `main`. HEAD == `origin/main` after fast-forward push.

## Preserved local material

`docs/text/`, `docs/probes/ieee14_ibr_phaseG/`, the local Thai report source/
PDF, and the archived font/resource file are committed validation/provenance
material by explicit user instruction. They remain unreachable from
production and `pf_init_paths`.

## Analysis Wizard UI (2026-07-19)

**Status:** Wizard backend delivered; compact legacy-style dialogs restored as
the default interactive surface after desktop review. Full regression was
stopped by user request; focused verification is recorded below.
**Branch:** `main`
**Doc:** `docs/project/IEEE14_ANALYSIS_WIZARD.md`

`solve_case.m` refactored into a thin wrapper (Extract + delegate). The
wizard UI (base-MATLAB `figure`/`uipanel`/`uicontrol`, NOT uifigure) and
the programmatic path both route through the SINGLE shared dispatcher
`wizard.dispatch_analysis` (G4). Pure logic lives in `+wizard/*`
(headless-testable); page/render builders live in nested packages
`+wizard/+pages/*`, `+wizard/+render/*`.

Frozen contracts preserved across the refactor (characterization tests
18/18 green before AND after):
- programmatic ABI (name-value `analysis`/`case`/`options`);
- stable analysis IDs (`pf`/`sssa`/`ts`/`ibr`; no `ibr_ts`);
- per-analysis result schemas; launcher sub-struct; execution_summary;
- error IDs (`solve_case:analysis`, `solve_case:case` preserved, not relaxed
  to `wizard:*`);
- log-file tokens (`PF VERIFICATION`, `STATUS: COMPLETE`, etc.);
- partial invocation: partially specified calls open the wizard with
  selections pre-populated and NEVER auto-execute (raise
  `MATLAB:hg:NonInteractiveFunctionSupport` in batch, matching the old
  `listdlg` behavior);
- events=false reaches the production IBR runtime as an ACTUALLY empty
  schedule (distinct slim 17-field schema vs 58-field events-on; empty
  `events`; all-zero per-sample `transaction_id`; zero `event_transactions`).

IBR settings dialog moved verbatim from `solve_case.m` into
`+wizard/ibr_settings_dialog.m` (base-MATLAB three-column contract
unchanged; `test_ibr_launcher_settings_ui.m` contract checks green, source
location updated). `run_ts.m` NOT edited (correction #7).

Generic 12-section view model (`wizard.adapt_result`) for ALL analyses;
IBR Section H producer reused ONLY through the explicit
`wizard.adapt_ibr_section_h` adapter (PF/SSSA/TS return `not_applicable`).

### Tests (headless)

- `tests/test_wizard_characterization.m` — 18 (frozen ABI, before/after refactor)
- `tests/test_wizard_pure_layer.m` — 29 (registry/discover/defaults/build/validate)
- `tests/test_wizard_dispatch.m` — 15 (dispatch + adapt_result + config_io)
- `tests/test_wizard_section_h_adapter.m` — 6 (Section H adapter)
- `tests/test_wizard_ui_smoke.m` — 21 (real hidden-figure renderer and navigation)
- existing launcher tests (`test_ibr_launcher_settings_ui.m`,
  `test_ibr_launcher_configuration_logging.m`, `test_solve_case_launcher.m`)
  — 16 green

The default `solve_case()` path is now `wizard.legacy_show`: compact analysis
and case list dialogs followed by method-specific editable settings. It uses
the same `wizard.build_request` / `validate_request` / `dispatch_analysis`
backend as programmatic calls. The six-page UI is non-default. Desktop defects
in its footer, initial-case commit, Events navigation, and blank Results page
were corrected as fallback hardening (`UI-2026-07-19-01`).

Focused final-tree evidence: legacy backend Code Analyzer 0 issues; launcher
and dispatcher tests 31/31; hidden-figure wizard smoke 21/21; broader focused
wizard/launcher suite 66/66. No failed or incomplete targeted tests. No
numerical equation, parameter, tolerance, solver, or result schema changed.
Full repository regression was intentionally not rerun by user request.

