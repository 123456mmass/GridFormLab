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

## What is and is not in version control

The extracted plain text of each source **is not tracked**, and neither are the
original PDFs. Both are third-party copyrighted material and are not
redistributed from this repository; they are kept on the local machine only, as a
searchable index while equations are being traced. The `.gitignore` rules
`*.pdf` and `docs/text/**/*.txt` enforce that.

What remains version-controlled is this file and the two folder READMEs. They are
the citation index: they name every source, say which device contract it belongs
to, and record what the project did and did not take from it. Obtain the sources
yourself from the publisher or the DOI listed in the folder README, and place the
extracted text beside the corresponding entry using the same basename if you want
the local searchable index back.

A source being present in a folder does not automatically classify a project
realization as `SOURCE_DEFINED`; consult the folder README and the project
provenance matrix.
