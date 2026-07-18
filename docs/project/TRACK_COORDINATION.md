# Parallel Worktree and Track Coordination

This document is the coordination contract for agents working on PF, SSSA,
TS, and IBR in parallel. Read it together with the repository-root
`AGENTS.md` and the track-specific plan before changing code.

The purpose is to let tracks progress independently without allowing two
agents to modify the same numerical contract or shared integration layer at
the same time.

## 1. Source of truth

The integration branch is `main`. A result from another branch is valid only
for the tested source tree/commit on which it was produced. If `main` advances,
any claim that a feature branch is aligned or merge-ready becomes stale until
the merge base and changed scope are rechecked. Rerun proportional targeted
gates after integration; rerun the full regression only when the risk policy
in the repository-root `AGENTS.md` requires it. Do not repeat an unchanged-tree
full PASS merely because a commit was created or an agent turn ended.

Agents must never copy numerical results between worktrees and present them as
a fresh run. Each final report must record:

- branch name;
- tested source commit;
- current `main` commit;
- merge-base;
- exact test commands and fresh counts;
- overall working-tree status;
- files changed relative to `main`.

Do not hard-code commit hashes in production code, tests, or permanent gate
logic. Hashes may appear in timestamped validation artifacts as provenance.

## 2. Track definitions

### Track A — SG numerical core and adaptive TS

Purpose: maintain the production SG baseline and implement adaptive-step TS
without changing the IBR model.

Current responsibilities:

- PF, SSSA, and fixed-step regression integrity;
- shared algebraic Newton and one-step TS kernel;
- adaptive-step driver, LTE estimation, accept/reject logic, and timestep
  controller;
- exact landing at fault and clear events;
- fixed/adaptive common-grid comparison without extrapolation;
- Case14 and RTS-24 PSAT validation.

Potentially owned shared files include:

- `+stability/ts_step_kernel.m`;
- `+stability/ts_algebraic_solve.m`;
- `+stability/ts_jac_y_fd.m`;
- `+stability/ts_topology*.m`;
- adaptive TS driver files;
- shared TS dispatch only when explicitly assigned.

Track A must not edit `+ibr/**` or change the VSG mathematical model. If it
needs an IBR interface, record the request in
`docs/project/plans/ibr_interface_requests.md`.

### Track B — IBR/VSG model and diagnostic hardening

Purpose: develop the sourced VSG/IBR model and its diagnostic contracts while
remaining isolated from the production PF/SSSA/TS integration layer.

Current responsibilities:

- `+ibr/**` model, schema, provenance, and diagnostic helpers;
- IBR-owned cases;
- equilibrium, current/power identity, reference-frame, FD, mapping, and
  provenance tests;
- voltage-aligned current-limit contract;
- bus-type-aware PF metadata contract;
- IBR diagnostic documentation and pre-integration reports.

Track B owns only:

- `+ibr/**`;
- explicitly IBR-named files under `+cases/`;
- `tests/test_ibr_*.m`;
- `docs/ibr/**`;
- `scripts/ibr/**`;
- `docs/project/plans/ibr_interface_requests.md`.

Track B must not edit production PF, SSSA, TS, shared numerical kernels, or
dispatchers. Until integration begins, it must report:

```text
IBR_DIAGNOSTIC_PROTOTYPE_READY = PASS or FAIL
IBR_PRODUCTION_INTEGRATION_READY = NOT_STARTED
```

> **2026-07-15 integration addendum:** integration has begun and the historical
> pre-integration ownership split above is no longer a current readiness flag.
> The approved corrective work is consolidated on `main` under one
> implementation owner, with independent read-only review. Current status is
> `PHASE_G1_LIMITER_READY = IMPLEMENTED_STRUCTURAL_ONLY` and
> `IBR_PRODUCTION_INTEGRATION_READY = NOT_READY`. Shared-core edits require the
> all-KCL/SG-reference/TS-SSSA gates recorded in `AGENT_HANDOFF.md`; parallel
> writers must still avoid overlapping files.

### Track C — equations, sources, and validation design

Purpose: prepare evidence for the production IBR implementation without
changing runtime numerical code.

Current responsibilities:

- locate and cite primary sources for VSG, droop, virtual impedance, current
  limiting, and anti-windup equations;
- state variables, algebraic variables, inputs, sign conventions, current and
  power direction, and per-unit bases;
- distinguish sourced parameters, forward-designed parameters, and
  `ASSUMED_DIAGNOSTIC` values;
- design mixed SG/IBR tests and independent validation cases;
- identify unresolved mathematical or case-schema decisions.

Track C is documentation and research only unless the integration owner grants
a specific implementation allowlist. It must not change runtime code merely to
make a reference comparison closer.

## 3. Files that require a single owner

Only one active track may modify any of the following at a time:

- `solve_case.m`;
- `run_pf.m`, `run_ssa.m`, and `run_ts.m`;

> **2026-07-19 Analysis Wizard note:** the Analysis Wizard refactor (Phases
> 1-6) refactored `solve_case.m` into a thin wrapper delegating to `+wizard/*`.
> That work is complete; `solve_case.m` is again available for single-owner
> reassignment. The wizard's pure dispatcher is `wizard.dispatch_analysis`
> (single shared dispatcher for both the UI and the programmatic path). See
> `docs/project/IEEE14_ANALYSIS_WIZARD.md`.
- `pf_init_paths.m`;
- `+stability/ts_simulate.m`;
- `+stability/multicase_sssa.m`;
- `+stability/multimachine_ssa.m`;
- shared DAE composition and state-order contracts;
- shared TS kernel, algebraic solver, topology, and event-grid helpers;
- common case schema or PF bus-type semantics.

An agent needing one of these files must first record an interface request and
wait for ownership to be assigned. Two branches must not independently create
different versions of the same shared interface.

## 4. Work that may proceed in parallel

The following work may run concurrently:

- Track A adaptive-driver tests while Track B changes only `+ibr/**` and its
  diagnostic files;
- Track B model-contract tests while Track C researches and cites equations;
- report and test design that does not modify shared runtime paths;
- read-only review of another track;
- independent validation scripts that do not enter `pf_init_paths` or become
  production dependencies.

The following work must not run concurrently without an explicit integration
owner:

- two changes to the shared one-step TS kernel;
- two changes to SSSA Schur/composite-DAE logic;
- IBR integration and adaptive-driver dispatch changes in the same shared
  dispatcher;
- independent changes to state ordering, algebraic ordering, case schema, or
  per-unit conventions;
- rebasing a branch while another agent is still committing to that branch.

## 5. Synchronization points

### Sync point 1 — diagnostic closure

Required before merging the diagnostic IBR branch:

- Track B targeted tests pass;
- the risk-proportional verification policy in `AGENTS.md` is satisfied on the
  final merge tree; a full regression is required if the merge changes shared
  production numerical/runtime behavior;
- two-dot and three-dot diffs are identical;
- diff contains Track-B-owned files only;
- protected production core is unchanged;
- production integration remains `NOT_STARTED`.

### Sync point 2 — production IBR contract approval

Required before changing production dispatch or composite DAE code:

- sourced equations are documented;
- state, algebraic, input, sign, direction, and per-unit contracts are frozen;
- bus-type-aware initialization semantics are approved;
- parameter provenance is explicit;
- unresolved choices are presented to the user rather than guessed;
- fixed-step TS is selected as the first canonical integration path.

### Sync point 3 — mixed SG/IBR integration

At this point, assign one integration owner. That owner alone may change shared
dispatch, composite DAE, SSSA, and TS integration files. Other tracks submit
tests, documentation, or interface requests.

Integration order:

```text
PF initialization
-> no-fault equilibrium
-> mixed SG/IBR SSSA
-> fixed-step TS without current limiting
-> current limiter and anti-windup
-> multi-IBR and penetration studies
-> adaptive-step TS
-> independent validation and report
```

## 6. Local worktrees versus remote push/pull

Agents on this machine share the same Git object database but have separate
working directories. They do not need to push and pull merely to see commits.
Use `git fetch` only when synchronizing with a remote repository.

For local parallel work:

1. Each track uses its own branch and worktree.
2. The integration owner updates `main`.
3. A track waits until the current `main` task is fully committed.
4. The track rebases onto `main` at a synchronization point.
5. The track reruns targeted tests and any additional risk-proportional gates
   required by `AGENTS.md`; a full regression is not automatic for every
   rebase or turn.
6. The track is merged only if its scope and regression gates pass.

For work shared through a remote:

```bash
git fetch origin
git rebase origin/main
git push --force-with-lease origin <feature-branch>
```

Use `--force-with-lease` only after a deliberate feature-branch rebase and only
when no other agent is writing that branch. Never force-push `main`. If branch
ownership is unclear, ask before rebasing or pushing.

Do not run `git pull` blindly inside every worktree. It combines fetching and
integration, may create an unintended merge, and does not replace explicit
merge-base and scope checks.

## 7. Start-of-turn checklist for every agent

Before editing:

```bash
git branch --show-current
git rev-parse HEAD
git rev-parse main
git merge-base main HEAD
git status --short
git diff --check
```

Then:

1. Read `AGENTS.md` completely.
2. Read this file completely.
3. Read the track-specific plan and current handoff.
4. State the track and exact file allowlist.
5. Identify shared files and refuse to edit them without ownership.
6. Preserve all unrelated modified and untracked files.
7. Record tolerances and validation criteria before viewing final metrics.

## 8. End-of-turn checklist for every agent

Before claiming completion:

```bash
git status --short
git diff --check
git diff --name-status main..HEAD
git diff --name-status main...HEAD
git merge-base --is-ancestor main HEAD
```

Run the track-targeted tests. Run the following full regression once on the
final tree only when required by the risk policy in `AGENTS.md`:

```matlab
restoredefaultpath;
cd('/home/birds/Documents/Power-flow');
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);
```

Do not rerun it after a commit when the tested source tree is unchanged. For a
permitted omission, report the reason and exact targeted/static gates instead.

The final report must distinguish:

- verified source commit;
- artifact commit;
- required gates;
- report-only diagnostics;
- known limitations;
- overall repository status, including preserved unrelated changes.

If `main` advances after verification, mark merge readiness stale, inspect the
new diff, and rerun the affected targeted gates. Reuse a previous full PASS
only when its tested source tree is unchanged; otherwise rerun full only if the
combined final tree meets the `AGENTS.md` full-regression criteria.

## 9. Merge order

Unless the user explicitly changes priority, use this order:

1. finish and commit the active `main` task;
2. checkpoint repository policy/documentation changes separately;
3. rebase and verify Track B against the new `main`;
4. merge Track B diagnostic work;
5. run post-merge targeted gates and one full regression if the merged final
   tree changes shared production numerical/runtime behavior;
6. freeze the production IBR interface contract;
7. begin mixed SG/IBR integration under one integration owner;
8. merge adaptive TS and IBR integration only after their shared-interface
   compatibility tests pass.

## 10. Stop conditions

Stop and ask the user when:

- a required change falls outside the track allowlist;
- another agent owns the same shared file;
- an equation or parameter lacks a reliable source;
- a change alters state order, sign convention, per-unit base, case schema, or
  validation criteria;
- agreement improves only after changing a parameter or numerical setting;
- Git history or working-tree ownership is ambiguous;
- a dependency or external validation tool is unavailable and required.

Never resolve these conditions by silently widening scope, tuning results, or
discarding another track's work.
