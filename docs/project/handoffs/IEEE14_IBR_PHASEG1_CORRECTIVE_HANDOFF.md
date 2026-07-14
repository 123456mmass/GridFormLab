# IEEE14 Phase-G1 corrective handoff

Date: 2026-07-15
Implementation commit: `6f48eff`
Documentation commit: this documentation checkpoint

## Why the correction was required

The earlier reduced formulation fixed one voltage coordinate and deleted the
matching KCL row. That produced a small reduced residual without satisfying the
physical network:

- SG_OFF + GFM omitted-KCL mismatch: approximately `0.581 pu`.
- SG_ON + 4 GFL omitted bus-1 imaginary KCL mismatch: approximately
  `1.586623 pu`.

Changing Newton variants, warm starts, gains, FD steps, tolerances, or dispatch
cannot repair an under-specified residual. The correction adds the missing
balancing input and retains all KCL rows.

## Governing reference equations

For an online SG at the MATPOWER REF bus:

```text
Re(Vref) = Vm_case*cos(theta_case)
Im(Vref) = Vm_case*sin(theta_case)
u_ref    = [Tm; Efd]                 (equilibrium unknowns)
R        = [f_active(x,y,u); g_all(x,y,u)]
g_all    = rectangular(Y*V - Iinj)  (all 2*nb rows)
```

For an SG_OFF island with selected GFMs:

```text
Im(Vref_GFM) = 0                     (one angle coordinate)
u_ref.P_ref  = equilibrium unknown
R            = [f_active(x,y,u); g_all(x,y,u)]
```

The coordinate gauge never replaces a physical equation. Non-reference GFM
active-power inputs remain scheduled. Each GFM reactive output is determined
by the network and voltage-regulation equations. The reference GFM scheduled
P, solved P, deviation, and Pmax check are reported.

## Index-selected configuration

The trip transaction carries:

```text
selected_gfm_indices
n_gfm_required
reference_resource_index
```

All three fields are atomic. Counts of 1, 2, 3, and larger are supported. The
reference must be exactly one selected eligible online GFM, and the selected
set must match the complete runtime GFM set. A hybrid snapshot and duplicate
caller tuple must agree exactly; conflict fails with
`selectionContextMismatch`. Invalid events leave the original hybrid state
unchanged.

While the SG is online, the unique online SG at the case REF bus owns the
numerical reference even if a post-trip GFM subset has already been committed.
After SG trip, the committed GFM reference owns the angle coordinate and
active-power balance.

## Initialization and state partitions

`mixed_ibr_reduced_initialize` solves a project-owned reduced positive-sequence
network problem for bus voltage, each GFM Q, and the one reference GFM P, then
uses exact device equation inversions to construct GFL/GFM state roots. The
full coupled Newton independently refines and checks the result.

Equilibrium/SSSA excludes offline devices and physically singular states. TS
uses a separately authenticated dynamic map:

- breaker-open SG: zero current, rotor coast and open-circuit flux dynamics;
- offline/tripped dual-mode IBR: zero current, zero power, `f=0`;
- inactive online dual-mode branch: exact `dx=0`;
- `Tpq0=0` SG `Edp`: frozen singular-limit state in every path.

## Shared PF/SSSA/TS equations

The equilibrium result returns the physical devices, `u_eq`, immutable event
context, equilibrium active/frozen maps, and TS dynamic map.

- Equilibrium solves project `f` plus all project `g` rows.
- SSSA differentiates those same closures, verifies the active map, forms
  `A = fx - fy*(gy\gx)`, then projects active states before `eig`.
- Fixed-step TS holds `u_eq` and the context constant, authenticates the
  dynamic map, and solves coupled trapezoidal `R_x` plus all KCL rows with
  `composite_newton`.

No external solver is reachable from production.

## Phase-G1 scope

Implemented:

- REGFM_B1 Eq.13 transient circular clamp;
- `Z_sys=kappa*(Re+jXL)` and `ImaxF_sys=ImaxF/kappa`;
- sourced `VPLLfrz=0.05 pu` PLL freeze;
- shared limited-current helper and metadata.

Deferred to Phase-G2:

- Emax/Emin actuator behavior;
- steady-state PQ priority and Eqs.10-11;
- Fig.6 `kI/s` active-current limiter state;
- anti-windup.

## Selector and event limitations

The selector enumerates deterministic exact-size candidate subsets but does
not fabricate topology/SSSA evidence. Until an authorized evaluator supplies
that evidence, `sssa_evaluated=false` and `ready_to_commit=false` remain the
honest result. Event primitives exist, but the current top-level runner is
no-event/static-context; integrated fault/trip/switch/reclose, synchronism
enforcement, and right-limit rollback remain NOT_READY.

## Verification

```matlab
restoredefaultpath;
cd('C:\Users\User\Desktop\Power-flow');
pf_init_paths;
r = runtests('tests','IncludeSubfolders',true);
r_guard = runtests('tests/test_no_external_solver_dependency.m');
```

Focused corrective suite: `105/105 passed`.

Fresh post-implementation full regression on MATLAB R2025a: `718 total / 714
passed / 0 failed / 4 incomplete`. The four incomplete results are the
PGAz-conversion contract assumptions filtered because PGAz is not installed.
The run had zero new failures. `git diff --check` remained clean.

## Readiness

```text
IEEE14_IBR_GFL_MODEL_READY       = STRUCTURAL_ONLY
PHASE_G1_LIMITER_READY           = IMPLEMENTED_STRUCTURAL_ONLY
IBR_PRODUCTION_INTEGRATION_READY = NOT_READY
```
