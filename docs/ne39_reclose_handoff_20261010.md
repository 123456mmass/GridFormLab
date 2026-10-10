# NE39 SG Reclose — Continuation Handoff (2026-10-10)

สถานะล่าสุดสำหรับเครื่องใหม่ ประวัติฉบับเต็มอยู่ที่ `ne39_reclose_resume_evidence_20261010.md`
(หมายเหตุ: ไฟล์นั้นมีบางหัวข้อล้าสมัย ให้ใช้เอกสารนี้เป็นข้อมูลอ้างอิงหลัก)

## สถานะปัจจุบัน (branch checkpoint/ne39-160s-20261009, HEAD 8b31052)

### คอมมิตที่ push แล้วทั้งหมด
| คอมมิต | เนื้อหา | การตรวจสอบ |
|---|---|---|
| `a59c461` | seed PLL จากแรงดันที่แก้ได้ + แยก droop ออนไลน์ออกจากเกนจับ offline (4 ไฟล์) | plant/wiring 30/30 |
| `0eb83c9` | dynamic SSSA partition (`opt.state_partition='dynamic'`), gauge `theta_hat`, ช่องทาง `R_online_pu` ผ่าน builder (5 ไฟล์) | dynamic SSSA 3/3 |
| `8b31052` | เพิ่ม `scripts/diagnostics/ne39_reclose_applied_probe.m` (สคริปต์ probe) | — |

### ผลการตรวจที่ผ่าน
- `test_ne39_sg_reclose_plant.m` + `test_ne39_sg_reclose_wiring.m` + `test_ne39_reclose_dynamic_sssa.m`: **33/33 ผ่าน**
- Selector ทั้ง SG_OFF และ SG_ON: **CERTIFIED** พร้อมสเปกตรัม 9 GFM ทั้งคู่ (probe run 20261010_195425_006)
- SG bounds, กระแสจริง (S_max 573.3 MVA < rating 1106.6), แรงดันบน sample ที่รับ: ผ่าน

### การตัดสินทางกายภาพที่บันทึกไว้
- เกนจับ offline (Komega≈24) ถูกใช้เป็น feedback ตอนออนไลน์ → damping โหมด IBR ~1.3 Hz ลดเหลือ 0.01794 < 0.02
- แยก droop ออนไลน์ออกมาแล้วสแกน: 4%→0.01785, 5%→0.01841, 6%→0.01878, 10%→0.01953, **20%→0.02010 ผ่าน**, 50%→0.02044, 100%→0.02055
- ค่าเริ่มต้นถูกล็อกเป็น `R_online_pu=0.20`; เกณฑ์ zeta 0.02 ไม่ถูกลด

## งานที่ยังเหลือ (บนเครื่องใหม่)

1. **รัน probe ที่ dt=0.001** (ตั้งค่าไว้แล้วในไฟล์):
   ```powershell
   & 'C:\Program Files\MATLAB\R2025a\bin\matlab.exe' -nojvm -batch "addpath(pwd); pf_init_paths(); addpath(fullfile(pwd,'scripts/diagnostics')); folder=ne39_reclose_applied_probe(); fprintf('APPLIED_PROBE_RETURNED=%s\n',folder);"
   ```
   สาเหตุที่ต้องทำ: รอบก่อน (dt=0.0025) private transition trial ปฏิเสธที่ event `sg_trip` ด้วย
   `DT_REFINEMENT_NOT_RESOLVED` — ความต่างของ path ระหว่าง mesh dt กับ dt/2 บน ramp ของ Pm
   ช่วงหลังตัดเครื่องเกิน `refinement_tol=1e-5` ลองใหม่ที่ dt=0.001 แล้ว

2. **เป้าหมายผล probe:** `close_applied=1`, `guard dV/df/dtheta pass=1`,
   `SELECTOR SG_OFF=CERTIFIED SG_ON=CERTIFIED exact9Spectrum=1 ทั้งคู่`, `right_KCL < 1e-8`

3. **ถ้าผ่านครบ** รัน chronology เต็ม 160 s ที่ max step 0.001 (แก้ `t_end 161.0`,
   `full_chronology=true` ตามคำสั่งในบทสนทนา) แล้วตรวจแรงดันและผล reclose อีกรอบ

4. **ตรวจ KCL / continuity / กระแส / แรงดัน แยกหมวด** แล้วบันทึกรายงาน

5. **ปิดงาน:** commit เฉพาะไฟล์ที่ตรวจแล้ว (ห้าม `git add .`), push ปิดท้าย

## ห้ามทำ (เหมือนเดิมทุกข้อ)
- ห้ามลด zeta_min 0.02, sync dwell, timeout, min-off, หรือเกตความสามารถใด
- ห้าม reset rotor state หรืออนุญาต Pm ติดลบ
- ห้ามปรับเกณฑ์เองเพื่อให้ผ่าน — ถ้าไม่ผ่านให้เก็บ log แล้ววิเคราะห์ก่อน

## สาเหตุเชิงเทคนิคที่ควรรู้ก่อนแก้
- พารามิเตอร์ SG ถูกปิดผนึกใน `provenance.params` ตอนสร้างเครื่อง — การแก้ struct ทีหลังไม่มีผล
  ต้องผ่าน `scenario_opt.sg_reclose_params` (ต่อเข้า trademark `ne39_sg_reclose_plant_params`) แล้วให้ builder สร้างใหม่
- ค่า droop ยิ่งแน่น (R น้อย) damping ยิ่งต่ำ — ทิศทางนี้พิสูจน์แล้วด้วยการวัดจริง 6 ค่า
- `probe.m` ห้ามเปลี่ยนเส้นทางเตือนภัยหรือบังคับ candidate ใดๆ — ทุก gate ปิด fail-close

## พยานล่าสุด
- Run จบ: `output/diagnostics/ne39_reclose_applied_probe_20261010_195425_006` (raw+request ครบ)
- Run ไม่จบ (หยุดเอง): `output/diagnostics/ne39_reclose_applied_probe_20261010_200626_166`
