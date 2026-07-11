# Master Plan — Production-Quality PF / SSSA / TS (end-to-end)

**Created:** 2026-07-11 (overwrites previous adaptive_ts_plan.md)  
**Definition of Done:** PF, SSSA, fixed-step TS, adaptive-step TS pass ALL required gates; Padiyar 15s AVR/manual has zero algebraic failures; Case14/RTS-24 vs PSAT pass; full regression clean; documentation matches runtime.

**Guiding principle:** "เหมือนเดิมเมื่อเดิมถูก และมี regression อธิบายชัดเมื่อจำเป็นต้องแก้พฤติกรรม" — bit-identical is NOT a goal when the baseline has a bug.

---

## CRITICAL ROOT CAUSE TO FIX (discovered in prior session)

**Long-horizon algebraic failure** — Padiyar AVR, Zf=j0.1, dt=0.01, t_end=15:
- Passes until ~4.25 s, algebraic solve breaks at 4.25–4.50 s
- Reducing dt to 0.005/0.0025 does NOT fix it → not purely a time-step issue
- **Root cause (suspected):** local solver reuses Jyy across many steps; Jacobian refreshed *inside* solve_g on line-search failure is NOT propagated back to the caller → stale Jyy accumulates
- The shared kernel (Phase 2 WIP) currently tries to preserve this bug bit-identically → **MUST NOT**

**Fix strategy:**
1. Reproduce the failure deterministically (regression test, BEFORE fix)
2. Fix root cause: algebraic Newton must refresh Jyy from current (x,y,Y); refresh on topology change / line-search failure / poor residual reduction / iteration threshold / large state change; propagate refreshed Jyy back OR do not cache across solves
3. Separate intended behavior change from mechanical refactor
4. Record before/after metrics

---

## Phase A — Audit current worktree

1. Read AGENTS.md, AGENT_HANDOFF.md, this plan, Padiyar contract, validation artifacts.
2. Inspect working tree: separate user changes vs current WIP; do NOT discard/overwrite.
3. Map TRUE call graph (trace from launcher to kernel, not from file existence):
   - PF → powerflow_newton_raphson
   - Padiyar SSSA → padiyar_model11_ssa → multimachine_ssa
   - Padiyar fixed TS → ts_simulate_padiyar_model11 (NOW calls ts_step_kernel)
   - EMF6 SSSA → synchronous_emf6_ssa
   - EMF6 fixed TS → ts_simulate_emf6 (NOW calls ts_step_kernel)
   - classical TS → ts_simulate (inline, direct Y\V — NO kernel)
   - shared: ts_step_kernel, ts_algebraic_solve, ts_jac_y_fd, ts_topology
4. Verify runtime path actually uses shared kernel (trace, don't assume).
5. Record baselines from REAL commands:
   - short horizon (3 s), 15 s, no-fault, Zf=j0.5, Zf=j0.1, solid fault if supported
   - **specifically capture the 4.25 s failure** for Padiyar AVR Zf=j0.1 dt=0.01 t_end=15

## Phase B — Power Flow (Definition of Done)

1. In-house Newton–Raphson only. No fsolve/lsqnonlin/fminsearch/external in production.
2. Audit: mismatch equations, Jacobian signs, REF/PV/PQ handling, gen/load sign, shunt, tap/phase-shift, external bus-ID mapping.
3. Convergence evidence: converged flag, iterations, max mismatch, finite state.
4. Padiyar Table 9.2: book = reference AFTER solve only; printed solution never drives solver.
5. Case14 + RTS-24: PF vs PSAT (primary); PGAz = secondary diagnostic only.
6. **Reference-independence test:** change Table 9.2 reference values to fake → PF result must not change.

**PF gates:** equations finite ✓ | converged ✓ | mismatch < declared tol ✓ | mapping correct ✓ | no external dependency ✓ | reference does not drive solver ✓ | Case14 PSAT PASS ✓ | RTS-24 PSAT PASS ✓

## Phase C — SSSA (Definition of Done)

SSSA uses SAME DAE as TS: ẋ=f(x,y,u), 0=g(x,y,u).

1. Equilibrium: max|f(x0,y0)|, max|g(x0,y0)|.
2. Central FD Jacobians: Jxx, Jxy, Jyx, Jyy.
3. FD convergence study: h=1e-4,1e-5,1e-6,1e-7 → physical eigenvalues converge.
4. Algebraic elimination: K=Jyy\Jyx; A=Jxx−Jxy*K. **No explicit inv(Jyy).**
5. Check: dimensions, finite, condition, conjugate-pair, angle-shift invariance, reference-angle mode.
6. State explicitly: full matrix / COI-reduced / both. No "COI reduction" claim if option='none'.
7. Modal metrics: eigenvalue, frequency, damping ratio, time constant.
8. Padiyar Table 9.5: secondary cross-check only; no tuning of frequency/params/scales.
9. **Falsification test:** change Table 9.5 reference → Afull + computed eigenvalues must not change.
10. Manual/no-AVR: 16 states, Efd fixed input, terminal V from algebraic network.
11. AVR: 20 states, dynamic Efd, correct equilibrium + voltage feedback.

**SSSA gates:** equilibrium residual ✓ | shared DAE ✓ | FD convergence ✓ | Schur solve ✓ | finite Jacobian ✓ | reference-angle structure ✓ | conjugate-pair ✓ | reference-independence ✓ | no calibration ✓ | manual(16)/AVR(20) state counts ✓

## Phase D — Shared TS kernel (finish Phase 2, FIX stale-Jacobian bug)

Shared components: ts_algebraic_solve, ts_jac_y_fd, ts_topology, ts_step_kernel.

**MUST fix root cause of long-horizon algebraic failure (NOT preserve it).**

Algebraic Newton must:
1. Build/refresh Jyy from CURRENT (x,y,Y).
2. Reuse only within a provable scope (one-step solve).
3. Refresh on: topology change, line-search failure, poor residual reduction, iteration threshold, large state change.
4. If refreshed inside solver: return updated Jacobian to caller OR do not cache across solves.
5. Check: condition estimate, finite Newton step, residual decrease.
6. Line search has explicit failure semantics.
7. Never accept algebraic state with residual not passing.

**Deterministic regression (must pass after fix):**
Padiyar AVR, Zf=j0.1, dt=0.01, t_fault=1.0, t_clear=1.1, t_end=15 → algebraic failures=0, nonconv accepted=0, all finite, residuals pass, events on grid, trajectory bounded (declared a priori).

Additional: dt=0.005, dt=0.0025, Zf=j0.5, Zf=j0.1, no-fault, manual, AVR, EMF6.

## Phase E — User-facing corrector configuration

1. Remove `max_corrector_iter` from USER SETTINGS of run_ts.
2. Keep internal safety cap (default ~20); solver stops when converged (not run to cap).
3. Override only for advanced/debug.
4. **No increasing cap to mask stale-Jacobian bug.**
5. Error message reports: time, update norm, trapezoidal residual, algebraic residual, iterations, dt, topology, fault status.
6. **Rename semantics:** old `corrector_mode='adaptive'` ≠ adaptive time-step → rename internal/report to `iterative` / `fixed_iterations`; reserve "adaptive" for LTE+reject time-step. Backward compat with deprecation warning.

## Phase F — Fixed-step TS (canonical validation path)

1. Exact event landing. 2. Topology convention (pre/faulted/post). 3. Algebraic Newton convergence. 4. Trapezoidal update convergence. 5. Trapezoidal residual convergence. 6. Finite states. 7. No silent continuation. 8. Deterministic raw grid. 9. Complete diagnostics.

Canonical cases: Padiyar AVR 3s, Padiyar AVR 15s, Padiyar manual 15s, true no-fault 15s, EMF6 no-fault, EMF6 fault, Case14 classical, RTS-24 classical. **3-second test alone is NOT long-horizon evidence.**

## Phase G — Adaptive-step TS (production candidate)

Start only after Phase 2 + fixed-step gates pass.

1. Shared step kernel (same as fixed). 2. Step doubling (full + two half). 3. e=(x_halfhalf−x_full)/3. 4. Weighted norm. 5. Accept/reject. 6. dt controller. 7. dt_min/dt_max. 8. Exact event landing. 9. Rejection limits. 10. Raw-grid diagnostics. 11. No extrapolation. 12. Segment-aware resampling.

Default stays fixed until ALL adaptive gates pass.

## Phase H — Test pyramid

1. Unit: Jacobian, algebraic Newton, topology, event grid, one-step kernel, error estimator, dt controller.
2. Contract: shared DAE, fixed/adaptive shared kernel, sign conventions, state/algebraic/input order.
3. Integration: PF→equilibrium→SSSA, PF→equilibrium→TS, SSSA/TS same residuals, event transition.
4. Long horizon: 15s Padiyar, no stale Jacobian, no algebraic failure.
5. Convergence: fixed O(h²) on smooth intervals, adaptive tolerance study, common-grid equivalence.
6. Full regression: clean restoredefaultpath, 0 failed, 0 incomplete (unless optional dependency + documented).

## Phase I — Cross-validation

Primary: PSAT. Cases: Case14, RTS-24. Metrics: PF |dV|, |dAngle|, COI angle/speed, Pe, Vbus, event alignment, extrapolation, convergence.

PGAz: secondary diagnostic only, never required gate, never relax tolerance.

Padiyar: PF vs Table 9.2, SSSA vs Table 9.5 (secondary), TS = project scenario. No PSAT claim without real converter/run.

## Phase J — Documentation (equations, not prose)

PF: mismatch, Jacobian, Newton update, stopping. SSSA: DAE perturbation, FD Jacobian, algebraic solve, Schur, eigenvalue, freq/damping/time-constant, reference-angle. TS: topology, algebraic Newton, predictor, corrector, residual, convergence, fixed vs adaptive, events, output reconstruction. Manual/no-AVR: fixed Efd, 4 state eqs, linearized field, difference from AVR. **Documentation must not claim behavior the code doesn't do.**

---

## FINAL ACCEPTANCE GATES

PF_PRODUCTION | PF_REFERENCE_INDEPENDENCE | SSSA_SHARED_DAE | SSSA_FD_CONVERGENCE | SSSA_REFERENCE_INDEPENDENCE | FIXED_SHARED_KERNEL | ALGEBRAIC_NEWTON_ROBUSTNESS | PADIYAR_15S_AVR | PADIYAR_15S_MANUAL | NO_FAULT_EQUILIBRIUM | EMF6_FIXED_TS | EXACT_EVENT_LANDING | FIXED_ORDER_CONVERGENCE | ADAPTIVE_ERROR_CONTROL | ADAPTIVE_EVENT_LANDING | FIXED_VS_ADAPTIVE | CASE14_PSAT | RTS24_PSAT | NO_EXTERNAL_PRODUCTION_DEPENDENCY | NO_REFERENCE_TUNING | FULL_REGRESSION | DOCUMENTATION_MATCHES_CODE

Any FAIL → OVERALL_PF_SSSA_TS_READY = FAIL, default production path unchanged.

---

## Prohibitions (selected, see spec K.1-24)

1. No fabrication/tuning. 2. No reference eigenvalues in solver. 3. No tolerance increase after results. 4. No iteration cap to mask root cause. 5. **No preserving baseline bug for bit-identical.** 6. No duplicated DAE/kernel. 7. No explicit inv(Jyy). 8. No accepting non-converged step. 9. No hiding algebraic failure. 10. No extrapolation/zero-fill. 11. No stepping past event. 12. "adaptive" reserved for LTE+reject. 13. No Phase 3 before Phase 2 passes. 14. No mixing mechanical refactor with behavior fix without detailing. 15. No editing PSAT/PGAz. 16. No discarding user changes. 17. No artifact in source commit. 18. No saved metrics as fresh. 19. No PASS if long-horizon fails. 20. No stopping because short test passes. 21. No asking which phase next — do them in order.
