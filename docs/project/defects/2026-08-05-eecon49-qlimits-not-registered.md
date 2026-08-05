# eecon49 Q-limit enforcement had no backing data

- **ID:** PF-2026-08-05-01
- **Status:** RESOLVED
- **Area:** case schema `+cases/case_matpower6_case14.m`, Q-limit enforcement
  `+pfsolver/powerflow_newton_raphson.m`, switching builders
  `+ibr/build_ieee14_switch_system.m` and `+stability/build_mixed_resource_devices.m`
- **Branch / commit at discovery:** `main` @ `126ae57` (uncommitted Phase D/F work)
- **Environment:** Windows 11 Pro 10.0.26200, MATLAB R2026a, `D:\Project\Power-flow`

## Symptom

`e-powerflow_newton_raphson` was asked (Q-limit demand) to enforce reactive
limits, but flipping `enforce_q_limits=false -> true` changed nothing on the
eecon49 operating point. Investigation showed why: the case converter emitted a
10-column `bus_data` and let `standardize_case` pad columns 11/12 with
$\pm\infty$, so the PV-to-PQ Q-limit switch had no finite $Q_{\min}/Q_{\max}$ to
act on.

## Reproduction

1. Build the eecon49 case and inspect `bus_data(:,11:12)` before the fix:
   every bus showed `Qmin=-Inf, Qmax=Inf`.
2. Run the in-house PF with `enforce_q_limits=true`: `q_limit_switching.rounds == 0`
   regardless of the solved Q values.

## Root cause with evidence

`convert_mpc_to_project_case` (`+cases/case_matpower6_case14.m:93`) built
`bus_data` from `mpc.bus` (10 columns) and never transferred the generator
reactive limits `mpc.gen(:,4:5)` (MVAr) into project columns 11/12:
```matlab
case_data.bus_data = [bus(:,1), proj_type, V0, A0, Pgen, Qgen, ... ];
```
`standardize_case` then padded the missing `Qmin_pu/Qmax_pu` columns with
$\pm\infty$ (`+cases/standardize_case.m` 10-column branch). Hence Q-limit
enforcement was silently a no-op even where the source data carried limits.

Additionally, the two switching builders passed `enforce_q_limits=false`; the
solver default is `true` (`+pfsolver/powerflow_newton_raphson.m:29`), so even
the backing-data fix would not have acted until the flags were flipped.

## Fix

- `+cases/case_matpower6_case14.m`: emit a full 12-column `bus_data` and
  aggregate the per-bus generator limits per unit as
  $Q_{\mathrm{pu}} = Q_{\mathrm{MVAr}}/S_{\mathrm{base}}$,
  $S_{\mathrm{base}}=100$~MVA (`mpc.baseMVA`), with $+\infty/-\infty$
  retained on buses with no finite generator limit. Provenance is recorded in
  `case_data.bus_q_limits_classification` as SOURCE_DEFINED.
- `+ibr/build_ieee14_switch_system.m` and
  `+stability/build_mixed_resource_devices.m`: `enforce_q_limits` set to
  `true` (the solver default).

## Verification

- On eecon49, `q_limit_switching.rounds == 0` and the solution is unchanged
  because every inverter bus is a PQ resource and the SG is the slack, so no PV
  bus reaches a reactive limit (`nPV == 0`). The mechanism is exercised by the
  baseline IEEE14 case, which carries PV buses.
- `test_case_format_contract.m`, `test_matpower6_case14.m`,
  `test_ieee14_eecon49_full_state.m`, `test_composite_schema.m` all pass
  (19/19).
- Q-limit provenance with per-bus values written to the report
  (`docs/source/report_ieee14_switch_en.tex`, \eqref{eq:qlimits}).

## Limitations

P-limit enforcement is not implemented and is fail-closed by design: the PF
Newton solver keeps $P$ as a prescribed input (not a variable) and has no
equivalent of the PV-to-PQ switch that makes $Q$ a solved quantity. A P-limit
would have to act through the governor/scheduler outside the power-flow solve,
which is out of scope for Phase F.

## Related files

- `+cases/case_matpower6_case14.m`, `+cases/standardize_case.m`
- `+pfsolver/powerflow_newton_raphson.m`
- `+ibr/build_ieee14_switch_system.m`, `+stability/build_mixed_resource_devices.m`
- `docs/source/report_ieee14_switch_en.tex`