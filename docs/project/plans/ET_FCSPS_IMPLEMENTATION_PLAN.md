# ET-FCSPS implementation plan

Date: 2026-08-04
Branch: `main`
Starting commit: `6eeb05cc0ab2dd687857ac8e6329905359a8cc03`

## Scope and ownership

This approved implementation adds an event-triggered finite-control-set
predictive-supervisor core without changing the production SG/IBR equations,
AGSI++ thresholds, event chronology, shared TS kernel, case data, reports, or
plots. The initial integration boundary is deliberately fail-closed: the core
returns an authenticated commit request but never mutates the hybrid state.
Existing atomic event handlers remain the only commit authority.

Allowlist:

- `+stability/et_fcs_*.m` (new files only);
- `tests/test_et_fcs_supervisor.m`;
- this plan and the current handoff;
- a defect record only if a reproducible material defect is found.

No shared dispatcher, composite DAE, TS kernel/driver, topology/event handler,
SG/IBR model, report source, or report PDF is in scope for this phase.

## Frozen decisions

- `PROJECT_DERIVED`: AGSI++ or an authenticated scheduled/topology/reference
  event may request evaluation; neither directly selects the winner.
- `PROJECT_DERIVED`: enumerate every eligible GFL/GFM mode vector. With an
  online SG reference, the SG remains the owner in this phase. Without an SG
  owner, each online reference-capable GFM in the selected subset is an owner
  candidate.
- `NUMERICAL_METHOD`: enumeration is canonical by binary mode ordinal then
  owner resource index. Ranking is deterministic and records every component.
- `PROJECT_DERIVED`: hard feasibility precedes cost. Unknown reserve, missing
  limits, non-finite evidence, failed KCL/prediction, stale fingerprint, and
  callback exceptions all fail closed.
- `CASE_DEFINED`: prediction horizon, limits, reserve targets, normalization,
  and weights are caller inputs. The IEEE14 prototype policy freezes one
  `PROJECT_DERIVED` set from the existing AGSI++ normalization scales before
  controller outcomes are viewed; callers may instead supply another
  provenance-labelled contract.
- `NUMERICAL_METHOD`: all candidate trials start from the same immutable
  accepted snapshot. The supervisor returns evidence and a commit request;
  it performs no production mutation.
- `ASSUMED_DIAGNOSTIC`: an in-house finite-set BO replay baseline may reveal
  candidate prediction costs sequentially using a Gaussian-process surrogate
  and expected improvement. It receives the same hard-screened universe and
  never feeds ET-FCSPS or production state. It exists only to compare selected
  cost/regret and expensive-evaluation count under a frozen budget.

## Predeclared gates

1. Four eligible IBRs produce 16 canonical mode vectors; SG-off produces 32
   mode-owner pairs and excludes all-GFL.
2. Duplicate IDs, unsupported modes, non-finite states, unknown reserve,
   stale/incomplete evidence, and missing case-defined policy fail closed with
   stable IDs.
3. Candidate trial callbacks cannot alter the accepted snapshot as observed
   by its fingerprint and value identity.
4. Voltage, current, frequency, RoCoF, reserve, KCL, horizon, dwell, lockout,
   online, and reference-continuity counterexamples are rejected before rank.
5. Ranking is invariant to candidate input order and replayed identical inputs
   produce identical winner/evidence fingerprints.
6. No feasible candidate returns `INFEASIBLE`; no event returns `HOLD`; neither
   path emits a commit request.
7. The default production runtime remains unreachable from the new core until
   a separately approved project-owned right-limit/prediction adapter supplies
   the mandatory case-defined contract.
8. BO replay is deterministic for a fixed table/policy, never evaluates more
   than its budget, uses no Optimization Toolbox/external solver, and recovers
   the exhaustive winner when its budget spans the full feasible universe.

## Verification

Run the focused MATLAB unit suite for the new core plus static checks proving
that no existing runtime/report file changed. The full repository regression is
not required for this isolated additive core unless a targeted failure points
to a broader interaction.
