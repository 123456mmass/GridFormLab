# Stale 30-iteration lease encoded in `test_algebraic_residual_in_tol_range`

- **ID:** TEST-2026-08-11-01
- **Status:** OPEN (reported, not repaired — outside the authorized allowlist of
  the TS runtime-performance work that found it)
- **Area:** shared algebraic solver test contract
- **Branch / commit observed:** `main`, working tree during the TS
  runtime-optimization work (`b6e510f` plus uncommitted performance changes)
- **Environment:** MATLAB R2026a, Windows 11

## Symptom

```
Assertion failed in test_ts_shared_kernel/test_algebraic_residual_in_tol_range
assertError failed.
--> The function did not throw any exception.
    Expected Exception: 'ts_algebraic_solve:failed'
tests/test_ts_shared_kernel.m:224
```

## Reproduction

```matlab
pf_init_paths;
runtests('tests/test_ts_shared_kernel.m');
```

## Observation vs inference

Observation: the test supplies `g(y)=y`, `y0=1`, a deliberately wrong Jacobian
`J=2` so each damped-Newton step halves `y`, and `tol=1e-11`. It asserts that
`stability.ts_algebraic_solve` throws `ts_algebraic_solve:failed`.

Its own comment states the mechanism it relies on
(`tests/test_ts_shared_kernel.m:216-223`): *"After 30 iterations residual =
1/2^30 = 9.31e-10, which is in (tol=1e-11, 100*tol=1e-9). Must throw."*

Inference (arithmetic, not measurement): `+stability/ts_algebraic_solve.m:24`
now iterates `for k = 1:60`. After 60 halvings the residual is
$2^{-60}\approx8.67\times10^{-19}$, which is far below `tol=1e-11`, so the
solver converges and correctly does **not** throw. The test therefore encodes a
lease value that the production contract no longer has.

The lease was raised from 30 to 60 deliberately, with its own record and an
in-source rationale (`+stability/ts_algebraic_solve.m:19-24`,
[fault-on solver lease](2026-08-05-eecon49-faulton-solver-lease.md)). The
regression this test was written to catch — *a residual in the band
`tol < r < 100*tol` must not be silently accepted* — is a real contract and is
still worth testing; only the iteration count that produces such a residual
changed.

## Falsified hypothesis

*"The failure was introduced by the TS runtime-performance changes."* Falsified:
the failing call is
`stability.ts_algebraic_solve(0,y0,0,g_lin,@stability.ts_jac_y_fd,tol,J_supplied)`
with scalar inputs and a synthetic residual. It does not reach
`+stability/composite_dae.m`, `+stability/ts_step_composite.m`,
`+stability/ts_fd_column_groups.m`, `+ibr/eecon49_dual_mode_model.m` or
`+stability/sg_composite_device.m`, which are the only production files those
changes touch. The 79 other tests in the same targeted run pass, including
`test_ts_shared_kernel`'s remaining cases.

## Fix

Not applied. Two candidate repairs, both requiring approval because they change
a test's mathematical contract:

1. Keep the intent and restore the mechanism: choose a step contraction that
   still lands the residual inside `(tol, 100*tol)` after the current 60-iteration
   lease — e.g. a supplied Jacobian giving a slower contraction — so the test
   again exercises the "no silent gap acceptance" branch.
2. Assert the branch directly rather than through the lease, by driving
   `ts_algebraic_solve` to lease exhaustion with a residual constructed to sit in
   the band, independent of the lease count.

Option 1 preserves the original falsification target with the smallest change.
Neither should be applied by changing the expected exception or relaxing the
tolerance, which would discard the contract the test exists to protect.

## Verification

None yet — no repair applied. The evidence above is arithmetic plus the failing
assertion; re-running `runtests('tests/test_ts_shared_kernel.m')` reproduces it.

## Related files

- `tests/test_ts_shared_kernel.m:214-226`
- `+stability/ts_algebraic_solve.m:19-24`
- [fault-on solver lease](2026-08-05-eecon49-faulton-solver-lease.md)
