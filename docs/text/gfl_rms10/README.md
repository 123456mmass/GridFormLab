# GFL RMS10 source set

Purpose: preserve the sources used to define and audit the explicit-state
grid-following RMS10 model. This is separate from the new no-PLL GFM source set.

The original files remain in `docs/text/`. The PDFs here are byte-identical
copies with descriptive names.

Each PDF has a same-basename `.txt` companion generated locally with
`pdftotext -layout -enc UTF-8` for local search. Neither the PDFs nor the `.txt`
companions are tracked: they are third-party copyrighted material and are not
redistributed from this repository. The PDF remains authoritative whenever
extracted symbols, subscripts, signs, or equation numbers are ambiguous.

## Files and intended use

| Curated file | Original file | Intended contribution | Limitation / classification |
|---|---|---|---|
| `yazdani-iravani-2010-vsc-modeling.pdf` | `../6739364.pdf` | PLL equations, dq-frame VSC model, current controller, and converter/filter dynamics | Primary nonlinear controller/plant source; project mapping to positive-sequence RMS and case bases must remain explicit. |
| `teodorescu-liserre-rodriguez-2011-grid-converters.pdf` | `../grid-converters-for-photovoltaic-and-wind-power-systems.pdf` | Three-phase synchronization, PLL, current control, grid-connected converter structure | Primary supporting textbook; not every project limiter or initialization rule is source-defined by this book. |
| `bacha-munteanu-bratcu-2014-converter-modeling-control.pdf` | `../978-1-4471-5478-5.pdf` | Converter modeling/control and integrator behavior during limitation | Supporting textbook; the project's exact directional anti-windup realization remains `PROJECT_DERIVED`. |
| `fu-2024-general-pq-v-hybrid-model.pdf` | `../A_General_P_Q-_V_Model_of_Hybrid_GFM_GFL_Multi-VSC_Systems_Power_Oscillation_Analysis_and_Suppression_Method.pdf` | Linear small-signal hybrid GFM/GFL P-Q/voltage-frequency port model | `LINEAR_DIAGNOSTIC_ONLY`; it is not the nonlinear production GFL ODE model. |

## Current provenance verdict

The source set supports the six-state nonlinear PLL/current-controller/L-filter
core used by GFL-RMS10. The P/Q measurement filters, outer-loop realization,
exact directional anti-windup, initialization, and some limit semantics remain
explicit `PROJECT_DERIVED` choices documented in the project provenance and
parameter manifest. Therefore the honest classification remains:

```text
SOURCE_DEFINED_NONLINEAR_CORE_CLOSED = YES
FULL_SOURCE_DEFINED_GFL_MODEL = NO
```

No GFL source or state may be reused as authority for a no-PLL GFM state merely
to make the two device orders equal.
