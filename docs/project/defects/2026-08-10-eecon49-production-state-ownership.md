# SWITCH-2026-08-10-02 — production GFL/GFM state ownership reversal

- **Status:** IMPLEMENTED_PENDING_200S_GATE
- **Area:** IEEE14 source-case production IBR model, state inventory, mode transfer
- **Environment:** Windows 11, MATLAB R2026a, branch `main`

## Symptom

The source-case production scenario dispatched to the historical 20-state
REGFM/WECC dual model. That family assigns a PLL pair to its GFM branch and no
PLL state to its seven-state GFL branch. This is the reverse of the requested
physical contract: PLL-synchronized GFL and VSG GFM without PLL.

## Reproduction and evidence

At checkpoint `5dc263f`, construct
`cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'))`
and pass its resource table to `stability.build_mixed_resource_devices`.
The IBR resource `model_id` was `regfm_b1_dual`; device states included
`gfm_delta_PLL` and `gfm_x_PLL_int`, while the WECC GFL branch contained no
PLL state. The direct diagnostic builder already had separate full-state
branches with the requested ownership, proving the discrepancy was the generic
production dispatch rather than the source interpretation.

Internal source inspection of `docs/text/EECON49_[Nui].pdf` shows the GFL PLL
and controller states in Eqs. (9)--(21), while the GFM VSG/voltage-loop states
in Eqs. (22)--(29) contain no PLL.

## Root cause

An earlier source-case restoration retired the full-state path because the
published DC energy equation did not include an `I_dc` control law, then reused
the already integrated REGFM/WECC family. Later documentation accurately
described that runtime family but did not correct the model/source mismatch.

## Falsified hypotheses

- **Only state labels were wrong:** false; active differential equations and
  frequency ownership came from different controller families.
- **A GFM must always contain a PLL:** false for this VSG formulation. The GFM
  internal angle is integrated from virtual speed and does not synchronize
  through a PLL.
- **The DC-link state must remain frozen:** false. The energy balance supports a
  physical dynamic state once the missing source-current port is declared.

## Correction

- Added a fixed 20-state shared-plant production device with common
  `[i_d,i_q,V_dc]`, eight GFL-only controller states including PLL, and nine
  GFM-only VSG/voltage/current states with no PLL.
- Registered the new factory only for `eecon49_figure4`; mission profiles keep
  their established REGFM/WECC/RMS10 contracts.
- Froze all four source-case IBRs to the source-defined 100-MVA device base and
  their explicit P/Q schedules and controller parameters.
- Closed the unpublished `I_dc` port with a documented `PROJECT_DERIVED`
  current-source DC regulator using exact instantaneous converter-power
  feed-forward and `T_dc=0.10 s` proportional voltage restoration. This gives
  `dot(V_dc)=(V_dc,ref-V_dc)/T_dc` without moving the AC equilibrium.
- Corrected the third fixed input from a nominal unused compatibility slot to
  the case-defined external `E_ref` consumed by the GFM amplitude equation;
  reduced equilibrium keeps `Q_ref,E_ref` immutable and solves terminal Q.
- Added strict metadata and mode-aware state inventory support. The existing
  per-device severity release and right-limit KCL transaction remain the only
  post-reclose path; no SG-reclose hard-code was added.
- Added event-local Rannacher restart: two backward-Euler half steps after a
  discontinuity, followed by the canonical implicit trapezoidal method.
- Removed manual GFM/reference tuples from the production/report launchers.
  The authenticated exhaustive selector evaluates every subset/reference pair
  and ranks only candidates passing equilibrium, limits, and physical SSSA.
- Rebuilt the English and Thai reports from the corrected equations. The Thai
  report is the detailed primary document, including all 15 selector candidates,
  complete physical SSSA mode/state inventories for both feasible formations,
  and raw-only trajectory figures with no synthetic overlay.

## Verification

- Final targeted producer/consumer/failure-path set on the implemented tree:
  71/71 PASS. It checks exact state/input ownership, the independent `E_ref`
  coefficient, standalone RHS/current identity, DC restoration, VSG-owned GFM
  angle, GFL PLL response, transfer continuity, rigid-frame covariance, SCR,
  equilibrium/physical SSSA, both integration methods, rollback, reclose, and
  index-driven handback.
- The authenticated SG-off selector evaluates 15 candidates. Only one-GFM
  `[5]` with reference 5 and four-GFM `[2 3 4 5]` with reference 2 are feasible;
  the frozen ranking chooses the former. Their physical SSSA margins are
  `0.0757499849651` and `2.24485077` 1/s respectively.
- The fresh 200-s hybrid gate and final numerical metrics are pending.

## Limitations

- `T_dc=0.10 s` is a project design choice, not a published parameter and not
  a fitted value. Sensitivity claims require a separately declared study.
- Limiter and anti-windup realization remain project-owned numerical choices.
- Reports must describe the project-owned physical equations without naming or
  citing the internal comparison source, per user instruction.

## Related files

- `+ibr/eecon49_dual_mode_model.m`
- `+ibr/gfl_eecon49_full_model.m`
- `+ibr/gfm_eecon49_full_model.m`
- `+ibr/device_contract_metadata.m`
- `+cases/scenario_ieee14_1sg_4ibr.m`
- `+stability/build_mixed_resource_devices.m`
- `tests/test_ibr_eecon49_dual_mode_model.m`
- `docs/project/EECON49_GFL_GFM_SOURCE_CONTRACT.md`
