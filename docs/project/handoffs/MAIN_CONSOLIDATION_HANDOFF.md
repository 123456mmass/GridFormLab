# Main consolidation handoff — 2026-07-13

## Objective and integration policy

This checkpoint consolidates the completed shared foundation, report assets,
and interactive launcher work onto `main` so that a fresh clone contains the
same launcher and report files used on the development machine. The unfinished
IEEE14 IBR mission remains isolated. Additional PF/TS method routing is deferred
until the IBR mission reaches its integration gate.

Production numerical paths remain in-house MATLAB. No external solver was
added to a production path, and no equation, case value, tolerance, event time,
or acceptance threshold was changed to force a result.

## Progression merged in this integration

1. `plan/pf-ts-multimethod` at `35599cc` was merged. This brings in Track A
   IBR interface foundation `31a211d` plus the tested PF/TS multi-method core.
2. `report/system-methods-v2` at `5d151ca` was merged.
3. The latest local Padiyar report artifacts were checkpointed in `c55d3b8`:
   - time-domain horizon 20 s;
   - fault bus 101;
   - `Zf = j10^-4 pu`;
   - stored absolute rotor angle and speed plots;
   - separate angle/speed/electrical-power/voltage figures;
   - linear Newton--Raphson mismatch plot;
   - updated `.tex`, `.lyx`, `.pdf`, generated tables/figures, and generation
     and comparison scripts.
4. `checkpoint/dialog-system` at `7f33dea` was merged. `run_ts.m` now selects a
   case first and then opens the case-aware settings dialog. The canonical TS
   plotter resolves from the current worktree and opens separate docked figures.
5. Two report tests inherited from the report branch were converted into valid
   `matlab.unittest` function-test suites. Their assertions and numerical
   criteria were unchanged. A static launcher comment was added to retain the
   existing testable declaration that the production TS default is fixed-step.

## Fresh verification on the consolidated tree

Environment date/time zone: 2026-07-13, Asia/Bangkok.

```matlab
restoredefaultpath;
cd('/tmp/Power-flow-main-integration');
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);
```

Result: **530 passed / 0 failed / 0 incomplete**.

The full run included the real-path external-solver scanner and fresh RTS-24
PSAT cross-validation. The Padiyar LaTeX report compiled twice with
`pdflatex -halt-on-error`: 24 pages, no undefined references after the second
pass. The only remaining LaTeX diagnostic was the pre-existing missing-author
warning.

## Readiness and deferred work

- Track A generic IBR interface foundation: merged and regression-green.
- PF/TS multi-method core: merged and directly tested, but **production routing
  remains deferred**. `solve_case`/TS continue to use their canonical NR and
  trapezoidal routes. Do not claim selectable production multi-method routing.
- Interactive dialog and current TS plot conventions: merged and
  regression-green.
- System-methods and Padiyar reports: merged; latest Padiyar source and PDF are
  tracked.
- `feature/ieee14-auto-vsg-switching` at `ed00805` was deliberately **not
  merged**. It is a WIP checkpoint; its latest recorded Phase-4 targeted result
  is 5 pass / 5 errors. Resume that branch independently and merge only after
  its gates pass on the then-current `main`.

## Preserved work outside this integration

The original worktree at `/home/birds/Documents/Power-flow` remains on
`checkpoint/dialog-system`. Its unrelated modified/untracked files were not
deleted, reset, cleaned, or silently staged. No IBR WIP branch, historical
Track B stash, or external-reference output was merged into production.

## Next owner

The next active owner is the IEEE14 1-SG + 4-IBR mission on
`feature/ieee14-auto-vsg-switching`. Rebase or merge the new `origin/main`, fix
and verify Phase 4, then continue the sourced GFL/VSG phases. Resume PF/TS
production method routing only after the IBR integration gate, as directed by
the user.
