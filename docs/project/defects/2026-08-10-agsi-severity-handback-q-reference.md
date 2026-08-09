# SWITCH-2026-08-10-01 — two-term AGSI handback and healthy-PQ reference consistency

- **Status:** RESOLVED
- **Area:** reduced-6 AGSI preset, composite SG-reclose handback, EECON49 resource dispatch, EN/TH report
- **Environment:** Windows 11, MATLAB, branch `main`

## Symptom

The report described an equal seven-term AGSI++ and a coordinated SG-reclose handback, while the requested contract is the bounded two-term severity

\[
S_i=\operatorname{sat}_{[0,1]}\left(0.5J_{V,i}+0.5J_f\right)
\]

with per-device down-line dwell and a mode change committed only by the physical transfer plus right-limit KCL transaction. The first diagnostic 200-s run demonstrated the two-phase transaction mechanics, but after release its GFL endpoint moved away from the healthy voltage profile.

Two validation traps were found at the same time: `SwitchableIbr6.V_ref_per_bus` flattened an intended Nx2 map, and `run_hybrid_case` forwarded the healthy-PF option only when both fields were already present, silently routing an incomplete pair to the legacy selector.

## Reproduction and observations

1. Reduced-6 `agsi_pp` used seven equal weights by default despite the approved two-term definition.
2. In the first composite 200-s run, SG reclosed with all IBRs still GFM and a later severity-authorised transaction changed them to GFL, proving the two phases were separated.
3. The same run showed GFM reactive outputs near the healthy PF values before release, but GFL converged toward `Q_ref=0`; buses 6 and 8 ended with severity above `Gamma_off`.
4. Source tracing found nonzero case-defined PQ dispatch at IBR buses 2, 3, 6, and 8, while `build_mixed_resource_devices` forced every IBR `Q_ref_pu=0`.
5. A targeted validation test expected an exception from `ts_simulate_ibr_hybrid`, but the public API intentionally returns a structured fail-closed result. Initialization also collapsed the governing validation identifier to generic `badInput`.

## Root cause

- The report conflated the historical seven-term diagnostic wording, the reduced-6 local supervisor, and the composite event transaction.
- The composite resource schema transported active dispatch but had no additive case-owned reactive setpoint, so its healthy-PF voltage reference and its eventual GFL target described different operating points.
- The per-bus voltage-reference map lost its row structure.
- The public option-forwarding layer swallowed incomplete-pair evidence.
- Initialization failure handling preserved the message but hid the original structured identifier.

## Falsified hypotheses

- **Adding weighted `J_P`/`J_Q` would repair release:** falsified. The mismatch was a wrong target setpoint, not missing severity information. A weighted sum could also let good P compensate bad Q or good V/f mask dispatch inconsistency.
- **GFL implies a PV bus:** falsified by the case and runtime contracts. GFL/GFM is dynamic controller mode; REF/PV/PQ is power-flow variable ownership. These GFL devices are PQ resources with specified `P_ref,Q_ref`.
- **The transfer reset map alone restores the long-term Q target:** falsified. It preserves terminal V/I at the event, but the active GFL branch subsequently tracks its input `Q_ref`.
- **Duplicate healthy-profile IDs should throw from the public TS API:** falsified by the established structured fail-closed API.

## Correction

- Set the `agsi_pp` preset to `[0.5 0.5 0 0 0 0 0]`; former terms remain zero-weight diagnostics.
- Validate and preserve `V_ref_per_bus` as an Nx2 bus-ID/value map.
- Forward `healthy_pf_V` and `healthy_pf_bus_ids` independently so the TS initializer owns atomic-pair validation.
- Implement Phase 1 as SG reclose/reference return with IBR modes unchanged; implement Phase 2 as per-device two-term severity dwell followed by device transfer and right-limit KCL acceptance. Reset remaining timers after a partial release.
- Add case-owned `ratings.default_Q_MVAr` for the EECON49 PQ resources and consume it generically in `build_mixed_resource_devices`; profiles without this additive field retain historical `Q_ref=0`.
- Preserve the governing initializer validation identifier in structured fail-closed results.
- Remove coordinated-handback and seven-term-current-engine claims from EN/TH reports and flowcharts.

No P/Q tracking tolerance was invented. If an authoritative source later supplies tracking bands, `|P-P^*|` and `|Q-Q^*|` belong to separate non-compensatory readiness gates, not new AGSI weights.

## Verification

- Reduced-6 route: GFL→GFM at 2.035 s (`S≈0.6508`) and GFM→GFL at 4.228 s (`S≈0.3465`); final modes GFL/GFL.
- Targeted builder/handback suites: 26/26 PASS, 0 failed, 0 incomplete.
- Independent EECON49 composite-equilibrium oracle after Q correction:
  - converged; residual and physical all-row KCL norm `2.0211610163301e-13`;
  - all four IBR `P,Q` outputs equal their case-defined `P_ref,Q_ref`;
  - IBR-bus equilibrium voltage differs from the healthy PF by at most `1.197e-13` pu;
  - all four transient-current and aggregate device-limit checks pass.
- Fresh `dt=0.1 s`, 200-s composite evidence reaches the declared endpoint. The synchronism guard accepts the SG at 145.400 s with every IBR still GFM; the separate per-device two-term severity dwell authorises the GFM-to-GFL transaction at 146.400 s. The accepted right-limit KCL norms are `7.102e-10` at reclose and `3.022e-13` at severity release. At 200 s all four IBRs are GFL, maximum endpoint severity is `1.048e-5`, `f_COI=60.000008 Hz`, the all-bus voltage range is `0.966733--1.057534 pu`, and the maximum accepted-step residual is `9.685e-9`. The event log, raw figures, and EN/TH reports preserve the reclose and release as distinct transactions; no SG-reclose hard-code commands an IBR mode.
- Stored evidence: `output/diagnostics/engine_release_result.log` and the local ignored cache `output/diagnostics/engine_release_result.mat` (SHA-256 `C1C1D81EAB4E3E32222A0DB95E70F287F335C3115604CB1B6672F6C0F1517D77`). The log records `severity_eligible=146.0000 s` and the separately committed `actual_mode_release=146.4000 s` for every IBR.
- Fresh checkpoint targeted gate on MATLAB R2026a: 44/44 passed, 0 failed, 0 incomplete across `test_ibr_switchable6`, `test_ieee14_eecon49_full_state`, `test_ieee14_ibr_sg_reclose_workflow`, and `test_padiyar_switch`.

## Limitations

- Bus 6 has scheduled `Q=0.247569 pu` versus a registered source-data `Qmax=0.24 pu`. It is a PQ resource, not a PV voltage controller, so the PV→PQ Q-limit mechanism does not constrain it. The report discloses this; no case value was tuned.
- The synchronizer/phase planner and governor mapping remain diagnostic rather than hardware-validated control.
- The full repository regression is optional under project policy; final delivery records the targeted gates actually run.

## Related files

- `+ibr/SwitchableIbr6.m`
- `+cases/scenario_ieee14_1sg_4ibr.m`
- `+stability/build_mixed_resource_devices.m`
- `+stability/run_hybrid_case.m`
- `+stability/ts_simulate_ibr_hybrid.m`
- `tests/test_ibr_switchable6.m`
- `tests/test_ieee14_eecon49_full_state.m`
- `tests/test_ieee14_ibr_sg_reclose_workflow.m`
- `scripts/reporting/generate_ieee14_switch_report_figures.m`
- `docs/source/report_ieee14_switch_en.tex`
- `docs/source/report_ieee14_switch_th.tex`
