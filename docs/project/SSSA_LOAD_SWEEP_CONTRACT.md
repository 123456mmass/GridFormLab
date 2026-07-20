# SSSA Load-Sweep Contract (FROZEN)

Date: 2026-07-21. Branch: `main`.
`smib_starting_commit = 83390db`; `smib_delivery_commit = efa9617`;
`load_sweep_starting_commit = efa9617`.
Status: `SSSA_LOAD_SWEEP_CONTRACT = PASS` (frozen before results).

This document is the frozen contract for the SSSA Load-Sweep workflow. It is
the authority for the load equation, scaling policy, dual-representation audit,
dispatch policy, SSSA ownership, mode-tracking contract, stopping semantics,
and prohibited claims. It must not be edited after results are produced; any
material change requires re-planning.

## 1. Product identity

- Public entry point: `stability.sssa_load_sweep(case_data, opt)`.
- Launcher families:
  - `analysis='sssa'` (conventional SG cases) — `route='sg'`.
  - `analysis='ibr'` (IEEE14 mixed SG/GFM/GFL) — `route='ieee14_ibr'`.
  - `analysis='ibr'` for `smib_loaded_ibr/1.0` cases (single GFL-RMS10 OR
    GFM-no-PLL to infinite bus with shunt load) — `route='smib_ibr'`.
- The IEEE14 mixed case is launched through `analysis='ibr'` ONLY; it is NOT
  routed through `stability.multicase_sssa`.
- SMIB verification cases are discovered under `analysis='ibr'` only (not
  `analysis='sssa'`). Ideal SMIB (`smib_verification/1.0`) →
  `LOAD_SWEEP_NOT_APPLICABLE_TO_IDEAL_SMIB`. Loaded-IBR cases
  (`smib_loaded_ibr/1.0`) are applicable and route through `route='smib_ibr'`.
- `result.sssa_load_sweep` attaches additively; existing single-point SSSA
  fields are never mutated.

## 2. Load equation (constant power factor)

```
load_scale alpha = 1 + load_percent/100
P_L,k(alpha) = alpha * P_L,k,base
Q_L,k(alpha) = alpha * Q_L,k,base
```
Default percentages: `[0 20 40 60 80]` → alpha = `[1.00 1.20 1.40 1.60 1.80]`.
(For `smib_loaded_ibr/1.0`, `P_L,k` and `Q_L,k` are the single shunt-load
fields `P_load_base_pu` / `Q_load_base_pu` at the terminal bus.) The user
may pass any strictly increasing nonnegative vector. The default includes the
base/normal operating point. Scale active and reactive load together; the original
load power factor is preserved at every bus.

## 3. Percentage validation (no silent canonicalization)

Validate `opt.sssa_load_percentages` in the order entered by the user.
Require strictly increasing and unique: `all(diff(percentages) > 0)`.
Do NOT sort, deduplicate, clip, or otherwise canonicalize invalid input.
Reject nonfinite, complex, negative, duplicate, or non-monotonic vectors
with `sssa_load_sweep:invalidPercentages`. No silent clip or replacement.

## 4. Case immutability and dual-representation audit

Never mutate or overwrite the original case data. For every sweep point, make
an isolated case copy. The scaled snapshot is stored as `point.case_data`
BEFORE solver execution; a separate working copy is passed into
PF/equilibrium/SSSA so the stored snapshot is never mutated by runtime-added
solved fields. Do not store runtime function handles, device closures, solved
fields, figures, or mutable solver artifacts inside the case snapshot.

### Dual load-representation audit (conditional, compare values)

Inspect the supported case schema first, then:
- a. If both `bus_data` and `mpc.bus` exist: audit their bus IDs, signs, units,
  nonzero-load support, and converted values (`bus_data` P/Q on system pu base
  ↔ `mpc.bus` Pd/Qd in MW/MVAr through `Sbase`); update both consistently.
  Fail closed (`sssa_load_sweep:loadRepresentationMismatch`) if they disagree.
- b. If only the schema-authoritative `bus_data` representation exists: scale
  it without fabricating `mpc.bus`.
- c. If the selected runtime consumer requires `mpc.bus` but it is absent:
  fail closed as unsupported (`sssa_load_sweep:missingMpcLoadRepresentation`).
- d. If both exist and disagree: fail closed with
  `sssa_load_sweep:loadRepresentationMismatch`.

### Do NOT scale

branch parameters; generator dynamic parameters; GFM/GFL gains; inertia or
damping; voltage setpoints; limits; event times; base MVA; state initial
values from another operating point. Every point must independently solve PF
and dynamic equilibrium.

## 5. PF and equilibrium contract at every load level

For each `alpha_k`:
1. Run the project-owned Newton PF (`pfsolver.powerflow_newton_raphson`) on a
   separate working copy. `composite_dae` is NOT the PF solver; it consumes
   the PF result.
2. Respect REF/PV/PQ semantics and Q limits.
3. Record convergence, iterations, maximum mismatch, voltage range,
   generator P/Q, total load, losses, and limit switching.
4. Rebuild devices from the scaled case (route-specific). GFM/GFL mode map
   from `event_context.hybrid_state` (single source of truth) — same map at
   every load point; do not auto-switch GFM/GFL to make a load point converge.
5. Solve `f(x,y,u)=0` and `g(x,y,u)=0` via `stability.mixed_equilibrium_solve`
   (IEEE14) or SG-equivalent.
6. Record `||f_active||inf`, `||g||inf`, rcond, active/frozen indices,
   active-bound regimes, device-limit verdicts.

### Dispatch policy (ASSUMED_DIAGNOSTIC)

Non-reference resource P/Q setpoints remain fixed according to the selected
case contract; the REF bus injection balances PF mismatch. `Tm`/`Efd` are
equilibrium initialization inputs only and are NOT a PF redispatch policy.
This dispatch policy is classified `ASSUMED_DIAGNOSTIC` because the current
IEEE14 case contract does not define a load-growth participation policy. It
cannot support a physical adequacy or production-readiness claim.

## 6. SSSA contract

For each converged operating point, form SSSA from the SAME production
equations used by equilibrium and TDS:
```
[fx fy; gx gy]
A_full = fx - fy * (gy \ gx)
A = A_full(active_state_indices, active_state_indices)
```
Rules:
- no `inv` or `pinv`;
- no independent or invented A matrix;
- no eigenvalue deletion;
- retain every active-state eigenvalue;
- use runtime state metadata (`dev.nx` / `dev.active_state_indices`), not
  hard-coded state counts;
- distinguish raw `sssa.A` from `physical_A`;
- never mix the two modal domains in one plot without explicit labels.

At every load level record: load percentage and alpha; number of SG, GFM,
GFL devices; total inventory and active-state count; `size(A)`; complete
eigenvalue vector; maximum real part; stable/marginal/unstable root counts;
oscillation frequency; damping ratio; dominant device/state when
participation is available; eigenpair residuals; conditioning/availability
status.

## 7. Mode matching across load levels (reporting-only, fail-closed)

Base MATLAB only — no `matchpairs` or any Optimization Toolbox routine.
Deterministic global one-to-one assignment across adjacent successful points
in a contiguous segment, using: normalized complex-eigenvalue distance;
left/right eigenvector correlation (MAC) in the same state coordinates;
conjugate-pair consistency; eigenpair residual / biorthogonality / eigengap /
conditioning gates.

Predeclare and test these NUMERICAL_METHOD choices (frozen BEFORE viewing
results): cost normalization; eigenvalue-distance weight; left/right
correlation weight; deterministic tie breaking (independent of raw eigenvalue
order); maximum acceptable assignment cost; ambiguity/eigengap threshold;
conjugate-pair consistency; residual and conditioning gates.

Never modify, delete, average, or reorder the raw eigenvalue result. Store raw
eigensolver order separately from the matched display order. When matching is
not unique, repeated/defective modes occur, state dimensions or ownership maps
differ, or conditioning gates fail, do not force a trajectory. Return
`MODE_MATCH_AMBIGUOUS` or `UNAVAILABLE_ILL_CONDITIONED` and publish a
cluster/subspace result when supportable.

### Analysis-domain separation

Mode-match only within ONE modal domain at a time. Publish separately:
- raw `sssa.A` spectrum and original active-state coordinates;
- `physical_A` spectrum when available;
- raw eigenvector/participation domain;
- physical reduced tangent/quotient domain.

Do NOT mode-match `physical_A` coordinates across points unless the lift maps
and coordinate identities are dimensionally consistent. Otherwise mark
physical mode tracking unavailable while retaining the raw-`A` tracking result.

### Reporting-only

The matching algorithm is reporting/analysis-only. It must NOT feed PF,
equilibrium, A-matrix construction, device parameters, or subsequent load
points.

## 8. Failure semantics (continue after point failure)

Each load point is an independent fail-closed transaction. A failure at one
point preserves its failure ID, stage, residuals, diagnostics, and requested
load scale, then continues with every later independent point. Do not
substitute a previous solution, interpolate missing eigenvalues, reduce the
requested load, or tune parameters to make the failed point pass.

### Segment split across failed gaps

Mode tracking must not bridge across a failed point. Example:
`0%,20% PASS / 40% FAIL / 60%,80% PASS` produces two tracking segments:
segment 1 = `[0%,20%]`, segment 2 = `[60%,80%]`, with
`NO_MODE_CONTINUATION_ACROSS_FAILED_POINT` published at the gap.

### Abort the entire sweep only for request-level failures

invalid load percentages; malformed case schema; ownership conflict;
unsupported analysis contract; missing authoritative equations/parameters;
missing required load representation (`mpc.bus` absent for a consumer that
needs it).

## 9. Applicability

- Ideal SMIB verification cases (`smib_verification/1.0` schema, no
  load-demand field): `LOAD_SWEEP_NOT_APPLICABLE_TO_IDEAL_SMIB`. Ordinary
  SMIB PF/SSSA/TDS products remain unchanged.
- Loaded-IBR cases (`smib_loaded_ibr/1.0` schema, single GFL/GFM to infinite
  bus with shunt load): applicable; route `smib_ibr`.
- `power_case/1.0` cases with nonzero load: applicable.
- Centralized predicate (`+load_sweep/applicability.m`), not `endsWith(case_id,'_smib')`.

### 9a. SMIB loaded-IBR dispatch policy (ASSUMED_DIAGNOSTIC)

For `smib_loaded_ibr/1.0`, the IBR references (`P_ibr_base_pu`, `Q_ibr_base_pu`
for GFL; `P_ibr_base_pu` + `V_ref` for GFM) are held FIXED at base values
across the sweep. The infinite bus is the slack that absorbs the incremental
load through `Z_line`. When load increases, the terminal voltage V moves, the
line current changes, and the IBR responds through its own dynamics (PLL /
current loop for GFL, VSG swing + Q-V droop for GFM). This is the physically
meaningful SMIB. Setting IBR reference = load would make line flow = 0 always
and degenerate to an isolated IBR+load, NOT a SMIB. Tm/Efd are not applicable
(IBR, no SG).

## 10. Prohibited claims and stop conditions

Do NOT: tune device/controller parameters for stability; modify load
percentages after seeing eigenvalues; delete positive-real-part roots; smooth
eigenvalue trajectories; force mode matching; modify tests merely to pass;
silently replace failed PF/equilibrium points; use MATPOWER/Simulink/Optimization
Toolbox/external solvers; modify GFL/GFM/SG equations as part of this UI feature.

No nose point; no exact stability boundary; no modal continuation; no adaptive
stepping. If increasing load makes PF infeasible, equilibrium fail, `gy`
singular, or SSSA unstable, report that exact result honestly. Continue to
later independent points; do not abort the sweep.

## 11. Readiness

`SSSA_LOAD_SWEEP_PRODUCTION_READY = DIAGNOSTIC_ONLY`. The workflow uses
production PF/equilibrium/SSSA equations but the load-growth/dispatch study
policy is `ASSUMED_DIAGNOSTIC`. It does not claim an exact stability boundary,
CPF nose point, or production operating-limit approval. Stability is an
outcome, not an acceptance gate.

### 11a. Plot-data correction amendment (2026-07-21)

This reporting-only amendment does not change PF, equilibrium, device, Schur,
or eigenvalue equations.

- Plot A publishes every raw eigenvalue on linear real/imaginary axes using
  unconnected markers. An optional low-frequency detail is additional and
  never replaces the complete spectrum.
- Tracked plot coordinates use a cumulative one-to-one raw-index permutation
  of shape `number_of_points` by `number_of_active_states`; adjacent-pair
  assignments are not modal identities.
- Plot G publishes accepted-equilibrium `i_d`, `i_q`, `P`, and `Q`. GFL
  currents come from native GFL current states. GFM-no-PLL has no current
  states, so its displayed dq current is the diagnostic transform
  `I_inv*exp(-j*delta_vsm)`, classified
  `PROJECT_DERIVED_DIAGNOSTIC_VSM_FRAME_TRANSFORM`, and never feeds the model.
- Each published operating point independently verifies
  `P+jQ = V*conj(I)` on system base with a `1e-10` pu numerical consistency
  tolerance; mismatch fails closed before plotting.

## 12. Ownership

Single-owner responsibility for:
- `+wizard/*` (defaults_for_method, legacy_show, validate_request,
  dispatch_analysis, adapt_result, config_io);
- new `+stability/sssa_load_sweep*.m` orchestration/adapters/reporting files;
- new `+stability/+load_sweep/*.m` files including the extracted shared IBR
  SSSA route helper `ibr_sssa_route.m`.

No shared numerical kernel (`composite_dae.m`, `composite_sssa_model.m`,
`mixed_equilibrium_solve.m`, `multicase_sssa.m`, `multimachine_ssa.m`,
`cpf_load_scaling.m`, `powerflow_newton_raphson.m`) may be edited unless
inspection proves it necessary and the plan is materially updated.
