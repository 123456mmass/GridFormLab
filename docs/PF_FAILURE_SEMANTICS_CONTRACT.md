# Power Flow Failure Semantics Contract (Phase B)

## Scope

This document defines the failure semantics of the in-house Newton-Raphson
power-flow solver (`+pfsolver/powerflow_newton_raphson.m`) as hardened in
Phase B. It documents the runtime contract that the code and tests enforce;
it is not a claim about results from any run.

## Two failure classes (mandatory correction C)

### C1. Invalid input / schema failure -- throws a stable error

These are caught in `pf_prepare_case` BEFORE the numerical solve. The solver
throws a stable error identifier; it never returns a plausible result.

| Condition | Error identifier | Reported context |
|-----------|------------------|------------------|
| Empty / missing `case_data` | `case_data is required.` | -- |
| Missing `bus_data` / `line_data` | `case_data.* is required.` | -- |
| Wrong column count | `bus_data must have 8, 10, or 12 columns.` | -- |
| Duplicate bus IDs | `bus_data contains duplicate bus numbers.` | -- |
| REF count != 1 | `Exactly one slack bus is required for this solver.` | -- |
| Invalid bus type | `Bus types must be 1 (Slack), 2 (PV), or 3 (PQ).` | -- |
| Non-positive V spec | `Initial/specified voltage magnitudes must be positive.` | -- |
| Qmin > Qmax | `Qmin must be less than or equal to Qmax for every bus.` | -- |
| Zero-impedance line | `Each line must have non-zero impedance.` | -- |
| Line endpoint not in bus table | `Line data references bus numbers that do not exist in bus_data.` | -- |

### C2. Numerical solve failure -- returns a structured non-converged result

When the input is valid but the numerical solve fails, the solver returns a
result with `converged = false` plus the following fields:

| Field | Type | Meaning |
|-------|------|---------|
| `converged` | logical | `false` |
| `reason` | string | One of: `converged`, `singular_jacobian`, `nonfinite_system`, `nonfinite_newton_step`, `nonfinite_state`, `max_iterations` |
| `max_mismatch` | double | Final `max(abs(mismatch))` (finite when available) |
| `iterations` | integer | Iteration count at the point of return |
| `finite_status` | string | `all_finite`, `nonfinite_at_index_N`, or `rcond_<value>` for the singular case |

`solve_case.m` converts a non-converged result into a user-facing error that
includes `reason`, `finite_status`, `iterations`, and `max_mismatch`.

## Newton iteration order (mandatory correction D)

The Newton iteration, inside the `solve_model` local function, follows this
strict order so that finiteness is checked before conditioning:

1. Compute mismatch.
2. Check mismatch finite -> `nonfinite_system` if not.
3. Check convergence (breaks if `max_mismatch < tolerance`).
4. Compute analytic Jacobian.
5. Check Jacobian finite -> `nonfinite_system` if not.
6. Check conditioning (`rcond(J) < 1e-13`) -> `singular_jacobian` if not.
7. Solve Newton step `delta_x = J \ mismatch`.
8. Check Newton step finite -> `nonfinite_newton_step` if not.
9. Update state `x = x + delta_x`.
10. Check updated state finite -> `nonfinite_state` if not.
11. Enforce fixed REF/PV quantities (non-positive V reset to 0.1).

If `max_iter` is reached without convergence, `reason = 'max_iterations'`.

## Happy-path preservation (Phase 2 baseline)

The hardening is a **strict superset** of the pre-Phase-B solver. On the
converged path:

- `rcond(J) >> 1e-13`, so the singular-Jacobian branch is dead.
- All states are finite, so the nonfinite branches are dead.
- The convergence check (step 3) breaks before the Jacobian solve on the
  final iteration, so the new guards never execute on a converging case.
- Iteration count, mismatch values, and final state are bit-for-bit
  identical to the pre-hardening solver.

The `reason`, `max_mismatch`, and `finite_status` fields are **additive** --
no existing field consumer reads them. `solve_case.m:177` already guards
`max_mismatch` with `isfield`. CPF and the Q-limit loop read `r.converged`,
which is unchanged.

## Reference-independence (mandatory correction G)

The solver reads ONLY `bus_data(:,3:6)` (V, angle, Pgen, Qgen) as physical
input. Published comparison fields (`operating_point.printed_*`,
`reference.table95_eigenvalues`, `reference_solution`, `case_data.pgaz`)
are NEVER read on the solver path. Corrupting them must leave the PF result
unchanged to machine precision (`AbsTol 1e-12`). This is enforced by
`tests/test_pf_reference_independence.m`.

## External dependency guard (mandatory correction B)

The production PF scope (`+pfsolver`, `+cases`, `internal`, `solve_case.m`,
`run_powerflow.m`, `pf_init_paths.m`, `compat/`, `scripts/`) must not call
external nonlinear solvers. The guard in
`tests/test_no_external_solver_dependency.m` uses a two-pass scanner:

- **Pass A** (comments stripped, string literals KEPT): detects
  `feval('fsolve', ...)`, `feval("fsolve", ...)`, `str2func('fsolve')`,
  `str2func("fsolve")`, `eval('fsolve(...)')`.
- **Pass B** (comments AND strings stripped): detects `fsolve(...)`,
  `@fsolve`, package-qualified calls.

A comment or documentation string must not trip either pass. Synthetic
self-tests cover every form.
