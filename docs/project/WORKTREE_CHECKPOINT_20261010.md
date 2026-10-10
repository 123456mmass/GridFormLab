# Worktree checkpoint — global groups and eligibility (2026-10-10)

## 0. Receipt — all three commits made and PUSH VERIFIED (supersedes §1/§8 pending wording)

- **Main primitive:** `81462daa643e73de633081e26bbdb1828eeee920` — 7 files, 1832 insertions / 6 deletions.
- **Broad source/tests/docs WIP:** `67c3a731ef5d967bff528ba60f7ed198000dfadb` — 257 files, 18610 insertions / 2905 deletions; the exact allowlist was checked and the excluded files are present (not deleted).
- **DSH installer:** `1e9b3d6e59b261d3cbc29814cbb4f34e05c0fe50` — 2 sources, 151 insertions; source-only, **no execution**, no bin/obj payload.
- All three are on `checkpoint/ne39-160s-20261009`; the latest remote hash is exactly `1e9b3d6e…` (**push verified**). The **16 staged deletions matched their saved baseline patch after each commit**.
- §1 and §8 below were written **before** these commits: their "pending"/"prepared"/"before the commit" wording is **historical and explicitly superseded by this receipt**.
- This receipt document's **own commit hash is unknown here — do not invent it**; the next session reads `git log` after `1e9b3d6e…` and the commit that contains this receipt.
- Tested basis is only what actually ran: **43/43** primitive (`pwsh-215`) and **116/116** broader offline contracts (`pwsh-244`) — **not** a full-test, reclose, or field result. The five wiring core files plus their test are inside the broad WIP with reviews **open**; the wiring child is **inactive/stopped**, and the last snapshot shows **no MATLAB**.

Purpose: one durable place that tells the next session **what must be saved from this working tree, in which commit group, what is tested, what is known-untested, and what must stay out**. Written at the checkpoint; the receipt above is the authoritative commit state, and later sessions should read `git show` on the commits that **contain these documents** for the canonical, exact file list.

## 1. State before the checkpoint commits

- Branch `checkpoint/ne39-160s-20261009`. The **main checkpoint is committed and REMOTE-VERIFIED**: `81462daa643e73de633081e26bbdb1828eeee920` — `checkpoint(ne39): preserve governed SG primitives and reviewed reclose handoff` (7 files, 1832 insertions / 6 deletions). `pwsh-255` collected **exit 0** and the exact remote hash matches, so the push is verified.
- After that commit, the 16 staged deletions still matched their baseline patch exactly.
- The parent's broad candidate set is **257 named source + docs paths, exact and verified** (see §2b). Do **not** quote a hand-tallied miscellaneous tracked/untracked total: for the exact file paths, `git show` on the commit that contains these documents is the canonical list.
- Preservation rules unchanged: keep the **16 user staged deletions** as they are, do not `git add .`/`git reset`/rewrite history, never commit artifacts, caches, or generated binaries, and **preserve the excluded files below — exclude means do not commit, not delete**.

## 2. Commit groups

| # | Group | Contents | Test status |
|---|---|---|---|
| 1 | **Main primitive — COMMITTED** | `81462daa643e73de633081e26bbdb1828eeee920`: the 5 NE39 reclose primitive files + the migration ledger + the [NE39 reclose checkpoint handoff](<C:/Users/User/Desktop/Power-flow/docs/project/NE39_RECLOSE_CHECKPOINT_HANDOFF_20261010.md>) | `pwsh-215` **43/43 PASS** + real online-factory closure PASS (§4 of the handoff) |
| 2 | **Broad source/tests/docs (WIP label)** | the remaining source, tests and project docs WIP, including the **five** wiring core files and the new wiring test | parent `pwsh-244` **OFFLINE contracts 116/116 PASS**; wiring still WIP (§3) |
| 3 | **DSH installer WIP (separate)** | the two DSH program sources, source-only, which include an installer that is **never executed** | not run here |

The main primitive group is committed **first**; the broad group commits second; the DSH installer group third and separately. Groups 2 and 3 are still **pending** and must be labelled **WIP / not validated** — except where the 116/116 offline contracts are explicitly cited.

## 2a. Honest limits carried into the broad commit

- **The whole full test suite was not run**, and there is **no field verification** of any kind. Cite only `pwsh-215` (43/43, main commit) and `pwsh-244` (116/116 offline contracts).
- The broad commit is a **snapshot of work in progress**, not a validated release; the wiring review finding stays open.
- **No actual SG reclose exists in any group**, and no new full chronology was run.

## 2b. Broad group candidate set (257 named source + docs paths)

The parent holds the broad allowlist: **257 named source and documentation paths**. Derivation rules and omissions:

- **Included:** the broad source/tests/docs WIP, including the **five** wiring core files plus [tests/test_ne39_sg_reclose_wiring.m](<C:/Users/User/Desktop/Power-flow/tests/test_ne39_sg_reclose_wiring.m>), and the legitimate `report_*.tex` / `report_*.pdf` items — included **as docs WIP, not rendered/verified**. Parent-verified group counts: docs 34, `+ai` 15, `+cases` 10, `+events` 6, `+studio` 14, `+pfapp` 72, `+wizard` 6, `+stability` 12, tests 39, scripts 30, and the remainder as listed by `git show`.
- **Excluded:** the **DSH setup (two files)**, which is its own separate source-only commit; `raw.mat`; `tmp/`; caches; `bin`/`obj` payloads; `*.fig`; `*.nav`; `*.snm`; `backup_slides_v15.*`; `ref_v15*` present derivatives; `presentation.backup.*`; `*_renders*.png` and other render PNGs; and the source archives.
- **No full 257-file table is duplicated here.** For the exact file paths, use `git show` on the group's commit and the group sections in this document; that is sufficient for the next session and avoids a second fragile manifest.

## 2c. Wiring group — actual current state (not a completed diff)

- The wiring child `a462…` was **interrupted to prioritize the user's checkpoint request**; no process was killed, and **no MATLAB job from the wiring work is running now**. Earlier check/concatenate PIDs (`40500`/`31016`) are gone, so their outcome is **unknown and must never be claimed as PASS**.
- The actual wiring set is **five core files plus the wiring test** (verified present on disk), all **WIP and not yet tested**:
  - [+cases/scenario_ne39_tamu_mixed.m](<C:/Users/User/Desktop/Power-flow/+cases/scenario_ne39_tamu_mixed.m>)
  - [+stability/build_mixed_resource_devices.m](<C:/Users/User/Desktop/Power-flow/+stability/build_mixed_resource_devices.m>)
  - [+stability/mixed_equilibrium_solve.m](<C:/Users/User/Desktop/Power-flow/+stability/mixed_equilibrium_solve.m>)
  - [+stability/mixed_ibr_reduced_initialize.m](<C:/Users/User/Desktop/Power-flow/+stability/mixed_ibr_reduced_initialize.m>)
  - [+stability/mixed_ibr_sg_on_gfl_initialize.m](<C:/Users/User/Desktop/Power-flow/+stability/mixed_ibr_sg_on_gfl_initialize.m>) — the fifth file, whose parent-read target is `P_ref`/`Emag_ref` recognition; **not yet tested**
  - [tests/test_ne39_sg_reclose_wiring.m](<C:/Users/User/Desktop/Power-flow/tests/test_ne39_sg_reclose_wiring.m>)
- The parent will run a **dry wiring-regression diagnostic**, but the set is still a **current actual git diff, unvalidated** — not a frozen wiring validation, and the WIP acceptance review remains open.

## 2d. Known open items (record, do not silently fix)

- **Open fixture issue:** the legacy prospective test teardown path behaviour (`rmpath(root)`) that forced isolated per-suite runs — still open as a test-harness follow-up.
- **Stale test:** `test_ieee14_multi_gfm_equilibrium` expects a retired WECC error and was **not rerun**; likely failure, tracked as an open follow-up.
- **Doc mismatch:** personal end-point environment defaults are documented differently from the code. The read-only review found **no embedded secrets**, so this is a documentation-consistency item only.
- **Frozen core:** the classical 7-state reclose model is **FROZEN** for this checkpoint. Adaptive `max_step=.001` is **NOT RUN**; the actual-reclose verdict is **FAIL/unknown-new** and unchanged.
- **Source capture scope is narrow:** the only installed capture test is the **`+0.1 Hz` case with the PLL initial-locked** (with all 7 terminal roots stable) — it is **not** full ±0.1 Hz field capture.
- **Tested counts to cite:** `pwsh-215` primitive **43/43 PASS** (in the main commit) and `pwsh-244` broader **offline contracts 116/116 PASS**.

## 3. Tested vs known-untested

**Tested and passing:**

- `pwsh-215` — NE39 primitive focused suite **43/43 Passed / 0 Failed / 0 Incomplete** (plant 14, rating 15, legacy prospective 2, speed 4, classical adapter 8) plus the real online-factory closure: `nx=7`, `f_inf=1.717548052701395e-17`, `Pe=5.4710017489623279 pu`, actual `Pm=5.5257117664519502 pu` (loss `0.05471001748962327 pu`), rated `1162.1019748713966 MVA`, `passes=true`, `DECLARED_PROJECT_DERIVED`.
- `pwsh-244` (broader, OFFLINE contracts) — **116/116 PASS**: events 26, AI 80 (`force_fallback`, no outbound), studio-no-wizard 2, case-visibility 5, inventory fail-closed 3.

**Known-untested / not fixed in this checkpoint (record, do not claim otherwise):**

- The **five** wiring core files plus their wiring test remain **WIP**: the parent's read found the test **accepts a `deviceLimit` failure instead of proving a full wire pass**; the child was asked to fix it. Wiring is **not validated** here. Latest check: **NO MATLAB PROCESSES**.
- `test_ieee14_multi_gfm_equilibrium` is **stale** and is expected to fail with a retired WECC error; it was **not run** for this checkpoint. It is an open follow-up, and this checkpoint does **not** claim all tests pass.
- Three pre-existing **TeX table trailing-whitespace warnings** are **not fixed** — this is a checkpoint, not a refactor.
- No actual SG reclose exists anywhere in these groups. No new full chronology was run; adaptive `max_step=.001` remains **NOT RUN**. The old real-160 verdicts are unchanged (accepted-sample study PASS, strict voltage FAIL, actual reclose FAIL `SYNC_TIMEOUT`), and the 0.5 % no-load-loss sensitivity (`16.81038988 deg`, outside the 10 deg criterion) is recorded as **not field-ready**.

## 4. Line endings (important for the broad group)

- `core.autocrlf=true`; **54 files currently have LF where HEAD has CRLF**, so committing them verbatim produces whole-file EOL diffs.
- Policy: **save as found** — do **not** mass-rewrite line endings as part of this checkpoint. Note the 54-file EOL normalization explicitly in the commit message or an adjacent note so a reviewer does not mistake it for a content change.
- Known style warnings (the three TeX tables above) are intentionally left alone for the same reason.

## 5. Contents to exclude

Do **not** add these to any checkpoint group — and **preserve the files**; exclude means *do not commit*, **not delete**:

- **bin/obj payloads** and build outputs. The separate **DSH installer** is source-only and must never be executed from this checkpoint.
- Generated figure/artifact families: `*.fig`, `*.nav`, `*.snm`, `*_review*.png`, and the copies `backup_slides_v15.*`, `ref_v15*`, `presentation.backup.*` (present under [docs/source](<C:/Users/User/Desktop/Power-flow/docs/source/>) and [docs/figures](<C:/Users/User/Desktop/Power-flow/docs/figures/>)). Treat the derived wrapper/duplicate copies as excluded artifacts and leave the originals in place.
- The immutable real-160 evidence ([raw.mat](<C:/Users/User/Desktop/Power-flow/output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827/raw.mat>)), `tmp/`, caches, and the source archives.
- Legitimate report sources such as `report_*.tex` / `report_*.pdf` **are** part of the broad docs archive; include them **as found**, and **do not rebuild** them in this checkpoint.

## 6. Read-only review outcomes already established

- **No embedded secrets found in source.**
- The DSH program source set includes the installer as **separate WIP**; it is never executed by this checkpoint.
- Manifest/exclusion derivation is **read-only** — use `git status`, `git ls-files`, and globs to build the exact path list. If an exact manifest is desired, keep it appended to this global document rather than changing the index.

## 7. Two case identity facts the next session must know

1. **`ne39` as a plain case id is the 10-SG RTS-derived case; it is NOT the TAMU 1SG+9IBR case.** They are different systems and must not be conflated in tests, catalogs, or documentation.
2. The TAMU source variant is identified by `case_data.source_variant.id == 'TAMU_LEDESMA_2016'` with exactly one SG at bus 31 and nine IBRs; the reclose primitive's parameter builder enforces this composition and fails closed otherwise.

## 8. Next steps

1. Main 7-file primitive group: **committed and remote-verified** at `81462daa643e73de633081e26bbdb1828eeee920` (`pwsh-255` exit 0, exact remote match).
2. Commit the **broad source/tests/docs WIP** group second, keeping the 16 staged deletions and excluding §5. Label it honestly: wiring **not validated** (five core files + wiring test, `deviceLimit` review finding open), stale `test_ieee14_multi_gfm_equilibrium` **not run**, whole full suite **not run**, no field verification, and the 54-file EOL normalization described in §4.
3. Commit the **DSH installer WIP** third, separately, source-only, never executed.
4. **Real engineering work still required** before any reclose claim:
   - fix the wiring `deviceLimit` **acceptance fixture** so it proves a proper capability pass instead of accepting a limit failure;
   - all-state SG_ON/SG_OFF **SSSA**, refinement, synchronism geometry, and **voltage terminal measurement**;
   - **no fake `Pm`/rotor/gate** manipulation anywhere;
   - an **applied `sg_reclose`** with finite actual time plus dwell and post-close constraints;
   - a **new 160-s** run under the `.001` cap **only when ready** — never by rerunning the old 160.
5. Test-harness follow-ups: decide the fate of the stale test; fix the three TeX EOL/whitespace items only when a refactor is authorized.
6. **Goal state:** the general NE39 reclose goal is at **revision 2**, **paused for the human** and requiring a **human resume through the GUI** — the model-resume tool is **not available**, so a model retry would be a false claim. Never mark it complete; do not repeatedly instruct a model resume.
7. **Team/route constraints for the next session:** every delegation uses provider **`deepseek-official`** with model **`ocg/deepseek-v4.1-flash`** or **`azure/gpt-6-luna`** and `reasoning_effort` **max**; the parent is PM/reviewer and **does not edit files**; continue on the **current branch and current working tree** and do **not** reset.
