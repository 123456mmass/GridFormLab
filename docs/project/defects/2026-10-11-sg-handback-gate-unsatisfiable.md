# SG handback gate unsatisfiable for self-governing SG plants

**Status:** RESOLVED (fix applied, verification run in progress)
**ID:** RECLOSE-2026-10-11-01
**Environment:** Windows 11, MATLAB R2026b (26.2.0.3386108), branch
`checkpoint/ne39-160s-20261009`, base commit `f79bead`

## Symptom

The NE39 1SG+9IBR chronology reached a real, fully guarded SG reclose
(`reclose_status=SUCCESS` at t=119.520001, `right_KCL=4.85e-10`, continuity
`PASS_NO_STATE_OR_INPUT_RESET`), and the post-reclose supervisor then requested
the release of every converter on **4295 consecutive accepted samples** with all
its own evidence green — yet no converter was ever returned to GFL. The run
ended with:

```
reselection_status   = PENDING_SEVERITY
handback_status      = NOT_STARTED
actual_mode_reselection_time = NaN
final modes          = all nine IBRs GFM
```

Evidence: `output/diagnostics/ne39_reclose_applied_probe_20261011_121120_812`.

## Evidence that every supervisor gate was satisfied

From the run's own `ne39_decision_log` (post-reclose, last decision at t=160):

| Quantity | Value | Policy ceiling | Verdict |
|---|---|---|---|
| severity (max over 9 IBR) | 0.02799 | `si_off` 0.35 | pass |
| ROCOF (max abs, Hz/s) | 1.185e-4 | `rocof_max` 1 | pass |
| ROCOV (max abs, pu/s) | 3.033e-5 | `rocov_max` 1 | pass |
| per-device `valid` | all true | — | pass |
| v_pu | 0.9715 .. 1.0748 | [0.9, 1.1] | pass |
| f_Hz | 60.0279 | [59.5, 60.5] | pass |
| `release` flag | **1** | — | pass |
| `T_minimum_hold` after reclose | 40.48 s elapsed | declared hold | pass |

Reason histogram over the 4295 post-reclose decisions:
`RELEASE_PENDING_CERTIFICATE` = 4295, `EVIDENCE_UNAVAILABLE` = 1. The policy
therefore never held on its own terms; it asked to release every single sample.

## Root cause

`ts_simulate_ibr_hybrid` gated the release on the SG governor handback having
finished:

```matlab
hold_ok = isfinite(actual_reclose) && ...
    t-actual_reclose >= settings.T_minimum_hold-settings.event_tol && ...
    sync_ctl.handback_complete;          % <-- unsatisfiable here
```

`sync_ctl.handback_complete` is produced by `enter_online_governor`, which is
only reached when `initialize_sync_controller` successfully armed the external
Sauer-Pai turbine/governor. That arming intentionally returns early for the
seven-state `sg_classical_reclose` plant (`+stability/sg_classical_reclose_device.m`,
`device_type='sg_classical'`, nx=7,
states `[delta,omega,Psv,Pm,Emag,theta_hat,nu_hat]`, inputs `[P_ref,Emag_ref]`,
`provenance.model='sg_classical_reclose_project_derived'`). That model is
**self-governing**: online it computes
`Pc = P_ref + no_load_loss - K_online_droop*(omega-1)` and ramps `Psv`/`Pm`
through its own `Tsv_s`/`Tch_s` states, so there is no external handback ramp to
await and no `Tm`/`Efd` input pair to drive. The schedule agrees:
`sched.has_sync_controller = 1` while `handback_status` stays `NOT_STARTED`.

The release gate therefore ANDed a satisfiable condition (hold time) with an
unsatisfiable one, for every sample of the run. The supervisor was correct; the
gate asked for evidence that this plant model cannot produce by construction.

## Falsified first hypothesis (recorded so it is not reintroduced)

The first diagnosis proposed relaxing the `device_type=='sg_classical'` guard in
`initialize_sync_controller`, on the assumption that the type name was stale.
That was **wrong** and would have thrown, not fixed anything:

- line `dae.devices(k).nx~=6` → `syncControllerSg` (the plant has nx=7)
- `input_names` must contain `Tm` → it has `P_ref`
- `input_names` must contain `Efd` → it has `Emag_ref`

`+stability/sg_classical_reclose_device.m:44-47` already states the contract:
inputs are reference commands `[P_ref,Emag_ref]`, "NOT the actual ...", and a
caller wanting governor behaviour "must add explicit support rather than relabel
P_ref as actual Pm". The guard is correct; the gate was the defect.

## Correction

One condition, in `run_hybrid_case`'s release path only:

```matlab
hold_ok = isfinite(actual_reclose) && ...
    t-actual_reclose >= settings.T_minimum_hold-settings.event_tol && ...
    (~sync_ctl.enabled || sync_ctl.handback_complete);
```

`sync_ctl.enabled` is true exactly when the external governor was armed, so a
six-state EMF6 SG keeps requiring `handback_complete` unchanged. For a
self-governing plant the handback clause is dropped and the remaining gates
decide alone and unmodified: the authenticated SG_ON one-step candidate, the
severity/ROCOF/ROCOV release dwell, `T_minimum_hold`, and the transactional
right-limit KCL. No threshold, ceiling, dwell, or acceptance gate was changed;
no state was reset; no candidate was forced.

## Verification

**A/B regression, same machine and MATLAB release:**

| Suite | Clean baseline `f79bead` | With fix |
|---|---|---|
| `test_ne39_sg_reclose_plant` + `_wiring` + `_dynamic_sssa` | 30 pass / 0 fail | **30 pass / 0 fail** |
| `test_c1_smoothstep_handback`, `test_identity_reference_handback`, `test_ts_hybrid_handback_command_timescale`, `test_ieee14_ibr_sg_reclose_workflow` | 14 pass / 6 fail / 1 incomplete | 23 pass / 6 fail / 1 incomplete |

The same six sub-tests of `test_ieee14_ibr_sg_reclose_workflow` fail in both
arms, with the identical failure ids (`PENDING_SYNC_FAIL`, expected `SUCCESS`) —
that failure is **pre-existing on this branch and not caused by this change**.
It was established by stashing the change and re-running the file at the clean
commit, not by inference.

**Behavioural proof:** the full 160 s chronology re-run with the fix, checking
`reselection_status`, `actual_mode_reselection_time`, the final
`device_modes_history`, and the `sg_reselection` event's right-limit KCL.

## Limitations

- The pre-existing `test_ieee14_ibr_sg_reclose_workflow` failure is a separate
  open defect; it is not analysed or repaired here.
- The fix removes a wait, never a check: a model that HAS an external governor
  behaves exactly as before, because `sync_ctl.enabled` is then true.
- `production_certified` and `hardware_certified` remain false on every artifact
  in this line of work.
