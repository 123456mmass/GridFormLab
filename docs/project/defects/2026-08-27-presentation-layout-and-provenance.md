# DOC-2026-08-27-01 - Presentation layout and provenance defects

- **Status:** RESOLVED
- **Area:** 16-page English project-defense presentation
- **Branch / base:** `main` at `3b9c67d`
- **Environment:** Windows 11, TeX Live 2026, MATLAB R2026a

## Symptom and reproduction

Rendering the original 16-page deck exposed defects that source-text checks did
not: the study-network page contained a placeholder, mathematical content on
pages 3 and 15 overlapped or clipped, and the page-14 title and final legend
entry extended beyond the slide boundary.  The original raster checks are the
`_slide_check-*.png` working artefacts; the defect is reproduced by rendering
the original PDF at 150 dpi.

## Root cause and fix

The deck had been assembled before its final figures and before visual fitting
at the physical 16:9 page size.  A real IEEE-14 study diagram replaced the
placeholder, dense text was restructured, and slide-native 5.90 in figures were
generated at the deck font size.  The electrical-response title and legend were
shortened without changing any plotted sample, value, model, parameter, event,
or gate.  The visible deck was also purged of source-code and filename language
at the owner's request.

## Verification

Two consecutive `pdflatex -interaction=nonstopmode -halt-on-error` runs exited
zero and produced exactly 16 pages.  All pages were rendered at 150 dpi and
visually inspected.  The corrected page 14 was re-rendered after the legend
repair.  Extracted PDF text contains no filename, MATLAB, source-code,
placeholder, or programming exponent notation.  The only build diagnostic is
the deliberate 6.9 percent fit reduction on the dense decision-parameter page;
its displayed mathematics remains legible and does not overlap the footer.

## Limitation

The repository study-network diagram is complete and usable, but the owner has
said a preferred drawing will be supplied later.  Replacing that one asset does
not alter the mathematical narrative or numerical results.
