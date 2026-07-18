# RMS10 SG-off reduced-initializer device-type rejection

Date: 2026-07-19  
Status: RESOLVED

## Symptom

The SG trip operating-point comparison failed before Newton iteration with
`mixed_ibr_reduced_initialize:notPureIBRIsland`, even though every online
resource was a registered RMS10 dual-mode IBR and all four were in GFM mode.

## Root cause

`+stability/mixed_ibr_reduced_initialize.m` admitted only the historical
`ibr_dual_mode` device-type string. GFL-RMS10 construction correctly publishes
`ibr_dual_mode_rms10`; both families implement the same generic equilibrium
ABI, but the legacy-only identity check rejected the newer registered family.

## Correction and independent oracle

The initializer now has an explicit allowlist containing the two registered
dual-mode types. Unknown future types still fail closed. The independent
regression `tests/test_ibr_rms10_sg_off_equilibrium.m` constructs the production
RMS10 devices, opens SG1, commits all four IBRs as GFM, and requires a 52-state
all-KCL equilibrium with physical KCL below `1e-6`. A second test replaces one
device type with an invented value and requires the original fail-closed ID.

No ODE, parameter, state order, residual, Jacobian, tolerance, or limiter was
changed.
