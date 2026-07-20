# Dynamic-model source sets

Curated model-building references are separated by device contract:

- [`gfm_no_pll/`](gfm_no_pll/README.md): sources for the new positive-sequence
  RMS GFM/VSM model with an internally integrated virtual-rotor angle and no
  PLL states.
- [`gfl_rms10/`](gfl_rms10/README.md): sources for the existing explicit-PLL,
  P/Q-controlled GFL-RMS10 model.

Do not combine the folders to equalize state counts. GFM and GFL state orders
follow their respective sourced dynamic equations. A source being present in a
folder does not automatically classify every project realization as
`SOURCE_DEFINED`; consult the folder README and the project provenance matrix.

PDF files are kept locally for visual verification and are ignored by the
repository-wide `*.pdf` rule. Same-basename extracted text and the README files
provide the version-controlled searchable index. Original PDFs in this parent
directory are retained for backward-compatible citations.
