# SSSA Engine Reconstruction Plan

## สถานะปัจจุบัน (2026-07-10)

### Engine ที่ใช้งานได้ (เก็บไว้)
- `+stability/synchronous_flux_ssa.m` — generic primitive-flux 6th-order engine
  - states: `[delta, omega, psi_fd, psi_1d, psi_1q, psi_2q]`
  - รับ `case_data` เป็น input โดยตรง (ไม่ hard-code Kundur)
  - PF-preserving equilibrium residual `1e-13`, angle invariance `1e-9`
- `+stability/multicase_sssa.m` — dispatcher ส่ง case ไป plugin ตาม schema
- `+stability/sauer_pai_flux_ssa.m` — thin wrapper เรียก generic engine
- `+pfsolver/powerflow_fsolve.m` — fsolve-based PF solver (เสริม NR)

### ผลที่พิสูจน์แล้ว
1. **Sauer-Pai Ex 8.3 (3-machine, 7-state)** — reproduce ที่ **0.11%** (ผ่าน 0.5%) ✓
2. **Kundur two-area (4-machine, 6-state)** — engine รันได้ แต่**ยังไม่ตรงตาราง E12.3**
   - interarea 0.545 Hz vs ตาราง 0.545 (ตรง freq)
   - แต่ damping คลาด 3–20% ทุก root
   - สาเหตุ: q-axis parameters ขัดแย้งกันเอง (discriminant < 0)
3. **Synthetic Sauer-Pai (2,5,6-machine)** — รันได้ (smoke test)

### ข้อกำหนด (non-negotiable)
- **ห้าม tune parameter/สมการเพื่อ force ให้ตรงค่าใดค่าหนึ่ง**
- แก้ได้แค่ derivation ที่ถูกต้องตามทฤษฎี
- ทุก case ต้องใช้ engine ตัวเดียวกัน (general)

---

## การตัดสินใจสำคัญ

### 1. ทิ้ง Table E12.3 เป็น reference
- ไม่ใช้ Table E12.3 เป็น benchmark pass/fail อีก
- เหตุผล: ค่า q-axis ของ Kundur (Xq=1.7, X'q=0.55, X''q=0.25, T'q0=0.4, T''q0=0.05)
  ขัดแย้งกันเอง — discriminant ของ coupled-rotor circuit < 0
  (พิสูจน์แล้วใน open-circuit pole consistency check)
- **ห้ามเคลมว่า Kundur ตรงตาราง** จนกว่าจะตรงจริงทุก root

### 2. เป้าหมายใหม่: 8 multimachine benchmark cases
- ต้องการ 8 cases ที่มี published eigenvalue reference
- engine ทำได้ทั้ง 8 ด้วย engine ตัวเดียว
- ห้ามใช้ SMIB (เบสิคไป)

---

## แผนการทำงาน

### Phase 1: ทำความสะอาด (ทันที)
**ลบ engines เดิมที่บั๊ก/ซ้ำซ้อน:**
- `+stability/kundur_ex126_book_flux_ssa.m` (mod) — GENTPJ E'/E'' diagnostic
- `+stability/kundur_ex126_kundur_ssa.m` — legacy GENTPJ diagnostic
- `+stability/kundur_ex126_genrou_ssa.m` — GENROU (residual 1.5e-2, ไม่ใช่ equilibrium)
- `+stability/kundur_ex126_book_e123_ssa.m` — calibrated wrapper (quarantined, ไม่ใช้)
- `+stability/kundur_ex126_sixth_order_ssa.m` — alias ไป kundur_ssa

**ลบ root scratch/calibration scripts:**
- `calibrate_*.m`, `compare_kundur*.m`, `debug_kundur.m`, `diag_kundur_ssa.m`
- `probe_*.m`, `sweep_*.m`, `check_eigenvalues_vs_kundur.m`
- `test_damping.m`, `test_dload_effect.m`, `test_common_mode_fix.m`
- `test_kundur_ssa_calibrated.m`, `test_load_models.m`, `test_mixed_load.m`, `test_zip_load.m`
- `generate_kundur6_crossvalidation_assets.m`, `compare_kundur6_sssa_3way.m`
- `kundur_6order_equations.m`, `run_twoarea_smallsignal.m`

**เก็บไว้ (diagnostic, ไม่ใช่ benchmark):**
- `+stability/kundur_e123_reference.m` — Table E12.3 values (เก็บเป็นข้อมูล ไม่ใช้เป็น pass/fail)
- `+stability/kundur_e123_family_compare.m` — diagnostic matcher
- `+stability/kundur_e123_primitive_compare.m` — diagnostic สำหรับ engine ใหม่

**ปรับ tests:**
- redirect tests ที่เรียก engines เดิม → ใช้ `multicase_sssa`/`synchronous_flux_ssa`
- ลบ tests ที่เกี่ยวกับ calibrated wrapper / Table E12.3 exact match
- เก็บ test ที่บังคับว่า Kundur **ต้องไม่ pass** จนกว่าจะตรงจริง

### Phase 2: แก้ engine bug (ถัดไป)
**ปัญหา:** interarea ออก 0.545 Hz ตรง Kundur book แต่ไม่ตรง PES-TR18 (0.611 Hz)
- ตรวจแล้ว: load model ไม่ใช่สาเหตุ
- สาเหตุ: PSS/E ใช้ GENROE realization ต่างจาก primitive flux ของเรา
- **งาน:** ศึกษา GENROE differential equations และ implement ให้ engine รองรับ
  - หรือยอมรับว่าเป็น model realization difference และรายงานตรงๆ

### Phase 3: สร้าง 8 benchmark cases
| # | Case | Machines | Ref source | งานที่ต้องทำ |
|---|---|---|---|---|
| 1 | Sauer-Pai Ex 8.3 | 3 | Sauer-Pai Table 8.2 | ✓ done (0.11%) |
| 2 | Kundur 2-area no-AVR | 4 | (รอ fix engine) | แก้ engine bug |
| 3 | Kundur + ESDC1A Ka=20 | 4 | PES-TR18 Sec 3.2 | implement ESDC1A |
| 4 | Kundur + ESST1A no-TGR | 4 | PES-TR18 Sec 3.5 | implement ESST1A |
| 5 | Kundur + ESST1A + PSS | 4 | PES-TR18 Sec 3.6 | implement IEEEST |
| 6 | 3MIB | 3 | benchmark paper | หา params+eig |
| 7 | New England 39-bus | 10 | published | หา params+eig |
| 8 | AU14G | 14 | state-space eig | implement GENROE/GENSAL |

### Phase 4: Implement exciter models (ถัดไป)
- `ESDC1A` (DC rotating exciter)
- `ESST1A` (static exciter)
- `IEEEST` (power system stabilizer)
- เพิ่มเป็น plugin ใน `multicase_sssa` ตาม case schema

---

## สิ่งที่จะทำใน commit นี้ (Phase 1)
1. เขียน plan นี้เป็น `PLAN_SSSA_ENGINE.md`
2. ลบ engines และ scratch files ที่ไม่ใช้
3. ปรับ tests ให้ใช้ engine ใหม่
4. รัน full suite ยืนยันผ่าน
5. commit and push
