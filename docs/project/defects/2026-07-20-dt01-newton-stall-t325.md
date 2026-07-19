# dt=0.01 Newton/Jacobian stall at t=3.25 s (separate from domain-throw fix)

Date: 2026-07-20
Status: OPEN

## Symptom

After the domain-preserving Newton globalization fix
(`2026-07-19-domain-preserving-newton-globalization.md`) resolved the
`dt=0.005 lowVoltagePowerInversion` trial throw, the IEEE14 Profile-B
`1-SG + 4-IBR` run with `Zf=0.1i` at `dt=0.01` still fails at `t=3.25 s`
with `ts_simulate_ibr_hybrid:stepNewton` (residual `4.983e-4`). The
`dt=0.005` run passes and reaches the reclose workflow.

## Reproduction

```matlab
opt = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
opt.ibr_analysis = 'ts';
opt.plot_results = false; opt.verbose = false;
opt.ibr_events.Zf = 1i*0.1;
opt.dt = 0.01;
r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);
```

Observed: `converged=false`, `t_end=3.24`, `domain_rejected_trials=0`,
`subdivision_depth=4`, `failure_id=ts_simulate_ibr_hybrid:stepNewton`.

## Bounded diagnosis (classification only; no production change)

`scripts/diagnostics/replay_dt01_terminal_20260720.m` replays the
terminal interval from the SAME last-accepted state (t=3.24) with several
step sizes h:

| h | max\|rx\| | max\|rg\| | rcond(J) | rank |
|---|---|---|---|---|
| 0.01 | 1.931e+05 | 1.003e+02 | 1.999e-07 | 76 |
| 0.005 | 3.800e+04 | 4.366e+01 | 3.414e-07 | 76 |
| 0.0025 | 8.762e+03 | 2.194e+01 | 6.549e-07 | 76 |
| 0.001 | 1.661e+03 | 9.138e+00 | 1.594e-06 | 76 |

The residual-per-step trajectory around the failure is non-smooth:
`8.1e-11` (t=3.16), `1.354e-3` (t=3.18), `5.0e-11` (t=3.20),
`4.983e-4` (t=3.22), then `stepNewton` at t=3.25.

## Root cause (classification)

- `max|rx|` decreases first-order with h — the equations HAVE a solution
  at this operating point; the failure is a step-size/globalization
  defect, not physical infeasibility.
- `rcond(J)` is very low at every h (~2e-7 at h=0.01) and improves only
  slowly with h — the coupled Jacobian is near-singular/ill-conditioned
  at the terminal iterate, so the Newton step is poorly scaled and the
  line search cannot find a decrease.
- `rank` is full (76) at every h — the Jacobian is not structurally
  singular, only ill-conditioned.
- `domain_rejected_trials=0` rules out a domain throw on the trial path;
  `subdivision_depth=4` (the cap) confirms subdivision engaged and
  exhausted without rescue.
- The non-smooth residual trajectory is consistent with a
  limiter/anti-windup discontinuity or near-singular Jacobian at the
  terminal iterate.

This is a **step-size / Jacobian-conditioning globalization defect**,
distinct from the domain-throw defect (which is fixed). The
domain-preserving catch is correct and complete for its scoped defect;
it does not address this stall.

## Falsified hypotheses

1. **Domain throw on the trial path** — falsified:
   `domain_rejected_trials=0`.
2. **Physical infeasibility (no solution)** — falsified: `max|rx|`
   decreases first-order with h; a smaller h reaches the solution.
3. **Structural singularity** — falsified: `rank` is full (76) at every h.

## Candidate fixes (NOT implemented; require separate plan + approval)

- Domain-aware finite-difference Jacobian (avoid FD perturbations that
  cross limiter/anti-windup boundaries).
- Jacobian regularization / conditioning (e.g. scaling, trust-region).
- Limiter smoothing at the trial boundary.
- Adaptive step-size selection driven by Jacobian conditioning.

Each is a separate numerical-method contract and must not be tuned to
make the run pass; the equations, parameters, thresholds, and event
timing remain unchanged.

## Scope

Out of scope for the domain-preserving Newton globalization fix. The
`dt=0.005` route passes and reaches the reclose workflow; `dt=0.01`
remains blocked at this stall until a separate fix is approved.

## Not a regression

The `dt=0.01` failure at `t=3.25 s` is a pre-existing symptom documented
in the domain-preserving fix plan as the original `stepNewton` failure
(residual `4.983e-4`). The domain-preserving fix targets the
`dt=0.005 lowVoltagePowerInversion` trial throw, which is a different
failure mode. The fix does not change the `dt=0.01` path: at `dt=0.01`
no domain throw occurs (`domain_rejected_trials=0`), so the
domain-preserving catch is never engaged and the behavior is identical
with and without the fix. The positive evidence that the fix works is the
`dt=0.005` route, which engaged the catch 197 times and completed to
`t=15 s`.

## Related

- `2026-07-19-domain-preserving-newton-globalization.md` (the
  domain-throw fix; resolved).
- `scripts/diagnostics/replay_dt01_terminal_20260720.m` (bounded
  diagnosis).
- `scripts/diagnostics/decompose_stall_residual_20260719.m` (prior
  per-device residual decomposition; reported `rcond~7e-7`).
