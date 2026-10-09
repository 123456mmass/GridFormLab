# NE39 source-aware SCR method contract

**Owner of this contract:** the SCR metric module only —
`+stability/ibr_scr_metrics.m`, its helper `+stability/scr_source_thevenin.m`,
and the tests `tests/test_ne39_scr_source_aware.m`. Callers
(`ibr_config_selector`, `ibr_candidate_evaluate`, `agsi_reference_terms`, the
selector/transition certificate) are owned elsewhere and integrate the new
options; nothing in this contract edits them.

**Status:** the legacy path remains the default and its *code path* is
unchanged. Its **numeric behaviour** is unchanged for IEEE14 and for NE39, and
in general for any case with no branch that is both off-nominal-tapped and
charged — but it is **not** a no-op everywhere: the shared branch/tap/shunt
stamp fix in §6 is an **intentional correctness change** that WILL move the
value for a case that has such a branch. So "legacy unchanged" is qualified
here to IEEE14 / NE39 / no-tapped-plus-charged cases; it is not a blanket
guarantee. The new `source_aware` path is **opt-in** and is the correct way to
measure New England 5 SG + 5 IBR grid strength. Every claim below is pinned by
a test in `tests/test_ne39_scr_source_aware.m`.

---

## 1. What was wrong with the old number

The pre-existing metric ground every POWER-FLOW slack bus (short-circuited it),
so `Zth = 0` and `SCR = Inf` at the slack: the slack was treated as an ideal
infinite reactive source, and every other source was ignored. On a case whose
slack *is* a real machine (NE39 bus 31 is `nuke01`) that is a false strength
credit. The metric also returned
`scr_profile = 'not_applicable_full_state_source_model'` for the
`eecon49_dual` family, i.e. it *skipped* the only IBR family the project uses —
so there was **no measured SCR at all** for NE39 converters.

## 2. The source-aware model (the fix)

`opt.scr_source_model = 'source_aware'` selects the new path. Model, with the
step that differs from the legacy path in bold:

1. Build the **network** admittance `Ynet` = branches + bus shunts, **no**
   machine, **no** load (the same `build_ybus_network` stamp; see §6).
2. **Place each ONLINE voltage source behind its own impedance as a shunt
   `1/Z` at its bus**, and do **not** ground any slack.
   A voltage source behind a series `Z` to its internal node is, for the
   Thevenin (internal EMFs zeroed, prefault voltage applied at the PCC), exactly
   a shunt `1/Z`. This is the *same* representation the classical machine
   already uses in its own network solve (`stability.classical_dae`:
   `yg = 1/(1i*Xdp)` added at the generator bus), so the two agree by
   construction. No bus is an ideal infinite source.
   - **SG** sources: `Z = 1i * Xdp`, `Xdp` from (in order) `opt.sg_sources`,
     `resources(k).dynamic_params.Xdp`, or `case_data.machines.units(bus).Xdp`.
     All three NE39 sources are the SAME system-base number
     (`ne39_machine_parameters`: `Xdp_sys = Xdp_RTS*(100/Smva_RTS)`).
     `H` and `D` are **not** impedances and are never read here.
   - **Converters**: a GFL converter is a current source and is **not** a
     Thevenin voltage source. A GFM converter enters ONLY when the caller
     supplies `opt.ibr_source_impedance.(model_id)` (default OFF). A
     current-limited IBR is never replaced by an ideal voltage source.
3. `Zth_k = (Yaug^{-1})_{kk}` solved as `Yaug*vz = e_k`, `vz(k)` — **never
   `inv`/`pinv`** — restricted to the PCC's **island**.
4. `Ssc_MVA = |V_prefault|^2 / |Zth_pu| * Sbase`, `SCR = Ssc_MVA / S_rated_MVA`
   with `S_rated = resources(k).ratings.Mbase`. **`SCR` never uses an
   instantaneous `Pg` as the denominator.**

## 3. Scope of the number — what it is NOT

`scr.validity_scope` is published on every return path. It states, and this
contract repeats, that the number is a **transient-reactance (`X'd`) network
strength**:

- It is **not** an IEC 60909 subtransient fault level. There is no `X''d`, no
  DC offset, no fault shunt, and no network capacitance. Available data is
  `X'd` only, so the honest label is "transient equivalent", not "subtransient".
- A fault shunt or line capacitance is never allowed to masquerade as source
  strength, so neither is included.
- It is a **screening metric**; it does **not** certify multi-infeed stability.
  That remains the job of the full-KCL SSSA (and the equilibrium / limit /
  synchronism gates), which are separate conditions and are not folded into a
  single severity score.

### 3.1 Synchronous-machine SCR is a DIFFERENT quantity (not this metric)

The synchronous-machine **SCR** is a machine nameplate/test quantity, at rated
speed:

> SCR = (field current needed to produce rated armature voltage on the air-gap
> line of the open-circuit saturation curve) / (field current needed to produce
> rated armature current under a sustained armature-terminal short circuit)
> = 1 / `Xd` (unsaturated).

In-repo primary source: IEEE Std 1110-2002, *IEEE Guide for Synchronous
Generator Modeling Practices*, §7.2.1 (`tmp/pdfscan/ALL_1110-2002_.txt`): "the
per-unit unsaturated value, Ldu, is the ratio of the field current required to
produce rated armature current under sustained armature terminal short-circuit,
to the field current required to produce rated armature voltage on the air-gap
line extrapolation of the open-circuit saturation curve." It is defined on the
MACHINE's own base and involves field currents, an OCC and an SCC.

### 3.2 IBR grid-strength SCR is a NETWORK quantity (this metric)

At the converter PCC this metric is `Ssc / S_rated`, `Ssc = |V_pf|^2 / |Zth|`.
There are **no field currents and no OCC/SCC** — an inverter has no field
winding. The convention (all sources shorted so each contributes a shunt
admittance; a GFL converter contributes nothing; an explicit resource rating) is
stated in-repo at `+ai/miescr_metrics.m` and, for the WECC strong-grid profile,
`docs/project/IEEE14_IBR_GFL_WECC_PROVENANCE.md` ("the network Ybus with the REF
source shorted, `Zth` from a linear solve (never `inv`/`pinv`), and explicit
resource `Mbase`").

### 3.3 An SG enters here as a SOURCE IMPEDANCE, never as an SG machine SCR

When an SG appears in this metric it is only a voltage source behind its
transient reactance `X'd` — a `1/Z` shunt contributing to the network Thevenin
(§2). That contribution is **not** the SG's machine SCR. This section exists to
stop the two being conflated: the SG's *machine* SCR (`1/Xd`, from its OCC/SCC,
machine base) and its *network contribution* (a source behind `X'd`, system
base) are different quantities.

### 3.4 `Xd` vs `X'd` vs `X''d`, and the effect on the gate

- `Xd` (steady-state, unsaturated) is the basis of the SG machine SCR (§3.1).
- `X'd` (transient) is what the project classical machine and this metric use;
  it gives a smaller source impedance — a *stronger* source — than `Xd`.
- `X''d` (subtransient) gives a still smaller impedance and is the correct basis
  for a fault-current level. The project carries **no `X''d`** (the NE39 `Xdp` is
  `PROJECT_DERIVED` from RTS-1996 Table 15 *transient* data), so a subtransient
  fault level is never claimed.
- Effect on the gate: the reactance choice changes the measured IBR
  grid-strength SCR through the source impedance. It is neither an SG machine
  SCR nor an IEC subtransient fault level. Because the IBR family in use
  (`eecon49_dual`) is `threshold_applicable = false` (§4), the number is
  reported, not gated, so today the `Xd`/`X'd`/`X''d` distinction does not move
  an accept/reject decision for NE39; it would matter only for a family with
  `threshold_applicable = true`, and then a sensitivity run is required before
  any threshold claim.

### 3.5 Current-limited converters are not ideal sources

A GFL converter is a current source bounded by its `Imax` (~1–1.2 pu), so its
fault-current contribution is limited; it stamps **no** Thevenin admittance and
is never modelled as an ideal voltage source (`+ai/miescr_metrics.m`). A GFM
converter enters only behind the caller-supplied coupling impedance. Replacing a
current-limited converter with an ideal source would overstate grid strength.

**Cited gaps (not fabricated).** MCP `9router` tools are not available in this
session, so every citation above is in-repo. The NE39 machines have no OCC/SCC
and no `Xd`/`X''d` data in-repo, so an **SG machine SCR cannot be computed for
the NE39 units from this repository** and is not reported; the metric reports the
IBR grid-strength SCR only.

## 4. Metric vs threshold applicability (kept separate)

The **measurement** and the **WECC `SCR > 3` threshold** are two things.

- The metric is **measured for every eligible online IBR**, including the
  `eecon49_dual` family. `scr.method`, `scr.validity_scope`, and the per-resource
  `SCR`/`Ssc_MVA`/`Zth` exist regardless of applicability.
- Applicability is reported separately: `pr.threshold_applicable` is false for
  the full-state `eecon49_dual` family (profile
  `not_applicable_full_state_source_model`) and true otherwise. For a
  non-applicable family the SCR is reported but does **not** gate
  (`pr.pass = true`); the WECC `SCR > 3` rule is **not** asserted as an EECON49
  requirement without a `PROJECT_DERIVED` label and a sensitivity study. The
  WECC number is a screening heuristic, not a project requirement.

## 5. Failure modes (all fail closed, never silently pass)

- **No-source island.** Islands are the connected components of the **branch
  graph** (an off-diagonal `|Ynet_ij| > 0` is an edge). A PCC whose island holds
  no ONLINE modelled source is `status = 'no_source_island'` and fails closed —
  this is a **physical** source-availability check, done *before* and *in
  addition to* any numerical `rcond`/residual test. An un-sourced island never
  certifies strong because some submatrix happened to be well conditioned.
- **Singular island** (`rcond < 1e-12`) or a solve residual `> 1e-6`:
  `status = 'invalid'`, fail closed.
- **Missing / non-positive rating**: SCR undefined, fail closed.
- The global `scr.is_singular` flag is **not** set by the per-island check (that
  would fail-close every candidate); island failures are reported per resource.

## 6. Branch / tap / shunt stamp (corrected)

The network stamp was checked independently against the canonical MATPOWER
`makeYbus` and the project's own `chronology_branch_stamp`
(`ts_simulate_ibr_hybrid`). The from-side diagonal must be

```
Y(ii,ii) += (yser + j*b/2) / (a*conj(a))     % MATPOWER Yff
Y(jj,jj) += yser + j*b/2
Y(ii,jj) -= yser/conj(a)
Y(jj,ii) -= yser/a
```

i.e. the from-end charging `b/2` is divided by `|a|^2` **together with** the
series admittance. The previous `build_ybus_network` divided only `yser`, which
is wrong whenever a branch is both off-nominal-tapped (col 9 ≠ 1) **and**
charged (col 5 ≠ 0). This is an **intentional correctness change**, not a
cosmetic one: not reverting the (correct) formula was a deliberate decision.
IEEE14 and NE39 each have **zero** such branches (NE39: 11 tapped branches, all
with `b = 0`; 34 charged branches, all at nominal tap; zero overlap), so for both
the fix is a numerical no-op and the existing IEEE14 SCR/selector suites stay
green. It matters for any case that *does* have a tapped-plus-charged branch
(e.g. a tapped transformer with charging), where the corrected value is the one
to use; for such a case the legacy numeric result is intentionally different.

The bus shunt is `diag((GS + j*BS)/baseMVA)` from `bus(:,5)`/`bus(:,6)`
(MW/MVAr at V = 1). No load admittance is folded in — pure network strength.

**Note for the caller/other owners:** the same `yser/(a*conj(a)) + j*b/2`
pattern (without the `/|a|^2` on `b/2`) also appears in
`classical_dae.m`, `composite_dae.m`, `ibr_selector_table.m`, `ts_simulate.m`,
`case14_ts_classical.m` and `ts_simulate_ibr_hybrid.m` (its shared
`build_ybus` helper, *not* its `chronology_branch_stamp`). Those are outside this
module and are flagged, not changed here.

## 7. Caching / invalidation (fingerprint versioning)

`scr.fingerprint` is deterministic and is the cache key. Two versions exist:

- **`scr_v1`** — the legacy key, kept **verbatim** for compatibility: `Sbase`,
  the threshold, the network `rcond`, the resource id list and every
  per-resource `SCR`. The legacy path's key is byte-identical to before.
- **`scr_v2_source_aware`** — the source-aware key, a SHA-256 digest (a
  deterministic sum-based signature if no JVM is present) over: the method, the
  validity scope, `Sbase`/threshold, the **network `Ybus`** and the **augmented
  `Yaug`** (so topology / line / shunt changes flip it), every **source
  impedance and its online/modelled status**, the **island membership**, and
  each **resource's id / bus / rated MVA / online flag**.

The source-aware key therefore changes when the method, a source impedance or
its online status, the topology, a rating, or the scope changes — **even when
every scalar SCR is unchanged**. That exact case is pinned by
`test_fingerprint_same_scr_different_sources`, which swaps two source reactances
between two buses that are symmetric to the PCC, so the parallel Thevenin and
every SCR are identical while the configuration differs. `scr.source_list`
echoes every modelled source (bus, kind, `Z_pu`, online, modelled) and is the
input the source part of the key is built from.

## 8. ABI

Signature is unchanged: `scr = stability.ibr_scr_metrics(case_data, resources,
topology, opt)`.

New `opt` (all optional; **absent ⇒ the legacy path, whose code is unchanged and
whose numeric behaviour is identical for IEEE14 and NE39 — see §6 for the
general-case stamp qualification**):

| field | meaning |
| --- | --- |
| `opt.scr_source_model` | `'legacy_slack_grounding'` (default) \| `'source_aware'` |
| `opt.sg_sources` | struct array `{bus_id, Xdp_pu, online}`; authoritative SG list |
| `opt.ibr_source_impedance` | struct keyed by `model_id`, value `[R X]` or complex; default absent ⇒ IBR are not voltage sources |
| `opt.bus_voltages`, `opt.V0_per_bus` | prefault `|V|` (as before) |
| `opt.scr_threshold` | threshold (as before) |

New output: `scr.method`, `scr.validity_scope`, `scr.source_list`, `scr.islands`
(`{id, members, has_source}`), `scr.Yaug`, `scr.n_sources_online`. Per-resource
adds `pcc_bus`, `source_available`, `status`
(`'valid' | 'no_source_island' | 'invalid'`), `prefault_V_pu`,
`threshold_applicable`.

## 9. Tests

`tests/test_ne39_scr_source_aware.m` (all independent, no tolerance relaxation):

- two-bus and three-bus `Zth` against closed-form hand values;
- reference-bus invariance (moving the slack designation changes nothing);
- finite SG impedance gives a finite SCR strictly below the legacy `Inf`;
- rating scaling (`SCR ∝ 1/S_rated`);
- source outage raises `Zth` / lowers `SCR`;
- island without a source fails closed while the sourced island still solves;
- branch/tap/shunt stamp re-derived by an independent congruence oracle
  (`Yb = T*Yprim*T'`, `T = diag(1/conj(a), 1)`);
- fingerprint invalidation on status / rating / topology / source-impedance
  change; the legacy key stays `scr_v1`, the source-aware key is
  `scr_v2_source_aware` and differs from legacy on the same network;
  `test_fingerprint_same_scr_different_sources` proves the key differs for a
  configuration change that leaves every scalar SCR equal;
- `method` + `validity_scope` on every return path; bad `scr_source_model`
  rejected;
- `opt.ibr_source_impedance` opt-in changes the source list and lowers `Zth`;
- legacy default profile/behaviour unchanged; no `inv`/`pinv`;
- real `cases.case_ne39()` 5 SG + 5 IBR, `Xdp` read from
  `case_data.machines.units`, every IBR bus finite and non-gated; tripping all
  SG makes every IBR `no_source_island`.
