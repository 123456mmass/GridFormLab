# Repository instructions for agents

These rules apply to the entire repository.

## Numerical integrity

- Production PF, SSSA, TS/TDS, and IBR must be project-owned base-MATLAB code. Do not delegate the problem to MATPOWER, PSAT, PGAz, Simulink, Optimization Toolbox, reference programs, generated models, external executables, or loaded solutions. Audited primitives (`\`, `lu`, `qr`, `eig`) are allowed.
- External tools are validation-only, unreachable from production and `pf_init_paths`; their outputs may supply comparison metrics only and must never feed production states, parameters, corrections, or decisions.
- Start from cited equations or an in-repo derivation. Document variables/order, units/bases, frames/signs, residuals/Jacobians, initialization, stopping criteria, limits, and fail-closed behavior.
- Use source/case values exactly. Classify nontrivial choices as `SOURCE_DEFINED`, `CASE_DEFINED`, `PROJECT_DERIVED`, `NUMERICAL_METHOD`, or `ASSUMED_DIAGNOSTIC`; freeze choices before results. Diagnostic assumptions cannot support production/readiness claims.
- Never tune, fabricate, scale, smooth, round, filter, clip, or alter models, parameters, events, solver settings, plots, or gates merely to improve agreement. Compare identical mapped inputs/IDs numerically; diagnose or report mismatches honestly.
- Tests are falsification instruments, not targets to optimize. Never change a test, expected value, tolerance, skip condition, or gate merely to obtain PASS; first diagnose the governing sourced equation, physical convention, runtime path, and implementation.
- Tests may—and must—be corrected when reproducible evidence proves that the test contradicts the cited source, approved derivation, physical/numerical contract, or intended runtime behavior. Document why the test is wrong, provide an independent oracle and before/after evidence, and obtain approval before changing any mathematical contract or acceptance criterion. Fix production code when the implementation is wrong; fix the test when the test is wrong. Never choose whichever side is easier to make pass.
- Reports must distinguish sourced inputs, assumptions/equations, project results, and external references, with citations and generating commands/scripts.

## Planning and ownership

- Read-only inspection and explanation need no approval. Before mutations, read this file, `docs/project/TRACK_COORDINATION.md`, the current handoff and relevant plan; inspect Git/worktrees, runtime paths, tests, schemas, sources, producers/consumers, ownership, and a relevant baseline.
- Present a compact plan covering scope/non-goals, evidence, allowlist, equation/data decisions, predeclared gates, tests, commits, and unresolved material choices; implement after approval.
- Re-plan only when evidence changes material scope, base, ownership, equations, inputs, schema, compatibility, runtime behavior, or validation criteria. Do not ask for facts available through safe inspection.
- Preserve unrelated work. Never use `git reset --hard`, `git clean`, mass rewrites, destructive checkout, or force-push `main`; checkpoint before history operations.
- One owner edits shared dispatch, schema, composite DAE, SSSA, TS kernel/driver, topology/event, launcher, or path files at a time. Reverify ownership and gates after `main` moves.

## Project contracts

- PF defaults to `pfsolver.powerflow_newton_raphson`; other production methods require an approved in-house route. Cases use `power_case/1.0`, 12-column `bus_data`, 7-column `line_data`; internal bus types are `1=REF,2=PV,3=PQ`.
- Respect effective bus semantics: PV specifies `P,|V|`, PQ specifies `P,Q`, REF specifies `|V|,angle`; solved quantities remain outputs. Preserve bases, limits, aggregation, ID mapping, explicit unspecified values, and schema meanings.
- Operational EMF6 is shared by `stability.emf6_dae`, `stability.synchronous_emf6_ssa`, and higher-order TS; legacy variants stay off-path.
- Classical TS keeps its canonical implicit-trapezoidal/event contract. EMF6 TS uses fixed `corrector_iter=3` unless an adaptive route is separately audited and tested. Stability uses COI-relative and pairwise metrics.
- Production paths contain no external nonlinear/optimization solver calls. Kundur E12.3 and external programs are references, never numerical acceptance targets.

## Verification and delivery

- During implementation, run the smallest proportional targeted tests that cover the changed producer, its consumers, the relevant failure path, and an independent oracle where applicable. Do not run the full repository regression after every edit, repair attempt, or agent turn.
- Run `pf_init_paths; r=runtests('tests','IncludeSubfolders',true);` once on the final delivery tree when the change affects production numerical equations, shared runtime/dispatch/schema, composite DAE, SSSA/TS kernels or drivers, topology/events, launcher/path integration, or when the approved plan or user explicitly requires it. Also run it when targeted evidence cannot bound the transitive risk. A full PASS is invalidated by subsequent runtime/source changes, but need not be repeated after a commit or documentation-only edit when the tested source tree is unchanged.
- Documentation-only, presentation-only, isolated fixture/test, and narrowly local changes may omit the full regression when targeted/static gates cover their scope and no production numerical/runtime contract changed. Record that the full suite was not run, why it was unnecessary, and the exact gates that were run. Any unexplained targeted failure escalates to broader testing; never use this policy to avoid investigating a failure.
- Run applicable independent comparisons only with identical input contracts.
- Every test-file change must identify the proven defect in the previous test and its independent source or oracle. A passing suite alone is not evidence that the equations are correct.
- Record branch, tested tree/commit, environment, commands, pass/fail/incomplete counts, metrics, limitations, and whether the full regression was required, reused from an unchanged tree, or intentionally omitted under the risk policy above.
- After approved scope passes declared gates, commit and fast-forward push without re-asking. Ask before conflicts, remote divergence, failed/unexplained gates, scope expansion, unrelated files, published-history rewrite, rebase, amend, or force-push.
- Verify local HEAD equals the remote after delivery. Read `docs/project/AGENT_HANDOFF.md` for current status and technical debt.
