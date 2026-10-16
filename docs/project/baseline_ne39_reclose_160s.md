# Baseline reference — NE39 SG31 reclose 160 s

เป้าหมายของเอกสารนี้: ยึดตัวเลขอ้างอิงชุดเดียวสำหรับเทียบ optimization ทุกตัว
(แยกจาก study run ใหม่ที่ `production_certified=false`)

สถานะ: **verified** จาก baseline-extractor (2026-10-13) ด้วย cross-check 3 ทาง
(`V_bus`, `delta_sg`, `df`) ค่าตรงกันเป๊ะ

## Provenance

| รายการ | ค่า |
|---|---|
| Artifact | `output/diagnostics/ne39_reclose_applied_probe_20261011_090300_358/` |
| Documented branch | `checkpoint/ne39-160s-20261009` ที่ base `3cbb7ea` |
| **Caveat** | branch ref นั้นตอนนี้ชี้ที่ `6f73668` (ถูกเลื่อน) — `3cbb7ea` ยังเป็น ancestor อยู่ แต่**กู้คืนจากชื่อ branch อย่างเดียวไม่ได้** ต้อง pin ที่ commit |
| Script ตอนรัน | commit `f79bead` (2026-10-11 11:13) |
| MATLAB | R2026b (26.2.0.3386108) |
| classification | `PROJECT_DERIVED_TRUE_TRIP_RECLOSE_DIAGNOSTIC` |
| production_certified / hardware_certified | **0 / 0 (false)** |
| `raw.mat` | ไม่ถูกแก้ไขโดย extraction (อ่านอย่างเดียว) |

> ตัวเลือก "ตามที่รันจริง" ให้ยึด `request.mat` เป็น authoritative
> ไม่ใช่ script บนดิสก์ปัจจุบัน เพราะ script ถูกแก้เป็น variant ใหม่แล้ว
> (`budget=64`, `ne39_trial_max_steps=1200000`, `jacobian_reuse=true`,
> `post_reclose_mode_reselection=true` — **ไม่มีอยู่ใน run นี้**)

### Options ที่รันจริง (`request.mat`)

`dt=0.001`, `dt_min=6.103515625e-07` (=0.0025/4096), `dt_max=0.025`,
`dt_max_armed=0.01`, `stepper=adaptive`, `adaptive_strict_lte=true`,
`reject_limit=16`, `ne39_trial_timestep_strategy=adaptive`,
`ne39_trial_max_steps=32000`, `budget.max_full_evaluations=4`,
`budget.stop_on_first_certified=true`, `post_reclose_mode_reselection=false`,
`rannacher_n=0`, `progress_every=5`, `t_end=160`

**ไม่มีใน run นี้:** `jacobian_reuse`, `ne39_trial_adaptive_dt_max`,
`global_refinement_max_retries`, `ne39_trial_screen_horizon_s`

## Timing

| Metric | ค่า |
|---|---|
| `elapsed` | **6708.725530 s = 1.8635 h** |
| Documented | 6708.73 s — ตรงกัน |
| `equilibrium_newton_iterations` | 1 (init เท่านั้น) |
| mtime span | `request.mat` 09:03:02 → `progress.log` 10:52:39 → `raw.mat`/`audit.mat` 10:56:27 |

## Event chronology

| Event | t (s) | sample idx | หมายเหตุ |
|---|---|---|---|
| sg_trip (SG31) | 20.000000 | 1605 | applied=1; 9 GFM committed |
| fault_on (bus 16, Zf=j0.1) | 60.000000 | 5400 | applied=1 |
| fault_clear | 60.150000 | 5877 | applied=1 |
| sg_on request | 100.000000 | 9576 | applied=1 |
| **SG31 reclose** | **119.521920776** | 13493→13494 | `SUCCESS`, actual_close=true |
| horizon end | 160.000000 | 18852 | `NUMERICAL_HORIZON_COMPLETE` |

## Status / guards

- `reclose_status=SUCCESS`, `converged=1`
- `accepted_path_status=NUMERICAL_HORIZON_COMPLETE`
- `private_trial_status=STUDY_TRIAL_COMPLETE`
- `sg_off_selector` / `sg_on_selector` = CERTIFIED (`exact_all_nine_spectrum_ready=true`)
- `energy_error_pu_s=8.98e-11`, `right_kcl_norm=4.775e-10`
- guard: `dtheta=0.4627°`, `dV=1.33e-15`, `df=3.30e-6`
- `strict_voltage_status=FAIL_ON_OBSERVED_SAMPLES` (64 samples)
- `strict_nonvoltage_status=PASS_ON_OBSERVED_SAMPLES`
- `reselection_status=DISABLED_BY_POLICY`, `handback_status=NOT_STARTED`

## Counters

| Counter | ค่า |
|---|---|
| `ts_accepted_steps` | 9423 |
| `ts_step_attempts` | 9473 |
| **cumulative rejected steps (public accepted path only)** | **50** |
| `ts_newton_iterations` | 64052 (min 3, mean 6.80, max 73) |
| `ts_invocations` / `equilibrium_invocations` / `sssa_invocations` | 1 / 1 / 0 |
| `event_transactions` | 5 |
| `selector_candidate_evaluations` | 0 |
| `domain_rejected_trials` / `subdivision_depth` / `floor_accepted_steps` | 0 / 0 / 0 |
| `residual_per_step` max | 9.996e-09 |
| `dt_history` | min 6.104e-07, median 2.172e-02, max 2.500e-02; 48.6% อยู่ที่ dt_max |
| init `residual_norm` / `physical_kcl_norm` | 3.14e-13 / 1.56e-13 |
| `accepted_sample_count` (audit) | 18852 |

## ข้อผิดพลาดในรายงานเดิมที่ต้องแก้

`docs/ne39_reclose_160s_success_report_20261011.md` ระบุว่า "rejects=0 ตลอด"
**ไม่ถูกต้อง** และ **ห้าม**แทนที่ด้วยเลข 50 แบบเหมารวม

### ความหมายจริงของ `rejects=` ใน `progress.log`

- `ts_simulate_ibr_hybrid.m:325` — `reject_count=0` reset ทุก accepted step
- `ts_simulate_ibr_hybrid.m:376-379` — มีสองตัวนับ: `reject_count` (รอบนี้) กับ `rejected_steps` (สะสม)
- `ts_simulate_ibr_hybrid.m:487-499` — พิมพ์เฉพาะ**สาขา accept** และ gate ด้วย
  `progress_every=5` s ⇒ rejection ที่เกิดกลางช่วง 5 วินาที **ไม่ถูกพิมพ์เลย**

หลักฐานเชิงประจักษ์: ทุกบรรทัดพิมพ์ `rejects=0` รวมบรรทัดที่ dt เล็กมากหลัง trip
และหลัง fault clear — ถ้าเป็นยอดสะสมจะรีเซ็ตกลับ 0 ไม่ได้

### ตัวเลขที่ใช้ได้ vs ใช้ไม่ได้

| scope | ค่า | ใช้ได้? |
|---|---|---|
| public accepted path (จาก `execution_summary`) | rejected = **50** (attempts 9473 − accepted 9423) | ✅ ตรงกับ `result.rejected_steps=50` |
| private transition trial | **ไม่มี field นับ rejection ใน artifact** | ❌ ยืนยันไม่ได้ทั้ง "rejects=0" และตัวเลขใดๆ |

artifact ของ trial มีแค่ `status`, `horizon_s`, `refinement_samples=4292`,
`refinement_error=5.52e-06` — **ต้องถอน claim ไม่ใช่แทนที่ด้วย 50**

> อย่าสับสนกับ study run ใหม่ (`ne39_fast160_study_*`) ที่ `rejected_steps=147`
> — คนละ run คนละ counter

### จุดที่ต้องแก้ในไฟล์ (รอผู้ใช้สั่ง ยังไม่แก้)

1. **บรรทัด 23** `private trial | ... rejects=0 ตลอด` →
   ระบุ `STUDY_TRIAL_COMPLETE`, `refinement_samples=4292`, `refinement_error=5.52e-06`
   และว่า **artifact ไม่มีตัวนับ rejection ของ trial**
2. **บรรทัด 43** วลี `(rejects=0)` ที่ใช้เป็นหลักฐานว่า trial ผ่าน → ตัดออก
   (หลักฐานที่ถูกคือ `STUDY_TRIAL_COMPLETE`)
3. **บรรทัด 22** `10,004+ samples` → ยอดจริง **18,852** (`audit.accepted_sample_count`)

ไฟล์อื่น (`docs/ne39_gfl_restoration_continuation_plan_20261012.md:32`,
`docs/ne39_independent_qa_plan_20261012.md:30`) เขียน caveat นี้ถูกแล้ว — แก้ไฟล์เดียว

## Checksums (ยืนยันว่าไม่ถูกแก้)

| ไฟล์ | SHA256 | bytes | mtime |
|---|---|---|---|
| `raw.mat` (อ่านอ้างอิง) | `d1dda3df5364e3f30f06f25d11e7b6d01a4e878edf1444a9d495140914494832` | 658,864,659 | 2026-10-11 10:56:27 |
| `baseline_compact.mat` (สร้างใหม่) | `d8895b2b41bb123465ccea81ee43ed430c69d87280426b3b751556bd295070ab` | 2,152,964 | — |

ยืนยัน: `raw.mat`, `request.mat`, `audit.mat`, `progress.log` **ไม่ถูกเขียนทับ**
อ่านผ่าน `H5F_ACC_RDONLY` / `load` / `matfile` (read-only) เท่านั้น
mtime ของทั้งสี่ไฟล์ยังเป็น 2026-10-11 ไม่มีไฟล์ `.m` ใน repo ถูกแก้

## Compact baseline สำหรับเทียบ candidate

`D:\4-year-project\GridFormLab-experiment\output\diagnostics\baseline_compact_20261013\baseline_compact.mat`
(2.15 MB, v7) — **21 variables**

| Variable | Size | หมายเหตุ |
|---|---|---|
| `t` | [18852×1] | time grid |
| `Vmag_sg_bus31`, `Vmag_ibr_bus30` | [18852×1] | |
| `coi_frequency_Hz` | [18852×1] | |
| `delta_rad`, `omega_pu` | [18852×1] | SG state (omega = per-unit) |
| `P_MW`, `Q_MVAr`, `device_frequency_Hz` | [18852×10] | คอลัมน์ 1=SG31, 2=IBR30, ... |
| `bus_ids` [1×39], `device_bus_ids` [10×1] | | mapping |
| `iter_per_step`, `dt_history` | [9423×1] | per accepted step |
| `sample_idx` [1×17], `sample_label` {1×17} | | event-anchored |
| `sg_state_rows` [17×8], `sg_state_cols` {1×8} | | |
| `scalars` | struct 1×1, **27 fields** | ดูด้านล่าง |
| `elapsed_s` | [1×1] | 6708.725530 |
| `N_samples` | [1×1] | 18852 |
| `source_folder` | char [1×95] | path ของ artifact ต้นทาง |

`scalars` (27 fields): `converged`, `actual_reclose_time`, `requested_sg_on_time`,
`t_sg_trip`, `actual_mode_reselection_time`, `handback_start_time`,
`handback_complete_time`, `handback_duration_s`, `production_certified`,
`hardware_certified`, `full_chronology`, `rejected_steps`, `domain_rejected_trials`,
`subdivision_depth`, `adaptive_strict_lte`, `floor_accepted_steps`,
`reference_owner_indices`, `gfm_reference_resource_indices`, `reference_island_ids`,
`step_count`, `newton_iters_total`, `newton_iters_max`, `dt_median`,
`dt_max_observed`, `dt_min_observed`, `sg_state_cols`, `sg_state_rows`

## สคริปต์ reproduce extraction

เดิมอยู่ใน TEMP (เสี่ยงถูกกวาด) → คัดลอกไปที่
`D:\4-year-project\GridFormLab-backups\baseline_extract_20261013\` แล้ว

| Script | หน้าที่ |
|---|---|
| `extract_final.m` | **ตัวหลัก** สร้าง `baseline_compact.mat` |
| `extract_pass2.m` | compact trajectory sample → `compact_sample.txt` (มี bug `save` ค้าง ใช้ `extract_final.m` แทน) |
| `inv_baseline.m` | `request.mat`/`audit.mat` inventory |
| `probe_meta.m` | `result` field listing (82 members) |
| `check_grid.m` | duplicate-timestamp + `rejected_steps` verification |
| `check_groups.m` | `/result/equilibrium\|execution_summary\|metadata` group scalars |
| `check_last.m` | ตรวจ field ที่หายไป |

รันด้วย `matlab -batch "<function_name>"`

**วิธีอ่าน `raw.mat` ที่ใช้ได้จริง (สำคัญ):**
- เปิด HDF5 handle **ครั้งเดียว** แล้ว `H5D.read` เฉพาะ flat dataset
- ❌ ห้ามใช้ `matfile` แบบ nested (`m.result.t` จะ error)
- ❌ ห้าม `h5info` recursive (ค้าง >10 นาที)

> ยังไม่ได้ย้ายเข้า `scripts/diagnostics/` ใน repo — รอผู้ใช้สั่ง
> เพราะเป็น script ที่แตะ artifact ขนาด 659 MB ควร review ก่อนเข้า repo

## การใช้เทียบ optimization

เทียบ candidate กับ baseline ด้วย `scripts/diagnostics/compare_ts_equivalence.m`:
- **DECISION fields ต้อง exact**: `reclose_status`, `actual_reclose_time`,
  `device_modes_history`, `failure_id`, fingerprints, `sg_indices`
- **continuous arrays** เทียบด้วย `opt.tol` ที่ตกลงกัน (baseline นี้ default 0 = bit-identical)
- **counters ไม่ใช้ gate** รายงานอย่างเดียว
- ห้าม reuse residual/Jacobian ข้ามเวลา/input/context/limiter regime ที่ต่างกัน
