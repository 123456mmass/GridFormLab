# Benchmark report — C++ TS engine vs MATLAB golden (NE39, 160 s)

Date 2026-10-16 · author report-dev · status: measured values only, optimize ladder **CLOSED**.
No git commit. Every number is read/decoded from disk; none carried over from chat.

## 0. Identification
| field | value |
|---|---|
| C++ runs | `D:\4-year-project\GridFormLab-port\runs\{cxx_bench_160s_run1..3, ..._h500us, perf_*}` |
| C++ parity golden | `...\runs\stage2_smoke_ne39_008_gfm160s_golden` |
| MATLAB golden | `...\GridFormLab-experiment\output\diagnostics\bench_160s_armA_20261014_113418_825` |
| machine · MATLAB | Intel i5-14400F, 10 cores, 31.8 GB · R2026b 26.2.0.3386108 |

## 1. Wall clock — measured
| run | `elapsed_wall_s` hex | wall (s) | steps | ms/step | note |
|---|---|---|---|---|---|
| `cxx_bench_160s_run1` | `0x40726A6F06B37868` | **294.652106** | 160000 | 1.842 | clean |
| `cxx_bench_160s_run2` | `0x4072C3F9CC74B839` | **300.248486** | 160000 | 1.877 | clean |
| `cxx_bench_160s_run3` | `0x407EF9F22E1AC57E` | **495.621626** | 160000 | 3.098 | **outlier, machine load** |
| `cxx_bench_160s_h500us` | `0x408701A9C3CE208A` | **736.207893** | 320000 | 2.301 | h = 0.5 ms |
| run008 (reference) | `0x4074F98E736049ED` | **335.597278** | 160000 | 2.097 | parity golden |
| `perf_clean_fd160s` | `0x4071A4F5EA67E847` | **282.31** | 160000 | 1.764 | after rung 1b |
| `perf_clean_col160s` | `0x4055128FB86F47B6` | **84.29** | 160000 | 0.527 | **after coloring** |
| `perf_rung4_160s_omp` | `0x405522CE9E5E2479` | **84.544** | 160000 | 0.528 | + OpenMP |
| `perf_rung4b_20s` | `0x406B80F82F512663` | **220.03** | 20000 | 11.00 | **barrier-bound, reverted** |

MATLAB golden = **1972.521620 s** (frozen anchor 6708.725530 s informational only). **Clean band 294.7–300.2 s, mean
297.45 s**, run3 excluded. Unoptimized: MATLAB/clean-pair = **6.63x**, MATLAB/run008 = 5.88x. **Optimized headline:
`perf_clean_col160s` 84.29 s = 3.98x vs run008, ~23x vs MATLAB.**

**Comparison conditions — read before quoting any ratio**

- C++ **fixed-step h = 1 ms**, 160000/160000 accepted, 0 failed, 300126 Newton iters = 300126 Jacobian evals (`h = 0.5 ms`: 320000 steps, 413253 iters).
- MATLAB golden is the **adaptive strict-LTE** stepper (rejected 50, Newton 64052, mean 6.7974, max 73) — not the same stepper.
- **MATLAB `maxNumCompThreads` = 10** (`threads=10 cores=10`), `gcp` pool = 0, `parfor=0 fallback=0 serial=0`.
- **C++ benchmark runs are single-threaded** (runbook `g++` has no `-fopenmp`); `PARITY_FLAGS := -O2 -ffp-contract=off -fno-fast-math`, changed to `-O3` at rung 3. So the headline is *MATLAB on 10 threads vs single-threaded C++* — not like-for-like; rung 4's OpenMP changes this later.

## 2. DISCREPANCY — 335.6 s / 386.2 s (resolved 2026-10-15)
run008 hex `0x4074F98E736049ED` = **335.597278 s** is the real value; **no 386.2 s in any manifest** (misread decode).

## 3. Profile breakdown — where the wall time went (pre-optimization)

`%TEMP%\cpp_perf_profile.txt` (rung P, measurement only; 5 s probe, 5000 steps, timed loop 14.241 s, nz = 238).

| phase | share | seconds |
|---|---|---|
| `jacobian_fd` | **81.483 %** | 11.603642 |
| `lu_factor_solve` | **13.148 %** | 1.872401 |
| `accept_io` | **4.810 %** | 0.684931 |
| `residual_base` / `regime_freeze` / `events_guard_p0` | 0.503 / 0.053 / 0.002 % | 0.0717 / 0.0076 / 0.0003 |

Structural: `jacobians == newton_iters == lu` (8126 each) → full FD rebuild on every Newton iteration, no reuse; 239
residual evals per build (238 perturbed cols + 1 base). Use the **percentages** — the probe's absolute ratio is load-inflated.

## 4. Ladder optimize — **CLOSED** (measured; source `%TEMP%\cpp_perf_consolidated_final.md`)

Rows bind to the **work**; the rung column is team-lead's 2026-10-15 numbering ("ห้ามสลับ", do not reorder).

| rung | work | wall (s) | same-window speedup | parity | status |
|---|---|---|---|---|---|
| 0 | baseline run008 (manifest) | 335.597 | — | (reference) | DONE |
| 0b | baseline clean band (bench) | 294.7–300.2 | — | (reference) | DONE |
| P | profile 5 s probe (measurement only) | — | — | n/a | DONE 17:00 |
| 1 — "rung 3" in older briefs | Jacob/LU reuse + warm start | — | — | FAIL 4/4, **guard-config artifact** | **REVERTED** (no speedup) |
| 1b | alloc removal + S2Scratch hoist | 282.31 | — | 0/160000×42, four PASS 0.0 | **GATE A PASS** |
| 2 | FD → sparse coloring (structural superset) | **84.29** | **~2x** | 0/160000×42, four PASS 0.0 | **GATE A PASS** |
| 3 | build flags `-O3` → `PARITY_FLAGS` | 9.847 (20 s) | **0.99x neutral** | **bitwise 0.0**, 160000×42 | **KEPT (0.0 diff)** |
| 4 | OpenMP FD columns | 84.544 | **1.52x on coloring** | 0/160000×42, four PASS 0.0 | **GATE A PASS** |
| 4b | parallel LU (bit-identical) | 220.03 (20 s study) | — | 0/20000×42 prefix PASS | **no-win → serial LU** |
| 5 | larger h | — | — | — | **OUT** — own gate + user approval only |

**Ratios are same-window only** — machine speed drifts **1.5–1.6x within a day** (measured from controls), so every
ratio is a pair measured back-to-back in one window; **cross-window ratios are forbidden** (wall times stay valid as
run-bound measurements). **Decomposition (20 s window):** `perf_check_fd20s` 19.906 → `perf_check_col20s` 6.639 =
**3.00x** combined; OpenMP alone `perf_rung2_20s_struct` 10.128 → `perf_rung4_20s_omp` 6.670 = **1.52x** → coloring
≈ **~2x**; FD phase chain 227.7 → 52.2 → 20.3 s. **160 s headline (same window): 282.31 → 84.29 = 3.35x** = coloring
~2x × OpenMP ~1.5x. **Corrected 2026-10-16:** `perf_clean_col160s` and `perf_rung4_160s_omp` **both already carry
OpenMP** (jac_fd 20.60 vs 20.27, identical 8319061 residual evals) — the old "OpenMP no profit" compared two
same-config runs. ~23x vs MATLAB 1972.5 s is cross-window/cross-engine — context only.

**Rung 1 — the +14.65 s reclose shift was a guard-config artifact, not solver divergence.** The FAIL is real, but a
**bit-identical build fails with identical figures** (`cpp_perf_parity_1b.txt` == `cpp_perf_parity_rung1_reuse.txt`:
dV 5.883e-2, dω 4.289e-3, reclose 115.1480 vs 100.4990, drift 4.7989e-1) because the test ran `dtheta 0.5°` where
run008 uses `10°`. Isolating the variable gives **1.586e-10** with **reclose 115.1480 = 115.1480 (diff 0.0000)** —
the event does not move. Row stays FAILED/REVERTED, no speedup; `jacobian_evals` 300126→160000 (−47 %) stands. Reuse
passes GATE B at 1.586e-10 but the code is out of the tree, so **no measured speedup**.

## 5. Parity gate — two-tier, binding for every rung

**GATE A** (path-preserving: alloc / coloring / OpenMP / parallel-LU): trajectory diff **exactly 0.0**.
**GATE B** (path-changing: reuse / -O3 bonus): max diff **≤ 1e-9** + event times equal to golden + all four criteria
with margin. Both carry: `|dV| < 1e-3 pu` · `|dω| < 1e-4 pu` · reclose diff `< 1 s` · rotor angle by **drift rate**
(max 1 s block-averaged, tol 0.0377 rad/s). Canonical `%TEMP%\cpp_perf_parity.py`: `ok` covers all four, **exit 1**
on FAIL, exit 2 on fatal preconditions, dies on row-count mismatch. Self-test golden-vs-golden: all four **PASS** 0.000e+00.

**Physics caveat — study event times track the guard policy, not solver detail.** The dtheta threshold moves reclose
by 14.6 s (0.5° vs 10°) while solver-path divergence measures **1.586e-10** — orders apart. ‖r‖/σ_min(J) stays a
theoretical risk, but the confounded experiment overstated it: measured amplification ~0.016, not ~1e6. Read event
times as **guard-policy settings**, not numerical noise; the 100.499 s (C++) vs 119.52 s (MATLAB) gap is policy, unchanged.
**Rule found: every run must use run008's guard config (`GFL_S1_SYNC=frozen`, `GFL_S1_P0GATE=off`) or the gate measures config, not code.**
