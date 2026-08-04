# SWITCH-2026-08-04-03 — subdivision residual provenance

- **Status:** RESOLVED
- **Area:** hybrid TS numerical diagnostics
- **Environment:** Windows, MATLAB R2026a, branch `main`, 2026-08-04 switching tree

## Symptom and reproduction

The 160-s `dt=0.05 s` refinement converged after one internal subdivision,
but `residual_per_step` reported approximately `1.43e-3` near the fault
recovery. The accepted child steps converged; the large value came from a
rejected parent attempt.

## Root cause and evidence

`advance_with_subdivision` intentionally set the returned diagnostic residual
to `max(parent,left,right)`. This preserves evidence of the rejected attempt,
but the result schema did not separately publish the accepted-leaf maximum.
Consequently a report could incorrectly label the rejected-parent residual as
an accepted-step residual. A second producer/consumer gap was found during the
first 160-s refinement: `ts_simulate_ibr_hybrid` published the new field, but
`run_hybrid_case` did not copy it to the public result. Solver decisions and
states were not affected by either diagnostic-schema gap.

## Correction and independent oracle

Retry statistics now carry `accepted_residual_norm`, recursively equal to the
maximum residual of accepted leaves only. The result retains
`residual_per_step` for rejected-attempt provenance and adds
`accepted_residual_per_step`; `run_hybrid_case` now preserves the field. Report
gates use the latter and separately retain the maximum attempted residual. The
direct hybrid-runner test checks accepted-versus-attempt-inclusive ordering,
and a run-hybrid consumer test checks the public schema on a failure path. The
final subdivided 160-s run is the independent numerical oracle for the accepted
leaf maximum.

## Limitations

This is a diagnostic-schema correction, not a tolerance change. Subdivision
depth, accepted states, event times, equations, and Newton acceptance remain
unchanged.
