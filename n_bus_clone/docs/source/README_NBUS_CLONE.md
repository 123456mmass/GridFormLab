# N-Bus Clone

This folder is a cloned and refactored version of the original project.
The original 5-bus script was converted into a generic n-bus analysis toolkit.
Newton-Raphson remains the primary solver, with Gauss-Seidel and two CPF
variants added for comparison and voltage-stability studies.
The toolkit now includes both full-network AC OPF and Saadat Chapter 7
one-bus economic-dispatch OPF references.

## Files

- `powerflow_newton_raphson.m`
  Generic solver for any n-bus case.
- `powerflow_gauss_seidel.m`
  Generic Gauss-Seidel solver with Slack/PV/PQ bus support.
- `cpf_load_scaling.m`
  Repeated-NR continuation power flow using a load-scaling parameter.
- `cpf_predictor_corrector.m`
  Pseudo-arclength predictor-corrector CPF for comparison.
- `economic_dispatch_opf.m`
  Saadat Chapter 7 economic-dispatch OPF solver for quadratic generator costs,
  demand balance, and optional generator MW limits.
- `ac_optimal_power_flow.m`
  Full-network AC OPF using a self-written coordinate pattern search wrapped
  around the project's own Newton-Raphson power-flow solver, with AC P/Q
  balance, voltage limits, generator P/Q limits, quadratic costs, and optional
  line MVA limits.
- `case_saadat_example_6_7.m`
  Hadi Saadat Chapter 6 Example 6.7 three-bus PQ benchmark.
- `case_saadat_example_6_8.m`
  Hadi Saadat Chapter 6 Example 6.8 three-bus PV benchmark.
- `case_saadat_ieee30bus.m`
  Hadi Saadat Chapter 6 Example 6.9 IEEE 30-bus benchmark, including AC OPF
  generator cost/limit data used by the main OPF regression test.
- `case_saadat_opf_example_7_4.m`, `case_saadat_opf_example_7_5.m`, `case_saadat_opf_example_7_6.m`
  Hadi Saadat Chapter 7 economic-dispatch OPF benchmarks.
- `saadat_reference_catalog.m`
  Inventory of implemented Saadat reference cases and their bus/generator counts.
- `run_powerflow_tests.m`
  Automated regression tests for NR, GS, CPF, Q-limit switching, and Saadat references.
- `run_powerflow_gui.m`, `run_gui.m`
  Interactive MATLAB GUI for selecting cases, methods, options, plotting, tests, and export.
- `pf_export_results.m`, `pf_export_powerflow_report.m`, `pf_export_cpf_results.m`, `pf_export_opf_results.m`
  Export bus/line/CPF results as CSV, summaries, console-style TXT/PDF reports,
  and PNG figures.
- `pf_*.m`
  Shared helpers for case normalization, validation, Y-bus construction,
  injection calculation, Jacobian construction, result reporting, and plotting.
- `case_ieee5bus.m`
  Example case package for the current IEEE 5-bus system.
- `case_ieee14bus.m`
  IEEE 14-bus example adapted from MATPOWER official data.
- `case_ieee5bus_bus_data.m`
  Example bus data.
- `case_ieee5bus_line_data.m`
  Example line data.
- `case_template_nbus.m`
  Template for creating a new case such as 14-bus or 30-bus.
- `run_nbus_example.m`
  Simple entry script that runs the 5-bus example through the generic solver.
- `run_ieee14_example.m`
  Simple entry script that runs the IEEE 14-bus example.
- `run_powerflow_suite.m`
  Runs IEEE 5-bus NR, GS, load-scaling CPF, predictor-corrector CPF, and plots
  convergence/PV-curve comparisons.

## Data format

### bus_data

```matlab
[BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload]
```

or

```matlab
[BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload Gsh Bsh]
```

or

```matlab
[BusNo Type Vmag VangleDeg Pgen Qgen Pload Qload Gsh Bsh Qmin Qmax]
```

- `BusNo` does not need to be `1:n`. The solver maps external bus numbers internally.
- `Type = 1` for Slack
- `Type = 2` for PV
- `Type = 3` for PQ
- `Qmin/Qmax` are optional generator reactive limits in pu. If finite limits are supplied, Newton-Raphson can switch a violating PV bus to PQ with Q generation fixed at the violated limit.

PV and PQ buses may contain both generation and load. The solvers use net
scheduled injection internally:

```matlab
P_spec = Pgen - Pload
Q_spec = Qgen - Qload   % for PQ buses
```

For PV buses, `P_spec = Pgen - Pload` and the voltage magnitude is fixed at
`Vmag`; reactive generation is calculated from the solved network state.

### line_data

```matlab
[From To R X]
```

or

```matlab
[From To R X B_half]
```

or

```matlab
[From To R X B_half TapRatio]
```

or

```matlab
[From To R X B_half TapRatio PhaseShiftDeg]
```

If `B_half` is omitted, the solver assumes it is zero for every line.
If tap ratio is omitted, the solver assumes `1.0`.
If phase shift is omitted, the solver assumes `0 degree`.

### AC OPF data

Full AC OPF uses the normal `bus_data` and `line_data`, plus optional
`case_data.opf_data.ac`:

```matlab
case_data.opf_data.ac = struct( ...
    'generator_ids', [1; 2], ...
    'generator_bus_ids', [1; 2], ...
    'cost', [0 12.0 0.020; 0 14.0 0.025], ... % alpha beta gamma, P in MW
    'P_min_MW', [0; 0], ...
    'P_max_MW', [220; 140], ...
    'Q_min_MVAr', [-120; -100], ...
    'Q_max_MVAr', [160; 100], ...
    'V_min', 0.95, ...
    'V_max', 1.08, ...
    'S_line_max_MVA', 200 * ones(size(case_data.line_data, 1), 1));
```

If AC OPF data is absent, the solver infers generator buses from Slack/PV
buses and applies conservative default costs and limits. Explicit OPF data is
recommended for reportable studies.

## How to run

GUI mode:

```matlab
cd('C:\Users\qwert\OneDrive\Desktop\api\n_bus_clone')
run_gui
```

In the GUI, choose a built-in demo/reference case or click
`Browse Custom n-bus Case` to load your own `.m`/`.mat` case, choose a method,
tune options, then click `Run`.
For the Saadat OPF examples, choose `Saadat OPF Ex 7.4`, `Saadat OPF Ex 7.5`,
or `Saadat OPF Ex 7.6`, then choose `OPF Economic Dispatch`.
For full-network OPF, choose a power-flow case such as `Saadat 30-bus reference`
or `5-bus demo`, then choose `AC OPF`.
Use `Export Last Result` to write CSV, text summary, console-style TXT/PDF report,
and PNG files under `output`.
Use `Open Separate Plots` to open larger standalone figures that include
voltage magnitude, voltage angle, convergence, and CPF curves. Use
`3D / CPF Ref Plots` for benchmark-style 3D bar plots across cases/solvers
and a CPF predictor-corrector reference diagram. The 3D plots are PF metrics;
AC OPF exports include dispatch, bus-voltage, and line-loading CSV files.

Script mode:

```matlab
cd('C:\Users\qwert\OneDrive\Desktop\api\n_bus_clone')
run_nbus_example
```

For IEEE 14-bus:

```matlab
cd('C:\Users\qwert\OneDrive\Desktop\api\n_bus_clone')
run_ieee14_example
```

For the full IEEE 5-bus comparison suite:

```matlab
cd('C:\Users\qwert\OneDrive\Desktop\api\n_bus_clone')
suite = run_powerflow_suite();
```

For automated tests, including Hadi Saadat textbook references:

```matlab
cd('C:\Users\qwert\OneDrive\Desktop\api\n_bus_clone')
summary = run_powerflow_tests();
```

Headless/no-plot example:

```matlab
case_data = case_ieee5bus();
options = struct('plot_results', false, 'verbose', false);
nr = powerflow_newton_raphson(case_data, options);
gs = powerflow_gauss_seidel(case_data, options);
cpf1 = cpf_load_scaling(case_data, options);
cpf2 = cpf_predictor_corrector(case_data, options);
```

Saadat benchmark examples:

```matlab
gs67 = powerflow_gauss_seidel(case_saadat_example_6_7(), options);
gs68 = powerflow_gauss_seidel(case_saadat_example_6_8(), options);
nr30 = powerflow_newton_raphson(case_saadat_ieee30bus(), options);
```

Saadat OPF/economic-dispatch examples:

```matlab
opf74 = economic_dispatch_opf(case_saadat_opf_example_7_4(), options);
opf75 = economic_dispatch_opf(case_saadat_opf_example_7_5(), options);
opf76 = economic_dispatch_opf(case_saadat_opf_example_7_6(), options);
catalog = saadat_reference_catalog();
```

Full-network AC OPF example, using the IEEE 30-bus Saadat case:

```matlab
acopf30 = ac_optimal_power_flow(case_saadat_ieee30bus(), options);
```

Export example:

```matlab
paths = pf_export_results(nr30, fullfile(pwd, 'output'), 'saadat_ieee30_nr');
cpf_paths = pf_export_cpf_results(cpf1, fullfile(pwd, 'output'), 'ieee5_cpf_load_scaling');
opf_paths = pf_export_opf_results(acopf30, fullfile(pwd, 'output'), 'saadat_ieee30_acopf');
```

`pf_export_results` also creates a detailed report similar to the console
power-flow report:

```matlab
paths.report_txt
paths.report_pdf
```

CPF options include:

- `target_bus`: external bus number for the PV curve, defaulting to Bus 5 when present.
- `lambda_step`: load parameter step size.
- `lambda_max`: maximum load parameter.
- `min_voltage`: stopping threshold for low-voltage points.
- `max_steps`: maximum CPF steps.
- `tolerance`: NR/corrector tolerance.
- `plot_results`: enable or disable figures.

## IEEE 14-bus source

The bundled `case_ieee14bus.m` example is adapted from the official MATPOWER
`case14` dataset:

- MATPOWER reference page: <https://matpower.org/docs/ref/matpower4.1/case14.html>
- MATPOWER official repository: <https://github.com/MATPOWER/matpower/blob/master/data/case14.m>

## How to upgrade to a new n-bus system

1. Copy `case_template_nbus.m`
2. Rename it, for example `case_ieee14bus.m`
3. Replace the sample `bus_data` and `line_data`
4. Run:

```matlab
case_data = case_ieee14bus();
results = powerflow_newton_raphson(case_data);
```

## Custom n-bus cases

The GUI accepts custom files:

- `.m` file: a function with the same filename that returns `case_data`
- `.mat` file: contains `case_data` or a struct with `bus_data` and `line_data`

Minimum format:

```matlab
function case_data = case_my_nbus()
case_data.system_name = 'My n-bus case';
case_data.base_values = struct('S_base_MVA', 100, 'V_base_kV', 230, 'frequency_Hz', 60);
case_data.bus_data = [
    1 1 1.05 0 0 0 0 0;
    2 3 1.00 0 0 0 1.0 0.4
];
case_data.line_data = [
    1 2 0.02 0.06 0.03
];
end
```

## Current limitations

- Exactly one slack bus is required
- PV reactive power limits are supported in Newton-Raphson by PV-to-PQ switching when finite `Qmin/Qmax` values are supplied
- Bus shunts are supported
- Transformer tap ratios and phase shifters are supported
- Full AC OPF does not call MATLAB Optimization Toolbox, MATPOWER, or other
  ready-made PF/OPF solvers; it uses project-owned NR and search routines
- AC OPF is a local nonlinear search implementation; use good limits/costs and
  validate results for each study case
- CPF predictor-corrector is intended as a clear academic comparison method;
  it now includes tangent-continuity and adaptive step reduction, but it is
  still a teaching/reference implementation rather than a full industrial CPF.

## Textbook reference coverage

The repository includes benchmark cases read from:

`C:\Users\qwert\OneDrive\Desktop\api\power system analysis - hadi saadat_320503100.pdf`

- Saadat Example 6.7: three-bus PQ case, printed pages 212-216.
- Saadat Example 6.8: three-bus PV case, printed pages 216-219.
- Saadat Example 6.9: IEEE 30-bus sample system, printed pages 224-228.
- Saadat Example 6.10: three-bus Newton-Raphson, same data as Example 6.8.
- Saadat Examples 6.11 and 6.13: IEEE 30-bus, same data as Example 6.9.
- Saadat Example 7.4: one-bus equivalent, three-generator economic dispatch, printed pages 271-274.
- Saadat Example 7.5: same one-bus equivalent data as Example 7.4, printed pages 275-276.
- Saadat Example 7.6: one-bus equivalent, three-generator dispatch with MW limits, printed pages 277-279.

Implemented bus-count inventory:

```matlab
struct2table(saadat_reference_catalog())
```
