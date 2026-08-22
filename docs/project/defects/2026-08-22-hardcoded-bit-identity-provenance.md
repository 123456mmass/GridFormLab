# The report-scalar generator stamped a bit-identity claim it could not know was true

- **ID**: `DOC-2026-08-22-01`
- **Status**: RESOLVED
- **Component**: `scripts/reporting/generate_ieee14_report_scalars.m`
- **Branch**: `main`. Tested tree: uncommitted, on top of `416e47a`.
- **Environment**: MATLAB R2026a Update 3 (26.1.0.3276743), glnxa64.

## Symptom (observation)

Regenerating `docs/source/figures/switch_ieee14_decision/run_summary_v2.tex` from the
non-ideal DC cache produced a header whose `PROVENANCE` line correctly named the new
cache while the line below it still asserted:

```text
% PROVENANCE. Accepted values of output/diagnostics/ieee14_gfm_lock_compare_dcreal/adaptive_250s.mat.
...
% That re-run was gated on being bit-identical to the delivered artifact.
```

The two statements cannot both be true. The `_dcreal` re-run is **not** bit-identical
to the delivered artefact and was never intended to be: `NUM-2026-08-20-01` changed the
DC-link closure on purpose, so the trajectory legitimately differs (4990 accepted
samples against 4994, reclose $159.2397$ against $159.3436$).

## Root cause with evidence

The sentence was a literal inside the header writer at
`generate_ieee14_report_scalars.m:52-55`, emitted unconditionally on every call:

```matlab
fprintf(fid,['%% Produced by run_ieee14_gfm_lock_comparison, whose option set is the\n' ...
             '%% flagship driver''s plus agsi_reference=true (opt-in, post-processing only).\n' ...
             '%% That re-run was gated on being bit-identical to the delivered artifact.\n' ...
             '%% No value here is rounded, scaled, smoothed or otherwise altered.\n%%\n']);
```

The claim was correct when written, because the only cache the generator was ever
pointed at was the ideal-DC one, whose re-run genuinely was gated on bit-identity
against the delivered chronology (`AGSI-2026-08-16-01`). The defect is that the
statement is a property of **one particular cache** while the code treats it as a
property of the generator, so it survives a change of `result_file`. `result_file` is
an exposed option, so any future cache inherits the claim silently.

A second, quieter instance of the same fault sat two lines below:

```matlab
fprintf(fid,'%% Regenerate with:  pf_init_paths; generate_ieee14_report_scalars\n\n');
```

That bare command defaults `result_file` back to the ideal cache, so following the
file's own reproduction instructions would have **overwritten** the non-ideal scalars
with ideal ones and produced no error.

## Why this is material and not cosmetic

`AGENTS.md` requires reports to distinguish sourced inputs, assumptions, project
results and external references, with citations. A provenance header is the mechanism
that does that for these macros, and a reader who checked it would have been told the
numbers were bit-identity-gated when they were not. It is exactly the class of claim
that must be earned per artefact.

## Fix

The bit-identity sentence is now selected from the cache the values were read from,
and the reproduction command carries the real argument:

- `cachename` is taken with two `fileparts` calls and compared with `strcmp` against
  `ieee14_gfm_lock_compare`. An exact component comparison, not a substring test —
  `contains(src,'ieee14_gfm_lock_compare')` would match `ieee14_gfm_lock_compare_dcreal`
  as well and reintroduce the defect.
- The ideal branch keeps the original sentence.
- The other branch states that bit-identity is **not** claimed, names
  `NUM-2026-08-20-01` as the reason the trajectory differs, and instructs the reader to
  compare caches by outcome rather than by bit-identity.
- `Regenerate with:` now prints `generate_ieee14_report_scalars(result_file="<src>")`.

## Verification

- `checkcode('scripts/reporting/generate_ieee14_report_scalars.m','-struct')` returns
  empty (clean).
- Regenerated against the non-ideal cache: the header now carries the
  not-bit-identical paragraph and a reproduction command naming
  `output/diagnostics/ieee14_gfm_lock_compare_dcreal/adaptive_250s.mat`.
- Macro values unchanged by the fix itself: `\NewRunReclose{159.240}`,
  `\NewRunSamples{4990}`, `\NewRunRejectedSteps{135}`, `\NewRunEnd{250.000}`,
  `\NewRunTerminalF{60.000000}`. Only comment lines moved.
- The ideal branch is unexercised by this session and is preserved verbatim, so
  re-pointing the generator at `ieee14_gfm_lock_compare` restores the original header.

## Limitations

The check keys on a directory name. A future cache that is genuinely bit-identity-gated
but stored under a different directory would get the weaker sentence, which fails
safe — it under-claims rather than over-claims. Tying the sentence to a recorded gate
result rather than to a path would be the stronger design and is not done here.

## Related

- `docs/project/defects/INDEX.md`
- `NUM-2026-08-20-01` — the closure change that exposed the claim
  ([record](2026-08-20-ideal-dc-link-carried-no-dynamics.md))
- `AGSI-2026-08-16-01` — the re-run for which the bit-identity claim is true
