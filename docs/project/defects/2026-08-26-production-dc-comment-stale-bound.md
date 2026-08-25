# DOC-2026-08-26-02 — Production DC-source comment keeps a bound its own model breaks

- **Status:** OPEN
- **Area:** `+ibr/dc_source_thevenin_params.m` (header comment only; no executed code)
- **Branch / commit:** `main` at `de65eb7`
- **Environment:** Windows 11, MATLAB batch

## Symptom

Two statements in the file's header comment cannot be reconciled with the model
the same file implements:

1. Lines 123–134, *BOUNDEDNESS WHILE EXPORTING*, assert

   ```
   For Vdc > Edc every term of (2) is negative whenever Pac >= 0, so
   dVdc/dt < 0 and therefore
     Vdc(t) <= max(Vdc(0),Edc) = Edc   whenever Pac(t) >= 0.            (9)
   ```

   Equation (2) in that same header is `C dVdc/dt = Idc - Pac/Vdc - Ich`, in which
   `Idc` is a **state** governed by (1). Its value at an instant is not a function
   of `Vdc`, so "every term of (2) is negative" does not follow from `Vdc > Edc`.

2. Line 68 states the declared `eps = 0.10` "sits inside that bound with realised
   margin **2.32**".

## Reproduction

```matlab
pf_init_paths();
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
[d,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
% per converter: Pac0 = x0(I_dc)*x0(V_dc); p.discriminant_margin
```

gives `discriminant_margin = 2.0725 / 2.0811 / 2.0929 / 2.1454` for
IBR8 / IBR3 / IBR2 / IBR6. The comment's `2.32` corresponds to `Pac0 = 0.85`,
which is `P_ref`, not `Pac0`; the same header's own `Edc = 1.0453` (line 134)
implies `Pac0 = 0.453` and margin `2.148`, so the two numbers in the comment are
mutually inconsistent as well.

## Root cause (inferred, not yet confirmed by the owner)

Both statements predate the source-current state. The invariance argument is
valid for the algebraic closure `Idc = (Edc-Vdc)/Rdc`, where the bracket really is
a function of `Vdc` alone; adding the inductance made `Idc` lag, and a
`zeta = 1/sqrt2` pair overshoots its target by `4.32%` (computed from
`exp(-pi*zeta/sqrt(1-zeta^2))`). The margin figure appears to have been evaluated
with `P_ref` in place of `Pac0` and not revisited.

## Impact

None on numerical behaviour: both are comment text. `chopper_inactive_by_bound`
is computed as `Edc <= Vdc_max`, which is a statement about the dispatched point
and is correct as written and as named. The impact is on a reader: the file is the
cited derivation for both switching reports, and as of `DOC-2026-08-26-01` both
reports now state the opposite of item 1 and a measured range in place of item 2.

## Why it is not fixed here

`+ibr/` is production path. The correction is a comment edit with no behavioural
consequence, but the file is the project's authoritative derivation record and its
wording belongs with its owner rather than with a report-presentation pass. No
gate is weakened by leaving it OPEN, because nothing reads the comment.

## Suggested resolution

Replace the invariance claim with the mechanism that does survive (the source row
drives `Idc` down whenever `Vdc > Edc`, and `A_dc` is stable, so the pair
returns), state the overshoot, and recompute the realised margin per converter or
quote its range.

## Related

- `docs/project/defects/2026-08-26-thai-report-dc-state-without-equation.md`
  (`DOC-2026-08-26-01`) — found while porting this derivation into the Thai report.
