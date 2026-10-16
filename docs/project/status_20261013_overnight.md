# Overnight status — 2026-10-13 (อัปเดตล่าสุด ~23:35)

## ✅ เสร็จแล้ว

### 1. Parallel Computing Toolbox 26.2 — ติดตั้งสำเร็จ
- ผ่าน MathWorks Product Installer **GUI** (silent ไม่ผ่าน เพราะบังคับ File Installation Key)
- `ver` ยืนยัน: `Parallel Computing Toolbox 26.2`
- `parpool('local',4)` → 4 workers (Processes profile) ทำงานปกติ
- อยู่ที่ `C:\Program Files\MATLAB\R2026b\toolbox\parallel`
  (**ชื่อใหม่ของ R2026b** — ไม่มี `distcomp` แล้ว ห้ามใช้ `Test-Path distcomp` เช็ก)
- บันทึกไว้: silent install ต้องใส่ `fileInstallationKey=` เอง แม้จะมี `enableLNU=yes`
  (Streamlined workflow ดึง FIK ให้อัตโนมัติเฉพาะ GUI mode) — template อยู่ที่
  `C:\Users\Birds\Downloads\_temp_matlab_R2026b_Windows\installer_input_pct.txt`

### 2. C++ toolchain + MEX
- `w64devkit-x64-2.10.0` (GCC 16.2.0 + OpenMP) ที่
  `D:\4-year-project\GridFormLab-backups\toolchain\w64devkit`
- SHA256 `18D0A4C71A166F8401AB6305781BEC5882B40B5E06BA9807C61CB5F3B3C6325E`
- `mex -setup C++` ลงทะเบียนแล้ว (mingw64-g++)

### 3. Baseline ยืนยันครบ
- `docs/project/baseline_ne39_reclose_160s.md` — elapsed **6708.725530 s**,
  event chronology, counters, checksums, 21 variables
- สคริปต์ extract 11 ตัว ย้ายจาก TEMP → `GridFormLab-backups\baseline_extract_20261013\`
- `raw.mat` SHA256 `d1dda3df…` ไม่ถูกแตะ (mtime ยัง 2026-10-11)

## กำลังวิ่ง (3 agents)

| Lane | โมเดล | งาน | ไฟล์เป้าหมาย |
|---|---|---|---|
| A — residual value threading | Sonnet | ลด residual ซ้ำ | `ts_step_composite.m`, `composite_newton.m` |
| E — MEX+OpenMP | Sonnet | C++ kernel + parity | `src/mex/`, design doc, tests |
| E — parfor FD groups | Sonnet | `ts_forward_fd_parallel.m` | helper ใหม่ + patch (ไม่แตะไฟล์หลัก) |

ทั้งสามตัวถูกสั่งให้ **ห้ามแตะไฟล์เดียวกัน** เพื่อไม่ให้ merge ทับกัน

## รอคุณตัดสินใจ (ไม่เร่ง)

1. **แก้รายงานผิด** 3 บรรทัดใน `docs/ne39_reclose_160s_success_report_20261011.md`
   (ดูรายละเอียดใน `docs/project/baseline_ne39_reclose_160s.md` หัวข้อ "จุดที่ต้องแก้")
2. **ย้ายสคริปต์ extract เข้า repo** `scripts/diagnostics/`
3. **รัน study ที่ค้าง t=110/160 ต่อ** ให้จบแล้ว audit —
   อยู่ที่ `output/diagnostics/ne39_5sg5ibr_fault_load_study_20261013_222640_139`
   (มีแค่ `progress.log` + `request.mat` ยังไม่มี `raw.mat`/`audit.mat`)

## ข้อจำกัดทางสถาปัตยกรรมที่กระทบ Lane E (MEX)

MATLAB C API ไม่ thread-safe → เรียก `dae.dae_f`/`dae.dae_g` กลับจากหลาย OpenMP thread
พร้อมกัน **ไม่ได้** ดังนั้น residual จะขนานได้จริงต่อเมื่อสมการ f/g ของ device
อยู่ใน C++ ล้วน — agent ต้องทำ port-surface inventory ก่อน

## Branch
- `backup/pre-ts-optimize-20261013` → main tree `D:\4-year-project\GridFormLab`
- `exp/ts-optimize-20261013` → worktree `D:\4-year-project\GridFormLab-experiment`
- **ห้าม** benchmark จนกว่าจะมี MATLAB ว่างจริงๆ — เวลาจะบิดเบือน
