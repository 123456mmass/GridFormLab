# 2026-07-21 — GFL-RMS10 SMIB unstable mode (~3.4e5 real eigenvalue)

Status: RESOLVED 2026-07-22 → root cause was a PLL phase-detector sign defect
(`v_q = -imag(Vdq)` instead of Yazdani eq 8.1 `v_q = +imag(Vdq)`). Fix applied
and verified by an independent 6-gate oracle and targeted tests (see
Verification below). The prior "RESOLVED (device property, not a defect)"
verdict below is SUPERSEDED and retained only as history.

## 2026-07-22 — Verification of the fix

Independent oracle `output/diagnostics/oracle_pll_signfix.m` (MATLAB R2025a):

- G1 equilibrium preserved: `||f0||inf = 2.79e-13`, `||g0||inf = 1.11e-16`
  (unchanged from pre-fix — the operating point does not move).
- G2 FD PLL 2x2 block: `trace = -3.4683e+05`, `det = +1.5954e+07`,
  `eig = [-3.4679e+05, -46.006]` (both stable; -46 = -1/Ti_pll as designed).
  Full SSSA `max_real_eigenvalue = -1.1234e+01` (was +3.37e5).
- G3 dominant mode (-11.23) is now the outer power loop (xi_P/P_f/xi_Q); the
  PLL is no longer the limiting mode.
- G4 perturbation restores lock both directions (delta_PLL +1e-3 -> d_delta_PLL
  = -346.8; -1e-3 -> +346.8).
- G5 `P+jQ = V*conj(I)` exact (|Pe-real(S)| = 0).
- G6 loaded-SMIB GFL sweep [0 20 40 60 80]%: all SUCCESS, stable
  (max_real -11.23 -> -11.09) (was +3.37e5 -> +3.33e5 unstable).

Targeted tests (109/109 PASS, 0 failed): test_ibr_gfl_rms10_model (26),
test_ibr_smib_sssa_oracle (9), test_ibr_gfl_rms10_sssa (4),
test_ibr_gfl_rms10_ts (5), test_ibr_gfl_rms10_dual (10),
test_ibr_gfl_rms10_metadata (8), test_ibr_gfl_rms10_routing (10),
test_sssa_load_sweep (31), test_ibr_gfm_vsg_no_pll_smib (6).

Test corrections: `test_pll_ode_form_matches_teodorescu` pinned the defective
`v_q=-imag(Vdq)`; corrected to `+imag(Vdq)` (source Yazdani eq 8.1 + oracle).
Stale unstable-mode comments in `test_ibr_smib_sssa_oracle.m` updated to the
stable post-fix behavior (the linear_overflow branch is retained but now takes
the stable path). `test_sssa_load_sweep.m` needed no expected-value change (it
never hard-pinned the unstable spectrum).

Full repository regression was intentionally NOT run, per explicit user
instruction to run targeted tests only. Residual risk: shared composite
SSSA/TS consumers of the GFL-RMS10 device in the IEEE14 mixed-resource path
were not exercised by the targeted set; those runs would now start from a
stable GFL spectrum.

## 2026-07-22 — REOPENING: PLL feedback polarity is inverted (root cause)

The prior verdict ("the ~3.4e5 unstable mode is a property of the GFL-RMS10
device model, not a bug") is **not supported**. The three falsified hypotheses
below (load term, equilibrium init, dispatch policy) never tested the PLL
phase-detector polarity, which is the actual cause.

### Analytical counterexample (det J_PLL < 0)

Code computed `v_q = -imag(V*exp(-1i*delta_PLL))`. With `V=|V|e^{j*theta_V}`:

```
v_q_code = -imag(Vdq) = -|V|*sin(theta_V - delta_PLL) = |V|*sin(delta_PLL - theta_V)
=> d(v_q)/d(delta_PLL)|_lock = +|V|
```

PLL law `d_xi_PLL = v_q`, `d_delta_PLL = omega_b*(kp_PLL*v_q + ki_PLL*xi_PLL)`
linearized about the lock point (`delta_PLL = theta_V`, `theta_V` fixed on an
ideal infinite bus) gives:

```
J_PLL = [ omega_b*kp_PLL*|V|   omega_b*ki_PLL ;   |V|   0 ]
trace(J_PLL) = +omega_b*kp_PLL*|V| ≈ 377*920*0.97 ≈ +3.36e5   (> 0)
det(J_PLL)   = -omega_b*ki_PLL*|V|                             (< 0)
```

`det < 0` forces one real eigenvalue of opposite sign — the equilibrium is a
**saddle**, which no correctly-locked PLL exhibits. The positive eigenvalue
`≈ trace ≈ +3.36e5` matches the reported `+3.37e5` to 3 significant figures,
proving the observed unstable mode IS the PLL loop, not a general device
property.

### Source verdict

- Yazdani & Iravani (2010) eq 8.1 (and eq 4.65): `f_d + j*f_q = f*e^{-j*rho}`,
  hence `f_q = +Im(f*e^{-j*rho})`. The cited convention is `v_q = +imag(Vdq)`.
- Teodorescu (2011) eq 4.24-4.25: phase-detector error `eps_pd ∝ (theta - theta')`
  drives a stable (negative-feedback) lock; the PI regulates the q-component
  to zero.
- The model's header comment already stated the intended value
  `v_q = |V|*sin(theta_V - delta_PLL)` (= +Im) but transcribed the operation as
  `-Im`; `-Im(Vdq)` actually equals `-|V|*sin(theta_V - delta_PLL)`. The single
  spurious minus inverted the phase-detector polarity.

### Why it stayed hidden

1. At equilibrium `delta_PLL = theta_V` → `v_q = 0`, so the sign is invisible;
   equilibrium residual is machine-zero (~1e-15) for either sign.
2. In the current loop `v_q` enters as feedforward `+v_q` (in `v_tq_raw`) and as
   plant disturbance `-v_q` (in `d_i_q`); these cancel, so the CLOSED current
   loop is sign-invariant. Only the PLL loop, driven directly by `v_q`, exposes
   the defect.

### Fix (Option A, source-faithful)

`v_q = -imag(Vdq)` → `v_q = +imag(Vdq)` in all three functions that compute it
(`f`, `model_current`, `model_reconstruct`) plus the header/inline comment
algebra. No gain, tolerance, state-order, limiter, or current-loop-structure
change. Post-fix `trace(J_PLL) ≈ -3.36e5 < 0`, `det(J_PLL) ≈ +1.55e7 > 0`
(both eigenvalues stable); the design gains (`ts_pll = 0.1 s`) then yield the
intended well-damped 2nd-order lock (dominant pole `≈ -1/Ti_pll = -46`).

Equilibrium is preserved bit-for-bit (v_q=0 at lock regardless of sign), so
this changes stability only, not the operating point.

---

## HISTORICAL (SUPERSEDED) verdict — retained for provenance

Status: RESOLVED (observation, not a defect in load-sweep code).

## Symptom

When running `stability.sssa_load_sweep` on the `smib_loaded_ibr/1.0` GFL-RMS10
case (`gfl_rms10_loaded_smib`), every load point reports
`sssa_diag.max_real_eigenvalue ≈ 3.4e+5` — a large positive real eigenvalue.
This is NOT a numerical bug introduced by the load-sweep workflow; it is a
property of the GFL-RMS10 device model operating against an infinite bus.

## Reproduction

```
pf_init_paths;
c = cases.case_ibr_smib_loaded_gfl_rms10();
opt = struct('sssa_load_percentages',[20 40 60 80], ...
    'sssa_save_plots',false,'case_id','gfl_test');
r = stability.sssa_load_sweep(c, opt);
% All 4 points: status=SUCCESS, eig=10, max_real_eigenvalue ~3.4e5
```

## Affected branch/commit/environment

- Branch: `main`.
- Starting commit (load-sweep baseline): `efa9617`.
- MATLAB R2023b+ (Windows).
- File: `+stability/+load_sweep/route_smib_ibr.m` (route adapter).

## Root cause (with evidence)

The GFL-RMS10 model (`ibr.gfl_rms10_model`) has an inherently unstable mode
when characterized against an ideal infinite bus. The same unstable eigenvalue
is present in the EXISTING ideal SMIB verification path:

```
pf_init_paths;
c = cases.case_ibr_smib_verification('gfl_rms10');
m = c.smib_verification;
dev = ibr.gfl_rms10_model(char(m.device_id),1,1,1,m.V_terminal,struct(), ...
    m.P_terminal_pu, m.Q_terminal_pu);
x = dev.equilibrium_initialize(m.V_terminal, m.P_terminal_pu, m.Q_terminal_pu, struct());
u = dev.u0;
V_inf = m.V_terminal - m.Z_line_pu * (dev.current_injection(0,x,...
    [real(m.V_terminal);imag(m.V_terminal)],u,struct()));
sssa = ibr.smib_sssa_oracle(dev, x, m.V_terminal, u, V_inf, m.Z_line_pu);
% IDEAL SMIB GFL: eig_count=10, max_real_eigenvalue ~3.37e5 (SAME magnitude)
```

The ideal-SMIB path (committed in `83390db` / `efa9617`, NOT touched by this
work) produces `max_real_eigenvalue ≈ 3.3715e+05` — the same order as the
loaded-IBR sweep (3.37e5 → 3.33e5 across load levels). The unstable mode is
therefore a property of the GFL-RMS10 device model, not of the load-sweep
code. The load sweep correctly reports this result honestly per the contract
(`SSSA_LOAD_SWEEP_PRODUCTION_READY = DIAGNOSTIC_ONLY`); it does NOT tune,
clip, or delete the unstable eigenvalue.

## Falsified hypotheses

1. **"The load term in local_g destabilizes the spectrum"** — FALSIFIED. The
   ideal SMIB (no load term) shows the same unstable eigenvalue.
2. **"The 2-stage equilibrium initialization corrupts the operating point"** —
   FALSIFIED. Residual norm at every load point is < 5e-12 (machine-precision
   convergence); the equilibrium is correct. The unstable mode is present at
   the equilibrium, not introduced by a bad solve.
3. **"The dispatch policy (IBR refs fixed) is wrong"** — FALSIFIED. Terminal
   voltage decreases monotonically with load (0.994 → 0.975) as expected
   physically; the equilibrium is physically meaningful. The unstable mode
   is a device-model property, independent of dispatch.

## Fix

No code fix. The unstable mode is an honest characteristic of the GFL-RMS10
device model. The load sweep reports it correctly; the GFM-no-PLL case
(`gfm_no_pll_loaded_smib`) shows `max_real_eigenvalue ≈ -0.56` (stable) at
every load point, confirming the workflow is sound.

## Verification

- `tests/test_sssa_load_sweep.m` — 27 tests pass, including
  `test_gfl_sweep_all_points_success` (verifies the sweep completes and
  reports the honest unstable spectrum without aborting).
- `test_A_from_same_device_equations` — Schur-direct relative error < 1e-6
  confirms `A` is built from the same device `f`/`current_injection` closures
  used by equilibrium, so the eigenvalue is a true property of the model.

## Limitations

The GFL-RMS10 device's unstable mode (~3.4e5) is large enough that any
downstream TS analysis starting from this equilibrium would diverge rapidly.
This is consistent with the existing ideal-SMIB verification TDS path, which
caps `T` at 0.05 s precisely because long unstable linear responses overflow
(`+ibr/run_smib_verification_case.m:58-60`). The load sweep does not run TDS;
it only reports the SSSA spectrum.

## Related files/commits

- `+ibr/gfl_rms10_model.m` (device model — NOT edited by this work).
- `+ibr/smib_sssa_oracle.m` (ideal-SMIB SSSA oracle — NOT edited; shows same
  unstable eigenvalue).
- `+ibr/smib_loaded_equilibrium.m`, `+ibr/smib_loaded_sssa_oracle.m`,
  `+stability/+load_sweep/route_smib_ibr.m` (new, this work).
- Commits `83390db`, `efa9617` (ideal-SMIB verification baseline).
