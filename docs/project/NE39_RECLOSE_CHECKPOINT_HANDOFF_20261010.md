# NE39 SG reclose — durable checkpoint handoff (2026-10-10)

## Receipt — three commits made and PUSH VERIFIED

- **Main primitive:** `81462daa643e73de633081e26bbdb1828eeee920` (7 files, 1832+/6-).
- **Broad source/tests/docs WIP:** `67c3a731ef5d967bff528ba60f7ed198000dfadb` (257 files, 18610+/2905-), exact allowlist checked with excluded files preserved.
- **DSH installer:** `1e9b3d6e59b261d3cbc29814cbb4f34e05c0fe50` (2 sources, 151+), source-only, never executed, no bin/obj payload.
- All on `checkpoint/ne39-160s-20261009`; latest remote hash exactly `1e9b3d6e…` (**push verified**). The **16 staged deletions matched their saved baseline after every commit**.
- Pre-checkpoint wording in this document (e.g. §4a "Prepared for committed checkpoint", §7/§8 pending language) is **historical and superseded by this receipt**. This receipt's own commit hash is **unknown here — do not invent it**; read `git log` after `1e9b3d6e…` and the commit that contains this receipt.
- Evidence limits unchanged: only **43/43** primitive (`pwsh-215`) and **116/116** broader offline contracts (`pwsh-244`) were actually run — the five wiring core files and their test sit in the broad WIP with reviews **open**, the wiring child is **inactive/stopped**, no MATLAB is running, and there is **no actual reclose, no new 160 s run, and `.001` NOT RUN**.

**Committed session handoff, not a completion certificate.** This document records the task state of the opt-in reduced SG31 reclose primitive at the moments of the checkpoint commits. It is written to `docs/project/` so a later session can read it from the repository; read `git log` for the commits that contain it.

Authority: the latest direct human instruction is to **create the checkpoint commit and explain everything plus the next step for another session**. The human's active engineering objective is:

> "แก้สิครับทำให้มัน reclose เราออกแบบเพื่อทดลองและนำไปใช้ได้ค่อนข้างจริง"

i.e. make the NE39 SG reclose work, with a design defensible enough to experiment with and reasonably use — not merely a numerically converging close. **The reclose is NOT fixed.** No actual reclose is claimed anywhere in this document.

- Goal record on the parent side: `goal-ab2c4b09-340c-4e29-8d02-b4141741da66`, revision 1, max 30 rounds. The goal is currently **paused because the harness does not permit the resume action**; this is recorded as paused, not falsely active and not complete.
- Worktree: main [Power-flow](<C:/Users/User/Desktop/Power-flow/>) tree, branch `checkpoint/ne39-160s-20261009`, HEAD **`38ad0b83a60aa6aaa71d75655336e658d64847b2`** at the time of writing (already pushed; it is the ledger-only checkpoint, 1 file / 59 insertions). The main checkpoint described here is the commit that contains this document.
- **Immutable evidence:** the old real-160 raw remains [raw.mat](<C:/Users/User/Desktop/Power-flow/output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827/raw.mat>) SHA256 `ED4670EB853E4C29AAD426985F9BCA382D78004C61E947AB9B0C332DA696E85E`. Do not overwrite or rerun it; postprocessing reads are allowed.

## 1. What this checkpoint contains

Main checkpoint = **7 files**: the five primitive files, the ledger, and this handoff. Working-tree paths/contents were observed while writing this note; the parent verifies the exact commit contents and re-checks hashes at commit time. This document asserts **no hash for itself** (no recursive self-reference) — read `git log` / the parent's receipt for the commit that carries it.

| File | SHA256 observed at handoff | Role |
|---|---|---|
| [+stability/ne39_sg_reclose_plant_params.m](<C:/Users/User/Desktop/Power-flow/+stability/ne39_sg_reclose_plant_params.m>) | `0DEF094EF97C142A6BCEB8A78DDA715B8F5661F967232A379483AC1F7B138852` | NEW frozen `PROJECT_DERIVED` parameter builder |
| [+stability/sg_classical_reclose_device.m](<C:/Users/User/Desktop/Power-flow/+stability/sg_classical_reclose_device.m>) | `B84CC81327BBDA817AD0FE088A49D3AF44BAD65C54C7AD1D79EED2B2350A2C84` | NEW opt-in 7-state device factory |
| [+stability/sg_prospective_close_metrics.m](<C:/Users/User/Desktop/Power-flow/+stability/sg_prospective_close_metrics.m>) | `F40BD6A7842C3BA1195696E09877D517FBD44427B6AA6BB6F4CDAA10EB437E11` | MODIFIED: opt-in explicit-rating branch |
| [tests/test_ne39_sg_reclose_plant.m](<C:/Users/User/Desktop/Power-flow/tests/test_ne39_sg_reclose_plant.m>) | `59DDDD3EEBD431109C8E5BAE33E4B06727C714CA7D94B446A19E8469930434BB` | NEW plant tests (14) |
| [tests/test_ne39_sg_reclose_rating.m](<C:/Users/User/Desktop/Power-flow/tests/test_ne39_sg_reclose_rating.m>) | `0ED42283BC11DA6EDA1CF4DFC04E4831D5241473F93D482B54CC6439B293DFEE` | NEW rating tests (15) |
| [docs/project/NE39_TAMU_MIGRATION.md](<C:/Users/User/Desktop/Power-flow/docs/project/NE39_TAMU_MIGRATION.md>) | appended primitive-evidence section | Ledger |
| this document | (no self hash) | Durable session handoff |

Excluded from the checkpoint: the 16 user staged deletions, `raw.mat`, `tmp/`, caches, `bin/`, `obj/`, source archives, and generated artifacts.

## 2. Why the old design failed (root cause)

The published runtime reduces SG31 to a constant-EMF classical two-state machine `[delta, omega]` with **source `D=0`** and a **frozen positive `Pm`**. Once the breaker opens, `Pe=0` while `Pm` stays at its pre-trip value, so the rotor accelerates monotonically: `H_system=30.299999 s`, `domega/dt=0.09083237758246307 pu/s` constant, absolute speed 1 → 12.354047197811518 (145 s) → 13.7165 (160 s), open-circuit EMF staying 1.2338630347189892. The 150-s timeout reports `dV=0.20853053924627685 > 0.05`, `df=11.808209075419386 > 0.001`, `dtheta=87.51503400875991 deg > 10`, and the SG never closes (`actual_reclose_time=NaN`, `SYNC_TIMEOUT`).

Two falsified shortcuts are recorded so they are not retried:

- **Non-negative valve closure alone is insufficient.** With `Tsv=.2`, `Tch=.4`, valves shut to `Pref=0` and no shaft-loss term, speed settles at `1.0544537398986964 pu` after 5 s and stays there forever (parent `pwsh-71` disproof).
- **A nominal-frequency-only phase law is insufficient.** At ±0.1 Hz the nominal-only target fails `df<=.001` / `dtheta<=10 deg` (parent `pwsh-83`), which is why real frequency-tracking states were authorized.

Guards were checked and are **not** unit-buggy: `sg_speed_deviation` is `omega_ABS − 1` (plain subtraction, not the mathematical `abs`), and the voltage guard uses the correct open `E`.

## 3. The implemented primitive (opt-in, PROJECT_DERIVED)

`stability.ne39_sg_reclose_plant_params(case_data,opt)` → frozen parameter record; `stability.sg_classical_reclose_device(case_data,device_id,bus_id,bus_position,bus_ids,V0,params)` → opt-in device. Both are opt-in; existing defaults are untouched.

- **States `nx=7`:** `[delta, omega, Psv, Pm, Emag, theta_hat, nu_hat]`, with `omega` absolute pu so the existing `sg_speed_deviation` stays valid. `nu_hat` is the estimated frequency deviation in rad/s; `theta_hat` is the local terminal phase estimate.
- **Inputs, honestly named `[P_ref, Emag_ref]`:** these are **reference commands**, not the actual `Pm`/`Emag` states; source `H`/`D`/`Xdp` are preserved unchanged.
- **Shaft power balance:** `2*H_system*omega*domega/dt = Pm - Pe - L0*omega^2` (source `D=0` retained; the windage `L0` is a separate declared term), with real non-negative valve/steam-chest states under `0 <= Pc,Psv,Pm <= Pmax`.
- **Phase tracking:** local-terminal PLL (`e_pll = wrap(phase_bus - theta_hat)`, `theta_hat_dot = nu_hat + pll_Kp*e_pll`, `omega_hat = 1 + nu_hat/w0`) — no hidden read of another device's omega.
- **Experimental declared constants:** windage `L0 = 1% of P0`, governor lags `Tsv=.2 s`, `Tch=.4 s`, `Emag` lag `.5 s`, capture `wn=.2 rad/s`, `zeta=1`.
- **No reset / no fake close:** the rotor and internal EMF are never reset or frozen, no negative mechanical power or brake is introduced, and no synchronism gate is relaxed.
- **Rating basis:** the stator rating is an explicit `S_rated_MVA` derived from the frozen Pmax/Q envelope times margin `1.1`, labelled `PROJECT_DERIVED`. Source `MBASE=100` is a **normalization only** and is never used as a stator/thermal rating.

## 4. Test status — definitive result recorded

The focused suite is **43 tests**: plant 14, rating 15, legacy prospective 2, speed 4, classical adapter 8, plus the **real online-factory closure check** (`f_inf < 1e-8`, `Pe = P_ref`, actual `Pm = Pe + L0`, true factory, explicit prospective rating).

- **DEFINITIVE `pwsh-215` — COMPLETED exit 0: 43/43 Passed, 0 Failed, 0 Incomplete**, with the five suites run **isolated** (`addpath` + `pf_init_paths` before every suite).
- **Real online factory closure passes:** `nx=7`, `f_inf=1.717548052701395e-17`, `Pe=5.4710017489623279 pu`, actual `Pm=5.5257117664519502 pu` (loss `0.05471001748962327 pu`), rated `1162.1019748713966 MVA`, `m.passes=true`, `DECLARED_PROJECT_DERIVED`. Source `H=30.299999`, `D=0`, `Xdp=.0697` unchanged.
- **Capture test:** `+0.1 Hz` with the PLL initial-locked — slip `1.620e-11`, phase closing `0`, max transient `73.6457 deg`, eligible `19.994 s`; fixed terminal **all 7 roots** stable (max real `-0.1539610`, min real `-5.324784`).
- **Fixture-vs-physics history, stated once and correctly:** the earlier combined `39 pass / speed 4 Incomplete` (`pwsh-169`/`pwsh-135` family) was a **fixture path-ordering defect and not physics** — the legacy [tests/test_sg_prospective_close_metrics.m](<C:/Users/User/Desktop/Power-flow/tests/test_sg_prospective_close_metrics.m>) `setupOnce` teardown calls `rmpath(root)` and removes the caller root after the rating fixture. **The new rating fixture is not at fault**; it already snapshots `path` and restores it. `pwsh-215` solves this by reinitializing the path before each suite, **without editing the legacy test and without weakening any assertion**.
- **Lint:** factory cleanup is done and the source files are clean **except one remaining `unused tf=false` warning in the metrics helper**; recorded to fix later, and **not** a claim that all files are warning-free.
- **Earlier context:** parent `pwsh-130` plant 14/14; parent `pwsh-109` rating 16/17 with one bad test constant (`I=5` against the `6.0 pu` circle), fixed to `I=7`.

## 4a. Commit state of this document

**Main checkpoint committed:** `81462daa643e73de633081e26bbdb1828eeee920` — `checkpoint(ne39): preserve governed SG primitives and reviewed reclose handoff` — carrying the 7 files of §1 (diffstat **1832 insertions / 6 deletions**). This document is inside that commit; read `git log` forward from it for anything later. The 16 staged deletions still matched their baseline patch exactly after the commit.

- **Push VERIFIED:** `pwsh-255` collected **exit 0** and the exact remote hash matches `81462daa643e73de633081e26bbdb1828eeee920` — the main checkpoint is published. The index's 16 staged deletions still matched their baseline patch after the commit.
- **Frozen:** the ledger [docs/project/NE39_TAMU_MIGRATION.md](<C:/Users/User/Desktop/Power-flow/docs/project/NE39_TAMU_MIGRATION.md>) is part of the committed main checkpoint and is **not edited again** for this work.
- **Next (broad WIP commit):** the remaining source/tests/docs work, including the four wiring patches and the new wiring test with the **major review finding still open**, with no new actual close. Its tested basis is `pwsh-244` offline contracts **116/116 PASS** plus `pwsh-215` primitive **43/43 PASS**. Global grouping, exclusions and next-session limitations live in [WORKTREE_CHECKPOINT_20261010.md](<C:/Users/User/Desktop/Power-flow/docs/project/WORKTREE_CHECKPOINT_20261010.md>).

## 5. Explicit non-claims

- **The installed capture test covers the `+0.1 Hz` tracker case ONLY, with the PLL initial-locked.** It is **not** a claim of full ±0.1 Hz field capture. Earlier ±0.1 Hz results come from **parent feasibility screens** (`pwsh-83` nominal-only disproof, `pwsh-84` tracked-PLL screen), which are diagnostics, not repository tests.
- The real online-factory closure check **passed** (§4) but is a closure/consistency check — **not** an actual reclose.
- This is **not** full-network SSSA, not private-trial coverage, and not a new chronology. No new short or full reclose run has been performed, and adaptive `max_step=.001` remains **NOT RUN**.
- **Sensitivity limit flagged:** with a `0.5%` no-load loss the phase reaches `16.81038988 deg`, outside the `10 deg` criterion (parent `pwsh-86`); the declared `1%` default is therefore an explicit feasibility limit, **not field-ready**.
- The three old 160-s verdicts are unchanged and are not reinterpreted here: accepted-sample study **PASS** (16051 samples, nonvoltage 0 / UNKNOWN 0), **strict voltage FAIL** (169 voltage-only samples), **actual reclose FAIL** (`SYNC_TIMEOUT`, `actual_reclose_time=NaN`). `production_certified=false` throughout.

## 6. Separate work in progress — not in this checkpoint

The four actual wiring files (verified present on disk) are:

- [+cases/scenario_ne39_tamu_mixed.m](<C:/Users/User/Desktop/Power-flow/+cases/scenario_ne39_tamu_mixed.m>)
- [+stability/build_mixed_resource_devices.m](<C:/Users/User/Desktop/Power-flow/+stability/build_mixed_resource_devices.m>)
- [+stability/mixed_equilibrium_solve.m](<C:/Users/User/Desktop/Power-flow/+stability/mixed_equilibrium_solve.m>)
- [+stability/mixed_ibr_reduced_initialize.m](<C:/Users/User/Desktop/Power-flow/+stability/mixed_ibr_reduced_initialize.m>)

plus [tests/test_ne39_sg_reclose_wiring.m](<C:/Users/User/Desktop/Power-flow/tests/test_ne39_sg_reclose_wiring.m>). **There is no module named `sg_classical_reclose_wiring.m`** — that name in an earlier draft was fictional and is corrected here. The parent read the four patches and raised a **major review finding: the test accepts a `deviceLimit` failure rather than a full wire pass**; the child is fixing it, so this stays **WIP until the parent tests it** and it is **not** part of the main checkpoint.

- The IEEE14 reclose workflow test ([tests/test_ieee14_ibr_sg_reclose_workflow.m](<C:/Users/User/Desktop/Power-flow/tests/test_ieee14_ibr_sg_reclose_workflow.m>)) belongs to the wiring/other-WIP track.
- Two independent review children are pending per the parent: `86cb…` (application review) and `4d52…` (numerical review). The user approved a broad source/tests/docs backup commit that **may include the WIP but must keep the 16 staged deletions** and exclude raw/tmp/cache/bin/obj/source archives/artifacts.

## 7. Next steps for another session

1. **Parent first:** the 43-test suite plus the real online-factory closure check are green (`pwsh-215`, §4); the broader offline contracts are also green (`pwsh-244`, 116/116 — see §8). Finish the remaining lint item (the `unused tf=false` warning in the metrics helper) without changing equations.
2. **Wiring:** resolve the `deviceLimit` acceptance-fixture finding, then parent-test the **five** wiring core files ([+cases/scenario_ne39_tamu_mixed.m](<C:/Users/User/Desktop/Power-flow/+cases/scenario_ne39_tamu_mixed.m>), [+stability/build_mixed_resource_devices.m](<C:/Users/User/Desktop/Power-flow/+stability/build_mixed_resource_devices.m>), [+stability/mixed_equilibrium_solve.m](<C:/Users/User/Desktop/Power-flow/+stability/mixed_equilibrium_solve.m>), [+stability/mixed_ibr_reduced_initialize.m](<C:/Users/User/Desktop/Power-flow/+stability/mixed_ibr_reduced_initialize.m>), [+stability/mixed_ibr_sg_on_gfl_initialize.m](<C:/Users/User/Desktop/Power-flow/+stability/mixed_ibr_sg_on_gfl_initialize.m>)) and [tests/test_ne39_sg_reclose_wiring.m](<C:/Users/User/Desktop/Power-flow/tests/test_ne39_sg_reclose_wiring.m>); the broad WIP commit may carry them but **labelled not validated**.
3. **Real engineering work before any reclose claim:** proper capability acceptance instead of a `deviceLimit` acceptance; all-state SG_ON/SG_OFF SSSA, refinement, synchronism geometry and voltage terminal measurement; **no fake `Pm`/rotor/gate** manipulation; then an **applied `sg_reclose`** with finite actual time, dwell and post-close constraints; a **new 160-s** run under the `.001` cap **only when ready** — never by rerunning the old 160.
4. **Goal state:** general NE39 reclose goal at **revision 2**, paused for the human and requiring a **human resume through the GUI**; the model-resume tool is **not available**, so a model retry would be a false claim. Never mark the goal complete and never repeatedly instruct a model resume.

## 8. Global checkpoint chapter (approved scope)

The checkpoint is not only this primitive. The approved global grouping, tested counts, exclusions, EOL handling and follow-ups are recorded in [WORKTREE_CHECKPOINT_20261010.md](<C:/Users/User/Desktop/Power-flow/docs/project/WORKTREE_CHECKPOINT_20261010.md>). In brief: group 1 = this main 7-file primitive commit (43/43 + online closure); group 2 = the broad source/tests/docs WIP commit, which carries the broader offline contracts **116/116 PASS** (`pwsh-244`: events 26, AI 80 with `force_fallback` and no outbound, studio-no-wizard 2, case visibility 5, inventory fail-closed 3) and still-unvalidated wiring; group 3 = the separate DSH installer WIP, never executed. That document also holds the exclusion list (`bin`/`obj` payloads, `*.fig`/`*.nav`/`*.snm`, `*_review*.png`, `backup_slides_v15.*`/`ref_v15*`/`presentation.backup.*`), the **54-file LF-vs-CRLF "save as found"** rule, the three unfixed TeX whitespace warnings, the stale-not-run `test_ieee14_multi_gfm_equilibrium`, and the warning that plain `ne39` is the 10-SG RTS-derived case, **not** this TAMU 1SG+9IBR case. No actual reclose is claimed by any group.

## 9. Sources for this handoff

Written from the actual new files and the parent's messages, not from the older continuation note ([tmp/ne39-reclose-pm-continuation-20261010.md](<C:/Users/User/Desktop/Power-flow/tmp/ne39-reclose-pm-continuation-20261010.md>)), whose statuses are historical. This writer ran no MATLAB, started no jobs or agents, and made no git/index/process changes.
