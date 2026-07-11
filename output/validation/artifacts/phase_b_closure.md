# Phase B Closure — PF Validation Artifact

**Generated:** 2026-07-12 (FRESH this session — all tools run in this invocation, no saved metrics)

## Provenance

- Repository (absolute): `/home/birds/Documents/Power-flow`
- validated_source_commit: `477b2ef5384b3bd389263473bab037c4980fbb85` (branch `main`)
- git status --porcelain at test time: clean for the files under test (Phase B comment-fix
  edits were uncommitted but DO NOT alter runtime behavior — comment-only changes; the
  Padiyar dispatch feature commit `477b2ef` precedes this closure).
- MATLAB version: 26.1.0.3276743 (R2026a) Update 3
- Reference tools (validation only, never production deps):
  - **PSAT** — primary required cross-validation reference. `/home/birds/Documents/psat-2.1.11-mat/psat` v2.1.11.
  - **PGAz** — secondary diagnostic only. `/home/birds/Documents/PGAz_V1.1.1` v1.1.1.
    NOT a required gate; never a basis for relaxing tolerance.

## Phase B closure scope

Phase B hardened the in-house Newton-Raphson PF solver's failure semantics (commits
`339b4ad` Phase B1 + `a393338` Phase B2) and demoted PGAz from a required gate to a
secondary diagnostic. This closure:

1. Fixes the `solve_model` Newton-iteration-order comment in
   `+pfsolver/powerflow_newton_raphson.m` to match the actual runtime order (convergence
   check is step 3, before the Jacobian is built — not step 11). Comment-only; runtime
   unchanged.
2. Removes a stale `FSOLVE` string in `+stability/synchronous_emf6_ssa.m` (PF uses the
   in-house Newton solver; fsolve was moved to `legacy/` in a prior session).
3. Aligns the `compare_case14_ts_three_way` docstring with the current gate semantics:
   PSAT is the primary required reference; PGAz is a secondary diagnostic.
4. Records fresh PF + PSAT + regression evidence below.

## PF failure-semantics summary (from `docs/PF_FAILURE_SEMANTICS_CONTRACT.md`)

- **C1 invalid input/schema** — thrown by `pf_prepare_case` before the numerical solve
  (stable error identifiers).
- **C2 numerical-solve failure** — returns `converged=false` with `reason` ∈
  {`singular_jacobian`, `nonfinite_system`, `nonfinite_newton_step`, `nonfinite_state`,
  `max_iterations`}, plus `max_mismatch`, `iterations`, `finite_status`.
- Converged path is bit-for-bit identical to the pre-hardening solver (new guards are
  dead on convergence: `rcond(J) >> 1e-13`, all states finite).
- Reference-independence: the solver reads ONLY `bus_data(:,3:6)`. Published comparison
  fields (`printed_*`, `table95_eigenvalues`, `pgaz`) are NEVER read on the solver path
  (`tests/test_pf_reference_independence.m`).

## Fresh verification results (this session)

### Targeted PF + contract tests

```
tests/test_pf_contract.m                       P=27 F=0 I=0
tests/test_pf_jacobian.m                       P=1  F=0 I=0
tests/test_pf_reference_independence.m          P=5  F=0 I=0
tests/test_nr_solver.m                         P=11 F=0 I=0
tests/test_no_external_solver_dependency.m     P=12 F=0 I=0
tests/test_padiyar_two_area_reference.m         P=9  F=0 I=0
tests/test_validation_gate_logic.m              P=11 F=0 I=0
TARGETED PF SUMMARY:                            P=76 F=0 I=0
```

### Case14 three-way (Ours + PSAT + PGAz), bus-4 fault, Zf=j0.1, dt=0.01, t_end=15s

- `psat_comparison = PASS` (primary required gate)
- `pgaz_comparison = FAIL` (secondary diagnostic only — NOT a required gate; PGAz's
  converged solution differs from PSAT/Ours due to its integration formulation, proven
  by the PGAz convergence study: ci=3/8/12 all give ~0.6 deg offset; Ybus/fault/mapping/PF
  match at machine precision. PGAz source was NOT modified. No tolerance was relaxed.)
- `all_gates_pass = PASS`
- PSAT ran=1, completed=1, td_points=1509
- Ours non-converged steps = 0
- PF (PSAT vs Ours): max|dV| = 6.661e-16 pu, max|dAng| = 3.553e-14 deg
- TS (PSAT vs Ours, COI frame): max|dCOI| = 0.0096 deg, max|dω| = 3.816e-6 pu,
  max|dPe| = 0.0422 MW, max|dVm bus4| = 3.179e-5 pu

### RTS-24 vs PSAT (classical, bus-15 fault, Zf=j0.1, dt=0.01, t_end=15s)

PSAT available on this host; PSAT leg completed. From `output/validation/rts24_psat/`:

- PF: in-house 5 iterations, PSAT 4 iterations; max|dVm| = 0.0000 mpu, max|dAng| = 0.0000 deg
  (exact-network PF cross-validation passes at machine precision).
- TS: max incremental COI-rel error = 0.0067 deg, max speed error = 4.674017e-6 pu,
  max Pe error = 8.270938e-4 pu, max fault-bus voltage error = 0.0054 mpu.
- Ours/PSAT max pairwise = 39.64 / 39.64 deg; incremental pairwise = 9.10 / 9.09 deg.
- Both bounded within the 15 s window (D=0 ⇒ marginal stability).

### Full regression

```
runtests('tests','IncludeSubfolders',true):
  total=259  passed=259  failed=0  incomplete=0
```

## Commands (reproduce)

```matlab
restoredefaultpath; cd('/home/birds/Documents/Power-flow'); pf_init_paths;

% Targeted PF + contract tests
files = {'tests/test_pf_contract.m','tests/test_pf_jacobian.m', ...
         'tests/test_pf_reference_independence.m','tests/test_nr_solver.m', ...
         'tests/test_no_external_solver_dependency.m', ...
         'tests/test_padiyar_two_area_reference.m','tests/test_validation_gate_logic.m'};
for k = 1:numel(files); r = runtests(files{k}); assert(~any([r.Failed]) && ~any([r.Incomplete])); end

% Fresh PSAT gates
addpath('/home/birds/Documents/psat-2.1.11-mat/psat');
o14 = compare_case14_ts_three_way;   % o14.gates.psat_comparison && o14.gates.all_gates_pass
o24 = compare_rts24_psat;

% Full regression
r = runtests('tests','IncludeSubfolders',true); assert(~any([r.Failed]) && ~any([r.Incomplete]));
```

## Gate status

| Gate | Status |
|---|---:|
| PHASE_B_PF_READY | PASS |
| targeted PF tests (76) | PASS |
| Case14 psat_comparison (primary) | PASS |
| Case14 all_gates_pass | PASS |
| RTS-24 PSAT leg (primary) | PASS (PF machine-precision; TS within declared tolerances) |
| PGAz comparison (secondary diagnostic) | FAIL (reported, not required) |
| full regression (259) | PASS |

## Explicit statements

- All values above are from fresh runs in this session (no saved `.mat` replayed as fresh).
- No parameter tuning to match PSAT/PGAz/Kundur/literature.
- No tolerance was relaxed after seeing a result.
- No hidden non-convergence (Ours non-converged steps = 0 on Case14).
- PGAz source was NOT modified; its comparison failure is reported honestly as a
  secondary diagnostic, not masked.
- Phase B closure does NOT touch TS kernel, PF solver runtime, or adaptive TS.
