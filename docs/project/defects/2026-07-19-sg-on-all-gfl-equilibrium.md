# SG-on all-GFL equilibrium used a load-inconsistent PF seed

Status: `RESOLVED`

## Symptom

On `main` at `4cbf413`, IEEE14 normal operation with SG1 online and all four
RMS10 IBRs in GFL mode failed closed before SSSA:

```text
wizard:dispatch_analysis:ibrEquilibrium
mixed_equilibrium_solve:noConverge
residual=1.563e-01 after 300 iterations
```

No eigenvalue or state table was published, which was the correct failure
behavior for a non-converged equilibrium. The same equilibrium failure stopped
the all-GFL TS launcher before integration.

Environment: Windows, MATLAB R2026a (`D:\MATLAB\R2026a`), branch `main`.

## Reproduction

Use `wizard.defaults_for_method('ibr','ieee14_1sg_4ibr')`, select
`ibr_analysis='sssa'`, set GFM/GFL counts to `0/4`, clear both initial GFM and
reference indices, disable events and plots, then call `solve_case`.

## Evidence and root cause

At the pre-fix mode-aware seed, residuals were:

- SG differential RHS infinity norm: `1.6191e-15`;
- GFL RHS infinity norms: `2.7903e-13`, `9.6265e-12`, `1.9253e-11`, `0`;
- physical KCL maximum component: `1.6421e-01 pu` at bus 3;
- physical KCL maximum complex-row magnitude: `1.7992e-01 pu`.

The KCL error occurred at load buses while non-load buses were at machine
precision. An independent load-model oracle reproduced the complete complex
KCL vector as

```text
Yload(Vbase) * Vmode - conj(Sload / Vmode)
```

with infinity-norm difference `3.3457e-09`; both observed and predicted
complex KCL norms were `0.179915204866462 pu`.

`composite_dae` freezes P and Q loads as constant admittances at the original
PF voltage. The in-progress all-GFL warm start instead ran a second
constant-power PF after changing GFL terminal buses from PV to PQ. Its device
states were stationary, but its network voltage did not satisfy the production
constant-admittance KCL. This load-representation mismatch, not an SG/GFL ODE,
parameter, limiter, sign, base, tolerance, or mode-assignment defect, caused
Newton to start from the wrong network equation.

Falsified hypotheses:

- SG stationary state/control initialization was wrong: the SG state matched
  an independent evaluation of the existing EMF6 stationary equations exactly
  (`0` infinity-norm difference; angle residual `2.7756e-17`).
- a GFL branch initializer was nonstationary: every GFL RHS was below
  `2e-11` before the correction.
- the equations admit no operating point: the equation-consistent probe gave
  differential RHS `9.6265e-12` and KCL `8.4308e-12`.

## Correction

`mixed_ibr_sg_on_gfl_initialize` now runs the unchanged base PF, converts each
unchanged load to the exact constant admittance frozen by `composite_dae`, and
then runs the existing in-house mode-aware PF with GFL buses as P/Q-controlled
PQ buses. Device-owned equilibrium initializers and the existing full coupled
Newton/all-KCL acceptance gates remain authoritative.

No ODE, state order, source/case parameter, current limit, base/sign convention,
acceptance tolerance, GFL/GFM assignment, dispatcher, or report source changed.

## Verification

- Corrected warm start: differential RHS `9.6265e-12`, physical KCL
  `8.4308e-12`.
- Coupled equilibrium: converged in one Newton iteration, residual
  `9.6265e-12`, physical KCL `8.4308e-12`.
- SSSA: complete `45 x 45` matrix and 45 finite roots published. The unchanged
  equations classify this all-GFL operating point as `UNSTABLE`; this result is
  reported, not tuned or hidden.
- Event-free 15 s TS: `1500/1500` steps accepted, 1500 Newton iterations.
- New targeted regression plus related RMS10/dispatcher/launcher gates:
  `45 passed / 0 failed / 0 incomplete`.
- Wizard UI smoke: `24 passed / 0 failed`.
- MATLAB Code Analyzer: zero issues in both changed MATLAB files.

The repository-wide suite was started after runtime stabilization and then
stopped at the user's explicit request that the full suite was unnecessary.
No full-suite PASS is claimed. A broader exploratory focused run had 83 passes
and four pre-existing contract-test failures in files outside this change; the
scoped delivery gate above excludes those unrelated stale assertions.

## Reporting follow-up

The R2026a report evidence was regenerated from the corrected production
route. It now includes 14 PF bus rows, 20 branch-flow/loss rows, the complete
45-root all-GFL SSSA spectrum, and manifest fields for the all-GFL equilibrium
and event-free TS. The 15-s event-free TS accepted `1500/1500` steps.

A separate presentation-only defect was proven in the PF resource breakdown:
the reporter treated the authoritative empty `initial_gfm_indices=[]` as a
missing option and substituted its default index 2. The solver and selected
mode map were already all-GFL, but the printed row incorrectly labelled IBR2
as GFM. The reporter now consumes `selection.selected_gfm_indices`, preserves
an explicit empty fallback, and prints active order 45 with four GFL-RMS10
resources. The targeted all-GFL file passes `6/6` tests on MATLAB R2026a.

The report keeps the complete GFM state order, ODEs, and control equations as
documentation of the reserved inactive dual-mode branch. Every numerical
table and plot in the report is from SG1 plus four active GFL-RMS10 resources.
The compiled report has 17 A4 portrait pages; the PF, line-flow, resource,
SSSA, and event-free TS pages were visually checked after rasterization.

The original report revision placed source-case REF/PV/PQ PF bus and branch
tables beside the all-GFL mixed-device injection table. Those are different
operating points and cannot be compared row-wise. The report producer now
reconstructs every operating-point table from the accepted all-GFL
equilibrium: device `S=V*conj(I)` is aggregated by bus, frozen-admittance load
power is evaluated at the equilibrium voltage, and branch terminal powers are
evaluated at that same voltage. An independent complex balance assertion gives
`1.8610e-11 pu`, and Table 5 generation agrees exactly with Table 7 after
aggregation by bus.

A separately configured bus-4 fault still fails closed at its right limit when
the all-GFL terminal voltage reaches `0.039238 pu`, below the unchanged
`V_div_min=0.1 pu` RMS10 balanced-LVRT domain. This is an explicit model-domain
diagnostic, not a recurrence of the equilibrium defect and not evidence for
changing the ODE, current limits, or voltage-domain gate.

## Related files

- `+stability/mixed_ibr_sg_on_gfl_initialize.m`
- `tests/test_ibr_sg_on_all_gfl_equilibrium.m`
- `docs/project/AGENT_HANDOFF.md`
