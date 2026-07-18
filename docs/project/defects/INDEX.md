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

New records use `YYYY-MM-DD-short-slug.md` and contain: status, observed
symptom, deterministic reproduction, affected tree/environment, evidence-backed
root cause, falsified hypotheses, correction, verification, and limitations.
