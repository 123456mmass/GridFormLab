# 2026-07-21 — GFL-RMS10 SMIB unstable mode (~3.4e5 real eigenvalue)

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
