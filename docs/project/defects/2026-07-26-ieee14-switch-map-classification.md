# SWITCH-2026-07-26-01 — IEEE14 AGSI++ switch study: map collapse criterion, plot gating, and event-bus fail-open

- **Status:** RESOLVED
- **Area:** IEEE 14-bus 1-SG + 4-IBR AGSI/AGSI++ GFL↔GFM switch study (`+ibr/` reduced-6 devices,
  `scripts/reporting/ieee14_switching_map.m`, solve_case route).
- **Branch / base commit / environment:** `main`, working tree on top of `51e0648`;
  MATLAB R2025a (Windows), XeLaTeX for the reports.
- **Found by:** independent read-only review of the uncommitted switch batch (static audit),
  then reproduced numerically.

## Symptoms

Three separate defects in the same batch:

1. **H1 — switching map declared voltage collapse from the during-fault sag.**
   The map classified a grid point as `diverge / voltage-collapse` when
   `min(out.Vmin) < 0.25`, where `out.Vmin` is recorded at every step *including the interval in
   which the shunt fault is applied*. A low-impedance fault pulls the faulted bus down **by
   construction** (`Zf = j0.02` ⇒ shunt `-j50` pu), so severe-but-cleared points were reported as
   collapses even though the network fully recovered. The collapse test was also evaluated
   *before* the switch test, so any genuine GFL→GFM index switch at those points was hidden.
2. **M1 — `plot_results=false` did not disable plotting.** `ibr.padiyar_switch_demo` always
   created the figure and wrote 8 PNGs; the runners only blanked `result.figure_files`. Callers
   asking for numbers still paid the figure cost and wrote files to disk.
3. **M3 — fail-open event location.** `ibr.padiyar_switch_tds` silently relocated an unknown
   `fault_bus` / `step_bus` to network position 1 (`if isempty(fault_bp), fault_bp = 1; end`),
   i.e. it disturbed a *different* bus and reported the result as the requested one.

Related weaknesses fixed in the same pass: the map ignored `newton_all_converged` in its verdict
(an unconverged trajectory could be published as `ride-through`), an unexpected throw was bucketed
as physical divergence, and the sweep silenced **all** warnings.

## Reproduction

```matlab
pf_init_paths;
sys = ibr.build_ieee14_switch_system(index_mode="agsi_pp");

% H1: severe but CLEARED fault -- during-fault sag vs post-clear recovery
o = ibr.padiyar_switch_tds(sys, T=3.0, dt=2e-3, sg_trip_time=inf, ...
        fault_on=1.0, fault_clear=1.15, fault_bus=9, fault_Zf=0.02i);
min(o.Vmin)                      % 0.075  -> old rule => "voltage collapse"
min(o.Vmin(o.tgrid>=1.15))       % 0.990  -> actually a full recovery
o.newton_all_converged           % 1

% M3: unknown scheduled event bus was silently moved to bus position 1
ibr.padiyar_switch_tds(sys, fault_on=1, fault_clear=1.1, fault_bus=999);

% M1: figures were written even with plot_results=false
solve_case('analysis','ibr','case','ieee14_switch', ...
    'options',struct('plot_results',false,'t_end',6));   % 8 PNGs appeared
```

## Root cause (observation vs inference)

- **Observed:** `ibr.padiyar_switch_tds` records `Vmin(ix) = min(|V|)` at every accepted step, and
  the fault admittance is added to `Yt` for `fault_on <= t < fault_clear`. Therefore
  `min(out.Vmin)` is dominated by the *applied* fault, not by the system's ability to survive it.
  Measured at bus 9 with `Zf = j0.02`: during-fault `min|V| = 0.075` pu, post-clear
  `min|V| = 0.990` pu, `newton_all_converged = 1`, `diverged = 0`.
- **Inference:** the classifier therefore encoded "a deep sag exists" as "the system collapsed".
  Because the collapse branch was tested first, the switch outcome at those points was masked.
  This is a classification defect, not a model defect: no equation, parameter, or event changed.
- **Observed:** `padiyar_switch_demo` had no plotting switch; the `plot_results` option existed
  only in the runners, where it filtered the returned path list after the PNGs were written.
- **Observed:** the `isempty(...) -> 1` defaults in the driver predate the multi-system
  generalisation, where `fault_bus`/`step_bus` defaults (3 / 13) are valid in one system and not
  necessarily in another; the builders already fail closed on an unknown IBR/SG bus, so the driver
  was the only fail-open path.

## Falsified hypotheses

- *"The severe points really are voltage collapses"* — falsified: every one of the 24 swept faults
  converges and recovers to 0.98–1.01 pu after clearing; `diverged` is false at all of them.
- *"The optimizer/map reuse of a mutated `sys` corrupts the sweep"* — falsified: the map rebuilds
  the system per grid point, and `optimize_agsi_weights` calls `SwitchableIbr6.reset()`, which
  restores every field the driver mutates.
- *"The limiter (`ilim_mode`) perturbs the equilibrium"* — falsified separately: SSSA
  `max Re` is identical (`+0.000000`) for `clamp`, `vi`, and no limiter.

## Fix

- `scripts/reporting/ieee14_switching_map.m`
  - `run_point` now takes the recovery-window start time and returns both the all-time and the
    **post-clear** minimum voltage. Verdict order: `diverged` → `~newton_all_converged`
    (own class) → post-clear `min|V| < 0.25` → `>=1` switch → ride-through. A throw is its own
    `error` class, not "divergence".
  - Four outcome classes (added grey `non-converged` / fail-closed), figure annotates the
    post-clear voltage, table publishes both voltages, header documents the rule.
  - Only the two documented driver warning IDs are silenced (not `warning('off','all')`).
  - Load-step points (permanent, never cleared) use `step_on + 0.5 s` as the recovery window.
- `+ibr/padiyar_switch_demo.m`: new `plot` option (default `true`); when false no figure is created
  and no PNG is written (`fig_paths = {}`). Runners `run_ieee14_switch_case` /
  `run_padiyar_switch_case` forward `plot = plot_results`.
- `+ibr/padiyar_switch_tds.m`: a **scheduled** fault/load-step on a bus that is not in
  `sys.bus_ids` now raises `ibr:padiyar_switch_tds:faultBus` / `:stepBus`; a scheduled step on a
  bus with zero load admittance warns (`:stepBusNoLoad`). Disabled events (`Inf` time) may keep an
  inapplicable default bus.

## Verification

- Targeted suites (full repository regression intentionally omitted per the risk policy in
  `AGENTS.md`; the maintainer runs the full suite): `test_ieee14_switch`, `test_padiyar_switch`,
  `test_ibr_switchable6`, `test_wizard_pure_layer`, `test_wizard_dispatch` →
  **69 passed / 0 failed / 0 incomplete**.
- New defect guards in `tests/test_ieee14_switch.m`:
  `test_severe_cleared_fault_recovers_post_clear` (during-fault `min|V| < 0.25` **and** post-clear
  `min|V| > 0.90` on the same run), `test_scheduled_event_bus_fails_closed` (both error IDs plus a
  disabled-event control), `test_plot_false_writes_no_figure` (no PNG on disk, no figure handle).
- Corrected map (regenerated): **ride-through 2, index-switch 22, diverge 0, non-converged 0**
  (previously reported 2 / 16 / 6). All 24 points converge; post-clear `min|V| = 0.98`–`1.01` pu.
  The reports' map section, figure caption, physics paragraph, and conclusion were corrected in
  both languages.

## Limitations

- The `0.25` pu post-clear floor remains an `ASSUMED_DIAGNOSTIC` study threshold, frozen before
  the rerun; it was not tuned to obtain any particular tally.
- The map is a diagnostic study product, not a production protection or acceptance gate.
- The reduced-6 devices still have no explicit LVRT block; ride-through is the outcome of the
  current-limited reduced model, and severity beyond the swept grid is not characterised.

## Related files and records

- `scripts/reporting/ieee14_switching_map.m`, `+ibr/padiyar_switch_tds.m`,
  `+ibr/padiyar_switch_demo.m`, `+ibr/run_ieee14_switch_case.m`,
  `+ibr/run_padiyar_switch_case.m`, `tests/test_ieee14_switch.m`,
  `docs/source/report_ieee14_switch_{en,th}.tex`,
  `docs/source/figures/switch_ieee14/{switching_map.png,table_switching_map.tex}`.
- Presentation rules added to `AGENTS.md` in the same delivery (figure lettering must match the
  report font/size at 1:1 scale; powers of ten as `$a\times10^{n}$`; subscript symbols instead of
  raw code identifiers).
