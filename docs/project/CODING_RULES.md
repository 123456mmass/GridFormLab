# Coding Rules — N-Bus Power Flow Studio

## 1. Goal
All numerical analysis in this repository must be implemented *in-house* using
this project's own MATLAB code. The repository must remain free of external
power-system toolboxes, third-party libraries, cloud services, or wrapped
commercial solvers that perform power-flow or stability calculations for us.

## 2. What is allowed
- **MATLAB base built-in functions** such as `eig`, `inv`, `lu`, `qr`, `plot`,
  `bar`, `scatter`, `linspace`, `sprintf`, `fopen`, `fprintf`, `exportgraphics`,
  `uifigure`, `uiaxes`, `str2double`, `mean`, `max`, `sum`, `abs`, `real`,
  `imag`, etc.
- **Project functions only**: `+pfsolver/*`, `+smib/*`, `+pfapp/*`,
  `+pfchecks/*`, `internal/*`, `+cases/*`, `+stability/*`.
- **External system utilities for report rendering only**: `xelatex`
  (PDF compilation) is permitted because it does not perform any power-system
  computation.

## 3. What is prohibited
No code in this repository may call any of the following for power-flow,
small-signal stability, or electrical network modeling:

- MATLAB Power System Toolbox (`powerlib`, `Simscape Electrical`)
- MATPOWER
- Pandapower / PyPower
- PSS/E, PowerWorld, DigSILENT, PSAT, OpenDSS
- Any Python integration (`py.*`, `pyimport`) for power-system computation
- Cloud APIs or remote web services for computation
- Commercial or open-source toolboxes that provide ready-made power-flow,
  continuation power-flow, optimal power-flow, or eigenvalue analysis
- Symbolic toolbox calls (`syms`, `solve`) for numerical solver workarounds

## 4. Implementation rule
Every algorithm that produces a numerical result — power flow, continuation
power flow, optimal power flow, SMIB state matrices, and stability figures —
must be coded explicitly in this repository. If a function is not part of this
project and is not a MATLAB base built-in, it must not be called.

## 5. Plotting and GUI
Figures must use MATLAB base graphics primitives only. Do not use
`matlab2tikz`, `export_fig`, or other third-party plotting helpers.

## 6. Adding dependencies
Before adding any new external file, toolbox call, or system dependency:
1. Document the reason in this file.
2. Add a fallback that keeps the code working on a plain MATLAB installation
   without the dependency.
3. Update the continuous-integration workflow if necessary.

## 7. Verification
Before committing, run:
```matlab
runtests('tests')
```
All tests must pass. Any newly introduced external toolbox call is considered
a regression and must be removed.

## 8. Documented exception: the AI supervisory layer (`+ai/`, `scripts/ai/`)

Recorded under rule 6. This is the one place in the repository that opens an
outbound network connection, and the reason it is admissible is narrow.

**What it does.** `scripts/ai/ai_supervisor.m` reads a scenario cache, extracts
physics indices that this repository computed (frequency, RoCoF, bus voltage,
ESCR), and POSTs them to an OpenAI-compatible chat-completions endpoint. The
reply names which IBR bus(es) should switch from grid-following to
grid-forming.

**Why rule 3 does not cover it.** Rule 3 forbids cloud APIs *for computation* —
power flow, small-signal stability, electrical network modeling. The endpoint
performs none of these. Every number it receives was produced by this
repository's own solvers, and what it returns is a control-mode *judgement*, not
a numerical result. No power-flow, SSSA, TS, selector, gate, or acceptance
decision in this repository consumes anything it produces.

**Isolation.** The layer is read-only with respect to the engine. It does not
enter `stability.ts_simulate_ibr_hybrid`, whose decision contract remains
`severity = min(1, max(0, 0.5*J_V + 0.5*J_f))` over `J_V` and `J_f` alone. It
writes only to its own mode table, and only to record what it believes it has
committed.

**Fallback (rule 6.2).** `ai.ai_fallback_selector` is a deterministic rule-based
selector that answers from the same features the model is shown, so a machine
with no key, no route out, or no MATLAB toolboxes still gets a decision. A
transport failure, a non-200 status, or a reply that fails validation falls back
to it and the loop continues; it never aborts the run. `force_fallback = true`
bypasses the network entirely, which is how `tests/test_ai_supervisor_contract.m`
covers the full pipeline offline. Deleting `+ai/ai_call_llm.m` and routing
straight to the fallback leaves everything else working.

**Credential.** The API key is read from the environment variable named by
`opts.api_key_env` (default `LLM_API_KEY`). It is never read from a file in this
repository, because this repository is version controlled.

**Dependency (rule 6.1).** `matlab.net.http` is a base MATLAB namespace, not a
toolbox, so no toolbox requirement is added. The guard in
`tests/test_no_external_solver_dependency.m` is unaffected.

**Status.** The layer is a shadow: its verdicts are comparable to the engine's
precisely because they do not steer it. It must not be cited as evidence that a
production switching decision was made or validated.
