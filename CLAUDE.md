@AGENTS.md

# Claude Code bootstrap

`AGENTS.md` above is the repository policy and must be followed in full. Do
not rely on conversation memory or a previous session's summary as a substitute
for reading the imported instructions.

Before any task that may modify files, tests, cases, documentation, reports,
artifacts, Git history, external state, or numerical behavior:

1. Normally call `EnterPlanMode` before performing any mutation. If the user
   has explicitly requested `implement`, `finish`, `do it`, `auto`,
   `run unattended`, `follow the plan`, or an equivalent
   finish-to-completion mandate, do not enter Plan Mode merely to obtain another
   confirmation. Perform the same read-only inspection and reviewed planning
   workflow in the active execution mode, publish the compact plan as a progress
   update, and continue automatically. If an approved plan already exists,
   execute it directly after refreshing repository evidence and ownership.
2. Read `docs/project/TRACK_COORDINATION.md`, the current handoff, and the
   relevant track plan from disk.
3. Use the global read-only `Explore` agent defined at
   `/home/birds/.claude/agents/Explore.md` to fan out across relevant files,
   directories, symbols, tests, producers, consumers, history, and defect
   records. Ask for conclusions, paths, symbols, and line numbers rather than
   large file dumps. The primary agent must verify material findings against
   the repository before relying on them.
4. Use the global read-only `Plan` agent defined at
   `/home/birds/.claude/agents/Plan.md` to design the implementation plan from
   the inspected evidence. Give it the goal, constraints, current code path,
   ownership, proposed scope/non-goals, mathematical or schema contracts,
   compatibility requirements, gates, and unresolved decisions. The primary
   agent remains responsible for turning its proposal into the actual plan.
5. Before `ExitPlanMode`, always ask the global read-only `custom-advisor`
   defined at `/home/birds/.claude/agents/custom-advisor.md` to independently
   review the draft plan. This is mandatory for every plan-mode task, including
   apparently simple changes. Ask it to challenge unsupported assumptions,
   missed consumers, ownership conflicts, counterexamples, failure semantics,
   validation gaps, and whether a smaller safer alternative exists.
6. Reconcile the `Explore`, `Plan`, and `custom-advisor` outputs against the
   repository evidence. Update the plan where warranted and include a compact
   `Advisor review` section stating the material findings, what changed, and
   any disagreement retained with its evidence. Never paste an agent response
   into the plan without independent judgment.
7. Present the reviewed implementation plan through `ExitPlanMode` for
   explicit user approval when no unattended mandate exists. With an explicit
   unattended/follow-the-plan mandate, publish the reviewed plan as a progress
   update and continue automatically; do not stop merely to ask Claude to begin.
8. `auto`, `acceptEdits`, `bypassPermissions`, or
   `--dangerously-skip-permissions` never permit Claude to skip inspection,
   planning, source review, numerical-integrity gates, ownership checks, or
   fail-closed behavior. An explicit user auto/unattended mandate removes the
   extra conversational approval pause only; it does not broaden scope or weaken
   safety and mathematical contracts.
9. After approval, implement only the approved file allowlist. During an
   unattended run, if scope, mathematical contract, validation criteria,
   ownership, or current `main` changes, do not repeatedly interrupt the user:
   defer the affected step fail-closed, continue all unaffected plan steps, and
   consolidate the exact required decision in the final report.

Read-only investigation and status reporting may be performed while planning.
No edit, commit, amend, merge, rebase, push, generated artifact, or other
state-changing command may occur before the plan is approved, except that an
explicit user unattended/follow-the-plan mandate counts as approval for the
inspected in-scope plan. It never approves a later material change in scope,
equations, bases, schema meaning, ownership, or acceptance criteria.

## Automatic unattended execution

When an explicit unattended/auto/follow-the-plan mandate is active, Claude must
behave as a persistent implementation agent until the plan reaches a terminal
outcome:

- Continue through inspection, reviewed planning, implementation, proportional
  diagnosis, targeted gates, the required final regression, documentation,
  commit, and fast-forward push without asking routine continuation questions.
- Follow every executable step in the approved plan. Do not stop after a partial
  implementation, the first passing targeted test, the first failed test, a
  quiet wait interval, documentation generation, or a local commit while later
  approved steps remain.
- Do not ask whether to read files, search code, run tests, diagnose or repair an
  in-scope failure, rerun the relevant gate, create approved documentation,
  commit passing work, or fast-forward push it.
- Resolve routine choices from repository evidence using the least expansive
  compatible assumption. Record assumptions and evidence in the final handoff.
- Treat the first failed test as diagnostic evidence, not as a reason to stop.
  Investigate and repair the proven in-scope cause, then rerun the smallest
  relevant gate. Continue the diagnose-repair-verify loop while it remains
  inside the approved plan and contracts.
- If one planned step is genuinely blocked, mark it fail-closed, preserve the
  evidence, and continue every later independent in-scope step. Do not ask a
  mid-plan question. Report completed work and the residual blocker together
  after exhausting the plan.
- Never ask generic questions such as `should I continue?`, `should I fix it?`,
  or `do you want me to run the tests?` while meaningful authorized work
  remains.
- A real authority/material-decision blocker includes conflicting ownership,
  remote divergence or merge conflict, destructive or published-history action,
  credentials/access, missing authoritative physics that would require
  invention, changed equations/bases/state order/schema/acceptance gates, scope
  expansion, or an unexplained gate failure after reasonable diagnosis. Defer
  only the affected step, continue the rest, and consolidate any indispensable
  question at the terminal report.
- Keep concise progress updates flowing during long operations. Updates inform
  the user; they are not requests for approval. Continue monitoring long tests
  instead of ending because one wait interval was quiet.
- Never fabricate equations, parameters, results, or PASS evidence to avoid a
  blocker. Automatic execution remains subject to every rule imported from
  `AGENTS.md`.

## Required agent roles and advisor escalation

The three global agents have separate responsibilities and must not be treated
as interchangeable:

- `Explore` gathers broad read-only evidence and maps files, symbols, callers,
  producers, consumers, tests, history, and defect records. It supplies facts
  for decisions; it does not design the solution or edit files.
- `Plan` converts verified evidence into a coherent implementation-ready
  design with ordered steps, allowlist, contracts, edge cases, stop conditions,
  and validation gates. It does not approve its own plan or edit files.
- `custom-advisor` acts as the read-only senior reviewer. It challenges the
  proposed reasoning, identifies counterexamples and simpler alternatives,
  and advises when the primary agent is uncertain. It does not implement or
  become the source of numerical truth.

In addition to its mandatory Plan Mode review, consult `custom-advisor`
whenever the primary agent is not confident that its reasoning or proposed
action is correct. Do not guess and do not use confidence alone as evidence.
State the exact uncertainty, the competing interpretations, the traced runtime
path, and what evidence would falsify each interpretation. Escalate especially
when one or more of these conditions applies:

- the behavior crosses three or more layers, such as option normalization,
  selector evidence, runtime transactions, state publication, and plotting;
- the decision depends on PF/SSSA/TS equations, reference frames, per-unit
  bases, residual/Jacobian conventions, eigenvalue gates, or current limits;
- the logic changes reference ownership, resource/index identity, island
  membership, event ordering, left/right sample identity, fingerprints, or
  atomic commit/rollback behavior;
- more than one plausible interpretation remains after tracing the code, or a
  proposed shortcut might discard a feasible/optimal configuration;
- a failure is intermittent, evidence conflicts, or the proposed fix changes
  a fail-closed path, readiness claim, or mathematical acceptance criterion.

The primary agent must first state the concrete question and use `Explore` or
direct read-only inspection to trace the relevant runtime path. Give
`custom-advisor` a bounded task: challenge assumptions, identify invariants
and counterexamples, trace producer-to-consumer behavior, and name the evidence
that would falsify the proposed conclusion. Prefer one well-scoped advisor
review over many overlapping agents. If new evidence materially changes scope,
contracts, ownership, or gates, return to Plan Mode and repeat the complete
`Explore` -> `Plan` -> `custom-advisor` review cycle before mutation.

The advisor is not an authority and does not replace repository evidence,
equation/source review, tests, user approval, or the single-owner rule. It is
read-only unless the approved plan explicitly assigns it a disjoint file
allowlist. The primary agent remains responsible for reconciling the review
against source code, recording agreements and disagreements, and making the
final recommendation. Never accept an advisor conclusion merely because it is
confident, and never use advisor output to relax a gate or fabricate evidence.

If any required agent is unavailable during Plan Mode, perform the missing
role explicitly as a separate self-review pass, state which agent was
unavailable, and disclose the limitation before `ExitPlanMode`. Never claim
that `Explore`, `Plan`, or `custom-advisor` review occurred when it did not.
Outside Plan Mode, use the same fallback for an unavailable `custom-advisor`
and report it in the final response.
