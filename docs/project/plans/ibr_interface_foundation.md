# Track A — Generic IBR Integration Interface Foundation (R1–R4)

## Context

The SG/shared numerical core must be prepared to receive a future IBR model
through generic, equation-first interfaces **without importing, registering,
or executing Track B runtime code**. Today the core has one canonical
trapezoidal kernel, one Schur SSSA engine, and hardcoded model-string dispatch;
inputs are constant (baked into closures), there is no composite DAE, and
`multimachine_ssa`'s `free_y` is a single variable-index set with no concept of
replacing KCL rows with voltage constraints.

This foundation adds four generic interfaces (R1–R4) using **synthetic analytic
models only** in tests. Track B (`feature/ibr-vsg-models`, HEAD `a684cd0`) stays
PAUSED and READ-ONLY. The 8 unsourced VSG equations remain fenced in `+ibr/`.

**Target:** `TRACK_A_IBR_INTERFACE_FOUNDATION_READY = PASS`;
`IBR_PRODUCTION_INTEGRATION_READY = NOT_STARTED`.

## Git / worktree plan

- New branch `feature/ibr-interface-foundation` from `origin/main` (`f59076f`).
- New worktree `/home/birds/Documents/Power-flow-ibr-interface`.
- Do NOT edit main directly. Do NOT push/merge. Do NOT touch Track B.

## Read-only evidence (verified this session)

- main == origin/main == `f59076f`; `+ibr/` does NOT exist on main; no
  production reference to `@ibr`/`register_model`/`model_fn`/`composite_dae`.
- Canonical kernel `ts_step_kernel.m`: legacy 8-arg + strategy 6-arg (dispatch
  L29); strategy path is a thin adapter, bit-identical.
- `ts_model_strategy.m`: `switch lower(model)` on 'padiyar'/'emf6'/'classical'.
- **Signature divergence:** classical `dae_f=@(x,y,Y)` (3-arg), `dae_g=[]`;
  padiyar/emf6 `dae_f=@(x,y)` (2-arg), `dae_g=@(x,y,Y)` (3-arg). This drives
  R2's capability-specific validators.
- `ts_adaptive_driver.m`: 3 kernel calls/trial; input is CONSTANT; on reject
  (x,y) restored.
- `multimachine_ssa.m:44`: `Afull = Jxx - Jxy(:,free_y)*(Jyy(free_y,free_y)\
  Jyx(free_y,:))`; `inv(Jyy)` FORBIDDEN.
- **SG sign convention (VERIFIED):** SG DAEs use `g = -Y*V + sum(I_inj)` —
  i.e. **`-YV+I`**. Padiyar L140 `gc=-Inet; gc(b)+=Ig`; EMF6 L169
  `g(1:2:end)=-real(Inet)` then `+=Ig`. The new composite canonical convention
  is `g = Y*V - Ibus` (Ibus = sum of device positive injections) — i.e.
  **`YV-I`**. These differ by a sign; the composite is NOT bit-identical to
  SG residuals. Devices return positive injection only; the sign relation
  `g_composite = -g_sg` is asserted ONLY in the legacy equivalence test (R3).
- Current INTO network (all models; matches Track B).
- `y=[Re(V1),Im(V1),...,Re(Vnb),Im(Vnb)]^T` interleaved, length 2*nb (shared).
- Bus mapping by external ID: `find(bus_ids==device_bus)`.
- SSSA has NO voltage-constraint concept today; PF has separate slack handling.
- Backward-compat gates: `test_ts_strategy_equivalence`,
  `test_ts_classical_strategy_equivalence`, `test_ts_characterization_fixed`,
  `test_sssa_contract` (7 sub-tests), `test_ts_default_routing`,
  `test_ts_adaptive_rollback`, `test_ts_result_schema`, `test_ts_simulate_
  general`, `test_no_external_solver_dependency`. 68 test files on main.
- `tests/+fixtures` does NOT exist yet (will be created for synthetic fixtures).

## R1 — Generic input interface (user-approved, revised)

Typed provider + constant adapter. **Binding constraints (user):**
- Provider is IMMUTABLE and side-effect-free.
- **Exogenous input:** `fn(t, event_context)` — NO state dependence. (State-
  dependent `fn(t,x,y,...)` would couple inputs to the trajectory and is NOT
  approved; if ever needed it requires separate approval.)
- `eval_input_provider(provider, t, event_context)` is the ONLY evaluation
  entry point (see Blocker 5: two public package functions).
- `event_context` is immutable, identifies topology + left/right event state.
  **Left/right endpoint semantics:** at an event time `t_e` (fault/clear),
  the LEFT context is the topology just before `t_e` and the RIGHT context is
  the topology just after `t_e`. The provider is evaluated with the context
  matching the endpoint being integrated: a step ending at `t_e` uses the LEFT
  context for its `t_e` evaluation; a step starting at `t_e` uses the RIGHT
  context. This matches the existing event convention (public sample uses the
  RIGHT-limit y; `ts_topology_at` selects Ypre/Yfault/Ypost by `t`).
- **Absent provider ⇒ EXACT legacy behavior.** Do NOT invent `u=[]` calls that
  change existing function dispatch or floating-point ordering. Legacy
  `dae_f(x,y)` / `dae_f(x,y,Y)` paths called UNCHANGED when no provider present.
- Constant provider returns `u0` exactly.
- Callback output type, size and finiteness validated on EVERY evaluation.
- **Endpoint time convention (revised):** evaluate `u` at EVERY RHS endpoint
  used by the trapezoidal step — `t`, `t+h/2`, `t+h` — so that the full step
  `[t,t+h]` and the two half-steps `[t,t+h/2]`, `[t+h/2,t+h]` see a consistent
  exogenous input at each evaluation point. (Trapezoidal RHS is evaluated at
  the step endpoints; the provider is sampled at those same endpoints.)
- Rejected attempts may append diagnostics but MUST NOT mutate provider state.
- NO closures capturing mutable counters, RNG state, or persistent state in
  production acceptance.
- Synthetic tests prove: full-step/two-half consistency, rejection rollback,
  event-time evaluation, bit-identical SG when provider absent.

**Interface:**
```
provider = make_input_provider('constant', u0)
provider = make_input_provider('callback', @(t,event_context) u)
provider.kind   = 'constant' | 'callback'
provider.u0     = vector/struct (constant input)
provider.fn     = @(t, event_context) u   (callback, EXOGENOUS)
u = eval_input_provider(provider, t, event_context)   % PURE, validates type/size/finite
```
**Backward-compat mechanism (critical):** kernel/strategy detect whether a
provider is present. If absent → ORIGINAL `dae_f(x,y)` / `dae_f(x,y,Y)` path,
no `u` argument, FP-identical. If present → provider-aware variant
`@(x,y,u) ...` (separate path). The two paths are SEPARATE.

**Synthetic oracle:** linear ODE `dx/dt=A*x+B*u(t)`, `A=[0,1;-1,0]`,
`B=[0;1]`, `u(t)=sin(2t)` (exogenous, no x/y dependence), `x0=[1;0]`. Closed
form (Duhamel): `x1(t)=cos(t)+(2/3)sin(t)-(1/3)sin(2t)`,
`x2(t)=-sin(t)+(2/3)cos(t)-(2/3)cos(2t)`. Source: standard ODE theory.

## R2 — Generic model dispatch (user-approved, revised)

**Model BUNDLE, not a step strategy.** A step strategy alone CANNOT initialize
`ts_simulate` (it lacks x0, y0, topology, mapping). The top-level dispatch
field is `opt.model_bundle`, which carries a complete TS initialization plus an
SSSA model. `ts_strategy` stays INTERNAL to the step layer. **Binding
constraints (user):**
- Dispatch precedence: (1) `opt.model_bundle` (already-built, fully populated),
  (2) `opt.model_fn` (explicit factory called once, returns a bundle),
  (3) existing built-in string switch.
- `model_bundle` and `model_fn` are MUTUALLY EXCLUSIVE; if both supplied, FAIL
  CLOSED.
- NO global/persistent registry, NO auto-discovery, NO path scanning.
- NO production reference to `+ibr` or any IBR model name.
- `model_fn` receives only documented case/options/context inputs and returns
  a bundle.
- **Capability-specific validators:** `validate_ts_bundle` (validates
  bundle.ts: .strategy [via the internal step-layer validate_ts_strategy],
  .x0, .y0, .topology{Ypre,Yfault,Ypost}, .mapping{bus_ids,gen_buses},
  .metadata; handles classical `dae_g=[]` and the 2-arg vs 3-arg arity
  divergence) and `validate_sssa_model` (validates bundle.sssa.model: .x0,
  .y0, .f, .g, optional Jacobian blocks, .free_y, .reduction fields). These
  are SEPARATE validators; a TS strategy does NOT double as an SSSA model.
- Validate: required fields, function arity, state/input/y dimensions, bus-ID
  mapping, names, finite initial values, ownership metadata — before solving.
- REJECT unknown extra ownership fields when they could change network
  semantics.
- Built-in SG string dispatch stays on the existing path and is bit-identical.
- Explicit `model_bundle` bypasses factory construction but NOT schema
  validation.
- Record dispatch provenance in result metadata: `built_in_string` |
  `explicit_model_fn` | `explicit_model_bundle`; NEVER serialize function
  handles.
- Synthetic tests cover all three routes, mutual-exclusion errors, malformed
  bundles, dimension mismatch, arity mismatch, and absence of any `+ibr`
  call-graph reference.

**Bundle contract:**
```
bundle.ts.strategy   = step strategy struct (internal; validated by validate_ts_strategy)
bundle.ts.x0         = initial differential state
bundle.ts.y0         = initial shared network y
bundle.ts.topology   = struct(Ypre, Yfault, Ypost)   % precomputed admittances
bundle.ts.mapping    = struct(bus_ids, gen_buses)     % external-ID mapping
bundle.ts.metadata   = {device_id, device_type, bus_id, provenance, ...}
bundle.sssa.model    = SSSA model struct (validated by validate_sssa_model)
bundle.metadata      = dispatch provenance (no function handles)
```
**Insertion:** `ts_simulate.m` BEFORE L50 (TS: opt.model_bundle > opt.model_fn
> string); `multicase_sssa.m` before its chain (SSSA: bundle.sssa.model >
opt.model_fn > string); `ts_model_strategy.m` keeps its internal role building
`bundle.ts.strategy` for the built-in SG paths and is called by
`validate_ts_bundle`.

**Synthetic plugin:** 2-state linear generator (classical ng=1) exposed as a
BUNDLE with both a ts_strategy and an sssa_model. Source: project `classical_dae`.

## R3 — Composite DAE foundation (user-approved, revised)

Single composite owner. **Binding constraints (user):**
- **Composite canonical convention:** devices return POSITIVE current
  injection only (`Iinj_dev`, current INTO network). The composite forms
  `Ibus = sum(Iinj_dev)` (by mapped bus), then forms the network residual
  `g = Y*V - Ibus` (`YV-I`). There are NO production "device sign adapters" —
  devices never see the network residual sign; they only return positive
  injection.
- **Sign conversion exists ONLY in legacy equivalence tests:** SG DAEs use
  `g_sg = -Y*V + sum(I_inj)` (`-YV+I`). The composite residual is
  `g_composite = Y*V - Ibus = -(g_sg)`. This relation `g_composite = -g_sg`
  is asserted ONLY in the legacy equivalence test, NOT in production code.
  No production adapter flips device contributions.
- Composite is the SINGLE owner of: shared interleaved y, topology/Y
  selection, external-bus-ID mapping, network KCL residual (`YV-I` form),
  slack/reference constraint replacement, state/input offsets and
  reconstruction metadata.
- Each device owns: differential state slice, input slice/provider, f_device,
  positive current injection (INTO network), device outputs/names.
- Slack/reference constraints replace corresponding KCL residual rows EXACTLY
  ONCE.
- NO device may return or modify the global network residual.
- Multiple devices at one bus summed deterministically into `Ibus`.
- Mappings use external bus IDs, never implicit row equality.
- Reject missing/duplicate/ambiguous ownership metadata.
- Preserve `y=[Re(V1),Im(V1),...,Re(Vnb),Im(Vnb)]^T`.
- Topology immutable within one accepted trapezoidal step; event switching
  owned by the driver/composite boundary.

**Synthetic one-device equivalence test (NOT production, NOT real-engine):**
- `g_composite = Y*V - Ibus`; `g_sg = -Y*V + Ibus = -g_composite`.
- A composite of ONE SYNTHETIC linear-generator device must reproduce that
  SAME synthetic device's standalone trajectory (delta, omega, Pe, Vbus) to
  solver tolerance. This is a synthetic-vs-synthetic equivalence (composite
  path vs direct-call path of the same fixture), NOT a claim that the
  composite reproduces the real SG classical engine.
- There is NO production classical-device adapter in scope. Real SG behavior
  is preserved through SEPARATE AbsTol=0 legacy regressions
  (`test_ts_strategy_equivalence`, `test_ts_classical_strategy_equivalence`,
  `test_ts_characterization_fixed`) that run on the unchanged legacy path.
- The residual relation is asserted as `max|g_composite - (-g_sg)| = 0`
  (sign-flip exact), NOT `max|g_composite - g_sg| = 0`. This is a TEST-only
  sign conversion; production code has no adapter.

**Frozen device signatures (Revision 2):**
```
f_dev                  = @(t, x_dev, y, u_dev, event_context) dx
current_injection_dev  = @(t, x_dev, y, u_dev, event_context) Iinj   (complex, INTO network)
reconstruct_dev        = @(t, x_dev, y, u_dev, event_context) struct(delta,omega,Pe,Vbus,...)
```
- All three device callbacks take `(t, x_dev, y, u_dev, event_context)`.
- Y/topology remains COMPOSITE-OWNED; devices never receive Y.
- Slicing uses `nx` (per-device differential-state count). `ns` is OPTIONAL
  metadata only (or removed); it is NOT used for slicing.
- `event_context` is the immutable left/right topology+event struct from R1.

**State/input ordering (user-approved, device-contiguous):**
```
x = [x_device1; x_device2; ...; x_deviceN]   (caller-provided ORDERED list)
u = [u_device1; u_device2; ...; u_deviceN]
```
- Every device has unique stable `device_id` + explicit external `bus_id`.
- Order is part of the case/interface contract; do NOT depend on struct field
  iteration, package discovery, registry order, or filesystem order.
- If canonical sorting desired, it is a SEPARATELY APPROVED case-schema rule.
- Support variable `nx_k`, `nu_k` including `nu_k=0`.
- 1-based inclusive offsets via cumulative sums. Expose `x_range`, `u_range`,
  `nx`, `nu`, `device_id`, `device_type`, `bus_id` per device.
- Qualified names: `device_id/state_name`, `device_id/input_name`.
- Reject duplicate `device_id`, malformed lengths, overlapping ranges,
  non-finite initial values.
- Reconstruction uses stored ranges, never assumes equal states-per-device.
- Shared y ordering is bus-contiguous, independent of device ordering.
- Current injections accumulated by mapped bus ID, not device position.
- Serialize metadata only; NEVER function handles.
- Tests cover mixed `nx={2,4,6}`, `nu={0,2,4}`, shuffled device lists,
  multiple devices at one bus, deterministic repeatability, exact round-trip
  slice/reconstruction, synthetic one-device equivalence (sign-flip).

**Submodel contract:** device.{name,device_id,bus_id,nx,nu,f,current_injection,
electrical_power,x0,u0,state_names,reconstruct}. (`ns` optional metadata only.)

## R4 — Algebraic/reference ownership (user-approved, revised)

Separate variable/residual ownership. **Binding constraints (user):**
- `vcon_vars`: algebraic variables whose perturbations are constrained.
- `vcon_rows`: residual rows replaced by voltage/reference constraints.
- `vcon_eq`: equations defining those constraints.
- **FIXED y-ONLY constraints (Revision 1):** `vcon_eq = vcon_eq(y,
  constant_reference)` — the constraint depends ONLY on `y` and a constant
  reference, NOT on `x`. Therefore `dvcon_eq/dx = 0` (the constraint Jacobian
  w.r.t. states, `Jcon_x`, is ZERO). Validate `Jcon_x == 0` (to FD tolerance)
  at the operating point. If `Jcon_x` is nonzero (state-dependent constraint),
  FAIL CLOSED with error `stateDependentConstraintUnsupported` — a state-
  dependent voltage constraint requires a different Schur derivation and is
  OUT OF SCOPE for this foundation.
- **Dimensions (Blocker 4):** `nr=size(Jyy,1); ny=size(Jyy,2)`;
  `free_rows = setdiff(1:nr, vcon_rows)`; `free_vars = setdiff(1:ny, vcon_vars)`.
- `A = Jxx - Jxy(:,free_vars) * (Jyy(free_rows,free_vars) \ Jyx(free_rows,:))`.
  (Because `Jcon_x = 0`, the eliminated constraint rows contribute no `x`
  coupling; the Schur stays the standard form with paired free sets.)
- Validation requires: `numel(vcon_vars)==numel(vcon_rows)`; `numel(free_rows)
  ==numel(free_vars)` (equal free cardinality); reduced `Jyy(free_rows,free_vars)`
  is SQUARE; indices unique, finite integers, in range; no duplicate ownership
  across devices; `vcon_eq` output dim matches `vcon_rows`; constraint Jacobian
  w.r.t. `vcon_vars` (`Jcon_y`) has FULL RANK; `Jcon_x == 0` (FD-verified);
  free Jyy sufficiently nonsingular for backslash; FAIL CLOSED; NEVER use `inv`
  or `pinv` to hide rank defects.
- **`free_y` and `vcon` are STRICTLY field-level mutually exclusive.** If a
  model supplies a NONEMPTY `free_y` AND ANY vcon field (`vcon_vars`,
  `vcon_rows`, OR `vcon_eq`), FAIL — no merge, no silent choice. When vcon is
  used, the COMPLETE vcon field set (`vcon_vars` + `vcon_rows` + `vcon_eq`) is
  required; partial vcon sets FAIL. There is NO "default-like free_y" exception:
  if vcon is present, `free_y` must be absent/empty; if `free_y` is present
  (nonempty), vcon must be entirely absent. The ONLY backward-compatible case
  is BOTH entirely absent (current `free_y=1:ny` path, bit-identical).
- Composite network owner replaces KCL rows with constraints EXACTLY ONCE.
- Constraint-variable indices NEED NOT equal residual-row indices.
- Full DAE evaluation may retain all y and replaced constraint rows.
- Elimination for Schur/SSSA uses paired `free_rows`/`free_vars` explicitly.
- Slack magnitude and angle constraints SEPARATELY identifiable; do NOT assume
  both always fixed.
- Tests cover: mismatched cardinality, rank-deficient constraints, nonmatching
  row/column indices, free_y+vcon conflict (any combination), partial vcon
  sets, one/two constraints, shuffled buses, exact Schur reconstruction,
  unchanged SG eigenvalues, AND state-dependent constraint
  (`Jcon_x != 0`) → `stateDependentConstraintUnsupported` fail-closed.

**Plug-in (`multimachine_ssa.m`):** after the existing `free_y` check
(L38-42), before the Schur (L44). Logic:
```
has_freey = isfield(model,'free_y') && ~isempty(model.free_y);
has_vcon  = isfield(model,'vcon_vars') || isfield(model,'vcon_rows') || isfield(model,'vcon_eq');
if has_freey && has_vcon
    error('multimachine_ssa:exclusiveOwnership', 'free_y and vcon_* are mutually exclusive.');
end
if has_vcon
    % require COMPLETE vcon set; validate cardinality/square/rank; paired formula
elseif has_freey
    free_vars = free_rows = model.free_y;   % legacy path (unchanged)
else
    free_vars = free_rows = 1:ny;           % current default (bit-identical)
end
```

## R1–R4 decision table (revised)

| Req | Decision | Backward-compat | Gate |
|-----|----------|-----------------|------|
| R1 | Typed provider (immutable, EXOGENOUS `fn(t,event_context)`); absent = exact legacy (no `u` arg on legacy path); two public fns `make_input_provider`/`eval_input_provider` | Bit-identical | strategy/classical equivalence, characterization, rollback |
| R2 | Model BUNDLE `opt.model_bundle` (bundle.ts = strategy+x0+y0+topology+mapping+metadata; bundle.sssa.model); capability-specific validators; model_bundle/model_fn mutually exclusive; provenance metadata | String dispatch unchanged | default_routing, simulate_general |
| R3 | Single composite owns y+KCL+mapping+constraint replacement; devices return positive `Iinj` only; composite forms `Ibus` then `g=YV-Ibus`; sign conversion `g_composite=-g_sg` ONLY in legacy equivalence test (no production adapter) | Additive (explicit request only) | strategy equivalence, characterization, sign-flip test |
| R4 | Separate vcon_vars/vcon_rows/vcon_eq; `nr=size(Jyy,1)`, `ny=size(Jyy,2)`; paired free_rows/free_vars; FIXED y-only `vcon_eq(y,ref)` with `Jcon_x==0` (state-dependent → fail-closed); full-rank `Jcon_y`; free_y and vcon STRICTLY field-level mutually exclusive (complete vcon set required); no inv/pinv | Both absent = bit-identical | sssa_contract (7), fd_convergence |

## State/input/y ownership diagram (revised)

```
x = [ x_dev1(1..nx1) ; x_dev2(1..nx2) ; ... ]   (ordered device list)
u = [ u_dev1(1..nu1) ; u_dev2(1..nu2) ; ... ]   (nu_k may be 0)
y = [ Re(V1);Im(V1);Re(V2);Im(V2);...;Re(Vnb);Im(Vnb) ]  (bus-contiguous, ONE owner)

COMPOSITE canonical KCL:  Ibus = sum_k(Iinj_dev_k)  (by mapped bus);
                          g = Y*V - Ibus                       [YV-I]
SG legacy KCL:            g = -Y*V + sum_k(Iinj_dev_k)         [-YV+I]   (= -g_composite)
  Iinj_dev_k = device_k.current_injection(t, x_dev_k, y, u_dev_k, event_context)
              [complex, positive INTO network; devices return positive injection ONLY]
  f_dev_k    = device_k.f(t, x_dev_k, y, u_dev_k, event_context)
  (Y/topology composite-owned; devices never receive Y; no production sign adapter)

Voltage constraints (R4) — FIXED y-only:
  nr=size(Jyy,1); ny=size(Jyy,2)
  vcon_eq = vcon_eq(y, constant_reference)   ⇒  dvcon_eq/dx = 0  (Jcon_x == 0, FD-verified)
  vcon_vars ⊂ [1..ny]   (constrained variables; slack mag/angle separately identifiable)
  vcon_rows ⊂ [1..nr]   (KCL rows REPLACED; need not equal vcon_vars)
  free_vars = setdiff(1:ny, vcon_vars); free_rows = setdiff(1:nr, vcon_rows)
  |free_vars| == |free_rows|  (required; reduced Jyy square)
  Jcon_y = dvcon_eq/dvcon_vars  must be FULL RANK;  Jcon_x must be ZERO
  (state-dependent constraint ⇒ stateDependentConstraintUnsupported, OUT OF SCOPE)
  A = Jxx - Jxy(:,free_vars)*(Jyy(free_rows,free_vars)\Jyx(free_rows,:))   [SQUARE]
```

## Files (revised — Blockers 5 & 6)

### NEW (production `+stability/`)
- `+stability/make_input_provider.m` — provider builder (Blocker 5). Returns
  immutable provider struct.
- `+stability/eval_input_provider.m` — pure evaluation entry point; validates
  type/size/finite on every call (Blocker 5).
- `+stability/validate_ts_bundle.m` — validates bundle.ts (strategy via
  internal validate_ts_strategy, x0, y0, topology, mapping, metadata) (Blocker 2).
- `+stability/validate_ts_strategy.m` — INTERNAL step-layer strategy validator
  (required fields, arity, classical dae_g=[]) (Blocker 2).
- `+stability/validate_sssa_model.m` — SSSA capability validator (Blocker 2).
- `+stability/composite_dae.m` — composite assembler (single owner; devices
  return positive Iinj; forms Ibus then `g=YV-Ibus`).

### NEW (test-only, NOT in `+stability` or production `+cases` — Blocker 6)
- `tests/+fixtures/synthetic_linear_generator.m` — 2-state linear generator
  bundle (bundle.ts + bundle.sssa.model) for R2/R3 tests.
- `tests/+fixtures/synthetic_composite_cases.m` — multi-device composite
  fixtures (2-bus, 3-bus, shuffled IDs) for R3.
- `tests/+fixtures/synthetic_slack_case.m` — 2-bus 1-gen slack-constrained
  fixture for R4.
- Tests reference these via `fixtures.<name>` (the `+fixtures` package is on
  the test path; called as `fixtures.synthetic_linear_generator`, NOT
  `tests.fixtures.*`).

### NEW tests
- `tests/test_r1_input_provider.m`, `test_r2_model_dispatch.m`,
  `test_r3_composite_dae.m`, `test_r4_voltage_constraints.m`.

### NEW docs
- `docs/project/plans/ibr_interface_foundation.md` — this design.
- `docs/project/handoffs/TRACK_A_IBR_INTERFACE_FOUNDATION.md` — handoff.

### MODIFIED (mechanical, separate commits from new behavior)
- `+stability/ts_step_kernel.m` — provider-aware path SEPARATE from legacy;
  legacy path unchanged when provider absent.
- `+stability/ts_model_strategy.m` — provider-aware closures for the provider
  path ONLY; add `otherwise` prebuilt-strategy path.
- `+stability/ts_adaptive_driver.m` — pass `t`+event_context to kernel on
  provider path; sample `u` at t, t+h/2, t+h; legacy path unchanged.
- `+stability/ts_simulate.m` — TS dispatch precedence (opt.model_bundle >
  opt.model_fn > string) before L50; provenance metadata.
- `+stability/ts_simulate_emf6.m`, `ts_simulate_padiyar_model11.m` — pass
  t/event_context on provider path.
- `+stability/multimachine_ssa.m` — vcon_vars/vcon_rows/vcon_eq with
  `nr`/`ny` dims; free_y and vcon STRICTLY field-level mutually exclusive
  (complete vcon set required); both absent = bit-identical.
- `+stability/multicase_sssa.m` — SSSA dispatch precedence (bundle.sssa.model
  > opt.model_fn > string).

### FORBIDDEN
- `+ibr/**`, `docs/ibr/**`, `tests/test_ibr_*`, `scripts/ibr/**`.
- Test-only synthetic files in `+stability/` or production `+cases/`
  (Blocker 6 — they go in `tests/+fixtures/`).
- `AGENTS.md`, `CLAUDE.md`, `docs/project/TRACK_COORDINATION.md`,
  `docs/project/AGENT_HANDOFF.md`.
- Track B worktree. Production catalog IBR registration; current-limiter
  integration; adaptive default switch; parameter/tolerance/source-data
  changes; external solver; push/merge of main.

## Per-phase commits (mechanical separate from new behavior)

0. **Baseline** — full regression on `f59076f` (0 failed/0 incomplete). No change.
1. **Design doc** — `ibr_interface_foundation.md`.
2. **R1 mechanical** — kernel/strategy/driver absorb provider path (legacy
   untouched, exogenous `fn(t,event_context)`, endpoints t/t+h/2/t+h). Gate:
   strategy/classical equivalence AbsTol=0, characterization, rollback.
3. **R1 behavior** — `make_input_provider.m`, `eval_input_provider.m`,
   `tests/+fixtures` (if first use), `test_r1_input_provider.m`.
4. **R2 mechanical** — model_bundle/model_fn precedence + mutual-exclusion +
   provenance metadata; capability-specific validators. Gate: default_routing,
   simulate_general.
5. **R2 behavior** — `validate_ts_bundle.m`, `validate_ts_strategy.m`,
   `validate_sssa_model.m`, `tests/+fixtures/synthetic_linear_generator.m`,
   `test_r2_model_dispatch.m`.
6. **R3** — `composite_dae.m` (devices return positive Iinj; composite forms
   Ibus then `g=YV-Ibus`; sign conversion ONLY in legacy equivalence test),
   `tests/+fixtures/synthetic_composite_cases.m`, `test_r3_composite_dae.m`.
7. **R4** — `multimachine_ssa.m` vcon (nr/ny, STRICTLY field-level mutually
   exclusive with free_y, complete vcon set required),
   `tests/+fixtures/synthetic_slack_case.m`, `test_r4_voltage_constraints.m`.
8. **Regression + scope + docs** — full regression, scope audit (no +ibr ref,
   no inv(Jyy), no test-only files in +stability/+cases), handoff.

## Synthetic fixtures & oracles (equation-sourced, test-only)

- **R1:** linear ODE `dx/dt=A*x+B*u(t)`, `u(t)=sin(2t)` EXOGENOUS, closed form
  via Duhamel.
- **R2:** classical ng=1 as a BUNDLE (ts_strategy + sssa_model).
- **R3:** two synthetic linear generators; synthetic one-device equivalence
  (composite path vs direct-call of the SAME fixture, sign-flip residual
  relation); NOT a claim of reproducing the real SG classical engine. KCL
  `Y*V-Ibus=0` at every bus. Real SG behavior preserved by separate AbsTol=0
  legacy regressions (unchanged legacy path).
- **R4:** 2-bus 1-gen slack-constrained; reduced `Jyy` square; eigenvalues
  analytic from linearized swing. Source: project SSSA contract §2; Sauer-Pai
  §6.7.

## Source/derivation plan (revised)

| Invariant | Source |
|-----------|--------|
| Trapezoidal `x_{n+1}=x_n+h/2*(f0+f1)` | `ts_step_kernel.m`; adaptive_ts_track_a.md |
| LTE `e=(x_halfhalf-x_full)/3` | adaptive_ts_track_a.md; `test_ts_adaptive_lte.m` |
| SG KCL `g=-Y*V+sum(I_inj)` (`-YV+I`) | padiyar L140; emf6 L169 (VERIFIED) |
| Composite canonical KCL `g=Y*V-Ibus` (`YV-I`); devices return positive Iinj | user directive (new canonical); sign conversion `g_composite=-g_sg` ONLY in legacy equivalence test |
| Current INTO network | `kundur_book_network.m`; `classical_dae.m:135` |
| Schur `A=Jxx-Jxy*(Jyy\Jyx)` (backslash) | `docs/SSSA_CONTRACT.md` §2; `multimachine_ssa.m:44` |
| `inv(Jyy)` forbidden | `test_sssa_contract.m` guard |
| Voltage constraint replaces KCL row (not naive removal) | Sauer-Pai §6.7; directive R4 warning |
| Exogenous input `fn(t,event_context)`; left/right endpoint semantics | user directive (Blocker 1) |
| `nr=size(Jyy,1)`, `ny=size(Jyy,2)`; free_y/vcon STRICTLY field-level mutually exclusive; vcon FIXED y-only (`Jcon_x==0`) | user directive (Blocker 4, Revision 1) |
| Model bundle `opt.model_bundle` (ts: strategy+x0+y0+topology+mapping+metadata; sssa.model) | user directive (Blocker 1, revised) |
| Frozen device signatures `f/current_injection/reconstruct(t,x_dev,y,u_dev,event_context)`; nx slicing; ns optional | user directive (Revision 2) |
| Synthetic one-device equivalence (NOT real-engine reproduction); real SG via separate AbsTol=0 legacy regressions | user directive (Revision 3) |
| Duhamel (R1 oracle) | standard ODE theory (synthetic) |
| `y=[Re(V1),Im(V1),...]` interleaved | `SSSA_CONTRACT.md` §1; all DAEs |

**Fence:** 8 unsourced VSG equations stay in `+ibr/` (Track B). NOT referenced,
tested, or promoted.

## Verification gates

- Full regression: 0 failed / 0 incomplete (fresh, each phase).
- SG fixed paths bit-identical where contract is mechanical (AbsTol=0):
  `test_ts_strategy_equivalence`, `test_ts_classical_strategy_equivalence`,
  `test_ts_characterization_fixed`.
- Classical/Padiyar/EMF6 SSSA + TS remain green.
- Production default stays FIXED; adaptive explicit (`test_ts_default_routing`).
- One network residual owner; one canonical kernel.
- Composite KCL passes bus-by-bus; devices return positive Iinj only;
  `g_composite=-g_sg` asserted ONLY in legacy equivalence test (no production
  adapter).
- Algebraic ownership explicit; Schur square; free_y/vcon STRICTLY field-level
  mutually exclusive (complete vcon set required); vcon is FIXED y-only
  (`Jcon_x == 0` FD-verified; state-dependent → fail-closed); no inv/pinv
  hiding rank defects.
- Input callbacks deterministic + rollback-safe; exogenous `fn(t,event_context)`
  (no state dependence); left/right endpoint semantics.
- Synthetic dispatch passes; no production `+ibr` reference.
- No external solver (`test_no_external_solver_dependency`).
- No test-only synthetic files in `+stability/` or production `+cases/`
  (they live in `tests/+fixtures/`, called as `fixtures.*`).
- No Track B/policy files modified.
- Documentation matches code.
- Final `origin/main` race check (must still be `f59076f`).

## Stop conditions

- State/input/y ordering needs a new semantic decision ⇒ stop, ask.
- Algebraic ownership cannot produce a square, full-rank Schur ⇒ stop, ask.
- A voltage constraint is state-dependent (`Jcon_x != 0`) ⇒ fail closed with
  `stateDependentConstraintUnsupported` (out of scope; different Schur
  derivation required) ⇒ stop, report.
- An interface change alters existing SG numerical behavior (AbsTol>0 on the
  legacy/provider-absent path) ⇒ stop, root-cause; never raise tolerance.
- A required equation lacks a verified source/derivation ⇒ stop, ask.
- A change overlaps Track B/shared ownership ⇒ stop, ask.
- Agreement improves only after parameter/tolerance changes ⇒ stop, ask.
- `origin/main` advances during verification ⇒ stop, mark stale, re-verify.
- Any action expands beyond the approved allowlist ⇒ stop, ask.

## Non-goals (explicit)

- `IBR_PRODUCTION_INTEGRATION_READY = NOT_STARTED`.
- No `+ibr/**`; no IBR catalog entry; no current-limiter integration.
- No adaptive default switch; no parameter/tolerance/source-data changes.
- No external solver; no push/merge of main; no Track B touch.
- No promotion of the 8 unsourced VSG equations.
- No claim of residual bit-identity between composite (`YV-I`) and SG (`-YV+I`);
  no production device sign adapter (sign conversion is test-only).
- No top-level `opt.strategy` (replaced by `opt.model_bundle`); `ts_strategy`
  stays internal to the step layer.
- No state-dependent voltage constraints (R4 is FIXED y-only; `Jcon_x != 0` ⇒
  fail-closed, out of scope).
- No claim that the composite reproduces the real SG classical engine (R3
  equivalence is synthetic-vs-synthetic; real SG preserved by separate AbsTol=0
  legacy regressions).
