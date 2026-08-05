# ET-FCSPS production SG-trip adapter

Status: `RESOLVED`

## Symptom

The first authenticated IEEE 14-bus SG-trip trial reported no feasible
ET-FCSPS candidate. All candidate trials stopped before a valid event-right
full-KCL state could be published, although the accepted event-left state and
the existing atomic SG-trip transaction were valid.

## Reproduction and affected tree

- Branch: `main`
- Starting commit: `f7ff31690d031fb7b6eb32e3b1dd391caf4b23fa`
- Environment: MATLAB batch on Windows, 4 August 2026
- Reproduction:

```matlab
pf_init_paths;
addpath(fullfile(pwd,'scripts','reporting'));
run_ieee14_controller_comparison(reuse_completed=true);
```

The first implementation produced an incomplete authenticated trial table for
every SG-off candidate.

## Root cause and evidence

Two adapter defects were present.

1. The trial adapter passed the SG transition to `breaker_open` into the IBR
   mode-transfer helper. The production runtime intentionally applies that
   helper only to `gfl`, `gfm`, and `tripped` device transitions; breaker state
   is handled by the SG event transaction. Therefore the adapter did not match
   the production event path.
2. Authentication compared selected-GFM index arrays with orientation-sensitive
   `isequal`. Equivalent row and column index sets were rejected even though
   their identities were identical.

The hypotheses that the all-KCL right-limit solve, the candidate feasibility
limits, or the 0.25-s predictor caused the universal failure were falsified:
after correcting the two adapter mismatches, all eight authenticated candidates
that passed the fixed pre-screen completed the same project-owned nonlinear
trial pipeline.

## Correction

- Mirror the production transition set and leave SG `breaker_open` handling to
  the authenticated SG event transaction.
- Canonicalize selected-GFM identities as sorted row vectors before exact
  comparison.
- Preserve the accepted event-left state in the immutable snapshot, while
  carrying explicit authenticated event-right `decision_device_online` and
  `decision_reference_owner_indices` fields for enumeration and screening.

No equation, threshold, event time, candidate cost, solver tolerance, or case
parameter was changed.

## Verification

- Common SG-trip evidence: 8/8 pre-screen-feasible candidates completed the
  full-KCL right-limit and 0.25-s production prediction.
- ET-FCSPS and finite-set BO replay each selected IBR1--IBR4 as GFM with IBR1
  as reference owner.
- Both fresh closed-loop runs reached 160 s and matched the unchanged legacy
  trajectory exactly for AGSI++, modes, P, Q, currents, frequency, angle,
  voltages, reference identity, and SG signals.
- The additive unit test
  `test_authenticated_sg_trip_uses_event_right_context` falsifies regression
  of the event-left/event-right distinction.

## Limitations

This resolves the software adapter mismatch for the frozen IEEE 14-bus
prototype. P/Q reserve remains the documented case-nameplate proxy, BO remains
an offline diagnostic replay, and the result is not a protection, HIL, or field
readiness claim.
