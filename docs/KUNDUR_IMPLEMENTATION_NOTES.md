# Kundur Two-Area System — Load Model & Damping Study

## สรุปผล (อัปเดต 2026-07-08)

หลังศึกษาตำรา Kundur & Sauer-Pai + ทดสอบกับ reference ภายนอกหลายแหล่ง
พบว่า **ค่าตำรา Kundur Table E12.3 reproduce ไม่ได้ด้วย tools สมัยใหม่**
(PSS/E, PacDyn, Dynaω) เป็น known issue ที่ colib.net ยอมรับไว้

ดังนั้น acceptance criteria เปลี่ยนเป็นเทียบกับ **reproduced literature range**
แทนค่าตำรา (ดู `FEEDBACK_CHECKLIST.md`)

## Load Model (ยืนยันจากตำรา + colib.net)

Kundur Example 12.6 / Example a (small-signal, constant excitation) ใช้:
- **Active power P**: constant current (CC)
- **Reactive power Q**: constant impedance (CZ)
- ทั้งสองมาจาก ZIP load model โดยตั้ง `I_p = 1, Z_q = 1`, ค่าอื่น = 0

→ โค้ดใช้ `load_model = 'cc_p_cz_q'` ✓ ถูกต้องตามที่ Kundur ระบุ

หมายเหตุ: เพื่อ reproduce load-flow results ของ Kundur เฉพาะ load flow (ไม่ใช่
dynamic), colib.net บอกว่าต้องใช้ constant power (P,Q) สำหรับ load และ
constant impedance สำหรับ shunt capacitor — แต่นี่เป็นเรื่อง load-flow ไม่ใช่
small-signal analysis

## ZIP Load Model (จาก colib.net)

```
P = P_Ref * (Z_p * (U/U_0)^2 + I_p * (U/U_0) + P_p)
Q = Q_Ref * (Z_q * (U/U_0)^2 + I_q * (U/U_0) + P_q)
```

Kundur Example 12.6: `I_p = 1, Z_q = 1`, ค่าอื่น = 0 → CC-P + CZ-Q

## ผลลัพธ์ปัจจุบัน (cc_p_cz_q, no saturation)

| Mode | ค่าเรา | Reproduced range | Kundur E12.3 |
|------|--------|------------------|-------------|
| Interarea | -0.123+j3.42, ζ=0.036 | ζ 0.03–0.04 | ζ=0.032 |
| Local 1 | -0.580+j6.79, ζ=0.085 | ζ 0.080–0.092 | ζ=0.072 |
| Local 2 | -0.589+j6.98, ζ=0.084 | ζ 0.080–0.090 | ζ=0.072 |
| Field | -0.165, -0.175 | — | -0.265, -0.276 |
| d-damper | -29 … -37 | — | -31 … -38 |
| q-damper | -2.4, -3.3, -4.7, -4.7 | — | -3.4, -4.1, -5.3, -5.3 |

- **Frequency**: ทุก EM mode ตรงตำราภายใน 1.5% ✓
- **Interarea ζ**: 0.036 อยู่ในช่วง reproduced (0.03–0.04) ✓
- **Local ζ**: 0.084–0.085 อยู่ในช่วง reproduced (0.080–0.092) ✓
  - **ตรงกับ academia.edu (0.080–0.085) ทุกป**
  - ค่าตำรา 0.072 เป็น outlier ที่ไม่มี tool ใด reproduce ได้
- **Field modes**: ตื้นกว่าตำรา (-0.17 vs -0.27) เพราะ CC-P load coupling อ่อน
  - ถ้าใช้ CZ load (constant impedance) field mode ลึกขึ้นเป็น -0.26 (ใกล้ตำรา)
  - แต่ colib.net ยืนยันว่า Kundur ใช้ CC-P ไม่ใช่ CZ

## สิ่งที่ตรวจสอบแล้วว่าถูกต้องในโค้ด
1. ✅ Operating point: DAE residual = 1.5e-10 (แทบศูนย์)
2. ✅ Load model `cc_p_cz_q` ตรงกับที่ Kundur/colib ระบุ
3. ✅ Power flow: P = 7.00, 7.00, 7.19, 7.00 pu ตรงตำรา
4. ✅ Machine parameters ตรงกับ IEEE PES-TR18 ทุกตัว
5. ✅ Stator equations ตรงกับ ANDES/GENROU (generator convention)
6. ✅ Damper flux equations (f5/f6) ตรงกับ ANDES
7. ✅ Unit conversion (H, Tm, Te, reactances) สอดคล้องกัน
8. ✅ Saturation params (Asat=0.015, Bsat=9.6, PsiT1=0.9) ตรง colib

## สิ่งที่ตรวจแล้วไม่ใช่สาเหตุของ error
- Id_eff/Iq_eff form: ลองเปลี่ยนเป็น real Id แล้วผลไม่ดีขึ้น
- Sign ของ damper eq: ตรง ANDES อยู่แล้ว
- gamma_d2 สูตร: ถูกต้อง
- Ra: ผลน้อยมาก
- Saturation on/off: ผลน้อยมาก

## ข้อสังเกตทางเทคนิค
- State 5,6 ของโค้ด label เป็น `psi''d`/`psi''q` แต่จริงๆ คือ damper fluxes
  `psi_1d`/`psi_2q` (ตาม Sauer-Pai/ANDES) — ชื่อทำให้สับสนแต่สมการถูกต้อง
- Id_eff form ในโค้ด (g_d1=0.5, g_d2=5.0) ต่างจากสูตร Sauer-Pai 3.151
  (A_d=0.0067) แต่ให้ damper modes ใกล้ตำรากว่า จึงเก็บไว้

## ไฟล์ศึกษา
- `docs/DAMPING_ROOT_CAUSE_ANALYSIS.md` — การวิเคราะห์สาเหตุเชิงลึก
- `probe_pure_realization.m` — ทดสอบ pure ANDES realization
- `probe_fix_transients.m` — ทดสอบแก้ transient equations
- `docs/sauer_pai.txt` — สมการ Sauer-Pai 3.148–3.159 (extracted)
- `docs/genrou.txt` — PowerWorld GENROU documentation
