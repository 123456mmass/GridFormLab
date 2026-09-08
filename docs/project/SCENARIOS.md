# Scenario ที่มีในโปรเจคนี้

บันทึกนี้ตอบคำถามเดียว: **มี scenario อะไรให้รันได้บ้าง แต่ละอันตอบคำถามอะไร
และผลล่าสุดคืออะไร** เขียนไว้เพราะตอนนี้มี 2 ชุดที่คนละที่มา คนละ generator
คนละไฟล์รูป และเคยสับสนกันมาแล้ว

ทั้งหมดใช้ IEEE-14 bus, 1 SG (บัส 1) + 4 dual-mode IBR (บัส 2/3/6/8),
`case_profile='eecon49_figure4'` → `ibr_model_id='eecon49_dual'`
(GFL มี PLL / GFM เป็น VSG ไม่มี PLL, 16 สเตต, DC-source เป็นสเตตที่ 17)
ลำดับ device คงที่: `[1]=SG1 [2]=IBR2 [3]=IBR3 [4]=IBR6 [5]=IBR8`

---

## ชุด A — chronology ที่ส่งมอบแล้ว (1 อัน)

รายงานและ deck ทุกตัวอ้างผลจาก **chronology เดียวนี้**

| | |
|---|---|
| ลำดับเหตุการณ์ | `sg_trip 20 → load +20 % 50 → fault บัส 9 ที่ 85 เคลียร์ 85.15 → line 6-13 trip 110 → restore/reclose 145 → 250 s` |
| driver | `scripts/examples/run_ieee14_eecon49_chronology.m` |
| runner ที่ผลิต cache ที่รายงานใช้ | `scripts/reporting/run_ieee14_gfm_lock_comparison.m` |
| cache | `output/diagnostics/ieee14_gfm_lock_compare_zeta/adaptive_250s.mat` |
| รูปในรายงาน | `docs/source/figures/switch_ieee14_decision/` — `electrical_adaptive.png` (8 แผง a–h), `mode_switch_PQ.png`, `decision_indices*.png` |
| generator รูป | `generate_ieee14_switch_evidence.m`, `generate_ieee14_mode_pq_figure.m` |
| ผลที่เผยแพร่ | reclose SUCCESS 159.252 s, 3679 samples, 161 rejected steps, max accepted KCL residual 9.9721e-09, terminal f_COI 60.000001 Hz |

**สำคัญ:** chronology นี้รันโดย**ไม่มี** `anti_windup_blend` และยังคงเป็นเช่นนั้น
ตัวเลข 6 ค่าข้างบนถูกใช้เป็น regression gate — ยืนยันแล้ว (2026-09-04) ว่าโค้ดที่แก้ใหม่
ไม่ทำให้ค่าใดเปลี่ยน

---

## ชุด B — scenario suite 4 อันที่เพิ่มใหม่

ตอบฟีดแบคว่าต้องเห็น framework ในสถานการณ์อื่น ไม่ใช่ chronology เดียว

| runner | `scripts/reporting/run_ieee14_scenario_suite.m` |
|---|---|
| generator รูป | `scripts/reporting/generate_ieee14_scenario_suite_figures.m` |
| cache | `output/diagnostics/ieee14_scenario_suite/<id>.mat` + `summary.mat` + `provenance.txt` |
| รูป | `docs/source/figures/ieee14_scenario_suite/<id>_{pq,fv,mode}.png` + `.fig` (3 แผ่นต่อ scenario) |
| horizon | 150 s ทุกอัน |
| option ที่ต่างจาก chronology | `anti_windup_blend = 1e-3` (ประกาศไว้ชัดเจนใน `base_request`) |

ทั้ง 4 อันแชร์ case เดียว dispatch เดียว solver เดียว step controller เดียว
**ต่างกันแค่ลำดับเหตุการณ์** และ `assert_only_declared_differences` บังคับให้
ความต่างที่ไม่ได้ประกาศทำให้ run ตายทันที

**ทุกอันมี SG reclose** ตามที่เจ้าของโปรเจคสั่ง (2026-09-04) — reclose SUCCESS ครบ 4 อัน

### 1. `sg_load_step30`
- ลำดับ: `sg_trip 20 → load +30 % ที่ 50 → sg_on 80`
- คำถาม: เกาะรับโหลด +30 % (หนักกว่า chronology 1.5 เท่า) ได้ไหม แล้ว SG กลับเข้ามาใต้โหลดหนักได้ไหม
- ผล: ถึง 150 s, reclose SUCCESS 81.15 s, `load_step` EXECUTED, GFM 4 ตัวตอนจบ, support commit 3 ครั้ง 0 ปฏิเสธ

### 2. `sg_fault_bus9`
- ลำดับ: `sg_trip 20 → fault บัส 9 ที่ 50 เคลียร์ 50.15 → sg_on 80`
- คำถาม: เกาะ ride through ฟอลต์แบบ bolted ได้ไหม แล้วผ่านเกต synchronism หลังจากนั้นไหม
- ฟอลต์เดียวกับ chronology (บัสเดียวกัน Zf เดียวกัน) ต่างที่มาถึงตอนเกาะยังใหม่และมี former น้อยกว่า
- ผล: ถึง 150 s, reclose SUCCESS 81.8627 s, `fault_clear` EXECUTED, GFM 0 ตัวตอนจบ (hand back ครบ) สูงสุด 2 ตัว

### 3. `line_fault_9_14`
- ลำดับ: `sg_trip 20 → fault ที่ 50 → line_fault_clear 50.15 (เบรกเกอร์สองปลายเปิด สายกับฟอลต์ออกพร้อมกัน) → sg_on 90` — **สายไม่กลับมา**
- คำถาม: รีเลย์เคลียร์ฟอลต์ด้วยการตัดสายทิ้งถาวร ระบบปรับตัวไหม แล้ว GFM กลับเป็น GFL ได้ไหมบนเครือข่ายที่พิการ
- เลือกสาย 9-14 เพราะเป็นสายส่งจริง (4-9 กับ 7-9 เป็นหม้อแปลง) และปลดแล้วไม่มีบัสหลุดเกาะ
- **ข้อจำกัดที่ต้องระบุ:** เป็นฟอลต์**ระยะศูนย์** (close-in) ไม่ใช่ฟอลต์กลางสาย — โค้ดไม่มีโมเดลฟอลต์กลางสาย เพราะต้องแบ่งอิมพีแดนซ์ด้วยโนดช่วย ซึ่งจะเปลี่ยน `mpc` และทำให้ selector fingerprint เปลี่ยน เทียบกับ chronology ไม่ได้
- ผล: ถึง 150 s, reclose SUCCESS 92.4126 s, `line_fault_clear` EXECUTED, GFM 0 ตัวตอนจบ สูงสุด 2 ตัว

### 4. `former_outage`
- ลำดับ: `sg_trip 20 → ibr_trip 60` เป้าหมาย = `reference_owner` (ตีความตอนรัน ไม่ pin index) `→ sg_on 90`
- คำถาม 2 ข้อต่อกัน: (1) ตัวที่ถือ angle reference ตาย → framework เลื่อนตัวรอดขึ้นมาได้ไหม
  หรือปฏิเสธแบบ fail-closed (2) แล้ว SG กลับเข้ามาบนเกาะที่**เสีย converter ไปถาวร**ได้ไหม
- เป็นความสามารถใหม่: `ibr_trip` event + `select_post_outage_candidate` + `ibr_trip_transaction`
- ผล: ถึง 150 s (2815 samples), `ibr_trip` EXECUTED ที่ t=60.000 — IBR2 ออกจากระบบ
  และเพราะมันถือ reference จึง commit `selected=3 reference=3` ในธุรกรรมเดียวกัน,
  **reclose SUCCESS 90.3374 s**, **owner กลับเป็น SG ตอนจบ**,
  GFM สูงสุด 2 ตัว, **support commit 2 ครั้ง 0 ปฏิเสธ**
- **ไม่มีกลไก reclose IBR** — converter ที่ปลดแล้วปลดเลยจนจบ run เครื่องจักรกลับมา
  แต่ converter ไม่กลับ ถ้าต้องการ IBR กลับเข้ามาต้องทำ synchroniser สำหรับ IBR ซึ่งเป็นงานอีกก้อน
- **เดิมไม่มี `sg_on`** (2026-09-04 เช้า) โดยตั้งใจว่าจะถามแค่เรื่องการกู้ reference
  เจ้าของโปรเจคสั่งให้ทุก scenario ต้องมี SG reclose จึงเพิ่ม `sg_on = 90`
  ต้องแก้ capability row (`sg_reclose`, `sync_controller` เป็น true) + กฎลำดับ
  (`sg_trip < ibr_trip < sg_on`) ใน `+stability/ibr_event_schedule.m` แล้วรันใหม่
  (403.3 s) — cache เดิมใช้ไม่ได้เพราะ `opt_signature` เห็น event struct ที่เปลี่ยน

#### ข้อบกพร่องที่เจอและแก้แล้วใน scenario นี้ (2026-09-04)

รอบแรก scenario นี้ **ประกาศ converter ที่ตายไปแล้วเป็น angle-reference owner**
วัดได้ชัด: ที่ t=60 owner ย้ายไป 3 ถูกต้อง แต่ที่ t=64.037 มี commit
`selected=[2 3 4 5] ref=2` fingerprint `sg_off_agsi_augment|...|version=6`
แล้ว owner กลับไปเป็น 2 = IBR2 = **ตัวที่เพิ่ง trip** และค้างอยู่อย่างนั้นอีก ~86 s

สาเหตุ 2 ชั้น แก้ทั้งสองชั้น:
1. `+stability/select_support_augmentation_candidate.m` ไม่เคยได้รับ service state
   จึงเลือกจากตาราง static ได้ทุกแถว — และ `[2 3 4 5]` เป็น **superset เดียว**
   ของ `[3 4]` ที่ feasible (`[3 4 5]` infeasible: `mixed_equilibrium_solve:noConverge`
   residual 3.346e+02) ตอนนี้รับ `online_ibr` เพิ่ม แล้วข้ามแถวที่ selected
   หรือ reference มีอุปกรณ์ที่ออฟไลน์
2. `sg_off_support_transaction` เพิ่ม guard ปฏิเสธการ publish ownership
   ที่ชี้ไปอุปกรณ์ออฟไลน์ (fail-closed ชั้นที่สอง)

หลังแก้: commit ที่ t=64.037 ไม่เกิดขึ้นอีก, 0 ปฏิเสธ
(selector คืน `found=false` จึงไม่มีการพยายาม transaction เลย), เกาะเดินด้วย
former 2 ตัวจนถึง SG reclose — **ไม่มีการผ่อนเกตใดๆ** คำตอบที่ซื่อสัตย์คือ
ไม่มี survivor-only superset ของ `[3 4]` ในตารางที่ authenticate ไว้

**cache อีก 3 อันไม่ต้องรันใหม่** — ตรวจแล้ว (`tmp/mt/probe_cache_validity.m`):
predicate ใหม่ "reference ต้องเป็นสมาชิกของ selected" ไม่ตัดแถวที่เคยผ่านออกแม้แถวเดียว
(ทั้ง 6 แถวที่ `feasible && ready_to_commit` มี ref อยู่ใน selected อยู่แล้ว) และ
อีก 3 scenario ไม่มีอุปกรณ์ตัวใด trip เลย guard ทั้งสองจึงไม่มีผล

---

## รูปของ suite — 3 แผ่นต่อ scenario แผ่นละ 2 แผง

เจ้าของโปรเจคกำหนด (2026-09-04) ว่ารูปสำหรับสไลด์ต้องมี **P, Q, F, V**
และกราฟ **สลับโหมด GFL/GFM แบบ 0–1** สไตล์ latex / ไม่มีกรอบ / กริดเส้นประ
เซฟทั้ง `.png` และ `.fig` แล้วสั่งเพิ่มว่า **scenario ละ 3 รูป รูปละ 2 แผง**

จัดกลุ่มตาม**คำถามที่แผ่นนั้นตอบ** ไม่ใช่ตามจำนวนช่องที่ว่าง — 1 แผ่น = 1 สไลด์ = 1 เรื่อง

| ไฟล์ | แผง (a) | แผง (b) | ตอบอะไร |
|---|---|---|---|
| `<id>_pq.png` | `P` ต่อ converter [p.u.] | `Q` ต่อ converter [p.u.] | converter จ่ายอะไรออกไป |
| `<id>_fv.png` | `f_COI` [Hz] + ขอบแถบ `J_f = 1` | `\|V_i\|` ต่อบัส converter + healthy level และขอบแถบ `J_V = 1` ของแต่ละตัว | สัญญาณ 2 ตัวที่ index สร้างจาก |
| `<id>_mode.png` | โหมด GFL/GFM 0–1 | angle-reference owner (บันไดครบ SG + ทุก converter) | framework ตัดสินใจอะไร |

**2 แผงเรียงบน-ล่าง ไม่ใช่ซ้าย-ขวา** — ทั้งสองแผงใช้แกนเวลาเดียวกัน วางบนล่างแล้ว
เวลาเดียวกันอยู่ตำแหน่งแนวนอนเดียวกัน ลากเส้นตั้งด้วยตาผ่านทั้งสองแผงได้
ถ้าวางซ้าย-ขวา แกนจะกว้างครึ่งเดียวและช่วง 150 s จะอ่านไม่ออกบนขนาดสไลด์

**แผ่น `_fv` คือสัญญาณที่ index ใช้คิดจริง ไม่ใช่ f กับ v ที่ดูเข้าเค้า**
supervisor กิน `S = min(1, max(0, 0.5·J_V + 0.5·J_f))` โดย
`J_V = |V_i − V_healthy(บัส i)| / dV_base` (`dV_base = 0.10` p.u.) และ
`J_f = |f_COI − f0| / df_base` (`df_base = 0.50` Hz) —
base ถูกตรึงที่ `+stability/ts_simulate_ibr_hybrid.m:1675-1677`
สูตรอยู่ที่ `+stability/agsi_reference_terms.m:186-190` ผลที่ตามมา 2 ข้อ:

- **f เป็นเส้นเดียวของระบบ** (centre-of-inertia) **ไม่ใช่ 4 เส้นต่อ converter** —
  `J_f` เท่ากันทุก converter โดยโครงสร้าง วัดได้ spread ข้าม converter = 0.000e+00
  บน 933 sample ที่ทั้ง 4 ตัวออนไลน์ ถ้าวาด 4 เส้นจะเป็นการวาดปริมาณที่ index ไม่ได้สร้าง
  วาดด้วย**สีม่วง ไม่ใช่สีของ converter** เพราะพาเลต converter จบที่สีดำ ถ้าใช้สีเกือบดำ
  ข้างๆ legend ที่บอกว่า IBR8 เป็นสีดำ จะอ่านว่า "นี่คือความถี่ของ IBR8"
  ซึ่งเป็นการเข้าใจผิดที่แผงนี้มีไว้เพื่อป้องกัน — ม่วงเป็นสีเดียวกับ owner บนแผ่น `_mode`
  จึงได้ระเบียบเดียวกันทั้งชุด: พาเลต converter = ปริมาณต่อตัว, ม่วง = ปริมาณของระบบ
- **V เทียบ healthy level ของบัสตัวเอง ไม่ใช่เทียบ 1.0 p.u.** —
  `J_V` เป็น deviation จาก power-flow reference ของบัสนั้น
  (`healthy_pf_V` อยู่ใน `opt_signature` ของ cache)

**generator พิสูจน์ตัวเองทุก scenario** ไม่ได้เชื่อจาก probe ครั้งเดียว:
เอา `f_COI` กับ `|V|` ที่จะวาด มาคำนวณ `J_V`, `J_f`, `S` ใหม่ด้วย base ที่ตรึงไว้
แล้วเทียบกับค่าที่ run ตัวนั้น publish เอง ถ้าไม่ตรงเกิน `1e-9` จะ **error ไม่วาด**
วัดได้ `max|J_V − published| = 0`, `max|J_f − published| = 0`, `max|S − published| = 0`
ครบทั้ง 4 arm (7604–11384 sample ที่มีการประเมินต่อ arm)
และ `dV_base` ที่ถอดกลับจาก `J_V` ที่ publish ได้ = 0.100000000 spread 1.4e-17

**สิ่งที่ generator ไม่ยอมวาดให้ดูดีกว่าความจริง:**
- **เส้นโหมดถูก mask เป็น NaN ตอน converter ออฟไลน์** — `device_modes_history`
  เก็บ `'tripped'` และ `mode_gfm` เช็คแค่ `'gfm'` ดังนั้นตัวที่ trip จะได้ค่า false
  ซึ่งบนแกน 0–1 คือระดับ GFL — บน `former_outage` คือ 1882 sample
  ที่จะถูกวาดเป็น "IBR2 กำลัง follow กริด" ทั้งที่มันไม่อยู่แล้ว จึงเว้นเป็นช่องว่าง
- **P, Q, |V| ไม่ mask** — ตัวที่ trip ฉีดกระแส 0 จริง ศูนย์นั้นเป็นค่าที่วัดได้
  และบัสของมันยังมีไฟจากเกาะที่เหลือ `|V|` ที่นั่นจึงยังเป็นการวัดเครือข่าย
- **เส้นโหมดไม่มี offset** — ที่หลายตัวโหมดเดียวกันเส้นทับกัน ความทับนั้น**คือข้อเท็จจริง**
  (เปลี่ยนโหมดพร้อมกัน) การเลื่อนจะเป็นการสร้างความต่างที่ไม่มีอยู่
  แยกด้วย line style แทน — รูปแบบเดียวกับ `generate_ieee14_mode_pq_figure.m:24-26`
- **แกน x กว้างเท่า horizon ที่ขอ** ไม่ crop ตามข้อมูล ถ้า run หยุดก่อนจะมีเส้นแดงกำกับ
- **แกน y บน arm ที่มีฟอลต์ คิดจากช่วงปฏิบัติการ** (run ลบหน้าต่างฟอลต์ + 50 ms)
  แล้วค่าที่หลุดกรอบถูก**กำกับที่ขอบด้วยค่ายอด** วัดได้บน `sg_fault_bus9`:
  `|V|` กว้าง [0.258 1.864] p.u. ทั้ง run แต่ [0.551 1.138] p.u. นอกหน้าต่างฟอลต์ —
  กว้างกว่า 2.74 เท่าเพื่อ sample 5 % และ `P` กว้างกว่า 2.72 เท่า
  ยอด 1.86 p.u. คือ right-limit burst 12 sample ของธุรกรรม fault-clear
  กลับเข้าใต้ 1.15 p.u. ภายใน 1.1 ms ถ้าให้มันกำหนดแกน แถบ `J_V = 1` ที่แผงนี้มีไว้เพื่อ
  จะเหลือไม่กี่เปอร์เซ็นต์ของแผง — **ไม่มี sample ใดถูกทิ้ง กรอง หรือ clip**
  ทุก sample ยังวาดอยู่ และทุกค่าที่หลุดกรอบถูกลิสต์ใน `provenance.txt`
  arm ที่ไม่มีฟอลต์ไม่ตัดอะไรเลย (วัดได้อัตราส่วน 1.00 เท่าพอดี)

**เรื่องฟอนต์:** เจ้าของสั่ง "latex" และสั่งให้ใช้ฟอนต์เดียวกับสไลด์
สองข้อนี้ขัดกันใน MATLAB — interpreter `latex` เรนเดอร์ผ่าน Computer Modern
ไม่ว่าจะตั้ง `FontName` อะไร จึงไม่สามารถให้ Helvetica ของสไลด์
(`presentation_pf_sssa_ts_gfm_en_v11.tex:3`) ได้เลย
เลือก **`tex` interpreter + Helvetica** ซึ่งให้ทั้งฟอนต์ของสไลด์และหน้าตาแบบ LaTeX
(math italic, กรีกจริง, subscript) ครบ — ตรงกับ contract ที่บันทึกไว้เดิม
ถ้าต้องการ Computer Modern จริงๆ ต้องยอมให้ฟอนต์ต่างจาก body ของสไลด์

`S` เองไม่อยู่บนแผ่นไหนเลย — แผ่น `_fv` มีวัตถุดิบทั้งสองของมัน วาดในหน่วยจริง
พร้อมขอบแถบ อ่านแล้วตรวจกับการวัดได้ ส่วน `S` ยังอยู่บน slide 14 ของ deck
และบนหน้า decision ของรายงาน

---

## รูปวินิจฉัยอัตโนมัติ — ไม่ใช่ deliverable

`output/plots/` มีรูปชื่อ `SG TS angle`, `IBR TS power`, `<case>_ibr_frequency_speed.png`
ฯลฯ สร้างโดย `+stability/plot_ibr_ts_results.m` ซึ่งถูกเรียกอัตโนมัติจาก
`+wizard/dispatch_analysis.m:315` ทุกครั้งที่รัน analysis (และจาก test บางตัว)

- **ไม่มีโค้ดใดอ่านรูปพวกนี้กลับ** — ตรวจแล้ว ไม่มี `imread`/`openfig`/`load` จากโฟลเดอร์นั้น
- ชื่อไฟล์ซ้ำกันทุกรอบ จึงถูกเขียนทับ — รูปที่เห็นคือรอบล่าสุดของ case ใดก็ตามที่รันไป **ไม่ใช่ cache เก่าค้าง**
- ปิดได้ด้วย `plot_results=false` ตอนรัน
- **รูปที่รายงานใช้อยู่ใน `docs/source/figures/` เท่านั้น** และมี `provenance.txt` กำกับทุกโฟลเดอร์

---

## เกตที่ทุกชุดต้องผ่าน (ไม่เคยผ่อน)

`newton_tol = 1e-8` · `kcl_tol = 1e-6` · Richardson LTE test ·
`dt_min = 0.05/2^13 = 6.10352e-06` · `reject_limit = 20`

`anti_windup_blend` เป็นการเปลี่ยน**โมเดล** (regularize สวิตช์ anti-windup ให้
engage ต่อเนื่องบนแถบกว้าง 0.1 % ของ `Imax` แทนที่จะกระโดด) ไม่ใช่การผ่อนเกต
default เป็น 0 ซึ่งให้สาขาเดิมทุกบิต รายละเอียดและหลักฐานอยู่ใน
`docs/project/defects/2026-09-04-limiter-antiwindup-sliding-mode.md`

---

## วิธีรัน

```matlab
pf_init_paths;

% chronology ที่ส่งมอบ (regression)
run_ieee14_eecon49_chronology('t_end',250)

% suite 4 อัน
out = run_ieee14_scenario_suite(t_end=150);

% รูปของ suite (PNG + .fig + provenance)
generate_ieee14_scenario_suite_figures();
```

`run_ieee14_scenario_suite` ใช้ `reuse_completed=true` เป็น default และ
`opt_signature()` จะปฏิเสธ cache ที่ option เปลี่ยนไป — ถ้าเปลี่ยน option แล้ว
cache เก่าจะถูกทิ้งและรันใหม่เอง ไม่ต้องลบด้วยมือ

**ข้อควรระวัง:** `opt_signature()` เห็นแค่ **option** ไม่เห็นการเปลี่ยน **logic**
ถ้าแก้โค้ด selector หรือ transaction แล้วอยากยืนยันผล ต้องสั่ง
`reuse_completed=false` เองมิฉะนั้นจะได้ cache เดิมกลับมาแล้วเข้าใจผิดว่าผ่าน

---

## โมเดลที่ยังดูแลอยู่ และที่เลิกดูแลแล้ว

เจ้าของโปรเจคตัดสินใจ (2026-09-04) ว่า **สนใจเฉพาะ `eecon49_dual`** เพราะเป็นตัวที่
รายงานและสไลด์ใช้ และเป็นตัวที่ถูกต้องกว่า ตระกูลเก่าไม่ได้รับการแก้ไขต่อ:

| ตระกูล | สร้างจาก | สถานะ |
|---|---|---|
| `eecon49_dual` | `case_profile='eecon49_figure4'` | **ใช้งานจริง** 16 สเตต + DC-source เป็นสเตตที่ 17 |
| `regfm_b1_dual` | `scenario_ieee14_1sg_4ibr()` ไม่ใส่ `case_profile` (default `mission`) | เลิกดูแล |
| `decoupled_dual` | `case_profile='decoupled_figure4'` | เลิกดูแล 17 สเตต DC source เป็นแบบ algebraic โดยเจตนา (`GATE-2026-08-25-02`) |
| EMF6 standalone oracle | `stability.synchronous_emf6_ssa` | พังมาก่อนหน้านี้ `TEST-2026-08-13-04` (OPEN) residual 4.485e-01 |

เหตุผล: ตระกูลเก่าเกิดก่อนการแก้ที่ทำเฉพาะบน production path — DC-link closure
(`NUM-2026-08-20-01`) และเกต damping ratio (`GATE-2026-08-25-01`) — ดังนั้น test
ที่แดงในตระกูลเก่ามักเป็น test ที่บรรยายโมเดลที่ไม่มีใครใช้อย่างซื่อสัตย์
ไม่ใช่ข้อบกพร่องที่ควรตาม

เวลา `runtests('tests')` แดง ให้ดูก่อนว่าไฟล์นั้นสร้างโมเดลตระกูลไหน ถ้าเป็นตระกูลเก่า
ให้บันทึกไว้แล้วข้าม — ห้าม revert งาน production เพื่อให้มันเขียว และห้ามลบ assertion
ของมันด้วย

