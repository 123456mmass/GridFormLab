# Domain-preserving Newton globalization for GFL-RMS10 trial-iterate throws

Date: 2026-07-19 (diagnosed); 2026-07-20 (fix delivered)
Status: DOMAIN_THROW_RESOLVED / END_TO_END_GATE_BLOCKED

The domain-throw defect is fixed and verified by targeted tests. The original
two-dt end-to-end acceptance gate is **not** fully met: `dt=0.005` passes and
reaches the reclose workflow, but `dt=0.01` still fails at `t=3.25 s` with
`domain_rejected_trials=0` and `subdivision_depth=4` — a separate
non-domain Newton/Jacobian failure that is out of scope for this fix and
tracked as a follow-up defect. See "End-to-end original scenario" below.

## Symptom

The IEEE14 Profile-B `1-SG + 4-IBR` full-analysis run with `Zf=0.1i` died at
`t=3.25 s` — before the scheduled `sg_trip=5 s` and `sg_on=8 s` events — so
the SG reclose workflow was never reached. The failure surfaced as:

- `dt=0.01`: `ts_simulate_ibr_hybrid:stepNewton` with residual `4.983e-4`.
- `dt=0.005`: `ibr:gfl_rms10_model:lowVoltagePowerInversion` thrown from
  `gfl_rms10_model.model_f` while `composite_newton` evaluated a **line-search
  trial iterate**.

## Proven defect (root cause of the dt=0.005 domain throw)

The damped-Newton owner `composite_newton` propagated any exception raised
during the line-search trial evaluation `residual_fn(z_new)` straight to the
caller. The classified RMS10 runtime domain exception
(`ibr:gfl_rms10_model:lowVoltagePowerInversion`) is raised by the device model
when a *trial* iterate leaves the balanced-LVRT voltage domain, not when the
*accepted* iterate does. Accepted-trajectory instrumentation proved the
accepted RMS10 terminal voltages never fell below `0.48735` at IBR bus 8 and
`0.45766` overall — both far above the configured `V_div_min=0.1`. The throw
was therefore a Newton-globalization defect (a trial outside the domain
aborted the whole solve), not a physical endpoint LVRT violation.

Because the exception bypassed the `trial.converged=false` path,
`advance_with_subdivision` never received a failed step to bisect, so its
existing timestep bisection could not engage.

This is the root cause of the `dt=0.005 lowVoltagePowerInversion` throw and
**one** failure mode of the fault-window Newton globalization. It is NOT the
root cause of the `dt=0.01` death at `t=3.25 s`, which is a separate
non-domain failure mode tracked as `IBR-2026-07-20-01`.

## Falsified hypotheses

1. **Physical LVRT violation at the accepted endpoint** — falsified by
   instrumented accepted-trajectory voltage traces: accepted `min|V|` at IBR
   buses `0.48735 > V_div_min=0.1`.
2. **Timestep too large (dt-convergence defect)** — falsified by the
   dt-convergence diagnostic: smaller `dt` did not rescue the solve; the
   throw persisted and merely moved with the step grid.
3. **Shallower fault impedance** — out of scope; `Zf` is a source/case value
   and must not be tuned to make the run pass.
4. **`voltageOutsideValidityDomain` as a runtime trial ID** — falsified by
   stack-trace evidence: that ID is a constructor/equilibrium-init contract
   and has no runtime trial-path stack. Only `lowVoltagePowerInversion`
   appears on the TS trial path.

## Correction

Opt-in, backward-compatible domain-preserving line search confined to the TS
trial path. No equation, parameter, threshold, tolerance, event timing,
accepted-state rule, or PF/equilibrium/SSSA result changed.

### `+stability/composite_newton.m` (single Newton owner)

- Extended ABI: optional 7th input `opt`, always-returned 7th output `info`.
  Omitted `opt` reproduces the six-output legacy contract exactly (verified
  by `test_default_opt_preserves_six_output_legacy_behavior`).
- `try/catch` wraps **only** `r_new = residual_fn(z_new)` inside the
  alpha-halving loop. The current/initial residual, Jacobian/FD, and final
  residual/Jacobian reporting remain uncaught.
- Classifier is an exact `strcmp` on the single confirmed runtime ID
  `ibr:gfl_rms10_model:lowVoltagePowerInversion`. Every other exception
  `rethrow(me)` immediately (no alpha halving, no swallowed root failure).
- A classified trial: increments `domain_rejected_trials`, records bounded
  diagnostics, never assigns `z`/`r`/`residual_norm`/`J_final` from the
  trial, halves `alpha` via the existing `1, 1/2, ..., 2^-19` sequence, and
  continues. The legacy acceptance rule
  (`all(isfinite(r_new)) && norm(r_new,inf) < residual_norm`) is unchanged.
- Diagnostic callback is pure (no DAE/device callbacks); if it errors, the
  original device exception is rethrown so the root failure stays visible.
- `info` is additive and bounded: `domain_rejected_trials`,
  `line_search_exhausted`, `residual_before_line_search`,
  `final_tested_alpha`, `minimum_trial_voltage`, `final_domain_violation`,
  `minimum_voltage_violation`. No rejected-trial state/residual vector is
  retained.

### `+stability/ts_step_composite.m`

- Policy enabled only when `step_opt.domain_preserving_trials=true`;
  `ts_simulate_ibr_hybrid` is the sole caller that sets it. Equilibrium,
  SSSA, and `ts_simulate_composite` remain default-off.
- Local classifier/diagnostic helpers (no new public abstraction):
  - `trial_domain_classifier` — exact-ID predicate.
  - `trial_domain_diagnostic` — pure voltage reconstruction from `z_trial`
    via `free_vars`/`vcon_vars`/`vcon_ref` (same mapping as
    `coupled_residual`); never calls `dae_f`/`dae_g`/`reconstruct`/
    `current_injection` or any device callback.
  - `resolve_runtime_mode` — reads `event_context.hybrid_state` to report
    only online GFL resources; inactive GFM/tripped branches are never
    counted as violators.
  - `read_runtime_min_voltage` — reads the threshold from dual-mode
    provenance or standalone RMS10 params; no hard-coded `0.1`, no
    exception-message parsing.
- Reports every below-threshold online GFL device (`violating_devices`),
  not just the first by loop order; never claims a single exact throw owner
  when multiple devices are below threshold.
- Publishes `step.newton_info` and `step.domain_rejected_trials` additively.

### `+stability/ts_simulate_ibr_hybrid.m`

- Sets `domain_preserving_trials=true` in `step_opt`.
- Initializes/run-aggregates/publishes `res.domain_rejected_trials`,
  `res.subdivision_depth`, `meta.domain_rejected_trials`,
  `meta.subdivision_depth`; same fields in `empty_result` for stable
  early-fail shape.
- `advance_with_subdivision.stats` extended: `attempts`,
  `accepted_leaf_steps`, `domain_rejected_trials` (parent + children),
  `subdivision_depth` (max recursion reached), `terminal_domain_failure`
  (terminal-leaf evidence only).
- Invariants preserved: subdivision starts only after a Newton step returns
  failed/nonfinite; left-child state used only if left converged+finite;
  right child starts from the accepted left endpoint; rejected parent/trial
  state never flows to children or the published trajectory; terminal-leaf
  evidence is not overwritten during recursive unwind.
- Event targeting unchanged: the main loop bounds `target` by the next
  scheduled event before subdivision; recursion halves that interval, so
  scheduled fault/event boundaries are never crossed and internal
  half-step samples are never published.
- `format_step_failure` composes a domain-specific message (logical failure
  time, terminal `h`, residual before line search, `final_tested_alpha`,
  exact domain ID, `violating_devices`, minimum trial voltage) only when
  the terminal leaf has classified evidence; otherwise the original generic
  `stepNewton` message is preserved. Aggregate counters never relabel an
  ordinary Newton failure as domain exhaustion.
- `pick_terminal_failure` uses a has-evidence predicate so a `struct([])`
  cannot override real terminal-leaf evidence.

### `+stability/run_hybrid_case.m`

- Copies `domain_rejected_trials`/`subdivision_depth` to the public result
  on every normal/fail-closed construction path; `ts_safe_counter` returns
  0 for missing fields.
- Adds both fields to `execution_summary`.

### `+ibr/dual_mode_ibr_model.m` (provenance only)

- Forwards `gfl_runtime_min_voltage` from the standalone GFL device
  provenance (`gfl_dev.provenance.params.V_div_min`) into
  `dev.provenance.gfl_runtime_min_voltage`. Pure additive metadata; no
  model callback or equation change.

## Verification

### Unit tests — `tests/test_composite_newton_contract.m` (9 tests)

- `test_default_opt_preserves_six_output_legacy_behavior`: omitted `opt`
  reproduces the six-output contract exactly; additive `info` shape clean.
- `test_domain_trial_rejected_then_smaller_alpha_accepted`: full-step trial
  throws the domain ID once (nested-function one-shot flag); alpha=0.5
  trial accepted; `domain_rejected_trials=1`; accepted iterate comes from
  the valid trial; `minimum_trial_voltage=0.5`.
- `test_all_domain_trials_exhaust`: all 20 trials throw; `converged=false`;
  `z_sol==last accepted`; `domain_rejected_trials=20`;
  `final_tested_alpha=2^-19`; `line_search_exhausted=true`;
  `residual_before_line_search` preserved.
- `test_non_domain_exception_rethrows_immediately`: `badState` rethrows
  exact ID, no alpha halving.
- `test_domain_exception_at_accepted_point_rethrows`: classified throw at
  the current/initial residual rethrows (not relabeled as rejected trial).
- `test_domain_exception_from_jacobian_rethrows`: classified throw from
  Jacobian/FD rethrows (no line-search alpha owns an FD perturbation).
- Plus the three pre-existing legacy contract tests (unchanged).

Result: **9/9 PASS** (MATLAB R2026a, `matlab -batch`).

### TS policy tests — `tests/test_ts_domain_preserving_newton.m` (5 tests)

- `test_classifier_accepts_only_lowVoltagePowerInversion`: exact-ID
  predicate accepts only the confirmed runtime ID; rejects
  `voltageOutsideValidityDomain`, `badState`, `nonfiniteRhs`,
  `equilibriumCurrentLimit`, and unrelated MATLAB IDs.
- `test_opt_in_rejects_then_accepts_smaller_alpha`: end-to-end through the
  public solver; one-shot throw, alpha halving, accepted iterate from the
  valid trial, `domain_rejected_trials=1`, `minimum_trial_voltage=0.5`.
- `test_opt_in_exhaust_reports_terminal_leaf`: all trials throw;
  `converged=false`; `domain_rejected_trials=20`;
  `final_tested_alpha=2^-19`; `line_search_exhausted=true`.
- `test_opt_in_non_domain_exception_rethrows`: `badState` rethrows exact ID.
- `test_run_hybrid_case_early_fail_publishes_counters`: invalid scenario
  never reaches TS; public result and execution summary still expose the
  additive counters with a stable 0 shape.

Result: **5/5 PASS**.

### Numerical invariance gates (existing tests, expected values unchanged)

| File | Passed | Failed | Incomplete |
|---|---|---|---|
| `test_equilibrium_active_bound_contract.m` | 28 | 1* | 1* |
| `test_ibr_gfl_rms10_sssa.m` | 4 | 0 | 0 |
| `test_ibr_gfl_rms10_ts.m` | 5 | 0 | 0 |
| `test_ts_shared_kernel.m` | 14 | 0 | 0 |
| `test_ieee14_ibr_ts_event_runner.m` | 19 | 0 | 0 |
| `test_ibr_sg_on_all_gfl_equilibrium.m` | 6 | 0 | 0 |
| `test_ibr_rms10_sg_off_equilibrium.m` | 2 | 0 | 0 |
| `test_ieee14_multi_gfm_equilibrium.m` | 15 | 0 | 0 |
| `test_ieee14_sg_reference_equilibrium.m` | 3 | 1* | 0 |

`*` Pre-existing failures confirmed by `git stash` baseline comparison on
the unmodified tree: `test_mixed_equilibrium_solve_enters_callback_path`
(`active_bound_regime_history` field / G2 convergence) and
`test_ref_voltage_controls_and_all_kcl` (`Tm_solved_pu`/`Efd_solved_pu`
equal to scheduled). Both are in the `mixed_equilibrium_solve` path, which
calls `composite_newton` with the 6-arg default form (no `opt`), so they
are unrelated to this change and retained as known limitations.

### End-to-end original scenario

`scripts/diagnostics/verify_domain_preserving_fix_20260720.m` and
`scripts/diagnostics/diagnose_dt01_t325_20260720.m` run the production
`Zf=0.1i` route at `dt=0.01` and `dt=0.005` with no shadow code. Evidence
is recorded in `output/diagnostics/`.

| dt | converged | t_end | domain_rejected_trials | subdivision_depth | failure_id |
|---|---|---|---|---|---|
| 0.01 | false | 3.24 s | 0 | 4 | `ts_simulate_ibr_hybrid:stepNewton` |
| 0.005 | true | 15.0 s | 197 | 4 | — (reaches `sg_reclose_timeout` at 13 s) |

**dt=0.005 (PASSES):** the prior `lowVoltagePowerInversion` throw at a
line-search trial is now a rejected trial; the domain-preserving catch
engaged **197 times** and the run completed all 3005 accepted samples to
`t=15 s`, reaching `sg_trip=5 s`, `sg_on=8 s`, and terminating at
`sg_reclose_timeout=13 s` (CASE_DEFINED synchronism timeout). Accepted IBR
terminal voltages stayed `min|V|=0.48825 >= V_div_min=0.1`;
`domain_rejected_trials=197` and `subdivision_depth=4` are published;
scheduled event landings are exact; no non-domain exception is swallowed.
The reclose workflow is reached and reports `SYNC_TIMEOUT` — a physical
synchronism outcome, not a numerical failure.

**dt=0.01 (STILL FAILS — separate defect):** the residual-per-step
trajectory around the failure is non-smooth — `8.1e-11` at `t=3.16`,
`1.354e-3` at `t=3.18`, `5.0e-11` at `t=3.20`, `4.983e-4` at `t=3.22`,
then `stepNewton` at `t=3.25`. Critically, `domain_rejected_trials=0`:
**no classified domain throw occurred**, so the domain-preserving catch
was never engaged. `subdivision_depth=4` shows `advance_with_subdivision`
bisected to its cap and still could not find a convergent sub-step. This
is a non-domain Newton/Jacobian failure (near-singular conditioning or
limiter/anti-windup discontinuity), not a trial-voltage violation. It is
out of scope for this fix and is tracked as a follow-up defect
(`2026-07-20-dt01-newton-stall-t325`).

### Bounded diagnosis of the dt=0.01 stall (classification only)

The dt=0.01 failure was classified with read-only instrumentation
(`scripts/diagnostics/replay_dt01_terminal_20260720.m`); no production
code, equation, parameter, or tolerance was changed. The terminal interval
was replayed from the SAME last-accepted state (t=3.24) with several step
sizes h:

| h | max\|rx\| | max\|rg\| | rcond(J) | rank |
|---|---|---|---|---|
| 0.01 | 1.931e+05 | 1.003e+02 | 1.999e-07 | 76 |
| 0.005 | 3.800e+04 | 4.366e+01 | 3.414e-07 | 76 |
| 0.0025 | 8.762e+03 | 2.194e+01 | 6.549e-07 | 76 |
| 0.001 | 1.661e+03 | 9.138e+00 | 1.594e-06 | 76 |

Interpretation:

- `max|rx|` decreases first-order with h (1.931e+05 -> 1.661e+03, ~100x for
  10x h reduction) — the equations HAVE a solution at this operating
  point; the failure is a step-size/globalization defect, not physical
  infeasibility.
- `rcond(J)` is very low at every h (~2e-7 at h=0.01) and improves only
  slowly with h — the coupled Jacobian is near-singular/ill-conditioned
  at the terminal iterate, so the Newton step is poorly scaled and the
  line search cannot find a decrease.
- `rank` is full (76) at every h — the Jacobian is not structurally
  singular, only ill-conditioned.
- `domain_rejected_trials=0` rules out a domain throw on the trial path;
  `subdivision_depth=4` (the cap) confirms subdivision engaged and
  exhausted without rescue.

This is a **step-size / Jacobian-conditioning globalization defect**,
distinct from the domain-throw defect fixed here. A full root-cause fix
(domain-aware FD, Jacobian regularization, or limiter smoothing) is a
separate numerical-method contract and requires its own plan and approval.
It is tracked as `IBR-2026-07-20-01`.

### Distribution of the 197 dt=0.005 domain rejects

`scripts/diagnostics/analyze_dt005_rejects_20260720.m` confirms the 197
domain-rejected trials are concentrated in the fault window (3.0-3.1 s)
where trial iterates transiently leave the balanced-LVRT domain, while
the accepted trajectory never violates `V_div_min=0.1` (accepted
`min|V|` at IBR buses = 0.48825; overall 0.45845). After fault clear
(3.1 s) voltages recover above 0.9 pu and no further domain rejects are
needed. This is the intended behavior of the domain-preserving catch:
reject transient trial excursions, never consume their state, and let
the existing alpha backtracking find a valid iterate.

## Classification

- Domain-preserving line search, exact-ID classifier, alpha backtracking
  reuse, additive diagnostics, subdivision aggregation, event-boundary
  preservation: `PROJECT_DERIVED` / `NUMERICAL_METHOD`.
- Threshold attribution reads the frozen `V_div_min` from device
  provenance; no new validity-domain schema.
- FD/Jacobian exceptions remain fail-closed (no line-search alpha owns an
  FD perturbation); domain-aware FD is a separate numerical-method
  contract and out of scope.

## Limitations

- The fix globalizes the TS trial path only. Equilibrium, SSSA, and
  `ts_simulate_composite` remain default-off and bit-identical.
- `voltageOutsideValidityDomain` is not allowlisted; it remains a
  constructor/equilibrium-init contract and rethrows on the runtime path.
- Two pre-existing equilibrium-path failures (above) are unrelated and
  retained as known limitations; they do not block this delivery.
- **dt=0.01 end-to-end gate is NOT met.** The domain-throw defect is
  resolved (dt=0.005 passes and reaches the reclose workflow), but dt=0.01
  still fails at `t=3.25 s` with `domain_rejected_trials=0` — a separate
  non-domain Newton/Jacobian stall tracked as
  `2026-07-20-dt01-newton-stall-t325`. The domain-preserving fix is
  correct and complete for its scoped defect; it does not claim to fix the
  dt=0.01 stall.
- Full repository regression: **1185 passed / 10 failed / 7 incomplete**
  (MATLAB R2026a, `matlab -batch`, tested tree `ea7150f` with the
  domain-preserving fix applied). All 10 failures were confirmed
  pre-existing by `git stash` baseline comparison on the unmodified tree
  (they fail identically without the fix): 2 in the
  `mixed_equilibrium_solve` path (6-arg default `composite_newton` form,
  unrelated), 2 in `test_ibr_launcher_settings_ui` (UI dialog), 2 in
  `test_ibr_ts_plotting_absolute` (figure creation), 1 in
  `test_ibr_equilibrium_initializer` (SG device), 1 in
  `test_ieee14_1sg_4ibr_phaseB1`, 1 in `test_wizard_characterization`, 1
  in `test_wizard_ibr_subanalysis`, 1 in
  `test_ieee14_sg_reference_equilibrium`. None are caused by the
  domain-preserving change. The 7 incomplete are the pre-existing
  `test_pgaz_conversion_contract` assumption filters (external pgaz tool
  not installed).
