# PF/TS Multi-Method Architecture Plan

**Status:** PLAN_ONLY → P0–P3 package-level + P3.5 contract closure authorized.
No production code, SSSA, PF/TS equations, cases, tolerances, launchers, tests,
or defaults were changed. No push/merge occurred. All method status flags remain
NOT_STARTED/PLAN_ONLY:
`PF_FDPF_READY`, `PF_BFS_READY`, `TS_BACKWARD_EULER_READY`, `TS_RK4_READY`,
`TS_ESDIRK_READY`, `PF_TS_MULTIMETHOD_READY`.

**Ownership route (binding, per user correction): PACKAGE-ONLY.** Factories and
solvers are CORE_ONLY / NOT_ROUTED. `solve_case.m`, `ts_simulate.m`,
`ts_adaptive_driver.m`, and other dirty/single-owner files are NOT modified.
Production routing readiness remains **NOT_READY** until the single-owner
integration files are separately resolved. P4 (Backward Euler) starts only
after P3.5 passes. `PF_TS_MULTIMETHOD_READY` and user-selectable production
routing are NOT claimed while single-owner files remain unresolved.

**Branch/worktree/base (to be created on approval):**
- branch: `plan/pf-ts-multimethod` (does NOT exist yet — verified)
- worktree: `/home/birds/Documents/Power-flow-pf-ts-method-plan` (does NOT exist yet — verified)
- base: `31a211d` (verified reachable from `feature/ibr-interface-foundation`; NOT reachable from `main=f59076f`; `git rev-list --count f59076f..31a211d = 16` commits ahead of main; carries Track A IBR interface foundation)
- no push, no merge, no `git reset --hard`, no `git clean`, no history rewrite
- **Regression count is NOT predeclared.** A fresh clean baseline must be run on
  the new worktree (clean checkout from `31a211d`, NOT the dirty worktree) and
  the observed passed/failed/incomplete counts recorded before any code change.

---

## Context

The repository has a single hard-coded PF method (Newton–Raphson) and a single
TS integrator (implicit trapezoidal). The TS option field `opt.method` is
**metadata-only**: it is recorded in results but never dispatched — every step
calls `ts_step_kernel`, which is canonical trapezoidal. This plan introduces a
selectable, fail-closed multi-method architecture for PF (FDPF-XB, FDPF-BX,
BFS radial) and TS (Backward Euler, RK4, sourced ESDIRK32) while:

- preserving the canonical NR and trapezoidal paths **bit-identical (AbsTol=0)**;
- leaving `ts_step_kernel` untouched (no giant method switch inside it);
- leaving SSSA entirely untouched (it stays on its existing NR route);
- keeping every new method in-house MATLAB (backslash/lu/qr/eig only, no
  `inv`/`pinv`/`fsolve`/`optim*`);
- failing closed on unknown names and unsupported topologies (no silent
  fallback to NR or trapezoidal).

The intended outcome: a user can pass `pf_options.pf_method='fdpf_bx'` or
`ts_options.integrator='backward_euler'` and the framework selects, validates,
records, and runs the correct in-house method — with the default paths
unchanged.

---

## 1. Executive summary

PF dispatch is a single line (`solve_case.m:87`); TS dispatch is the
`ts_step_kernel` call (6 sites). The plan inserts two **thin, fail-closed
factories** at these two boundaries:

- `pfsolver.pf_method_strategy(name)` → returns a struct with `.solve`
  function handle and `.name`/`.capability`. Default `'newton_raphson'`
  wraps the existing `powerflow_newton_raphson` verbatim → bit-identical.
- `stability.ts_integrator_step(opt)` → returns `@ts_step_kernel` /
  `@ts_step_be` / `@ts_step_rk4` / `@ts_step_esdirk32`. Default
  `'trapezoidal'` returns `@ts_step_kernel` → bit-identical.

`ts_step_kernel` and `powerflow_newton_raphson` are **not modified**. New
methods are sibling files sharing the existing strategy struct
(`validate_ts_strategy`), shared primitives (`ts_algebraic_solve`,
`ts_algebraic_solve_u`, `ts_jac_y_fd`, `eval_input_provider`,
`ts_event_transition`, `ts_topology_at`), and `pf_prepare_case` /
`pf_build_results` for PF. The adaptive driver is generalized by a **method-
specific adaptive DAE error contract** (binding, per user correction —
generalizing only `p/denom/exp` is insufficient), specifying per integrator:
- **differential estimator:** step-doubling `(x_halfhalf-x_full)/denom` (trap,
  BE, RK4) OR embedded `b_hat-b` difference (ESDIRK);
- **algebraic estimator/discrepancy:** how the algebraic error is estimated
  (`(y_halfhalf-y_full)` for step-doubling; stage-residual or embedded for
  ESDIRK) — declared per method;
- **algebraic residual gate:** `alg_res <= g_tol` accept condition (existing
  `ts_adaptive_driver.m:178`), unchanged semantics, applied to the method's
  final-stage residual;
- **controller order:** `exp_ctl=1/(p+1)` per method (trap 1/3, BE 1/2, RK4
  1/5, ESDIRK per embedded order);
- **cache/stage rollback:** on reject, restore `x, y, Jyy/cache, topology-
  local mutable state` exactly (existing pattern); for multi-stage methods
  (RK4/ESDIRK) all intermediate stage state is discarded, not partially
  retained.
The driver branches once: `if has_embedded_estimator, use embedded; else,
step-doubling`. This is a 2-branch if/else, not a per-method switch.

**Recommended first slice:** P0 (option contract + factories, no new methods)
→ P2 (FDPF-XB + FDPF-BX) → P3 (radial BFS) → P5 (Backward Euler) → P6 (RK4,
diagnostic) → P7 (ESDIRK32, after source approval).

**User decisions captured:** FDPF = both XB and BX; BFS = radial-only
fail-closed; TS slice = all three integrators in separate phases; PF in TS =
keep TS on NR until PF methods mature. Two remaining recommendations to
confirm at implementation start: advanced methods (BDF/Radau/Rosenbrock-W)
= defer all; UI timing = defer until methods validated (dirty launchers
are user-owned and must not be touched).

---

## 2. Current repository/worktree state

- `main` HEAD = `f59076f` (Power-flow working dir, dirty with user-owned
  changes to `ts_simulate.m`, `run_ts.m`, `solve_case.m`, `plot_ts_result.m`).
- `feature/ibr-interface-foundation` tip = `31a211d` (worktree
  `/home/birds/Documents/Power-flow-ibr-interface`, also dirty with the same
  4 user-owned files — these are read-only for planning).
- `31a211d` is NOT reachable from `main`; `merge-base(31a211d, main) = main`.
- `git rev-list --count main..31a211d = 16`. Full regression count is **NOT
  predeclared** — only the fresh clean-worktree result (run in this session)
  is recorded as the baseline.
- The 4 dirty files do **not** touch PF dispatch: `solve_case.m:87` (dirty)
  still reads `result=pfsolver.powerflow_newton_raphson(case_data,opt)`;
  `ts_simulate.m` dirty changes only a verbose `fprintf` message (verified
  by `git diff`). A clean branch from `31a211d` will NOT carry these dirty
  changes, so the canonical PF/TS paths equal `main`'s paths.

**Dirty-file / single-owner ownership (binding, per user correction):**
`solve_case.m` and `+stability/ts_simulate.m` are BOTH user-owned dirty files
AND on the `TRACK_COORDINATION.md:114-130` single-owner list. The plan does
NOT claim `solve_case` method selection works before the integration owner is
resolved. Two options, to be chosen at implementation start:
  (a) checkpoint/cherry-pick the owner's dirty changes first, then edit; or
  (b) keep P0/P3 at **package-level only** (`+pfsolver/`, `+stability/` new
      files + factory functions) and defer the `solve_case.m:87` /
      `ts_simulate.m` wiring until ownership is assigned.
Until ownership is resolved, the factories exist and are tested in isolation
(called directly, not through `solve_case`/`ts_simulate`), and NO claim is
made that production dispatch routes through them.

**Verified not pre-existing:** `plan/pf-ts-multimethod` branch and
`/home/birds/Documents/Power-flow-pf-ts-method-plan` worktree path. If either
exists at implementation time, STOP and report (do not delete/rewrite).

---

## 3. Current PF call graph (file:line on `31a211d`)

```
run_pf.m / solve_case('analysis','pf')
  -> solve_case.m:87  result=pfsolver.powerflow_newton_raphson(case_data,opt)   [HARD-CODED, no method dispatch]
       -> powerflow_newton_raphson.m:1  (outer Q-limit loop L37-80)
            -> pf_prepare_case (internal/core): builds model + Ybus (L156-188)
            -> solve_model (L106+): mismatch (pf_calculate_mismatch), Jacobian, J\mismatch (L212), x=x+delta_x (L228)
            -> convergence: max(abs(mismatch))<tol (L170, inf norm, tol=1e-10)
            -> Q-limit switching: find_q_limit_violations (L290-308); PV->PQ bus_data(:,2)=3 (L72), Qgen fixed (L73)
       -> pf_build_results (internal/core/pf_build_results.m:36-88): ~40-field result struct
       -> results.q_limit_switching attached (L86-90)
```

PF option struct (`solve_case.m:45-47`): `verbose, plot_results, max_iter=50,
tolerance=1e-10, enforce_q_limits=true, q_limit_tolerance=1e-6,
max_q_limit_switches=20`. **No `method` or `pf_method` field.**

PF result schema consumers (SSSA + TS):
`pf.converged`, `pf.bus_voltage`, `pf.bus_angle_deg`, `pf.P_generation`,
`pf.Q_generation`, `pf.external_bus_ids` — consumed at
`+stability/ts_simulate.m:78,94,102`; `+stability/emf6_dae.m:23,29`;
`+stability/synchronous_emf6_ssa.m:17,94,109,111,121,197,199,204`;
`+stability/padiyar_model11_dae.m:19,22-23,66,80,82-83,91,193,195,203`;
`+stability/classical_sssa.m:22,33`.

Bus types: internal `1=REF, 2=PV, 3=PQ` (`pf_prepare_case.m:23-25,139-141`);
MATPOWER `3/2/1`; conversion `+cases/mpc_to_case.m:23`. External bus IDs →
matrix rows via `ismember` (`pf_prepare_case.m:16-20`); row index = `bus_data`
row; permutation-invariant (`tests/test_pf_contract.m:167-198`).

line_data 7-col `[From To R X B_half TapRatio PhaseShiftDeg]`. Ybus
(`pf_prepare_case.m:156-188`): `y_series=1/(R+1i*X)` (L174);
`y_shunt=1i*B_half` (L175); complex tap `tap=tap_ratio*exp(1i*deg2rad(phase_shift))`
(L173); off-nominal taps L177-180; bus shunts cols 9-10 at L183-187; parallel
branches accumulate via `+=`.

PF load model = **constant power only** (no ZIP in PF). PF convergence = inf
norm, no line search/damping. NR uses backslash ONLY (no `inv`/`pinv`/
`fsolve`) — verified by `tests/test_no_external_solver_dependency.m`.

---

## 4. Current TS call graph (file:line on `31a211d`)

```
run_ts.m / solve_case('analysis','ts')
  -> solve_case.m:98  stability.ts_simulate(case_data,opt)
       -> ts_simulate.m:50-65  model dispatch (padiyar_1_1_* / emf6 / classical inline)
       -> ts_simulate.m:94  pf=pfsolver.powerflow_newton_raphson(...)  [TS uses NR, hard-coded]
       -> ts_model_strategy (per model): builds strategy struct (dae_f, dae_g, jac_y, needs_algebraic_solve, reconstruct, optional provider fields)
       -> stepper dispatch: opt.stepper=='adaptive' -> ts_adaptive_driver ; else fixed-step loop
            fixed-step loop (ts_simulate.m:231): step=ts_step_kernel(strat,x,y,dt_step,Y_now,kopt_cl)
            EMF6 fixed (ts_simulate_emf6.m:147): step=ts_step_kernel(strat,x,y,dt_step,Y_now,kopt)
            Padiyar fixed (ts_simulate_padiyar_model11.m:70): step=ts_step_kernel(strat,x,y,h,Ynow,kopt)
       -> ts_adaptive_driver.m:148,152,156  step_full/step_h1/step_h2 = ts_step_kernel(...)
       -> result reconstruction (ts_simulate.m:265-278)
```

**`ts_step_kernel.m` is canonical trapezoidal with 3 internal paths, ALL
using `x + 0.5*h*(f0+f1)`:**
- legacy 8-arg path (L58-136): adaptive corrector (L82-100, `x_new` L87) /
  fixed corrector (L101-121, `x_new` L107).
- `classical_step` (L139-213): linear-network model, no `ts_algebraic_solve`
  (network solved inside `dae_f`); `x_new` L172/L187.
- `provider_step` (L216-358): R1 provider-aware; `u0=eval_input_provider(...,t0)`
  (L250), `u1=eval_input_provider(...,t0+h)` (L263); `x_new` L271/L291/L318/L333.

**`ts_adaptive_driver.m` constants (hard-coded):** `p=2` (L42), `q=p+1=3` (L43),
`denom=2^p-1=3` (L44), `exp_ctl=1/q=1/3` (L45). Step doubling: full step (L148),
half1 (L152), half2 (L156). LTE `e=(x_halfhalf-x_full)/denom` (L161). Accept
iff `err<=1 && alg_res<=g_tol` (L178). Controller
`factor=min(fac_max,max(fac_min,fac*(1/err)^(exp_ctl)))` (L224). Reject
`dt=h/2` (L241). Fail-closed at `dt_min` (L244-258).

**6 `ts_step_kernel` call sites:** `ts_simulate.m:231`,
`ts_simulate_emf6.m:147`, `ts_simulate_padiyar_model11.m:70`,
`ts_adaptive_driver.m:148,152,156`. Every one is trapezoidal.

**`opt.method` is metadata-only:** validated as always `'trapezoidal'`
(`solve_case.m:370`); written to result metadata
(`ts_simulate.m:267`, `ts_simulate_emf6.m:183`,
`ts_simulate_padiyar_model11.m:96` hard-codes `'trapezoidal'`). It is **never
dispatched**. Confirmed concern C1.

**Shared primitives are method-agnostic (reusable by BE/RK4/ESDIRK):**
`ts_algebraic_solve.m` (damped Newton, `Jyy\g`, line search),
`ts_algebraic_solve_u.m` (provider-aware variant), `ts_jac_y_fd.m` (central FD
`dg/dy`), `ts_event_transition.m` (explicit `event_id`, no `t+eps`),
`ts_topology_at.m`, `ts_prevalidate_events.m`.

---

## 5. Proof that SSSA remains out of scope

SSSA has **3 PF entry points**, all hard-coding NR, all OUT OF SCOPE:
- `+stability/synchronous_emf6_ssa.m:14` → `pfsolver.powerflow_newton_raphson`
- `+stability/padiyar_model11_dae.m:19` → `pfsolver.powerflow_newton_raphson`
- `+stability/classical_sssa.m:22` → `stability.ts_simulate` (which calls NR at `ts_simulate.m:94`)

SSSA builds its **own** `Ynet` from `case_data` (NOT the PF `Ybus`); PF
provides only the operating point (V, theta, P, Q) + `external_bus_ids`. SSSA
contract documented at `docs/SSSA_CONTRACT.md` (Schur reduction
`A=Jxx-Jxy(:,free_y)*(Jyy(free_y,free_y)\Jyx(free_y,:))` at
`multimachine_ssa.m:44`, backslash only; `pinv(T)` at L132 is the COI
reduction pseudoinverse, not an algebraic elimination).

**This plan touches NONE of:** `multimachine_ssa.m`, `multicase_sssa.m`,
SSSA Jacobians, Schur reduction, eigenvalue pairing, vcon
(`multimachine_ssa.m` + `composite_dae.m` on `31a211d`), SSSA model dispatch.
SSSA stays on its existing NR route. New PF methods are TS/PF-only initially;
when (if ever) a PF method is allowed for SSSA init, that is a **separately
approved** change with its own equilibrium-tolerance gate.

---

## 6. Current option/dispatch problems

1. `opt.method` (TS) is recorded in results but never dispatched → every TS
   step is trapezoidal regardless of the string. Misleading metadata.
2. No `pf_method` field exists → PF is unselectable at the option level
   (only the GUI and `benchmark_all_methods.m` hard-code method names).
3. `result.method` is a display label only, not an executed-method record.
4. No fail-closed validation of method names (unknown names silently do
   nothing or default).
5. `ts_adaptive_driver` hard-codes trapezoidal constants — cannot generalize
   to BE (`p=1`) / RK4 (`p=4`) / ESDIRK (embedded) without change.
6. The 3-path structure of `ts_step_kernel` (legacy/classical/provider) is
   trapezoidal-only; a naive "method switch" inside it would duplicate
   provider/classical logic 4× and is forbidden.

---

## 7. PF method source register

| method | source | DOI/loc | classification | readiness |
|---|---|---|---|---|
| Newton–Raphson | project-existing canonical (`powerflow_newton_raphson.m`) | in-repo | PROJECT_DERIVED | READY (baseline) |
| FDPF-XB | Stott & Alsac (1974), IEEE Trans. PAS-93(3), 859–869 | 10.1109/TPAS.1974.293985 | SOURCE_VERBATIM (variant rule) | PLAN_ONLY |
| FDPF-BX | Stott & Alsac (1974), same paper, BX variant | 10.1109/TPAS.1974.293985 | SOURCE_VERBATIM (variant rule) | PLAN_ONLY |
| BFS radial (minimal capability) | Shirmohammadi, Hong, Semlyen, Luo (1988), IEEE Trans. Power Systems 3(2), 753–762 | 10.1109/59.192932 | SOURCE_VERBATIM (radial sweep) | PLAN_ONLY |
| BFS weakly-meshed compensation | same 1988 paper, §compensation | 10.1109/59.192932 | DEFERRED_SOURCE_REQUIRED | NOT_STARTED (separately approved) |

FDPF conceptual iteration (to be derived and sign-mapped, NOT copied
verbatim): `B'·dθ = ΔP/|V|`; `B''·d|V| = ΔQ/|V|`. Exact B'/B'' construction,
row/column sets, and sign mapping to the project Ybus convention
(`pf_prepare_case.m:156-188`) must be derived from the full Stott-Alsac
paper. **MATPOWER is validation evidence only, not the construction source.**
EQUATION_LOCATION_PENDING for the exact B-matrix entries until the paper
section is read and mapped.

**FDPF variant construction (per user correction — final signs/simplifications
to be derived from the full paper):**
- **XB variant:** remove R in B' (neglect series resistance in the P-θ
  matrix); retain R in B'' (full series admittance in the Q-V matrix).
- **BX variant:** retain R in B' (use `X/(R²+X²)`); remove R in B'' (neglect
  series resistance in the Q-V matrix).
- Both variants: neglect line charging and shunts in B'; include them in the
  *other* matrix per the paper. Phase-shift angle handling follows the paper.
  The XB/BX asymmetry of R-treatment is the defining distinction and must be
  derived verbatim from Stott-Alsac, not assumed.

**Before FDPF implementation (binding, per user correction 4):** verify exact
Stott–Alsac equation locations (paper section + equation number for each
B'/B'' construction rule and the XB/BX asymmetry). Every FDPF B-matrix row is
classified `EQUATION_LOCATION_PENDING` until its exact source location is
recorded in `PF_TS_MULTIMETHOD_SOURCES.csv`. No FDPF production code is written
before the row-by-row source verification is complete.

---

## 8. TS method source register

| method | source | classification | readiness |
|---|---|---|---|
| Implicit trapezoidal | project-existing canonical (`ts_step_kernel.m`) | PROJECT_DERIVED | READY (baseline) |
| Backward Euler | standard numerical method (Hairer & Wanner ODE II; implicit Euler) | NUMERICAL_METHOD | PLAN_ONLY |
| RK4 (classical) | standard explicit RK4, DAE-consistent semi-explicit form | NUMERICAL_METHOD | PLAN_ONLY |
| ESDIRK3(2) | Kennedy & Carpenter ESDIRK family (NASA TM-2016-219173); also Skvortsov (2022) Comput. Math. Math. Phys. 62:5 | SOURCE_VERBATIM (tableau pending) | EQUATION_LOCATION_PENDING |
| BDF2/BDF | deferred | DEFERRED_SOURCE_REQUIRED | NOT_STARTED |
| Radau IIA | deferred | DEFERRED_SOURCE_REQUIRED | NOT_STARTED |
| Rosenbrock-W | deferred | DEFERRED_SOURCE_REQUIRED | NOT_STARTED |

ESDIRK coefficients (A, b, b_hat, c tableau; stiffly-accurate; L-stability;
stage order) must be read from the paper and verified before any production
implementation. **No production scaffold file with `EQUATION_LOCATION_PENDING`
coefficients is created** (correction 7): the `ts_step_esdirk32.m` file is
written only when real, sourced coefficients are available. Until then,
requesting `esdirk32` returns `ts_integrator_step:notYetApproved` with no
executable step handle.

---

## 9. PF compatibility matrix

Legend: SUPPORTED (implemented + validated) / TARGET_PENDING_VALIDATION
(unimplemented method — target capability, not yet validated) /
UNSUPPORTED_FAIL_CLOSED / DEFERRED_SOURCE_REQUIRED / NOT_APPLICABLE.
NR is the only SUPPORTED method; FDPF-XB, FDPF-BX, BFS are
TARGET_PENDING_VALIDATION until implemented and fresh regression passes.

| Feature/case | NR | FDPF-XB | FDPF-BX | BFS |
|---|---|---|---|---|
| Meshed transmission | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | UNSUPPORTED_FAIL_CLOSED |
| Radial distribution | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION |
| Multiple PV buses | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | DEFERRED_SOURCE_REQUIRED (BFS Phase-1 PQ-only) |
| Q-limit switching | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | DEFERRED_SOURCE_REQUIRED (BFS Phase-1) |
| Phase-shifting transformer | SUPPORTED | DEFERRED_SOURCE_REQUIRED | DEFERRED_SOURCE_REQUIRED | DEFERRED_SOURCE_REQUIRED (BFS Phase-1 unity-tap only) |
| ZIP load | NOT_APPLICABLE (PF is const-power) | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE |
| Parallel branch | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | UNSUPPORTED_FAIL_CLOSED (creates cycle) |
| Island detection | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | UNSUPPORTED_FAIL_CLOSED |
| IEEE14 | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | UNSUPPORTED_FAIL_CLOSED (meshed) |
| RTS-24 | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | UNSUPPORTED_FAIL_CLOSED (meshed) |
| Padiyar two-area | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | UNSUPPORTED_FAIL_CLOSED (meshed) |
| Synthetic radial feeder | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION |

---

## 10. TS compatibility matrix

Legend: SUPPORTED (trapezoidal, implemented+validated) /
TARGET_PENDING_VALIDATION (BE/RK4/ESDIRK unimplemented — target capability) /
DEFERRED_SOURCE_REQUIRED (BDF/Radau/Rosenbrock-W). Trapezoidal is the only
SUPPORTED integrator; BE/RK4/ESDIRK are TARGET_PENDING_VALIDATION until
implemented and fresh regression passes.

| Capability/route | Trap | BE | RK4 | ESDIRK | BDF | Radau | ROS-W |
|---|---|---|---|---|---|---|---|
| Fixed step | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | DEFERRED | DEFERRED | DEFERRED |
| Adaptive step | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION (diag) | TARGET_PENDING_VALIDATION | DEFERRED | DEFERRED | DEFERRED |
| Step doubling | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION (diag) | NOT_APPLICABLE | DEFERRED | DEFERRED | DEFERRED |
| Embedded estimator | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | TARGET_PENDING_VALIDATION | DEFERRED | DEFERRED | DEFERRED |
| Provider stage evaluation | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | DEFERRED | DEFERRED | DEFERRED |
| Exact event landing | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | DEFERRED | DEFERRED | DEFERRED |
| Event rollback | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | DEFERRED | DEFERRED | DEFERRED |
| Classical SG | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION | DEFERRED | DEFERRED | DEFERRED |
| Padiyar model 1.1 | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION (diag) | TARGET_PENDING_VALIDATION | DEFERRED | DEFERRED | DEFERRED |
| EMF6 | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION (diag) | TARGET_PENDING_VALIDATION | DEFERRED | DEFERRED | DEFERRED |
| Generic bundle | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION (diag) | TARGET_PENDING_VALIDATION | DEFERRED | DEFERRED | DEFERRED |
| Composite SG/IBR DAE | SUPPORTED | TARGET_PENDING_VALIDATION | TARGET_PENDING_VALIDATION (diag) | TARGET_PENDING_VALIDATION | DEFERRED | DEFERRED | DEFERRED |

`diag` = diagnostic-only target (RK4 bounded stability region). All
BDF/Radau/Rosenbrock-W = DEFERRED_SOURCE_REQUIRED.

---

## 11. Proposed option/schema contract

**PF options (additive, no field reinterpreted):**
- New field `pf_method` (default `'newton_raphson'`). No pre-existing competing
  PF field → no alias needed.
- Resolution + fail-closed validation in new `pfsolver.pf_resolve_method(opt)`
  called at `solve_case.m:86`.

**TS options (additive, with silent alias):**
- New field `integrator` (default `'trapezoidal'`).
- Existing `opt.method` (TS) remains a **silent alias** resolved in new
  `stability.resolve_ts_integrator(opt)`:
  1. if `opt.integrator` non-empty → use it;
  2. else if `opt.method` present → `integrator=lower(opt.method)`;
  3. else default `'trapezoidal'`.
- Silent alias (no deprecation warning) because `run_ts.m` (user-owned,
  cannot edit) and the catalog set `method='trapezoidal'`; breaking it would
  cascade. After resolution, `opt.method` is set to `integrator` so
  `result.method` / `plot_ts_result.m` keep working.
- Existing `opt.stepper` (`'fixed'`/`'adaptive'`) retained unchanged.
- Fail-closed validation against the allowed set; unknown → error
  `resolve_ts_integrator:unknownIntegrator`.

**Metadata (record actual executed method, not just requested string):**
- PF `results.metadata`: `method_requested`, `method_executed`,
  `method_source` (`'default'`/`'explicit'`), `capability`,
  `fallback_used=false`, `iterations`, `full_ac_mismatch`, `factorizations`,
  `runtime_diagnostic`.
- TS `res.metadata` (+ top-level `res.integrator`): `integrator_requested`,
  `integrator_executed`, `stepper`, `order`, `stages`, `error_estimator`
  (`'step_doubling'`/`'embedded'`), `method_source`, `fallback_used=false`,
  `accepted_steps`, `rejected_steps`, `rhs_evaluations`, `algebraic_solves`,
  `nonlinear_iterations`, `jacobian_evaluations`, `factorizations`,
  `maximum_differential_residual`, `maximum_algebraic_residual`.

**Never serialize function handles.** `strategy.provider.fn` must not appear
in results (same pattern as `validate_ts_bundle.m` enforcing
`bundle.metadata` = provenance strings only).

---

## 12. Proposed minimal architecture (PACKAGE-ONLY, CORE_ONLY / NOT_ROUTED)

The factories and solvers are package-level and tested by direct calls. They
are NOT wired into `solve_case.m`/`ts_simulate.m`/`ts_adaptive_driver.m`
(those single-owner files are not modified). Production routing remains
NOT_READY until ownership is resolved.

**PF:** factory `pfsolver.pf_method_strategy(name)` (closed switch, not a
global registry / no path scanning):
```
'newton_raphson' -> strategy.solve = @(c,o) pfsolver.powerflow_newton_raphson(c,o)
otherwise         -> error('pf_method_strategy:unknownMethod')
```
(Phase-1 ships ONLY `newton_raphson` in the switch. `fdpf_xb`/`fdpf_bx`/`bfs`
are added to the switch ONLY when their phase lands and their source gate
passes. Before that, requesting them returns `pf_method_strategy:unknownMethod`.)
When called directly with `'newton_raphson'`, the factory returns the exact
existing NR call → bit-identical. `solve_case.m:87` is NOT changed in P0–P3.

**TS:** factory `stability.ts_integrator_step(opt)` (closed switch):
```
'trapezoidal'    -> @stability.ts_step_kernel
otherwise        -> error('ts_integrator_step:unknownIntegrator')
```
(Phase-1 ships ONLY `trapezoidal`. `backward_euler` is added only after P3.5
passes AND P4 lands; `rk4` after P5; `esdirk32` ONLY after the ESDIRK source
gate passes — requesting it before the gate returns
`ts_integrator_step:notYetApproved` with NO executable step handle. No
production scaffold carries `EQUATION_LOCATION_PENDING` coefficients.)
The 6 `ts_step_kernel` call sites are NOT changed in P0–P3 (single-owner files
untouched). When later wired, `step_fn=ts_integrator_step(opt); step=step_fn(...)`;
for `'trapezoidal'`, `step_fn=@ts_step_kernel` → bit-identical.

`ts_step_kernel` and `powerflow_newton_raphson` are **NOT modified**. New
integrators are siblings sharing `validate_ts_strategy`'s strategy struct and
the shared primitives. This is option (c) from the design audit: the smallest
safe solution that avoids a giant switch inside the kernel, avoids duplicating
event/provider/result logic (they call the shared helpers), and keeps method-
specific correctness visible (each integrator owns its stage loop).

---

## 13. FDPF mathematical and implementation plan

**Source:** Stott & Alsac (1974), DOI 10.1109/TPAS.1974.293985. Derive B' and
B'' per variant, mapped to the project Ybus convention
(`pf_prepare_case.m:156-188`). MATPOWER is validation evidence only.

**B' (P-θ subproblem):**
- **XB:** remove R in B' → branch susceptance from `-1/X`; neglect line
  charging, shunts; taps/phase per paper.
- **BX:** retain R in B' → `b = X/(R²+X²)` (= `-imag(1/(R+jX))`); neglect line
  charging, shunts; taps/phase per paper.

**B'' (Q-V subproblem):**
- **XB:** retain R in B'' → full series admittance; include line charging
  (`B_half`), bus shunts (cols 9-10), off-nominal tap ratios; phase per paper.
- **BX:** remove R in B'' → susceptance only; include line charging, shunts,
  taps; phase per paper.

**Row/column sets:**
- P-θ: REF (type 1) removed (angle fixed); unknowns = [PV; PQ] (matches NR
  `model.delta_idx`).
- Q-V: PV (type 2) removed (|V| fixed); unknowns = PQ (matches NR
  `model.V_idx`).

**Full nonlinear AC mismatch must be recomputed at three points per iteration
(binding, per user correction — do NOT reuse a stale Q mismatch after θ changes):**
1. **initially** (start of iteration, current V, θ);
2. **after the P/θ update** (recompute ΔP AND ΔQ with the new θ before the
   Q-V half — the Q mismatch depends on θ, so it must be refreshed);
3. **after the Q/|V| update** (final convergence check).

All three recomputations use `pf_calculate_mismatch` with the full Ybus and
the current V, θ. Convergence = `max(abs([ΔP;ΔQ]))<tol` (inf norm, same as
NR `powerflow_newton_raphson.m:170`). NOT the decoupled residual.

**Factorization reuse:** B' and B'' constant per topology/Q-limit state →
factorize once `[L,U,P]=lu(B')`, solve `U\(L\(P*b))`. No `inv`. On PV→PQ
switch, re-factorize B'' only (B' excludes PV already).

**Single shared solver with variant argument (binding, per user correction):**
implement ONE fast-decoupled solver `+pfsolver/powerflow_fdpf.m` taking a
`variant` argument (`'XB'`/`'BX'`). Thin wrappers
`+pfsolver/powerflow_fdpf_xb.m` and `+pfsolver/powerflow_fdpf_bx.m` call it
with the variant fixed. Iteration loop, full-AC-mismatch recomputation,
factorization, and Q-limit PV→PQ switching are NOT duplicated — they live
once in the shared solver. The variant flag only selects B'/B'' construction.

**Q-limits (binding, per user correction 3):** the existing
`find_q_limit_violations` is a **private local function** inside
`powerflow_newton_raphson.m` (L290-308) — it is NOT extracted or shared by
modifying the canonical NR solver (NR AbsTol=0 is preserved). Instead, a NEW
shared helper `internal/core/pf_find_q_limit_violations.m` reproduces the
existing result/event schema (same fields: `round, bus_id, from_type, to_type,
Q_generation_before, Q_fixed, limit_type`) and is used by the FDPF shared
solver (and later BFS). **Parity tests** assert the new helper returns
byte-identical violation sets and event structs to NR's private function on
shared fixtures (case_ieee5bus, case14, RTS-24). The shared FDPF solver owns
its PV→PQ switching loop (re-solve re-factorizes B'' on PV→PQ). NR is
untouched.

**Failure modes:** high R/X (XB's B' neglects R → more sensitive), heavy load,
near voltage collapse → fail closed (`converged=false`, `reason='max_iterations'`
or `'singular_jacobian'` via `rcond(B)<1e-13`). **No silent NR fallback.**

**New files:** `+pfsolver/powerflow_fdpf.m` (shared solver, variant arg),
`+pfsolver/powerflow_fdpf_xb.m` (thin wrapper), `+pfsolver/powerflow_fdpf_bx.m`
(thin wrapper), `internal/core/pf_build_b_matrices.m` (variant flag).

---

## 14. BFS mathematical and topology-contract plan

**Source:** Shirmohammadi et al. (1988) radial sweep, DOI 10.1109/59.192932.
Weakly-meshed compensation is DEFERRED (separately approved).

**Phase-1 minimal capability contract (binding, per user correction):**
Phase 1 supports ONLY an explicitly sourced minimal radial capability:
- exactly one REF bus;
- ALL remaining buses are PQ (no PV buses in Phase 1);
- connected radial tree (one connected component, no cycles);
- no parallel branches (same from-to pair → cycle → fail closed);
- **unity taps and zero phase shifts initially** (non-unity/complex taps,
  phase shifters DEFERRED_SOURCE_REQUIRED until their exact sweep equations
  are sourced and tested);
- **constant-power injections only** (constant-impedance/ZIP DEFERRED).

**DEFERRED_SOURCE_REQUIRED in BFS until exact sweep equations sourced+tested:**
PV buses, Q-limit switching, non-unity/complex taps, phase shifters, bus
shunts, line charging. The topology validator rejects any case carrying these
features in Phase 1 with a clear message naming the deferred feature.

**Load/current sign resolution (binding):** derive the injection current sign
against the project convention BEFORE implementation. The project uses
`P_net = P_gen - P_load` and `Q_net = Q_gen - Q_load` (net injection,
`pf_prepare_case.m:53-54`). The injection current and the constant-power
`S_spec` sign must be resolved to this convention (injection INTO the network
positive) and cited to Shirmohammadi 1988 + the project's
`pf_calculate_mismatch` convention. Do NOT assume `I_load = conj(S/V)` is
sufficient without the sign mapping. **Before BFS implementation: close the
Shirmohammadi sign/base mapping** — record the exact per-unit base, current
direction, and sign in `PF_TS_MULTIMETHOD_SOURCES.csv`; every BFS equation row
is `EQUATION_LOCATION_PENDING` until verified.

**BFS Phase-1 test semantics (binding, per user correction 4):** tests for
non-unity/complex taps, phase shifters, bus shunts, line charging, and PV
buses are **fail-closed REJECTION tests** — they assert the validator throws
the documented deferred-feature error (`powerflow_bfs:complexTapDeferred`,
`:shuntDeferred`, `:pvUnsupportedDeferred`, etc.). They are NOT supported-
feature tests. A passing Phase-1 BFS test suite means: minimal-capability
radial cases solve and match NR; every deferred feature is rejected with the
correct error identifier.

**Topology contract** (`internal/core/pf_validate_radial_topology(model)`):
1. exactly one REF bus (already `pf_prepare_case.m:135-137`);
2. all other buses type 3 (PQ) — any PV bus → `powerflow_bfs:pvUnsupportedDeferred`;
3. tree: `num_lines == num_buses - 1` (else `powerflow_bfs:meshedUnsupported`);
4. connected (BFS/DFS from REF; else `powerflow_bfs:disconnectedNetwork`);
5. no parallel branches (same from-to pair → `powerflow_bfs:parallelBranchUnsupported`);
6. all taps unity and all phase shifts zero (else
   `powerflow_bfs:complexTapDeferred`);
7. no bus shunts / no line charging (else `powerflow_bfs:shuntDeferred`).

**IEEE14 is meshed (20 branches > 13 = 14-1) AND has PV buses AND
transformers → UNSUPPORTED_FAIL_CLOSED.** Error names NR/FDPF as
alternatives. Never spanning-tree a meshed network.

**Algorithm (minimal, unity-tap radial, project sign convention):**
- Backward sweep (leaves→root): branch current = sum of downstream injection
  currents. Bus injection `I_bus` resolved per the load/current sign contract
  above (constant-power `S_spec=P_net+j*Q_net`).
- Forward sweep (root→leaves): `V_child = V_parent - Z_branch*I_branch`
  (unity tap, no phase shift in Phase 1).
- Slack ownership: REF `|V|`, angle fixed; REF generation computed from
  network solution post-convergence (`pf_calculate_power_injections`).

**Convergence:** full AC mismatch via `pf_calculate_mismatch` (full Ybus),
same `tol` as NR. **Not** the sweep residual.

**New files:** `+pfsolver/powerflow_bfs.m`,
`internal/core/pf_validate_radial_topology.m`.

---

## 15. Backward Euler TS plan

**Prerequisite (binding, per user correction):** a generic coupled-DAE
Jacobian contract must be added BEFORE Backward Euler. Existing `ts_jac_y_fd`
provides only `dg/dy`. The new contract specifies, for a coupled Newton solve
on the stacked residual `[R_x; R_g]`:
- **Blocks required:** `df/dx`, `df/dy`, `dg/dx`, `dg/dy`.
- **FD/analytic capability flag:** which blocks are analytic (from the
  strategy) vs finite-differenced; the strategy declares
  `has_analytic_jxx/jxy/jyx/jyy`.
- **Perturbation rule (binding, per user correction 5):** DO NOT copy the `dg/dy`
  FD perturbation (`1e-7*(1+|y_j|)` from `ts_jac_y_fd.m:12`) to `df/dx`,
  `df/dy`, `dg/dx` without derivation. Each block's perturbation step is
  DERIVED per-block from the variable's scale and the residual sensitivity
  (central FD `h_j = sqrt(eps_machine)*(1+|var_j|)` or a documented per-block
  value justified by a convergence study), and recorded in
  `PF_TS_MULTIMETHOD_SOURCES.csv` before implementation. Document the
  column/row ordering for each block.
- **Scaling:** residual and Jacobian scaling so the differential and
  algebraic blocks are commensurate (declare the scaling before viewing
  results).
- **Residual norm:** stacked `norm([R_x; R_g], inf)` for convergence; weighted
  variant (`atol+rtol*max(|x|,|cand|)`) for adaptive.
- **Newton tolerance:** declare `newton_tol` per-solve (from `opt`); fail-closed
  on `nonconverged`.
- **Line search:** damped backtracking (as in `ts_algebraic_solve.m:19-66`),
  alpha down to 2^-16.
- **`rcond` threshold:** `rcond(J)>=1e-13` (matching NR
  `powerflow_newton_raphson.m` Phase-B guard); else `singular_jacobian`.
- **Factorization policy:** `[L,U,P]=lu(J)` once per Newton iteration; reuse
  across line-search steps; no `inv`/`pinv`.
- **Analytic/FD capability ABI:** the strategy declares
  `has_analytic_jxx/jxy/jyx/jyy` and optionally provides analytic closures;
  when a block is FD, the contract calls the documented perturbation; the ABI
  (function signatures, return shapes, error identifiers) is FROZEN and
  documented before P4 starts.

**P3.5 is a HARD numerical-contract gate (binding, per user correction 5):**
each block's perturbation, residual scaling, Newton tolerance, rcond rule,
line search, analytic/FD capability ABI, and tests are FROZEN and documented
before P4 (Backward Euler) starts. P3.5 passing its own test suite (FD vs
analytic cross-check on a synthetic DAE, line-search convergence, rcond
rejection, factorization reuse) is the gate. P4 does not start until P3.5
passes.

This contract lives in a new `+stability/ts_coupled_jacobian.m` (or a
strategy-extended `ts_jac_y_fd` generalization) and is shared by BE, ESDIRK,
and later implicit methods. RK4 (semi-explicit) uses only `dg/dy` per stage
but may reuse the contract for its final re-solve.

**Residual:**
```
R_x = x_{n+1} - x_n - h·f(x_{n+1}, y_{n+1}, u_{n+1}) = 0
R_g = g(x_{n+1}, y_{n+1}, Y_left) = 0
```
Coupled nonlinear system in `(x_{n+1}, y_{n+1})`. Newton with block Jacobian
`J=[I-h·df/dx, -h·df/dy; dg/dx, dg/dy]`, `[dx;dy]=J\[R_x;R_g]` (backslash),
using the coupled-DAE Jacobian contract above. `dg/dy` via `ts_jac_y_fd`
(or `jac_y_u` provider-aware); `df/dx, df/dy, dg/dx` via FD or analytic per
the capability flag. Classical linear model: y solved inside `dae_f` →
residual in x alone.

**Provider:** 1 stage, `c=1` → `u_{n+1}=eval_input_provider(provider,t0+h,...)`.
**L-stable.** **Event reuse:** call `ts_event_transition` identically after step.

**Adaptive mode is FROZEN before enablement (binding, per user correction 6):**
the method-specific algebraic adaptive-error definition for BE must be frozen
BEFORE adaptive BE is enabled. This means the following are declared and
documented (in `PF_TS_MULTIMETHOD_SOURCES.csv` + a contract file) before any
adaptive BE code runs:
- **differential estimator:** step-doubling `p=1, denom=2^1-1=1, exp_ctl=1/2`,
  `e_x=(x_halfhalf-x_full)/1`;
- **algebraic estimator/discrepancy:** the exact algebraic-error definition for
  BE (NOT the unresolved "stage residual or embedded" placeholder) — declared
  per the method-specific adaptive DAE error contract in §12;
- **algebraic residual gate:** `alg_res<=g_tol` accept condition;
- **controller order:** `exp_ctl=1/2`;
- **cache/stage rollback:** full state restore on reject.
Until this definition is frozen, BE ships FIXED-STEP ONLY; requesting
`stepper='adaptive'` with `integrator='backward_euler'` returns
`ts_integrator_step:adaptiveNotFrozen` (no executable adaptive path).

**New file:** `+stability/ts_step_be.m`. Strategy-form entry mirroring
`ts_step_kernel`'s step-struct contract.

---

## 16. RK4 DAE-stage plan

**DAE-consistent semi-explicit RK4** (4 stages, each solves algebraic network):
```
Stage 1: g(X_1,Y_1,Y)=0, X_1=x_n            ; K_1=f(X_1,Y_1,u(t_n))
Stage 2: g(X_2,Y_2,Y)=0, X_2=x_n+h/2·K_1     ; K_2=f(X_2,Y_2,u(t_n+h/2))
Stage 3: g(X_3,Y_3,Y)=0, X_3=x_n+h/2·K_2     ; K_3=f(X_3,Y_3,u(t_n+h/2))
Stage 4: g(X_4,Y_4,Y)=0, X_4=x_n+h·K_3       ; K_4=f(X_4,Y_4,u(t_n+h))
Final:   x_{n+1}=x_n+h/6·(K_1+2K_2+2K_3+K_4) ; y_{n+1}: re-solve g(x_{n+1},y_{n+1},Y)=0
```
Each stage calls `ts_algebraic_solve`/`_u`. Provider at `t_n, t_n+h/2, t_n+h/2, t_n+h`.
**≥4 algebraic solves/step** (not cheaper than trapezoidal). **Fixed step first.**
Optional step-doubling `p=4, denom=15, exp_ctl=1/5`. **Bounded stability region
→ diagnostic-only initially** (`capability='diagnostic'`).

**Adaptive RK4 is FROZEN before enablement (binding, per user correction 6):**
the method-specific algebraic adaptive-error definition for RK4 must be frozen
BEFORE adaptive RK4 is enabled (same five items as BE §15: differential
estimator `p=4, denom=15, exp_ctl=1/5`; algebraic estimator/discrepancy — the
exact definition, NOT unresolved "stage residual or embedded"; algebraic
residual gate; controller order; cache/stage rollback). Until frozen, RK4 ships
FIXED-STEP ONLY; requesting `stepper='adaptive'` with `integrator='rk4'` returns
`ts_integrator_step:adaptiveNotFrozen`.

**New file:** `+stability/ts_step_rk4.m`.

---

## 17. ESDIRK source-selection plan

**Candidates:** Kennedy-Carpenter ESDIRK3(2) (NASA TM-2016-219173); Skvortsov
(2022) order-3(2). **Recommend Kennedy-Carpenter** as first candidate (broader
community validation), unless user prefers Skvortsov.

**Must verify from paper before implementation:** the exact Butcher tableau
(A, b, b_hat, c); stiffly-accurate property; L-stability (`R(z)→0` as `z→-∞`);
stage order; global order; DAE applicability; stage count `s`. **No provisional
structural claims** (e.g. "zero first column, unit diagonal", "stiffly-accurate
b==A(end,:)") are made in this plan — these are properties to be VERIFIED from
the paper, not assumed. The ESDIRK structural shape is determined entirely by
the sourced tableau.

**Error estimator:** embedded (`b_hat` vs `b`) for ESDIRK, NOT step-doubling
(per the method-specific adaptive DAE error contract in §12).

**Binding gate (per user correction 7):** `esdirk32` is NOT registered in the
`ts_integrator_step` production switch until (a) the exact sourced tableau is
read from the approved paper, (b) DAE applicability is verified, and (c) the
source gate passes. Before the gate, requesting `opt.integrator='esdirk32'`
returns `ts_integrator_step:notYetApproved` with **NO executable step handle**
— the factory does NOT return a function handle to a scaffold. **No production
scaffold file carrying `EQUATION_LOCATION_PENDING` coefficients is created.**
The ESDIRK step file is written only when real, sourced coefficients are
available; until then, the name is a known-but-not-approved entry that errors
on request. This prevents an unreachable-but-present scaffold from being
mistaken for a validated method.

---

## 18. Deferred BDF/Radau/Rosenbrock prerequisites

- **BDF:** multistep history, startup, variable-step coefficients, restart/order
  reduction at events, DAE consistency. Event-rich IBR switching may reduce its
  advantage. DEFERRED.
- **Radau IIA:** sourced tableau, coupled nonlinear stages, L-stable, high-DAE-
  order; cost high → high-accuracy reference. DEFERRED.
- **Rosenbrock-W:** sourced coefficients, mass-matrix/DAE form, inexact-Jacobian
  policy, stage order, embedded estimator, factorization reuse; benefits appear
  after analytic Jacobians exist. DEFERRED.

All require separate approval. Not in first slice.

---

## 19. PF-to-TS initialization contract

Per user decision: **TS stays on NR** (`ts_simulate.m:94` hard-codes
`pfsolver.powerflow_newton_raphson`) until PF methods mature. `pf_method` is
PF-only in the first slice. SSSA paths unchanged.

When (later) selectable PF is allowed in TS:
- TS init gate: after PF, verify full AC mismatch `< pf_eq_tolerance` (declare
  before viewing results; e.g. match `1e-10`). If `pf.converged=false` or
  mismatch exceeds → fail closed `ts_init:pfEquilibriumViolation`.
- BFS on meshed IEEE14 → `converged=false` → existing `ts_simulate:pfNotConverged`
  (`ts_simulate.m:95`). No silent NR fallback.
- FDPF convergence uses full AC mismatch (§13) → if `converged=true`, TS init
  satisfied.
- Explicit fallback (if ever desired) = separate approved option
  `opt.pf_fallback_method`, recorded `fallback_used=true`. OUT OF SCOPE now.

---

## 20. Event/provider/rollback preservation plan

- `ts_event_transition` (explicit `event_id`, no `t+eps`) is method-agnostic;
  called identically after every accepted step that lands on an event. New
  integrators call it unchanged.
- `ts_topology_at` selects Y by time; used by all integrators unchanged.
- Provider evaluation extends per-stage: trapezoidal/BE use endpoints
  (`t0`, `t0+h`); RK4 uses `t0, t0+h/2, t0+h`; ESDIRK uses `t0+c_i·h`. Each
  integrator owns its stage-time calls to `eval_input_provider`; the provider
  interface (`make_input_provider`/`eval_input_provider`) is unchanged.
- Rollback: accepted output arrays untouched on reject; restore `x,y,Jyy`,
  halve `dt`, append one rejection record — same pattern in the generalized
  driver for all step-doubling integrators.

---

## 21. Result metadata/diagnostic plan

See §11. PF and TS metadata are additive under `results.metadata` /
`res.metadata` (+ top-level `res.integrator`). Tests use field-existence checks,
not exact-struct equality (avoid metadata-bloat breakage). No function handles
serialized.

---

## 22. Test plan (specify, do not implement now)

**PF tests:** (1) default NR == explicit NR AbsTol=0; (2) unknown PF method
fails before solving; (3) requested/executed metadata matches; (4) FDPF
order/sign/B-matrix unit tests; (5) FDPF full-AC mismatch convergence; (6)
FDPF IEEE14 + RTS-24 vs NR; (7) FDPF high-R/X diagnostic fixture; (8) FDPF
Q-limit/PV-PQ; (9) BFS analytic 2/3-bus radial oracle; (10) BFS radial graph
orientation with shuffled external bus IDs; (11) BFS transformer/tap/shunt
fixtures; (12) BFS rejects meshed IEEE14; (13) BFS rejects unsupported PV/
multi-slack; (14) no inv/pinv/external solver (existing scanner); (15)
existing PF tests unchanged.

**TS tests:** (1) default == explicit trapezoidal AbsTol=0; (2) unknown
integrator fails before stepping; (3) actual-method metadata; (4) analytic
harmonic oscillator; (5) scalar stiff decay; (6) synthetic semi-explicit
linear DAE; (7) convergence order (BE≈1, trap≈2, RK4≈4, ESDIRK sourced
orders); (8) algebraic residual at every accepted endpoint; (9) stage-time
provider evaluation; (10) exact event landing; (11) left-arrival/right-public
event convention; (12) rejection rollback; (13) bundle/composite route;
(14) classical/Padiyar/EMF6 capability routing; (15) existing adaptive `/3`
test unchanged; (16) existing default + schema tests green; (17) no external
solver dependency; (18) full regression.

---

## 23. Benchmark plan

**PF cases:** analytic small PF fixture; IEEE14 (MATPOWER); RTS-24; Padiyar
two-area; new equation-sourced radial feeder for BFS.
**TS cases:** analytic linear ODE; analytic semi-explicit DAE; IEEE14 SG
diagnostic; Padiyar two-area; generic composite/bundle fixture; future
IEEE14 SG+IBR only after IBR equations sourced.

Identical input contract per comparison (case data, base values, IC, fault
bus/impedance, event times, horizon, output mapping, tolerance, convergence
metric). PF metrics: convergence, full AC mismatch, |ΔV|, |Δθ|, iterations,
factorizations, runtime median, failure reason. TS metrics: state error,
algebraic voltage error, Pe error, DAE residual, event-time error,
accepted/rejected steps, RHS evals, algebraic solves, nonlinear iterations,
Jacobian/factorization count, runtime median. **Do not rank by runtime unless
same accuracy/residual contract. No equivalence from similar plots.**

---

## 24. UI integration plan

Deferred until methods validated (per recommendation; confirm at implementation
start). Dirty launchers (`run_ts.m`, `solve_case.m`, `+stability/ts_simulate.m`,
`scripts/plot_ts_result.m`) are **user-owned** — read-only for planning. **No
claim is made that `solve_case('analysis','pf',...,'pf_method',...)` or
`solve_case('analysis','ts',...,'integrator',...)` works from P0.** The package-
level factories/solvers are CORE_ONLY / NOT_ROUTED: they are tested by direct
calls, not through `solve_case`/`ts_simulate`. Production routing readiness
remains **NOT_READY** until the single-owner integration files (`solve_case.m`,
`ts_simulate.m`, `ts_adaptive_driver.m`) are separately resolved. Future UI:
capability-aware method menu (hide BFS for IEEE14; hide adaptive RK4 until
verified; hide ESDIRK until sourced; no method shown merely because a metadata
string exists). No UI commit may mix with numerical-method commits.

---

## 25. File-by-file proposed changes

**New (PF):** `+pfsolver/pf_resolve_method.m`, `+pfsolver/pf_method_strategy.m`,
`+pfsolver/powerflow_fdpf.m` (shared solver, variant arg),
`+pfsolver/powerflow_fdpf_xb.m` (thin wrapper),
`+pfsolver/powerflow_fdpf_bx.m` (thin wrapper),
`+pfsolver/powerflow_bfs.m`, `internal/core/pf_build_b_matrices.m`,
`internal/core/pf_validate_radial_topology.m`,
`internal/core/pf_find_q_limit_violations.m` (shared Q-limit helper, parity-
tested against NR's private function; NR untouched).
**New (TS):** `+stability/resolve_ts_integrator.m`,
`+stability/ts_integrator_step.m`, `+stability/ts_coupled_jacobian.m`
(coupled-DAE Jacobian contract, P3.5 hard gate, prerequisite for BE/ESDIRK),
`+stability/ts_step_be.m` (after P3.5 passes),
`+stability/ts_step_rk4.m` (after P3.5 passes; diagnostic).
**NOT created in authorized scope:** `+stability/ts_step_esdirk32.m` — no
production scaffold with `EQUATION_LOCATION_PENDING` coefficients (correction 7);
written only when sourced coefficients are available and the source gate passes.
**Forbidden (NOT touched):** `+stability/ts_step_kernel.m`,
`+stability/multimachine_ssa.m`, `+stability/multicase_sssa.m`,
`+stability/synchronous_emf6_ssa.m`, `+stability/padiyar_model11_ssa.m`,
`+stability/padiyar_model11_dae.m`, `+stability/classical_sssa.m`,
`+stability/composite_dae.m`, SSSA Jacobians/Schur/vcon/dispatch, `pf_init_paths.m`
(no new path entries beyond new `+pfsolver`/`+stability` files which are auto-
included by package), dirty launchers.

---

## 26. Phased commit plan

- **P0** — Option contract + factories (package-level only per §2 ownership
  note — NO `solve_case.m`/`ts_simulate.m` edits until integration owner
  resolved). NR/trapezoidal bit-identity tests via direct factory calls.
  Fail-closed unknown method.
- **P1** — FDPF shared solver + thin XB/BX wrappers (per user decision: both
  variants). Full-AC-mismatch recomputation at 3 points. B'/B'' construction
  derived from Stott-Alsac paper (EQUATION_LOCATION_PENDING until read).
- **P2** — Radial BFS Phase-1 minimal capability (per user decision:
  radial-only fail-closed; unity taps, zero phase, PQ-only, const-power;
  load/current sign resolved against `P_gen-P_load` convention).
- **P3** — Generic TS integrator boundary (`ts_integrator_step` factory;
  `ts_step_kernel` untouched; single-owner files NOT yet wired).
- **P3.5** — Coupled-DAE Jacobian contract (`ts_coupled_jacobian.m`):
  df/dx, df/dy, dg/dx, dg/dy; FD/analytic flag; perturbation; scaling;
  residual norm; Newton tol; line search; rcond; factorization policy.
  Prerequisite for BE/ESDIRK.
- **P4** — Backward Euler (uses the coupled-DAE Jacobian contract).
- **P5** — RK4 (diagnostic; semi-explicit, uses dg/dy per stage + final re-solve).
- **P6** — Sourced ESDIRK32 (source-gated; NOT authorized in this scope — no
  scaffold created. The `ts_step_esdirk32.m` file is written only when sourced
  coefficients are available, DAE applicability is verified, and the source
  gate passes. Before then, requesting `esdirk32` returns
  `ts_integrator_step:notYetApproved` with no executable step handle).
- **P7** — Method capability routing through classical/Padiyar/EMF6/bundle
  (requires single-owner file edits — ownership must be resolved first).
- **P8** — Benchmarks and readiness derivation.
- **P9** — (Later, separately approved) selectable PF in TS.
- **P10** — (Later) UI integration after launchers checkpointed.

(Phase numbering aligned to user decision "all three integrators in separate
phases"; P3.5 inserted per user correction 7.)

---

## 27. Risks and failure modes

1. NR/trapezoidal bit-identity violation if factory alters call path → guarded
   by AbsTol=0 tests in P0.
2. `ts_step_kernel` 3-path structure: new integrators must mirror
   legacy/classical/provider paths → kept DRY via shared primitives.
3. Adaptive driver embedded-vs-step-doubling branch must stay a 2-branch
   if/else, not a per-method switch.
4. FDPF Q-limit PV→PQ re-factorizes B''; BFS Phase-1 has no PV/Q-limits → both
   need explicit tests.
5. FDPF divergence on high-R/X IEEE14 branches → fail-closed, tested.
6. BFS Phase-1 minimal capability: any PV/tap/phase/shunt/charging →
   DEFERRED_SOURCE_REQUIRED, fail closed — must not silently widen scope.
7. FDPF stale-Q-mismatch bug: must recompute full AC mismatch after P/θ update
   (binding per user correction 3) — explicit test required.
8. Coupled-DAE Jacobian contract (P3.5): FD perturbation per block is DERIVED
   (correction 5 — NOT copied from `ts_jac_y_fd.m:12`); rcond/line-search
   semantics match `ts_algebraic_solve`. Hard gate: P4 blocked until P3.5 passes.
9. ESDIRK coefficients unverified → **no production scaffold created**
  (correction 7); `esdirk32` returns `notYetApproved` with no executable handle
  until the source gate passes.
10. Metadata bloat → additive under `.metadata`, field-existence tests.
11. Dirty single-owner files: plan tested against clean checkout from `31a211d`,
   not the dirty worktree; P0/P3 stay package-level until ownership resolved.
12. Single-owner files (`solve_case.m`, `ts_simulate.m`,
   `ts_adaptive_driver.m`, shared TS kernel helpers per
   `TRACK_COORDINATION.md:114-130`) → must declare ownership and wait for
   assignment before edit (binding per user correction 6).

---

## 28. Explicit user decisions still required

**Captured this turn:**
- FDPF variants = **both XB and BX**.
- BFS scope = **radial-only fail-closed** (weakly-meshed deferred).
- TS slice = **all three integrators (BE, RK4, ESDIRK32) in separate phases**.
- PF in TS = **keep TS on NR until PF methods mature**.

**To confirm at implementation start (recommendations):**
- Advanced methods (BDF/Radau/Rosenbrock-W) = **defer all**.
- UI timing = **defer until methods validated** (dirty launchers user-owned).

**To approve when ESDIRK phase begins:**
- ESDIRK source selection: Kennedy-Carpenter ESDIRK3(2) (recommended) vs
  Skvortsov (2022) — AND verify the exact tableau + DAE applicability from the
  paper; pass the source gate BEFORE registering `esdirk32` in the production
  switch (binding per user correction 9).

**To resolve before any single-owner file edit (binding per user correction 6):**
- Ownership of `solve_case.m` and `+stability/ts_simulate.m` (both user-owned
  dirty AND single-owner per `TRACK_COORDINATION.md:114-130`): checkpoint/
  cherry-pick the owner's changes first, OR keep P0/P3 at package-level only.

---

## 29. Stop conditions

Stop and ask if: exact source/equation location cannot be verified; FDPF XB/BX
semantics ambiguous; BFS would discard mesh loops; BFS PV support needs
unsourced extension; a new PF method changes SSSA behavior; a new method
changes case data/physical equations; NR/trapezoidal default paths cannot
remain AbsTol=0; event semantics differ by method; provider state/time
semantics cannot be preserved; implementation requires external solvers;
results improve only after tuning; a dirty user-owned file must be modified;
work expands into IBR equations or Track B; any method must silently fall back.

---

## 30. Recommended first implementation slice

**P0 (package-level factories) + P1 (FDPF shared solver, both variants) +
P2 (radial BFS minimal capability) + P3 (integrator boundary, package-level) +
P3.5 (coupled-DAE Jacobian contract) + P4 (Backward Euler).**

Rationale: P0 delivers the option/factory infrastructure (package-level only,
no single-owner file edits until ownership resolved) and proves NR bit-identity
via direct factory calls. P1/P2 validate the PF factory + Ybus-reuse pattern
with two real PF methods (one meshed-capable shared solver with XB/BX variants,
one radial-only minimal-capability fail-closed). P3/P3.5/P4 validate the
integrator-strategy pattern, the coupled-DAE Jacobian contract (prerequisite
per user correction 7), and the method-specific adaptive DAE error contract
(per user correction 8) with the simplest L-stable implicit method. RK4 (P5)
and ESDIRK32 (P6, after source gate) follow. TS PF selection (P9) and UI (P10)
are deferred per user decisions.

---

## Verification (after implementation, not in this planning turn)

```matlab
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);
% P0 gate: test_nr_solver, test_pf_contract, test_ts_strategy_equivalence,
%         test_ts_classical_strategy_equivalence, test_ts_adaptive_lte must
%         pass with AbsTol=0 (bit-identity preserved through factories).
% Per method: the dedicated tests listed in §22.
% Scanner: test_no_external_solver_dependency must remain green.
```

No implementation occurs until the user explicitly approves this plan and the
first slice. No status flag is marked PASS during planning.

---

# Part 2 — Production Integration Plan (read-only, pending approval)

This section covers wiring the package-level factories (P0–P5, complete at
510/510) into the production dispatch path. It is PLAN_ONLY until the user
approves and grants single-owner ownership. Per user decisions (2026-07-13):

## Context for integration

The package-level multi-method work (510/510, CORE_ONLY/NOT_ROUTED) is complete
but **unrouted** — production still hard-codes `pfsolver.powerflow_newton_raphson`
(solve_case.m:87) and `stability.ts_step_kernel` (6 call sites). The goal is to
wire the factories into production so a user can pass `pf_method='fdpf_bx'` or
`integrator='backward_euler'` and the framework selects, validates, records, and
runs the correct in-house method — with default paths bit-identical (AbsTol=0).

**Binding user decisions (2026-07-13):**
1. Integration base = `plan/pf-ts-multimethod @31a211d` (immutable). Using 31a211d
   as base does NOT auto-grant ownership of single-owner files.
2. Dirty main is user-owned: do NOT stage/commit/copy/overwrite/reconcile its
   interactive dialog files. Implement on the isolated 31a211d-based branch.
3. Checkpoint 21 untracked files via explicit path list (NO `git add .`), with
   audit + SHA-256 hashes, before any history operation.

## Objective and non-goals

**Objective:** wire PF + TS factories into production dispatch with default
bit-identity preserved, fail-closed semantics, and method metadata recorded.

**Non-goals (this plan does NOT):**
- touch dirty main (dialog system preserved as user-owned);
- change `ts_step_kernel` or `powerflow_newton_raphson` numerical behavior;
- allow PF method selection into TS/SSSA initialization (TS/SSSA stay on NR);
- enable adaptive + BE/RK4 (fail closed until adaptive-error contract frozen);
- register `esdirk32` (stays `notYetApproved`);
- promote RK4 to production-default/UI route;
- change SSSA, equations, tolerances, FD steps, iteration caps, defaults, cases.

## Active track and integration owner

- **Track:** PF/TS multi-method production integration (Track A-adjacent).
- **Integration base:** `plan/pf-ts-multimethod` @ `31a211d` (immutable).
- **Integration owner (requested, pending user assignment):** this agent, for
  the single-owner files listed below ONLY after the user explicitly grants
  ownership and checkpoints the dirty dialog system. Until then, this agent
  owns only the new package-level files (already complete).
- **SSSA:** out of scope (untouched, stays on NR).

## Git/worktree state (verified 2026-07-13)

- main HEAD = `f59076f`; merge-base(main, 31a211d) = `f59076f`; 31a211d is
  NOT reachable from main (16 commits ahead); main lacks IBR interface
  foundation (composite_dae, ts_event_transition, make_input_provider, etc.).
- Dirty main (user-owned, PRESERVED): `solve_case.m`, `run_ts.m`,
  `+stability/ts_simulate.m`, `scripts/plot_ts_result.m`,
  `docs/project/AGENT_HANDOFF.md` + 9 untracked docs/scripts.
- `plan/pf-ts-multimethod` worktree @ `31a211d`: 21 untracked files (18
  multi-method + SOURCES.csv + plan doc + 1 other); needs checkpoint.
- Active branches with worktrees: main, feature/adaptive-ts, feature/ibr-
  interface-foundation (31a211d), feature/ieee14-auto-vsg-switching (69fcac3),
  checkpoint/padiyar-report-assets, plan/pf-ts-multimethod, report/system-methods-v2.

## Checkpoint procedure (before any history op)

1. `git status --porcelain` → record full untracked list.
2. Audit each untracked file; **exclude** any temp/generated/.mat/.log/.aux/
   .toc/.out/credential/user-owned file. Stage ONLY the approved 21 paths by
   exact filename (NO `git add .`).
3. Record SHA-256 of each staged file before commit.
4. `git diff --cached --name-status` + `git diff --cached --check` review.
5. Commit message: `checkpoint: preserve PF/TS multi-method work before integration`
   (work-in-progress only; no production-readiness claim).
6. No push/merge.

## Dirty-main reconciliation (binding: do NOT touch)

- Dirty `solve_case.m` (+305 lines): adds `prompt_pf_options`/`prompt_sssa_options`/
  `prompt_ts_options` interactive dialogs + `case_selection_interactive` flag;
  PF dispatch at line 87 still `pfsolver.powerflow_newton_raphson` (no factory
  wiring); TS dialog has `'Integration method (trapezoidal)'` prompt validated
  to trapezoidal-only.
- Dirty `run_ts.m`: rewritten to case-first dialog launcher; no explicit
  `ts_options.stepper='fixed'` (will break `test_ts_default_routing.m:35`).
- Dirty `+stability/ts_simulate.m`: only a verbose fprintf message change.
- **Policy:** preserve ALL dirty main files. The integration branch is based on
  31a211d (clean) and does not carry these dialog changes. Production/UI routing
  stays NOT_READY until the user checkpoints the dialog system and grants
  single-owner ownership under explicit authorization.

## Current production call graph (verified file:line)

**PF (main, clean at 31a211d):**
```
run_powerflow.m → solve_case('analysis','pf')
  → solve_case.m:87  result=pfsolver.powerflow_newton_raphson(case_data,opt)  [HARD-CODED]
       → powerflow_newton_raphson.m (outer Q-limit loop L37-80; solve_model L106+)
       → pf_build_results.m:36-88
```
PF option struct (solve_case.m:45-47): no `pf_method` field. `opt.method` is
TS-only (always 'trapezoidal'). `result.method` is display label only.

**TS (main, clean at 31a211d):**
```
run_ts.m / solve_case('analysis','ts')
  → solve_case.m:98  stability.ts_simulate(case_data,opt)   [opt passed wholesale, unfiltered]
       → ts_simulate.m:50-65  model dispatch (padiyar_1_1_* / emf6 / classical inline)
       → ts_simulate.m:231  step=ts_step_kernel(strat,x,y,dt_step,Y_now,kopt_cl)  [classical fixed]
       → ts_simulate_emf6.m:147  step=ts_step_kernel(...)  [emf6 fixed]
       → ts_simulate_padiyar_model11.m:70  step=ts_step_kernel(...)  [padiyar fixed]
       → ts_adaptive_driver.m:127,128,129  step_full/step_h1/step_h2=ts_step_kernel(...)
       → result metadata (ts_simulate.m:265-340; emf6 L180-253; padiyar L92-185)
```
- Stepper dispatch: `isfield(opt,'stepper')&&strcmpi(opt.stepper,'adaptive')` at
  ts_simulate.m:186, ts_simulate_emf6.m:77, ts_simulate_padiyar_model11.m:30.
- `opt.method` is **metadata-only** (never dispatched) in all 3 routes.
- `ts_adaptive_driver.m` constants: p=2 (L42), denom=3 (L44), exp_ctl=1/3 (L45).

## Proposed integration (two-phase)

### Phase 1 — package-level hardening (NO single-owner edits; authorized now)

Already complete at 510/510. Remaining Phase-1 items (read-only edits to new
files only, no single-owner touch):
- Fix P3.5 `SOURCES.csv` row: `EQUATION_LOCATION_PENDING` →
  `VERIFIED_SOURCE_LOCATED` (derivation is in `ts_coupled_jacobian.m`: eps^(1/3)
  central-FD optimality, hrule=6e-6 per block). Cite Süli & Mayers 2003 (verified)
  or Hairer-Wanner ODE II (TOC-only; label project-derived if Hairer not
  directly verified). The code derivation is complete and tested
  (test_ts_coupled_jacobian 7/7); only the CSV provenance is stale.
- Add package-level end-to-end routing tests that call the factories directly
  (not through solve_case): `test_pf_routing_end_to_end` (default == explicit
  NR AbsTol=0; fdpf/bfs methods produce method_executed metadata), and
  `test_ts_integrator_routing` (trapezoidal default == explicit AbsTol=0;
  backward_euler/rk4 produce method_executed; adaptive+BE/RK4 fail closed;
  esdirk32 returns notYetApproved with no handle).

### Phase 2 — production wiring (BLOCKED until user checkpoints dialog + grants ownership)

**Files to modify (single-owner — require ownership grant):**
- `solve_case.m`: PF dispatch line 87 → `[opt_pf, mn]=pfsolver.pf_resolve_method(opt); strat=pfsolver.pf_method_strategy(mn); result=strat.solve(case_data,opt_pf)`. When `pf_method` absent or `'newton_raphson'`, factory returns exact NR call → bit-identical. TS dispatch line 98 unchanged (opt flows wholesale). Add `opt.pf_method` default `'newton_raphson'` to PF defaults.
- `+stability/ts_simulate.m`: before fixed-step loop (L231), add `[integrator,~,opt]=stability.resolve_ts_integrator(opt); step_fn=stability.ts_integrator_step(opt);` then `step=step_fn(strat,...)`. Add adaptive+BE/RK4 fail-closed gate (reject `stepper='adaptive'` with `integrator` in {backward_euler,rk4} → error `ts_simulate:adaptiveNotFrozen`). Result metadata: add `res.integrator` + `res.metadata.method_executed`.
- `+stability/ts_simulate_emf6.m`: same pattern before L147; add metadata.
- `+stability/ts_simulate_padiyar_model11.m`: same pattern before L70; add metadata.
- `+stability/ts_adaptive_driver.m`: resolve `step_fn` once before L127; replace 3 call sites (L127/128/129). Generalize constants per-integrator ONLY for trapezoidal (p=2/denom=3/exp=1/3 unchanged). Adaptive+BE/RK4 already fail-closed at ts_simulate level, so the driver never receives them.

**Files NOT modified (binding):**
- `+stability/ts_step_kernel.m` (canonical trapezoidal, bit-identity source);
- `+pfsolver/powerflow_newton_raphson.m` (canonical NR);
- `+stability/multimachine_ssa.m`, `multicase_sssa.m`, `synchronous_emf6_ssa.m`,
  `padiyar_model11_ssa.m`, `padiyar_model11_dae.m`, `classical_sssa.m`,
  `composite_dae.m` (SSSA + IBR foundation, out of scope);
- `pf_init_paths.m` (single-owner; new package files auto-included);
- `scripts/plot_ts_result.m` (user-owned dirty);
- `run_ts.m`, `run_powerflow.m` (user-owned dirty / single-owner launchers);
- cases, tolerances, defaults, equations.

**Option precedence & fail-closed:**
- PF: `opt.pf_method` (default `'newton_raphson'`); unknown → `pf_resolve_method:unknownMethod`; BFS on unsupported topology → `pf_validate_radial_topology:*`. No silent NR fallback.
- TS: `opt.integrator` (default `'trapezoidal'`) > `opt.method` alias > default; unknown → `resolve_ts_integrator:unknownIntegrator`; `esdirk32` → `notYetApproved` (no handle); adaptive+{backward_euler,rk4} → `adaptiveNotFrozen`. No silent trapezoidal fallback.

**Compatibility/result-schema:**
- Additive fields only: `result.metadata.method_requested/method_executed/method_source/capability/fallback_used=false`; PF `result.method_variant`; TS `result.integrator`. Existing `result.method` stays as display alias (set to resolved name).
- Tests use field-existence checks, not exact-struct equality (avoid metadata bloat).

## Tests to add (Phase 2)

End-to-end routing tests (require single-owner edits):
1. `solve_case('analysis','pf','case','ieee5','options',struct('pf_method','fdpf_bx'))` → result.method_executed='fdpf_bx', V matches NR within 1e-6.
2. `solve_case('analysis','pf')` (default) == direct NR AbsTol=0 (bit-identity).
3. `solve_case('analysis','pf','options',struct('pf_method','bogus'))` → error before solve.
4. `solve_case('analysis','ts','options',struct('integrator','backward_euler'))` → result.integrator='backward_euler', finite trajectory, algebraic residual < g_tol.
5. `solve_case('analysis','ts')` (default) == canonical trapezoidal AbsTol=0.
6. `solve_case('analysis','ts','options',struct('integrator','bogus'))` → error before step.
7. `solve_case('analysis','ts','options',struct('integrator','backward_euler','stepper','adaptive'))` → `adaptiveNotFrozen`.
8. `solve_case('analysis','ts','options',struct('integrator','esdirk32'))` → `notYetApproved`.
9. Per-model routing: classical (ts_simulate.m:231), EMF6 (ts_simulate_emf6.m:147), Padiyar (ts_simulate_padiyar_model11.m:70) each route BE/RK4 via factory and produce correct metadata.
10. `test_no_external_solver_dependency` remains green (scanner scans real path).

## Tolerances/acceptance (declared before viewing results)

- Default NR via factory == direct NR: AbsTol=0 (bit-identity).
- Default trapezoidal via factory == direct ts_step_kernel: AbsTol=0.
- FDPF vs NR on IEEE5/14: V AbsTol 1e-4, angle AbsTol 1e-3 (different method, not bit-identical).
- BFS vs NR on radial: V AbsTol 1e-6 (same physics, radial).
- BE convergence order ~1 (error ratio ~0.5); RK4 order ~4 (ratio ~0.0625).
- Algebraic residual at every accepted endpoint < g_tol.
- Full regression: ≥510 passed (existing) + new routing tests, 0 failed.

## Validation commands

```matlab
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);
compare_case14_ts_three_way;   % per availability
compare_rts24_psat;            % per availability; report honestly if PSAT unavailable
```

## Commit split (Phase 2)

- C1: checkpoint untracked multi-method work (explicit paths, audited).
- C2: PF production wiring (solve_case.m:87 factory + pf_method default + metadata) + PF routing tests.
- C3: TS production wiring (ts_simulate.m + ts_simulate_emf6.m + ts_simulate_padiyar_model11.m + ts_adaptive_driver.m) + TS routing tests + per-model routing tests.
- C4: P3.5 SOURCES.csv provenance fix.
- No push/merge. Each commit reruns full regression.

## Rollback / fail-closed

- Any commit that breaks NR/trapezoidal bit-identity → revert that commit, do not amend.
- Unknown method names error before solve (never silent default).
- BFS topology violations error with named deferred-feature identifier.
- adaptive+{BE,RK4} errors `adaptiveNotFrozen` before stepping.
- esdirk32 errors `notYetApproved` with no executable handle.
- If a model route's BE/RK4 step diverges, fail closed (error), do not silently fall back to trapezoidal.

## Unresolved decisions requiring user authority

1. **Single-owner ownership grant:** which files (solve_case.m, ts_simulate.m,
   ts_simulate_emf6.m, ts_simulate_padiyar_model11.m, ts_adaptive_driver.m) may
   this agent edit in Phase 2, and when? (Blocked until user checkpoints dialog.)
2. **Dialog system reconciliation:** after user checkpoints dirty main dialog
   work, how to merge factory wiring with `prompt_pf_options`/`prompt_ts_options`
   (extend dialogs to add `pf_method`/`integrator` prompts + capability-aware
   menu per §24).
3. **P3.5 provenance citation:** Süli & Mayers 2003 (verified) vs Hairer-Wanner
   ODE II (TOC-only → project-derived) for the eps^(1/3) central-FD optimality.
4. **Main merge of 31a211d:** when will main merge the IBR interface foundation
   so plan/pf-ts-multimethod can rebase onto main at a sync point?
5. **UI timing:** when to add capability-aware method menus (hide BFS for IEEE14,
   hide RK4 from production-default, hide ESDIRK until sourced).

## Minimum acceptance gates (Phase 2)

1. Default PF route == direct NR, AbsTol=0.
2. Default/explicit trapezoidal route == canonical baseline, AbsTol=0.
3. Every registered method records method_requested/method_executed/method_source/capability/fallback_used=false.
4. No silent fallback (unknown → error; topology violation → error).
5. adaptive+{BE,RK4} rejected before simulation starts.
6. RK4 not reachable as production-default/UI route.
7. BFS capability violations fail closed.
8. All model-specific fixed-step routes tested (classical/EMF6/Padiyar/bundle).
9. `test_no_external_solver_dependency` passes.
10. Full regression passes on integration commit (fresh count recorded).
11. `compare_case14_ts_three_way` + `compare_rts24_psat` run per availability; report honestly.
12. Report branch, tested commit, main commit, merge-base, exact commands, fresh counts, working-tree status.

## Stop conditions (integration-specific)

Stop and ask if: dirty user-owned file must be modified; main does not contain
31a211d and rebase would conflict; a model route's BE/RK4 diverges; event
semantics would differ by integrator; provider state/time cannot be preserved;
implementation requires external solvers; results improve only after tuning;
SSSA scope creep; ownership ambiguous; esdirk32 must silently fall back.

## First implementation slice (Phase 2, after approval)

C1 (checkpoint) → C2 (PF wiring + tests) → C3 (TS wiring + per-model tests)
→ C4 (P3.5 provenance). Each gated by full regression. Production routing
declared READY only after all acceptance gates pass AND the user confirms
dialog reconciliation is not needed for this slice (dialog stays user-owned).

`PF_TS_MULTIMETHOD_READY` remains NOT_READY until Phase 2 acceptance gates pass.
