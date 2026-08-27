# DOC-2026-08-28-02 - Domain-rejected trial count did not reproduce on a fresh run

- **Status:** OPEN (diagnostic counter only; no result, gate or published claim
  depends on it)
- **Area:** switched-TS diagnostic counters / deck and report scalars
- **Branch / base:** `main` at `31e9242`
- **Environment:** Windows 11, MATLAB R2025a Update 1, `dt=0.05`,
  `stepper='adaptive'`

## Symptom

The `adaptive` arm of the 250 s IEEE-14 chronology was re-run from scratch to
regenerate the deck figures. The accepted trajectory reproduces the earlier
cache on every published quantity, but `domain_rejected_trials` does not:

| scalar | earlier cache | fresh run |
|---|---|---|
| last accepted time [s] | 250.000 | 250.000 |
| reclose instant [s] | 159.252 | 159.252 |
| accepted samples | 3679 | 3679 |
| controller-rejected steps | 161 | 161 |
| largest accepted residual | $9.9721\times10^{-9}$ | $9.9721\times10^{-9}$ |
| deepest subdivision | 0 | 0 |
| terminal COI frequency [Hz] | 60.000001 | 60.000001 |
| augment/release instants | identical | identical |
| **domain-rejected trial steps** | **1027** | **1225** |

Every other scalar in `run_summary_v2.tex` is byte-identical between the two
generations; that file's only differing line is `\NewRunDomainRejects`.

## Reproduction

```matlab
pf_init_paths;
run_ieee14_gfm_lock_comparison(arms="adaptive", reuse_completed=false, ...
    outdir="output/diagnostics/ieee14_gfm_lock_compare_zeta");
generate_ieee14_report_scalars(result_file= ...
    "output/diagnostics/ieee14_gfm_lock_compare_zeta/adaptive_250s.mat");
```

Then compare `\NewRunDomainRejects` in the regenerated
`docs/source/figures/switch_ieee14_decision/run_summary_v2.tex` against the
committed value.

## What is observation and what is not established

**Observed.** The counter differs by 198 between two generations whose accepted
samples, residuals, event instants and rejected-step count are identical.

**Not established.** The cause. Two readings are consistent with the evidence
and this record does not choose between them:

1. the earlier cache was produced by a slightly different code state (the
   counter's call site was touched during the DC-source work), so the two
   numbers count different populations; or
2. the counter genuinely varies between runs of the same tree, which would mean
   the Newton line-search trial sequence is not bit-reproducible even where its
   accepted iterates are.

Distinguishing them needs two consecutive fresh runs on one unchanged tree,
which was not performed here. Nothing in the current work depends on the
answer, so it is recorded rather than investigated.

## Why this is not a numerical defect

`domain_rejected_trials` counts *trial* iterates that the line search rejected
because they left a device's declared voltage domain. A rejected trial is
discarded: `composite_newton.m:132-136` never assigns the accepted iterate, its
residual or its Jacobian from a rejected trial, and a violation at an
*accepted* state is still thrown and still aborts the run. The counter is
therefore diagnostic output about the search path, not about the trajectory,
which is consistent with the trajectory reproducing exactly while the counter
does not.

## Action taken

The defense deck no longer prints this counter. It had appeared in the
accepted-run-quality table as evidence that no gate was relaxed to complete the
horizon; that claim is now carried by the residual, the subdivision depth and
the controller-rejected step count, all of which reproduce. The owner chose to
drop the value rather than print a number that cannot be reproduced on demand
(the alternative considered was printing the fresh 1225). A comment at the
frame's `% SOURCE` line records the decision so the value is not reinstated by
a later editor.

`report_ieee14_switch_en_rev2.tex` still prints it in
Table~\ref{tab:runscalars} as "Domain-rejected trial steps ... no gate was
relaxed to pass", now regenerated to 1225. That is left as found: the report
states the value of the run it presents, and the report was not in scope for
this pass.

## Related

- `docs/project/defects/2026-08-28-deck-slowest-root-mislabel.md`
  (`DOC-2026-08-28-01`) - the other deck-content defect from the same session.
- `docs/project/defects/2026-07-19-domain-preserving-newton-globalization.md` -
  introduced the domain-preserving trial rejection and this counter.
