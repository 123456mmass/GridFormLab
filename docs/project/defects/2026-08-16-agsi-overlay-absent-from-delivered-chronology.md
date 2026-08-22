# AGSI-2026-08-16-01 — the delivered chronology carries no reference-AGSI overlay

Status: **RESOLVED** (2026-08-16)

Branch: `main`. Tested tree: on top of `416e47a` (== `origin/main` at the time).
Environment: MATLAB R2026a, Windows 11.

## Symptom

The switching-decision figure the project owner asked for plots the composite
severity `S` together with every AGSI sub-index (`J_V`, `J_f`, `J_R`, `J_P`,
`J_lock`, `J_SCR`). None of them is present in the delivered flagship result
`output/diagnostics/ieee14_eecon49_chronology.mat`, so the page could not be
produced from the artifact that the README and the handoff cite.

## Reproduction

```matlab
S = load('output/diagnostics/ieee14_eecon49_chronology.mat','r');
isfield(S.r,'agsi_reference')     % -> 0
```

A byte probe of the v7.3 (HDF5) container is the same evidence without loading
133 MB: the link name `coi_frequency_Hz` occurs twice, `x_traj` twice, and
`agsi_reference` **zero** times.

## Root cause, with evidence

The overlay is opt-in and defaults OFF, and the flagship driver never opts in.

- `+stability/ts_simulate_ibr_hybrid.m:1473`
  `s.agsi_reference_enabled = logical(option(opt,'agsi_reference',false));`
  The in-file comment at `:1472` states the intent: *"Default false, so an
  omitted option leaves the result schema and the runtime byte-identical."*
- `:1339` gates the whole call on that flag:
  `if settings.agsi_reference_enabled` → `res.agsi_reference = stability.agsi_reference_terms(...)`.
- `scripts/examples/run_ieee14_eecon49_chronology.m:73-85` builds the complete
  option struct and never sets `agsi_reference`.

The option name is `agsi_reference`; the settings field it lands in is
`agsi_reference_enabled`. Forwarding is in place and was never the problem
(`+stability/run_hybrid_case.m:226` forwards the option, `:534` passes the
result field through), so the only missing piece was the caller.

### Why post-processing cannot recover it

`stability.agsi_reference_terms` needs the admittance matrix in force at each
sample to compute a topology-correct Thevenin impedance for `J_SCR`. That log is
also built only under the same flag:

- `ts_simulate_ibr_hybrid.m:80` seeds `Ylog` when the flag is on;
- `:703` appends `(t, topology, Y)` at every applied event.

The similarly named published field is **not** the same object:

- `:1240` `res.Y_log = samples.topology;`

`samples.topology` holds topology **labels**, not matrices. Without the real
`Ylog`, `agsi_reference_terms` returns `status='OK_NO_SCR_TOPOLOGY_LOG'` and
`J_SCR` is all-NaN. Rebuilding the per-topology `Y` inside a reporting script
would mean re-implementing the fault / line-trip / restore admittance logic
outside the engine — a correctness risk and a duplication of production logic in
the presentation layer.

## Fix

No production change. The option is enabled by the new comparison runner rather
than by the published driver, so the delivered artifact remains exactly
reproducible from the file the README cites:

- `scripts/reporting/run_ieee14_gfm_lock_comparison.m` — `base_request` copies
  the flagship option set verbatim and adds `'agsi_reference',true`. It writes to
  `output/diagnostics/ieee14_gfm_lock_compare/`, never over the delivered
  artifact.
- `scripts/reporting/ieee14_switch_decision_signals.m` — refuses with
  `ieee14_switch_decision_signals:overlayAbsent` when a result carries no
  overlay, and with `:overlayNotOk` for any status other than `OK` (including
  `OK_NO_SCR_TOPOLOGY_LOG`, which would render a blank `J_SCR` panel).
- `tests/test_ieee14_decision_signals.m` — pins both refusals, so the trap
  cannot return silently.

## Verification

The re-run was gated on being bit-identical to the delivered artifact, not on the
existing byte-inertness test alone:

```text
t isequal           1   (4994 vs 4994 samples)
max|dx|             0.000e+00
max|dy|             0.000e+00
max|du|             0.000e+00
sample_side isequal 1
modes isequal       1
online isequal      1
n_events            15 vs 15   event types isequal 1   event max|dt| 0.000e+00
reclose             159.343560 vs 159.343560
t_end               250.000000 vs 250.000000
overlay status      OK
COI residual        0.000e+00   (tol 1e-9, 4994 samples compared)
```

`J_SCR` is finite at all 4994 samples for all four devices, so the topology log
was built correctly.

## Hypotheses that measurement disproved

- **"`res.Y_log` can rebuild `J_SCR`."** False. `:1240` assigns
  `samples.topology`, which is a label record. The field name invites the error.
- **"`support_supervision_status` gives the supervisor state for the figure."**
  False. `ts_simulate_ibr_hybrid.m:1288` does assign it, but
  `run_hybrid_case.m:517-527` copies `ts_res` → `result` through an explicit
  whitelist that omits it, and the `adaptive_fields` list at `:532-535` omits it
  too. A byte probe finds zero occurrences in either stored artifact. The
  surviving equivalent is per-transaction data in `r.event_log`.
- **"`severity_gamma_on/off` can be read back from the result."** False. They are
  top-level run options and are not republished in `result.metadata`
  (`metadata.ibr_events` carries only the event struct). The decision bundle
  therefore takes them from the caller, defaulting to the frozen contract
  0.65/0.35, and records the source.
- **"`J_f` and `J_R` are per-device quantities."** False.
  `agsi_reference_terms.m:190` and `:193` have no dependence on the device index
  `q`; the four columns are identical except for the offline NaN mask at `:177`.
  Plotting four coincident traces would suggest four independent measurements.

## Limitations

The overlay remains `ASSUMED_DIAGNOSTIC` (`agsi_reference_terms.m:11-16`) and
publishes `aggregate_index='NOT_FORMED_BY_DESIGN'`. Only `S`, `J_V` and `J_f`
enter the supervisor's decision; the decision figure states that split on the
page itself. Nothing derived from `J_R`, `J_P`, `J_lock` or `J_SCR` may support a
readiness claim.

## Related files

`+stability/ts_simulate_ibr_hybrid.m` (`:80`, `:703`, `:1240`, `:1288`, `:1339`,
`:1473`) · `+stability/agsi_reference_terms.m` · `+stability/run_hybrid_case.m`
(`:226`, `:517-535`) · `scripts/examples/run_ieee14_eecon49_chronology.m:73-85` ·
`scripts/reporting/run_ieee14_gfm_lock_comparison.m` ·
`scripts/reporting/ieee14_switch_decision_signals.m` ·
`tests/test_ts_hybrid_agsi_reference.m` · `tests/test_ieee14_decision_signals.m`
