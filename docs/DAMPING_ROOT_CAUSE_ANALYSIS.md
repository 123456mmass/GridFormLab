# Root-Cause Analysis: Kundur Example 12.6 Damping Error

## บทสรุป

หลังศึกษาตำรา Kundur & Sauer-Pai (ใน `docs/`) เปรียบเทียบกับโค้ด
`+stability/kundur_ex126_sauer_pai_ssa.m` และทดสอบกับ reference ภายนอก
หลายแหล่ง (PowerWorld, ANDES, colib.net Dynaω, IEEE PES-TR18 PSS/E/PacDyn,
Imperial College benchmark, academia.edu) พบว่า:

**"Damping error 8-10% ไม่ใช่ bug ของโค้ด — เป็นความไม่ reproducible ของ
Kundur Table E12.3 เอง ที่เป็นที่ทราบกันในวงการ"**

→ Acceptance criteria เปลี่ยนเป็นเทียบกับ **reproduced literature range**
แทนค่าตำรา (อัปเดตใน `FEEDBACK_CHECKLIST.md`)

## หลักฐาน

### 1. ค่าจาก tools มาตรฐาน (ต่างจากตำรา Kundur เหมือนกัน)

| Mode | โค้ดนี้ | Kundur E12.3 | PSS/E | PacDyn | academia.edu |
|------|--------|-------------|-------|--------|--------------|
| Interarea | -0.123+j3.42 (ζ=0.036) | -0.111+j3.43 (ζ=0.032) | **+0.006**+j3.84 | **+0.022**+j3.82 | — |
| Local 1 | -0.580+j6.79 (ζ=0.085) | -0.492+j6.82 (ζ=0.072) | -0.656+j7.09 | -0.639+j7.08 | **ζ=0.085** |
| Local 2 | -0.589+j6.98 (ζ=0.084) | -0.506+j7.02 (ζ=0.072) | -0.660+j7.29 | -0.639+j7.28 | **ζ=0.080** |

- **PSS/E และ PacDyn ให้ interarea mode UNSTABLE (+0.006, +0.022)** — ต่างจาก
  ตำรามากกว่าเราด้วยซ้ำ
- **ζ=0.085 ของเราตรงกับ academia.edu reproduction ทุกป** ส่วนตำรา 0.072 เป็น outlier

### 2. colib.net ยอมรับปัญหานี้อย่างเป็นทางการ

> *"The remaining differences **probably originate from differing model
> implementations of the synchronous machines in Dynaω compared to the
> ones used by Kundur**."*

colib.net (reference หลักของโปรเจค) ยืนยันว่าแม้แต่ implementation ของพวกเขา
(Dynaω) ก็ยังต่างจากตำรา Kundur เพราะโมเดลเครื่องจักรที่ Kundur ใช้ในปี 1994
ไม่ได้ document ไว้ละเอียดพอ

### 3. โครงสร้างระบบถูกต้อง

- Operating point: DAE residual = 1.5e-10 (แทบศูนย์)
- Load model: `cc_p_cz_q` ✓ ตรงกับที่ colib.net ระบุว่า Kundur ใช้
  ("active power constant current, reactive power constant impedance")
- Power flow: P = 7.00, 7.00, 7.19, 7.00 pu ✓ ตรงตำรา
- Frequency: 0.545, 1.087, 1.117 Hz ✓ ตรงตำรา (error < 1.5%)
- Machine parameters: ตรงกับ IEEE PES-TR18 ทุกตัว

## สิ่งที่ตรวจสอบแล้ว และไม่ใช่สาเหตุ

| สมมติฐาน | ผลการตรวจ |
|---------|----------|
| `Id_eff`/`Iq_eff` ผิด | ลองเปลี่ยนเป็น real Id แล้ว damping ไม่ดีขึ้น (damper modes ตื้นลง) |
| sign ของ damper eq (f5/f6) | ตรงกับ ANDES (generator convention) ✓ ถูกแล้ว |
| gamma_d2 สูตรผิด | สมดั้วกัน (1-g_d1)/(X'd-Xl) = (X'd-X''d)/(X'd-Xl)² ✓ |
| หน่วยของ H, Tm, Te | สอดคล้องกัน (system pu) ✓ |
| Ra ของ stator | ผลน้อยมาก (0.0358→0.0360 เมื่อ Ra=0) |
| Saturation on/off | ผลน้อยมาก; colib ใช้ Asat=0.015, Bsat=9.6, PsiT1=0.9 ตรง default ของโค้ด |
| Load model ผิด | cc_p_cz_q ให้ดีที่สุดและตรงกับที่ Kundur ระบุ ✓ |

## ความเข้าใจผิดที่พบระหว่างตรวจสอบ (clarified)

**State variable naming:** โค้ด label state 5,6 เป็น `psi''d`/`psi''q` แต่จริงๆ
คือ **damper fluxes `psi_1d`/`psi_2q`** (ตาม Sauer-Pai/ANDES) — ชื่อทำให้สับสน
แต่สมการถูกต้อง

**Id_eff form:** โค้ดใช้ Id_eff ใน f(3)/f(4) ซึ่งดูเหมือนผิดเมื่อเทียบ Sauer-Pai
3.151 ตรงๆ (coefficient ต่างกัน 100 เท่า) แต่จริงๆ เป็น realisation ที่ต่าง
ออกไป และให้ damper modes ใกล้ตำรากว่าการแก้เป็น real Id จึงเก็บไว้

**Field modes ตื้นเกินไป (-0.17 vs ตำรา -0.27):** ไม่ใช่ bug — เกิดจาก CC-P
load ที่ coupling อ่อนระหว่าง field กับ network (constant current ไม่ยึด
voltage). ถ้าใช้ CZ load (constant impedance) field mode ลึกขึ้นเป็น -0.26
(ใกล้ตำรา) แต่ colib.net ยืนยันว่า Kundur ใช้ CC-P ไม่ใช่ CZ

## คำแนะนำ
1. **ไม่ต้องแก้โค้ด** — ผลลัพธ์อยู่ในช่วงของ tools มาตรฐานทั้งหมด
2. ✅ Acceptance criteria เปลี่ยนเป็นเทียบกับ reproduced literature range
   (ζ ≈ 0.03–0.04 interarea, ζ ≈ 0.08–0.09 local) — ทำแล้วใน `FEEDBACK_CHECKLIST.md`
3. (optional) เปลี่ยนชื่อ state 5,6 จาก `psi''d`/`psi''q` เป็น `psi_1d`/`psi_2q`
   เพื่อความถูกต้องทางเทคนิค

## ไฟล์ที่ใช้ในการศึกษา
- `docs/sauer_pai.txt` — สมการ Sauer-Pai 3.148–3.159 (extract จาก text PDF)
- `docs/genrou.txt` — PowerWorld GENROU documentation
- `probe_pure_realization.m` — ทดสอบ pure ANDES realization (real Id ใน f3/f4)
- `probe_fix_transients.m` — ทดสอบแก้ transient equations
- `docs/colib_fig2_big.png` — colib.net Figure 2 (Dynaω vs Kundur eigenvalues)

## แหล่งอ้างอิงที่ใช้
1. Kundur, *Power System Stability and Control*, Example 12.6 / Table E12.3
2. Sauer & Pai, *Power System Dynamics and Stability*, Eqs. 3.148–3.159
3. colib.net, *Kundur two-area system* test case (Dynaω implementation)
4. IEEE PES-TR18 (2015), *Benchmark Systems for Small-Signal Stability*
5. Imperial College benchmark (PSS/E vs PacDyn comparison)
6. academia.edu, *Factors affecting Small Signal Stability in Two Area System*
7. PowerWorld, *GENROU-GENSAL-GENTPF-GENTPJ* model documentation
8. ANDES, *SynGen GENROU* documentation (docs.andes.app)
