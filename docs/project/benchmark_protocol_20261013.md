# Benchmark protocol — TS engine optimization (2026-10-13)

ใช้สำหรับวัด optimization ทุกตัวในรอบนี้ อย่าตั้งตัวเลขเอง ต้องอ้างอิง baseline

---

## Baseline ที่ยึด

`docs/project/baseline_ne39_reclose_160s.md` — NE39 SG31 reclose 160 s

| | ค่า |
|---|---|
| elapsed | **6708.725530 s** |
| accepted steps | 9423 |
| cumulative rejected | 50 (public path เท่านั้น; private trial ไม่มีตัวนับ) |
| newton iterations | 64052 |
| reclose | t = 119.521920776 SUCCESS |
| horizon | 160.000000 |
| production_certified | **false** |

Options ที่รันจริง ยึด `request.mat` ไม่ใช่ script บนดิสก์ปัจจุบัน

---

## เงื่อนไขที่ต้องรักษาก่อนวัด

1. **MATLAB ต้องว่างจริงๆ** — ห้ามมี process อื่นแย่ง CPU/RAM
   (ตอนนี้มี agent รัน MATLAB อยู่ จึงยังวัดไม่ได้)
2. Hardware: Intel i5-14400F (10 cores/16 threads), RAM 31.8 GB, MATLAB R2026b 26.2.0.3386108
3. บันทึก `maxNumCompThreads`, `gcp('nocreate')`, commit SHA, dirty-state ทุกครั้ง
4. ปิด background apps เท่าที่ทำได้
5. รัน baseline arm ซ้ำอย่างน้อย 1 ครั้งเพื่อเช็ก noise ก่อนเทียบ

---

## สองชุดทดสอบ (ตามที่ผู้ใช้เลือก)

### ชุด 1 — Replay event chronology
ยึด event จาก baseline แล้ว replay เพื่อแยก numerical core ออกจากการตัดสินใจ
- ใช้ `sample_idx` / `sample_label` จาก `baseline_compact.mat` (17 event-anchored points)
- เทียบ trajectory บน time grid ร่วมที่รักษา event pre/post samples

### ชุด 2 — Autonomous event decision
ปล่อยให้ engine ตัดสินใจ trip/reclose เอง แล้วเทียบ:
- event order, actual trip/reclose times
- `reclose_status`, `failure_id`
- mode selection outcomes

---

## สิ่งที่ต้องวัดทุก arm

| รายการ | บันทึกเป็น |
|---|---|
| wall clock (s) | ตัวเลขเดียว + raw timestamp |
| `ts_accepted_steps` / `ts_step_attempts` | counters |
| cumulative rejected | **จาก attempts−accepted เท่านั้น** ห้ามใช้คอลัมน์ `rejects=` ใน progress.log |
| `ts_newton_iterations` (total/mean/max) | counters |
| `jacobian_evaluations` | ตาม convention เดิม (ไม่นับ wrap-up J_final) |
| residual evaluations | รวม + จำนวนที่หลบได้ (`residual_evaluations_avoided`) |
| FD group count / parallel mode / n_workers | สำหรับ Lane E |
| hardware + settings | dict |
| checks ที่ตัดออก (ถ้ามี) | รายการชัดเจน |

---

## เกณฑ์ตัดสิน (ต้องตกลงก่อนรัน ไม่ตั้งเอง)

### Decision fields — ต้อง exact เสมอ
`converged`, `device_modes_history`, `actual_reclose_time`, `reclose_status`,
`actual_mode_reselection_time`, `reselection_status`, `requested_sg_on_time`,
`handback_status`, `handback_start_time`, `handback_duration_s`,
`handback_complete_time`, `failure_id`, `committed_config_fingerprint`,
`pre_event_input_fingerprint`, `selector_table_fingerprint`, `sg_indices`

### Continuous arrays — ใช้ `opt.tol` ที่ตกลงกัน
- รอบนี้ยอมให้ไม่ bit-identical ได้ ("ขอแค่ค่าไม่หนีกันมาก") แต่ **ยังไม่ตั้งตัวเลข**
- เริ่มวัดจาก `tol=0` ก่อนเสมอ ถ้าผ่าน bit-identical → ไม่ต้อง relax
- ถ้าไม่ผ่าน → **รายงาน ห้ามเพิ่ม tolerance เอง** แล้วค่อยคุยกัน
- เทียบ: voltage/frequency/angle/P/Q trajectories, peaks, settling, KCL

### Counters — ไม่ใช้เป็น gate
รายงานอย่างเดียว (`residual_per_step`, `iter_per_step`, etc.)

---

## การรายงาน speedup

- แยกให้ชัด ไม่รวมเป็นตัวเลขเดียว:
  - **A** ลดงานซ้ำ (residual reuse)
  - **E-parallel** ขนาน (parfor / MEX+OpenMP)
  - **D** เปลี่ยน numerical method (integrator)
  - **F** ลด certification gates (research, ต้องติดป้าย)
- ค่า timing จาก cached replay **ไม่นับ**เป็น solver speedup
- ต้องมีทั้ง **wall clock** และ **call counts** เพราะ wall clock อย่างเดียวเชื่อไม่ได้ถ้า machine busy
- อย่าอ้าง speedup = n_cores เพราะ residual ใน MATLAB ยัง interpreted

---

## เครื่องมือ

- `scripts/diagnostics/compare_ts_equivalence.m` — falsification instrument หลัก
- `scripts/diagnostics/profile_switch_ts_kernel.m` — arms: `composite` (t_end=2.0s, ~3.12s),
  `compressed` (t_end=8.0s, ~827s — **กินเวลาหลายนาที**), `compressed_fast` (t_end=3.5s)
- `scripts/diagnostics/bench_parfor_fd_groups.m` — micro-bench ของ Lane E parfor
- `output/diagnostics/baseline_compact_20261013/baseline_compact.mat` — compact baseline 21 vars

**ข้อควรระวัง:** อย่าถือว่า `compressed` = cheap เริ่มจาก micro/short-window ก่อนเสมอ

---

## ข้อห้ามที่ใช้กับทุก arm

- ห้าม reuse residual/Jacobian ข้ามเวลา/input/context/limiter regime ที่ต่างกัน
- ห้ามเปลี่ยน `jacobian_evaluations` counter convention
- ทุก numerical path ต้องมี legacy fail-closed fallback
- ต้องผ่าน `tests/test_composite_newton_contract.m` (17/17) และ
  `tests/test_ts_fd_column_groups.m` (`step.rcond` bit-identical)
- Pre-existing failures (`test_ieee14_ibr_ts_event_runner` 3 ตัว) ไม่นับเป็น regression
