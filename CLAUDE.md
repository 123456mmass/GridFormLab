@AGENTS.md

# Claude Code bootstrap

`AGENTS.md` above is the repository policy and must be followed in full. Do
not rely on conversation memory or a previous session's summary as a substitute
for reading the imported instructions.

Before any task that may modify files, tests, cases, documentation, reports,
artifacts, Git history, external state, or numerical behavior:

1. Call `EnterPlanMode` before performing any mutation.
2. Read `docs/project/TRACK_COORDINATION.md`, the current handoff, and the
   relevant track plan from disk.
3. Inspect the repository and present the implementation plan through
   `ExitPlanMode` for explicit user approval.
4. Do not treat `auto`, `acceptEdits`, `bypassPermissions`, or
   `--dangerously-skip-permissions` as permission to skip planning.
5. After approval, implement only the approved file allowlist and stop for
   renewed approval if the scope, mathematical contract, validation criteria,
   ownership, or current `main` changes.

Read-only investigation and status reporting may be performed while planning,
but no edit, commit, amend, merge, rebase, push, generated artifact, or other
state-changing command may occur before the plan is approved.
