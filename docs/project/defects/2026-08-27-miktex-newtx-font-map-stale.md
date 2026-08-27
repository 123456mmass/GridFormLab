# DOC-2026-08-27-02 - MiKTeX newtx font map stale

- **Status:** RESOLVED
- **Area:** English defense-presentation PDF build environment
- **Branch / tree:** `main` at `b7f1b15` plus the cover-only working-tree edit
- **Environment:** Windows 11, MiKTeX 26.2, pdfTeX 1.40.29

## Observed symptom and reproduction

Running the deck's documented build command from `docs/source` failed after
typesetting all 16 frames:

```text
pdflatex -interaction=nonstopmode -halt-on-error presentation_pf_sssa_ts_gfm_en.tex
```

MiKTeX attempted to generate `ntx-Regular-tlf-ot1r` or
`ntx-Bold-tlf-ot1r` as a PK font and terminated because the font could not be
created. The failure was deterministic with both pdfLaTeX and XeLaTeX.

## Root cause and evidence

The `newtx` package verified as correctly installed, and its physical Type-1
files (`ztmr.pfb`, `ztmb.pfb`) plus `newtx.map` were present. The map entry for
`ntx-Regular-tlf-ot1r` correctly referenced `ztmr.pfb`, but the active MiKTeX
PDF font map did not contain that mapping. Consequently the engines fell back
to the invalid PK-generation path.

The initial hypothesis that a newly introduced fractional font size caused
the failure was falsified: replacing it with standard Beamer sizes merely
moved the same failure to the pre-existing bold title font.

## Fix

Rebuilt MiKTeX's font-map configuration without changing the deck's typeface:

```text
miktex fontmaps configure --force
```

No numerical source, model, parameter, event, result, tolerance, or gate was
changed.

## Verification

Two consecutive pdfLaTeX runs exited zero and produced a 16-page PDF. The log
shows the expected embedded `ztmr.pfb`/`ztmb.pfb` fonts and no missing-font,
fatal-error, or cover-overflow diagnostic. All 16 rendered pages were visually
inspected. The only fit warning is the pre-existing documented 6.9 percent
shrink on the dense decision-parameter frame.

## Limitations and related files

This repair changes the local MiKTeX user font-map configuration; another
machine with a stale map may require the same command. Related deck source:
`docs/source/presentation_pf_sssa_ts_gfm_en.tex`.
