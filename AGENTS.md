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
- Present a compact plan covering scope/non-goals, evidence, allowlist, equation/data decisions, predeclared gates, tests, commits, and unresolved material choices; implement after approval. An explicit user instruction such as `implement`, `finish`, `do it`, `auto`, `run unattended`, or `I will leave this running` is itself approval to inspect, formulate the compact plan, and execute it without a separate plan-confirmation pause, provided inspection reveals no unresolved material choice that would change the authorized scope or numerical contract.
- Re-plan only when evidence changes material scope, base, ownership, equations, inputs, schema, compatibility, runtime behavior, or validation criteria. Do not ask for facts available through safe inspection.
- Preserve unrelated work. Never use `git reset --hard`, `git clean`, mass rewrites, destructive checkout, or force-push `main`; checkpoint before history operations.
- One owner edits shared dispatch, schema, composite DAE, SSSA, TS kernel/driver, topology/event, launcher, or path files at a time. Reverify ownership and gates after `main` moves.

## Unattended and autonomous execution

- When the user requests automatic, unattended, end-to-end, or finish-to-completion work, treat that instruction as a persistent execution mandate for the authorized scope. Once a plan is approved or covered by that mandate, follow the plan continuously to its terminal outcome. Continue through inspection, implementation, proportional diagnosis, targeted verification, required final regression, documentation, commit, and fast-forward push without asking whether to continue at each stage.
- Do not pause for routine choices that can be resolved from repository evidence or by a conservative in-scope assumption. Inspect the code, sources, schemas, tests, Git state, ownership records, and prior defect records; choose the least expansive compatible option; record the assumption and evidence in the final handoff.
- Do not ask permission to read files, search the repository, run proportional tests, diagnose a failure, repair an in-scope defect, rerun a failed targeted gate after repair, create required in-scope documentation, commit an approved change, or fast-forward push after the declared gates pass.
- A first test failure is not a reason to stop or ask the user what to do. Preserve the failure evidence, identify the governing equation/runtime path, check matching defect records, fix the proven in-scope defect, and rerun the smallest relevant gate. Continue this diagnose-repair-verify loop while the work remains inside the approved plan and numerical contract.
- If one planned step is blocked, mark that step fail-closed, preserve its evidence, and continue every later independent, safe, in-scope step. Do not interrupt the unattended run for a mid-plan question. At the end, report completed steps and the exact residual blocker. Ask the user only when no meaningful planned work remains and a new authority or material decision is indispensable.
- Never ask a generic `should I continue?`, `should I fix it?`, or `do you want me to run the tests?` question while an approved plan still contains meaningful executable work.
- New authority is required only for: conflicting concurrent ownership; remote divergence or merge conflict; destructive or published-history operation; access/credential approval; an authoritative source gap that would otherwise require inventing an equation or parameter; a change to bases, signs, state order, physical equations, schema meaning, compatibility contract, or acceptance gate; an unapproved external side effect; or files/people/systems outside the authorized scope. During an unattended run, defer any such blocked step, continue the rest of the plan, and consolidate the unresolved items in the final report instead of repeatedly interrupting the user.
- Missing source evidence never authorizes fabrication. Complete and verify all work that does not depend on the missing source, mark the blocked production claim fail-closed, and report the exact missing decision after exhausting the remaining plan.
- Keep the user informed with concise progress updates during long work, but progress updates are not approval requests. For long-running tests or monitors, continue observing them and report material changes; do not terminate merely because one wait interval produced no output.
- An unattended mandate does not weaken numerical-integrity, ownership, safety, or fail-closed rules. It removes unnecessary conversational pauses; it does not authorize silent fallback, threshold tuning, test manipulation, fabricated physics, destructive Git operations, or expansion beyond the user's task.

## Project contracts

- PF defaults to `pfsolver.powerflow_newton_raphson`; other production methods require an approved in-house route. Cases use `power_case/1.0`, 12-column `bus_data`, 7-column `line_data`; internal bus types are `1=REF,2=PV,3=PQ`.
- Respect effective bus semantics: PV specifies `P,|V|`, PQ specifies `P,Q`, REF specifies `|V|,angle`; solved quantities remain outputs. Preserve bases, limits, aggregation, ID mapping, explicit unspecified values, and schema meanings.
- Operational EMF6 is shared by `stability.emf6_dae`, `stability.synchronous_emf6_ssa`, and higher-order TS; legacy variants stay off-path.
- Classical TS keeps its canonical implicit-trapezoidal/event contract. EMF6 TS uses fixed `corrector_iter=3` unless an adaptive route is separately audited and tested. Stability uses COI-relative and pairwise metrics.
- Production paths contain no external nonlinear/optimization solver calls. Kundur E12.3 and external programs are references, never numerical acceptance targets.

## Verification and delivery

- During implementation, run the smallest proportional targeted tests that cover the changed producer, its consumers, the relevant failure path, and an independent oracle where applicable. Do not run the full repository regression after every edit, repair attempt, or agent turn.
- The full repository regression (`pf_init_paths; r=runtests('tests','IncludeSubfolders',true);`) is OPTIONAL and is run by the maintainer at their own discretion; it is NOT a mandatory pre-commit or pre-push gate for an agent. Targeted tests that cover the changed producer, its consumers, and the relevant failure path are sufficient evidence for delivery. An agent need not run the full suite before committing or pushing unless the user explicitly asks for it. When the full suite is not run, record which targeted gates were run instead.
- Documentation-only, presentation-only, isolated fixture/test, and narrowly local changes may omit the full regression when targeted/static gates cover their scope and no production numerical/runtime contract changed. Record that the full suite was not run, why it was unnecessary, and the exact gates that were run. Any unexplained targeted failure escalates to broader testing; never use this policy to avoid investigating a failure.
- Run applicable independent comparisons only with identical input contracts.
- Every test-file change must identify the proven defect in the previous test and its independent source or oracle. A passing suite alone is not evidence that the equations are correct.
- Record branch, tested tree/commit, environment, commands, pass/fail/incomplete counts, metrics, limitations, and whether the full regression was required, reused from an unchanged tree, or intentionally omitted under the risk policy above.
- After approved scope passes declared gates, commit and fast-forward push without re-asking. Ask before conflicts, remote divergence, failed/unexplained gates, scope expansion, unrelated files, published-history rewrite, rebase, amend, or force-push.
- Verify local HEAD equals the remote after delivery. Read `docs/project/AGENT_HANDOFF.md` for current status and technical debt.

## Defect memory and context budget

- Record every reproducible material defect or diagnostic trap in `docs/project/defects/YYYY-MM-DD-short-slug.md` before delivery. Include status, symptom, reproduction, affected branch/commit/environment, root cause with evidence, falsified hypotheses, fix, verification, limitations, and related files/commits. Mark unresolved records `OPEN`; update the same record to `RESOLVED` without erasing its history.
- Add one compact row to `docs/project/defects/INDEX.md`. Before debugging, search the index and defect directory with `rg` using the failure ID, symptom, component, or model name; read only matching records. Never load every defect record merely because the directory exists.
- Keep the current handoff and active plan concise and free of duplicated history. Move superseded detail to timestamped files under `docs/project/handoffs/` or an archive, and link it instead of copying it into every current document.
- Defect records must distinguish observation from inference, avoid unsupported root-cause claims, contain no secrets or large raw dumps, and point to reproducible commands or stored artifacts rather than embedding bulky output.
