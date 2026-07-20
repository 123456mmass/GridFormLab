# Defect index

Search this file first, then open only matching defect records. Do not load the
whole directory into agent context.

| ID | Status | Area | Symptom | Record |
|---|---|---|---|---|
| IBR-2026-07-16-01 | RESOLVED | IEEE14 IBR hybrid TS validation | Scenario-B routing, per-island validation, transaction identity, and comparison evidence are incomplete | [Corrective validation defects](2026-07-16-ieee14-ibr-corrective-validation.md) |
| IBR-2026-07-17-01 | OPEN | Generic automatic GFM selection | Revision 5 corrective closure: event-runner migration, validator latent bugs, real timers, authenticated SG_ON routing, N_exhaustive_max guard, unpinned automatic integration. Targeted 86/86 GREEN; full regression pending | [Fixed GFM selection defects](2026-07-17-fixed-gfm-selection.md) |
| IBR-2026-07-18-01 | RESOLVED | IBR Section H reporting + stability modal analysis | struct() constructor collapsed cell-of-structs to a 1x1 struct; parentheses-on-cell indexing in modal_analysis mis-read participation status | [Cell-array collapse and indexing](2026-07-18-cell-array-collapse-and-indexing.md) |
| UI-2026-07-19-01 | RESOLVED | Analysis Wizard | Analysis could be highlighted but footer was missing; initial case was not committed; TS/IBR Events page was skipped | [Wizard footer, selection, and navigation](2026-07-19-wizard-footer-selection-navigation.md) |
| UI-2026-07-19-02 | RESOLVED_TEST_CONTRACT | IBR launcher defaults | Tests encoded the retired implicit four-WECC launcher default and required an out-of-scope RMS10 fault to converge | [IBR launcher default-profile test contract](2026-07-19-ibr-launcher-default-profile-test-contract.md) |
| IBR-2026-07-19-02 | RESOLVED | RMS10 reduced equilibrium initialization | Registered `ibr_dual_mode_rms10` devices were rejected by a legacy-only device-identity gate although they implement the required equilibrium ABI | [RMS10 reduced initializer device type](2026-07-19-rms10-reduced-initializer-device-type.md) |
| IBR-2026-07-19-03 | RESOLVED_PENDING_FINAL_REGRESSION | GFL-RMS10 balanced-fault TS | Runtime `V_valid_min` gate blocked the sourced FRT domain; fault-on rolled back near 0.377 pu | [RMS10 runtime low-voltage domain](2026-07-19-rms10-runtime-low-voltage-domain.md) |
| IBR-2026-07-19-04 | RESOLVED | SG-on all-GFL equilibrium/SSSA/TS | Mode-aware PF used constant-power loads while the composite DAE used frozen constant-admittance loads, leaving a 0.164 pu KCL component | [SG-on all-GFL equilibrium](2026-07-19-sg-on-all-gfl-equilibrium.md) |
| IBR-2026-07-19-05 | DOMAIN_THROW_RESOLVED / END_TO_END_GATE_BLOCKED | Domain-preserving Newton globalization (GFL-RMS10 TS trial) | Profile-B Zf=0.1i died at t=3.25s before sg_trip; classified RMS10 trial-iterate lowVoltagePowerInversion throw aborted the whole Newton solve instead of rejecting the trial. Fix verified by targeted tests; dt=0.005 passes and reaches reclose; dt=0.01 still fails with domain_rejected_trials=0 (separate non-domain stall, tracked as IBR-2026-07-20-01) | [Domain-preserving Newton globalization](2026-07-19-domain-preserving-newton-globalization.md) |
| IBR-2026-07-20-01 | OPEN | dt=0.01 Newton/Jacobian stall at t=3.25s | After the domain-preserving fix, dt=0.01 still fails at t=3.25s with domain_rejected_trials=0 and subdivision_depth=4; non-smooth residual trajectory and near-singular rcond indicate a non-domain Newton/Jacobian failure (limiter discontinuity or conditioning), not a trial-voltage violation | [dt=0.01 Newton stall](2026-07-20-dt01-newton-stall-t325.md) |
| UI-2026-07-20-01 | OPEN | IBR Full result schema | Completed IEEE14 Full Analysis result lacks `r.ts.internal_substeps`, so its targeted test errors; reproduced identically at clean baseline `83390db` | [IBR Full internal-substeps schema](2026-07-20-ibr-full-internal-substeps-schema.md) |

New records use `YYYY-MM-DD-short-slug.md` and contain: status, observed
symptom, deterministic reproduction, affected tree/environment, evidence-backed
root cause, falsified hypotheses, correction, verification, and limitations.
