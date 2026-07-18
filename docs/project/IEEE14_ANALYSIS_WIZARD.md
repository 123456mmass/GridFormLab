# IEEE14 Analysis Wizard

Date: 2026-07-19
Branch: `main`
Status: `LEGACY_DIALOG_DEFAULT / WIZARD_BACKEND_AVAILABLE`

## Purpose

`solve_case.m` is the canonical public launcher for the four in-house
analyses (PF, SSSA, TS, IBR). Before this work its interactive surface was
four separate `listdlg`/`inputdlg` prompts plus a hand-built `dialog` for
IBR, with validation inline in local functions unreachable from tests.

This work introduced a sequential, method-aware **wizard** built entirely
with base-MATLAB `figure`/`uipanel`/`uicontrol` (NOT uifigure; the two are
not mixed). The wizard collects analysis, case, configuration, and (for
TS/IBR) events, reviews the run contract, executes through the existing
production launchers, and displays a generic 12-section result view. PF and
SSSA are event-free. The pure logic is separated from the GUI so headless
`matlab -batch` tests work.

After desktop acceptance, the user selected the former compact dialog workflow
as the default interactive surface. Therefore `solve_case()` now opens the
legacy-style analysis list, case list, and method-specific settings dialogs.
The six-page wizard remains an explicit non-default UI, while its pure request,
validation, dispatch, and result-adapter layers remain the shared backend.

This is a UI/orchestration change only. No new PF/SSSA/equilibrium/TS
solvers, no independent SSSA A matrix, no GFL-specific solver, and no loaded
solutions as production results were introduced.

## Architecture

```
solve_case (canonical public entry, thin wrapper)
 ├─ no arguments / partial ──> wizard.legacy_show (compact dialog workflow)
 └─ programmatic            ──> wizard.build_request
                                ↓
                          wizard.validate_request
                                ↓
                          wizard.dispatch_analysis   (SINGLE shared dispatcher;
                                                      wizard UI + programmatic
                                                      path both call this)
                                ↓
                          existing PF / SSSA / TS / IBR launcher
                                ↓
                          wizard.adapt_result  (generic 12-section view model)
                          wizard.adapt_ibr_section_h  (IBR-only explicit adapter
                                                       to +ibr/section_h_report.m)
```

The single shared dispatcher (`wizard.dispatch_analysis`) is used by BOTH the
wizard UI and the programmatic path. No duplicate dispatch exists anywhere.

## Stable analysis IDs

| ID    | Analysis                          | Events           | Equilibrium required |
|-------|-----------------------------------|------------------|----------------------|
| `pf`  | Power Flow                        | NOT_APPLICABLE   | no                   |
| `sssa`| Small-Signal Stability           | NOT_APPLICABLE   | yes                  |
| `ts`  | Transient Stability              | optional         | yes                  |
| `ibr` | IBR Simulation (mixed-resource)  | optional         | yes                  |

`ibr` already means mixed-resource transient stability; a separate `ibr_ts`
ID is NOT introduced.

## Pure layer (+wizard/*, headless-testable)

| File                       | Responsibility                                              |
|----------------------------|-------------------------------------------------------------|
| `analysis_registry.m`      | Four analyses with method metadata.                         |
| `discover_cases.m`         | Lazy case enumeration (no PF/equilibrium/solved-state load).|
| `defaults_for_method.m`    | Default-option producer (frozen priority order).           |
| `build_request.m`          | Selections -> unvalidated `wizard_request_v1` struct.       |
| `validate_request.m`       | Schema + event-contract validation; stable failure IDs.     |
| `dispatch_analysis.m`      | SINGLE shared dispatcher; calls existing launchers verbatim.|
| `adapt_result.m`           | Generic 12-section view model (no production-result mutation).|
| `adapt_ibr_section_h.m`    | Explicit IBR-only adapter to `+ibr/section_h_report.m`.    |
| `config_io.m`              | Save/load `wizard_config_v1` with its own fingerprint.      |
| `ibr_settings_dialog.m`   | Base-MATLAB three-column IBR settings editor.              |

## UI layer (base-MATLAB)

| File                  | Responsibility                                              |
|-----------------------|-------------------------------------------------------------|
| `show.m`              | Wizard controller (thin; routes to pure functions).         |
| `create_figure.m`    | Classic figure (NOT uifigure); Sarabun/Segoe UI font fallback; non-interactive guard raises `MATLAB:hg:NonInteractiveFunctionSupport` in batch. |
| `render_page.m`      | Page dispatcher + step indicator + fixed footer (Back/Next/Run/Cancel). |
| `go_page.m`          | Page navigation (skips non-applicable events page).        |
| `run_from_ui.m`      | Build -> validate -> dispatch from the UI; inline validation. |
| `cancel.m`, `close_request.m` | Lifecycle.                                          |
| `+pages/p1_analysis.m` ... `p6_results.m` | Page builders (render only; three-column layout). |
| `+pages/format_value.m`, `classify.m` | Helpers.                                           |

Page/render builders live under nested packages `+wizard/+pages/*` and
`+wizard/+render/*` (valid MATLAB nested packages); no ordinary package
subfolders are added to the runtime path.

## Default-value provenance (frozen priority)

1. case-defined canonical defaults (`network_case_catalog` per-entry options);
2. source-defined model defaults;
3. existing approved launcher defaults;
4. frozen project numerical defaults (e.g. EMF6 `corrector_iter=3`);
5. otherwise require an explicit value or mark unavailable.

Display presets may change only display/output sampling — never solver step,
event timing, physical parameters, tolerances, or gates.

## events=false reaches production as an actually empty schedule

For IBR, `events_policy='event_free'` (an explicit disabled event struct or
an empty events value) reaches `stability.run_hybrid_case` as an actually
empty schedule. The result schema is distinct and slimmer (17 fields) than
the events-on schema (58 fields): `events` is `[0 0]`, every per-sample
`transaction_id` is 0, and `execution_summary.event_transactions` is 0.

The wizard does NOT hide canonical events only at the UI layer. The disabled
struct is passed through to the runtime, which produces the empty-schedule
sentinel. For TS, the event-free path leaves the TS event fields absent so
`ts_simulate` runs event-free.

## Result view model (generic 12 sections)

`wizard.adapt_result` builds a uniform 12-section view model for ALL
analyses. Each section has `index`, `title`, `status` (`ok` /
`not_run` / `not_applicable`), and a content struct. Missing information is
`not_run` / `not_applicable`, never fabricated. The production result is
never mutated.

The IBR Section H producer (`+ibr/section_h_report.m`) is reused ONLY
through the explicit `wizard.adapt_ibr_section_h` adapter (IBR results only;
PF/SSSA/TS return `not_applicable`).

## Headless / programmatic usage

```matlab
% Programmatic (no UI):
req = wizard.build_request('pf', 'ieee5', 'options', struct('verbose', false));
req = wizard.validate_request(req);
result = wizard.dispatch_analysis(req);
view = wizard.adapt_result(result, req);

% Save/load a validated configuration:
wizard.config_io('save', req, 'my_config.json');
loaded = wizard.config_io('load', 'my_config.json');

% Interactive (opens the wizard UI; in batch raises
% MATLAB:hg:NonInteractiveFunctionSupport):
solve_case();
```

## Known limitations

- The wizard figure cannot be kept alive in a non-interactive (batch) MATLAB
  session; `wizard.create_figure` raises `NonInteractiveFunctionSupport`
  (matching the frozen partial-invocation contract). The UI smoke test
  exercises routing/builders directly; the interactive figure render is
  exercised manually in a desktop session.
- The 6-section wizard UI is functional but minimal; the page builders render
  base-MATLAB controls (listboxes, uitable, text) with the polished styling
  (step indicator, accent colors, three-column layout, fixed footer). Full
  styling polish (scrollable panels, expandable Advanced) is scaffolded but
  not exhaustively rendered.
- Live progress counters: the existing launchers do not publish a progress
  callback, so the wizard shows the current execution stage and publishes
  counters after completion (correction #5). No numerical solver was edited
  to implement progress.

## Test commands and results

```matlab
pf_init_paths;
% Characterization (frozen ABI before/after refactor):
runtests('tests/test_wizard_characterization.m')        % 18 passed
% Pure layer:
runtests('tests/test_wizard_pure_layer.m')              % 29 passed
% Dispatch + adapt_result + config_io:
runtests('tests/test_wizard_dispatch.m')                % 15 passed
% UI smoke (invisible figure / routing):
test_wizard_ui_smoke                                    % 14 passed
% Section H adapter:
runtests('tests/test_wizard_section_h_adapter.m')       % 6 passed
% Existing launcher contracts:
runtests({'tests/test_ibr_launcher_settings_ui.m', ...
          'tests/test_ibr_launcher_configuration_logging.m', ...
          'tests/test_solve_case_launcher.m'})          % 16 passed
% Full regression (required: edits single-owner shared solve_case.m):
pf_init_paths; r = runtests('tests', 'IncludeSubfolders', true);
```

Environment: MATLAB R2025a on Windows 11. Tested commit: see `git log`.
