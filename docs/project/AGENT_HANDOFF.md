# Agent handoff — IEEE14 mixed-resource IBR corrective checkpoint

Date: 2026-07-15
Branch: `main`
Implementation commit: `6f48eff`
Immediate parent work: `dff89dc` (eigenvalue dominant-state table)

This is the current canonical handoff. Older phase handoffs remain historical
evidence and do not override this file or
`handoffs/IEEE14_IBR_PHASEG1_CORRECTIVE_HANDOFF.md`.

## Outcome

The false SG_ON and SG_OFF equilibria caused by replacing a physical KCL row
with an angle constraint are removed. A reference constraint now removes a
coordinate only; every rectangular network KCL equation remains in the solved
residual.

Two physical reference formulations are implemented:

```text
SG online REF:
  unknowns = [x_active; y except Re/Im(Vref); Tm_ref; Efd_ref]
  residual = [f_active; all 2*nb KCL rows]
  Vref is fixed to the case REF magnitude and angle

SG offline, selected GFM REF:
  unknowns = [x_active; y except Im(Vref); P_ref_reference]
  residual = [f_active; all 2*nb KCL rows]
  one selected GFM P reference balances load and losses
```

The solved controls are returned in `u_eq` and held constant by the audited
fixed-step TS and SSSA paths. They are not re-solved at each time step.

## Exact index-selected GFM contract

- `n_gfm_required` is explicit; the engine does not assume one GFM.
- `selected_gfm_indices` may contain 1, 2, 3, or more eligible resources.
- The selected set must equal the complete online runtime GFM set.
- Exactly one selected GFM is `reference_resource_index`.
- Other selected resources remain physical GFMs and share through their
  sourced equations; they are not relabeled as GFL or as additional slacks.
- The selection/count/reference tuple is atomic. A hybrid-state snapshot owns
  the tuple; conflicting caller metadata fails closed.
- Resource IDs, device ordering, online status, GFM capability, cardinality,
  and reference membership are validated before Newton.

## Corrected runtime path

```text
scenario / solve_case
  -> build_mixed_resource_devices
  -> mixed_equilibrium_solve
       -> mixed_ibr_reduced_initialize (SG_OFF warm start)
       -> composite_dae f/g and all-KCL residual
       -> composite_newton (damped Newton/backtracking)
  -> composite_sssa_model (same f/g, full-KCL Schur reduction)
  -> ts_simulate_composite (same f/g, constant u_eq/context)
  -> result/output
```

Equilibrium and TS state maps are intentionally distinct. An offline SG has no
stationary root with retained mechanical torque, so its states are excluded
from equilibrium/SSSA. During TS its non-singular states still follow the
breaker-open rotor-coast and open-circuit flux equations while its network
current is exactly zero. Inactive dual-mode IBR states use exact `dx=0`; the
old artificial `lambda=1e-3` decay is removed.

## Network and model corrections

- Composite Ybus now includes MATPOWER bus shunts:
  `diag((GS + j*BS)/baseMVA)`. IEEE14 bus 9 therefore contributes `+j0.19 pu`.
- GFL and GFM devices expose exact, equation-derived equilibrium initializers.
- The GFM Eq.13 current clamp uses
  `Z_sys=kappa*(Re+jXL)` and `ImaxF_sys=ImaxF/kappa`.
- The same limited-current helper feeds RHS filters, current injection,
  electrical power, and reconstruction.
- REGFM_B1 PLL freeze at `|V| < VPLLfrz=0.05 pu` is active.
- `composite_newton` retains project-owned damped Newton/backtracking; rejected
  line-search steps are never applied. No LM, pseudo-inverse, or external
  solver fallback is present.

## Evidence

Focused corrective gates: `105/105 passed`, including Phase 4/8/B2/EF/G,
one-to-three GFM selection, atomic event commitment, SG reference, SG_OFF
TS/SSSA, Newton contracts, and the external-solver guard.

SG REF independent evidence at the corrected root:

```text
physical KCL / residual = 8.35060909e-11
rcond                   = 1.58080885e-5
V1                      = 1.06 angle 0
Tm solved               = 2.01708058 pu
Efd solved              = 1.18881580 pu
```

The original MATPOWER REF `Pg=232.4 MW` is not treated as a fixed input. Under
the mixed-resource `Qref=0` operating point, REF-bus P/Q are solved outputs.

Fresh post-implementation full regression on MATLAB R2025a: `718 total / 714
passed / 0 failed / 4 incomplete`. The four incomplete results are the
PGAz-conversion contract assumptions filtered because PGAz is not installed;
they are not new Phase-G1 failures.

## Honest readiness

```text
IEEE14_IBR_GFL_MODEL_READY       = STRUCTURAL_ONLY
PHASE_G1_LIMITER_READY           = IMPLEMENTED_STRUCTURAL_ONLY
IBR_PRODUCTION_INTEGRATION_READY = NOT_READY
```

Remaining blockers include source-closing GFL `Kps/Kis`, Phase-G2 steady-state
PQ priority/current limiting and anti-windup, an integrated topology +
equilibrium + SSSA selector, an event-driving adaptive hybrid simulation with
right-limit rollback, and independent validation. The current production
runner is still no-event/static-context; do not claim end-to-end automatic
trip/switch/reclose readiness.

## Preserved local material

`docs/text/` and `docs/probes/ieee14_ibr_phaseG/` are intentionally untracked.
They include local source transcriptions and validation-only probes, including
external-solver experiments. They are not production dependencies and were not
staged by this corrective delivery.
