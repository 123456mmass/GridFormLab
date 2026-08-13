# Standalone EMF6 SSSA oracle fails its own equilibrium tolerance on the mission profile

Date: 2026-08-13
Status: OPEN (pre-existing, out of scope for the work that found it)
Defect ID: `TEST-2026-08-13-04`

## Symptom

```text
tests/test_ibr_sg_on_all_gfl_equilibrium/test_sg_stationary_initializer_matches_emf6_oracle
Error using stability.synchronous_emf6_ssa (line 30)
EMF6 equilibrium residual 4.485e-01 exceeds tolerance.
```

The test calls the standalone EMF6 small-signal oracle
`stability.synchronous_emf6_ssa(scenario.case_data, struct('load_model','cz_p_cz_q'))`
purely to obtain machine parameters for an independent stationary-initializer
comparison. The oracle refuses to build because its own internal equilibrium
residual is `0.4485`, far above its tolerance, so the comparison never runs.
The other five tests in the file pass.

## Reproduction and evidence boundary

```matlab
pf_init_paths; runtests('tests/test_ibr_sg_on_all_gfl_equilibrium.m')
```

The failure is **pre-existing**. It was verified on a pristine detached
worktree at `e233b6c` — the commit before the decoupled-GFM work — with the
identical result (5 passed, 1 errored, same identifier
`synchronous_emf6_ssa:equilibrium`, same `4.485e-01` residual). It is therefore
not caused by the decoupled-GFM registration, the reference-AGSI overlay, or the
provenance corrections delivered alongside it.

The test uses the DEFAULT `mission` case profile
(`cases.scenario_ieee14_1sg_4ibr(struct('ibr_profile',...))` with no
`case_profile`), i.e. `case_ieee14_1sg_4ibr_auto_vsg` and the
`regfm_b1_dual` IBR family. Every scenario edit made by the decoupled work is
guarded on `case_profile in {eecon49_figure4, decoupled_figure4}` or
`model_id in {eecon49_dual, decoupled_dual}`, so the mission path is
semantically unchanged.

## Not yet diagnosed

No root cause is claimed here. The observation is only that the standalone
`synchronous_emf6_ssa` route cannot reach its own equilibrium tolerance on this
case/load-model combination, while the production mixed path
(`stability.mixed_equilibrium_solve` + `composite_sssa_model`) solves the same
network to `2.02e-13` in the same test file. Candidate directions, none
verified:

1. the standalone route builds an SG-only network problem, so the four IBR
   injections of this scenario are absent from its power balance — the
   documented hazard already recorded as `SWITCH-2026-08-04-05`;
2. the `cz_p_cz_q` load model may not be applied identically on both routes;
3. the machine data path may differ from the one the production device uses.

## Consequence

The affected assertion is an *independent oracle* for the SG stationary
initializer, so while it errors, that particular cross-check is unavailable.
Production PF/SSSA/TS behaviour is unaffected: nothing in the production path
calls `synchronous_emf6_ssa`, and the mixed equilibrium and composite SSSA gates
used for delivery pass on the same tree.

Do not "fix" this by relaxing the oracle's tolerance or by deleting the
assertion. Either the standalone route's problem statement is wrong for a mixed
SG/IBR case (fix the route or restrict its documented applicability), or the
case/load-model combination is being passed incorrectly (fix the caller).

## Related files

- `+stability/synchronous_emf6_ssa.m`
- `tests/test_ibr_sg_on_all_gfl_equilibrium.m`
- `2026-08-04-mixed-emf6-initialization-contract.md`
