# SWITCH-2026-08-04-05 — mixed-resource EMF6 initialization contract

- **Status:** RESOLVED
- **Area:** mixed SG/IBR equilibrium and operational EMF6 singular limit
- **Environment:** Windows, MATLAB R2026a, branch `main`, 2026-08-04 switching tree

## Symptoms

1. `sg_composite_device` called the SG-only network SSSA initializer when no
   prebuilt EMF6 data were supplied. In a mixed-resource case that initializer
   omitted the four independently modelled IBR injections, so its network
   equilibrium was not the mixed system being initialized.
2. A caller-supplied value that violated a declared frozen-state contract could
   be replaced by the later mode-aware warm start before the consistency gate,
   hiding the bad input.
3. The operational `T'_{q0}=0` contract required exact `E'_d=0`, while the SSSA
   initializer/RHS still evaluated the ordinary quotient route.
4. A nonfinite equilibrium norm was not explicitly rejected because a NaN does
   not satisfy an ordinary greater-than comparison.

## Root causes and evidence

The SG-only initializer assembles KCL for synchronous machines and loads only;
it is not a valid oracle for a mixed SG/IBR port. The frozen-state check was
ordered after a state-replacing initializer. The zero-time-constant singular
limit was represented in metadata but not implemented exactly in every shared
EMF6 consumer. These are runtime-contract defects, not parameter-fitting issues.

## Corrections

- Build identical EMF6 coefficients locally and initialize the SG from the
  in-house PF terminal port; the subsequent mixed all-KCL Newton solve remains
  the acceptance gate.
- Reject inconsistent caller-supplied frozen states before any warm-start can
  replace them.
- For exact `T'_{q0}=0`, initialize `E'_d=0` and set its derivative to zero
  without epsilon substitution or division.
- Reject nonfinite equilibrium residual norms explicitly.

## Verification and limitations

The proportional gates are `test_ieee14_eecon49_full_state` and
`test_ieee14_sg_reference_equilibrium`, plus the existing EMF6/mixed-equilibrium
consumers. The local PF-port initialization is only an initial guess; it cannot
declare mixed equilibrium success. Full physical acceptance remains the
subsequent mixed KCL/differential residual solve and frozen-state gate.

## Related files

- `+stability/sg_composite_device.m`
- `+stability/mixed_equilibrium_solve.m`
- `+stability/synchronous_emf6_ssa.m`
- `tests/test_ieee14_eecon49_full_state.m`
- `tests/test_ieee14_sg_reference_equilibrium.m`
