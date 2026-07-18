# IBR launcher default-profile test contract

Date: 2026-07-19  
Status: RESOLVED_TEST_CONTRACT  
Scope: launcher/orchestration tests only; no device equation changed

## Proven defect in the previous tests

Three tests encoded the historical implicit launcher default of four legacy
WECC GFL devices (`initial_gfm_count=0`, `initial_gfl_count=4`).  The approved
launcher contract now binds the IEEE14 IBR menu to Profile B:

- SG1: five active EMF6 states (one source-frozen state),
- IBR2: REGFM_B1 GFM, 13 active states,
- IBR3/6/8: GFL-RMS10, ten active states each.

The independent cardinality oracle is therefore `5 + 13 + 3*10 = 48` active
states.  Runtime metadata additionally proves that all four IBR containers are
`ibr_dual_mode_rms10` and the total fixed inventory is 98 states.

The previous configured-fault test also required convergence.  GFL-RMS10 is
approved only for normal-operation TS; its low-voltage ride-through contract is
not approved.  On the frozen test fault the new route deterministically rejects
the right-limit algebraic transaction with
`ts_simulate_ibr_hybrid:rightLimit`.  Requiring convergence would encourage an
unsourced PLL freeze, limiter change, or tolerance relaxation.

## Correction

- Default tests now assert Profile B identity and counts.
- The RMS10 configured-fault test asserts deterministic fail-closed behavior.
- The historical trip/logging test explicitly requests `ibr_profile='legacy'`
  and remains a regression-only fixture; it no longer defines launcher defaults.

No tolerance, physical equation, event time, or solver gate was changed to make
the tests pass.

## Presentation-contract follow-up

The earlier plotting test required exactly two IBR figures. That assertion
contradicted the approved user-facing TS contract, which now requires separate
angle, frequency, power/current, and bus-voltage figures for both SG and mixed
SG/GFM/GFL studies. The fixture now supplies an explicit angle trajectory and
checks exactly four figures. This changes presentation only; trajectories and
device equations are unchanged.

The imported MATPOWER6 case14 left `V_base_kV=0`, even though the repository's
source-mapped IEEE14 case (`cases.case_ieee14bus`) freezes the same network's
reporting base at 69 kV. The imported case now reuses that in-repository base
contract, and the independent reporting oracle is exactly
`bus_voltage_kV = 69*bus_voltage_pu`. No per-unit PF input or equation changed.

The previous IBR UI test required the user-facing text
`blank=count selector` and a manual GFM+GFL cardinality check. Desktop evidence
showed that changing the GFM count while leaving a stale explicit index caused
the production validator to reject the request. The approved UI now exposes
only `initial_gfm_count`; GFL count, GFM indices, and reference are disabled
AUTO fields resolved by the pure `wizard.normalize_ibr_mode_selection` helper.
The test now verifies that automatic contract rather than requiring the stale
manual-entry behavior.
