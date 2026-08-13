# Adaptive hybrid options silently dropped by column-cell loop orientation

Date: 2026-08-13  
Status: RESOLVED  
Defect ID: `ADAPT-2026-08-13-02`

## Symptom

A diagnostic called `stability.run_hybrid_case` with
`stepper='adaptive'` and `reject_limit=12`, but the hybrid driver failed with

```text
Adaptive step exceeded reject_limit=10
```

The MATLAB process itself exited normally because the public TS contract is a
structured fail-closed result; the mismatch was visible only in
`result.failure_reason` and `rejection_history`.

## Reproduction

`chk_fault_adaptive_attribution_tmp.m` contains paired authenticated all-four
arms with `reject_limit=10` and `reject_limit=12`. Before the correction, both
arms stopped after exactly 10 rejections at the same state even though the
harness printed the two different requested values. Evidence is retained in:

- `output/diagnostics/fault_adaptive_attribution_rejectlease_run.log`

The decisive regression uses a deliberately invalid non-`stepper` adaptive
option:

```matlab
opt.stepper = 'adaptive';
opt.reject_limit = 0;
r = stability.run_hybrid_case(scenario,opt);
```

The hybrid driver's existing validator must return
`ts_simulate_ibr_hybrid:badAdaptiveOptions`. If `reject_limit` is silently
lost, the run instead proceeds with the default value 10.

## Root cause

The adaptive option forwarding loop in `+stability/run_hybrid_case.m` was:

```matlab
for afield = {'stepper','dt_min', ... ,'rannacher_n'}.'
```

MATLAB `for variable = A` iterates over the **columns** of `A`. The transpose
turned the row cell array into an `N x 1` column, so the loop executed once and
`afield` held the complete column cell array. The body always read
`afield{1}`, therefore only `stepper` reached
`stability.ts_simulate_ibr_hybrid`; `dt_min`, `dt_max`, tolerances, controller
factors, `reject_limit`, and Rannacher options were silently dropped.

This was an option-plumbing defect, not a device equation, tolerance, or
acceptance-gate defect.

## Correction

Remove the transpose so the cell array remains `1 x N` and the loop visits one
option name per column:

```matlab
for afield = {'stepper','dt_min', ... ,'rannacher_n'}
```

No default, numerical value, equation, event, limiter, threshold, or
fail-closed gate changed.

## Verification

Fresh targeted run on the corrected working tree:

```text
ADAPTIVE_PLUMBING_RERUN total=11 pass=11 fail=0 inc=0
```

Coverage:

- `tests/test_ts_hybrid_fixed_bitident.m` — 4/4, including the new invalid
  `reject_limit=0` forwarding oracle and fixed-path bit identity;
- `tests/test_ts_hybrid_adaptive_lte.m` — 3/3 analytic LTE/order oracle;
- `tests/test_ts_hybrid_adaptive_rollback.m` — 4/4 rollback,
  determinism, exact event landing, and accepted-grid diagnostics.

End-to-end attribution after the correction proves the requested value now
reaches the driver:

- all-four with `reject_limit=10` stops at the expected rejection lease;
- the otherwise identical diagnostic with `reject_limit=12` crosses that
  point, commits `load_step`, `fault_on`, `fault_clear`, and `line_trip`, then
  fails separately at the post-line nonsmooth DAE/Newton wall.

Evidence:

- `output/diagnostics/adaptive_plumbing_targeted_rerun.log`
- `output/diagnostics/fault_adaptive_attribution_plumbing_fixed_run.log`

## Corrected evidence boundary

Results produced before this correction prove only behavior under the hybrid
driver's defaults, except for `stepper` itself. They do **not** prove that a
caller-specified `dt_max`, `reject_limit`, tolerance, controller factor, or
Rannacher option was honored. In particular, exact sample/rejection counts and
performance claims in `ADAPT-2026-08-12-01` that depended on such overrides
must be revalidated or explicitly marked stale; they are not silently carried
forward as current-tree evidence.

The corrected option forwarding does not resolve the Dv=20 chronology blocker.
That blocker is tracked separately and remains fail-closed.

## Falsified hypotheses

1. The harness forgot to set `reject_limit=12` — falsified by direct source and
   its printed requested value.
2. The hybrid validator ignored `reject_limit` — falsified by direct invocation
   and the new `reject_limit=0` oracle after forwarding.
3. MATLAB reused a stale function — falsified by the deterministic pre/post
   behavior and fresh 11/11 test process.

## Independent review note

A read-only review confirmed the loop semantics, the producer→consumer path, and
that the regression test is an identifier-based oracle that deterministically
fails on the old code and passes on the new. Two coverage observations were
recorded rather than expanded, because the fix itself is minimal and proven:

1. the regression asserts that one specific non-first field (`reject_limit`, the
   12th name) now reaches the driver; a truncated or reordered list that still
   contained `reject_limit` would not be caught. A parameterized invalid-value
   sweep over all forwarded names would be the complete instrument.
2. no test asserts byte-identity of a fixed run that also carries an adaptive
   field (e.g. `opt.atol_x` set while `stepper` is absent); the risk is
   negligible because the fixed path reads none of these fields, but it is the
   one untested cell.

The review also independently corroborated the stale-evidence boundary in the
section above: `scripts/validation/hybrid_adaptive_compare_fixed.m` recorded its
G-COI / decision-parity PASS at the driver defaults (`dt_max=1.0`,
`reject_limit=10`), not at its declared `dt_max=0.5`, `reject_limit=12`. That
validation-script claim must be rerun on the corrected tree before it is cited.

## Related files

- `+stability/run_hybrid_case.m`
- `+stability/ts_simulate_ibr_hybrid.m`
- `tests/test_ts_hybrid_fixed_bitident.m`
- `tests/test_ts_hybrid_adaptive_lte.m`
- `tests/test_ts_hybrid_adaptive_rollback.m`
- `chk_fault_adaptive_attribution_tmp.m`
- `2026-08-12-adaptive-hybrid-discontinuity-restart.md`
