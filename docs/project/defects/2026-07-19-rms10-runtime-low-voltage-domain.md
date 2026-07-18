# GFL-RMS10 runtime voltage gate blocked sourced balanced-fault LVRT

Date: 2026-07-19  
Status: RESOLVED_PENDING_FINAL_REGRESSION

## Symptom

The IEEE14 Profile-B fault transaction rolled back at `fault_on` with
`ibr:gfl_rms10_model:voltageOutsideValidityDomain` when the fault-bus voltage
fell to approximately 0.377 pu. The original test contract required every
runtime sample below `V_valid_min=0.50` to fail.

## Proven defect

`V_valid_min` is an equilibrium/normal-operating-point gate. Applying it to
every runtime sample made the implemented converter unable to exercise the
fault-ride-through current structure documented by Teodorescu, Liserre and
Rodríguez, Chapter 7 pp.162-163. The former test therefore contradicted the
newly approved sourced balanced positive-sequence FRT contract.

## Correction and independent oracle

- Equilibrium still rejects `|V|<V_valid_min`.
- Balanced positive-sequence runtime continues while `|V|>=V_div_min`.
- Below `Vdip`, active current follows a voltage-dependent LVPL capability and
  reactive current has priority. Numerical values are mapped from the official
  WECC REGC_A/REEC_A conversion example already frozen in
  `+ibr/wecc_regca_reeca_model.m`.
- `|V|<V_div_min`, zero voltage, and unbalanced/negative-sequence behavior
  remain fail-closed.
- The previous low-voltage unit test was corrected to verify finite RHS,
  reactive-current direction, current magnitude, and the independent near-zero
  failure boundary.

The public TS output step remains 0.01 s. Failed coupled-Newton logical steps
may use bounded internal bisection (maximum four levels) without changing event
times or the published sample grid.

## Classification

FRT structure: SOURCE_DEFINED (Teodorescu Ch.7). WECC characteristic values:
SOURCE_DEFINED / PROJECT_MAPPED. dq/sign/base mapping and bounded retry policy:
PROJECT_DERIVED / NUMERICAL_METHOD. This does not claim unbalanced-fault or
zero-voltage LVRT readiness.
