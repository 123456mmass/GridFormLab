# DOC-2026-08-26-01 — Thai report declared a state no equation governed

- **Status:** RESOLVED
- **Area:** `docs/source/report_ieee14_switch_th_rev2.tex` (report prose and equations)
- **Branch / commit:** `main`, found at `de65eb7`, fixed in the following commit
- **Environment:** Windows 11, XeLaTeX (TeX Live), MATLAB batch for the oracle probe

## Symptom

The Thai switching report listed the Thevenin DC-source current as state index 17
and its active-state counts as 10 (GFL) / 11 (GFM), and its shared-power-stage
subsection printed a `\dot V_{dc}` row that substituted the **algebraic** source
law:

```
\dot{V}_{dc} = \tfrac{1}{C}\!\left[\tfrac{E_{dc}-V_{dc}}{R_{dc}}
               -\frac{P_{ac}}{V_{dc}}-\frac{I_{ch}}{}\right]
```

`rg '\\tau_s' docs/source/report_ieee14_switch_th_rev2.tex` returned **zero
matches**. No equation anywhere in the report governed the state the report's own
table declared, and the substituted closure is the $\tau_s=0$ limit rather than
the model that runs.

The same staleness ran through three further places:

1. The boundedness argument `V_{dc}(t) \le \max(V_{dc}(0),E_{dc})` was still
   asserted from "every term of row (3) is negative when $P_{ac}\ge0$".
2. `\S`small-signal spectrum predicted **four real roots just above**
   $-100~\mathrm{s^{-1}}$ from $\lambda_{dc}=-100+10P_{ac}/V_{dc}^2$, and read the
   participation column as $1.000$ on $V_{dc}$ — while the same section
   `\input`s the generated table that prints **four complex conjugate pairs** at
   $-95.56$ to $-98.41$ with $\zeta\approx0.707$ near $15$~Hz.
3. `eq:oneway` was written over $\max_{i\neq V_{dc}}|\partial f_i/\partial
   V_{dc}|$ with a measured $17.65$ for the DC row, both belonging to the
   single-DC-coordinate revision.

The Thai report therefore contradicted (a) its own state table, (b) the table it
prints, and (c) the production model, inside one document.

## Reproduction

```
rg -n '\\tau_s' docs/source/report_ieee14_switch_th_rev2.tex        # 0 matches
rg -n 'I_{dc}'  docs/source/report_ieee14_switch_th_rev2.tex        # index 17 declared
sed -n '809p'   docs/source/report_ieee14_switch_th_rev2.tex        # algebraic row (3)
sed -n '1253p'  docs/source/report_ieee14_switch_th_rev2.tex        # -100 + 10 P/V^2
grep -n '0.707' docs/source/figures/switch_ieee14/sssa_modes_n1.tex # the table it prints
```

## Root cause, with evidence

The Thai report was corrected twice by different pieces of work and each pass
owned a different part of the file. `DOC-2026-08-22-02` replaced the Thai
"$-10~\mathrm{s^{-1}}$" sentence with the predict-then-measure argument for the
**resistive** source, which was correct at that time. `NUM-2026-08-20-01` and the
`GATE-2026-08-25` sequence then added the source-current state and rebuilt the
English report with a new `\S`Non-ideal DC source subsection (`sec:dcsource`,
`eq:dcsrc`, `eq:dcdisc`, `eq:dcblock`, `eq:dctau`, `eq:dclam`) — but on the Thai
side only the **state table**, the state vector, the active sets and the reduction
paragraph were updated. The equations, the boundedness proof and the small-signal
DC prose were not, and nothing in the toolchain cross-checks an align row against
the sentence beneath it or against a `\input`-ed generated table.

That the Thai file has no `sec:dcsource` and no `eq:dcblock` while the English
file has both is the structural fingerprint of the half-applied correction.

## Falsified en route

- **"The English report's numbers are the safe source to translate from."**
  Two of them could not be reproduced. `+ibr/dc_source_thevenin_params.m:68`
  states a realised discriminant margin of `2.32`; the English report states
  `2.15`; measurement on the configuration whose modal table the report prints
  gives `2.0725 / 2.0811 / 2.0929 / 2.1454` for IBR8/IBR3/IBR2/IBR6. The code
  comment's value matches no converter (it corresponds to `Pac0 = 0.85`, which is
  `P_ref`, not `Pac0`), and the report quoted the **least binding** of the four.
  Both were replaced by the measured range with its dispatch named.
- **"`E_dc = 1.0453` pu is the dispatched value."** `x0(11) = dcp.Idc0` and
  `Idc0 = Pac0/Vdc0` (`+ibr/gfl_eecon49_full_model.m:66`, `:244` of the params
  helper), so `Pac0` is recoverable exactly from the assembled initial state. On
  `eecon49_figure4` it is `0.268929 / 0.290190 / 0.319192 / 0.447748`, giving
  `E_dc = 1.026893 / 1.029019 / 1.031919 / 1.044775` — a maximum of `1.0448`, not
  `1.0453`. The single unattributed value was replaced in both reports by the
  measured range over the four links.
- **"The first feasible row of the selector table is the one the `n1` table
  prints."** It is not. All four feasible `n_gfm_required=1` rows write to
  `sssa_modes_n1.tex`, so the surviving file is the **last** of them; its header
  records `selected=2 reference=2` while `find([cfgs.feasible],1)` returns
  `selected=5`. Measuring on the wrong row gave `max|\partial f_{DC}/\partial
  x_{AC}| = 35.0558`, which would have contradicted the English report's `33.4`
  for no reason. Re-measured on `pick(end)` the value is `33.4019`, confirming the
  report.
- **"The monotone bound survives with an extra state."** It does not, and this is
  a statement about the model rather than about which revision is tidier. Row (3)
  reads $I_{dc}$, a state that lags its own static characteristic, so at an
  instant with $V_{dc}>E_{dc}$ the source row drives $\dot I_{dc}<0$ but $I_{dc}$
  itself may still exceed $P_{ac}/V_{dc}$, giving $\dot V_{dc}>0$. The
  $\zeta=1/\sqrt2$ step response overshoots by $4.3214\%$ (computed), which is the
  same fact in the frequency domain. `+ibr/dc_source_thevenin_params.m:123-134`
  still asserts the bound — see *Limitations*.

## Independent oracle

A throw-away probe (`chk_dc_numbers_tmp.m`, not committed) rebuilt the assembled
model through the same authenticated producer the table generator uses, then
measured, on `selected=[2] reference=2`:

| Claim | Measured |
|---|---|
| `physical_A` size | `40x40`, `common_gfm_vsg_angle_quotient` |
| DC coordinates | 8 (`V_dc`,`I_dc` per converter), 32 AC |
| $\max_{i\in AC}\max_{j\in\{V_{dc},I_{dc}\}}|\partial f_i/\partial x_j|$ | `0` exactly |
| $\max|\partial f_{DC}/\partial x_{AC}|$ | `33.4019` at `IBR6:V_dc <- IBR6:gfl_xi_Id` |
| DC sub-matrix off-block entries | `0` (block-diagonal by converter) |
| participation of each DC pair | `0.5000 / 0.5000`, all else `0.0000` |
| the four pairs | `-98.406155±98.380337`, `-96.455579±96.325245`, `-96.346517±96.207876`, `-95.555521±95.348575` |
| their $f$ / $\zeta$ | `15.175`–`15.658` Hz, `0.707200`–`0.707873` |
| $\tau_s$ maximally-flat | `5.0009`–`5.0025` ms per converter; declared `5.000` ms |
| $\tau_s$ trace bound `C V^2/Pac0` | `223.34`–`371.85` ms |
| CPL margin `V^2/(Rdc Pac0)` | `22.33`–`37.18` |
| $\lambda_{dc}$ ($\tau_s\to0$ limit) | `-95.52`–`-97.31` s$^{-1}$ |

Every number written into the Thai report comes from this table or from the
derivation recorded in `+ibr/dc_source_thevenin_params.m`. None was carried over
from the English prose unverified.

## Fix

`docs/source/report_ieee14_switch_th_rev2.tex`

- Shared power stage retitled to states `1--3 และ 17`; row (3) now reads
  $C\dot V_{dc}=I_{dc}-P_{ac}/V_{dc}-I_{ch}$ and a new row (4) is
  $\tau_s\dot I_{dc}=(E_{dc}-V_{dc})/R_{dc}-I_{dc}$; the glossary gains
  $\tau_s=L_s/R_{dc}$.
- The closure paragraph derives $I_{dc}$ as a state from the inductance of the
  source circuit and states the exact $\tau_s\to0$ degeneracy, so a reader
  comparing revisions compares a model with its own limit.
- Two derivation paragraphs ported from the production helper: $R_{dc}$ from the
  declared regulation $\varepsilon$ bounded above by the reachability condition
  (`eq:dcdisc`), and $\tau_s$ from the maximally-flat criterion bounded on both
  sides (`eq:dcblock`, `eq:dctau`) with the degeneracy statement.
- The monotone bound is replaced by *what survives* — the mechanism, not the
  inequality — with the measured $4.3\%$ overshoot stated.
- A stiffness paragraph (`eq:dclam`) matching the English report.
- The chopper paragraph no longer opens by referring to a bound that has been
  removed; its measured per-arm evidence is unchanged.
- Small-signal section: the DC family is four conjugate pairs near $15$ Hz;
  `eq:oneway` is rewritten over the AC/DC partition on the assembled $40\times40$;
  participation is read as $0.500/0.500$; a *three revisions* paragraph records
  what changed across the ideal, resistive and inductive closures.
- Notation table gains $I_{dc}$, $L_s$, $\tau_s$, $\varepsilon$.
- The file header records the correction and the $+4$ equation renumbering.

`docs/source/report_ieee14_switch_en_rev2.tex`

- Removed a dangling sentence fragment left in `\S`Non-ideal DC source by an
  earlier edit (`and, with the overvoltage chopper of ... the DC-link row of the
  shared power stage.` following a completed sentence).
- `realised margin 2.15` → `2.07--2.15 across the four links`, with the dispatch
  named.
- `At this dispatch $E_{dc}=1.0453\pu$` → the measured range
  `1.0269--1.0448\pu` over the four links.

## Verification

- `xelatex` twice per report. Thai: 0 errors, 0 undefined, 0 overfull, 27 pages
  (26 before; the added derivation is one page). English: 0 errors, 0 undefined,
  38 pages unchanged, one pre-existing `Overfull \vbox (11.8pt)` while `\output`
  is active on page 35–36, far from every edited line and below the declared
  20 pt gate.
- Rasterised and inspected Thai pages 15 (rows (3)–(4), `eq:dcdisc`,
  `eq:dcblock`, `eq:dctau`, the replaced bound) and 22 (`eq:oneway`, the
  participation reading, the three-revisions paragraph). Equations render, Thai
  text is set in the bundled TH Sarabun PSK, cross-references resolve
  (`\ref{sec:ibr}` → 5, `\eqref{eq:dcblock}` → (28), `eq:oneway` → (54)).
- No production code, test, case or generator was touched, so no numerical gate
  applies. The full repository regression was not run and is not required: the
  change is confined to two report `.tex` files and their PDFs, and the oracle
  for every number is the probe table above.

## Limitations

- `+ibr/dc_source_thevenin_params.m:123-134` still carries the section
  *BOUNDEDNESS WHILE EXPORTING* asserting `Vdc(t) <= max(Vdc(0),Edc)` from a sign
  argument on row (2), and `:68` still states a realised margin of `2.32`. Both
  are **comments**, not executed code, so no numerical behaviour is affected —
  but the first now contradicts both reports and the second matches no converter.
  Left OPEN as `DOC-2026-08-26-02` rather than edited here, because that file is
  production-path and the correction belongs with its owner.
- The English report is not re-verified page by page beyond the three edited
  lines; its DC content was measured and confirmed correct in the oracle table.

## Related

- `docs/project/defects/2026-08-22-report-dc-proof-contradicted-its-equation.md`
  (`DOC-2026-08-22-02`) — the previous, resistive-era instance of the same class.
- `docs/project/defects/2026-08-25-admissibility-gate-rate-vs-ratio.md`
  (`NUM-2026-08-20-01`, `GATE-2026-08-25-*`) — the work that introduced the
  source state and updated only the English report.
- `+ibr/dc_source_thevenin_params.m` — the authoritative derivation the Thai
  prose was ported from.
