# Placeholder command-delay instability and quasi-static reduction (EECON49 IBR)

Date: 2026-08-12
Status: RESOLVED (device reduction + gates; production 250 s @ dt=0.05 confirmation in progress)
Failure ID: SSSA `physical_omega = +1.29` @ 11.4 Hz (all-GFL SG-online); TS
`ts_simulate_ibr_hybrid:stepNewton` at the bolted fault (secondary, see below).

## Summary

The EECON49 dual-mode IBR carried two command/actuation-delay states per
branch (`Vd_del/Vq_del`, source Eqs. 20-21) driven by a first-order lag
`T_d v_del_dot = v_cmd - v_del`. The delay time constant `T_d` is NOT published
by the source; it had been left at an unphysical placeholder `T_d = 0.02 s`.
That value sat only ~1 ms below the linearized delay margin `T_d,crit ~= 19 ms`
and produced a **spurious** small-signal instability in the all-GFL SG-online
configuration: `physical max Re = +1.29 s^-1` at `f = 71.8/(2*pi) = 11.4 Hz`.

## Observation vs inference

- OBSERVED: at `T_d = 0.02 s`, `composite_sssa_model` returns
  `physical_omega = +1.29` (all-GFL SG-online); the mode is robust across
  `fd_eps` in `[1e-8,1e-2]` (not an FD artifact) and both nonlinear TS
  integrators diverge under perturbation (real-in-model, not a gauge artifact).
- OBSERVED: a `T_d` sweep gives `max Re` flat at `-0.065` for
  `T_d in [0.15, 18] ms`, crossing into the RHP near `T_d ~ 19-20 ms` (Hopf).
- INFERENCE (owner authority, PROJECT_DERIVED): the physical digital-VSC
  actuation delay is `T_d = 1.5/f_sw` (1-sample compute + 0.5-sample PWM/ZOH);
  at `f_sw = 5 kHz`, `T_d = 3.0e-4 s`, ~63x below `T_d,crit`. The placeholder
  was ~13x larger than any physical converter delay.

## Root cause

The instability was an artifact of the oversized placeholder delay, not a
physical property of the all-GFL SG-online system. At the physical
`T_d = 0.3 ms` the pole `1/T_d ~ 530 Hz` sits far below the phasor step
`dt = 0.10 s`, so the state is unresolvable by the RMS engine and adds nothing
the phasor model can represent. By singular perturbation (`T_d << dt`) the fast
lag collapses onto its slow manifold `v_del = v_cmd`; the two delay states are
removed algebraically and the AC current dynamics use the commanded voltage
`vcd/vcq` directly. This is a standard model-order reduction that leaves the
equilibrium and the retained-state dynamics unchanged.

## Fix

State reduction 20->16 (dual), 12->10 (standalone GFL/GFM), active GFL 11->9,
active GFM 12->10:
- `+ibr/gfl_eecon49_full_model.m`, `+ibr/gfm_eecon49_full_model.m`: remove
  `Vd_del/Vq_del`; `dx(1)/dx(2)` use `vcd/vcq` directly; drop the `T_d` param.
- `+ibr/eecon49_dual_mode_model.m`: superset 16, index maps 4:9 (GFL) / 10:16
  (GFM); transfer/merge helpers renumbered; `mt(5)/gt(5)` unchanged (index 5 =
  omega/xi_PLL, ahead of the removed states).
- `+ibr/device_contract_metadata.m`: `ibr_eecon49_dual` nx 20->16; drop the 4
  delay rows and state names. (`ibr_dual_mode` nx=20 / `dual_rms10` nx=23 are
  different models, untouched.)
- `+cases/scenario_ieee14_1sg_4ibr.m`, `+ibr/build_ieee14_switch_system.m`:
  remove `T_d`; store `f_sw_Hz=5000` as the reduction basis.

## Secondary consequence (TS step size)

The retired placeholder `T_d = 0.02 s` had incidentally low-pass-filtered the
commanded voltage before the stiff AC-filter current dynamics
(`tau = L/omega_b ~ 4e-4 s`). Removing it exposes the discontinuous fault-onset
command jump at the bolted bus-9 fault (`Zf = 0.01+0.01i`). A fixed-`dt` sweep
of the reduced model (`chk_arm_dtsweep_tmp.m`) shows `dt = 0.10` stalls at fault
onset (`stepNewton`, residual 1.3e-2 even at subdivision depth 9) while
`dt in {0.05, 0.02, 0.01, 0.005}` all integrate to `t_end`. The production
report run therefore uses `dt = 0.05` (NUMERICAL_METHOD accuracy/stability
choice; owner-approved 2026-08-12). This is a step-size resolution matter, not a
model defect: the reduced model is fully integrable at `dt <= 0.05`.

## Verification

- G-STATE (`chk_gstate_tmp.m`): 29/29 — nx, contract metadata, branch-RHS and
  current match under new maps, mode-transfer current continuity ~1e-17.
- G-EQUIL/G-SSSA (`chk_gsssa_tmp.m`): all-GFL SG-online converges,
  `physical max Re = -0.0652` (STABLE; +1.29@11.4 Hz gone); all-GFM handback
  `-0.2307`. SG angle-gauge oracle (`test_sg_online_network_angle_quotient`)
  and Sauer-Pai reference tests pass.
- Tests: `test_ibr_eecon49_dual_mode_model` 13/13, `test_ieee14_eecon49_full_state`
  6/6 (incl. coordinated handback returns all-GFL, 2 switches each), TS-kernel
  determinism (`adaptive_rollback`, `fixed_bitident`) pass.
- SSSA tables regenerated (16-state inventory; all-GFL `Omega_worst=-0.065`).
- PENDING: full 250 s production chronology at `dt=0.05` (converged + reclose
  characterization).

## Narrative correction

The all-GFL SG-online system is small-signal STABLE (`-0.065`), not unstable.
GFM handback is required post-SG-trip for grid-forming reference and capacity /
robustness margin, NOT to cure a small-signal instability. The SG-off minimum
feasible GFM count also shifts (n_gfm=1 no longer feasible; feasible set {2,4}).

## Related

Files above; supersedes the `T_d=1.5/5000` interim edit. See
`docs/project/defects/2026-08-12-adaptive-hybrid-discontinuity-restart.md`
(adaptive path at the same discontinuity) and the SG reclose synchronizer
record. Reproduction harnesses: `chk_gstate_tmp`, `chk_gsssa_tmp`,
`chk_arm_dtsweep_tmp`, `chk_gts_prod_tmp` (repo root, uncommitted).
