# SWEEP-2026-07-21-02 — SSSA load-sweep plot mapping

Status: `RESOLVED`

## Observation

At starting commit `3379688` on MATLAB R2025a, the load-sweep renderer joined
raw eigenvalues from one operating point with lines and interpreted the number
of adjacent point-to-point assignments as the number of modes. Consequently,
the tracked plots showed three apparent modes for both the 10-state GFL and the
4-state GFM, and the frequency plot omitted the final load point. The renderer
also had no accepted-equilibrium `i_d`, `i_q`, `P`, and `Q` product.

## Reproduction

Run either loaded-SMIB case at `[0 20 40 60 80]`, save plots, then inspect
`plot_A_eigenvalue_overlay`, `plot_D_tracked_trajectories`, and
`plot_E_freq_damping_vs_load`. The old Plot D loop iterated over
`numel(seg.matches)`, which is `number_of_load_points - 1`, rather than the
device's runtime active-state count.

## Root cause and falsified hypotheses

The numerical SSSA products were not missing roots: every raw GFL spectrum had
10 roots and every raw GFM spectrum had 4. The defect was a reporting-index
error. `seg.matches{k}.assignment` maps raw indices between two adjacent load
points; it is not itself a modal trajectory. Plot A additionally used a line
style that visually connected unrelated raw roots.

## Correction

- Build a cumulative `tracked_indices(point,mode)` permutation from the
  pairwise assignments and validate it as a full one-to-one map.
- Preserve and plot every raw eigenvalue; Plot A uses markers only and retains
  a separately labelled low-frequency detail without replacing the full view.
- Derive Plots G--J from the accepted device reconstruction, with `i_d`,
  `i_q`, `P`, and `Q` in separate figures. GFL `i_d/i_q` are
  native states. GFM-no-PLL has no current state, so its displayed dq current is
  explicitly classified `PROJECT_DERIVED_DIAGNOSTIC_VSM_FRAME_TRANSFORM` and
  does not feed any equation.
- Compute `P+jQ = V*conj(I)` independently and fail closed above `1e-10` pu.
- Include the unswept base point in the default `[0 20 40 60 80]`.

## Verification

`tests/test_sssa_load_sweep.m`: 31/31 PASS after adding checks for cumulative
mode identity, 10/4 modal dimensions, raw-spectrum equality, native/derived dq
current provenance, power identity, four scalar-plot files, and single-point tables.
Final delivery reruns the proportional targeted launcher consumers only.

## Limitations

The GFL spectrum's large positive real root is retained and reported; it is not
removed or rescaled by this display correction. GFM dq current is a reporting
coordinate transform, not an additional GFM dynamic state. No full repository
regression was run, per explicit user instruction.

## Follow-up: desktop figures closed after rendering

The renderer originally called `close(fig)` unconditionally after every save,
so `sssa_plot_visible=true` briefly displayed each graph and then removed it.
The save path now retains visible desktop figures and closes only invisible
headless figures. A targeted test asserts that visible figure handles survive
the renderer return and cleans them up afterward.
