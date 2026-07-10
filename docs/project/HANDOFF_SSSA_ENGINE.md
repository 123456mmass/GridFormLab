# Handoff — SSSA Engine Reconstruction (2026-07-10)

## สถานะปัจจุบัน

**ทุก test ผ่าน: 81/81** ✓

## งานที่ทำไปแล้ว (commit นี้)

### Engine ใหม่ที่สร้างขึ้น
- `+stability/synchronous_flux_ssa.m` — generic primitive-flux 6th-order SSSA engine
  - states: `[delta, omega, psi_fd, psi_1d, psi_1q, psi_2q]`
  - รับ `case_data` เป็น input โดยตรง (ไม่ hard-code Kundur)
  - PF-preserving equilibrium residual `1e-13`, angle invariance `1e-9`
  - ใช้ fsolve สำหรับ local stator/machine equilibrium solve
- `+stability/multicase_sssa.m` — dispatcher ส่ง case ไป plugin ตาม schema
- `+stability/sauer_pai_flux_ssa.m` — thin wrapper เรียก generic engine
- `+pfsolver/powerflow_fsolve.m` — fsolve-based PF solver (เสริม NR)
- `+stability/kundur_e123_primitive_compare.m` — diagnostic เทียบ engine ใหม่กับ Table E12.3

### Modifications
- `pf_init_paths.m` — แก้ path bootstrap ให้ตรวจ path จริงทุกครั้ง (test framework คืน path หลังจบ test)
- `+stability/sauer_pai_ex83_ssa.m` — เพิ่ม metadata.plugin field
- `+stability/kundur_ex126_book_flux_ssa.m` — ลบ debug knobs (debug_flux_q_saturation_sign)

### Tests ใหม่
- `tests/test_sauer_pai_flux_engine.m` — contract tests สำหรับ generic engine
- `tests/test_multicase_sssa.m` — dispatcher tests + Kundur "must not pass" guard
- `tests/test_fsolve_powerflow.m` — fsolve PF + path bootstrap tests

## ผลที่พิสูจน์แล้ว

### 1. Engine ใหม่ถูกต้อง (cross-case validated)
- **Sauer-Pai Ex 8.3 (3-machine, 7-state)**: reproduce ที่ **0.11%** (ผ่าน 0.5%) ✓
- **Synthetic Sauer-Pai (2,5,6-machine)**: รันได้ (smoke test) ✓

### 2. Kundur two-area ยังไม่ตรง (ห้ามเคลม)
- interarea: 0.545 Hz (ตรง Kundur book E12.3 ที่ 0.545)
- แต่ PES-TR18 (PSS/E) บอก 0.611 Hz → engine ใช้คนละ model realization
- damping คลาด 3–20% ทุก root
- **สาเหตุ root cause**: q-axis parameters ขัดแย้งกันเอง
  - `Xq=1.7, X'q=0.55, X''q=0.25, T'q0=0.4, T''q0=0.05`
  - discriminant ของ coupled-rotor circuit = **−1.15e-3 < 0** (ไม่มี real solution)
  - พิสูจน์แล้วใน open-circuit pole consistency check
  - ตรวจ Canay leakage แล้ว: ไม่ช่วย (disc ยังติดลบทุกค่า Xrc)

### 3. ทดสอบ load model ทั้ง 3 แบบ
- cc_p_cz_q, cp_p_cp_q, cz_p_cz_q: ทั้งหมดให้ interarea ~0.51-0.55 Hz
- → load model ไม่ใช่สาเหตุของความต่างจาก PES-TR18

## การตัดสินใจสำคัญ

### ทิ้ง Table E12.3 เป็น reference
- ไม่ใช้เป็น benchmark pass/fail อีก
- เหตุผล: ค่า q-axis ขัดแย้งกันเอง (discriminant < 0)
- **ห้ามเคลม Kundur ว่าตรงตาราง** จนกว่าจะตรงจริงทุก root

### ใช้ Kundur book (ไม่ใช่ PES-TR18/PSS/E)
- engine เราให้ค่าใกล้ Kundur book (0.545 Hz) ไม่ใช่ PSS/E (0.611 Hz)
- ที่ต่างเพราะ PSS/E ใช้ GENROE realization ต่างจาก primitive flux ของเรา

## Engines เดิมที่ยังไม่ได้ลบ (Phase 1 ของแผน)
- `+stability/kundur_ex126_book_flux_ssa.m` — GENTPJ E'/E'' diagnostic
- `+stability/kundur_ex126_kundur_ssa.m` — legacy GENTPJ diagnostic
- `+stability/kundur_ex126_genrou_ssa.m` — GENROU (residual 1.5e-2, ไม่ใช่ equilibrium)
- `+stability/kundur_ex126_book_e123_ssa.m` — calibrated wrapper (quarantined)
- `+stability/kundur_ex126_sixth_order_ssa.m` — alias ไป kundur_ssa

## งานที่เหลือ (ตาม PLAN_SSSA_ENGINE.md)

### Phase 1: ทำความสะอาด (ถัดไป)
- ลบ engines เดิม 5 ไฟล์ข้างบน
- ลบ root scratch files (calibrate_*, probe_*, sweep_*, debug_*, compare_*, ฯลฯ)
- redirect tests ที่เรียก engines เดิม → ใช้ `multicase_sssa`/`synchronous_flux_ssa`
- ลบ tests ที่เกี่ยวกับ calibrated wrapper / Table E12.3 exact match

### Phase 2: แก้ engine bug
- ปัญหา: interarea 0.545 Hz (ตรง book) แต่ PES-TR18 บอก 0.611 Hz
- ต้องศึกษา GENROE differential equations ของ PSS/E
- หรือยอมรับว่าเป็น model realization difference

### Phase 3: สร้าง 8 benchmark cases
1. Sauer-Pai Ex 8.3 (3-mach) ✓ done
2. Kundur 2-area no-AVR (4-mach) — รอ fix engine
3. Kundur + ESDC1A Ka=20 (4-mach) — implement ESDC1A
4. Kundur + ESST1A no-TGR (4-mach) — implement ESST1A
5. Kundur + ESST1A + PSS (4-mach) — implement IEEEST
6. 3MIB (3-mach) — หา params+eig
7. New England 39-bus (10-mach) — หา params+eig
8. AU14G (14-mach) — implement GENROE/GENSAL

### Phase 4: Implement exciter models
- ESDC1A, ESST1A, IEEEST เป็น plugin ใน `multicase_sssa`

## ข้อกำหนด (non-negotiable)
- ห้าม tune parameter/สมการเพื่อ force ให้ตรงค่าใดค่าหนึ่ง
- แก้ได้แค่ derivation ที่ถูกต้องตามทฤษฎี
- ทุก case ต้องใช้ engine ตัวเดียวกัน (general)
- ห้ามใช้ SMIB (เบสิคไป) — ต้องการ multimachine (2+ machines)

## คำสั่งที่ใช้ตรวจสอบ
```matlab
% รันทุก test
runtests('tests')

% ตรวจ engine ใหม่กับ Sauer-Pai
r = stability.multicase_sssa(cases.sauer_pai_ex83_case());

% ตรวจ Kundur diagnostic (ต้อง "ไม่ผ่าน")
q = stability.kundur_e123_primitive_compare()
```

## แหล่งข้อมูลสำคัญ
- PES-TR18 PDF: `/tmp/pes_tr18.pdf` (downloaded, Table 7 = params, Table 11 = eigenvalues)
- PES-TR18 text: `/tmp/pes_tr18.txt`
- Benchmark models paper: `/tmp/benchmark_models.pdf` + `.txt` (6 benchmarks: 3MIB, Brazilian, Kundur, New England, AU14G, 68-bus)
- colib.net Kundur: https://colib.net/testCases/kundur_two_area_system/
- Texas A&M 3MIB: https://electricgrids.engr.tamu.edu/electric-grid-test-cases/three-machines-infinite-bus-benchmark-system/
