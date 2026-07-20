# IBR Full result omits `internal_substeps`

Status: OPEN

## Observation

`test_wizard_ibr_subanalysis/test_full_fault_profile_b_completes_with_lvrt`
errors after a numerically completed IEEE14 Full Analysis because
`r.ts.internal_substeps` does not exist. The test then cannot compare it with
`r.ts.accepted_steps`.

## Reproduction and affected tree

MATLAB R2025a, Windows, baseline commit `83390db`:

```matlab
pf_init_paths;
r = runtests('tests/test_wizard_ibr_subanalysis.m', ...
  'Name','test_wizard_ibr_subanalysis/test_full_fault_profile_b_completes_with_lvrt');
```

Result: 0 passed, 1 failed/errored/incomplete with
`MATLAB:nonExistentField`. The same failure was reproduced in a detached clean
worktree at `83390db`, proving it is not caused by the later SMIB launcher
changes.

## Evidence and current inference

The Full Analysis run itself reaches `STATUS: COMPLETE`; the error occurs only
when the test dereferences the missing result field. No source/runtime producer
for `internal_substeps` was changed during the SMIB work. The evidence proves a
result-schema/test expectation mismatch, but does not yet prove whether the
correct repair belongs in the TS result producer, Full Analysis assembler, or
the test contract.

## Falsified hypotheses

- The new SMIB case list changed IEEE14 numerical execution: falsified by the
  identical failure at the clean baseline commit.
- The SMIB dispatcher branch consumed the IEEE14 request: falsified by the log,
  which shows the normal IEEE14 scenario and completed Full Analysis.

## Correction and verification

No correction made; this is outside the requested SMIB launcher scope. Before
repair, trace the intended `internal_substeps` producer and public result-schema
contract. Do not simply weaken the assertion or fabricate the counter.

## Limitations

This defect prevents a full green targeted launcher suite but does not invalidate
the independently passing SMIB discovery, PF/equilibrium, SSSA, and TDS gates.
