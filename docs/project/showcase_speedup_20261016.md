# สรุปสั้นสำหรับโชว์ — C++ GFM engine เร็วขึ้นกี่เท่า (NE39 160s study)
# เขียน team-lead 2026-10-16 — เลขทุกตัว = ค่าที่วัดได้จริงบนดิสก์ (path ท้ายไฟล์)
# วินาทีทุกช่องวัดแบบ serialize, speedup ทุกตัวมาจากคู่วัด window เดียวกัน

## 1. หัวข้อหลัก
| รายการ | wall (s) | speedup |
|---|---|---|
| MATLAB golden (NE39 160s, เดิม) | 1972.5 | 1x |
| C++ baseline (run008) | 335.6 | ~5.9x เทียบ MATLAB (cross-engine = context) |
| C++ + optimization ปลอดภัย (coloring+OpenMP+O3) | **84.3** | **3.35x วัดจริง same-window** / ~23x เทียบ MATLAB (context) |
| + Jacob/LU reuse = stack สุดท้าย (coloring+OpenMP+O3+reuse) | 107.4 (วันเครื่องช้า) / ~51.6 (normalize) | **x1.62 ต่อจากแถวก่อน (same-window) = รวม ~5.4x** |

- speedup ที่ขายได้จริง = 3.35x (window 1) x 1.62x (window 2) = **~5.4x** จาก baseline FD เปล่า 282.3 s -> stack สุดท้าย
- wall วัดจริง 107.4 s บนวันที่เครื่องช้ากว่า ~2x (control วันเดียวกัน 173.8 s) — normalize กลับเครื่องปกติ ~51.6 s = ข้อมูลประกอบ
- เทียบ MATLAB 1972.5 s -> ~38x (normalized) หรือ 18.4x บนเลขวันช้า = cross-engine context

- study: NE39 (9 SG + 5 IBR) 160 s, fixed-step h=1 ms = 160k steps, Newton implicit ทุก step
- วัด phase จริง: Jacobian FD 227.7 s -> 20.3 s, LU 46.3 s, io 15.0 s (ของ 84.3 s)

## 2. validate ยังไง (ว่าเร็วแล้วยังถูก)
- golden reference = trajectory run008 (C++ ต้นฉบับที่ผ่านเทียบ MATLAB แล้ว) ทุกค่า 160000 rows x 42 cols
- 4 เกณฑ์ฟิสิกส์: |dV| < 1e-3 pu, |dโอเมกา| < 1e-4 pu, เวลา reclose คลาด < 1 s, drift < 0.0377 rad/s
- **GATE A** (opt ที่ไม่เปลี่ยนเส้นทางคำนวณ: alloc / coloring / OpenMP): diff ต้องเป็น 0.0 เป๊ะทุกค่า
  — ผ่านจริง 0/160000x42 ทุกชั้น + counters newton=jacobian=300126 เท่าเดิม = เส้นทาง iteration ไม่ถูกแตะ
- **GATE B** (opt ที่เปลี่ยนเส้นทาง: reuse): max diff <= 1e-9 + เวลา event ต้องเท่า golden เป๊ะ
  — ผ่านจริงแล้ว: max diff ทุกคอลัมน์ 1.769e-10, reclose 100.4990 = 100.4990 (0.0000 s), drift 2.4e-9 (band 1e-9 ห่างจากเกณฑ์ฟิสิกส์ 1e6 เท่า)

## 3. optimize อะไรไปบ้าง (ทุกชั้นผ่าน gate แล้ว)
| ชั้น | วิธี | ผลวัดจริง |
|---|---|---|
| alloc | ตัด heap alloc + hoist scratch buffer | bitwise 0.0 |
| coloring | FD Jacobian -> sparse graph coloring (pattern จาก topology ของ case = superset โดยการสร้าง) | FD phase 227.7 -> 52.2 s (รวม wall ~2x) |
| OpenMP | ขน FD columns อิสระ | FD 52.2 -> 20.3 s (เพิ่ม ~1.5x) |
| -O3 | -O3 -ffp-contract=off -fno-fast-math | bitwise 0.0 (wall-neutral เก็บไว้) |
| reuse | Jacob/LU rebuild 1 ครั้ง/step + reuse เฉพาะ backsolve (knob GFL_S1_JREUSE, default 0 = legacy) | **ผ่าน GATE B**: diff 1.769e-10, reclose 0.0000 s, jac 300126->160000 (-47%), LU -40%, wall x1.6 same-window |
| warm-start | predictor ทายค่าตั้งต้น (GFL_S1_WSTART) | วัดแยกแล้ว: iter ลด 0.6%, wall -1.3% = ไม่คุ้ม -> ไม่เข้า stack (default OFF) |

- รวม safe track = 282.3 -> 84.3 s = **3.35x** (คู่วัด window เดียวกัน); ต่อด้วย reuse x1.62 = **รวม ~5.4x** ถึง stack สุดท้าย
- parallel LU = ลองแล้วไม่คุ้ม (barrier-bound ที่ n=238) — ตัดทิ้ง ไม่ขาย

## 4. ความสัตย์จริงที่ต้องบอกคู่กัน
- reclose: C++ 100.5 s vs MATLAB 119.5 s = ต่างที่นโยบาย guard (dtheta threshold) ไม่ใช่ solver
  — เวลา event ไวต่อ guard config (~14.6 s) มากกว่ารายละเอียด solver (วัดได้ 1.6e-10) หลาย order
- ~23x เทียบ MATLAB เป็น cross-engine/cross-window = ใช้เป็น context; 3.35x คือตัวเลขใน engine ที่คุมตัวแปรได้
- ความเร็วเครื่องต่างกัน 1.5-2x ระหว่างวัน -> ทุกอัตราเร็วขึ้นเทียบคู่วัดเดียวกัน window เดียวเท่านั้น

## 5. หลักฐาน
- gate: %TEMP%\cpp_perf_parity.py (exit 0/1/2) — รายงานผลทุกชั้นใน %TEMP%\cpp_perf_parity_*.txt
- รายงานเต็ม: docs/project/benchmark_report_20261015.md + %TEMP%\cpp_perf_consolidated_final.md
- runs: D:\4-year-project\GridFormLab-port\runs\{stage2_smoke_ne39_008_gfm160s_golden, perf_clean_fd160s, perf_clean_col160s, perf_reuse2_160s_reuse2dev, perf_reuse2o3_160s_reuse2dev, perf_ctrl_o3_160s_reuse2dev}\manifest.json
- GATE B report: %TEMP%\cpp_perf_parity_reuse2_criteria_reuse2dev.txt + cpp_perf_parity_reuse2o3_reuse2dev.txt
