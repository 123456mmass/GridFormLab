# Context — SMIB Small-Signal Stability Project

> ไฟล์นี้บันทึกว่าเรากำลังทำอะไร ทำถึงไหนแล้ว (update เป็นระยะ)
> Last updated: 2026-05-31 (Phase 3-6 เสร็จครบ — Kundur scope สมบูรณ์)

## เป้าหมาย

ต่อยอด MATLAB toolkit เดิม (`n_bus_clone` — steady-state power flow) ด้วยการวิเคราะห์
**Small-Signal Stability บนระบบ SMIB** (Single-Machine Infinite-Bus) ตามตำรา **Kundur Ch.12**
พร้อม report (อังกฤษ) + กราฟ + เอกสารสรุปความรู้ (PDF ไทย)

## การตัดสินใจที่ยืนยันแล้ว

| ประเด็น | คำตอบ |
|---------|-------|
| ขอบเขตโมเดล | ครบถึง excitation + PSS (§12.3–12.5) |
| ระบบอ้างอิง | **Kundur เท่านั้นก่อน** — IEEE 5-bus deferred (ทำหลัง) |
| ภาษา report | อังกฤษ |
| รูปแบบ | standalone script (ไม่รวม GUI) |
| K-constants | **derive จาก machine d-q params** (ไม่ใช่รับค่าสำเร็จรูป) |

## โมเดล 4 ชั้น

- **A** classical (2 states: Δωr, Δδ) — สมการ 12.78
- **B** + field circuit (3 states: +Δψfd) — K1–K4, 12.115
- **C** + exciter/AVR (4 states: +Δv1) — K5,K6, ST1A, 12.139–12.141
- **D** + PSS (6 states: +Δv2, Δvs) — washout + lead-lag, 12.151

## Golden references (เกณฑ์ผ่าน <1%)

1. **Ex 12.2 (classical):** δ0=49.92°, E'=1.123∠13.92°, XT=0.95, Ks=0.757, ωn=6.387 rad/s=1.0165 Hz.
   eigenvalues: KD=0→0±j6.39 (ζ=0); KD=10→−0.714±j6.35 (ζ=0.112); KD=−10→+0.714±j6.36 (unstable)
   time resp: Δωr=−0.0015·e^(−0.714t)·sin(6.35t)
2. **Table 12.1 (field+AVR):** K1=1.591,K2=1.5,K3=0.333,K5=−0.12,K6=0.3,H=3.0,ω0=377,T3=1.91.
   KA: 0→KD=+1.77; 15→+0.024(boundary); 25→−1.17(unstable); 200→−12.27; ∞→0
3. **PSS:** ที่ KA=200 (KD=−12.27 unstable) → ใส่ PSS → KD บวก → eigenvalue เข้า LHP

## โครงสร้างไฟล์ (ยึด convention เดิม, เพิ่มอย่างเดียว)

```
+cases/case_kundur_smib_classical.m, case_kundur_smib_detailed.m
+smib/smib_init_classical.m, smib_k_constants.m, smib_build_state_matrix.m, smib_analyze.m, smib_from_powerflow.m
internal/plotting/smib_plot_{root_locus,step_response,mode_shape,torque_vs_ka,power_response,eig_comparison}.m
tests/test_smib.m
run_smib_example.m
```

## สถานะ (phases)

- [x] วางแผน → `PLAN_SMIB_SmallSignal.md` + plan mode → `radiant-meandering-manatee.md`
- [x] อ่าน Kundur §12.3–12.5 ครบ (render หน้า scan → ดู, golden refs ครบ 4 ชุด)
- [x] **Phase 0 เสร็จ + verified ด้วย MATLAB R2026a:**
  - Model A (classical): δ0=49.91°, Ks=0.7574, eigenvalue table KD=0/10/−10 ตรง golden A เป๊ะ
  - Model B (field circuit, derive K จาก d-q): init ครบ (δ0=79.13°, Efd0=2.395), K1=0.7643 K2=0.8649 K4=1.4187 T3=2.356, A-matrix ตรง, λ=−0.110±j6.41 ζ=0.017 ตรง golden B เป๊ะ
- [x] **Phase 1 เสร็จ** — test_smib.m gate ผ่าน
- [x] **Phase 2 เสร็จ + verified (8/8 tests pass):**
  - Model C (AVR 4-state): Table 12.1 torque components ตรงทุก KA (0/15/25/200), AVR-only KA=200 → +0.504±j7.23 unstable ตรง Ex12.6
  - Model D (PSS 6-state): eigenvalues ตรง Ex12.6 เป๊ะ — swing −1.005±j6.607 (ζ=0.15), exciter −19.8±j12.8 (ζ=0.84), stable=1 (PSS ดึงกลับเสถียร)
  - K5,K6 derive form + torque decomposition (smib_torque_components.m)
  - ไฟล์เพิ่ม: case_kundur_smib_{avr,pss}.m, smib_torque_components.m, build_avr/build_pss
- [x] **Phase 3 เสร็จ + verified** — 4 plot funcs, headless render PNG ผ่าน, เทียบ eigenvalue ตรง:
  - smib_plot_root_locus.m (KD sweep: KD<0→RHP, KD>0→LHP), smib_plot_step_response.m (expm, ~1Hz decay)
  - smib_plot_mode_shape.m (compass + participation; Δωr/Δδ dominant, Δψfd~0.017), smib_plot_torque_vs_ka.m (Table 12.1 KD→neg)
- [x] **Phase 4 เสร็จ + verified** — run_smib_example.m รัน 4 models end-to-end, **26/26 golden checks PASS**, save_plots wiring ok
- [x] **Phase 5 เสร็จ + ปรับใหญ่** — docs/source/report_smib.tex → report_smib.pdf
  (**18 หน้า** หลังรื้อโครงตาม 11-item spec: title ใหม่ "Small-Signal Stability Analysis
  and MATLAB Simulation of a SMIB System Based on Kundur"; abstract เน้น SMIB/4 models/methods/results;
  + section "Single-Machine Infinite-Bus System" + TikZ diagram (E'∠δ—jX'd+jX_E—E_B);
  modelling แยก power-angle/swing/lineariz/state-space; state-space summary table; analysis-procedure
  7-step section; K-constants physical-meaning table (เน้น K5<0); figure-interpretation table;
  Discussion section; engineering Conclusion. **6 figures** (เพิ่ม 05_power_response, 06_eig_comparison;
  01_root_locus เพิ่ม shaded regions + KD points). pdflatex 2 รอบ, 0 overfull)
- [x] **Phase 6 เสร็จ** — docs/source/report_smib_thai.tex → report_smib_thai.pdf (11 หน้า, xelatex + Sarabun font, Thai glyphs render ok)
- [ ] Phase 4-IEEE [DEFERRED] IEEE 5-bus integration — ทำหลัง Kundur ครบ (smib_from_powerflow.m)

**สถานะรวม: Kundur scope สมบูรณ์ 100% — test 8/8 pass, runner 26/26 golden pass, รายงาน 2 ภาษาเสร็จ**

## อัปเดต GUI (2026-06-21)

- **ถอด AI service ออกหมด:** ลบ `ai_service/` (FastAPI + Docker), `+ai_client/`, `start_ai_service.m`, `ai_analyze_action.m`, `ai_chat_action.m` และลบ AI Chat tab ออกจาก GUI. ไม่มี dependency ภายนอก (LLM) อีกต่อไป.
- **ปรับปรุง GUI ให้โปร:** เขียน `create_gui_layout.m` ใหม่ — header มี logo accent box + title/subtitle + status dot, metric card มี left accent stripe, refined palette (light/dark).
- **แก้ bug theme toggle:** เดิมสร้าง orphan figure + recolor ไม่ครบ. ตอนนี้ rebuild-in-place (`create_gui_layout` ล้าง `fig.Children` แล้วสร้างใหม่ใน figure เดิม) + `wire_callbacks`/`cb` ที่ callback จับเพียง `fig` และดึง live app จาก `fig.UserData.app` — wiring ยังใช้ได้หลัง theme swap.
- **Wire SMIB เข้า GUI:** เพิ่ม method "SMIB Stability Analysis", tab "SMIB Stability" (s-plane + impulse response + eigenvalue table), `run_smib_action`/`show_smib_result`/`open_smib_figure`/`smib_summary_line`. `discover_cases` ใช้ `cases.<name>` prefix จึงเจอ SMIB case ได้. `on_case_changed` auto-switch method ให้เข้ากับ case (SMIB case ↔ SMIB method). Export รองรับ SMIB (CSV + PNG).
- **CI:** ลบ python-tests/docker-build jobs เหลือ MATLAB tests อย่างเดียว.

## บันทึกสำคัญ (สมการ derive K จาก d-q + K-form)

- init: δ0 = atan2(EBd0, EBq0) โดยตรง; saturation total ใช้ init, incremental ใช้ perturbation
- m2,n2 (eq 12.108) ใช้ **Lads incremental (no prime)** ไม่ใช่ L'ads parallel
- K4: a32 = −(ω0·Rfd/**Ladu**)·K4 (ไม่ใช่ /Lfd)
- **K-form (Model B/C/D สมมูล d-q):** a32=−K3·K4/T3, a33=−1/T3, b3=K3/T3, a34=−(K3/T3)·KA, a42=K5/TR, a43=K6/TR, a44=−1/TR; PSS a36=+(K3/T3)·KA
- Golden C/D ใช้ K-set ตรงจากตำรา (Ex12.6 K-set = Ex12.3 + K5=−0.1463,K6=0.4168); PSS Ex12.6: KSTAB=9.5,Tw=1.4,T1=0.154,T2=0.033
- package function เรียก sibling ต้อง qualify `smib.func()`
- Kundur PDF scan: pages render เก็บ `D:\Project\tmp_kundur\` (offset = book page + 22)

## หมายเหตุ / ข้อจำกัด

- **MATLAB R2026a ที่ `D:\MATLAB\R2026a\bin\matlab.exe`** — รัน headless ได้: `matlab.exe -batch "..."` (verified, code เดิมรันผ่าน NR 4 iters Vmin 0.9716). R2025b ก็มีแต่ไม่มี exe ใน bin
- Kundur PDF เป็นภาพสแกน (ไม่มี text layer) — render หน้าด้วย pymupdf เก็บที่ `D:\Project\tmp_kundur\` (offset = book page + 22)
- IEEE 5-bus เดิมไม่มี machine dynamic params (H, X'd, ...) → ต้องเพิ่ม/สมมติค่ามาตรฐานใน case
- Python บน Windows ต้องใช้ Windows path (`D:\...`) ไม่ใช่ `/d/...` (bash MSYS path แปลงไม่ได้)
- lean-ctx ctx_read มีปัญหากับ path บางครั้ง → ใช้ filesystem MCP แทน
- code เดิม base dir ใน README ชี้ `C:\Users\qwert\OneDrive\Desktop\api\n_bus_clone` แต่จริงอยู่ `D:\Project\Power-flow\n_bus_clone`
- **รายงาน toolchain:** TeXLive 2026 ที่ `C:\texlive\2026\bin\windows` (pdflatex + xelatex). ไม่มี pandoc.
  - English report: `pdflatex` ธรรมดา (รัน 2 รอบให้ TOC/refs)
  - Thai report: ต้อง `xelatex` + fontspec. **font "TH Sarabun PSK" ไม่มีในเครื่อง** — ใช้ "Sarabun" (Google Fonts) แทน
    via explicit Path `C:/Users/qwert/AppData/Local/Microsoft/Windows/Fonts/` + UprightFont=*-Regular ฯลฯ
  - tcolorbox `breakable` ต้อง `\tcbuselibrary{breakable}` ก่อนใช้ key breakable
  - render PDF ตรวจ glyph: ใช้ pymupdf (`fitz`) → PNG (ไม่มี pdftoppm)
- **runtests headless:** ต้อง `cd` project + `addpath(fullfile(pwd,'tests'))` ก่อน `runtests('test_smib')` (ชื่อไม่ใส่ .m/path)
```
