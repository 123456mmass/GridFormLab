# Documentation Layout

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
