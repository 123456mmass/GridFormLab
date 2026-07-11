# Repository instructions for agents

These instructions apply to the entire repository.

## Non-negotiable rules

1. Production PF/SSSA/TS must use in-house MATLAB code. PSAT, PGAz, MATPOWER,
   Optimization Toolbox solvers, and book/reference programs are validation
   references only. Build the physical equations and implement their numerical
   solution methods in project code using base MATLAB; do not hand the core
   problem to a ready-made toolbox function, external solver, simulation
   environment, or reference program. External tools must never be reachable
   from a production execution path.
2. Do not use `git reset --hard`, `git clean`, or mass rewrites. This project
   previously lost uncommitted launchers and solver files through a reset.
   Checkpoint new files before any history operation.
3. Preserve numerical behavior when reorganizing files. Move wrappers to
   `compat/` and scripts to `scripts/`; update `pf_init_paths` and tests.
4. Do not claim equivalence from visually similar plots. Compare mapped bus and
   generator IDs, identical network/fault/load/machine inputs, and numeric error
   metrics.
5. Never fabricate, tune, scale, round, filter, or otherwise massage numerical
   values to make results match a book, paper, PSAT/PGAz, prior artifact, or
   expected plot. References are used to diagnose and validate only. If results
   differ, find the modeling, data, convention, mapping, or numerical bug; if no
   bug is proven, report the mismatch honestly.
6. Do not change solver tolerances, finite-difference steps, iteration caps,
   parameters, load models, fault impedances, event times, scaling factors, or
   plotting transforms after seeing results in order to force a pass. Such
   changes require a prior written rationale, a deterministic regression, and
   before/after metrics.
7. Always use the values specified by the case, problem statement, source data,
   or documented provenance. This is not "tuning"; it is the input contract. For
   example, if a case states 60 Hz, set the case frequency to 60 Hz rather than
   keeping an old 50 Hz default. If the source states a line impedance, machine
   base, load model, fault impedance, event time, or controller parameter, use
   that value and cite where it came from. Do not replace source-provided values
   with defaults just because an older script used them.
8. If a requested change is ambiguous, changes the mathematical model, changes
   validation criteria, or could be interpreted as fitting results to a
   reference, stop and ask the user before implementing it.

## Mandatory planning before implementation

Every task that may modify code, tests, cases, documentation, reports, Git
history, validation artifacts, or numerical behavior must begin with a planning
phase. If the agent environment provides a Plan Mode, enter it before making
changes. If Plan Mode is unavailable, perform the same process explicitly in
the conversation and do not start implementation until the user approves the
plan.

Before proposing the plan, the agent must investigate enough of the repository
to avoid planning from assumptions:

1. Read `AGENTS.md`, `docs/project/TRACK_COORDINATION.md`, the current handoff,
   and the track-specific plan completely.
2. Inspect the actual Git branch, worktree, HEAD, current `main`, merge-base,
   working-tree changes, and active parallel workstreams.
3. Trace the relevant runtime call graph from launcher to solver/model/output;
   the existence of a file is not proof that the runtime uses it.
4. Read the affected tests, numerical contracts, case schema, source material,
   and equation provenance. Search for every producer and consumer of any field
   or interface whose meaning may change.
5. Reproduce the current behavior or failure with read-only commands when it is
   safe and relevant. Record baseline commands and metrics before editing.
6. Identify file ownership, an explicit allowlist, protected/shared files,
   dependencies, risks, required gates, and the proposed commit/artifact split.

The agent must then present a concrete plan containing:

- objective and non-goals;
- evidence and current call graph;
- files expected to change and files explicitly forbidden;
- mathematical/data-contract decisions and their cited sources;
- tests to write or update, including deterministic failure reproductions;
- tolerances and acceptance criteria declared before final results are viewed;
- execution order, synchronization points, validation commands, and rollback
  or fail-closed behavior;
- unresolved questions and decisions requiring user authority.

Ask the user before implementation whenever information is missing or a choice
could materially change equations, inputs, schema, runtime behavior, validation
criteria, compatibility, ownership, or merge scope. Do not guess. Questions
must state the discovered evidence, the exact decision required, and the
consequence of each reasonable option.

Do not ask the user for facts that can be established safely from repository
files, local source material, Git state, tests, or read-only diagnostics. First
investigate those sources, then ask only about genuine policy, intent, authority,
or unresolved scientific decisions.

After the user approves the plan, implement only the approved scope. If new
evidence invalidates the plan, a required file falls outside the allowlist, a
parallel track changes the shared base, or a new mathematical decision appears,
stop implementation, update the plan, and obtain approval again. Previous
approval does not authorize silent scope expansion.

Purely read-only inspection, status reporting, or answering a conceptual
question may proceed without a separate approval cycle, but it must not mutate
files, Git history, artifacts, or external state.

## Equation-first in-house implementation

Production numerical work must start from the sourced mathematical model, not
from a convenient solver API. Before implementing or approving a numerical
engine, document all of the following:

- governing differential, algebraic, network, constraint, or optimization
  equations;
- unknowns, states, algebraic variables, inputs, parameters, and their order;
- units, per-unit bases, reference frames, signs, and current/power direction;
- residuals and constraints actually solved by the code;
- Jacobian, derivative, linearization, or approximation used;
- the iteration or update equation derived from the model;
- initialization, stopping criteria, iteration limits, and failure semantics;
- convergence, consistency, and falsification tests.

Then implement the solution procedure in project-owned MATLAB code. It is not
enough to wrap, rename, or indirectly dispatch to a function that already
solves the complete problem. This prohibition applies to direct calls,
function handles, string dispatch, generated models, fallback paths, and
optional branches that become reachable in production.

Examples of forbidden production delegation include, but are not limited to:

- nonlinear/root/optimization/assignment functions that accept the project
  residual or cost matrix and return the final solution;
- MATPOWER, PSAT, PGAz, Simulink, or another program used as the PF, SSSA, TS,
  controller, integration, or assignment engine;
- loading an externally solved state, trajectory, eigenvalue, matching, or
  parameter set and treating it as the project solver's result;
- silently falling back to a toolbox or external executable when the in-house
  method fails.

Base MATLAB language and elementary numerical primitives may be used as
building blocks, including array operations and audited linear-algebra
primitives such as matrix backslash, `lu`, `qr`, and `eig`. These primitives
must support an in-house algorithm whose residuals, updates, and failure
contracts remain visible and tested in this repository; they must not replace
the project-level method itself.

External programs and toolbox implementations may run only in explicitly
labeled validation or diagnostic paths that are unreachable from production.
Their outputs may be compared with independently computed project outputs, but
must not flow backward into production as initial states, corrections,
parameters, mode assignments, convergence decisions, fallback results, or
acceptance values. The permitted direction is:

```text
sourced equations -> in-house solver -> project result
                                          |
independent external run -> comparison metrics only
```

If a standard published algorithm is needed, cite or derive it, implement it
with base MATLAB/project code, and test it independently. Using a standard
algorithm name does not authorize calling a ready-made implementation.

## Scientific and numerical integrity

- Derive equations from a cited source before implementing them. Prefer the
  local textbook/problem statement, project documentation, standards, or primary
  papers. If the source is not already in the repository or local materials,
  look it up before coding and record the source in the relevant comment, test,
  or documentation.
- Every equation used in code, tests, documentation, or reports must have a
  source of truth. Acceptable sources include the case/problem statement,
  textbook pages, standards, primary papers, project design documents, or a
  derivation written in the repository. If no source is known, do not present
  the equation as authoritative; mark it as an assumption and ask before using
  it in production or validation claims.
- Before writing or revising any LaTeX/report document, first inspect the
  relevant source material and implementation. Report content must be traceable:
  equations need citations or in-repo derivations, case data needs provenance,
  tables/figures need the command or script that generated them, and comparison
  values need a cited book/table/tool/artifact source. Do not write report
  prose, equations, or tables from memory.
- LaTeX reports must distinguish four kinds of information: sourced input data,
  equations/model assumptions, computed results from project commands, and
  external reference values. Do not mix them in a table or paragraph without
  labeling which is which.
- Separate source-correct input changes, reasonable engineering choices, and
  forbidden fitting:
  - **Required source-correct changes:** If the case, problem statement,
    textbook page, data file, standard, or documented provenance gives a value,
    use that value. This includes frequency (50/60 Hz), base MVA/kV, generator
    MVA base, inertia, damping, reactances, resistances, transformer taps,
    line charging, shunts, load model, controller constants, fault impedance,
    fault/clear times, bus IDs, generator-to-bus mapping, and per-unit
    conversion rules. Correcting an old/default value to the sourced value is
    required and is not fitting. Example: if the case is specified as 60 Hz,
    changing an old 50 Hz default to 60 Hz is the correct fix.
  - **Reasonable engineering choices:** If the source does not specify a value
    needed to run a diagnostic or prototype, choose a conservative value before
    looking at pass/fail metrics, label it `ASSUMED_DIAGNOSTIC`, document why it
    is needed, and keep it out of production acceptance claims. Examples:
    diagnostic IBR prototype gains, plotting limits, report-only perturbation
    sizes, or a non-acceptance scenario used only to exercise code paths.
  - **Numerical-method choices:** Solver tolerances, finite-difference steps,
    timestep sizes, iteration caps, scaling factors, and convergence criteria
    must be declared from numerical analysis, machine precision, existing
    project contracts, or an a-priori convergence study. They may be changed
    only to fix a proven numerical bug or to implement a documented method, and
    the change must include before/after evidence.
  - **Forbidden fitting:** Do not adjust any physical parameter, model switch,
    source data, load model, damping, reactance, controller gain, fault
    impedance, event time, tolerance, FD step, timestep, iteration cap,
    scaling factor, or post-processing transform merely because it makes an
    error metric, eigenvalue, damping ratio, trajectory, table, or plot closer
    to a reference. Do not perform grid-search/manual calibration against a
    book table, PSAT/PGAz trace, saved artifact, expected graph, or prior run
    unless the explicit task is a diagnostic calibration script kept out of
    production and labeled as such.
  - **Ambiguity rule:** If a change both (a) improves agreement with a
    reference and (b) changes model/data/solver behavior, the agent must prove
    the previous value was wrong from source/provenance or ask the user before
    implementing. Agreement improvement alone is not evidence.
  - **Reporting rule:** When values differ from a reference after sourced
    inputs and equations are correct, report the mismatch and likely causes.
    Do not hide it by relaxing tolerances, changing labels, omitting failing
    metrics, smoothing data, clipping plots, or moving the case out of tests.
- Every new PF/SSSA/TS/IBR equation must state its state variables, algebraic
  variables, inputs, sign convention, per-unit base, and current/power direction.
  Do not implement equations from memory when the convention matters.
- When a reference comparison fails, the workflow is: reproduce, map inputs and
  IDs, check units/signs/reference frames, inspect residuals, isolate the root
  cause, then fix the bug. Do not "calibrate" the implementation to hide the
  discrepancy.
- Diagnostic scripts may use external reference tools only when clearly labeled
  as validation. Production code and the MATLAB path initialized by
  `pf_init_paths` must remain free of external solver dependencies.

## Numerical contracts

- PF: `pfsolver.powerflow_newton_raphson`, no external nonlinear solver.
- Network cases: `power_case/1.0`, 12-column `bus_data`, 7-column `line_data`,
  and MATPOWER-v2-compatible `mpc` matrices.
- Internal bus types: `1=REF`, `2=PV`, `3=PQ`; MATPOWER: `3=REF`, `2=PV`,
  `1=PQ`.
- Interpret generator quantities according to the effective PF bus type:
  - PV: scheduled inputs are active power `P` and voltage magnitude `|V|`;
    reactive power `Q` is a PF-solved output unless a reactive-power limit
    becomes active.
  - PQ: specified inputs are active and reactive power `P,Q`.
  - REF: voltage magnitude and angle are specified; active and reactive power
    `P,Q` are PF-solved outputs.
- Never hard-code a PF-solved `P` or `Q` result back into case input metadata
  merely to satisfy a consistency test or reference comparison.
- Validate case or device metadata only against quantities that are true inputs
  for the effective bus type. Account explicitly for local load, generator
  aggregation, sign convention, per-unit base, and generator-to-bus mapping;
  do not compare a generator schedule directly with net bus injection.
- Do not use numeric zero to mean "unspecified" because zero may be a valid
  physical setpoint. Use an explicit empty value, schema field, validity flag,
  or control-mode indicator.
- If reactive-power limits cause PV-to-PQ switching, apply input/output
  validation using the effective bus type after limit enforcement.
- Changing the meaning of `P_pu`, `Q_pu`, voltage setpoints, or device control
  modes is a case-schema decision. Audit all producers and consumers and ask
  the user before changing or silently reinterpreting that contract.
- Classical TS default: adaptive implicit trapezoidal corrector, exact fault
  event grid, update and trapezoidal-residual convergence checks.
- Sixth-order model: the operational EMF6 model
  (`stability.emf6_dae` / `stability.synchronous_emf6_ssa`) is the SINGLE
  equation set shared by SSSA and higher-order TS (`stability.ts_simulate_emf6`).
  It uses the in-house Newton solver and published parameters only -- no
  calibration knobs. The historical primitive-flux (psi-state) and calibrated
  GENTPJ (Kundur Table E12.3) realizations are in `legacy/`, off the MATLAB
  path, and are not in the catalog, launcher, or acceptance tests.
- Higher-order EMF6 TS uses a FIXED corrector (default `corrector_iter=3`).
  Do NOT describe it as adaptive until a residual-based convergence/
  rejection path is audited and tested. Adaptive corrector is validated only
  for the classical path.
- TS plot angle is `delta_i(t)-delta_i(0)` (PSAT `delta_Syn` style). Stability
  decisions use COI-relative and pairwise metrics, not the plotted common drift.
- Production packages AND every directory `pf_init_paths` adds to the path
  (`internal`, `compat`, `scripts`, `docs`) contain no
  `fsolve`/`optimoptions`/`fmincon`/`fminsearch`/`lsqnonlin`/`optimset`
  (guarded by `test_no_external_solver_dependency`, which scans the real
  MATLAB path, not a hard-coded list). `fsolve` survives only in `legacy/`
  (off the path) and `docs/probes/` (off the path) as reference/diagnostic
  code; it is never a production dependency.
- Kundur Table E12.3 is reference/case-study data only, never a numerical
  acceptance target. Never tune parameters, scales, time constants, saturation,
  load model, finite-difference step or solver tolerance to match it.

## Required checks

Before working in parallel branches or worktrees, read
`docs/project/TRACK_COORDINATION.md`, declare the active track and file
allowlist, and follow its synchronization and merge-readiness rules.

```matlab
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);
```

For numerical cross-validation:

```matlab
compare_case14_ts_three_way;
compare_rts24_psat;
```

Read `docs/project/AGENT_HANDOFF.md` for current pass/fail status and known
technical debt before changing Kundur or sixth-order models.
