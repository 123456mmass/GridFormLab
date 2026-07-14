# Repository instructions for agents

These rules apply to the entire repository.

## Numerical integrity

- Production PF, SSSA, TS/TDS, and IBR must be project-owned base-MATLAB code. Do not delegate the problem to MATPOWER, PSAT, PGAz, Simulink, Optimization Toolbox, reference programs, generated models, external executables, or loaded solutions. Audited primitives (`\`, `lu`, `qr`, `eig`) are allowed.
- External tools are validation-only, unreachable from production and `pf_init_paths`; their outputs may supply comparison metrics only and must never feed production states, parameters, corrections, or decisions.
- Start from cited equations or an in-repo derivation. Document variables/order, units/bases, frames/signs, residuals/Jacobians, initialization, stopping criteria, limits, and fail-closed behavior.
- Use source/case values exactly. Classify nontrivial choices as `SOURCE_DEFINED`, `CASE_DEFINED`, `PROJECT_DERIVED`, `NUMERICAL_METHOD`, or `ASSUMED_DIAGNOSTIC`; freeze choices before results. Diagnostic assumptions cannot support production/readiness claims.
- Never tune, fabricate, scale, smooth, round, filter, clip, or alter models, parameters, events, solver settings, plots, or gates merely to improve agreement. Compare identical mapped inputs/IDs numerically; diagnose or report mismatches honestly.
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

- Run proportional targeted tests and normally: `pf_init_paths; r=runtests('tests','IncludeSubfolders',true);`. Run applicable independent comparisons only with identical input contracts.
- Record branch, commit, environment, commands, pass/fail/incomplete counts, metrics, and limitations.
- After approved scope passes declared gates, commit and fast-forward push without re-asking. Ask before conflicts, remote divergence, failed/unexplained gates, scope expansion, unrelated files, published-history rewrite, rebase, amend, or force-push.
- Verify local HEAD equals the remote after delivery. Read `docs/project/AGENT_HANDOFF.md` for current status and technical debt.
