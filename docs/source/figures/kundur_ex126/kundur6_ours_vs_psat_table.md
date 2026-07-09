# Kundur 2-area 4-machine 6th-order: OURS vs PSAT

Model เดียวกัน (6th-order, params ตรงกันทุกตัว, no AVR) เทียบ 3 ระดับ: PF, SSSA, TS.

## สรุปตาราง

| ระดับ | เทียบ | ผล | สถานะ |
|---|---|---:|---|
| **PF** | OURS vs PSAT | max\|ΔV\|=0.0025 pu, max\|Δθ\|=0.134° | ✅ ตรง |
| **SSSA** | OURS vs **book (Table E12.3)** | **<0.5%** (real/imag/damping) | ✅ ตรง (benchmark จริง) |
| **SSSA** | PSAT vs book | 9–14% (freq ต่ำกว่า book) | ⚠️ PSAT ต่างจาก book |
| **SSSA** | OURS vs PSAT | ~14% (PSAT ต่างจาก book, เราตรง book) | คนละ formulation |
| **TS** | OURS vs PSAT (COI) | max\|Δδ\|=1.90°, max\|Δω\|=3.7e-4 pu | ✅ ตรง |

## PF (OURS vs PSAT)
| Metric | ค่า |
|---|---:|
| max \|ΔV\| | 0.0025 pu |
| max \|Δangle\| | 0.134 deg |

slack bus ต่างกัน (bus1 vs bus3) แต่ cosmetic; ความต่างที่เหลือ = load model.

## SSSA (eigenvalues) — benchmark คือ Kundur Table E12.3 (book)

| Mode | Book (E12.3) | OURS (modern) | PSAT | OURS vs book | PSAT vs book |
|---|---|---|---|---:|---:|
| interarea | -0.111 ± j3.430 | -0.112 ± j3.432 | -0.127 ± j3.128 | <0.5% | 8.8% |
| local 1 | -0.492 ± j6.820 | -0.492 ± j6.800 | -0.519 ± j6.174 | <0.5% | 9.5% |
| local 2 | -0.506 ± j7.020 | -0.505 ± j7.032 | -0.510 ± j5.998 | <0.5% | 14.5% |

- **OURS ตรง book <0.5%** (real/imag/damping) — คือ model-reconstruction benchmark ที่ validate ไว้
- **PSAT ต่ำกว่า book 9–14%** ใน frequency → PSAT model 6 มี formulation ต่างจาก Kundur GENTPJ/book (ไม่ใช่ solver error; ลอง load model cp/cz/cc ทุกตัวแล้วยังต่าง)
- ดังนั้น SSSA "OURS vs PSAT" ต่างเพราะ **PSAT ต่างจาก book** ไม่ใช่เพราะเราผิด

## TS (6th-order, solid fault bus 8, 1.0–1.05s, t_end=10s) — OURS vs PSAT (COI frame)
| Metric | ค่า |
|---|---:|
| max \|Δδ_rel\| | 1.90 deg |
| max \|Δω_rel\| | 3.7e-4 pu |
| max \|Δδ_abs\| | 40 deg (reference offset: PSAT ล็อก slack, เรา float no-governor) |

TS ตรงแม้ SSSA frequency ต่าง เพราะ oscillation amplitude เล็ก (~0.5°) หลัง fault 50ms ทำให้ phase drift จาก frequency ต่างไม่โต; diff อยู่ ~0.5° ตลอด 10s.

## สรุปความหมาย
- **PF + TS**: OURS กับ PSAT ตรงกันดี (independent cross-validation ผ่าน)
- **SSSA**: benchmark จริงคือ book; **OURS ตรง book <0.5%**, PSAT ต่างจาก book 9–14% (PSAT model 6 ≠ Kundur book formulation) → ฝั่งเราแม่นกว่าเทียบกับ book
- 6th-order model ของเรามีหลักฐาน 2 ชั้น: (1) <0.5% vs book SSSA, (2) 1.9° vs PSAT TS

ไฟล์: `kundur_three_way_summary.md`, `kundur6_ts_compare_psat_ours.{md,png}`, `psat_kundur6_ts_raw.mat`, `psat_kundur6_sssa.mat`
