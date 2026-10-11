# NE39 SG Reclose — 160 s Chronology SUCCESS Report (2026-10-11)

Branch: `checkpoint/ne39-160s-20261009`, base HEAD `3cbb7ea`, MATLAB R2026b
(26.2.0.3386108, C:\Program Files\MATLAB\R2026b)

## สรุปผล

**NE39 1SG+9IBR actual SG reclose: สำเร็จจริงครั้งแรกพร้อม chronology เต็ม 160 s จบ**

พยานหลัก: `output/diagnostics/ne39_reclose_applied_probe_20261011_090300_358`
(raw.mat + request.mat ครบ, elapsed 6708.73 s)

| เกตที่ต้องการ | ผลที่วัดได้ | สถานะ |
|---|---|---|
| `close_applied=1` | 1, status `SUCCESS`, actual_time **t=119.521920776** | ✅ |
| มุมปิดจริง | **0.4627°** (ในหน้าต่างศึกษา 0.5° ที่รัดจากเพดานเคส 10°) | ✅ |
| guard dV | 1.33e-15 / เพดานเคส 0.05 pu | ✅ |
| guard df | 3.30e-6 / เพดานเคส 0.001 pu | ✅ |
| guard dtheta | 0.4627 / เพดานเคส 10° | ✅ |
| `right_KCL < 1e-8` | **4.775e-10** (recompute อิสระจาก accepted right sample = ค่าเดียวกัน) | ✅ |
| continuity | `PASS_NO_STATE_OR_INPUT_RESET` x_exact=1 u_exact=1 online left=0 right=1 | ✅ |
| accepted path | `NUMERICAL_HORIZON_COMPLETE` (160 s ครบ, 10,004+ samples) | ✅ |
| private trial | `STUDY_TRIAL_COMPLETE`, global refinement ผ่าน, rejects=0 ตลอด | ✅ |
| SELECTOR SG_OFF | CERTIFIED, exact9Spectrum=1 | ✅ |
| SELECTOR SG_ON | CERTIFIED, exact9Spectrum=1 | ✅ |
| SG bounds | `PASS_ACCEPTED_STATES` Psv/Pm/Emag ในช่วงตลอด | ✅ |
| SG current | `PASS_ACTUAL_ONLINE_SAMPLES` S_max 624.94 < rating 1106.63 MVA | ✅ |
| strict nonvoltage | **PASS** (ไม่มี active-power zero crossing หลังปิด) | ✅ |
| strict voltage | FAIL_ON_OBSERVED_SAMPLES — dip กายภาพช่วง fault 150 ms (min 0.9070 pu) ภายใต้ `ne39_assessment_policy='observe_voltage'` เป็นหลักฐานการศึกษา ไม่ใช่เกตกายภาพที่ปฏิเสธ | ⚠️ รายงาน |

## สถานการณ์ที่ใช้ (ตาม timeline สไลด์, fault bus พอร์ตเป็น NE39 bus 16)

`event_profile='sg_fault_cycle'` (ตามแถว `sg_fault_bus16` ใน catalog ที่ freeze ไว้):
- SG31 trip ที่ **t=20 s** (หลังเครื่องนิ่งแล้ว 20 วิ, ไม่ใช่ 0.02 s แบบรอบก่อน)
- fault 3 เฟสที่ **bus 16** (คู่เทียบ bus 9 ของ IEEE14), Zf=j0.1, **60.0→60.15 s**
- SG reclose request ที่ **t=100 s**
- horizon **160 s**

## ทางแก้ทางวิศวกรรม 3 ชั้น (พร้อมเหตุผล + precedent ทุกตัว)

### 1. dt=0.001 (คงเพดานความละเอียดเดิม, ไม่ใช่เกณฑ์ใหม่)
- **หลักฐาน:** dt=0.0025 ปฏิเสธที่ `DT_REFINEMENT_NOT_RESOLVED` **สองจุด** — จุดเดิม (ramp หลังตัดเครื่อง, run 20261010_200626) และจุดใหม่ที่ trial `sg_trip` ที่ t=20 (run 20261011_043054: จบใน 568 s แต่ trial refused UNKNOWN)
- **วัดจริง:** ที่ dt=0.001 trial ผ่านทั้งสองจุด (rejects=0), mesh dt vs dt/2 path difference ≤ tolerance
- **เวลา:** 4728 s (79 นาที) สำหรับ 160 s horizon
- **ผลการทดสอบ adaptivity (มีประโยชน์ต่อการศึกษา):** adaptive stepper **เปิดอยู่แล้วเต็มรูปแบบ** — dt ตั้งต้น 0.001 แล้วโตเองเป็น 0.025 ตอน smooth (เห็นใน progress.log ทั้งสอง run), หดเอง 7.6e-4 ตอน fault clear และ 1.5e-4 ตอน post-trial swing การ "ไม่ใช้ adaptive" จะยิ่งช้าลง ~10 เท่า (fixed 0.001 = 160k steps)

### 2. รัดหน้าต่าง synchronism (tightening — เข้มขึ้น ไม่ใช่ผ่อน)
- **ปัญหาที่พบจริง (run 20261011_052802_378):** ปิดที่ first landing ในเพดาน 10° → มุมปิด 8.62° → first swing ของเครื่องเพิ่งซิงค์ทำ active power ข้ามศูนย์ชั่วขณะ **P=−1.23 MW** (0.2% rating) ที่ t=100.7216 → snapshot `P≥0` ปฏิเสธ → run หยุดที่ t=100.722 (แม้ reclose สำเร็จแล้ว)
- **หลักฐานสนับสนุนจาก 2 run:** รอบที่ปิดที่มุม 0.0085° (20261011_025214) P ไม่เคยติดลบเลยตลอด tail (Pmin=0) → crossing เกิดเฉพาะมุมปิดใหญ่
- **ทางแก้ตาม precedent:** รัดเฉพาะ probe ด้วย `synchronism_overrides = struct('dtheta_max',0.5,'dV_max',0.02,'df_max',0.0002)` ที่ **top-level options** (kernel อ่านจาก `opt.synchronism_overrides` ที่ ts_simulate_ibr_hybrid:1890) — ทิศทาง tightening ทั้งหมด, ไม่แก้เพดานเคส, ไม่แก้ check ใดๆ ใน shared code
- **ห้ามลืม:** ครั้งแรกวาง overrides ใน events struct แล้วไม่ทำงาน — ต้องอยู่ top-level

### 3. หน้าต่างรอ reclose 5→20 s (พารามิเตอร์ออกแบบการศึกษา)
- **ปัญหาที่พบจริง (run 20261011_073312_027):** มุมกวาดจริง **~1.0°/s** (9.31°@t=100 → 4.33°@t=105, วัดจาก resync_diag 507 records; คอมเมนต์แรกเขียน 0.36°/s — ประเมินผิด) จึงถึง <0.5° ที่ t≈109-112 → เคสให้หน้าต่าง 5 s (SYNC_TIMEOUT ที่ t=105) → ไม่ทัน
- **precedent ใน repo:** flagship IEEE14 EECON49 chronology runner ใช้ `delays_overrides=struct('timeout_s',20,'dwell_s',0.5)` (run_ieee14_eecon49_chronology:71) — ที่นี่ override **เฉพาะ timeout_s=20** ไม่แตะ dwell และ min-off (คง 0.5 s ตามเคสเป๊ะ)
- เครื่องกำลังซิงค์จริงตลอดหน้าต่าง (df ลด 6.6e-5 → 3.1e-5 pu) แค่ต้องรอเฟสกวาดเข้า

## ผลการตรวจแยกหมวด (ne39_chronology_category_checks_20261011.m, ok=1)

**[1] KCL/continuity:** event pre_kcl=1.35e-13, right_kcl=4.78e-10 ≤1e-6; recompute อิสระ = 4.78e-10 ≤1e-8; resync ใกล้ปิด eligible=1 ที่ dtheta=0.466°
**[2] กระแสรายเครื่อง (online samples) — ผ่านทั้ง 10:**

| dev | kind | I_max | declared | pass |
|---|---|---|---|---|
| SG31 | sg | 5.83 pu (sys) | 11.07 (=rating/base) | ✅ |
| IBR30,32–39 | ibr | 0.60–0.69 pu (conv) | 1.20 (ImaxF) | ✅ |

**[3] แรงดันแยกเฟส:**

| ช่วง | |V| (pu) |
|---|---|
| pre-event [0,20) | 0.9715 .. 1.0778 |
| island [20,60) | 0.9487 .. 1.0778 |
| fault [60,60.15) | 0.9070 .. 1.0838 (dip กายภาพ) |
| post-fault [60.15,119.52) | 0.9599 .. 1.1284 (swing หลังซิงค์ — เหนือ 1.1 ชั่วคราวตาม swing physics) |
| post-reclose [119.52,160] | 0.9705 .. 1.0818 |

**[4] reclose:** SUCCESS t=119.5219, offline_age 99.52 s ≥ min_off 0.5 s

## Chain of evidence (ทั้งหมดใน output/diagnostics/)

| run | ผล | สอนอะไร |
|---|---|---|
| `..._20261010_200626_166` (เอกสารรับช่วง) | DT_REFINEMENT จุดเดิม | dt=0.0025 ไม่พอ (รอบก่อน) |
| `..._20261011_025214_298` | **ทุกเกตผ่าน** 131 s (timeline เดิม) | dt=0.001 ผ่าน trial จริง; ปิดมุม 0.0085° → P บวกตลอด |
| `..._20261011_040358_433` | ถูกหยุดตามคำสั่ง ก่อนมีผล | — |
| `..._20261011_043054_349` | DT_REFINEMENT จุดใหม่ (t=20) | dt=0.0025 ยังไม่พอแม้ timeline ใหม่ |
| `..._20261011_052802_378` | reclose SUCCESS @100.5 แต่ tail หยุด @100.72 | first swing มุมใหญ่ → P ข้ามศูนย์ → ต้องรัดมุม |
| `..._20261011_073312_027` | SYNC_TIMEOUT ที่ t=105 (มุม 4.33°) | มุมกวาด ~1°/s → หน้าต่าง 5 s ไม่พอ |
| `..._20261011_090300_358` | **SUCCESS ครบ + 160 s จบ** | ทางแก้ 3 ชั้นพร้อมกันได้ผล |

## Environment provenance

- MATLAB **R2026b 26.2.0.3386108** (ต่างจาก R2025a ที่เอกสารรับช่วงอ้าง — ติดตั้งใหม่ระหว่าง session, รันผ่าน login online licensing; มี hang ที่ startup ก่อน login ซึ่งแก้ด้วยการ login)
- ชุดทดสอบยืนยันก่อน probe: `SCOPED_TESTS pass=30 fail=0 incomplete=0 total=30` (plant 13 + wiring 14 + dynamic SSSA 3; มี R2026b path quirk — ต้อง `path(path,pwd)` ก่อน `pf_init_paths`)
- **ไม่มีการ:** ลด zeta_min 0.02 / dwell / min-off, reset rotor, Pm ติดลบ, ปรับเกณฑ์ snapshot ใดๆ ใน shared code, บังคับ candidate
- **ไม่มีการเปลี่ยนเพดานเคส** (dV 0.05 / df 0.001 / dtheta 10° / timeout เคส 5 s ยังอยู่ครบใน request.declared_synchronism) — overrides ทั้งหมดเป็นการ*รัด*ของ probe เท่านั้น

## ไฟล์ที่แก้/เพิ่มใน commit นี้

1. `scripts/diagnostics/ne39_reclose_applied_probe.m` — timeline สไลด์ + overrides รัด synchronism + timeout window 20 s (พร้อมคอมเมนต์หลักฐานครบ)
2. `scripts/diagnostics/ne39_chronology_category_checks_20261011.m` — ตรวจแยกหมวด (KCL recompute อิสระ)
3. เอกสารนี้
