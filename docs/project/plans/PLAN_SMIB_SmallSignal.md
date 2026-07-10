# แผนงาน: Small-Signal Stability Analysis (SMIB)

> ต่อยอดจากโครงสร้าง MATLAB เดิม (`n_bus_clone`) ตามตำรา **Kundur — Power System Stability and Control, Chapter 12**
> Scope: classical → field circuit → excitation/AVR → PSS (เต็มรูปแบบ §12.3–12.5)

---

## 0. การตัดสินใจที่ผู้ใช้ยืนยันแล้ว

| ประเด็น | คำตอบ |
|---------|-------|
| ขอบเขตโมเดล | **ครบถึง excitation + PSS** (§12.3–12.5) |
| ระบบอ้างอิง | **Kundur examples เท่านั้นก่อน** — IEEE 5-bus พักไว้ (deferred) |
| ภาษา report | **อังกฤษ** |
| รูปแบบ | **Standalone script** (ไม่รวม GUI) |

> **อัปเดต 2026-05-31:** ผู้ใช้สั่งเอา Kundur อย่างเดียวก่อน IEEE 5-bus เลื่อนไปทำหลัง (Phase 4-IEEE deferred)

---

## 1. ขอบเขตและที่มา

งานเดิม = steady-state power flow (NR/GS/CPF/OPF) — งานใหม่ = dynamic small-signal stability (domain ใหม่ ยึด convention เดิม)

อ้างอิง **Kundur Ch.12** (อ่านครบแล้ว — PDF เป็นภาพสแกน):
- §12.1 fundamental concepts (state-space, linearization)
- §12.2 eigenproperties (eigenvalue, eigenvector, mode shape, participation factor)
- §12.3 SMIB: §12.3.1 classical, §12.3.2 field circuit dynamics
- §12.4 effects of excitation system (AVR, K5/K6)
- §12.5 power system stabilizer (PSS)

---

## 2. ลำดับโมเดล (สร้างเป็นชั้น เพิ่ม state ทีละขั้น)

### Model A — Classical (2 states): `[Δωr, Δδ]`
สมการ (12.78):
```
A = [ -KD/(2H)   -Ks/(2H) ;   ω0   0 ]      b = [ 1/(2H) ; 0 ]
Ks = (E'·EB/XT)·cos δ0                              (12.76)
ωn = sqrt(Ks·ω0/2H),   ζ = (KD/2H)/(2ωn)           (12.80)
```

### Model B — + Field circuit dynamics (3 states): `[Δωr, Δδ, Δψfd]`
ใช้ K-constants (Heffron–Phillips). state matrix 3×3 (12.115–12.116):
```
ΔTe = K1·Δδ + K2·Δψfd                              (12.103)
Δψfd dynamics: a32 ∝ K4, a33 ∝ 1/T3 (T3 = K3·Td0')  (12.119–12.120)
K3 = 1/(1 + (Xd−X'd)/(XE+...)),  K4 = ...           
```

### Model C — + Exciter/AVR (4 states): `[Δωr, Δδ, Δψfd, Δv1]`
exciter ST1A: transducer `1/(1+sTR)`, gain `KA` (Fig 12.11). state matrix 4×4 (12.139–12.141):
```
a42 = K5/TR,  a43 = K6/TR,  a44 = −1/TR            (12.140)
a34 = −ω0·Rfd·KA/Ladu                              (exciter→field)
K5 = ∂Vt/∂δ,  K6 = ∂Vt/∂ψfd                        (12.132–12.134)
```

### Model D — + PSS (6 states): `[Δωr, Δδ, Δψfd, Δv1, Δv2, Δvs]`
PSS (Fig 12.14): gain `KSTAB` · washout `sTw/(1+sTw)` · lead-lag `(1+sT1)/(1+sT2)`. state matrix 6×6 (12.151):
```
Δv2: washout state,  Δvs: lead-lag output → summing junction ของ exciter
```

---

## 3. Golden References (เกณฑ์ผ่าน — เทียบเลขกับตำรา < 1%)

### Golden 1 — Classical, Example 12.2
input: H=3.5, X'd=0.3, X_E=0.65, Et=1.0∠36°, EB=0.995, P=0.9, Q=0.3, f=60Hz

| ปริมาณ | ค่า |
|--------|-----|
| δ0 | 49.92° |
| E' | 1.123 ∠13.92° |
| XT | 0.95 |
| Ks | 0.757 |
| ωn | 6.387 rad/s = 1.0165 Hz |

eigenvalue table:

| KD | λ | ζ |
|----|---|-----|
| 0  | 0 ± j6.39 | 0 |
| 10 | −0.714 ± j6.35 | 0.112 |
| −10| +0.714 ± j6.36 | −0.112 (unstable) |

time response (validate step plot):
```
Δωr(t) = −0.0015·e^(−0.714t)·sin(6.35t)
Δδ(t)  =  0.088·e^(−0.714t)·cos(6.35t − 0.112)   [rad? scaled]
```

### Golden 2 — Field + AVR, Table 12.1
system: K1=1.591, K2=1.5, K3=0.333, K5=−0.12, K6=0.3, KD=0, H=3.0, ω0=377, T3=1.91 (ที่ ω=10 rad/s)

| KA | Ks = K1+Ks(Δψfd) | KD(Δψfd) |
|----|------------------|----------|
| 0    | 1.5885 | +1.772 |
| 15   | 1.5817 | +0.024 (boundary) |
| 25   | 1.5812 | −1.166 (unstable) |
| 200  | 1.8714 | −12.272 (most negative) |
| ∞    | 2.1910 | 0.000 |

ข้อสรุป: K5<0 + AVR gain สูง → damping ลบ → ระบบสั่นไม่หยุด (จุดที่ PSS เข้ามาแก้)

### Golden 3 — PSS
ที่ KA=200: KD=−12.27 (ไม่เสถียร) → ใส่ PSS (KSTAB ที่เหมาะสม) → KD กลับเป็นบวก → eigenvalue ย้ายเข้า LHP
- validation: PSS ทำให้ Re(λ) ของ swing mode < 0 และ ζ เพิ่มเป็นค่าบวกชัดเจน

---

## 4. โครงสร้างไฟล์ (ยึด convention เดิม — เพิ่มอย่างเดียว ไม่แก้ของเก่า)

```
n_bus_clone/
├── +cases/
│   ├── case_kundur_smib_classical.m       [ใหม่] Ex 12.2 params
│   └── case_kundur_smib_detailed.m        [ใหม่] §12.4 K-constants + machine d-q params
├── +smib/                                  [ใหม่ package]
│   ├── smib_init_classical.m              operating point → δ0, E', Ks
│   ├── smib_k_constants.m                 K1..K6 จาก operating point
│   ├── smib_build_state_matrix.m          A สำหรับ model A/B/C/D (เลือกด้วย option)
│   ├── smib_analyze.m                      eig → ωn, ζ, freq(Hz), mode shape, participation factor
│   └── smib_from_powerflow.m              [DEFERRED] IEEE 5-bus → SMIB equivalent (ทำหลัง Kundur ครบ)
├── internal/plotting/
│   ├── smib_plot_root_locus.m            sweep KD / KA / KSTAB บน s-plane
│   ├── smib_plot_step_response.m         time-domain Δδ, Δωr
│   ├── smib_plot_mode_shape.m            compass plot eigenvector
│   └── smib_plot_torque_vs_ka.m          Ks, KD vs KA (Table 12.1)
├── tests/
│   └── test_smib.m                        validate Golden 1 + Golden 2
└── run_smib_example.m                     [ใหม่] standalone demo end-to-end (ทุก model + ทุกกราฟ)
```

---

## 5. แผนเป็นเฟส

### Phase 0 — Core math (Model A + B)
- `case_kundur_smib_classical.m`, `smib_init_classical.m`, `smib_build_state_matrix.m` (A/B), `smib_analyze.m`
- **Verify:** Golden 1 (δ0, Ks, ωn, eigenvalue table)

### Phase 1 — Validation gate
- `test_smib.m` เทียบ Golden 1 (tol<1%) — **ผ่าน = ไปต่อ**

### Phase 2 — Detailed model (Model C + D)
- `case_kundur_smib_detailed.m`, `smib_k_constants.m`, ขยาย `smib_build_state_matrix.m` (C/D)
- **Verify:** Golden 2 (Table 12.1), Golden 3 (PSS ทำให้เสถียร)

### Phase 3 — Plots
- root locus, step response, mode shape, torque-vs-KA
- **Verify:** กราฟสอดคล้อง eigenvalue (KD>0 ลู่เข้า, AVR gain สูง ลู่ออก, PSS ดึงกลับ)

### Phase 4 — Standalone demo (Kundur-only)
- `run_smib_example.m` — รันครบ end-to-end ด้วย Kundur cases ล้วน (classical + detailed + PSS, ทุกกราฟ)

### Phase 4-IEEE — [DEFERRED] IEEE 5-bus integration
- `smib_from_powerflow.m` — ดึง operating point จาก power flow เดิม
- ทำหลัง Kundur เสร็จครบ ตามคำสั่งผู้ใช้

### Phase 5 — Report (English)
- `REPORT_SMIB_SmallSignal.md` สไตล์เดียวกับ `REPORT_IEEE5Bus_*.md`
- theory + equations + golden comparison tables + plots + conclusion

---

## 6. Verification

| ระดับ | วิธี |
|------|------|
| Unit | `test_smib.m` เทียบ Golden 1 + Golden 2 |
| Sanity | KD>0 stable, KA สูง+K5<0 unstable, PSS restore stable |
| Cross-check | ωn จาก eig = ωn จากสูตร; freq oscillation ~1 Hz (local mode) |

**ข้อจำกัด:** เครื่องนี้ไม่มี MATLAB → เขียน test + ใส่ค่าคาดหวังในไฟล์ ให้ผู้ใช้รันยืนยัน

---

## 7. ความเสี่ยง / หมายเหตุ

- Model B–D ต้องการ K-constants ที่ derive จาก machine d-q parameters — Kundur ให้ค่า K สำเร็จรูปสำหรับ example แต่การคำนวณ K จาก raw params (Ld, Lq, Lfd, Rfd, saturation) ซับซ้อน. **แผน:** Phase 2 รับ K-constants โดยตรงจาก case (ตรง Table 12.1) ก่อน แล้วค่อยเพิ่มการ derive จาก d-q params ภายหลังถ้าต้องการ
- IEEE 5-bus ไม่มี machine dynamic params (H, X'd) ในข้อมูลเดิม → ต้องสมมติค่ามาตรฐาน หรือกำหนดเพิ่มใน case
```
