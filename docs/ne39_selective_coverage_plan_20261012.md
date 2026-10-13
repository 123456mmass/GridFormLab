# แผน NE39: selective-mode / candidate-coverage (1 SG31 + 9 IBR)

วันที่จัดทำ: 2026-10-12
สถานะ: **PLAN ONLY — รอเจ้าของโครงการ review ก่อนเริ่มข้อใด ๆ**
เอกสารนี้ **ไม่แก้ source, ไม่รัน MATLAB/simulation, ไม่ commit/push** และไม่แตะ WIP ที่ค้างอยู่
Branch ที่ตรวจ: `checkpoint/ne39-160s-20261009` @ `f79bead`; รอบนี้อนุมัติแก้เฉพาะสี่แผน ไม่อนุมัติ numerical implementation/tests/simulation
เอกสารประกอบ [แผนรวม](ne39_gfl_restoration_continuation_plan_20261012.md), [Supervisor](ne39_supervisor_design_plan_20261012.md) และ [QA](ne39_independent_qa_plan_20261012.md); ขอบเขตฉบับนี้คือ selective-mode + candidate/endpoint coverage

---

## 0. สรุปผู้บริหาร (สิ่งที่แผนนี้เปลี่ยน)

1. **เป้าหมายคือคืน GFL มากที่สุด เหลือ GFM เท่าที่จำเป็นให้น้อยที่สุด และสมดุลจริง** — ไม่บังคับ all-nine GFL; mixed/residual ยอมรับเมื่อมี certificate + evaluated justification + recovery evidence. Bounded discoveryต้องรายงานalternatives/ขอบเขตที่ค้นหา ไม่อ้างglobalminimum
2. **coverage คือ node/edge path ไม่ใช่ count band** — การมี `counts=0:9` หรือมี CERTIFIED แถวแรก ไม่ใช่หลักฐานว่าเดินจาก 9 → 0 ได้
3. **ไม่มีการอ้าง all-9GFM success** เพราะ coverage ที่มีจริงยังไม่ครบ (ข้อ 3)
4. **Weighted supervisor ที่ใช้ gate จริง + controlled decision tests เป็น implementation slice แรก ก่อน coverage discovery** ไม่ใช่ logging-only และไม่ต้องรอ physical9→8 commit. Kernel/runner ที่ใช้ร่วมกันต้องมี single writer และ serializeตามdependency
5. **node certificate ≠ edge trial** — certificate ของ subset ไม่ได้ authenticate การเปลี่ยนโหมดเข้าหา subset นั้น
6. **terminal/residual status ต้องมีเหตุผลที่ประเมินแล้ว** ไม่ค้าง `PENDING` ไปเรื่อย ๆ และไม่ใช้ “ไม่มีแถว” แทน “พิสูจน์แล้วว่าเป็นไปไม่ได้”

---

## 1. เป้าหมาย timeline และเกณฑ์ปลายทาง

คง timeline เดิม (ไม่คัดลอกเวลาของ IEEE14 มาเป็นค่าบังคับ):

| เวลา | เหตุการณ์ | หลักฐาน |
|---|---|---|
| 0–20 s | SG31 online; IBR 9 ตัวใน operating point ปกติ | equilibrium + full KCL + dynamic SSSA + mode/dispatch/reference จริง |
| 20 s | SG31 trip จริง | committed event, transition mapping, KCL, reference owner |
| 60–60.15 s | fault shunt ที่ NE39 bus 16, `Zf=j0.1`, clear 60.15 | fault_on/fault_clear + traces |
| 100 s | SG31 return/reclose **request** (earliest request) | guard+dwell เท่านั้นที่ตัดสินเวลาจริง |
| หลัง reclose | SG31 รับ reference ของกริด | synchronism, right-limit KCL, continuity |
| หลังกริดฟื้น | supervisor คืนโหมด IBR ตามหลักฐาน | weighted severity+ROCOF+ROCOV, dwell, **certified one-step row**, applied transaction |
| 160 s | จบด้วย 1 SG online + IBR ที่ **mixed หรือ all-GFL ตามหลักฐาน** และใกล้ operating point เป้าหมาย | final modes, P/Q/V/f, rate/energy/current envelopes, equilibrium error |

**เกณฑ์ที่ถือว่าจบ (แก้จากแผนเดิม):**
- Final IBR set ต้องเป็น **certified endpoint** ที่มี recovery metrics ผ่านเกณฑ์ที่ประกาศล่วงหน้า
- **ไม่บังคับ** ว่า final ต้องเป็น 9 GFL; ถ้ามี residual GFM ต้องมี (ก) certificate ของ node นั้น (ข) หลักฐานการพยายาม release ตัวนั้น และ (ค) เหตุผลที่ประเมินแล้วว่าเหมาะสม (residual โดยเจตนา ไม่ใช่ค้างเพราะ coverage ขาด)
- ห้ามใช้ `reclose_status=SUCCESS` หรือชื่อโหมดแทนหลักฐานสมดุล (ตามแผนเดิม §1)

---

## 2. นิยามที่ต้องไม่ปนกัน (บังคับใช้ในทุก status ที่จะเพิ่มในภายหลัง)

| คำ | ความหมายที่ต้องแยก |
|---|---|
| **node certificate** | subset ของ GFM มี equilibrium/full-KCL/SSSA certificate ใน context นั้น |
| **edge trial** | forward trial ของการปล่อย/รับหนึ่งตัว (`certify_ne39_transition` / private trial) เป็นหลักฐานของ *การเปลี่ยน* ไม่ใช่ของ subset |
| **missing row** | ตารางไม่มีแถวที่ target ตรง (`choose_sg_online_one_step` พบ match ≠ 1) |
| **budget exhaustion** | ยังมี candidate ที่ไม่ถูก evaluate → HOLD/INCONCLUSIVE |
| **path not covered** | มี node แต่ไม่มี edge/บรรทัดที่ทำให้ walk ไปถึง endpoint ที่ประกาศ |
| **evaluated infeasibility** | ทุก candidate ถูก evaluate แล้วและ definitively infeasible → NO_FEASIBLE_CANDIDATE |

สี่อย่างหลังนี้ต้องปรากฏเป็น **status/reason คนละค่า** และห้ามยุบรวมเป็น `NO_FEASIBLE_SG_ON_ONE_STEP` เดียว (ปัจจุบัน runtime ยุบรวม — ดูข้อ 3.4)

---

## 3. ผลการตรวจ blocker (ยืนยันจากโค้ดจริงพร้อมเลขบรรทัด)

### 3.1 probe ปัจจุบันปิดทางเลือกด้วย configuration

[ne39_reclose_applied_probe.m:95-112](../scripts/diagnostics/ne39_reclose_applied_probe.m#L95-L112):

- `sg_on_n_gfm_required=9` (บรรทัด 98) → pin ตาราง SG_ON เป็น 9 GFM
- `budget.max_full_evaluations=4`, `stop_on_first_certified=true` (บรรทัด 97)
- `events.selected_gfm_indices=ibr` (บรรทัด 92-94) + `design_analysis.initial_modes` = all-GFM (บรรทัด 42-45)

ผลเดิมที่เจ้าของรายงาน: `reselection_status=NO_FEASIBLE_SG_ON_ONE_STEP`, reclose119.520000610 s, right KCL4.845e-10, horizon160, accepted31,448, rejected steps7
[หลักฐานเดิม](../output/diagnostics/ne39_reclose_applied_probe_20261012_024613_920/): รอบนี้ตรวจfilesystem/textได้ แต่ไม่ได้อ่านMAT; progressยืนยันreclose119.5200และจบ155.1355 ไม่ยืนยันhorizon160หรือยอดrejectสุดท้าย. ดูระดับหลักฐานในQAplan

**ยืนยัน:** ถอด pin เดียวไม่พอ — lazy selector หยุดได้ที่ certificate แรกหรือหมด budget ก่อนสร้างแถว release path

### 3.2 count pin และการสร้าง candidate แบบ lazy

- pin: [ibr_selector_search_lazy.m:252-269](../+stability/ibr_selector_search_lazy.m#L252-L269) — `pin.n_gfm_required` บังคับ `cmin=cmax`; ไม่ pin → SG_OFF `cmin=1`, SG_ON `cmin=0`
- initial-set priority ของ SG_ON: [ibr_selector_search_lazy.m:283-314](../+stability/ibr_selector_search_lazy.m#L283-L314) — evaluate committed initial set ก่อน แล้วจึงเดินตาม `stability.ibr_lazy_priority`
- ลำดับการสร้าง: [ibr_lazy_priority.m:24-43](../+stability/ibr_lazy_priority.m#L24-L43) — เรียงตาม count แล้ว lexicographic ภายใน count; ไม่ materialize 2^N
- budget/early stop: [ibr_selector_search_lazy.m:343-358](../+stability/ibr_selector_search_lazy.m#L343-L358)
- การ pin จาก runner: [run_hybrid_case.m:487-489](../+stability/run_hybrid_case.m#L487-L489)
- forwarding: [run_hybrid_case.m:513-517](../+stability/run_hybrid_case.m#L513-L517) ส่ง `certificate`, `budget`, `candidate_evaluator`, `state_validity`, `gamma_req`; [run_hybrid_case.m:528-530](../+stability/run_hybrid_case.m#L528-L530) บังคับ `require_physical_evidence=true`

### 3.3 certificate predicate (ทำไม “มีแถว” ไม่เท่ากับ “ครอบคลุม”)

`is_certified` [ibr_selector_search_lazy.m:490-545](../+stability/ibr_selector_search_lazy.m#L490-L545) ต้องมีพร้อม: trusted evaluator, `feasible`+`ready_to_commit`, topology/SCR/equilibrium/SSSA evaluated, `eq_rcond`/`gy_rcond`/`sssa_f0_norm`/`sssa_g0_norm` finite, `full_kcl`, `physical_kcl_norm<=1e-6`, eigenvalues + physical_eigenvalues ไม่ว่าง, FD 3 คู่ finite, `zeta_worst`/`margin` finite, และ evidence records ทุก applicable ต้อง PASS ([บรรทัด 547-590](../+stability/ibr_selector_search_lazy.m#L547-L590))

การจัดสถานะ fail-closed: [ibr_selector_search_lazy.m:454-481](../+stability/ibr_selector_search_lazy.m#L454-L481) — `HOLD` (budget หมด ยังมีของไม่ประเมิน), `INCONCLUSIVE` (มี UNKNOWN), `NO_FEASIBLE_CANDIDATE` (ทุกตัว definitively infeasible)
`is_definitively_infeasible`: [บรรทัด 592-613](../+stability/ibr_selector_search_lazy.m#L592-L613)

**สรุป:** ตัวแยก 3 สถานะนี้มีอยู่แล้วในระดับ selector — แต่ไม่ถูกส่งต่อไปถึง runtime reselection status

### 3.4 `choose_sg_online_one_step` คืน target/audit/ok ไม่ใช่ candidate เต็ม

signature จริง: [ts_simulate_ibr_hybrid.m:2963-2964](../+stability/ts_simulate_ibr_hybrid.m#L2963-L2964)
`[target_selected, audit, ok] = choose_sg_online_one_step(table, dae, sched, ec, Y, t, case_data, current_gfm, release_candidates)`

- สร้าง exact target = `setdiff(current_gfm,k_release,'stable')` ([บรรทัด 3019-3021](../+stability/ts_simulate_ibr_hybrid.m#L3019-L3021))
- หา row ที่ match และต้อง **unique** ([บรรทัด 3024-3041](../+stability/ts_simulate_ibr_hybrid.m#L3024-L3041)) → ถ้า ≠1 คือ “missing row/ambiguous”
- เรียก validator เป็น `manual_override` พร้อม `Ytopo = canonical_ybus_from_mpc(mpc)` ([บรรทัด 3042-3058](../+stability/ts_simulate_ibr_hybrid.m#L3042-L3058))
- เก็บ `c_auth` ไว้ใน `accepted_cells` **ภายในฟังก์ชัน** ([บรรทัด 3069-3101](../+stability/ts_simulate_ibr_hybrid.m#L3069-L3101)) แต่ **ส่งออกเฉพาะ `selected_gfm_indices`** ([บรรทัด 3138-3146](../+stability/ts_simulate_ibr_hybrid.m#L3138-L3146))
- ถ้า accepted ว่าง → `NO_FEASIBLE_SG_ON_ONE_STEP` + `noOneStepCandidate` ([บรรทัด 3102-3106](../+stability/ts_simulate_ibr_hybrid.m#L3102-L3106)) — **ยุบทุกสาเหตุเป็นค่านี้**; รายละเอียดอยู่ใน `audit.rejection_detail` ซึ่งเป็น diagnostic ไม่มี gate อ่าน ([บรรทัด 2973-2983](../+stability/ts_simulate_ibr_hybrid.m#L2973-L2983))

caller: [ts_simulate_ibr_hybrid.m:1357-1394](../+stability/ts_simulate_ibr_hybrid.m#L1357-L1394) — ส่ง `current_gfm`, `release`; ได้ `target_selected` แล้วประกอบ `target_modes = modes_from_selected(dae,target_selected)` ([บรรทัด 3842-3876](../+stability/ts_simulate_ibr_hybrid.m#L3842-L3876)) และ `authority='severity_sg_online_authenticated'`

**ช่องว่างที่ต้องปิดในแผน:** candidate ที่ authenticate แล้ว (มี `omega`, `physical_eigenvalues`, `eq_u_eq`, `eq_x0/eq_y0`, `modes`) ถูกทิ้งที่ขอบฟังก์ชัน → `reselection_transaction` จึงไม่มี spectrum ให้ trial

### 3.5 `reselection_transaction` ปฏิเสธด้วย transitionEvidenceMissing

signature: [ts_simulate_ibr_hybrid.m:3756-3758](../+stability/ts_simulate_ibr_hybrid.m#L3756-L3758)
guard: [บรรทัด 3830-3837](../+stability/ts_simulate_ibr_hybrid.m#L3830-L3837)

```matlab
if ok && isfield(case_data,'study_capability')
    ok=false;
    reason='NE39 reselection lacks an authenticated transition spectrum (transitionEvidenceMissing).';
```

คือ: หลัง right-limit KCL ผ่าน ถ้าเป็น NE39 study case **ยังไม่ publish** จนกว่าจะมี authenticated candidate/spectrum + trial evidence
ข้อบังคับเพิ่มสำหรับ SG_ON release: [บรรทัด 3782-3789](../+stability/ts_simulate_ibr_hybrid.m#L3782-L3789) ต้องเปลี่ยน GFM แค่หนึ่งตัว

### 3.6 API จริงของ private trial / certify (ห้ามประดิษฐ์ใหม่)

- `ne39_private_transition_trial(t,x,y,u,ec,Y,dae,case_data,candidate,opt,kcl_tol)` → `[ok,reason,audit]` — [ts_simulate_ibr_hybrid.m:3192-3253](../+stability/ts_simulate_ibr_hybrid.m#L3192-L3253)
  - ต้องมี `opt.resources` ([บรรทัด 3198-3204](../+stability/ts_simulate_ibr_hybrid.m#L3198-L3204)) และ `case_data.synchronism` ([บรรทัด 3205-3207](../+stability/ts_simulate_ibr_hybrid.m#L3205-L3207))
  - horizon มาจาก `omega` ของ candidate + dwell + rounding ตามคาบของ physical eigenvalues ([บรรทัด 3217-3229](../+stability/ts_simulate_ibr_hybrid.m#L3217-L3229))
  - ส่งต่อให้ `stability.certify_ne39_transition` ([บรรทัด 3243-3245](../+stability/ts_simulate_ibr_hybrid.m#L3243-L3245))
- `certify_ne39_transition(t,x,y,u,ec,Y,dae,resources,c,bounds,candidate,opt)` → `[ok,audit]` — [certify_ne39_transition.m:1-19](../+stability/certify_ne39_transition.m#L1-L19)
  - **precondition ของ candidate** ([บรรทัด 33-40](../+stability/certify_ne39_transition.m#L33-L40)): `ready_to_commit=true`, `feasible=true`, `omega` finite < 0
  - spectrum contract ([บรรทัด 47-61](../+stability/certify_ne39_transition.m#L47-L61)): ถ้ามี `physical_eigenvalues` ต้อง finite/nonempty/ทุก root `real<0` และ **`omega >= max(real(lam))`**; โค้ดปฏิเสธเมื่อ omega ต่ำกว่า spectral abscissa
  - PASS ต้องมี 2 passes + refinement coverage ครบ ([บรรทัด 85-107](../+stability/certify_ne39_transition.m#L85-L107)); `commit_authorized` **ยังเป็น false เสมอ** ([บรรทัด 22-25](../+stability/certify_ne39_transition.m#L22-L25)) — caller ตัดสิน
  - ต้องมี former ในทุก energized island ([บรรทัด 134-140](../+stability/certify_ne39_transition.m#L134-L140)) → all-GFL ที่ SG offline จะได้ `NO_VOLTAGE_FORMING_SOURCE`
  - synchronism: pairwise excursion ระหว่าง SG/GFM ที่ island เดียวกัน ([บรรทัด 246-256](../+stability/certify_ne39_transition.m#L246-L256)); former เดียว → ไม่มีคู่ให้ตรวจ
- caller ที่มีอยู่: trip [บรรทัด 2409-2423](../+stability/ts_simulate_ibr_hybrid.m#L2409-L2423); reference recovery [บรรทัด 2802-2813](../+stability/ts_simulate_ibr_hybrid.m#L2802-L2813); SG_OFF support [บรรทัด 3489-3502](../+stability/ts_simulate_ibr_hybrid.m#L3489-L3502) — จุดสุดท้ายส่ง `settings` เป็น `opt` และต้องมี `settings.resources` ([บรรทัด 1827](../+stability/ts_simulate_ibr_hybrid.m#L1827))

**SG_ON applicability:** certify ไม่รู้จัก SG_ON/SG_OFF; มันบังคับเงื่อนไข candidate + former-per-island เหมือนกันทุก context ดังนั้น reuse ได้ แต่ต้อง **(ก)** ส่ง candidate ที่ authenticate แล้ว **(ข)** ส่ง `ec` ของ right state ของ SG_ON **(ค)** ไม่ลบ guard ที่ 3830 และไม่ตั้ง `ready_to_commit` เอง

### 3.7 validator: input/context/current-state + trial

[validate_runtime_candidate_compatibility.m](../+stability/validate_runtime_candidate_compatibility.m)

- 3-layer fingerprint ด้วย live Y ([บรรทัด 181-198](../+stability/validate_runtime_candidate_compatibility.m#L181-L198))
- `manual_override`: exact unique match + canonical empty-shape ([บรรทัด 320-356](../+stability/validate_runtime_candidate_compatibility.m#L320-L356))
- hold/lockout revalidation ([บรรทัด 357-378](../+stability/validate_runtime_candidate_compatibility.m#L357-L378))
- **ไม่มี equilibrium/SSSA ในลูป TS** (predicates only) — หลักฐานกายภาพมาจาก certificate ที่ build time

### 3.8 support augmentation/release = set relation

- augmentation: minimal strict superset, `numel(selected) > numel(current_gfm)` + incumbent ⊆ selected ([select_support_augmentation_candidate.m:53-58](../+stability/select_support_augmentation_candidate.m#L53-L58)); ผู้สมัครต้องยัง online ([บรรทัด 59-74](../+stability/select_support_augmentation_candidate.m#L59-L74))
- release: strict **nonempty** subset ([select_support_release_candidate.m:36-43](../+stability/select_support_release_candidate.m#L36-L43)) → **อาจปล่อยหลายตัวใน transaction เดียว** เพราะตรวจเพียง strict subset ไม่จำกัด delta=1; SG_ON one-step เป็นคนละเส้นทางที่บังคับปล่อยหนึ่งตัว
- transaction บังคับ relation ซ้ำอีกชั้น: [ts_simulate_ibr_hybrid.m:3373-3383](../+stability/ts_simulate_ibr_hybrid.m#L3373-L3383)
- outage case ใช้ ranker คนละตัว (ไม่ใช่ strict superset/subset): [select_post_outage_candidate.m:83-96](../+stability/select_post_outage_candidate.m#L83-L96)

### 3.9 rate policy เป็น authority แยก

[ne39_rate_policy.m:60-88](../+stability/ne39_rate_policy.m#L60-L88): trigger = SI/ROCOF/ROCOV/prediction; release ต้องการ `all(s<si_off)` + safe band + no prediction + `off_dwell`; decision ออกเป็น proposal (`*_PENDING_CERTIFICATE`) ไม่ใช่ commit
ผูกกับ release: [ts_simulate_ibr_hybrid.m:1325-1327](../+stability/ts_simulate_ibr_hybrid.m#L1325-L1327) (`release=current_gfm` เมื่อ policy เปิด) และ [บรรทัด 977-980](../+stability/ts_simulate_ibr_hybrid.m#L977-L980)

### 3.10 WIP ที่ต้องไม่แตะ

working tree ยังมี (จาก `git status`): `+stability/ts_simulate_ibr_hybrid.m` และ `scripts/diagnostics/ne39_reclose_applied_probe.m` แก้ค้าง
diff ของ kernel คือ gate เดียวที่
`sync_ctl.handback_complete` → `(~sync_ctl.enabled || sync_ctl.handback_complete)` ที่ [บรรทัด 1354-1356](../+stability/ts_simulate_ibr_hybrid.m#L1354-L1356)
**ข้อกำหนด:** แผนนี้ไม่ revert/ไม่ stage/ไม่ overwrite WIP นี้; การแก้ edge trial ต้องต่อยอดบนไฟล์ที่มีอยู่ ไม่ใช่สร้างไฟล์ใหม่ทับ

---

## 4. โมเดล coverage ที่เสนอ (bounded endpoint/candidate)

### 4.1 กราฟ

- **Node** = `(context, GFM subset)` ที่มี certificate (หรือ definitively infeasible ที่บันทึกไว้)
- **Edge (release)** = `S → S \ {i}` โดยมี (ก) แถว SG_ON certified ของ `S\{i}` และ (ข) **private trial ของการเปลี่ยนโหมดเข้าหา `S\{i}`** ผ่าน
- **Edge (augment/recover)** = `S → S ∪ {i}` หรือ `S → S'` (outage) ด้วย relation ของข้อ 3.8
- Acceptance path = path จาก node เริ่มจริง (actual committed set หลัง SG reclose) ไปยัง **endpoint ที่ผ่านเกณฑ์และคืน GFL มากที่สุด/เหลือ GFM น้อยที่สุดตามหลักฐาน**. SG_ON endpointอาจเป็นempty GFM subsetเมื่อSGเพียงพอ ไม่บังคับ `9→…→0`; residualต้องมีevaluated justification ไม่หยุดที่mixed setใด ๆเพียงเพราะแถวแรกผ่าน

### 4.2 Bounded discovery (ไม่ประเมิน 512 subset)

- ใช้ **priority order ที่ประกาศล่วงหน้า**: `n_mode_changes` → `n_gfm_required` → `margin` → resource tuple (ฟรีซก่อนรัน) — ตาม [ibr_selector_search_lazy.m:665-690](../+stability/ibr_selector_search_lazy.m#L665-L690)
- **โหมด endpoint discovery**: กำหนดเป้าหมายเป็น *reachable permitted endpoint* เช่น “subset ขนาด ≤ k ที่ปล่อยต่อได้อีกหนึ่งตัวจนถึงปลายทางที่ยอมรับ” — หยุดเมื่อได้ path ที่ปลายทางผ่านเกณฑ์ หรือเมื่อ budget หมด (**HOLD** ไม่ใช่ fail)
- **โหมด neighborhood expansion**: จาก node ที่ certify แล้ว ขยายทีละ release/one-step (ไม่ backtracking) จนสุดงบ; ถ้าตันให้รายงาน `PATH_NOT_COVERED` พร้อมจำนวน node/edge ที่ประเมินแล้ว
- **ห้าม** ใช้ `stop_on_first_certified=true` ในการรันวัด coverage ของ SG_ON: มันหยุดที่ certificate แรก (บรรทัด [352-358](../+stability/ibr_selector_search_lazy.m#L352-L358)) ซึ่งเป็นเหตุผลที่แถว 8→7→… ไม่ถูกสร้าง
- **ห้าม** สรุป `NO_FEASIBLE_CANDIDATE`/“all-GFL เป็นไปไม่ได้” จาก HOLD หรือ INCONCLUSIVE

### 4.3 สถานะปลายทางที่ต้องมี (แยกกัน)

| สถานะ | เงื่อนไข | ความหมาย |
|---|---|---|
| `ENDPOINT_CERTIFIED` | มี node ปลายทาง certified + edge trials ครบ path | สำเร็จตามหลักฐาน |
| `PATH_NOT_COVERED` | ยังมี candidate ที่ไม่ได้ประเมิน หรือ edge trial ยังไม่รัน | ยังไม่พิสูจน์ |
| `BUDGET_HOLD` | หมด budget ก่อนขยายครบ | ยังไม่พิสูจน์ |
| `INCONCLUSIVE_EVIDENCE` | มี candidate ที่ UNKNOWN/missing evidence | ไม่ใช่ infeasibility |
| `NO_FEASIBLE_ENDPOINT` | ทุก candidate ที่เกี่ยวข้อง definitively infeasible | พิสูจน์แล้ว |
| `RESIDUAL_ACCEPTED` | ปลายทางเป็น mixed set ที่มีเหตุผลประเมินแล้ว | จบโดยเจตนา ไม่ใช่ค้าง |

หลักการ: **residual terminal ต้องไม่อยู่ใน `PENDING` ตลอดกาล** และต้องมี evaluated reason + recovery metrics; ถ้าเหตุผลคือ coverage ขาด ให้คงสถานะเป็น `PATH_NOT_COVERED` (ไม่ใช่ `RESIDUAL_ACCEPTED`)

### 4.4 Reload/transition ของ SG_ON ในปลายทาง 0 GFM

`certify_ne39_transition` ต้องการ former อย่างน้อยหนึ่งตัวต่อ island ([บรรทัด 134-140](../+stability/certify_ne39_transition.m#L134-L140)) ดังนั้น:
- SG_ON + 0 GFM + SG online = **มี former (SG)** จึงไม่ถูกปฏิเสธด้วยformer-countเพียงอย่างเดียว; ยังต้องพิสูจน์candidate/input/context/spectrum/trialและrecoveryด้วยfixtureจริง ไม่ใช่certified endpointแล้ว (ไม่มีformerคู่ให้ตรวจslip)
- SG_OFF + 0 GFM = **ไม่มี former** → `NO_VOLTAGE_FORMING_SOURCE` เป็นการปฏิเสธที่ถูกต้อง ไม่ใช่ช่องว่างของ coverage

---

## 5. แผนดำเนินการ (phases + gates) และลำดับที่บังคับ

> **Human review gate (REQUIRED) ก่อน Phase 2 ทุกข้อ** — เอกสารนี้ไม่เริ่มงานเอง

### Phase 0 — Freeze (ไม่มีโค้ด)

1. ฟรีซ endpoint acceptance: mixed/residual ยอมรับได้แค่ไหน, เกณฑ์ recovery
2. ฟรีซ priority/ranking และงบต่อ context
3. ฟรีซนิยามสถานะในข้อ 4.3 (ชื่อ field/ค่าที่จะ publish)
4. ระบุ owner เดียวต่อไฟล์ (ข้อ 6)

**Gate 0:** เจ้าของโครงการอนุมัติเกณฑ์ mixed/residual + งบ ก่อนแตะโค้ดใด ๆ

### Phase 1 — Weighted supervisor เข้า gate จริง (FIRST implementation slice)

หลังอนุมัติ implementation แยกต่างหาก owner B ทำตาม [Supervisor](ne39_supervisor_design_plan_20261012.md): canonical weighted sampleเข้า actual gates, options/validation/forwarding, resolved thresholds/clocks, per-GFM eligibilityแยกglobal hard-safe/prediction dwell และ caller reset tests

**Gate 1:** controlled rate-only tests SI `.245→.365` และ `.28→.37`, actual release true→hold/resetdwellหลังbaseline dwell โดย hard/predictionไม่trigger; legacy/invalid/alignment testsผ่าน. ไม่ใช่logging-only และไม่ต้องรอphysical9→8commit

### Phase 2 — Endpoint/candidate coverage discovery (owner A; หลัง Gate 1)

1. รัน selector-only ภายใต้ approved design/budget เพื่อวัด SG_ON nodesที่ไม่pin; เก็บ `n_generated/n_evaluated/n_cached/budget_exhausted/universe_complete` และselection_statusจริง
2. ตรวจ certified initial/endpoints และ state_validity_fingerprintตรงcontext/runtime
3. ใช้ bounded discoveryตามข้อ4และ evaluator/validatorเดิม; ไม่fake ready flagsหรือinjectevaluatorเพื่ออ้างcertificate
4. ส่งมอบ node/edge manifestพร้อม evaluated/missing/budget/inconclusive reasons; build-time edge feasibilityไม่แทนlive private transition trial

**Gate 2:** มี certified nodes และ reachable permitted path ไป appropriate endpoint; ไม่mandatory9→0. Missing coverageไม่ใช่retained-certified success

Kernel/runner single writer: owner B ส่งมอบ Phase1ก่อน owner A/Cแตะไฟล์ร่วม ห้ามแก้พร้อมกัน

### Phase 3 — Serialized transition implementation (owner C; หลัง Gate 2)

ลำดับที่บังคับ (dependency ภายใน ไม่ขนาน):

1. **ส่ง candidate เต็มผ่านขอบเขต SG_ON**
   - ขยายผลลัพธ์ของ `choose_sg_online_one_step` จาก `target_selected` เป็น candidate ที่ authenticate แล้ว (เพิ่ม output โดย **ไม่ลบ** `target_selected`/`audit`/`ok` เดิม เพื่อไม่ทำลาย caller/เทสต์)
   - **ห้าม** fabricate `ready_to_commit`/`feasible`/`omega`
2. **validate certified input/context/current state + trial SG_ON DESTINATION แบบ private ก่อน publish**
   - ใน `reselection_transaction`: หลัง right-limit KCL และก่อน publish — เรียก `ne39_private_transition_trial` ด้วย candidate/spectrum จริง (SG_ON)
   - คง guard 3830 ไว้ แต่เปลี่ยนจาก “ปฏิเสธเพราะไม่มี spectrum” เป็น “ปฏิเสธเพราะ trial/spectrum ไม่ผ่าน” — ถ้าไม่มี candidate ให้ยังปฏิเสธด้วย `transitionEvidenceMissing` เหมือนเดิม
   - **ไม่ publish** right sample เมื่อ trial ไม่ผ่าน (rollback ตามรูปแบบ [บรรทัด 3830-3836](../+stability/ts_simulate_ibr_hybrid.m#L3830-L3836))
   - ต้องติดตั้ง certified input แบบ pair ตามแบบแผน support transaction ([บรรทัด 3384-3409](../+stability/ts_simulate_ibr_hybrid.m#L3384-L3409)) ถ้าใช้ `eq_u_eq`
3. **แยก runtime status ตามข้อ 2/4.3**
   - เพิ่ม reason จาก `audit.rejection_detail` (missing row / not ready / validator refused) เข้า terminal status โดยเป็น diagnostic ที่มีโครงสร้าง
4. **Multi-switch แบบ opt-in bounded delta**
   - SG_OFF support release ปัจจุบันเป็น **strict nonempty subset ไม่จำกัด delta=1** จึงอาจปล่อยหลายตัวในหนึ่ง transaction; augmentationก็ไม่จำกัดdelta1
   - เพิ่ม bounded routine แบบ **opt-in** ที่ deltaปกติ=1 และจำนวนก้าวมีbound; **legacy omissionต้องคงunbounded set-relation behaviorเดิม**. SG_ON authenticated releaseเป็นone-stepอยู่แล้ว
   - การสร้าง SG trip/reference-rescue เป็น certified-subset path แยก (อนุญาต simultaneous ได้เฉพาะเมื่อมี evidence) — คนละฟังก์ชันกับ weighted release
5. **Preflight reachable permitted path**
   - assert ก่อนเริ่ม 160 s ว่ามี path ถึง endpoint ที่ยอมรับ (ไม่ผูกกับ `9→0`)
   - ถ้าไม่มี → `PATH_NOT_COVERED`/`BUDGET_HOLD` พร้อมตัวเลข

**Gate 3:** controlled tests ผ่าน (ข้อ 8) + trial ปฏิเสธ state ที่ไม่ควร commit จริง

### Phase 4 — Integration / chronology

- Full 160 s เฉพาะเมื่อ Gate 3 ผ่าน และไม่ใช้ run นี้เป็น “physical proof แรก” ของ coverage (ข้อ 9)
- เก็บ per-release: node/edge id, trial audit, right-KCL, authority, weights/decision terms
- final modes ต้องตรงกับ endpoint ที่ประกาศ หรือรายงาน incomplete ตามจริง

---

## 6. ไฟล์และ ownership (single owner ต่อไฟล์)

| ไฟล์ | งาน | หมายเหตุ |
|---|---|---|
| [+stability/ibr_selector_search_lazy.m](../+stability/ibr_selector_search_lazy.m) | coverage/โหมด discovery, สถานะ 4.3 | มี WIP? ไม่ — แต่เป็น shared |
| [+stability/ibr_lazy_priority.m](../+stability/ibr_lazy_priority.m) | ลำดับ candidate ถ้าต้องเพิ่มโหมด | shared |
| [+stability/choose_sg_online_one_step (ใน ts_simulate_ibr_hybrid.m)](../+stability/ts_simulate_ibr_hybrid.m#L2963) | ส่ง candidate เต็ม | **ไฟล์มี WIP ค้าง** |
| [reselection_transaction](../+stability/ts_simulate_ibr_hybrid.m#L3756) | SG_ON destination trial | ไฟล์เดียวกัน → serialized |
| [+stability/certify_ne39_transition.m](../+stability/certify_ne39_transition.m) | reuse; แก้เฉพาะถ้าจำเป็นและมีเทสต์ | ห้าม weaken precondition |
| [+stability/select_support_augmentation_candidate.m](../+stability/select_support_augmentation_candidate.m) / [release](../+stability/select_support_release_candidate.m) / [post_outage](../+stability/select_post_outage_candidate.m) | bounded delta routine | legacy default = พฤติกรรมเดิม |
| [+stability/run_hybrid_case.m](../+stability/run_hybrid_case.m) | preflight path + option forwarding | shared runner |
| [scripts/diagnostics/ne39_reclose_applied_probe.m](../scripts/diagnostics/ne39_reclose_applied_probe.m) | request ชุดใหม่ (mixed/residual) | **ไฟล์มี WIP ค้าง** |

`ts_simulate_ibr_hybrid.m` + `run_hybrid_case.m` = runner/kernel ร่วม → **ห้ามแก้พร้อมกัน**; ถ้าจำเป็นต้องแตะทั้งคู่ ให้ทำเป็น sequence เดียวและมี owner เดียว

---

## 7. Cache / fingerprint (ต้องตรวจก่อนใช้เป็นหลักฐาน)

**สถานะปัจจุบัน:**
- `run_hybrid_case` **ไม่มี cache forwarding**: ตารางที่ผู้เรียกส่งมาจะถูก **rebuild + revalidate** เสมอ ([run_hybrid_case.m:502-511](../+stability/run_hybrid_case.m#L502-L511)) และเทียบ `state_validity_fingerprint` ([บรรทัด 580-609](../+stability/run_hybrid_case.m#L580-L609)); `opt.cache` **ไม่อยู่ใน** forward list ([บรรทัด 513-517](../+stability/run_hybrid_case.m#L513-L517)) → **ห้ามอ้างว่ามี cache reuse ผ่าน runner**
- cache ที่มีอยู่คือ `table.search_cache` ของ lazy search: resolve/lookup/store ที่ [ibr_selector_search_lazy.m:902-945](../+stability/ibr_selector_search_lazy.m#L902-L945) ใช้ `opt.cache.state_validity_fingerprint` เทียบกับ `sv_fp` ปัจจุบัน ([บรรทัด 107-110](../+stability/ibr_selector_search_lazy.m#L107-L110)); mismatch → `invalidated=true` และ cold search
- เทสต์ที่มีอยู่แล้ว: [test_ibr_lazy_vs_exhaustive.m:291-331](../tests/test_ibr_lazy_vs_exhaustive.m#L291-L331) ครอบ (ก) fp ตรง + `n_cached>0` (ข) fp ผิด → `cache_invalidated` + `n_cached=0` (ค) dispatch เปลี่ยน → fp เปลี่ยน

**สิ่งที่แผนนี้ต้องเพิ่ม (ยังไม่มี):**
1. **forwarding + adapter + roundtrip schema test**: output cacheใช้`fp`แต่inputต้องการ`state_validity_fingerprint`; ต้องมีexplicitadapterและrunnerforwardingพร้อมvalidation ไม่ใช่ส่งstructเดิมตรง ๆ. `table.search_cache` → persist → reload → adaptเป็น `opt.cache` แล้วต้องได้ candidate/`selected_gfm_indices` เดิม; ต้องทดสอบว่า struct array ของ certificate ยัง assignment-compatible (บทเรียน `cellstruct_to_structarray` [บรรทัด 1234-1274](../+stability/ibr_selector_search_lazy.m#L1234-L1274))
2. **fingerprint ต้องเปลี่ยนเมื่อ**: dispatch, topology, resource modes/online, ratings/params, source impedances, solver options ([บรรทัด 772-871](../+stability/ibr_selector_search_lazy.m#L772-L871))
3. **ต้องพิสูจน์ว่า cache ที่ reload ไม่ถูกนับเป็น run ใหม่** และ `fresh` ที่ runner สร้างต้องเป็นตัวตัดสิน ไม่ใช่ `supplied_table` ([บรรทัด 610-611](../+stability/run_hybrid_case.m#L610-L611))
4. **ห้ามเสนอ cache เป็น first physical proof** — cache เป็น view/diagnostic ก่อน; หลักฐานกายภาพคือ endpoint/edge trial ที่รันจริง

---

## 8. Tests / budgets / stops / owners

| # | Test / control | เกณฑ์ผ่าน | Owner | Stop condition |
|---|---|---|---|---|
| T1 | coverage discovery bounded: รู้จัก `ENDPOINT_CERTIFIED` / `PATH_NOT_COVERED` / `BUDGET_HOLD` / `INCONCLUSIVE_EVIDENCE` / `NO_FEASIBLE_ENDPOINT` | แยกครบ 5 และไม่ยุบรวม | A | ถ้ายุบรวม → หยุด |
| T2 | `stop_on_first_certified=false` ให้ row มากกว่า `true` ใน SG_ON context เดียวกัน | จำนวน evaluated เพิ่มจริง | A | ถ้าไม่ต่าง → รายงานว่า early-stop ไม่ใช่ blocker |
| T3 | `sg_on_n_gfm_required` ถอดออกแล้ว **ไม่** กลายเป็น HOLD ทันที | มีทั้ง certified node และรายงานจำนวนที่ยังไม่ประเมิน | A | budget หมดก่อน coverage → `BUDGET_HOLD` |
| T4 | candidate เต็มไหลผ่านขอบเขต SG_ON: candidate ที่ได้ต้องผ่าน precondition ของ certify ([36-40](../+stability/certify_ne39_transition.m#L36-L40)) | `ready_to_commit/feasible/omega` มาจาก evaluator ไม่ใช่ตั้งเอง | C | ถ้าตั้งเอง → หยุด |
| T5 | SG_ON destination trial: state ที่ไม่ควร commit ถูกปฏิเสธ และ **ไม่** publish right sample | `ok=false` + left state คงเดิม | C | ถ้า publish → หยุด |
| T6 | missing row / not ready / validator refused แยกกันได้จาก status | 3 เหตุผลต่างกัน | C | ถ้ายุบ → หยุด |
| T7 | bounded routine opt-in: deltaปกติ1; omissionรักษาlegacy unbounded set relation | legacy behavioral regressionผ่าน; byte-equivalenceถ้าจะอ้างต้องมีผลทดสอบเฉพาะ | C | legacyเปลี่ยนโดยไม่อนุมัติ → หยุด |
| T8 | SG trip/reference rescue path แยกจาก weighted release | simultaneous เฉพาะเมื่อมี evidence | C | ถ้าปนกัน → หยุด |
| T9 | preflight path: ไม่เริ่มเมื่อ path ไม่ครบ | fail-closed ก่อน TS | C | ถ้าเริ่ม → หยุด |
| T10 | cache roundtrip + fingerprint invalidation ครบ 3 กรณี | ตามข้อ 7 | D | ถ้า fp ไม่เปลี่ยน → หยุด |
| T11 | residual endpoint: ต้องมี evaluated reason ไม่ค้าง `PENDING` | ไม่มี `PENDING` ที่ horizon | A | ถ้าค้าง → รายงาน incomplete |
| T12 | legacy regression: `SCOPED_TESTS` + handback regression 3 ไฟล์ + IEEE14 workflow เทียบชื่อ/diagnostics กับ baseline | ไม่มี failure ใหม่ที่ไม่มี baseline | D | failure ใหม่ที่ไม่มี baseline → หยุดวิเคราะห์ |

**Budgets (ข้อเสนอ ต้อง freeze ก่อนรัน):**
- discovery: `max_full_evaluations` แยก SG_OFF/SG_ON (ค่าเริ่มไม่ผูกกับ 4); `stop_on_first_certified=false` สำหรับ SG_ON coverage
- `max_generated` ระบุชัดเมื่อต้องการ bound
- trial budget: `ne39_trial_max_steps` ต้องครอบ dt และ dt/2 ([ts_simulate_ibr_hybrid.m:3230-3234](../+stability/ts_simulate_ibr_hybrid.m#L3230-L3234))

**Stops:** หยุดทันทีถ้าพบ (ก) การตั้ง ready flag เอง (ข) การลบ guard 3830 (ค) publish state หลัง trial fail (ง) legacy path เปลี่ยนพฤติกรรม (จ) การสรุป infeasibility จาก HOLD

---

## 9. Dependency / serialization (บังคับ)

1. **Gate 0 → Phase 1 weighted actual-decision tests → Gate 1 → Phase 2 coverage → Gate 2 → Phase 3 transition (serial) → short fixtures + regression baseline + recovery approval → Phase 4**
2. Kernel/runner ร่วมต้องเข้า queue เดียวและมีsingle writer; ไม่ทำcoverageก่อนหรือขนานกับweighted sliceแรก
3. Serializationไม่ใช่physical proof; node certificateและlive edge trialเป็นคนละหลักฐาน. Controlled decision testsไม่ใช่physical transition certificate
4. ถ้า Phase2 coverageไม่ครบ การแก้kernelไม่ทำให้coverageครบเอง; รายงาน `PATH_NOT_COVERED` ตามจริง

---

## 10. ข้อห้าม (fail-closed)

- ห้ามตั้ง `ready_to_commit`/`feasible`/`omega`/spectrum เอง หรือ inject evaluator แล้วอ้าง certificate ([ibr_selector_search_lazy.m:490-501](../+stability/ibr_selector_search_lazy.m#L490-L501))
- ห้ามลบ guard `transitionEvidenceMissing` ([ts_simulate_ibr_hybrid.m:3830-3837](../+stability/ts_simulate_ibr_hybrid.m#L3830-L3837)) — เปลี่ยนได้เฉพาะ “เงื่อนไขที่ทำให้ผ่าน” ไม่ใช่ลบการตรวจ
- ห้ามสร้าง API ใหม่แทน `certify_ne39_transition`/`ne39_private_transition_trial`; ห้ามสลับลำดับ argument
- ห้าม publish right sample เมื่อ trial/KCL ไม่ผ่าน
- ห้ามสรุป all-GFL/all-9 เป็นไปไม่ได้จาก “ไม่มีแถว”, HOLD หรือ INCONCLUSIVE
- ห้ามใช้ `reclose_status=SUCCESS` แทนหลักฐานสมดุล
- ห้าม commit/push หรือ stage WIP ที่ค้างในรอบวางแผนนี้

---

## 11. สิ่งที่ต้องให้เจ้าของโครงการตัดสิน (ก่อน Phase 2)

1. เกณฑ์ **mixed/residual endpoint** ที่ยอมรับได้ และ recovery metrics ที่ต้องผ่าน
2. งบ `max_full_evaluations` ต่อ context และการยอมรับ `BUDGET_HOLD` เป็นผลลัพธ์ที่ publish ได้
3. จะให้ residual GFM ในปลายทางเป็น `RESIDUAL_ACCEPTED` ได้เมื่อใด (เงื่อนไขขั้นต่ำ)
4. ขอบเขต multi-switch opt-in: delta สูงสุดที่ยอมรับ และเงื่อนไข justified
5. Recovery tolerances/หน่วย/settling window และ target/reference provenance ที่ต้องอนุมัติก่อน outcomesใหม่; ลำดับweighted-firstกำหนดแล้ว ไม่เปิดcoverage-firstเป็นตัวเลือก

---

## 12. Non-claims ของเอกสารนี้

- เป็น **แผน** ไม่ใช่หลักฐานว่า coverage ครบ หรือ all-GFL/all-9 ผ่าน
- ไม่ได้รัน MATLAB, ไม่แก้ numerical code, ไม่แก้ git ในรอบนี้
- เลขบรรทัดอ้างจาก snapshot ของ working tree ขณะเขียน; ก่อน implementation ต้องเช็ค diff/hash และอัปเดตเลขบรรทัด
- WIP ที่ค้าง (`handback` gate และ probe) ถูกอธิบายตามที่มีอยู่จริง แต่ **ไม่ถือว่าอนุมัติ** และไม่ถูกแก้ในรอบนี้
- ไม่ใช้ข้อความประมาณเวลา/artifact เก่าเป็น benchmark
