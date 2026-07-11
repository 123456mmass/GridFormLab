# In-house Power-Flow and Stability Toolkit

MATLAB implementations of power flow, small-signal stability analysis (SSSA),
and transient stability (TS). Production solvers are project code; PSAT and
PGAz are reference tools used only by validation scripts.

## Quick start

Open MATLAB in this repository and run one of the root launchers:

```matlab
run_powerflow   % choose a case, run in-house Newton-Raphson PF
run_sssa        % choose a supported SSSA case/model
run_ts          % choose a case, run TS and create the four-panel plot
run_gui         % legacy power-flow GUI
```

Non-interactive example:

```matlab
pf_init_paths;
r = solve_case('analysis','ts','case','rts24', ...
    'options',struct('plot_results',true,'verbose',true));
```

Padiyar two-area reference study:

```matlab
pf_init_paths;
pf = solve_case('analysis','pf','case','padiyar_two_area', ...
    'options',struct('plot_results',false));
ssa = solve_case('analysis','sssa','case','padiyar_two_area');
ts = solve_case('analysis','ts','case','padiyar_two_area', ...
    'options',struct('plot_results',true));
generate_padiyar_two_area_report;
```

The reference follows Padiyar model 1.1 with a single-time-constant AVR
(five states per generator). It deliberately does not infer sixth-order data
or PSS settings that are absent from the cited source pages.

## Repository layout

- `+cases/` — case loaders and the canonical case catalog
- `+pfsolver/`, `+stability/`, `+smib/` — production analysis code
- `compat/` — backward-compatible unqualified MATLAB wrappers
- `scripts/` — examples, validation, diagnostics, and report generators
- `tests/` — MATLAB unit/regression tests
- `legacy/` — archived submissions/reference implementations; not on the path
- `docs/` — reports, contracts, and project handoff notes

`pf_init_paths` adds only `internal/`, `compat/`, `scripts/`, and `docs/`.
It intentionally does not add `legacy/`.

See [AGENTS.md](AGENTS.md) and
[docs/project/AGENT_HANDOFF.md](docs/project/AGENT_HANDOFF.md) before making
solver or case-format changes.
