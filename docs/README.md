# Documentation Layout

## Authority and stale-result policy

- Read `../AGENTS.md` and `project/AGENT_HANDOFF.md` before using numerical
  claims from any report or plan.
- Markdown under `source/figures/` is generated evidence, not an authoritative
  contract. Obsolete Kundur comparison summaries that claimed a calibrated
  calibrated sub-percent reproduction were removed.
- Kundur Table E12.3 is reference data only. A result is reportable only when
  it is regenerated from the current in-house implementation and backed by a
  passing test or documented cross-validation script.
- Files under `archive/` are historical and must not be cited as the current
  implementation or current validation status.

## source
- Hand-edited documentation and report source files.
- Main files:
  - `source/PROJECT_STRUCTURE.md`
  - `source/README_NBUS_CLONE.md`
  - `source/REPORT_POWERFLOW_THAI.md`
  - `source/report.tex`

## generated
- Files produced by LaTeX/report generation.
- These are build artifacts and usually should not be edited manually.

## Notes
- Runtime exports still go to `../output`.
- Code entrypoints remain at the project root as compatibility wrappers.
