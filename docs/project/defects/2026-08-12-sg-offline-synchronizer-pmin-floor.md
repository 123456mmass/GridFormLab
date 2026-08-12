# SG reclose SYNC_TIMEOUT: offline synchronizer command floored at Pmin=0

Date: 2026-08-12
Status: RESOLVED (arm + oracle + unit test; production 170 s confirmation pending)
Failure ID: `ts_simulate_ibr_hybrid` reclose_status `SYNC_TIMEOUT` (symptom);
root cause is the non-negative command floor in the breaker-open synchronizer.

## Symptom

The production `production_request` config (sg_trip=20, load_step=50,
fault 85/85.15, line_trip=110, restore=sg_on=145, sync `timeout_s=20`, dwell
0.5 s) reaches `t_end` but the SG reclose never fires:
`reclose_status=SYNC_TIMEOUT`, `handback_status=NOT_STARTED`. Confirmed
dt-independent (dt=0.10 and dt=0.01 both time out).

## Reproduction (read-only diagnostics)

- `chk_reclose_dt01_tmp.m` — loads `engine_release_result_dt01.mat`; over
  [145,165] (2002 records) `eligible` and `dwell_ok` are NEVER true;
  limiting_gate = theta 1992 / f 10; dtheta median ~106 deg.
- `chk_reclose_freq_tmp.m` / `chk_sync_history_tmp.m` — the SG locks FREQUENCY
  (df -> 7e-8) but the angle FREEZES at ~106 deg; the synchronizer command is
  identically 0 for all 2202 samples (`saturated-low 2202/2202`), phase_error
  ~ -106 deg, Pm -> 0.
- `chk_reclose_fix_test_tmp.m` — after the fix, compressed arm (t_end=24)
  recloses SUCCESS at 15.5 s, dtheta -> 0.72 deg, handback C1_ACTIVE.

## Root cause (with derivation)

The breaker-open SG obeys (helper header, `sg_offline_synchronizer_step.m`)
```
2H dω_sg/dt = Pm − D·ω_sg,   dδ_sg/dt = ω₀·ω_sg     (Pe = 0, breaker open)
```
Synchronizer command
```
Pm = sat(D·ω_grid + K_ω·(ω_grid−ω_sg) + K_θ·e_θ,  Pmin, Pmax),
K_ω = 4Hζω_n − D,  K_θ = 2Hω_n²/ω₀,  e_θ = wrap(θ_grid − θ_sg).
```
Unsaturated, the closed loop is exactly the requested critically-damped
second order (ζ=1, ω_n=0.8):
```
d²e_θ/dt² + 2ζω_n de_θ/dt + ω_n² e_θ = 0   →  e_θ → 0 from EITHER sign.
```
Two facts break this in production:
1. At alignment the steady command is `D·ω_grid`, and the island settles to
   ~nominal (`ω_grid → 0` deviation), so the steady command is ~0 and the
   angle correction must swing SYMMETRICALLY about 0.
2. `Pmin=0` (`ts_simulate_ibr_hybrid.m` offline `sopt`) truncates the negative
   half. When the SG LEADS the grid (`e_θ<0`, here −106 deg), the loop demands
   a NEGATIVE (decelerating) command; it clips to 0. Because the model damping
   `D·ω_sg` also vanishes at `ω_sg=0` (deviation), a rotor already at grid speed
   has NO decelerating torque available, so it coasts to `ω_sg=0` and the angle
   freezes at its standing offset (~106 deg). dtheta never enters ±10 deg ⇒
   `SYNC_TIMEOUT`.

The command trace proves it: `raw = K_θ·(−1.85 rad) ≈ −0.0157 < 0`, clipped to
`command = 0` for the entire [145,165] window.

## Fix

`+stability/ts_simulate_ibr_hybrid.m`, offline branch of `advance_sync_controller`:
change the synchronizer bound from `'Pmin',0` to `'Pmin',-c.Tmax` (symmetric
authority). The breaker-open command is the PROJECT_DERIVED synchronizer
actuator (a governor speed/torque bias during alignment, not literal turbine
output), so allowing a transient decelerating command is physically the "run
the incoming machine slightly slow to walk the phase to zero" action. The
ONLINE governor (post-close, `enter_online_governor`) keeps `Pmin=0` because a
loaded turbine genuinely cannot absorb power. Correction magnitude for a 106 deg
error is only ~0.016 pu, far from −Pmax; the bound merely removes the one-sided
clip.

## Verification

- Independent ODE oracle (`chk_sync_fix_oracle_tmp.m`, documented equations
  only): `Pmin=0` leaves e_θ frozen (final −163 deg); `Pmin=−Pmax` drives
  e_θ → 0 (enters ±10 deg at 4.76 s, matching 4/(ζω_n)≈5 s).
- Unit test `tests/test_sg_offline_synchronizer_retard.m` (drives the
  PRODUCTION `stability.sg_offline_synchronizer_step`): negative command clipped
  by Pmin=0 vs passed by Pmin=−Pmax; closed loop converges only with the
  symmetric floor; gains realize the 2nd-order poles. 3/3 PASS.
- Integration (`chk_reclose_fix_test_tmp.m`, compressed arm t_end=24, fixed
  stepper): reclose SUCCESS at 15.5 s, dtheta 51 deg → 0.72 deg, dwell reached,
  handback C1_ACTIVE.
- Production 170 s confirmation (`run_reclose_prod_confirm_tmp.m`): PENDING at
  time of writing.

## Falsified hypotheses

1. **Handback SSSA gate (H1)** — falsified. The 4-GFM SG-online candidate is
   STABLE (`chk_sssa_sgon_tmp`: omega=−0.23); derive_handback_duration is never
   reached (`handback_status=NOT_STARTED`). Unstable SG-online configs are the
   ones with GFL units (n_gfm 0/2/3, dominated by GFL Vd_del/Vq_del ~11 Hz).
2. **Synchronizer regression d63f48d→HEAD** — falsified. `sg_offline_synchronizer_step`,
   `synchronism_guard`, `reference_grid_omega`, gains, and `case_data.synchronism.*`
   are byte-identical across the range; the "d63f48d reclosed @154.3" figure was
   a stale-cache MISREPORT (corrected in commit `918c3c6`). Both commits time out.
3. **Decoupled DC state (V_dc)** — a real modeling critique (V_dc feed-forward
   cancels AC coupling → V_dc≡1.0 pu, eigenvalue −1/T_dc, participation 0 in all
   modes) but NOT the reclose cause; it never participates in the limiting mode.

## Limitations / scope

- This changes production reclose behavior (both fixed and adaptive stepper use
  the same synchronizer). It is an intended Phase-2 correction; the pre-fix
  byte-identity vs commit f9b710b no longer holds by design. The
  `test_ts_hybrid_fixed_bitident` default==explicit-fixed check still holds
  (both share the fixed code).
- The change is a control-authority bound (PROJECT_DERIVED), not an equation,
  base, event time, current limit, or acceptance threshold. `case_data.synchronism.*`
  gates are unchanged; no safety gate was relaxed.

## Related files

- `+stability/ts_simulate_ibr_hybrid.m` (offline synchronizer `sopt.Pmin`)
- `+stability/sg_offline_synchronizer_step.m` (control law; unchanged)
- `+stability/synchronism_guard.m` (band test; unchanged)
- `tests/test_sg_offline_synchronizer_retard.m` (new)
- `2026-08-10-sg-reclose-command-step-and-angle-gauge.md` (b6e510f gauge/handback)
- `2026-08-11-ts-kernel-runtime-optimization.md` (the 154.3 misreport correction)
