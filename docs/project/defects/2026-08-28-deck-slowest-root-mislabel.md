# DOC-2026-08-28-01 - Defense deck named the wrong slowest root

- **Status:** RESOLVED
- **Area:** 16-frame English project-defense presentation
  (`docs/source/presentation_pf_sssa_ts_gfm_en.tex`)
- **Branch / base:** `main` at `044fd3a`
- **Environment:** Windows 11, MiKTeX `pdflatex`, MATLAB not required
  (documentation-only)

## Symptom and reproduction

The spectrum frame's machine-online block printed

```text
against the declared floor zeta_min = 0.05 --- a factor of three of margin.
Slowest root -0.174920 (machine field flux).
```

and cited `docs/source/figures/switch_ieee14/sssa_sg_on_modes_all_gfl.tex` as
its source. Reading that generated table contradicts the sentence:

| row | eigenvalue | f [Hz] | zeta | dominant |
|---|---|---|---|---|
| 34 | $-0.174920$ | 0 | 1 | SG1:Eqp (field flux) |
| 35 | $-0.065196 \pm 0.124395\mathrm{j}$ | 0.019798 | 0.464215 | SG1:omega |

Row 35 is slower than row 34 under both conventions in use anywhere in this
repository: its real part is less negative ($-0.065196 > -0.174920$) and its
modulus is smaller ($0.140 < 0.175$). Reproduce by rendering page 7 of the
deck and comparing it against rows 34-35 of the cited table.

## Root cause

The sentence was written from a scan of the table's *real* roots only. Row 34
is the last purely real row before the end of the table, so a reader looking
for "the slowest root" in a column of real parts stops there and never reaches
the complex pair on the following line. Nothing in the deck cross-checks a
prose claim against the `\input`-ed generated table it cites, which is the same
failure mode recorded in `DOC-2026-08-26-01` and `DOC-2026-08-26-03`.

Independent corroboration that row 35 is the correct slowest root: the
authenticated selector table publishes the machine-online base case with margin
$-0.065196$ (`figures/switch_ieee14/sssa_sg_on_candidate_summary.tex:10`),
which is exactly that pair's real part. The selector and the modal table agree;
only the deck's sentence disagreed.

## Fix

The claim now distinguishes the two quantities and stays inside the alert block
that already carries the frame's stated limits:

```text
With the machine online the slowest root is -0.065196 +/- 0.124395j
(0.019798 Hz, zeta = 0.464215, machine speed) and the slowest real decay
rate is -0.174920 (machine field flux).
```

Two wording decisions are deliberate. The "factor of three of margin" sentence
stays attached to the electromechanical mode ($\zeta=0.156033$), which is the
smallest damping ratio in the table, so the margin statement keeps the mode it
actually describes. And row 34 is described as a decay *rate*, not a damping,
because a real root prints $\zeta=1$ trivially and "clears the 0.05 floor"
would be a vacuous claim about it.

No numerical model, parameter, event, gate, or generated artefact changed. The
underlying tables were already correct; only the prose that quoted them was
wrong.

## Verification

- Two consecutive `pdflatex -interaction=nonstopmode` runs exit 0 and produce
  exactly 16 pages with `Overfull`/`Underfull` count 0.
- `pdftotext` on the built PDF contains `0.065196`, `0.124395`, `0.464215` and
  `0.174920`, and the removed unsourced power-flow residual claim (`6.34`)
  returns zero matches.
- Page 7 rendered at 110 dpi and inspected against rows 34-35 of the cited
  table.
- Full MATLAB regression intentionally omitted: the change is
  documentation-only, no production file is touched, and the build/render/text
  gates above cover its entire scope (AGENTS.md verification policy).

## Related

- `docs/project/defects/2026-08-27-presentation-layout-and-provenance.md`
  (`DOC-2026-08-27-01`) - the layout/provenance pass on the same deck.
- `docs/project/defects/2026-08-26-rev2-report-stale-provenance-claims.md`
  (`DOC-2026-08-26-03`) - same class: prose contradicting its own generated
  input.
- `docs/project/defects/2026-08-25-admissibility-gate-rate-vs-ratio.md`
  (`GATE-2026-08-25-01`) - the 0.0198 Hz mode in row 35 is the mode whose
  damping ratio that gate defect turned on; the deck deliberately does not
  narrate that history on-slide.
