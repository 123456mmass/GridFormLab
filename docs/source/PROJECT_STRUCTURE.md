# N-Bus Clone Structure

## Root
- Public entrypoints and compatibility wrappers stay here.
- Main commands:
  - `run_powerflow_gui`
  - `run_powerflow_tests`
  - `run_powerflow_suite`
  - `powerflow_newton_raphson`
  - `powerflow_gauss_seidel`
  - `cpf_load_scaling`
  - `cpf_predictor_corrector`
  - `ac_optimal_power_flow`
  - `economic_dispatch_opf`

## +cases
- Packaged case library and reference catalogs.
- Root-level `case_*` files are compatibility wrappers that forward here.

## +examples
- Packaged launchers for GUI and quick example runs.
- Root-level `run_gui`, `run_ieee14_example`, `run_nbus_example`, and `run_powerflow_suite` forward here.

## +pfsolver
- Packaged PF, CPF, and OPF implementations.
- `ac_optimal_power_flow` is the full-network AC OPF solver using a
  self-written coordinate pattern search and the project-owned NR solver.
- `economic_dispatch_opf` is the Saadat one-bus economic-dispatch solver.
- Root-level solver function names stay the same and forward here.

## +pfapp
- GUI implementation package (45 files).
- **`run_powerflow_gui.m`** — thin orchestrator (~85 lines). Initializes app, calls `create_gui_layout`, wires callbacks, defines nested wrappers.
- **Layout:** `create_gui_layout`
- **Action callbacks:** `run_selected_action`, `export_last_action`, `open_separate_plots_action`, `open_analysis_plots_action`, `run_tests_action`, `run_suite_headless`
- **Case loading:** `load_selected_case`, `browse_custom_case`
- **CPF helpers:** `build_cpf_options`, `auto_calibrate_cpf`, `apply_cpf_setup`, `choose_auto_target_bus`, `predictor_defaults`, `load_scaling_defaults`
- **Result rendering:** `show_powerflow_result`, `show_cpf_result`, `show_suite_result`, `show_opf_result`, `plot_empty_state`
- **UI helpers:** `set_busy`, `start_progress`, `stop_progress`, `append_log`, `common_options`, `update_method_state`
- **Standalone figures:** `open_powerflow_figure`, `open_cpf_figure`, `open_suite_figure`, `open_opf_figure`, `open_cpf_reference_figure`
- **Analysis plots:** `open_benchmark_3d_plots`, `plot_metric_3d`, `choose_reference_pv_series`, `mark_cpf_points`
- **Utilities:** `powerflow_summary_line`, `cpf_summary_line`, `opf_summary_line`, `make_safe_name`, `cpf_opened_plot_line`, `fillmissing_for_plot`, `shorten_labels`, `is_powerflow_case_loader`, `make_case_registry`

## +pfchecks
- Automated test implementation package.

## internal/core
- Core solver helpers:
  - case normalization and validation
  - mismatch and Jacobian assembly
  - state/vector conversions
  - result struct building

## internal/plotting
- Shared plotting utilities for PF and CPF.

## internal/export
- CSV/TXT/PDF/PNG export helpers.

## internal/reports
- Formal power-flow report formatting and console report output.

## docs/source
- Hand-edited project notes, Markdown docs, and LaTeX report source.

## docs/generated
- LaTeX build artifacts and generated report PDF files.
- Treat this folder as generated output, not as primary source.

## output
- Exported results and generated figures.

## tmp
- Temporary PDF/image extraction artifacts.

## Path bootstrap
- `pf_init_paths.m` adds `internal/**` to the MATLAB path automatically.
- Public entrypoints call it at startup, so the user should not need to run `addpath` manually.
- Package folders like `+cases` and `+examples` are resolved from the project root.
