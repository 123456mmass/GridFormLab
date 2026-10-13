# แผนทำต่อ NE39: certified mode restoration และ operating-point recovery

วันที่: 2026-10-12
สถานะ: **PLAN ONLY — ยังไม่อนุมัติ implementation หรือ simulation**
รอบนี้ตรวจโค้ด/หลักฐานที่อ่านได้และแก้เอกสารเท่านั้น ไม่แก้ source ไม่เริ่ม MATLAB ไม่ commit/push

## 1. เป้าหมาย

NE39 ประกอบด้วย SG31 + 9 IBR; normal ก่อน 20 s, SG trip 20 s, fault bus 16 `Zf=j0.1` ที่ 60–60.15 s, return request 100 s, horizon 160 s. เวลา close จริงเป็นผลของ guard/dwell ไม่บังคับให้เท่ากับ request หรือผล IEEE14

- เป้าหมายเจ้าของโครงการ: **คืน GFL ให้มากที่สุด เหลือ GFM เท่าที่จำเป็นให้น้อยที่สุด และกลับเข้าสมดุลจริง** ภายใต้ safety/certification/recovery gates ไม่ใช่หยุดที่ mixed set แรกที่ผ่าน
- Initial/final mode mix ต้องเลือกจากหลักฐานและมี certification ใน context จริง **ไม่บังคับ all-nine GFL หรือเส้นทาง 9→0**; การอ้าง minimum GFM ต้องมี evaluated alternatives/ขอบเขตการค้นหา ไม่อ้าง global minimum จาก bounded search
- Routine adaptation เป็น bounded/per-device; SG-trip formation/reference rescue อาจเปลี่ยน certified subset พร้อมกันเมื่อมีเหตุผล ไม่ใช่ auto-all-nine
- Residual GFM ยอมรับเฉพาะมี evaluated/certified justification และ recovery evidence ไม่ใช่คงไว้เพราะไม่มี coverage
- All-nine GFM ที่ค้างเพราะ restoration coverage/implementation ขาด ไม่ใช่ความสำเร็จ
- Reclose SUCCESS, ชื่อโหมด หรือ `converged` ไม่แทน physical safety/equilibrium evidence

## 2. Baseline และระดับหลักฐาน

ตรวจ checkout เดิมโดยตรง: `checkpoint/ne39-160s-20261009` @ `f79bead`.
WIP ที่ต้องรักษา: kernel `27 insertions / 1 deletion`, probe `33 / 1`.
Fingerprint ของ `git diff` สองไฟล์คือ `62f1a21054a2e0e1d249ea4516427d82bb9a55a6` — git blob hash ของ diff ไม่ใช่ raw evidence checksum.

[โฟลเดอร์หลักฐานเดิม](../output/diagnostics/ne39_reclose_applied_probe_20261012_024613_920/):

| ระดับ | ข้อเท็จจริง/ข้อจำกัด |
|---|---|
| Artifact-verified (filesystem/text) | raw 1,850,924,388 B; cache 549,979 B; request 2,012,152 B; audit 171,520 B. progress.log บันทึก trip/fault/clear/request/reclose; reclose 119.5200 s; progress สุดท้าย 155.1355 s |
| Owner-reported | horizon160; close119.520000610; right KCL4.845e-10; 31,448 accepted samples; rejected steps7; final9GFM/no GFL return; แต่ละ8GFM target มี0 matching rows; cache load~0.03 s |
| Unverified ในรอบนี้ | ข้อมูลภายใน MAT, per-bus voltage/final recovery และเวลาการโหลดจริง: Python ที่มีอยู่ไม่มี h5py/scipy ไม่ติดตั้งเพิ่มหรือเปิด MATLAB |

progress `rejects=0` ไม่ยืนยันยอดสุดท้าย และ progress ที่จบ155.1355 ไม่ยืนยัน horizon160. แคชเป็น replay ไม่ใช่ certificate ใหม่.

Historical regression ที่เจ้าของให้: scoped30 Passed/0 Failed/0 Incomplete; handback9 Passed; IEEE14 **20 total,14 Passed,6 Failed,1 Incomplete flag**; combined29 **23 Passed,6 Failed,1 Incomplete flag**. Failed/Incomplete อาจซ้อนกัน ห้ามบวกเป็น21/30. ยังไม่มี per-name baseline ของหก failures จึงไม่อ้าง no-regression. Function counts ที่ตรวจไม่ใช่ผลรัน: plant14, wiring13, dynamicSSSA3; handback2+2+5; workflow20.

## 3. Findings จาก source จริง

| จุด | ข้อเท็จจริง | ผลต่อแผน |
|---|---|---|
| `online_ibr_severity`, kernel3895–3969 | SI=clip(.5Jv+.5Jf), frequency COI | Rate gates/prediction มีแล้ว แต่ weighted four-term SI ยังไม่มี |
| kernel1322–1327 + ratepolicy74 | per-GFM release eligibility ถูกทับด้วย `release=current_gfm`; policy down ใช้ all(SI<off) | Opt-in ต้องแยก per-device SI/dwell จาก global hard-safe/prediction dwell |
| kernel253–276, settings1820–1853 | landing ใช้ severity dwell แต่ policy override dwell/threshold ได้แยก | Resolve thresholds และ clocks เดียวกัน ไม่เลือก conflict เงียบ |
| kernel4483–4539 | caller ใช้ EtFcsRateAccumulator/device frequency, reset epoch/duplicate | ทดสอบ caller จริง ไม่ใช่ standalone policy เท่านั้น; midpointไม่บันทึก rates จึงห้าม zipกับres.t |
| probe95–112 | SG_ON pin9, budget4, stop-first | Missing8target rows ไม่ใช่ evaluated instability; ถอดpinอย่างเดียวไม่พอ |
| kernel2963 onward/1438/3830–3836 | helper authenticate c_auth แต่ไม่ส่ง candidate เต็มเข้า transaction; study guard ปฏิเสธหลัง KCL | ต้องส่ง authenticated candidate/context/input และ destination SG_ON private trial ก่อน publish ไม่ลบ guard |
| SG_OFF rankers/kernel3373 onward | Strict superset/subset เดิมไม่จำกัด delta1 | เพิ่ม bounded routine แบบ opt-in รักษา legacy unbounded |
| runner503–518/lazy903 onward | cacheไม่forward; outputfp/inputstate_validity_fingerprint ต่าง schema | ต้องมี adapter/roundtrip/invalidation tests ไม่ใช่แค่forward |
| demo53–55/256–259 | loadinfoไม่ตรวจSHAตามcomment; fallback cell-valued structอาจขยายarray | แก้/ทดสอบภายหลังทั้ง cache/fallback ไม่อ้าง checksum verified |

SG seven-state `[P_ref,Emag_ref]` เป็น commands ไม่ใช่ actual Pm/Emag หรือ EMF6 Tm/Efd. รักษา initializer/handback capability guard และไม่สร้าง governor ซ้ำ.

## 4. ลำดับงานหลังอนุมัติ implementation แยกต่างหาก

| ขั้น/Owner | งาน | Acceptance | Stop gate |
|---|---|---|---|
| 0 Lead + study owner | Freeze study design, target/reference provenance, ranking, budgets; recovery tolerances/window ต้องอนุมัติก่อน outcomes ใหม่ | Contractชัด/ค่าที่ยังไม่อนุมัติระบุpending | ไม่สร้างvalidated tolerancesเอง |
| **1 Supervisor owner** | **Weighted supervisor real gates + controlled decision tests เป็น slice แรก ก่อน coverage discovery**; helper/options/forwarding/canonicalSI, resolved thresholds/clocks, perdevice eligibility, caller reset, legacy regression | Rate-only tests release true→hold หลังdwell; SI .245→.365/.28→.37; nohard/predtrigger | Logging-only/helper-onlyไม่ผ่าน; ไม่รอ physical9→8 commit เพื่อพิสูจน์ decision |
| 2 Coverage owner | Bounded candidate/node discovery และ reachable permitted mode path ไป appropriate endpoint; แยกmissing/budget/path/infeasible/inconclusive | Certifiednodes + valid reachableedges; evaluated residual justification | ไม่มีrow/pathไม่รัน160 และไม่สรุปunstable |
| 3 Transition owner | Authenticate fullcandidate/context/input; mapped private right-state/KCL; SG_ON destination trialก่อนpublish; bounded routine deltaและlegacy tests | Success/rejection fixtures; failedtrialไม่publish; spectrum/energy/slip/ref guards | ไม่ลบguard/fakeflags/truncate required trial |
| 4 QA + integration owner | Short fixturesมีeventsจริงภายในhorizon; per-name regression baseline; freeze recovery contractครบ | Applied transitions+rightKCL+DC/current และ expected refusal | Eventsนอกhorizon/unknown baselineไม่ผ่าน |
| 5 Run owner | Full160s chronologyเฉพาะpreflightผ่าน | Timeline/mix/transactions/recoveryครบ; reject/samplecountsจากresult | เก็บfailureตามจริง ไม่ขยายhorizonเงียบ |
| 6 Evidence owner + Lead | Raw/request/audit + replay provenance/schema, both-path roundtrip/staleness tests, report | Cacheตรงartifact ไม่อ้างlive/certification; Leadตรวจdiff/evidence | MAT/metricที่ยังไม่อ่านไม่claimverified |

Kernel/runner ที่ร่วมกันมี single writer ต่อไฟล์และทำตาม dependency ไม่แก้พร้อมกันหลาย owner. เอกสาร scope แยกได้ แต่ numerical code รอบนี้ไม่อนุญาต.

## 5. Recovery acceptance ที่ยังต้องอนุมัติ

Freeze numeric tolerances/หน่วย/settling window **ก่อนดู outcomes ใหม่** สำหรับ P/Q/V/f, per-device rates, physical state derivatives พร้อม gauge treatment, full KCL, current/MVA, cumulative DC energy, SG Psv/Pm/field/source bounds และ dispatch/reference provenance.

- ไม่ตัดทุก angle stateทิ้ง: quotient/removeเฉพาะ common rotating gauge ที่มีหลักฐาน และตรวจrelative dynamics
- P/Qต่างจากtargetพร้อมคำอธิบายไม่ใช่PASS เว้นเปลี่ยนtarget/acceptance prospectively แล้ว
- Strict voltage failuresต้องรายงานตามเดิม ห้าม retrospective10ms/+M1 waiver เพื่อทำrunเก่าผ่าน
- Observe-voltage study completionไม่เท่ากับstrict certificate; production/hardware certificationไม่ถูกอ้าง

## 6. แผนรายฝ่ายและขอบเขตส่งมอบ

- [Supervisor](ne39_supervisor_design_plan_20261012.md)
- [Selective coverage](ne39_selective_coverage_plan_20261012.md)
- [Independent QA](ne39_independent_qa_plan_20261012.md)

รอบนี้ส่งมอบ corrected plans/verified findings ไม่เริ่ม implementation, MATLAB, simulation, install, stage, commit/push หรือ cleanup worktrees. ไม่แตะ `docs/source/report_ieee14_all_gfm_constraints_{en,th}.{pdf,tex}`. การแก้ defect/success report นอกสี่แผนนี้และการเผยแพร่ต้องมีscopeอนุมัติของตัวเอง.
