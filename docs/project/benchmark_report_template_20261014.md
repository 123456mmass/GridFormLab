# Benchmark report — TS engine optimization (template)

> กรอกตาม `benchmark_protocol_20261013.md` ทุก arm ต้องกรอกครบทุกหัวข้อ
> ห้ามตั้ง tolerance เอง — ช่อง tolerance เว้นว่างไว้จนกว่าจะตกลงกันก่อน
> อ้างอิง baseline: `baseline_ne39_reclose_160s.md` (elapsed 6708.725530 s)

---

## 0. Identification

| field | ค่า |
|---|---|
| arm name / optimization lane | |
| วันที่–เวลาที่รัน (raw timestamp) | |
| MATLAB version | R2026b 26.2.0.3386108 |
| โหมดทดสอบ | ชุด 1 replay / ชุด 2 autonomous (ระบุ) |

---

## 1. Wall clock

| field | ค่า |
|---|---|
| wall clock (s) — ตัวเลขเดียว | |
| wall clock (raw timestamp) | |
| ผล baseline-arm rerun (noise check) | |
| หมายเหตุ machine busy ระหว่างรัน | |

พร้อมกันนี้ต้องรายงาน call counts ใน §3 — wall clock อย่างเดียวเชื่อไม่ได้ถ้า machine busy

---

## 2. Hardware & environment

| field | ค่า |
|---|---|
| `maxNumCompThreads` | |
| `gcp('nocreate')` | |
| cores / threads ที่ใช้ | 10 cores / 16 threads (i5-14400F) |
| RAM | 31.8 GB |
| commit SHA | |
| dirty-state (git status ตอนรัน) | |
| background apps ที่ปิดแล้ว | |

---

## 3. Counters (รายงานเท่านั้น ไม่ใช้ gate)

| counter | baseline (อ้างอิง) | arm นี้ |
|---|---|---|
| `ts_accepted_steps` | 9423 | |
| `ts_step_attempts` | 9473 | |
| cumulative rejected = attempts−accepted | 50 (public path เท่านั้น) | |
| `ts_newton_iterations` total | 64052 | |
| newton mean / max | 6.80 / 73 | |
| `jacobian_evaluations` | | |
| residual evaluations (รวม) | | |
| `residual_evaluations_avoided` | | |
| FD group count | | |
| parallel FD mode | | |
| n_workers | | |

**ห้าม**ใช้คอลัมน์ `rejects=` ใน progress.log เป็น rejected — ใช้ attempts−accepted เท่านั้น
**ห้าม**เปลี่ยน `jacobian_evaluations` counter convention (ไม่นับ wrap-up J_final ตาม convention เดิม)

---

## 4. DECISION fields — ต้อง exact เสมอ

ตารางเปรียบเทียบ baseline vs candidate ทุก field — ใส่ ✓ exact / ✗ ต่าง (พร้อมค่าจริงทั้งสอง)

| DECISION field | baseline | candidate | exact? |
|---|---|---|---|
| `converged` | | | |
| `actual_reclose_time` | | | |
| `reclose_status` | | | |
| `device_modes_history` | | | |
| `failure_id` | | | |
| `committed_config_fingerprint` | | | |
| `pre_event_input_fingerprint` | | | |
| `selector_table_fingerprint` | | | |
| `sg_indices` | | | |
| `actual_mode_reselection_time` | | | |
| `reselection_status` | | | |
| `requested_sg_on_time` | | | |
| `handback_status` | | | |
| `handback_start_time` | | | |
| `handback_duration_s` | | | |
| `handback_complete_time` | | | |

field ใดต่าง → arm นั้น **fail ทันที** ห้ามปรับ tolerance มาชดเชย

---

## 5. Continuous arrays — tolerance

**ช่องนี้เว้นว่าง — ค่า tolerance ต้องตกลงกันก่อนรันเทียบ ห้ามตั้งเอง**

เริ่มวัดจาก `tol=0` เสมอ ถ้าผ่าน bit-identical ไม่ต้อง relax

| array | tol (ตกลงตอนไหน โดยใคร) | max |mean| diff | ผ่าน/ไม่ผ่าน @tol ที่ตกลง |
|---|---|---|---|---|
| V trajectories | | | |
| f / frequency trajectories | | | |
| angle / delta trajectories | | | |
| P / Q trajectories | | | |
| peaks / settling | | | |
| right-KCL | | | |

ถ้าไม่ผ่าน @tol=0 → **รายงาน ห้ามเพิ่ม tolerance เอง** แล้วค่อยคุยกัน

---

## 6. Speedup — แยกหมวด ห้ามรวมเป็นตัวเลขเดียว

| หมวด | กลไก | wall clock | call counts | หมายเหตุ |
|---|---|---|---|---|
| **A** — ลดงานซ้ำ | residual reuse (`residual_evaluations_avoided`) | | | |
| **E-parallel** | parfor FD groups / MEX+OpenMP | | | |
| **D** — เปลี่ยน numerical method | integrator/stepper | | | |
| **F** — ลด certification gates | เฉพาะงาน research ต้องติดป้าย | | | |

ข้อห้าม:
- ห้ามรวมสี่หมวดเป็นตัวเลข speedup เดียว
- **timing จาก cached replay ไม่นับเป็น solver speedup** — ต้องสาบาน/ยืนยันว่า:
- ห้ามอ้าง speedup = n_cores เพราะ residual ใน MATLAB ยัง interpreted

> **declaration:** timing ที่รายงานในหมวด A/D/E ทั้งหมดมาจาก cold numerical execution
> ไม่ใช่ cached replay (ช่องนี้กรอกว่า ยืนยัน / ไม่สามารถยืนยัน — ถ้าไม่ ห้ามนับเป็น speedup)

---

## 7. Checks ที่ตัดออก (ถ้ามี)

รายการเชิงชัดเจน — อันไหนถูก bypass/disable/check ที่ข้าม ต้องระบุชื่อ + เหตุผล
ถ้าไม่มี ระบุ "ไม่มี checks ที่ถูกตัดออก"

| check ที่ตัดออก | เหตุผล | ผลกระทบ (ถ้านำกลับมา คงผ่าน / fail) |
|---|---|---|
| | | |

---

## 8. เกณฑ์ pass ที่ใช้จริง (อ้าง protocol ย่อ)

- DECISION fields §4 exact ➜ บังคับ
- continuous §5 ใช้ tol ที่ตกลงร่วมกัน (ไม่ตั้งเอง)
- counters §3 ไม่ใช้ gate
- ต้องผ่าน `tests/test_composite_newton_contract.m` (17/17) และ `tests/test_ts_fd_column_groups.m` (step.rcond bit-identical)
- pre-existing failures (`test_ieee14_ibr_ts_event_runner` 3 ตัว) ไม่นับเป็น regression
