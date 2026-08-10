# SG reclose command step and SG-online angle-gauge defect

**ID:** `SWITCH-2026-08-10-02`

**Status:** `IMPLEMENTED_PENDING_250S_EVIDENCE`

**Branch / starting commit:** `main` / `d63f48d`
**Environment:** MATLAB R2026a Update 2, Windows, Base MATLAB production path

## Symptom and reproduction

The accepted 200-s trajectory closed SG1 at 154.3 s and then developed large
post-reclose oscillations. At the breaker transaction, the full composite
input vector changed by 1.28758 pu because `reclose_transaction` assigned the
entire pre-event vector to the right limit. The same transaction therefore
changed SG mechanical/excitation commands and all IBR P/Q references.

Separately, the SG-online full-KCL SSSA table reported a dominant real pole
near `-5.93e-4 1/s`. Its right eigenvector had equal normalized components in
SG1 `delta` and every active GFM `delta_VSG`, with current components below
`2.2e-5`. Using that coordinate pole in the handback formula produced an
unphysical duration of roughly 5,000 s.

Reproduction artifacts are the preserved baseline
`output/diagnostics/engine_release_400s_baseline.mat` and its log. A source-tree
probe on the implementation worktree produced the modal-shape evidence; the
probe itself was removed after the result was encoded in a permanent oracle.

## Root cause (evidence-backed)

1. `reclose_transaction` used `u_right=initial_u`. This was an implementation
   defect: breaker closure and numerical-reference ownership do not authorize
   an atomic controller-command reset.
2. `composite_sssa_model` quotiented the common angle only when every SG was
   offline. Full-KCL equations retain a rigid network-angle coordinate with an
   online SG as well, so the SG-online decision spectrum and handback timing
   consumed a coordinate mode rather than a physical mode.

The SG current itself is not assumed zero at closure. A new prospective audit
evaluates current, P, Q, electrical power, torque mismatch and state derivative
from the accepted breaker-left state under a hypothetical closed context. The
close remains fail-closed when declared SG current/apparent-power rating is
exceeded.

## Correction

- Keep the accepted left-limit input vector at breaker close.
- Transfer SG governor/exciter targets and all IBR P/Q references with a C1
  cubic smoothstep after closure; duration is derived before the run from the
  worst robust SG-online SSSA pole, controller time constants, `rho`, and the
  declared minimum hold.
- Quotient one rigid network-angle coordinate before physical `eig` for both
  SG-off and SG-on full-KCL models. Infer the owner only when exactly one
  online SG exists; ambiguous ownership remains fail-closed.
- Evaluate every selector candidate at FD steps `[0.5,1,2]*3e-6` and use the
  least-damped result. Classification and the frozen margin must pass at all
  three steps.
- Enumerate the complete 16-row SG-online table and authenticate staged
  one-IBR releases. All-GFL remains rejected when its physical spectrum is
  unstable.

No source/case parameter, AGSI equation, event time, Newton tolerance, current
limit, plot filter, or acceptance threshold was changed.

## Verification to date

- Focused C1/prospective/gauge tests: 12/12 PASS.
- Selector, SG-online, reclose, event transaction, gauge, prospective-close
  and C1 helper group: 107/107 PASS within the broader targeted run.
- Broad targeted run: 162/163 PASS; the sole error was a legacy SG-online
  full-KCL caller without an explicit owner. The compatibility repair permits
  inference only for a unique online SG; affected SSSA/gauge rerun 10/10 PASS.
- Full repository regression intentionally omitted under the repository risk
  policy; producer, consumers, failure paths, model equations, and external-
  solver isolation were covered by the targeted 16-file gate.

The final 250-s trajectory, before/after metrics, report artifacts and final
status will be appended after the committed-source run completes.

## Limitations

SSSA is a local equilibrium result and cannot guarantee transient stability.
The all-GFL SG-online candidate is presently unstable, so automatic handback
must retain the minimum authenticated GFM subset rather than force all four
IBRs to GFL. Operational readiness remains separate from numerical completion.

## Related files

- `+stability/composite_sssa_model.m`
- `+stability/ibr_candidate_evaluate.m`
- `+stability/ts_simulate_ibr_hybrid.m`
- `+stability/sg_prospective_close_metrics.m`
- `+stability/c1_smoothstep.m`
- `tests/test_sg_online_network_angle_quotient.m`
- `tests/test_sg_prospective_close_metrics.m`
- `tests/test_c1_smoothstep_handback.m`
