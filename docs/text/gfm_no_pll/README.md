# GFM no-PLL source set

Purpose: authoritative inputs for designing a new positive-sequence RMS
grid-forming VSM/VSG model whose dynamic equations contain no PLL state or
PLL-derived frequency.

This directory is a curated source set. The original files remain in
`docs/text/` so existing citations and scripts do not break. The PDFs here are
byte-identical copies with descriptive names.

Each PDF has a same-basename `.txt` companion generated locally with
`pdftotext -layout -enc UTF-8` for local search and equation discovery. Neither
the PDFs nor the `.txt` companions are tracked: they are third-party copyrighted
material and are not redistributed from this repository. The PDF is
authoritative. In particular, the Japanese embedded fonts in the
Sakimoto paper cause imperfect text extraction, so its equations and symbols
must be verified visually against the PDF before being entered in a contract.

## Model rule

The new GFM may contain an internally generated virtual-rotor angle, but it
must not contain `delta_PLL`, a PLL integrator, a PLL freeze rule, or PLL gains:

```text
dot(delta_vsm) = omega_base * delta_omega_vsm
2 H dot(delta_omega_vsm) = active-power imbalance - damping terms
```

The final state count is determined by the approved sourced dynamic blocks. It
must not be forced to equal the legacy 13-state REGFM_B1 model or the 10-state
GFL-RMS10 model.

## Files and intended use

| Curated file | Original file | Intended contribution | Limitation / classification |
|---|---|---|---|
| `sakimoto-2015-vsg-without-pll.pdf` | `../135_462.pdf` | Primary no-PLL VSG architecture: impedance model, governor, AVR, rotor inertia/angle, damper, and current controller | Primary equation source. Its current-controlled inverter is more detailed than the project's positive-sequence RMS interface; any reduction must be derived and documented. |
| `pnnl-35110-regfm-a1.pdf` | `../PNNL-35110.pdf` | Positive-sequence REGFM_A1 network interface, droop controls, filters, initialization, limits, and transient fault-current limiting | Primary RMS/interface source. It is droop-forming rather than a complete inertial VSM source. |
| `du-2024-positive-sequence-gfm.pdf` | `../2477606.pdf` | Positive-sequence voltage-behind-impedance GFM and algebraic current limiting for transmission transient-stability simulation | Primary RMS/fault-interface source. It does not by itself define every VSM/governor state. |
| `avila-martinez-2025-self-synchronisation-gfm.pdf` | `../Impact_on_transient_stability_of_self-synchronisation_control_strategies_in_grid-forming_power_converters.pdf` | VSM-noPLL swing/angle structure and transient-stability comparisons | Supporting/cross-check source; detailed converter implementation and publication status must be stated when cited. |
| `nrel-90260-regfm-b1-legacy-comparison.pdf` | `../90260.pdf` | Existing REGFM_B1 contract and parameters for comparison with the current legacy implementation | Not authority for copying its embedded PLL states into the new no-PLL GFM. |

## Sufficiency verdict

The set is sufficient to write a source-to-equation design contract for a new
no-PLL positive-sequence RMS GFM. It is not permission to splice blocks
silently. Before production implementation, freeze:

1. the selected dynamic blocks and exact state order;
2. every ODE/algebraic equation and its source or project derivation;
3. dq orientation, injection sign, per-unit bases, and initialization;
4. current limiting, anti-windup, low-voltage validity, and recovery behavior;
5. which fast current/filter states are retained or removed by the RMS
   reduction; and
6. one common equation set for equilibrium, SSSA linearization, and TS.

The existing 13-state REGFM_B1 model remains a legacy model. Renaming or hiding
its PLL states does not create a no-PLL GFM.
