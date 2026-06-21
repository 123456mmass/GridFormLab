# N-Bus Power Flow Studio

MATLAB toolkit for power system analysis — Newton-Raphson, Gauss-Seidel, Continuation Power Flow (CPF), Optimal Power Flow (OPF), and SMIB small-signal stability (Kundur Ch.12).

## Features

- **Power Flow Solvers**: Newton-Raphson and Gauss-Seidel with Q-limit enforcement
- **Continuation Power Flow**: Load scaling and predictor-corrector methods for voltage stability
- **Economic Dispatch / OPF**: Classical quadratic-cost optimization with generator limits
- **SMIB Small-Signal Stability**: Kundur Ch.12 — classical, field-circuit, AVR, and PSS models with eigen-analysis
- **Modern MATLAB GUI**: Theme-switchable (light/dark), in-place rebuild, metric cards, SMIB Stability tab
- **Multi-format Export**: CSV, JSON, HTML, PDF, PNG
- **Benchmark Mode**: Headless multi-method comparison with timing
- **Test Suite**: MATLAB unit tests

## Quick Start

### MATLAB GUI

```matlab
run_powerflow_gui
```

### Headless Benchmark

```matlab
pf_init_paths();
results = benchmark_all_methods(case_ieee5bus());
```

### SMIB Stability Analysis

```matlab
run_smib_example   % standalone, prints golden-reference checks
% or pick a Kundur SMIB case + "SMIB Stability Analysis" method in the GUI
```

## Project Structure

```
n_bus_clone/
├── +pfapp/              # GUI application package
│   ├── run_powerflow_gui.m       # GUI launcher
│   ├── create_gui_layout.m       # Themed layout (rebuild-in-place)
│   ├── wire_callbacks.m          # Central callback wiring
│   ├── cb.m                      # GUI callback dispatcher
│   ├── run_selected_action.m     # Solver dispatch + SMIB hand-off
│   ├── run_smib_action.m         # SMIB analysis dispatch
│   ├── show_smib_result.m        # SMIB eigenvalue/s-plane render
│   ├── open_smib_figure.m        # Standalone SMIB figures
│   ├── toggle_theme.m            # Light/dark rebuild
│   ├── save_preferences.m        # Persist user settings
│   ├── load_preferences.m        # Restore user settings
│   ├── discover_cases.m          # Auto-scan +cases/
│   ├── run_async_action.m        # Async solver (PCT)
│   ├── run_tests_action.m        # Test runner
│   └── thai_messages.m           # Thai localization
├── +pfsolver/           # Power flow solvers
│   ├── powerflow_newton_raphson.m
│   ├── powerflow_gauss_seidel.m
│   ├── cpf_load_scaling.m
│   ├── cpf_predictor_corrector.m
│   ├── economic_dispatch_opf.m
│   ├── ac_optimal_power_flow.m
│   └── benchmark_all_methods.m   # Headless benchmark
├── +cases/              # IEEE/Saadat + Kundur SMIB test cases
├── +smib/               # SMIB stability (K-constants, state matrices, analyze)
├── internal/            # Shared internal utilities (export, plotting)
│   └── plotting/                # PF + SMIB plot functions
├── tests/               # MATLAB unit tests
│   ├── test_nr_solver.m
│   ├── test_gs_solver.m
│   ├── test_cpf.m
│   ├── test_opf.m
│   └── test_smib.m
├── .github/workflows/   # CI/CD
│   └── ci.yml
└── output/              # Generated reports and plots
```

## GUI Overview

| Tab | Content |
|-----|---------|
| Analysis | Voltage profile + convergence history (PF/CPF/OPF) |
| Results Table | Bus / dispatch / CPF data table |
| Advanced Plots | CPF PV-curve + OPF dispatch charts |
| SMIB Stability | s-plane eigenvalues + impulse response + eigenvalue table |

The dashboard shows four live metric cards (status / case / method / result).
Selecting a Kundur SMIB case auto-switches the method to *SMIB Stability Analysis*.

## Test Cases

| Case | Buses | Method | Source |
|------|-------|--------|--------|
| IEEE 5-bus | 5 | PF, CPF | Saadat Ch.6 |
| IEEE 14-bus | 14 | PF, CPF | MATPOWER |
| IEEE 30-bus | 30 | PF, CPF, OPF | Saadat/MATPOWER |
| IEEE 300-bus | 300 | PF | MATPOWER |
| Saadat 3-bus PQ | 3 | PF | Saadat Ex 6.7 |
| Saadat 3-bus PV | 3 | PF | Saadat Ex 6.8 |
| Saadat OPF Ex 7.4-7.6 | var | OPF | Saadat Ch.7 |
| Kundur SMIB classical | 1 | SMIB Model A | Kundur Ex 12.2 |
| Kundur SMIB field circuit | 1 | SMIB Model B | Kundur Ex 12.3 |
| Kundur SMIB + AVR | 1 | SMIB Model C | Kundur Sec 12.4 |
| Kundur SMIB + PSS | 1 | SMIB Model D | Kundur Ex 12.6 |

## Running Tests

### MATLAB
```matlab
import matlab.unittest.TestSuite
import matlab.unittest.TestRunner
suite = TestSuite.fromFolder('tests');
runner = TestRunner.withTextOutput();
runner.run(suite);
```

## License

MIT
