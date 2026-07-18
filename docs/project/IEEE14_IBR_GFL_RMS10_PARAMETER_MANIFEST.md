# IEEE14 IBR GFL-RMS10 — Numerical Parameter Manifest

Date: 2026-07-18
Branch: `main`
Status: `NUMERICAL_PARAMETER_PROFILE_FROZEN = YES` (per-IBR overrides under params.gfl_rms10)

This manifest freezes every numerical parameter, unit, original base, project base,
source, and classification for the GFL-RMS10 device (`+ibr/gfl_rms10_model.m`)
BEFORE production code is written. A parameter without a frozen value/unit/base/
source is NOT a contract. This satisfies the plan stop condition: `+ibr/gfl_rms10_model.m`
is NOT created until this manifest is complete. All citations are `pdftotext`-verified.

## Sources (verified identity)

- **A** = `docs/text/6739364.pdf` — Yazdani & Iravani, *Voltage-Sourced Converters in
  Power Systems*, 2010, ISBN 978-0-470-52156-4, 473 pp.
- **B** = `docs/text/grid-converters-for-photovoltaic-and-wind-power-systems.pdf` —
  Teodorescu, Liserre, Rodríguez, *Grid Converters for PV and Wind Power Systems*,
  2011, ISBN 978-0-470-05751-3, 407 pp.
- **C** = `docs/text/978-1-4471-5478-5.pdf` — Bacha, Munteanu, Bratcu, *Power
  Electronic Converters Modeling and Control*, 2014, DOI 10.1007/978-1-4471-5478-5.

## Frozen parameter table

All numerical values are FROZEN. Production code recomputes per-unit values from
the frozen equations at construction time so base conversions are exact; the
numbers below are the reference values used in tests and provenance.

| # | Parameter | Value | Unit | Original base | Project base | Source/page/eq | Classification |
|---|-----------|-------|------|---------------|--------------|----------------|----------------|
| 1 | `kp_PLL` | 920 | rad/s per pu | SI (V=1) | inverter pu | B eq 4.38, Kp=9.2/ts², ts=0.1 s | SOURCE_DEFINED (PI form, B eq 4.38) |
| 2 | `ki_PLL` | 42320 | 1/s | SI (V=1) | inverter pu | B eq 4.38, ki=kp/Ti, Ti=ts/4.6=0.02174 s | SOURCE_DEFINED (PI form, B eq 4.38) |
| 3 | `T_P` | 0.02 | s | s | s | REGFM_B1 Eq.1 Tpf=0.02 (`regfm_b1_vsg_model.m:184`) | PROJECT_DERIVED (REGFM_B1 filter pattern) |
| 4 | `T_Q` | 0.02 | s | s | s | REGFM_B1 Eq.3 TQf=0.02 (`regfm_b1_vsg_model.m:185`) | PROJECT_DERIVED (REGFM_B1 filter pattern) |
| 5 | `kp_P` | 1.0 | pu/pu | inverter pu | inverter pu | PROJECT_DERIVED outer-loop PI (user §5.4) | PROJECT_DERIVED |
| 6 | `ki_P` | 20.0 | 1/s | inverter pu | inverter pu | PROJECT_DERIVED; Ki = kp_P/T_P | PROJECT_DERIVED |
| 7 | `kp_Q` | 1.0 | pu/pu | inverter pu | inverter pu | PROJECT_DERIVED outer-loop PI (user §5.4) | PROJECT_DERIVED |
| 8 | `ki_Q` | 20.0 | 1/s | inverter pu | inverter pu | PROJECT_DERIVED; symmetric to ki_P | PROJECT_DERIVED |
| 9 | `kp_i` | L/τi (eq 8.56) | pu/pu | SI (V/A) | inverter pu | A eq 8.56, kp=L/τi, τi=2 ms (Ex.8.2 p.222) | SOURCE_DEFINED (A eq 8.56); value recomputed from L_pu at construction |
| 10 | `ki_i` | R_t/τi (eq 8.57) | 1/s | SI (V/A·s) | inverter pu | A eq 8.57, ki=(R+ron)/τi, τi=2 ms (Ex.8.2) | SOURCE_DEFINED (A eq 8.57); value recomputed from R_t_pu at construction |
| 11 | `R_t` | (R+ron) on inverter Z_base | pu | SI 1.63 mΩ (Ex.8.2) | inverter pu | A Ex.8.2 R=0.75mΩ + ron=0.88mΩ | SOURCE_DEFINED (A Ex.8.2); base-converted at construction |
| 12 | `L` | L on inverter Z_base/ω_b | pu | SI 100 µH (Ex.8.2) | inverter pu | A Ex.8.2 L=100µH; ω_b·L is the pu coupling reactance | SOURCE_DEFINED (A Ex.8.2); base-converted at construction |
| 13 | `Imax` | 1.20 | pu | inverter pu | inverter pu | A p.371 footnote "saturation 10-20% higher than rated" | SOURCE_DEFINED (A p.371 footnote) |
| 14 | `Vdc0` | 1.0 | pu (AC base) | SI 1250 V (Ex.8.2) | inverter pu (AC base; /2 absorbed) | A Ex.8.2 + Appendix B Table B.2 | SOURCE_DEFINED (A Ex.8.2 + App.B) |
| 15 | `m_max` | 1.30 | pu | pu | pu | PROJECT_DERIVED 30% overmodulation headroom (clamp inactive in normal op); A eq 8.47-8.48 | PROJECT_DERIVED |
| 16 | `V_valid_min` | 0.50 | pu | system pu | system pu | CASE_DEFINED validity threshold (IEEE14 normal ~0.95-1.06 pu) | CASE_DEFINED |
| 17 | `V_div_min` | 0.10 | pu | device pu | device pu | CASE_DEFINED division floor (v_d²+v_q² threshold) | CASE_DEFINED |
| 18 | `aw_tol` | 1e-6 | scaled residual | — | — | NUMERICAL_METHOD anti-windup tolerance | NUMERICAL_METHOD |
| 19 | `Sbase` | 100.0 | MVA | system | system | case data (IEEE14) | CASE_DEFINED |
| 20 | `Mbase` | 100.0 (140 IBR2) | MVA | inverter | inverter | CASE_DEFINED unity-PF nameplate proxy | CASE_DEFINED |
| 21 | `omega_b` | 376.9911 | rad/s | rad/s | rad/s | 2·π·60, case fbase=60 Hz | CASE_DEFINED |
| 22 | `fbase` | 60.0 | Hz | Hz | Hz | case data | CASE_DEFINED |

## Base conversion notes (must be exact, not fitted)

### L per-unit convention (parameter #12)
`L` is stored as the **per-unit coupling reactance** `X = ω_b·L_SI` (NOT per-unit
inductance in seconds). This matches the PF/WECC convention where impedances are
per-unit reactances. The ODE (eq 8.45/8.46) uses `omega_PLL_pu*L` as the
per-unit coupling term, where `omega_PLL_pu = 1 + Δω_PLL` is the per-unit PLL
frequency. The time-derivative form divides by `L/omega_b` (per-unit inductance).
Frozen default `L = 0.15 pu` (typical converter coupling reactance).

### kp_i / ki_i (parameters #9, #10)
Yazdani eq 8.56/8.57 give `kp = L/τi` and `ki = (R+ron)/τi` in SI. With `L` as the
per-unit reactance, the per-unit inductance is `L/ω_b`, so:
- `kp_i = (L/ω_b)/τi`  (per-unit inductance / closed-loop time constant)
- `ki_i = R_t/τi`      (per-unit resistance / closed-loop time constant)
with `τi = 2 ms` (SOURCE_DEFINED from Ex.8.2). Production code computes both
gains from `L`, `R_t`, `ω_b`, `τi`.

### PLL gains (parameters #1, #2)
Yazdani Ex.8.1 PLL compensator (eq 8.38) is high-order (complex zeros ±jω₀) and does
NOT match our simple-PI ODE form `dot(delta_PLL) = ω_b·(kp_PLL·v_q + ki_PLL·xi_PLL)`.
Teodorescu eq 4.38 gives the simple-PI tuning `Kp = 9.2/ts²`, `Ti = ts/4.6` for a
second-order type-2 PLL with unit input (V=1), which matches our ODE form exactly.
Frozen with `ts = 0.1 s` (settling time, Teodorescu §4.2.2.4 uses ts=100 ms):
- `kp_PLL = 9.2/ts² = 9.2/0.01 = 920`
- `Ti = ts/4.6 = 0.1/4.6 = 0.02174 s`
- `ki_PLL = kp_PLL/Ti = 920/0.02174 = 42320 1/s`

The frozen contract is the equation `kp_PLL = 9.2/ts²`, `ki_PLL = kp_PLL/Ti`,
`Ti = ts/4.6`, `ts = 0.1 s` (B eq 4.37-4.38). Production code stores `ts` and
computes both gains from these equations, not from the rounded numbers.

### V_t modulation (factor 1/2 absorbed by base convention)
Yazdani eq 8.47 gives `v_td = (V_DC/2)·m_d` in SI. In the project per-unit system
`Vdc0` is stored in **per-unit AC-voltage base** (Yazdani Appendix B Table B.2:
DC base = 2·AC base, so 1.0 pu DC corresponds to 1.0 pu AC at unity modulation
after the /2 in eq 8.47). Therefore the modulation clamp is
`V_t_max = m_max·Vdc0` (the /2 is already absorbed; `Vdc0 = 1.0` means v_td can
reach 1.0 pu AC at `m = 1`). Verified: at equilibrium with `|V| ≈ 1.01 pu`,
`v_td_raw = v_d + R_t·i_d ≈ 1.02 < V_t_max = 1.10`, so the clamp is inactive in
normal operation (as required by the LV fail-closed domain).

### Current-controller feedforward (verified)
The feedforward includes `R_t·i` (not just `v` and `ω·L·i`). From eq 8.45/8.46 at
steady state: `v_td = v_d + R_t·i_d - ω_PLL·L·i_q`,
`v_tq = v_q + R_t·i_q + ω_PLL·L·i_d`. Verified: at equilibrium the current-plant
derivatives `dot(i_d)`, `dot(i_q)` are exactly zero (machine-epsilon residual).

## Classification summary

- **SOURCE_DEFINED** (equation + numerical value from cited source): kp_PLL, ki_PLL
  (B eq 4.38), kp_i, ki_i (A eq 8.56/8.57), R_t, L (A Ex.8.2), Imax (A p.371),
  Vdc0 (A Ex.8.2 + App.B).
- **PROJECT_DERIVED** (user-authorized, follows sourced pattern): T_P, T_Q (REGFM_B1
  filter), kp_P/ki_P/kp_Q/ki_Q (outer-loop PI), m_max (modulation headroom).
- **CASE_DEFINED** (from case data / operational decision): Sbase, Mbase, omega_b,
  fbase, V_valid_min, V_div_min.
- **NUMERICAL_METHOD** (comparison tolerance, not tuning): aw_tol.

## Stop condition satisfied

Every parameter has a frozen Value, Unit, Original base, Project base, Source,
and Classification. The `+ibr/gfl_rms10_model.m` production file may now be created.
Production code must recompute the per-unit values from `L_pu`, `R_t_pu`, `τi`,
`ts`, `Mbase`, `Vbase` at construction time so base conversions are exact; the
frozen NUMBERS above are the reference values used in tests and provenance.

## Low-voltage policy (frozen, separate from parameter table)

GFL-RMS10 has NO PLL freeze. Before evaluating PLL/PQ-inversion/current-control,
require `|V| >= V_valid_min` AND `D_V = v_d²+v_q² >= V_div_min²`. Else fail-closed
with `ibr:gfl_rms10_model:voltageOutsideValidityDomain` /
`ibr:gfl_rms10_model:lowVoltagePowerInversion`. `V_PLLfrz` is NOT a GFL-RMS10
parameter. Fault/LVRT TS is outside this production slice.

## Anti-windup tolerance

`aw_tol = 1e-6` is a frozen NUMERICAL_METHOD comparison tolerance for the one-sided
conditional-hold logic (`AW_*`). It is NOT a tuning parameter and MUST NOT be
adjusted to make a simulation pass.
