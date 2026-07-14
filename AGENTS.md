# Repository instructions for agents

These rules apply to the entire repository.

## 1. Production numerical code

- Production PF, SSSA, TS/TDS, and IBR must be project-owned MATLAB code using
  base MATLAB. Build the equations and algorithms here; do not delegate the
  complete problem to MATPOWER, PSAT, PGAz, Simulink, Optimization Toolbox, a
  reference program, generated model, external executable, or loaded solution.
- Audited primitives such as array operations, `\`, `lu`, `qr`, and `eig` are
  allowed inside visible, tested in-house algorithms. No silent fallback.
- External tools are validation-only, clearly labeled, unreachable from
  production and `pf_init_paths`, and may feed comparison metrics only. Their
  states, corrections, parameters, assignments, or acceptance decisions must
  never flow back into production.

## 2. Equations, data, and provenance

- Start numerical work from a cited equation or an in-repo derivation. Record
  states, algebraic variables, inputs and ordering; units and per-unit bases;
  frames, signs, and current/power direction; residuals, Jacobians/updates;
  initialization, stopping criteria, limits, and fail-closed behavior.
- Use source/case values exactly. Classify every nontrivial equation or value as
  `SOURCE_DEFINED`, `CASE_DEFINED`, `PROJECT_DERIVED`, `NUMERICAL_METHOD`, or
  `ASSUMED_DIAGNOSTIC`. Freeze non-source choices before viewing final results.
  Diagnostic assumptions must not support production/readiness claims.
- Reports must be traceable to implementation and sources. Label sourced data,
  assumptions/equations, computed project results, and external references;
  record the generating command/script for tables and figures.
- Never tune, fabricate, scale, smooth, round, filter, clip, or change physical
  parameters, models, faults/events, tolerances, FD steps, timesteps, iteration
  caps, scaling, plotting transforms, or acceptance gates merely to improve
  agreement. Similar plots are not equivalence. Compare identical mapped
  inputs and IDs with numeric metrics; diagnose or report mismatch honestly.

## 3. Planning and authority

- Read-only inspection, explanation, and status reporting need no approval.
- Before modifying code, tests, cases, docs/reports, artifacts, or Git history:
  read this file, `docs/project/TRACK_COORDINATION.md`, the current handoff and
  relevant plan; inspect branch/worktree/HEAD/main/status/parallel work; trace
  the real runtime path; inspect affected tests, schemas, sources, producers,
  and consumers; reproduce a relevant baseline when safe.
- Present a compact plan with objective/non-goals, evidence, allowlist and
  forbidden files, mathematical/data decisions, predeclared gates/tolerances,
  test and commit order, ownership, and genuine unresolved choices. Implement
  after user approval. Small details inside the approved scope need no repeated
  approval.
- Stop and ask only when evidence cannot resolve a material equation, input,
  schema, runtime, validation, ownership, merge-scope, or compatibility choice;
  when scope/base/ownership changes; or when user work is at risk. Do not ask
  for facts available from repository files or safe diagnostics.

## 4. Git, worktrees, and ownership

- Preserve unrelated user changes. Never use `git reset --hard`, `git clean`,
  mass rewrites, or destructive checkout. Checkpoint new/untracked files before
  history operations. Do not amend/rebase/force-push published work without
  explicit approval; never force-push `main`.
- In parallel work, declare the track and file allowlist. Only one owner may
  edit shared dispatch, case/schema, composite DAE, SSSA, TS kernel/driver,
  topology/event, launcher, or `pf_init_paths` files at a time. Other agents
  review read-only or submit isolated tests/docs. Reverify after `main` moves.
- Preserve numerical behavior during reorganization; wrappers belong in
  `compat/`, scripts in `scripts/`, with paths and tests updated.

## 5. Core numerical contracts

- PF production uses `pfsolver.powerflow_newton_raphson` unless a separately
  approved in-house method is explicitly routed. Cases follow `power_case/1.0`,
  12-column `bus_data`, 7-column `line_data`, and MATPOWER-v2-compatible `mpc`.
  Internal bus types are `1=REF, 2=PV, 3=PQ`; MATPOWER uses `3,2,1`.
- Respect effective PF bus semantics: PV specifies `P,|V|`; PQ specifies `P,Q`;
  REF specifies `|V|,angle`. PF-solved quantities are outputs. Account for
  local load, aggregation, bases, limits, and ID mapping. Never use numeric zero
  to mean unspecified or silently reinterpret `P_pu`, `Q_pu`, setpoints, or
  control modes.
- Operational EMF6 is the single equation set in `stability.emf6_dae` and
  `stability.synchronous_emf6_ssa`, shared with higher-order TS. Historical
  calibrated/primitive-flux variants remain in `legacy/`, off the path.
- Classical TS uses the canonical implicit-trapezoidal/event-grid contract.
  EMF6 TS has a fixed corrector (`corrector_iter=3`) unless a separately audited
  adaptive route is selected. Default plots show stored absolute rotor angle;
  stability decisions use COI-relative and pairwise metrics.
- Production/path-added directories contain no `fsolve`, `optimoptions`,
  `fmincon`, `fminsearch`, `lsqnonlin`, `optimset`, or equivalent solver
  delegation. Kundur Table E12.3 and external programs are references, never
  numerical acceptance targets.

## 6. Verification and delivery

- Run targeted falsification/regression tests proportional to risk. Numerical
  completion normally requires:

```matlab
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);
```

- Run applicable independent comparisons (`compare_case14_ts_three_way`,
  `compare_rts24_psat`) only with identical input contracts. Record branch,
  commit, environment, commands, pass/fail/incomplete counts, and limitations.
- If an approved plan includes delivery, the agent may commit and fast-forward
  push the approved branch after declared gates pass, without asking again,
  provided scope is clean, remote has not advanced, and no history is rewritten.
  Force-push, rebase/amend of published work, conflicts, failed/unexplained
  gates, scope expansion, unrelated files, or remote divergence require user
  approval. Verify and report local HEAD equals the remote after push.

Read `docs/project/AGENT_HANDOFF.md` for current status and technical debt.
