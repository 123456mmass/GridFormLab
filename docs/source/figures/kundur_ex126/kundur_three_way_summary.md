# Kundur 2-area 4-machine: OURS vs PSAT vs PGAz

## สถานะการรองรับ model

| Tool | Classical (2nd) | 6th-order GENTPJ | ใช้ในเคสนี้ |
|---|:---:|:---:|---|
| **OURS** (`ts_simulate`) | ✓ | ✓ (model='genpj6') | 6th-order |
| **PSAT** (`d_kundur1_mdl`) | ✓ | ✓ (model 6) | 6th-order |
| **PGAz** (`pgaz_ts`) | ✓ | ✗ (classical เท่านั้น) | **N/A — เข้าไม่ได้** |

PGAz รองรับเฉพาะ classical (pgaz_ts: "Classical synchronous generator model (2nd-order)", ใช้ Gen(:,11)=H, Gen(:,16)=X'd). ไม่มี GENROU/6th-order/subtransient. ดังนั้น Kundur 6th-order เทียบได้แค่ OURS vs PSAT.

## params (verify แล้วตรงกัน 3 ฝั่งที่เกี่ยว)

| พารามิเตอร์ | OURS | PSAT | หมายเหตุ |
|---|---:|---:|---|
| Xd / X'd / X''d | 1.8 / 0.3 / 0.25 | 1.8 / 0.3 / 0.25 | machine base 900 MVA |
| Xq / X'q / X''q | 1.7 / 0.55 / 0.25 | 1.7 / 0.55 / 0.25 | — |
| Ra / Xl | 0.0025 / 0.2 | 0.0025 / 0.2 | — |
| T'd0 / T''d0 / T'q0 / T''q0 | 8 / 0.03 / 0.4 / 0.05 | 8 / 0.03 / 0.4 / 0.05 | — |
| H (G1,G2 / G3,G4) | 6.5 / 6.175 | 6.5 / 6.175 | M=13 / 12.35 |
| Excitation | constant Efd (manual) | constant Efd (no AVR) | ตรง Table E12.3 |

## Power flow (OURS vs PSAT)

| Metric | OURS vs PSAT |
|---|---:|
| max \|ΔV\| | 0.0025 pu |
| max \|Δangle\| | 0.134 deg |

slack bus ต่างกัน (เรา bus1, PSAT bus3) แต่ cosmetic — converge ไปที่ operating point เดียวกัน. ความต่างที่เหลือมาจาก load model.

## Transient stability — 6th-order (OURS vs PSAT)

สถานการณ์: solid 3-phase fault bus 8, t=1.0–1.05 s, dt=0.001 s, t_end=10 s, load=constant-impedance.

เทียบใน **COI frame** (PSAT ล็อก slack angle ตลอด TD, เราปล่อย COI ลอยเพราะไม่มี governor → เป็น convention ต่างกัน ไม่ใช่ model ผิด):

| Metric | OURS vs PSAT | OURS vs PGAz | PSAT vs PGAz |
|---|---:|---:|---:|
| max \|Δδ\_rel\| (deg) | **1.90** | N/A | N/A |
| max \|Δω\_rel\| (pu) | **3.7e-4** | N/A | N/A |
| max \|Δδ\_abs\| (deg) | 40* | — | — |

\* reference-frame offset (PSAT fix slack, เรา float) — ไม่ใช่ error; COI frame คือการเทียบที่ถูกต้อง

## สรุปการ validate ของ 6th-order model (2 ชั้น independent)

| การเทียบ | เทียบกับ | ผล | ประเภท |
|---|---|---:|---|
| SSSA eigenvalues | Kundur Table E12.3 (book) | **<0.5%** | model-reconstruction benchmark |
| Transient (6th-order) | PSAT (independent code + implicit-Newton scheme) | **1.9° COI** | independent cross-validation |

## หมายเหตุ
- หากต้องการตาราง 3 ฝั่ง (OURS vs PSAT vs PGAz) สำหรับ Kundur ต้องใช้ **classical model** (ที่ PGAz รองรับ) — สามารถทำได้โดยสร้าง Kundur case ใน PGAz format แล้วรันทั้ง 3 ฝั่งใน classical
- ไฟล์ผล: `docs/source/figures/kundur_ex126/kundur6_ts_compare_psat_ours.{md,png}`, `psat_kundur6_ts_raw.mat`
- guardrail test: `tests/test_kundur6_psat_ts.m` (ผ่าน)
- Regression: 64 Passed, 0 Failed
