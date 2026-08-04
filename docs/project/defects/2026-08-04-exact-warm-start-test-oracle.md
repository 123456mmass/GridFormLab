# SWITCH-2026-08-04-02 — exact warm-start equality was not a valid solve oracle

- **Status:** RESOLVED_TEST_CONTRACT
- **Area:** mixed SG/IBR equilibrium test
- **Environment:** Windows, MATLAB R2026a, branch `main`, uncommitted 2026-08-04 switching tree

## Symptom and reproduction

`runtests('tests/test_ieee14_sg_reference_equilibrium.m')` failed two
`verifyNotEqual` assertions because the PF-port EMF6 initializer supplied
`Tm=2.017080580527539` and `Efd=1.188815797202659`, exactly equal to the
accepted mixed-equilibrium values.

## Root cause and falsified hypothesis

The test treated a numerical change from the warm start as proof that `Tm`
and `Efd` were Newton unknowns.  That implication is false: an exact warm
start is allowed to remain unchanged.  The Newton partition still contains
both SG inputs, all physical KCL rows remain present, and the accepted full
residual is below tolerance.  No production equation or tolerance was wrong.

## Correction and independent oracle

The equality prohibition was replaced by three direct checks: both solved
values occupy the accepted `u_eq` slots, the partition contains two slack
input unknowns, and independently perturbing either accepted input by
`1e-3 pu` makes the active differential residual exceed `1e-5`.  Thus the
test now checks mathematical sensitivity rather than solver iteration count
or initializer distance.

## Verification and limitations

The corrected isolated test and the surrounding targeted SG/IBR suites must
pass before delivery.  This change does not alter equations, bases, solver
tolerances, or acceptance gates.
