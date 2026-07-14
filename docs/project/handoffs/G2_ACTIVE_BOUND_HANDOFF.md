# Phase G-2 active-bound solver handoff

Date: 2026-07-15

Branch: `main`

Parent checkpoint: `b555027`

Delivery commit: this handoff's commit

## Outcome

The generic equilibrium active-bound path is implemented and exercised through
`stability.mixed_equilibrium_solve`, not only through direct helper calls.
Devices without `equilibrium_constraint_specs` retain the original one-shot
Newton path. Devices that declare constraints use a locked-regime outer loop;
classification occurs only between Newton solves, while residual, line-search,
and forward-FD calls share the same locked regime.

Each constrained differential row is supplied by the device callback for every
regime:

```text
interior -> raw differential equation
upper    -> device-defined upper equality
lower    -> device-defined lower equality
```

The solver does not hard-code `x-bound` arithmetic, so voltage-style equalities
are supported. Only the matching active differential row is replaced; all
rectangular network KCL rows remain present.

## Corrective work completed

- Reconstructed current `x`, `y`, and solved slack `u` for classification,
  residual, raw-derivative, and admissibility callbacks.
- Replaced every declared constraint row through `spec.residual_fn`, including
  the interior regime.
- Required and validated `classify_fn`, `residual_fn`, `raw_dot_fn`, and
  `admissible_fn` for every spec.
- Converted callback exceptions and non-finite callback values into the stable
  fail-closed contract instead of allowing implementation-specific exceptions
  to escape.
- Removed the silent missing-regime fallback.
- Corrected the diagnostic fixture's seven-rule classification and added a
  voltage-style equality constraint.
- Exercised the real `mixed_equilibrium_solve` branch with an IEEE14 SG/GFL
  case plus a zero-current diagnostic device.

The end-to-end fixture initially failed during struct concatenation. The
production IEEE14 builder returns a column device array (`5-by-1`), while the
test attempted horizontal concatenation. Field-value types were not the cause.
Appending along the existing device dimension (`[devices; diag_dev]`) is the
correct structural operation; no production device builder or IBR model was
changed.

## Stable failure IDs

```text
mixed_equilibrium_solve:activeBoundNewton
mixed_equilibrium_solve:activeBoundInconsistent
mixed_equilibrium_solve:activeBoundCycle
mixed_equilibrium_solve:activeBoundMaxOuter
mixed_equilibrium_solve:badActiveBoundSpec
mixed_equilibrium_solve:nonFiniteActiveBound
```

The outer-loop limit remains the predeclared numerical-method value of five.
No smoothing, pseudo-inverse, LM fallback, tolerance tuning, KCL-row removal,
or external solver was added.

## Verification

Environment: MATLAB R2025a, Windows, project paths initialized by
`pf_init_paths`.

Commands:

```matlab
restoredefaultpath;
cd('C:/Users/User/Desktop/Power-flow');
pf_init_paths;
runtests('tests/test_equilibrium_active_bound_contract.m');
runtests('tests/test_no_external_solver_dependency.m');
runtests('tests/test_ieee14_1sg_4ibr_phaseG.m');
runtests('tests','IncludeSubfolders',true);
```

Results:

```text
active-bound contract: 29/29 passed
external-solver guard: 12/12 passed
Phase-G regression:    15/15 passed
full regression:       747 total / 743 passed / 0 failed / 4 incomplete
```

The four incomplete results are the existing PGAz conversion assumptions
filtered because PGAz is unavailable to those tests. They are not failures of
the active-bound path.

The contract suite falsifies boundary zero/outward/inward classification,
infeasible projection, ordinary and voltage-style residuals, solved-slack
propagation, callback exception/non-finite handling, Newton failure,
inconsistency, cycle detection, the five-outer limit, locked-FD behavior, the
empty-callback identity path, and end-to-end KCL preservation.

## Readiness and next owner

This checkpoint completes the generic solver layer only. It does not implement
the REGFM_B1 Phase-G2 model states or equations. The next IBR checkpoint may
add `equilibrium_constraint_specs` to the sourced G2 model and then rerun these
contract gates plus its model-specific equation oracles.

```text
G2_ACTIVE_BOUND_SOLVER_READY      = READY
PHASE_G2_LIMITER_MODEL_READY      = NOT_IMPLEMENTED
IBR_PRODUCTION_INTEGRATION_READY  = NOT_READY
```

Local `docs/text/` and `docs/probes/ieee14_ibr_phaseG/` material remains
untracked and is not part of this delivery.
