# New England IEEE 39-Bus System — การเปลี่ยนชุดข้อมูลต้นทาง

## สถานะปัจจุบัน (authoritative, snapshot ณ ก่อน commit — 2026-10-10)

ส่วนนี้เป็น **สถานะล่าสุดที่ใช้ตัดสินใจ**; หัวข้อเก่าที่ตามมา (รวม PENDING/running/no-subagent/ผล short 8.4s และ `pwsh-74`/`pwsh-90`) เป็น **ประวัติ ณ เวลานั้น** ไม่ใช่สถานะปัจจุบัน. รายละเอียดหลักฐานอยู่ที่ [superseding section:410–444](<C:/Users/User/Desktop/Power-flow/docs/project/NE39_TAMU_MIGRATION.md#L410-L444>).

- Branch `checkpoint/ne39-160s-20261009`, revision `8c891d6d7988a658bedbb099efa6652debe1bde7`; งาน study ทั้งหมดอยู่บน main working tree นี้ ไม่มี worktree/branch/reset ใหม่.
- Roles: **subagents เป็น primary implementers, parent เป็น PM/reviewer**. Delegation ที่อนุญาตใช้ provider **`deepseek-official`** + model **`ocg/deepseek-v4.1-flash`** + `reasoning_effort` **max** (ทางเลือกที่อนุญาตถ้าจำเป็น: `azure/gpt-6-luna`). ทำงานใน tree เดียวกันโดย ownership จำกัด; parent ตรวจไฟล์/diff จริงและ reconcile. ข้อความ no-subagent ที่เหลืออยู่เป็น historical.
- Verdicts ปัจจุบัน: **(1)** real-160 accepted-sample study **ผ่าน** (`STUDY_ACCEPTED_SAMPLES_VERIFIED`, 16051 samples, nonvoltage0/UNKNOWN0), **(2)** strict voltage **ไม่ผ่าน** (voltage-only169 samples; Vmax1.12146514pu bus35), **(3)** actual SG reclose **ไม่ผ่าน** (`SYNC_TIMEOUT`, `actual_reclose_time=NaN`). `production_certified=false` เสมอ.
- Main final checker (คำสั่ง exact ของผู้ใช้) **exit0 ~04:50:26**, device/mission assertions ผ่านและ artifacts ถูกบันทึก. Supplemental event/contract chain ปิดแล้วด้วย `pwsh-17` **exit0** (`RELOADED_FINAL_ARTIFACT_AND_CONTRACT_CORRECT_EVENT_CHECKS_PASS`); `pwsh-13` codecheck0/assertionFAIL เกิดจาก supplemental assertions **ผิด contract** ไม่ใช่ lint หรือ physics failure และถูก disproof โดย `pwsh-16` instrumentation — ไม่มีการ patch helper. Checkpoint commit ถัดไปยัง **pending parent review/commit**; เอกสารนี้ไม่ประดิษฐ์ commit hash ใหม่.
- Process: final snapshot **NO_MATLAB_PROCESSES_REMAIN**; [raw.mat](<C:/Users/User/Desktop/Power-flow/output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827/raw.mat>) SHA256 `ED4670EB…6E85E` และ checker SHA256 `745B8571…7B45` ไม่เปลี่ยน; accepted device artifact `71DF94CB…0A16F`. Remote branch/ref ตรง `8c891d6d…bde7` ก่อน ledger commit ที่จะมาถึง. Parent จะ commit **ledger-only**. ไม่มี final process check ค้างอยู่.
- **ห้ามรัน real160 ซ้ำตามคำสั่งผู้ใช้; ให้ตรวจ postprocessing ของ [raw.mat](<C:/Users/User/Desktop/Power-flow/output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827/raw.mat>) เดิมเท่านั้น** (ไม่ invalidate raw เก่า และไม่เขียนทับ). Adaptive `max_step=.001` เป็นคำขอในอนาคตที่ **deferred และ NOT RUN**; Pm change, rotor reset, fake close และ synchronism relaxation แยกต่างหากและยังไม่อนุญาต.
- **16 staged deletions ของผู้ใช้** และ unrelated tracked work ค้างอยู่ — ห้าม stage/commit/reset รวม. Protection hashes: staged `02F3EB7FB06F85983EF5E6CE1C50127D2552239096F43BFF2D773ED62128368C`, unrelated `E58F4948499A07E61CA60BEC573141952F55A77ED0C90A1175EFB20E00BCF3AA`.

## ขอบเขตที่เสร็จ

ทั้ง `cases.case_ne39_5sg_5ibr()` และ `cases.case_ne39_1sg_9ibr()` ใช้ข้อมูลจากชุด New England IEEE 39-Bus System ที่เผยแพร่โดย Texas A&M University แทน MATPOWER case39 และ RTS dynamics proxy ที่ใช้ก่อนหน้า ชื่อระบบไม่ใช่ TAMU; คำนี้ใช้ระบุช่องทางเผยแพร่ชุดข้อมูลเท่านั้น

ไฟล์ต้นทางเก็บแบบ byte-identical ใน `docs/benchmark_sources/ne39_tamu/` ส่วน runtime ใช้ literals ใน `cases.ne39_tamu_raw()` และ `cases.ne39_tamu_machine_parameters()` จึงไม่ต้องมีโฟลเดอร์ Downloads บนเครื่องที่นำโปรเจกต์ไปรัน

แหล่งเผยแพร่: https://electricgrids.engr.tamu.edu/electric-grid-test-cases/new-england-ieee-39-bus-system/

ต้นทางอ้าง Athay, Podmore and Virmani (1979) และ Pai (1989); ไฟล์ export ระบุผู้จัดทำ Pablo Ledesma และวันที่ 2016-09-03

| ไฟล์ | SHA256 |
|---|---|
| PSSE/IEEE 39 bus.RAW | `800b65ed18e25957eba636b1c58e555fcf1b5990e918e2a982413085304b4689` |
| PSSE/IEEE 39 bus.dyr | `780f11c219271d6fc409cc41c755a9ceb52963f5b3986ed6cacaac5f64e4ffed` |
| PSLF/IEEE 39 bus.EPC | `d0b27156c3e178412243514c58750bc8cd385abe3ae995f2daa8218658036ab8` |
| PSLF/IEEE 39 bus.dyd | `3601edfdbe82da9cda434b23eaede3b7ad1ab9ac7e7d15dcee8d64b5a04b0f89` |

## ข้อมูลที่ใช้จริง

- 39 buses, 10 generators, 34 lines, 12 transformers; Sbase=100 MVA, fbase=60 Hz
- โหลดรวม 6124.5 MW; shunt บัส 4 = +100 MVAr และบัส 5 = +200 MVAr
- Transformer 31→6 ใช้ tap=0.993 ตามต้นทาง ไม่ใช้ 1.07 จาก MATPOWER
- ทุก bus มี base kV=1 ในไฟล์: เก็บเป็น normalized source base ไม่อ้างว่าเป็นแรงดันกายภาพ 345 kV
- Header ที่เขียน 9 generators ไม่ใช้กำหนดจำนวน: นับ generator records ได้ 10
- SG composition: {31,32,35,38,39} หรือ {31}; บัสเครื่องที่เหลือเป็น IBR `eecon49_dual` 17-state

## การปรับของโครงการ

Slack อยู่ SG31 ที่ V=1 pu และ angle=0° ในทั้งสองแบบ ไม่ย้ายไปบัส 1 ไม่ตรึงแรงดันและมุมทุก dynamic timestep

คง active dispatch ของเครื่อง non-reference ตามต้นทาง แล้วแก้ PF เมื่อปรับ Slack voltage ใหม่ ใช้ reactive output ที่ได้หลังปรับ operating point เป็น IBR Q schedule จากนั้นแทน PV ของ IBR เป็น PQ และตรวจว่า PF ให้ operating point เดียวกัน

Rating converter เป็น PROJECT_DERIVED:

`S_rated_MVA = 10 * ceil(1.25 * hypot(P_schedule_MW,Q_schedule_MVAr)/10)`

ค่านี้เป็น converter apparent-power sizing ไม่ใช่ DC reserve ไม่ใช่หลักฐานว่าชดเชย SG outage ได้

## SG dynamics และฐานหน่วย

เก็บ GENROU ของ DYR ครบ 14 parameters ตามลำดับ:

`Tdo', Tdo'', Tqo', Tqo'', H, D, Xd, Xq, Xd', Xq', Xd'', Xl, S1, S1.2`

Xl ของ bus30=.025 ไม่ใช่ศูนย์ และไฟล์นี้ไม่มี Xq'' เป็น parameter แยก ค่าของ IEEEST จาก DYR และ EXST1 จาก PSLF DYD เก็บเป็น raw numeric records เพื่อไม่อ้าง mapping ของ controller ที่ยังไม่ได้ implement

MBASE ตาม RAW/EPC/DYD ที่ buses30:39 คือ `[200,100,200,200,100,200,200,200,200,2000]` MVA ใช้เป็นฐานแบบจำลอง ไม่ใช้เป็น physical nameplate limit:

- `H_system = H_machine * MBASE/Sbase`
- `D_system = D_machine * MBASE/Sbase` (ต้นทาง D=0 ทุกเครื่อง)
- `X_system = X_machine * Sbase/MBASE`

bus39 จึงมี H_system=500 s และ Xd'_system=.006 pu และมีความหมายเป็น external-system equivalent ไม่ใช่เครื่องจริงหนึ่งเครื่อง การแทนด้วย IBR ในแบบ1SG9IBR เป็นสมมติฐานโครงการ

**เส้นทาง runtime ยังเป็น classical reduction**: internal EMF คงที่หลัง Xd', swing equation จาก H/D ต้นทาง ไม่มี flux/damper/AVR/PSS dynamics ไม่ใช่ full GENROU และผล fault-current/voltage-recovery ไม่เทียบเท่า GENROU+EXST1+IEEEST

## ผลตรวจและข้อจำกัด

Verification จาก `scripts/diagnostics/verify_ne39_tamu_migration.m` เก็บที่ `output/diagnostics/ne39_tamu/migration_verification.json`:

- ทั้งสอง composition: PF converged, max mismatch≈1.09e-13 pu
- physical KCL residual≈1.63e-13 pu
- state count: 95 (5+5) และ155 (1+9)
- ตรวจ source-aware SCR ด้วย SG Xd' บน system base; เป็น transient-basis diagnostic ไม่ใช่ IEC60909 และไม่ใช่ SG machine SCR จาก OCC/SCC
- SSSA คำนวณเป็น diagnostic ของสมการเท่านั้น; real parts ใกล้ศูนย์ไม่ใช่ damping certificate และไม่ clip เพื่อให้ดู stable
- ชุดทดสอบ source/case/mixed/SCR/case-format รวม source archive SHA256 ผ่าน38/38; adapter oracle เดิมผ่าน8/8

**ยังไม่รับรอง physical active capability หรือ switching**: RAW PT=9999.9 เป็น sentinel ไม่ใช่ Pmax จริง จึงใส่ active limit เป็น unknown (NaN) ไม่ใช่ unlimited และไม่เปลี่ยน gate เพื่อให้ผ่าน `mixed_equilibrium_solve` ให้ equation solution ที่ residual ต่ำ แต่ `converged=false` เมื่อ operating-limit certification ไม่ครบ เช่นเดียวกับ production entry ที่ไม่ดำเนิน simulation ต่อ

Source-only diagnostic ไม่รัน TS เพราะ capability unknown ส่วน study profile ที่ออกแบบแยกในหัวข้อถัดไปรัน fault-only ได้แล้ว ไม่ใช้ผลนั้นอ้าง switching certification รายงานนี้ไม่ใช่รายงานการทดลอง switching ฉบับสุดท้าย

## Study capability ที่ออกแบบแยกจาก source profile

เปิดด้วย `cases.scenario_ne39_5sg_5ibr(struct('study_capability',true))` หรือ `cases.scenario_ne39_1sg_9ibr(struct('study_capability',true))` เท่านั้น Default ยังคง unknown physical active limit ตามต้นทาง

`cases.ne39_study_capability` ประกาศกำลังต้นทางที่ต้องจัดหาเป็น `Pmax=10*ceil(1.25*P0/10)` MW: เพิ่ม active-power design allowance 25% และปัดเป็นบล็อก10MW ไม่อนุมานจาก MBASE ไม่อ้างว่าเป็น rating เครื่องเดิม สำหรับ SG ค่านี้เป็นข้อกำหนด prime-mover design ไม่ใช่ SG capability curve หรือ governor response

สำหรับ IBR ตรวจ `hypot(Pmax,Q0)/(Mbase*.9)<=1.2` ที่ขอบ AC operating envelope .9pu (ไม่ใช่ relay/protection setting) รวม filter loss เป็น `Pacmax=Pmax/Mbase+Rf*Ineed^2` ใช้ Rdc=.1, Cdc=.1 และ tau_s=.005 จาก DC model ที่ประกาศ:

- `Edc=1+Rdc*Pac0` โดย Pac0 รวม filter loss ที่ actual initial voltage
- `Vdc_high=(Edc+sqrt(Edc^2-4*Rdc*Pacmax))/2`
- ตรวจ `Pacmax/Vdc_high^2<1/Rdc` และ `tau_s<Cdc*Vdc_high^2/Pacmax` ซึ่งเป็น determinant/trace conditions ของ local DC block
- ข้อกำหนดกระแส continuous source ที่ต้องจัดหา: `Idc_design=1.05*Pacmax/Vdc_high`
- ข้อกำหนดกำลัง source: `Psource_design=Edc*Idc_design*Mbase` MW รวม internal-resistance loss

ตรวจ Edc/Rdc ที่คำนวณกับ parameters ของ closures ทั้ง GFL/GFM จริง โดยคงไว้ใน device provenance ผ่าน factory ไม่ใช้สมการสำเนาเป็นหลักฐานเพียงอย่างเดียว การทดสอบ study capability3ข้อและ source/mixed/dual-mode/hotpath regressions รวม34ข้อผ่านหลังแก้ metadata

ผล `verify_ne39_study_no_event` ผ่าน production entry ทั้งสอง composition ที่ t_end=.1s, dt=.01s โดย max state/voltage-coordinate deviation=0 (stationary equilibrium ไม่มี disturbance) runtime ที่วัดก่อนเพิ่ม provenance metadata คือ1.237s และ.528s ผลนี้เป็น short smoke test ไม่ใช่ speedup benchmark หรือ switching certificate

Fault-only study ที่ bus16, Zf=j.1pu, t=.5–.7s, horizon1s, dt=.005s รันผ่านทั้งสอง composition เก็บ raw MAT และ summary JSON ที่ `output/diagnostics/ne39_tamu/` ค่า IBR current สูงสุดเป็น .867418/.838351 machine pu ไม่เกิน1.2 และ DC current ไม่เกิน design limit ใน traces ที่ตรวจนี้ ไม่ใช้ผล horizon สั้นอ้าง recovery หรือ switching

เพิ่ม online-rate measurement แบบ opt-in ใน production event driver อัปเดตเฉพาะ accepted samples/atomic event limits ไม่เปลี่ยน trajectory ทดสอบด้วย exact equality แก้ accessor ให้ GFM อ่าน active RHS ที่ index11 ของ dual superset และแยก event voltage jump จาก continuous ROCOV filter ใช้ time constant บน dt จริง Regression ล่าสุด75/75ผ่าน รูปและรายงาน fault-only แยกจากผล switching

**ยังต้องตรวจ transition energy, full-system candidate stability, SG capability curve และ fault/switching suite พร้อม timestep sensitivity** ไม่ใช้ local DC stability หรือ steady active sizing แทนหลักฐานเหล่านี้ และ `source_hardware_verified=false`, `transition_certified=false` เสมอใน design record นี้

## การคง DC plant และ dispatch หลัง SG trip (2026-10-09)

Study profile ส่ง `Edc`, `Rdc`, `Idc_max` และ `Psource_max` ที่ออกแบบไว้เข้า closures ทั้งสอง branch โดยตรง การเพิ่ม `P_ref` ของ candidate จึงไม่สร้างแหล่งจ่าย DC ที่แรงขึ้นใหม่ กระแสเริ่มต้นของ fixed plant ใช้ `(Edc-Vdc0)/Rdc`; equilibrium solver ต้องแก้แรงดัน/กระแสจริงภายใต้ plant เดิม ผู้เรียกเดิมที่ไม่ระบุ fixed plant ยังคง behavior เดิม

สำหรับ 1SG+9IBR กำหนด contingency เป็น SG31 และแจกกำลังที่สูญเสียตาม `Pmax-P0` ของ IBR แต่ละตัว ใช้ `post_trip_Pg_MW` และ `post_trip_Qg_MVAr` ชุดเดียวกันใน evaluator กับ runtime ไม่แจก deficit ซ้ำตาม GFM subset ส่วน reference GFM แก้สมดุลรวม network losses จาก full-KCL equilibrium สำหรับ 5SG+5IBR ยังไม่สร้าง all-SG-off dispatch แทนการ trip SG รายตัว: ถ้าไม่มี contingency-specific contract ต้องหยุด fail-closed

`ibr_dc_steady_reserve` ตรวจ high-voltage equilibrium, source continuous current/input-power limits, local DC determinant/trace และ AC current/Pmax ที่ Q/V ของ candidate โดยคำนวณ:

- `Jcap=min(Idc_max, Psource_max/Edc, Edc/(2Rdc), Cdc*Edc/(tau_s+Cdc*Rdc))`
- `Pac_cap=Jcap*(Edc-Rdc*Jcap)` บน converter base
- แก้ `p+Rf*(p^2+q^2)/|V|^2=Pac_cap` เพื่อหากำลัง AC ที่ PCC หลังหัก filter loss
- จำกัดเพิ่มด้วย current circle และ active `Pmax`; ส่งออก minimum margin รายเครื่องเป็น MW ไม่รวม margin บวกกลบเครื่องที่เกิน limit

ค่าที่ขาดหรือไม่ finite เป็น UNKNOWN/FAIL ไม่ใช้ converter MVA หรือ discriminant อย่างเดียวแทน source reserve ขอบ fold/trace เป็น supremum ของ steady envelope ไม่ใช่ safe transition boundary; จุด candidate จริงยังต้องผ่าน inequalities แบบ strict การตรวจนี้ **ไม่ใช่ transition-energy/synchronism certificate** และยังไม่รับรอง switching จนกว่าจะตรวจ trajectory และ transition gates จริง

แก้ lazy evaluator ให้รับ SG_ON/SG_OFF context ที่กำลังค้นจริง เพื่อไม่ประเมิน SG_ON ด้วย SG ทุกตัว offline โดยไม่ได้ตั้งใจ

ผล steady endpoint ที่ตรวจจริงของ 1SG+9IBR (จำกัดหนึ่ง candidate ต่อ context ไม่อ้าง global optimum):

- SG_ON, 9 GFL: ไม่ผ่าน damping floor .05; มี eigenvalue ใกล้ศูนย์ที่เปลี่ยนเครื่องหมายตาม FD และ worst oscillatory damping ประมาณ .01853 ไม่ clip eigenvalue เพื่อให้ผ่าน
- SG_ON, 9 GFM: ผ่าน steady certificate; KCL≈1.63e-13, worst damping≈.05946, rightmost decision eigenvalue≈-.4437 rad/s
- SG_OFF, 9 GFM: ผ่าน steady certificate; KCL≈1.69e-10, worst damping≈.2666, rightmost decision eigenvalue≈-1.615 rad/s
- SG_OFF, GFM subset ตัวแรกหนึ่งตัว: INCONCLUSIVE; initializer ไม่พบ exporting high-voltage DC branch ระหว่างการแก้ ไม่ใช่หลักฐานว่าทุก subset หนึ่ง GFM infeasible

การค้น SG_ON เพิ่มแบบจำกัด budget พบ subset `{IBR32}` GFM (อีก 8 IBR เป็น GFL) ผ่าน steady certificate: KCL≈1.63e-13, worst damping≈.07138 และ rightmost decision eigenvalue≈-.04566 rad/s ส่วน `{IBR30}` GFM ไม่ผ่าน damping≈.03792 ผลนี้เป็น first-certified search ไม่ใช่ global optimum

จึงยังไม่อนุญาตให้นำ 9GFL operating point ที่ไม่ผ่านไปอ้าง switching สำเร็จ การเริ่มด้วย IBR32 GFM หรือ9GFM เป็นคนละ initial-mode configuration และต้องรายงานแยกจากข้อกำหนดเริ่ม GFL เดิม เพิ่ม production entry gate ให้ต้องมี certified SG_ON row ที่ตรงกับ initial modes จริง ไม่ใช่เพียงพบ subset อื่นที่ผ่าน ผล endpoint นี้ไม่ใช่ผล trajectory หรือ transition certificate

การตรวจ 5SG+5IBR แบบ budget 6 candidate (all-GFL และ single-GFM แต่ละตำแหน่ง) ได้ HOLD และยังไม่มี candidate ผ่าน damping floor .05; single-GFM worst damping อยู่ประมาณ .00035–.00127 ค่า D=0 ของ classical SG มาจากต้นทาง ไม่มีการเติม damping เพื่อให้ผ่าน ผลนี้ไม่พิสูจน์ว่าทุก multi-GFM subset infeasible

Fixed-mode SG-cycle diagnostic จาก `verify_ne39_sg_cycle_fixed_modes` รันถึง .8s ได้ (dt=.0025s, trip=.02s, ขอ reclose=.70s); ใช้เวลาประมาณ38.66s แรงดันต่ำสุด .8839pu สูงสุด1.0640pu **ยังไม่ reclose**: `actual_reclose_time=NaN`, `PENDING_SYNC_FAIL` เก็บ raw trajectory และ JSON แยกที่ `output/diagnostics/ne39_tamu/sg_cycle_fixed_modes.*` ผล numerical convergence ไม่ใช่หลักฐานว่า voltage envelope หรือ synchronism ผ่าน ตรวจ DC trajectory จาก raw state เพิ่มแล้ว: Vdc รวมอยู่ประมาณ .995926–1.00295pu และทุก IBR มี source current ต่ำกว่า continuous design limit ใน run สั้นนี้; ไม่ใช้ผลนี้รับรอง AC-current, recovery ระยะยาว หรือ mode transfer

NE39 automatic SG-trip path ยังหยุดด้วย `transitionEvidenceMissing` ก่อน mode commit: steady endpoint ที่ผ่านไม่แทน event-time forward trial ที่ต้องตรวจ current/DC energy และ synchronism ระหว่าง transfer ส่วน fixed-mode trip ที่ไม่เปลี่ยน IBR mode เป็นการทดลองแยก และผล numerical convergence ไม่ใช่ physical-limit certificate

Short fault smoke ของ 1SG+9IBR ที่เริ่ม IBR32 GFM อีก8ตัว GFL ผ่าน production fault-only path ที่ fault bus16, Zf=j.1, t=.02–.04s, horizon=.1s และ dt=.0025s ผลนี้เป็น configuration แยก ไม่ใช่ all-GFL baseline และไม่รับรอง SG trip/switching

## Regression ของ lazy readiness และ test environment (2026-10-09)

ทำซ้ำปัญหา `pf_init_paths` ไม่พบได้เมื่อส่ง lazy suite และ NE39 suite ใน `runtests` ครั้งเดียว แต่เรียก `runtests` แยกต่อกันไม่เกิดปัญหา จึงไม่ใช่หลักฐานว่า helper หายจากโฟลเดอร์หลัก ตรวจพบ lazy `setupOnce` ลงทะเบียน teardown เป็น `rmpath(root)` ซึ่งลบ root แม้มีอยู่ก่อน setup แล้ว แก้ให้เก็บ `original_path` และคืน path เดิมแทนการลบ directory โดยไม่ตรวจ ownership

หลังแก้ รันทั้ง `lazy→NE39` และ `NE39→lazy` ผ่าน40/40ต่อรอบ พร้อม assertion ว่า path และ pwd เท่ากับก่อนรัน เพิ่ม negative test ที่ injected evaluator มี feasible/ready และ within_limits แต่ไม่มี DC reserve: เมื่อบังคับ physical/DC evidence ทุก raw configuration ต้องมี `ready_to_commit=false` และไม่มี certified row การทดลองแรกของ test ใหม่นี้ถูก state-validity gate ปิดก่อน evaluator เพราะ fixture ไม่มี dispatch; เติม dispatch ใน fixture แล้วจึงตรวจเส้นทาง missing-DC gate ได้จริง ไม่แก้ production gate เพื่อให้ test ผ่าน

Regression รวม lazy, NE39 study capability, dual-mode hotpath, causal rates, active-rate accumulator และ source-aware SCR ผ่าน90/90 ไม่มี failed/incomplete หลังแก้ fixture ผล hotpath เป็น measurement ของรอบทดสอบนี้ ไม่ใช้สรุป speedup ของทั้ง simulation

Regression ของ IEEE14 SG-reference/initializer รอบแรกผ่าน6และ fail1 เนื่องจาก assertion เดิมนับ `5+4*7` active states ของ WECC เป็น61แถว ขณะที่ factory ใช้ EECON49 GFL: shared plant3 + PLL/PI6ต่อเครื่อง ทำให้มี69แถวเมื่อ source เป็น algebraic ตรวจ active-state map ของ dual model แล้วแก้เฉพาะ test ให้คิด9 statesต่อ GFL และเพิ่ม `I_dc` เฉพาะ source ที่มี state นี้ ไม่เปลี่ยน production equations หรือ acceptance tolerances หลังแก้รันสอง suite นี้ผ่าน7/7 ไม่มี failed/incomplete

## การไล่สาเหตุ single-GFM SG_OFF initializer (2026-10-09)

ทำซ้ำกรณี `{IBR32}` GFM หลัง SG31 trip ได้: Newton ลด residual จาก5.467pu ไปประมาณ.333pu แล้ว line search ไม่พบ step ที่ลด infinity norm ภายใน20ครั้ง เพิ่มการส่งออก `newton_info` และรายละเอียด rcond/line-search/final-alpha ใน failure reason เท่านั้น ไม่เปลี่ยน iteration, residual, Jacobian หรือ acceptance gate

หักล้างสมมติฐานว่าเกิดจาก FD step เดียวด้วย `fd_eps={1.5e-6,3e-6,6e-6}`: ทุกกรณีหยุดด้วย `line_search_exhausted=1`, final tested alpha≈1.907e-6 และ residual≈.333pu หลัง10–11 iterations; rcond≈3.525e-8,9.069e-9,5.903e-9ตามลำดับ ผลนี้ชี้เส้นทาง numerical failure แต่ยังไม่พิสูจน์ว่าไม่มี equilibrium หรือว่า configuration infeasible ทางกายภาพ ไม่มีการเพิ่ม SG damping หรือเปลี่ยน dispatch เพื่อทำให้ผ่าน

หลังเพิ่ม diagnostics รัน NE39 study capability + IEEE14 SG-reference + IBR initializer ผ่าน20/20 ไม่มี failed/incomplete

ค้น SG_OFF แบบสอง GFM เพิ่มเฉพาะ3 candidateตาม budget: `{IBR30,IBR32}`, `{IBR30,IBR33}`, `{IBR30,IBR34}` โดย referenceเป็นIBR30 ทุก row ยังไม่ certified และหยุดด้วย line-search exhaustion; residual≈1.543,.3998,2.595puตามลำดับ ผลเป็น INCONCLUSIVE ของ subsetที่ตรวจ ไม่ใช่การพิสูจน์ว่าทุกคู่ไม่มี equilibrium

NE39 automatic trip ยังปิดด้วย `transitionEvidenceMissing` ตามเดิม ไม่ใช้ผล regression นี้รับรอง transition หรือ switching

MATPOWER/RTS helpers และ10SGเดิมเก็บไว้ ผลในหัวข้อนี้ยังไม่ได้ commit/push ณ เวลาทดลอง; ภายหลังผู้ใช้ขอ checkpoint บน branch แยก (ดูหัวข้อท้ายรายงาน)

## Independent rates/prediction policy และ transition snapshot (2026-10-09)

เพิ่ม `ne39_rate_policy`: augment proposal จาก SI-on หรือ ROCOF/ROCOV violation หรือ causal outward V/f projection แยกกัน; release ต้อง SI-off และ V/f/rates ของทุก online IBR valid/safe ต่อเนื่องครบ dwell ไม่ใช้คะแนนรวมกลบ failure เปิดผ่าน `ne39_rate_policy=true` พร้อม healthy PF reference; ค่าเริ่ม ROCOF=1Hz/s, ROCOV=1pu/s, horizon=.25s เป็น PROJECT_DERIVED policy design ไม่ใช่ protection setting และยังต้องทำ sensitivity

Production driver อัปเดต policy จาก accepted samples เท่านั้น reset dwell เมื่อ resource epoch เปลี่ยนหรือมี event right-limit duplicate; ส่ง proposal ไป SG-off support supervisor และใช้ rates/prediction block post-reclose release ส่วน SG-online/partial-SG augmentation และ transition authority ยังไม่ครบ จึงไม่อ้าง enhanced switching suite สำเร็จ IEEE14 default ไม่เปิด policy นี้

Regression รอบแรกพบ decision log ไม่ถูกส่งออกจาก `run_hybrid_case` แก้ output forwarding แล้ว รอบถัดมาพบ SI evidence invalid ทุก sample เพราะ severity accessor อ่านเฉพาะ mode `sg` แต่ classical device ส่ง `synchronous` และ omega แบบ absolute pu แก้ให้ classical ใช้ `f=fbase*omega`; detailed SG เดิมยังใช้ `f=fbase*(1+omega)` ไม่เปลี่ยน swing equation ผลล่าสุด policy/NE39 study/snapshot/active accumulator/IEEE14 SG-reference ผ่าน41/41 รวม exact equality ของ fault-only trajectory เมื่อเปิด policy measurement โดยไม่มี switching authority

เพิ่ม `ne39_transition_snapshot` ตรวจ online resource P/Q, AC current ที่ converter base, V/f, fixed DC Vdc/Idc/source power จาก device จริง ไม่บังคับ transient Vdc>Edc/2 ใช้ `Pac` จาก DC RHS ตรวจข้ามกับ PCC power + filter copper loss + filter magnetic-energy rate `Lf/wbase*(id*did/dt+iq*diq/dt)`

DC energy รวม capacitor และ source inductor: `Epu_s=.5*Cdc*Vdc^2+.5*tau_s*Rdc*Idc^2`, `EMJ=Mbase*Epu_s`; derivative เท่ากับ `Edc*Idc-Rdc*Idc^2-Pac-Vdc*Ich` จากสมการจริง ไม่ใช้ steady reserve แทน transition trajectory ชุด snapshot4ข้อผ่าน รวม overcurrent/source-limit/unknown capability และ transient AC/DC power balance

เพิ่ม private `certify_ne39_transition` สำหรับ forward trial, per-island SG/GFM synchronism, snapshotทุก trial sample, integrated energy balance และ dt/2 refinement; budgetหมดคืน UNKNOWN ไม่ trivial PASS เมื่อเหลือ formerเดียว ทดสอบ snapshot/early constraints/budget/private trial/right-KCL รวม8ข้อผ่าน และ regression รวม policy/NE39 study/IEEE14 SG-reference ผ่าน32/32 **ยังไม่เชื่อม commit authority และยังไม่ใช่ event-left/right end-to-end certificate** `transitionEvidenceMissing` ของ automatic trip ยังอยู่ และปิด NE39 support/mode-release transaction ที่ยังไม่มี evidence เช่นกัน

## Scenario runner ที่เพิ่ม (2026-10-09)

เพิ่ม `run_ne39_scenario_suite` และ `run_ne39_chronology` รองรับสอง composition และ SI/enhanced arms, เลือก scenario เดี่ยวและ initial GFM IDs แบบ explicit ได้ ไม่มีการเปลี่ยน initial modes เงียบ ๆ แยก suite/chronology/composition/policy directories; raw MAT เก็บ request/model SHA256/result/elapsed และ summary JSON เก็บ raw SHA256 เหตุการณ์ applied/refused, reached horizon และ actual reclose แยกจาก numerical convergence

Catalog มี no-event, fault-only bus16, independent load20%/line16–17 outage-restore, SG31 cycle, load20%หลัง trip, faultหลัง trip, close-in line16–17 fault/relay clear, reference-owner outage และ chronology เพิ่ม `load_only`/`line_cycle` เป็น per-event capability profiles โดยไม่เปลี่ยน profiles เดิม โหลดเพิ่ม20%ส่ง `load_step_factor=.2` เพราะ driver บวก delta admittance และ actual multiplier=1+factor ไม่ใช่ส่ง1.2แล้วเพิ่ม120% ไม่อ้าง mid-line model และไม่ปรับเวลาเพื่อให้เกิด switching ก่อน run ต้องตรวจ catalog/branch connectivity/cache invalidation จริง ชุด runner ผ่านการทดสอบ catalog/branch connectivity/cache invalidation แล้ว ส่วน partial-SG context ยังไม่ครบ

ผลตรวจ runner ล่าสุดเมื่อคง source files ตลอดรอบผ่าน59/59 (runner5, profilesเดิม38, transition snapshot/trial9, policy7) cache fault-only request เดิม reuse ได้จริง `FAULT_REUSED=1`; การทดสอบก่อนหน้าที่แก้ production/runner/helper ระหว่างรันทำให้ model SHA256 เปลี่ยนและ cacheถูกปฏิเสธตาม contract ไม่ใช่เหตุผลให้ลดความเข้ม fingerprint

รัน no-event และ fault-only bus16 จริงทั้งสอง composition/policy รวม8arms ถึง5s, dt=.005s; fault_on=.5s และ fault_clear=.7s appliedจริงทั้ง4 fault arms เก็บ raw MAT/JSON ที่ `output/diagnostics/ne39_scenario_suite/` ทุก arm มี `physical_switching_certified=false` ไม่ใช้ผลนี้อ้างผ่าน damping/transition certification ของ all-GFL initial configuration load20% และ line16–17 outage/restore รันครบ8armsทั้งสองcomposition/policyถึง5s, dt=.01s, defining event appliedจริงและ numerical convergence=true ทุกarm ไม่ถือ8armsนี้เป็น physical certificate; switching requests20arms และ chronology4arms ได้ผล blockedก่อนTSจริง: 5SG+5IBR เป็น `stability:ibr_lazy_search:budgetHold` ภายใต้ budget3 ส่วน1SG+9IBRเป็น `run_hybrid_case:initialModesNotCertified` ทุก defining event=false, reached horizon=0 ไม่อ้างว่า20/4armsนี้มี trajectory หรือ switchingสำเร็จ

ทดสอบ1SG+9IBR enhanced SG-cycle โดยระบุ initial GFM `{IBR32}` ชัดเจน, dt=.05s และ selector budget3 ได้ trajectory ถึง event-left20s จาก requested120s แล้วถูกปฏิเสธ trip/mode commit ด้วย `stability:gfm_selection:transitionEvidenceMissing`; defining SG reclose=false ไม่มี actual reclose ไม่ใช่ initialModesNotCertified ใน arm นี้ เก็บ rawแยกที่ `output/diagnostics/ne39_certified_initial/`

## Raw constraints audit และ regression เพิ่มเติม (2026-10-09)

Physical regression ที่รันภายหลัง runner ผ่าน60/60 (NE39 study13, IEEE14 SG-reference4, lazy27, snapshot/private-trial9, policy7) ไม่ใช่ผลทดสอบการแก้ helper หลังรอบนี้

ตรวจ raw `1sg_9ibr/enhanced/suite/fault_bus16.mat` ครบ1003 accepted samples พบ `SNAPSHOT_CONSTRAINT_FAILURE`390 samples เริ่มที่0.735s ไม่มี UNKNOWN; Vทุกbusอยู่0.9232–1.0993pu, peak converter current0.8384pu, Idcสูงสุด0.8250pu, Vdc0.9982–1.0075pu ข้อจำกัด V/f/P/Q/current/DC รวมยังไม่ผ่าน จึงไม่อ้าง physical pass จาก numerical convergence สมดุล DC-energy RHS คลาดเคลื่อนสูงสุด1.6542e-16pu และ AC/DC power cross-check4.4409e-16pu ตรวจ failure แรกซ้ำจาก raw state พบ SG31 มี `active_power` ไม่ผ่าน: P=695.2348MW เกิน study Pmax=690MW ที่0.735s ขณะ V=.9876pu และ f=60.4224Hz ยังอยู่ใน envelope ไม่ขยาย Pmax เพื่อให้ผลผ่าน การ audit ใช้ model RHS ของ current checkout ตาม label ไม่ใช่การยืนยันว่า model SHA256 ตรงกับตอนสร้าง raw cache

เพิ่ม audit helper เก็บเหตุผลและ resource records ณ failure แรก ปฏิเสธ raw dimensions/context ที่ขาด; event-enabled arm ที่ไม่มี per-sample event context ไม่ใช้ initial context แทน เพิ่ม private-trial dt refinement ตรวจทุก coarse accepted time ไม่ใช่เฉพาะ final state รอบ snapshot/trial+audit ผ่าน14/14 หลังเพิ่ม path refinement และ audit-context gates; รอบต่อมา SI component/argmax logs และ NE39/IEEE14 regression ผ่าน38/38; รุ่นล่าสุดหลังเพิ่ม explicit NaN-KCL refusal, refinement sample-count assertion และ finite electrical-evidence check ผ่าน39/39 (snapshot/trial10, audit5, study13, policy7, IEEE14 SG-reference4) ยังไม่ให้ commit authority

ตรวจ static analysis ของ snapshot/trial/audit helpers รุ่นล่าสุดไม่พบ warning; test audit มี1 warning จาก unused helper argument เปลี่ยน argument เป็น `~` แล้ว แต่ยังไม่ได้รัน checkcode ยืนยันซ้ำ หยุด background regression ที่ซ้ำกันสองรอบ (`babch148l`, `blrfzwpw8`) ก่อนมีผล เพื่อไม่ให้ MATLAB แย่งทรัพยากรกับ production runs ไม่ถือว่าสองรอบนี้ผ่าน และ SG-cycle accepted-sample audit ที่ผูกท้าย `blrfzwpw8` ยังไม่ได้รัน

หลัง39/39 เพิ่ม spectrum-contract gate อีกครั้ง: ถ้ามี `physical_eigenvalues` ต้อง finite/nonempty/stable ทุก root และ `omega` ต้องไม่อ้าง decay เร็วกว่าขอบขวาสุดของ spectrum มิฉะนั้น UNKNOWN ไม่ละทิ้ง NaN/unstable root เพื่อ derive horizon รอบ negative spectrum/snapshot/raw-audit regression ผ่าน16/16 ไม่มี failed/incomplete; raw-cache audit ทั้งsuiteยังรันอยู่ ส่วน certified-initial SG-cycle `{IBR32}` ตรวจ401 accepted samples ถึง20sแล้ว: snapshot PASSทั้งหมด ไม่มี FAIL/UNKNOWN, V=.9830–1.0640pu, converter currentสูงสุด.8118pu, Idcสูงสุด.8071pu, Vdcประมาณ1pu และ AC/DC cross-check errorสูงสุด3.3307e-16pu ผลนี้เป็น accepted snapshots ก่อน trip เท่านั้น ไม่ใช่ intersample/transition certificate และไม่มี end-to-end transition commit ที่เปิดเพิ่ม

No-event ยังใช้ legacy no-event path และไม่มี online policy จึงระบุ `NO_EVENT_LEGACY_PATH_NO_ONLINE_POLICY` ไม่ใช้เป็นผล enhanced control; fault-only ไม่มี switching authority และไม่ใช้ผลนั้นอ้าง certified SG-trip switching ส่วน switching rows ต้องผ่าน production entry gates ตามเดิม หาก initial all-GFL ไม่ certified หรือ transition evidence หาย ต้องรายงาน blocked ไม่เติม trajectory หรือถือ defining event สำเร็จ

## Checkpoint ระหว่างปลดเส้นทาง chronology160s (2026-10-09)

Branch `checkpoint/ne39-160s-20261009` เก็บ NE39 และ shared dependencies ที่จำเป็น ไม่รวมงาน GUI/deck หรือ staged deletions ของ model families เดิม สถานะนี้ **ยังไม่รัน chronology สำเร็จ160s** และไม่มี SG reclose สำเร็จ

- แก้ initial GFM ของ runner ให้ผ่าน construction-time `initial_modes` และให้ lazy SG_ON ประเมินชุด initial จริงก่อน first-certified stop ไม่ใช้ certificate ของชุดอื่นแทน
- เพิ่ม lazy authentication envelope พร้อม resource/state/dispatch/topology bindings และ partial-SG partition check; runtime topology authentication หลัง load/line เปลี่ยนยังต้องตรวจต่อ
- private trial เก็บ failed snapshot และ private right-state เพื่อ replay ไม่ publish state ที่ถูกปฏิเสธ; classical SG ไม่ใช้ six-state AVR/governor synchronizer และยังคง Pm/Emag เดิม
- ใช้ NE39 damping floor .02 เป็น PROJECT_DERIVED study criterion; ผล .05 ในหัวข้อก่อนหน้าเป็นผลของเกณฑ์เดิม IEEE14 ไม่เปลี่ยน floor และไม่มีการตัด surviving physical roots ตามขนาด FD step

| การทดลอง | สิ่งที่เปลี่ยน / ผล | สิ่งที่หักล้างหรือยังค้าง |
|---|---|---|
| `ne39_entry_5sg_5ibr_20261009_141721_350` | ใช้ SCR input จริง; SG_ON singles/pairs/all ที่ตรวจ zeta≈.00035–.00127; SG_OFF มี subset ผ่าน | steady SG_OFF ไม่แก้ SG_ON; probe นี้ไม่ได้ตรวจ triples/quads ครบ |
| `ne39_controller_20261009_141941_306` | IBR33+36: M=.02/.04/.08, Dv=.5/1/2/5/10; ทุก SG_ON ไม่ผ่าน .02 | ไม่ติดตั้ง profile ใด; range นี้ไม่แก้ damping โดยไม่แตะ SG |
| `ne39_trip_1sg_9ibr_20261009_141911_143` | initial IBR32 ถูกปฏิเสธก่อน TS เพราะ search หยุดที่ IBR30 | พบ initial-set search priority defect ไม่ใช่หลักฐานว่า initial IBR32 infeasible |
| `ne39_trip_1sg_9ibr_20261009_142018_127` | initial IBR30 ผ่าน entry ถึง trip .02s แต่ private snapshot fail | authentication/entry ผ่าน ไม่ใช่ transition ผ่าน |
| `ne39_trip_1sg_9ibr_20261009_142159_915` | initial IBR33+37 ตรง certified SG_ON; SG_OFF ใช้คู่เดิม; Vbus32=.883901 ที่ private t=0 | snapshot .9pu operating bound ไม่ผ่าน; trip rollback |
| `ne39_trip_1sg_9ibr_20261009_142258_972` | initial9GFM ผ่าน แต่ SG_OFF first certified ยังเป็น IBR33+37; Vbus32 เท่าเดิม | เปลี่ยน initial เป็น all-GFM อย่างเดียวไม่แก้ right-limit |
| `ne39_trip_1sg_9ibr_20261009_143038_756` | เก็บ private right-state หลัง full KCL; numerical run จบคำสั่งแต่ tripยัง applied=false | ใช้ replay ได้ ไม่ใช่ accepted trajectory หลัง trip |
| FD oracle รอบแรก | foreign derivative1e-3 คูณ probe1e-6 ถูก raw-change tolerance1e-9 ซ่อน; fail3tests | แก้ exact-zero cross-check; รอบถัดไป11/11ผ่าน |
| FD cache รอบถัดไป | แทน lossy closure summary ด้วย exact device/context equality; เพิ่ม coordinate-separated probes และ captured-weight/cancellation counterexamples | รุ่นล่าสุดต้องผ่าน oracle13ข้อและ shared regressions |
| Combined regression รอบแรก | FD13, lazy27, table44ผ่าน; NE3930ข้อ error/incomplete เพราะ table unit teardown `rmpath(root)` | แก้ teardown คืน original path; ไม่ถือรอบนี้ผ่านทั้งหมด |

Right-state diagnostic ใช้สมการเดิมและ label `DIAGNOSTIC_ONLY_NO_TRANSITION_OR_COMMIT_AUTHORITY`: ไม่มีการผ่อน production voltage/frequency/current/DC/energy/refinement gates ไม่มี equilibrium state jump เพื่อแทน transient ผลช่วงต้นแสดง V ฟื้นเหนือ.9ภายใน sample .0025s แต่ frequency nadirประมาณ59.06Hz และเกิด overvoltageภายหลัง จึงหักล้างแนวคิดว่าลดเพียง instantaneous V threshold แล้วจะผ่านทุก constraint ต้องตรวจ controller/input contract และ recovery trajectory ต่อ

คำสั่ง pair ที่ quote string array ไม่ถูกต้องจบด้วย MATLAB `Unrecognized function or variable 'IBR33'`; แก้ใช้ `string({'IBR33','IBR37'})` แล้วรันจริง ไม่ใช้ failed command เป็นผล simulation

หลังแก้ table unit teardown รัน combined regression ผ่าน114/114 (FD13, lazy27, table44, source6, study13, snapshot11) ไม่มี failed/incomplete; เป็น regression ของโค้ด ไม่ใช่160s certificate ส่วน private right-state replay ถึง1sจริงที่ dt=.0025 และปลายช่วง snapshot PASS แต่มี constraint failures ระหว่างทาง เก็บที่ `ne39_right_replay_20261009_143124_273` โดยไม่ทับ raw เดิม

Source archives คง byte-identical ด้วย `.gitattributes -text` ไม่ลบ trailing whitespace หรือเปลี่ยน line endings ของต้นฉบับ; diff-check ของโค้ดผ่านโดยแยก source archive ออก

ตรวจ shared dependencies เพิ่ม `et_fcs_policy_generic`, backward-compatible IEEE14 alias และ explicit-policy input ของ production trip decision เข้า checkpoint; ไม่รวม comment-only changes ของ scenario/resource/SG helpers และงาน GUI path setup คำสั่ง dependency discovery แบบ relative path ล้มเหลวเพราะ test path ไม่ถูก resolve จึงรันใหม่ด้วย absolute paths; ณ ตอนจัด checkpoint ยังรอผล พร้อม regression เพิ่มของ rate/SCR/hotpath/scenario runner ไม่ถือว่างานที่ยังรันอยู่ผ่านแล้ว

Checkpoint `a26d1cc` commit/push แล้วบน `checkpoint/ne39-160s-20261009`; ตรวจ remote hash ตรงกับ local ครบ76ไฟล์ และ staged deletions เดิม16ไฟล์ยังอยู่ไม่ถูก commit. หยุด absolute-path dependency discovery หลังเกิน7นาทีโดยไม่มีผล ไม่อ้างว่า dependency tool ตรวจครบ; ใช้ source trace ของ shared call paths ประกอบ scope แทน

Regression เพิ่มจบ68 results แต่ **ผ่าน62 และถูก assumption filter6** ไม่ใช่68/68: frequency fixture ใช้ source case ที่ capability ยัง unknown. แก้เฉพาะ fixture เปิด `study_capability=true` และคืน original path แล้วรัน frequency suite ผ่าน6/6จริง รุ่นก่อนแก้มี hotpath warm median1792.8us/call ขณะ MATLAB jobs แย่งทรัพยากร ไม่ใช้แทน clean performance benchmark

| การทดลองหลัง checkpoint | ผล | ข้อสรุป |
|---|---|---|
| `ne39_inertia_5sg_5ibr_20261009_150342_452` | all-GFM; M=.5/2/8 (H=.25/1/4s converter base), Dv=20/50/100; ทั้ง9profilesไม่ผ่าน .02 หลายตัว unstable | เพิ่ม inertia/damping gain อย่างเดียวไม่แก้ SG_ON; ไม่ติดตั้ง profile |
| `ne39_voltage_bw_20261009_150837_424` | all-GFM; kiV=12/36/120, Dv=5/20/50; ทั้ง9profilesไม่ผ่าน .02 ที่ kiVสูงเกิด unstable roots | เพิ่ม voltage PI bandwidth อย่างเดียวไม่แก้; SG/DC/physical limits คงเดิม |

อ่าน spectrum เดิมจาก raw entry พบ limiting mode SG_ON≈7.87rad/s และ zeta≈.00035–.00127 ส่วน SG_OFF≈7.42rad/sบาง subsetผ่าน. แยก replay1sพบ resource failuresเฉพาะ voltage153 records และ frequency30 records; ไม่มีการใช้จำนวนนี้แทน intersample/refinement certificate

| การทดลองต่อเนื่อง | ผล | ข้อสรุป |
|---|---|---|
| `ne39_trip_1sg_9ibr_20261009_151209_708` | initial IBR33+37; exact SG_OFF all9GFM ผ่าน steady certificate แต่ private t=0 Vbus32=.883901; production trip rollback | target dynamics ต่างจากคู่เดิม แต่ transfer รักษากระแส จึงไม่เปลี่ยน instantaneous voltage |
| `ne39_right_replay_20261009_151642_938` | exact all9GFM private right-state replay ถึง2s; t=0 FAIL; samples ที่ตรวจหลัง.0025sฟื้นเข้า V/f envelope | diagnostic recovery ไม่ใช่ production transition/global refinement/reclose certificate |
| `ne39_voltage_op_20261009_151634_140` | ออกแบบ pre-event generator voltage floor1.02pu แล้ว derive PF/Q ใหม่; raw source/network/SG dynamics/ratings/gatesคงเดิม; private coarse passถึง1.84261591sผ่าน physical/KCL/energy/angle แต่ fine global error=.0269565853ที่sampleแรก | operating-point design แก้ coarse physical failure ไม่แก้ discretization; ยังไม่ติดตั้ง default และ production rollback |
| right-step stencil รอบแรก | empty struct schema ทำให้ append rowล้มเหลวก่อน save | แก้ diagnostic schema ไม่แก้ kernel/physical gates |
| `ne39_right_stencil_20261009_152234_360` | ทั้ง10 stencils converged; h=.0025 error=.0269565853; h=7.8125e-5 error=9.95954429e-6; h=1.953125e-5 error=1.71823828e-7 | fast transient resolveด้วยhเล็กได้; single-step stencilไม่ใช่ global trajectory certificate |

เพิ่ม optional private `timestep_strategy='adaptive'` ใช้ full-step/two-half-step differenceเลือก mesh และรับ full step; local threshold=`refinement_tol/20` โดยคง global threshold1e-5ที่ทุก coarse accepted time. Fine passเดินครึ่งทุก coarse intervalจริง ไม่ใช้mesh uniformแทน. Budgetนับ accepted stepsต่อpassและrefuseเมื่อหมด; runtime adaptiveเลือกbudget32000แบบ explicitไม่ตัดhorizon. เพิ่มattempt/rejection/min-max dt diagnostics และไม่ต่อhalf-stepที่ไม่converged. Default fixedเทียบexplicit fixedได้ผลเดียวกันใน fixture; snapshot/private-trial regressionผ่าน14/14 รวมadaptive constraints/budget/refinement sample-count. การตรวจ exact voltage-op trajectoryกำลังรัน ณ จุดบันทึกนี้ ยังไม่อ้างadaptive production PASS.

Strict frequency fixture regressionผ่าน6/6 ไม่มีIncomplete และ generic/IEEE14 policy aliasตรงกันด้วยisequaln. Snapshot+FD regression24/24ก่อนเพิ่มadaptive ไม่ใช้แทนผลทดสอบadaptiveที่เพิ่มภายหลัง.

## Adaptive private trial และ strict LTE (2026-10-09)

| การทดลอง | ผลที่ตรวจจริง | ข้อสรุป |
|---|---|---|
| `ne39_adaptive_trial_20261009_152911_345`, `154819_973`, `155329_010` | หยุดก่อนมี `trial.mat`; พบ MATLAB child ของงานซ้ำยังอยู่หลังหยุด launcher จึงตรวจ command line แล้วปิดเฉพาะ process ของ session | ไม่มีผล PASS/FAIL ของ trajectory; ห้ามนับเป็น trial ที่เสร็จ |
| adaptive regression ก่อนเพิ่ม progress/coverage gate | snapshot14/14, LTE3/3, rollback+fixed8/8; ไม่มีIncomplete | default paths ผ่าน regression; ไม่ใช่ผล voltage-op transition |
| `ne39_adaptive_trial_20261009_163754_142` | เปิด profiler; รับก้าวแรกที่h=1.953125e-5หลังreject7ครั้ง; logล่าสุดที่ตรวจถึงt=.000231461276s, steps10, wall396.1s; หยุดก่อนมีrawผลสุดท้าย | numerical fast transient เริ่ม resolveได้ แต่ยังไม่ครบhorizon; ไม่อ้างว่า physical/global gates ผ่านทั้งtrial |
| canonical one-step profile | right-stateเดิม h=1.953125e-5; Newton2iterations, grouped FD23groups/12y-groups; profiled wall3.3178s ส่วนsingle-thread5.18275sและresidual2.83948e-9 | มีงานอื่นรันพร้อมกันและรวม cold locality probe; ไม่ใช่ clean speed comparison หรือหลักฐานว่าsingle-threadเร็วกว่า |

เพิ่ม progress แบบ opt-in บอก simulation time, accepted steps, attempts/rejections และ energy/refinement errors; log ไม่เป็น input ของ numerical acceptance. เพิ่ม final coverage gate ให้จำนวน refinement samples ต้องเท่ากับ coarse accepted stepsก่อนPASS. ลบการassign resourcesซ้ำในinitialize เพราะมีassignmentเดิมอยู่แล้ว.

พบ scheduled event บังคับ backward-Euler restart แม้ตั้งstrict LTE; แก้เฉพาะ `adaptive_strict_lte=true` ให้ไม่รับ restart/floor/rescueที่ไม่มีLTEผ่าน ส่วนdefaultfalseยังคงเดิม. เพิ่มnegative regressionตรวจว่า strict floor refusalไม่publishก้าวที่ถูกปฏิเสธ พร้อมtestoptionforwardingและfixed-schema. รุ่นหลังแก้นี้snapshot/private-trial regressionผ่าน15/15ไม่มีIncomplete รวมprogressไม่เปลี่ยนevidence; static analysisของtrial/probes/tests6ไฟล์ไม่พบwarning. LTEoracleผ่าน3/3; strict/default rollbackและfixed regressionยังรอผล. Voltage-optrialรอบ`165619_872`เริ่มจากrawเดิมและรับก้าวแรกh=1.953125e-5หลังreject7ครั้ง; ยังไม่ครบhorizon. **ยังไม่มีproduction SG-trip PASSหรือchronology160s PASS**.

ผล private voltage-op trial `ne39_adaptive_trial_20261009_165619_872` จบจริง: PASS ทั้งสองรอบถึง1.84261591s; coarse863ก้าว, fine1726ก้าว, refinementตรวจครบ863จุดและerrorสูงสุด7.22941e-6ต่ำกว่า1e-5. Integrated DC-energy errorสูงสุด8.17096e-10/2.28292e-10pu-sต่ำกว่า1e-6; elapsed544.466s. เป็น `DIAGNOSTIC_PRIVATE_TRIAL_NO_COMMIT_AUTHORITY` จากright-stateที่เก็บไว้ ไม่ใช่production tripที่commitแล้ว. Strict/default regressionล่าสุดผ่าน13/13 (LTE3, rollback5, fixed5), ไม่มีIncomplete. Checkpoint `4cc6385` commit/pushแล้วก่อนtrialจบ;ผลนี้บันทึกภายหลัง. Production short trip `ne39_voltage_dispatch_run_20261009_170603_058` เริ่มใหม่จากpre-eventscenarioและประเมินselectorใหม่ แต่หยุดที่t=0/.12s ด้วย `ts_simulate_ibr_hybrid:badAdaptiveOptions` ก่อนเกิดtrip; process exit0เป็นstructured failure ไม่ใช่TS PASS.

แก้ validator ของadaptiveoptions: `rannacher_n` ต้องfiniteและเป็นinteger>=0ตามcontractเดิม ไม่ใช่positive; ส่วนพารามิเตอร์อื่นรวม `rannacher_window_dt` ต้องpositive. ไม่เปลี่ยนLTE/physicalgates/defaultvalues. Targetedregressionผ่าน2/2ไม่มีIncomplete: strictfaultarmใช้rannacher_n0และยังrefuseLTEที่floor, invalidrannacher_n[-1,.5,Inf,NaN]ยังfailclosed. Productionretry `ne39_voltage_dispatch_run_20261009_171057_359` จบจริง: reached.12/.12s, converged1, elapsed723.387s; sg_tripที่.02s applied1 และsg_on requestที่.1s applied1. Private trialในproductionผ่าน863/1726stepsถึง1.84261591s; strictLTE174acceptedsteps, maxerror.801643593, nonfinite0, rejected1, flooraccepted0. RecloseยังPENDING_SYNC_FAILและactualNaN จึงไม่ใช่SGcycleที่recloseสำเร็จหรือfullchronologyPASS. Static/regressionbatchแรกหยุดที่assertเพราะwholeproductiondriverมีcheckcode35warnings จึงยังไม่ได้รันregressionในbatchนั้น; ไม่ใช่numericaltestfailure. batchถัดมาหยุดเพราะaudithelperใหม่มีISCLwarning1จุด (ไม่ใช่numericalfailure); แก้เป็นisscalarแล้วแยกtestออกจากwhole-driverwarninggate. Regressionล่าสุดLTE3/3, rollback5/5, fixed7/7รวม15/15 ไม่มีIncomplete; checkcodeของ2testfilesและaudithelper0warnings. Whole-driverwarnings35รายการตรวจแล้วไม่มีwarningที่validatorจุดแก้; ไม่อ้างว่าwhole-driverwarning-free.

ตรวจ raw `ne39_voltage_dispatch_run_20261009_171057_359/raw.mat` ด้วย `audit_ne39_voltage_dispatch_run`: 177accepted samples, snapshotfail0/unknown0, fullphysicalKCLสูงสุด4.61406308e-8. Tripมีleft/rightตรงtransactionid, targetทั้ง9GFMตรงจริง, SGrotorและVdc/Idcต่อเนื่องexact; terminalcurrentjumpเมื่อประเมินบนevent-leftvoltageสูงสุด2.67377111e-15. PrivateproductiontrialและstrictLTEผ่าน. Auditstatus `SHORT_PRODUCTION_ARM_VERIFIED_NOT_FULL_CHRONOLOGY`; ไม่รับรองintersample/globalproductionrefinementหรือreclose. เริ่มchronologyจริง160sจากpre-eventdesignเดิมใน `ne39_voltage_dispatch_run_20261009_172448_477` หลังauditผ่านแล้ว. ผลproductionจริงจบ160/160s, converged1, elapsed2958.22s; SG31trip20s, load+20%50s, fault85/85.15s, line16–17trip110s และrestore/sg_onrequest145s appliedครบ. StrictLTE8317ก้าว, nonfinite0, maxerror.991951302, rejected10, flooraccepted0. SGrecloseที่150s timeoutและactualNaN จึงยืนยันได้ว่าเดินnumericalchronologyครบ160s แต่ไม่อ้างfullswitchingmissionPASS. กำลังตรวจacceptedphysicalsnapshotsและfullKCLจากrawตลอด160sแยกจากprocessexit0.

ระหว่างไล่reclosepathพบABIคนละฐานที่ต้องตรวจต่อ: `sg_classical_device` reconstruct `omega` เป็นabsolutepu (nominal1), แต่ `reference_grid_omega` คืนGFM `omega_m` เป็นdeviationpu (nominal0) และ `reclose_guard` ส่งสองค่านี้ไปลบตรง ๆ. ยังไม่ได้แก้productionpathและไม่ถือว่านี่เป็นสาเหตุเดียวของtimeout: rotorclassicalยังcoastด้วยPmเดิมและD0 จึงต้องตรวจslipจริงหลังแปลงหน่วยด้วย. ไม่reset/freezeSGและไม่เติมgovernor/AVRเพื่อทำreclose.

ผลตรวจ `chronology_audit_20261009_181728_510.mat`: 8324samples, fullKCLสูงสุด5.52325458e-8, strictLTEและscheduledeventsผ่าน; snapshotFAIL4834/UNKNOWN0. NetworkVmin=.842606448pu/Vmax=1.27509077pu; onlinef59.5140832–60.2066561Hz; converterImax1.08373408pu. DCenergyledgerจากrawสูงสุด4.3494198e-7pu-s (เป็นaccepted-sampletrapezoidไม่ใช่globalrefinementcertificate). ก่อนtripและหลังtripก่อนloadไม่มีsnapshotFAIL; loaded1454, fault163, postfault1244, lineopen1684, restored289FAIL. SG31ที่160sยังoffline, omega13.6237absolutepu, Pm5.4643systempu, H30.3s; การแก้ฐานslipเพียงอย่างเดียวไม่ทำให้recloseผ่าน. Auditstatus `CHRONOLOGY_NUMERICALLY_VERIFIED_PHYSICAL_OR_RECLOSE_INCOMPLETE`. Helpercheckcode0warnings. รัน160sสำเร็จเชิงnumericalแต่physicalmissionยังไม่PASS.

แยกFAILcategoriesจากrawแล้ว: active_power33616resource-sampleviolations และvoltage1473 ไม่ใช่voltageอย่างเดียว. ที่steadyloaded~80s มี8IBRเกินPmaxราว5.7–18.1MW; steadyV~.9915–1.0603puผ่านแต่activecapabilityยังไม่ผ่าน. Vminทั้งหมดเกิดloadright-limit50sและVmaxเกิดrestoreright-limit145s; ไม่ใช่steadyvoltagecollapse. ที่50s firstFAILมี8IBRเฉพาะvoltage; restorationstepมีnetworkVmax1.2751pu. ต้องออกแบบdispatch/capabilityและeventtransientร่วมกัน ไม่เพิ่มvoltagePIgainแล้วถือว่าแก้instantaneousjumpได้.

เพิ่ม `sg_speed_deviation` และใช้ในrecloseguard/failed-close diagnostic: classicalomega-1, EMF6omegaเดิม. Realdevice/base/negativeABItestsแรกผ่าน3/3และcheckcode0warnings; เพิ่มproductionguardregressionผ่าน4/4และcheckcode0warnings; adaptive rollbackผ่าน5/5 และfixedregressionผ่าน7/7 รวม16/16 ไม่มีIncomplete. ไม่เปลี่ยนSGstate/Pmหรือreclosegates.

ตรวจreserve arithmeticและfrozen-currentrightlimitโดยตรง: initialIBR5620MW + SG31 546.427081MW; sumIBRPmax7070MW แต่nominal+20%load7349.4MW จึงขาด279.4MWก่อนnetworklossesหากพยายามรักษาnominalvoltage. ที่50s/145s differentialstateและinputเท่ากันexactทั้งleft/right และaggregateinjectiondeltaI=0; Vเปลี่ยนจาก[1.00210024,1.06462759]เป็น[.842606448,.916074937]ที่loadstep และจาก[.989128622,1.059672]เป็น[1.10582272,1.27509077]ที่restore. นี่เป็นผลของlinearKCLกับcurrentstateต่อเนื่อง ไม่ใช่adaptiveLTEfailure; การเปลี่ยนPIgainอย่างเดียวที่stateเดิมไม่เปลี่ยนinstantaneousrightlimit. ต้องมีการออกแบบoperatingpoint/physicalplantหรือchronologyใหม่ที่ระบุชัดก่อนรัน ไม่แก้rawย้อนหลังหรือเพิ่มPmaxย้อนหลังให้ผลเดิมผ่าน.

ตรวจslipหลังแปลงฐานหน่วยจากrawเดิมโดยไม่รัน/แก้trajectory: ที่145/150/160s ได้11.2777209/11.7220335/12.6237284pu หรือ676.663252/703.322010/757.423702Hz. ทุกจุดยังเกินsynchronismdf_maxอย่างชัดเจน. ผลนี้ยืนยันว่าunitfixจำเป็นต่อการวัดที่ถูกต้อง แต่ไม่ใช่การแก้frozen-Pmrotorcoastและไม่ทำให้rawเดิมrecloseสำเร็จ.

## Study design หลังผู้ใช้อนุญาตให้ปรับค่าพร้อมเหตุผล (เริ่ม2026-10-09; ตรวจต่อ2026-10-10)

เพิ่ม opt-in `cases.ne39_chronology_design` เฉพาะ1SG9IBR ไม่เปลี่ยน default/source archives/network/SG H-D-Xdp/synchronism/selector gates. ค่าและเป้าหมายเป็น **PROJECT_DERIVED** ไม่อ้างเป็น TAMU hardware หรือค่าที่ต้นทางตีพิมพ์. Profileนี้ยังไม่ production-ready; ไม่มี160sใหม่หรือactual recloseจากงานช่วงนี้.

| ค่าที่ออกแบบ | สมการ/เหตุผล | ผล V1 |
|---|---|---|
| generator voltage setpoints | 1.04pu เป็น study target ภายใน.9–1.1; derive pre-event Pslack/Q ใหม่โดย PV PF | Psg31=545.694996MW; Vpfทั้งnetwork1.02251–1.08487pu |
| active capacity | CZโหลดใช้ `1.2*Pd*(1.1/Vpf)^2`; loss allowance5% และdesign margin10% เป็นสมมติฐานที่ประกาศก่อนrun ไม่ใช่lossที่วัดจริง | load envelope8099.411902MW; required9354.820747MW; rounded total9410MW |
| Q และ converter Mbase | SG31offline PV sizingPF ทั้ง loaded/line-open; Qmax=ceil10(1.2*maxabsQ); Mbase=ceil10(hypot(Pmax,Qmax)/(.9*1.0)) | total11360MVA; Idesign<=1.0pu เพื่อเว้นmarginถึงgate1.2pu |
| virtual inertia | DeltaP=max(Psg,.2*Pload_envelope)/sumMbase; M=fbase*DeltaP/RoCoFtarget1Hz/s; H=M/2 | M8.555716798s, H4.277858399s converterbase; เป็น aggregate sizing ไม่ใช่รับรอง individual transient RoCoF |
| droop | Dv=fbase*DeltaP/Deltaftarget.4Hz | Dv21.389291995; independent loaded/line commonf59.7481180/59.7602454Hz |
| Q/V dynamics | kE8คงเดิม; kQ/kE=.025pu/puQ; tauE/kE=.05s | kQ.2, tauE.4s |
| voltage PI | kpV1.2และinner kpI.3/kiI4คงต้นทาง; kiV/kpV=min(1/.05,slow_current_root/5) | เป็น PI-zero placement heuristic ไม่ใช่ closed-loop bandwidth/damping certificate; ต้องตรวจfullspectrumก่อนproduction |
| DC capacitance | `.5*Cdc*(1-.9^2)=Pacmax*.02s`; .02sเป็นdeclaredsource-interruption energy target ไม่ใช่LTE timestep | Cdc.15716–.18888pu-s |
| DC source | Rdc.1ตาม10%regulation; Edc=1+Rdc*Pac0; tau_sจากmaxflathelper; high-branch/current/trace/determinant checks; Idc/Psource5%margin | tau_s.007862–.009451s; GFL/GFMfixedplantตรงกันจริง |

Pmax/Mbaseรายบัส:30=420/550,32=1090/1490,33=1060/1320,34=850/1040,35=1090/1360,36=940/1090,37=900/1020,38=1390/1590,39=1670/1900 (MW/MVA). Profileส่งค่าทั้งสองbranchและDCเข้าสู่productionfactoryจริง ไม่เพิ่มPmaxย้อนหลังให้rawเก่าผ่าน.

| Experiment | ผล | ข้อสรุป |
|---|---|---|
| MATLAB R2025a `bci2cbe4u` | ไม่ถึงbatch ไม่มีoutputกว่า10นาที; ตรวจparent/commandlineแล้วหยุดเฉพาะPID66336/67576 | ไม่มีnumericaltestresult; ไม่ใช่simulationFAIL |
| MATLAB R2024b `b1fadjsaj` | ไม่ถึง`BATCH_STARTED`; หยุดเฉพาะPID55820/38400หลังตรวจownership | ไม่ใช้exit127จากstopแทนphysicalFAIL |
| R2025a `-nojvm` `bo0dqyb1u` | batchเริ่มได้; designtests4/4; screeningหยุดเพราะชื่อstateใช้gfm_omegaแทนgfm_omega_VSG | runtimeพร้อม; แก้diagnosticชื่อstate ไม่เปลี่ยนplant |
| independent `ne39_independent_design_20261010_000622_189736` | basePASS; loadedโยนimbalanceให้referenceใหม่จึงIBR30overcurrent | เป็นnominal-frequency reference-redispatchscreen ไม่ใช่physicalpost-loadtrajectory; แก้oracleให้uคงเดิมและsolvecommondroopf |
| MATLAB `ne39_chronology_design_20261010_001502_310` และindependent `001945_117243` | posttrip/loaded/lineopen physical snapshotsPASS; V1.02023–1.08140 /1.01102–1.07036 /1.00122–1.06621; fullKCL<=4.55e-10 | capacity/DC/droopsteadyปัญหาเดิมแก้ในscreen; ไม่ใช่SSSA/transient/productioncertificate |
| same endpointscreen | loadrightV.855295210–.922020581; restoreright1.12927224–1.29121794; snapshotFAILเฉพาะvoltage; current/u/xคงเดิมและfullKCLผ่าน | ไม่รัน160sด้วยprofileที่endpointFAIL |
| independent voltage1.06 `ne39_independent_design_20261010_001625_710981` | posttripVmax1.10423>1.1; loadrightmin.876343; restoremax1.31590 | เพิ่มsetpointเหมือนกันทุกเครื่องไม่แก้ทั้งสองendpoint |
| necessary convexbound บนV1network | bus8 right |V|<=.89995723pu (+numericalallowance1e-7ยังต่ำกว่า.9); arbitraryIBRcurrents/phasorsโดยไม่จำกัดrating/dispatch และทุกleftbus<=1.1 | สำหรับnetwork/loadadmittanceชุดนี้ gains/rating/dispatchอย่างเดียวไม่สามารถให้ทุกleft/rightvoltageผ่าน; ไม่ได้พิสูจน์ทุกoperatingpointหรือnetworkextensionว่าเป็นไปไม่ได้ |

Boundเก็บvectorhและidentityresidualใน`ne39_independent_design_20261010_001945_117243/screen.json`: K=Yleft^-1*C*(portrows)^-1, t=righttransferrow, r=t-hK. ใช้triangleinequality `|Vright8|<=1.1*(sumabs(h)+sumabs(r))` จากทุกleftbusและportvoltage<=1.1; boundไม่อาศัยclaimglobaloptimalityของSLSQP. Plantไม่มีphysicalcurrentjump จึงgainไม่เปลี่ยนrightlimitที่stateเดิม.

ล่าสุดregression20/20ไม่มีIncomplete (design4,speed4,rollback5,fixed7). เพิ่มrealendpointfail-closedtestแล้วdesign5/5ไม่มีIncomplete; test/helper/design checkcode0warnings. Pythonoraclepy_compileผ่าน; source/defaultisolationตรวจactualcase/machine/archivepayloadและcasegatesด้วยtests. ยังไม่ตรวจSSSA/privateadaptive/160s/recloseของdesignใหม่. SGmechanicalextensionยังไม่เขียน; frozenpositivePm/D0ยังไม่reclose-ready. ขั้นถัดไปต้องออกแบบphysicalvoltage-support/operating-envelopeที่มีเหตุผลและตรวจendpointก่อน ไม่sweepPIหรือเพิ่มlimitsเพื่อให้FAILหาย.

### Endpoint differential ต่อหลัง checkpoint42324dc (2026-10-10)

Python oracle เพิ่ม explicit options ของ operating load fraction, Q/V droop และ fixed shunt reactors; ทั้งหมดเป็น diagnostic เท่านั้น ยังไม่ส่งเข้า production case. Archives/raw เดิมไม่เปลี่ยน. Reactor stamp คือ `Ysh=-j*Qr/Sbase` และ `Qabsorbed=Qr*|V|^2`; reactor คงอยู่ทั้งก่อน/หลังทุก event ไม่ใช่ current state ที่ reset หรือ active source เพิ่ม.

| Experiment / artifact suffix | ผล | สิ่งที่แยกได้ |
|---|---|---|
| ครึ่งโหลด `003953_808556` | load-right min.87609, restore max1.31298; steady max1.11879 และบาง IBR เกิน active cap | ลด MW ทุกเครื่องอย่างเดียวไม่แก้ fixed-state load/restore; ไม่เลือก reduced-load mission |
| Q/V droop.1 `004045_352618` | steadyผ่าน; load-right min.85432, restore max1.28495 | การเพิ่ม droop ภายใน declared envelope ไม่แก้ endpoints |
| reactors ที่ load buses=Qload `004121_722411` | load-right min.78683, restore max1.29598 | placement ที่ load buses แย่ลง; ไม่ใช้แนวทางนี้ |
| reactors ที่เก้า IBR ports, แต่ละ500MVAr `004228_126399` | load-right min.88413, restore max1.24627 | port admittance มีผลต่อ fixed-state sensitivity แต่ยังไม่ผ่าน |
| port1500MVAr/1.04pu `004249_171061` | load-rightผ่าน .95233–1.01851; restore max1.14456 | ต้องตรวจทั้งสอง events ไม่รับรองจาก load อย่างเดียว |
| port2000MVAr/1.04pu `004344_287985` | load-rightผ่าน; restore max1.12353 | reactor size อย่างเดียวไม่ใช่ design ที่เหมาะสม |
| port1500MVAr/1.00pu `004412_420686` | load-right min.89827, restore max1.10346 | ชุดใกล้ feasible แต่ยัง FAIL ทั้งสองขอบ |
| port2000MVAr/1.00pu `004442_839936` | independent steadyและสองendpointผ่าน; load-right .91342–.98445, restore .99912–1.08215 | **เพียง mathematical feasibility witness ไม่ใช่เหมาะสม/production PASS**: ต้อง18GVAr fixed reactors และ converterรวม32.25GVAโดยประมาณ ใหญ่เกินกว่าจะเลือกโดยไม่มี trade-off/physical design; ยังไม่ตรวจ canonical/SSSA/transients |

ทุก run ใช้ +20% load, source network branchesเดิม, fixed u หลัง trip และ physical current continuity. ผลข้างต้นไม่อนุญาตให้เรียก 160s PASS. จะลด/ออกแบบ reactive support ที่เหมาะสมหรือใช้ justified network-reinforcement study แทนการรับค่าที่ใหญ่เพียงเพราะ oracle ผ่าน.

ต่อมา independent network-parallel relaxation n2 (`004714_274641`) ยัง load-right min.87070/restore max1.29208 จึงไม่เลือกเพิ่มวงจรทุกสาย; line event ใน oracle เปิดหนึ่ง source circuit ไม่ได้เปิดทั้ง reinforced corridor. Nonuniform phasor/dispatch optimization (fixed load Y และสอง common-droop equilibria) ที่port1500MVAr (`004858_782797`) feasible residual1.53e-11 และ gates.905–1.095 แต่13.5GVAr support/converter25.87GVAยังใหญ่; ที่1000/500MVAr localoptimizerไม่พบfeasible (ไม่ใช่globalimpossibilityproof). sizingที่ต่ำกว่าQreactor (`004822_096552`) ไม่ผ่านแม้ voltageผ่าน ยืนยันว่าห้ามดูVอย่างเดียว. Scalingoptimizerใหม่ (`005835_727485`) ไม่แก้1000MVArfailure. droop.1ร่วมphasors (`005023_978930`) ยังFAIL.

Canonical witness2000MVAr/1.00pu (`ne39_chronology_design_20261010_005352_228`) ผ่านจริงทั้ง steadyและendpoint, exactx/u/currentcontinuity, KCL<=5.72e-13. เป็น opt-in **physical network extension** มีnegativeBshที่ports ไม่เปลี่ยนbranches/load/sourcearchives/default. DeriveQmax/Mbase/DCใหม่รวมreactor; production_selectedfalse. SSSAแรก (`005544_204`) diagnosticล้มเพราะSGactive_state_indices_for_contextไม่ใช่functionhandle; แก้ใช้numericactivepartitionของSG. ตรวจใหม่ (`005639_410`) SG_ON93physicalroots omega-.0814127,zeta.0229801–.0229806; SG_OFF98roots omega-.445558,zeta.0525692–.0525693 ทุกFD1.5e-6/3e-6/6e-6. Gatecaseเดิมzeta_min=.02 จึงผ่านโดยไม่แก้threshold; ไม่อ้างgate.05. ยังไม่ตรวจloaded/line rotating-frame spectrumหรือprivate/chronology/reclose. Testsเพิ่มwitness/defaultisolationแล้ว6/6ไม่มีIncompleteและcheckcode0warnings (`005906_653`). Shortproductionwitnessเริ่ม (`ne39_voltage_dispatch_run_20261010_005948_001`) ยังรันอยู่ ณบันทึกนี้; ไม่เดาผล.

Capacitor disproof oracle: portshunt -500MVAr (`010012_785903`) load-rightผ่าน.93265–1.01223แต่restoremax1.18834; -1000MVAr (`010029_674561`) load-rightผ่านแต่restore.67223–1.34525และIBR30active/DCsteadyenvelopeFAIL. fixedcapacitorเท่ากันทุกportไม่ใช่คำตอบทั้งสองevents; capacitor resonance/placementต้องตรวจไม่ถือว่าผ่านจากloadeventเดียว.

Placement optimizer (`ne39_endpoint_support_20261010_010230_456725`) ลดreactorเหลือรวมประมาณ6.96GVAr โดยยังใช้25.87GVA converter ceiling และarbitrarydispatch; load/restore/line steady feasible แต่ไม่ผูกpre-eventplantหรือDC. **ต่อมาพบ fault-right ของcanonical2000MVAr witnessFAIL**: `ne39_chronology_design_20261010_010958_653` V.871573–.982187,KCL1.57e-13; line-rightPASS. Tests6/6 (`011020_256`) ณเวลานั้นรับรองload/restorewitnessเท่านั้น ไม่ใช่ครบevents. แยกfield `load_restore_pass` แล้วให้ `endpoint_pass` ต้องรวมfault/linerightด้วย; witnessจึงกลับเป็นendpointFAILอย่างซื่อตรง ไม่แก้fault/gates. Optimizationถัดไปเพิ่มloadedrelativeequilibriumและfault/linefixed-currentrightlimitsในconstraint.

หยุดshortproduction `005948_001` ก่อนเสร็จหลังพบfault-infeasible: processใช้CPUจริงแต่ยังค้างprivateหลังPROGRESS.0025; ไม่มีraw/productionPASS. TaskStopไม่หยุดลูกMATLABบนWindows จึงอ่านexactcommandlinesด้วยNtQueryInformationProcessยืนยันPID9724/69732ก่อนหยุดเฉพาะงานนี้; ตรวจภายหลังPIDsไม่อยู่แล้ว. Pythonbound1.09ที่เริ่มด้วยinlinecommandไม่มีartifactและstartupค้างPID78196ถูกหยุดหลังยืนยันcommandlineเช่นกัน; ไม่ใช้เป็นผลnumerical. WMI/Get-CimInstanceล้มด้วยRPCfailure;ไม่เปลี่ยนservices/licensing/systemsettings. ทุกjobที่หยุดไม่ใช่numericalFAILหรือPASS.

หลังรวมfault: optimizercap1500 (`011946_009041`) ยังไม่feasible (eq.00103,constraintmin-.003819), cap2000 (`012509_010892`) feasibleทุกelectricalendpointที่margin.905–1.095 แต่ arbitraryredispatch และ13.58GVAr support/31.9GVAconverter ไม่ใช่productioncertificate. เขียนcase-boundoptimizerให้derivepre-eventPF/Q/ratings/DCและpost-tripproportionalPใหม่ทุกcandidate. แรก `bi09arbsq` exit127ไม่มีoutput/result ไม่ใช้แทนนumericalFAIL; รันใหม่ `ne39_bound_case_20261010_012815_557125` ถึงiteration100: ทุกphysical.9–1.1/P/Q/current/DCsteadyoraclechecksผ่าน แต่declareddesignmargin1.095ยังFAILด้วยrestore1.09741211จึงstatusCASE_SCREEN_FAILED ไม่ลดmarginย้อนหลัง. ส่งparameterชุดนั้นตรวจcanonical/SSSAต่อ และseedoptimizerเดิมเพื่อเพิ่มmargin. MATLABregressionล่าสุดหลังfaultfailclosed (`012632_033`)6/6ไม่มีIncomplete/checkcode0warnings.

Canonical case-bound `ne39_chronology_design_20261010_013244_483` ยืนยัน endpointทั้งสี่PASS: load.90881–1.03425,restore1.01534–1.09741,fault.90509–1.03379,line.95374–1.08887,KCL<=1.42e-13. แต่ **SSSAFAIL** ทั้งSG_ON(zeta.0157985<.02) และSG_OFF(omega+.015766,zeta-.0019722), FDclassificationตรงกันทุกfactor. ไม่รันproductionด้วยชุดนี้; ปรับinertia/drooptargetsและตรวจfullrootsต่อ. Seedoptimizermarginเดิม `ne39_bound_case_20261010_013212_723989` ถึงiteration100ยังrestore1.09580888>design1.095 แม้physicalgate1.1ผ่าน;ไม่เปลี่ยนstatusเก่า. Pythonunittest3/3ผ่าน (tap/phase/shuntsign, commondroopfixedP, DCfoldfailclosed) ไม่ใช่trajectorycertificate.

Dynamic differential (`013537_467`/`013542_766`/`013546_133`): df target.1เพิ่มDvเป็น33.2095ทำSG_OFFPASS แต่SG_ONzeta.0187643/.0111321/.0084428ยังFAILเมื่อRoCoFtarget1/.5/.25; inertiaมากขึ้นไม่ได้แก้SG_ONและ.25ทำSG_OFFunstable. df.075/.05 (`013919_351`/`013925_054`) SG_OFFPASSแต่SG_ONzeta.016894/.014707ยังFAIL. ไม่เติมSGDย้อนหลัง. เปลี่ยนpre-eventmodeอย่างระบุชัด: allGFL (`014037_031`) ยังFAILและnearzero physicalroots; **all9GFM+SG31** (`014041_648`) ผ่านSG_ON100roots omega-.16824,zeta.0205529 และSG_OFF98roots omega-1.80204,zeta.497597ทุกFD พร้อมelectricalendpointทั้งสี่PASS. ยังคง1SG9IBR composition แต่ไม่ใช่initial2GFMเดิม;เป็นexplicitstudyoperatingmode. SourceSGH/D/Xdpไม่เปลี่ยน. ชุดนี้ใช้fixedreactorsรวม16.168306GVAr (ผลรวมเก้าportของdesign012815; ไม่ใช่18GVArของuniform2000witness) และtransition/recloseยังไม่รับรอง; เริ่มshortproductionใหม่ด้วยrequestชุดนี้ ไม่รัน160sก่อนprivate/shortตรวจผ่าน.

Short production `ne39_voltage_dispatch_run_20261010_014137_761` เสร็จจริง: reached.12/converged1, elapsed1089.04s, SG trip.02 applied1. Private trial PASS ทั้ง4.19544s coarse1798/fine3596steps; global refinement5.57433e-6<1e-5และcoverage1798ครบ, energy errors1.81134e-10/4.52779e-11pu-s. ตรวจrawด้วยMATLAB: V.94893–1.07779, acceptedLTEfiniteทั้งหมดและmax.836676, flooracceptance0. **SG_ON request.1ไม่ใช่actual reclose: actual_reclose_timeNaN** จึงไม่ใช่missionPASS. Regressionปัจจุบันdesign6/6+hybridLTE3/3ไม่มีIncomplete; Pythonoracle3/3ผ่าน. ไม่ใช้exit0เป็นphysicalPASS.

Short-event runnerฉบับแรกเรียกhelperที่ไม่มีอยู่ (`ts_adaptive_trial_step`) จึงแก้ก่อนใช้ให้เรียกcanonical `ts_step_composite` สามครั้งต่อattemptและรับสองhalfsteps, productionสูตรxRichardson/3และy differenceไม่หาร3. ตรวจmidpoint/rightlimitทุกevent, fullKCL/DC energy ledger, เก็บstatesและcontinuity; ไม่มีglobal refinement/selector/reclosecertificate. Run `ne39_short_physical_events_20261010_020021_012` พบnestedMATLABworkspaceทับerr/flow (LTEแสดงเป็นenergyresidualและcontrollerใช้errผิด) ผลนี้ใช้เป็นbreadcrumbเท่านั้น ไม่รับรอง. แยกsnapshotเป็นlocalfunctionและenergy_residualเป็นชื่อเฉพาะ; runใหม่ `020555_972` ยังfault-rightV.897242–1.02402ที่t.8 (<.9), KCL9.95e-14, strictLTEก่อนeventผ่าน. เป็นcompressedtime experimentที่รอเพียง.4sหลังload ไม่แทนchronologyที่รอ35s; แยกdisproofโดยเพิ่มระยะload settlingเป็น5sก่อนfault (ยังfaultduration.15s, Zf=j.1, load+20%, line16–17และgatesเดิม) ไม่แก้chronoเวลาจริงหรือย้อนหลังผลเก่า.

### 2026-10-10: ศึกษา natural voltage excursion ก่อน mitigation

Short run รอโหลด5s (`ne39_short_physical_events_20261010_021339_534`) ผ่าน fault-on แต่ strict voltage reference หยุดที่ fault-clear5.55s: V1.00178–1.12147pu, KCL1.14572e-13, IBR35/36 failure เป็น voltage เท่านั้น ณ right sample. การกระโดดของ algebraic voltage หลังเปลี่ยน Y ไม่ใช่หลักฐานสมการหรือ solver ผิด; ต้องดูการฟื้นตัวบน trajectory ต่อไป.

Sensitivity ที่เปลี่ยน voltage_response_s=.1/.2/.4 (`ne39_chronology_design_20261010_021929_468`, `021934_226`, `021937_202`) ผ่าน canonical endpoints เดิมและ full SSSA ทุกFD: SG_ON zeta≈.0204241/.0202921/.020461; SG_OFF omega≈−1.81069/−1.83002/−1.65845. แต่ short TS ของ tV=.4 (`ne39_short_physical_events_20261010_022248_412`) ยังหยุด strict voltage reference ที่ fault-clear5.55s: V1.00204–1.12184pu, KCL8.64413e-14. จึงไม่เลือก tV=.4 เป็นวิธีกดยอด และคง witness tV=.05 เดิม.

ผู้ใช้สั่งให้ศึกษาการตอบสนองตามธรรมชาติก่อน ไม่ต้องบังคับทุก instantaneous sample อยู่ .9–1.1pu. ในไฟล์ที่ตรวจไม่พบ provenance ว่า ±10% เป็น universal transient voltage limit หรือ TAMU hardware/protection setting; แก้ comment ที่เรียกช่วงนี้ว่า operating ของ TAMU เป็น **project operating reference**. ไม่กำหนด transient band ใหม่เอง และไม่แก้ raw/status เก่าย้อนหลัง.

เพิ่ม opt-in `observe_voltage`: snapshot ยังรายงาน strict PASS/FAIL/UNKNOWN ตามเดิม พร้อม complete/nonvoltage checks และ allbus voltage reference. Policy อนุญาตศึกษาเฉพาะ voltage-only excursion ที่ nonvoltage checks ผ่านครบ; current/P/Q/DC/f, KCL, energy, strict LTE, synchronism และ UNKNOWN ยัง fail closed. รายงาน excursion ทุกbus พร้อม sampled entry/recovery brackets, peak และ left-hold duration; duration ไม่ใช่ intersample proof หรือ protection setting. Short runner ใช้ SHORT_STUDY_COMPLETED ไม่ใช่ strict PASS. Private trial ใช้ STUDY_TRIAL_COMPLETE และยังทำสอง passes/global refinement/energy/slip เดิม, commit_authorized=false. Public hybrid forwarding เป็น explicit option; default ไม่เพิ่ม runtime sample gate และไม่เปลี่ยน integrator. Study adaptive เก็บ actual halfstep midpoint เพิ่มสำหรับ voltage/device/DC ledger โดยไม่แก้ endpoint trajectory. ยังไม่รับรอง production หรือ actual SG reclose.

Regression ช่วงเริ่ม study (`bksn7ypj9`) snapshot17/17, voltage observation3/3, chronology design7/7 (รวม reproducible all9GFM helper), canonical hybrid LTE3/3 ผ่านก่อนเริ่ม short study. Private/runtime wiring ที่เพิ่มภายหลังอยู่ใน verification แยก ไม่อ้างรวมเป็นผลชุดนั้น. Python oracleล่าสุด (`bnq0ildmh`)3/3 และ py_compile ทั้งสาม scripts ผ่าน.

Verification รอบ `bta55q941` private/snapshot18/18 และ observation3/3 ผ่าน แต่ runtime tests ใหม่ทั้ง3ยังไม่ผ่าน: test ระบุ fault1–1.15sเกิน horizon.005s ทำให้ public schedule validation ปฏิเสธก่อนเข้า TS; ไม่ใช่ model response failure. แก้ test ให้ weak fault อยู่ภายใน horizon และเปรียบเทียบ endpoint ตาม time/side แทน stride ที่รวม event duplicate. ทดสอบใหม่แยก พร้อม source archive SHA-256. ยังไม่อ้าง runtime PASS จนได้ผลจริง.

### รับต่อ study-first บน working tree เดิม (2026-10-10)

- ตรวจ Windows process ก่อนเริ่ม: ไม่พบ MATLAB child ของสอง jobs ที่ถูกหยุดใน handoff จึงไม่มี orphan ให้ฆ่า; อ่าน logs ยืนยัน short เดิมถึง7.40938sแล้วถูกkill และ runtime rerunเดิมไม่มีผล ไม่ถือว่าcompleted/physicalFAIL.
- Branchยังเป็น `checkpoint/ne39-160s-20261009`, HEAD `42324dc2e4d8fa33581bc226c0bdb6b6533c05c7`; fetchoriginแล้ว remote branchตรงHEAD (ahead/behind0/0). Stageddeletionsเดิม16รายการยังอยู่ ไม่เปลี่ยนbranch/reset/worktreeและไม่ใช้subagent.
- เริ่ม fresh MATLAB R2025a runtime/observation/sourcehash tests (`pwsh-4`): public weakfault.001–.002s, horizon.003sตามtestที่แก้แล้ว. ตรวจexactcommandlinesของlauncherPID29520/childPID5420เป็นงานนี้เท่านั้น. อยู่ระหว่างรอผล; ไม่ประกาศPASSจากstartup.
- อ่าน study policy/snapshot, canonicaladaptive midpoint/controller, privateสองpasses/globalrefinement, shorteventrunnerและauditจริง. `observe_voltage`เป็นexplicitoptionและstrict evidenceยังอยู่; endpointintegratorไม่เปลี่ยน, midpointไม่ป้อนrate supervisor, energyใช้dt0ที่event. ใช้witness014041/tV.05เดิม ไม่optimizeยอดหรือเปลี่ยนchronologyevents.
- `pwsh-4`จบจริง: observation3/3และTAMUsource/hash6/6PASS; runtime3FAIL (สองIncomplete). Reproแรก `pwsh-8`ไม่ถึงmodelเพราะMATLAB `run`เปลี่ยนcwdก่อนpf_init_paths; แก้เฉพาะreprostartupแล้ว `pwsh-9`ยืนยันfailureเป็น `stability:gfm_selection:excessiveUniverse`: fixturefault-onlyละautomatic_gfm_switchingจึงdefaulttrueและเรียกexhaustiveselectorN9>4. Differentialตั้งfalseอย่างเดียวแล้วpublicnetwork-onlyconverged1. จึงแก้fixtureให้ระบุfalseตามเจตนาไม่มีmodechange ไม่ผ่อนselector/physicalgate. Realchronologyrunnerยังใช้lazysearch/manualall9เดิม.
- เริ่ม scopedregression `pwsh-10` (runtime,observation,source,snapshot/private,design,hybridLTE)หลังแก้fixture. ผล `pwsh-10`: runtime3/3, observation3/3, snapshot/private18/18, design7/7, hybridLTE3/3PASS; source5/6PASSและhashหนึ่งIncompleteเพราะใช้-nojvmกับjava.security (environment mismatch ไม่ใช่hashผิด). Source/hashเดิม `pwsh-4`6/6PASSด้วยJVM; เริ่มrerunruntime/observation/sourceด้วยJVM `pwsh-15`เพื่อมีfreshcombinedresult. Pythonbundledขาดh5pyจึงoracleยังไม่เริ่ม; ใช้Python312เดิมสำเร็จ3/3และpy_compileสามscriptsผ่าน. ไม่ติดตั้งdependencyหรือเปลี่ยนtesthash.
- เริ่ม shortstudyใหม่ `pwsh-16`จากrequest014041เดิม observe_voltage/horizon8.4sหลังruntime/private/LTEผ่าน. ใช้timestampfolderใหม่ ไม่เขียนrawเก่าทับและไม่ถือshortเป็น160/reclosecertificate.
- `pwsh-15`freshJVM runtime3/3+observation3/3+source/hash6/6PASS ไม่มีIncomplete. Scopedcodecheck `pwsh-17`: snapshot/policy/private/short/proberunner/audit/runtime0messages; observationมีหนึ่งstalesuppressionจึงลบเฉพาะcommentนั้น. hybriddriver35messagesและorchestratorALIGNหนึ่งอยู่บนunchangedlinesเมื่อเทียบdiff ไม่อ้าง0warningsทุกไฟล์.
- ตรวจreviewseamsเพิ่ม: runtimefixtureเปิดactualrateaccumulatorและassertonline_rate_log/series/jumpsเท่ากันระหว่างdefaultกับstudy รวมnondecreasingtimeและeventleft/rightcounts; เริ่มrollback/fixed/rate regressions `pwsh-19`. Auditเพิ่มexplicitstrict_snapshot_pass/actual_reclose_applied/production_certifiedfalse: ต้องมีappliedsg_recloseตรงactualtime ไม่ใช้sg_onหรือfinitesummaryแทน และstrictverifiedต้องผ่านDCenergyด้วย. เพิ่มnegativeaudittestให้summarySUCCESS/finiteแต่ไม่มีrecloseeventยังไม่verified. RealSGmechanical/synchronismไม่ได้แก้.
- `pwsh-19` isolationregression31/31PASS: runtime3,observation3,adaptive rollback5,fixed/default7,rateaccumulator13; ไม่มีIncomplete. `pwsh-20` strengthenedruntime/audit+observation6/6PASS; auditcodecheck0messages. Syntheticnegativeauditจงใจส่งweakfaultactualtimesใต้chronologyrequestZf=j.1จึงreconstructedKCL10.5169และไม่verified; `pwsh-22`สดเปรียบเทียบfreshdevicesกับequilibriumdevicesที่initialstateจริงให้KCL8.56e-14ทั้งคู่/I_diff0 จึงfalsifyสมมติฐานclosuremismatch ไม่เปลี่ยนproduction/auditKCLgate.
- `pwsh-16` shortstudyจบ8.4sจริง (`output/diagnostics/ne39_short_physical_events_20261010_032015_204/screen.mat`): SHORT_STUDY_COMPLETED, Vmin.905089825/Vmax1.12146555pu, finalinbandตั้งแต่sample7.40157s/span.998426s, energymax6.1945e-10pu-s. strictsnapshotไม่ผ่านvoltageบางsampleตามเจตนาstudy ไม่ลดcurrent/DC/f/KCL/LTE ไม่ใช้shortแทน160/reclose.
- เริ่ม `pwsh-23` pipelineตรวจshortartifact (eventcontinuity,current/DC/f/KCL/LTE/energy)ก่อนเรียกreal160จากrequest014041ผ่านproductionrunner. หากshortassertไม่ผ่าน160จะไม่เริ่ม; ใช้trip20/load50/fault85–85.15/line110/restore+SGrequest145/horizon160เดิม ไม่เปลี่ยนSGmodel/plantเพื่อกดยอด.
- `pwsh-23`shortindependentartifactchecksผ่านจริง: samples2984, snapshotscomplete/nonvoltagePASSทุกsample, actual5eventsตรงเวลาและx/u/contextcontinuityexact, timeไม่ลด, maxKCL9.8839e-10, maxLTE.9558, flooraccepted0, Imax.7113converterpu, Vdc.9917–1.0036, Idc.0290–.5174, f59.9155–60.0401Hz. เก็บ `verified_short_summary_20261010.mat`ในshortfolder. Peak1.12146555ที่bus35หลังfaultclear5.55s, recoverybracket5.55031158–5.55032001s; outsideleft-hold.000320010485s. Longestbusoutsideคือbus30หลังrestoreช่วง7.40001814–7.40157374s, .0015555971s (samplebrackets ไม่อ้างintersampleproof).
- Realchronologyเริ่มแล้วจริงจากpre-eventSG31+all9GFMrequest014041: `output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827/request.mat`, horizon160; `pwsh-23`ยังรัน ไม่รับรองcompletion/recloseก่อนrawจบ.

Review checkpoint: เป้าหมายคือเปลี่ยนvoltage-onlyจากstopเป็นobservationเฉพาะopt-in ไม่ใช่ลดdevice/numericallimits. ทางเลือกแค่postprocessrawไม่พอเพราะprivate/livegateเคยหยุดก่อนเก็บresponse; จึงใช้policyhelperร่วมและcanonicalkernelเดิม ไม่สร้างintegratorใหม่. Traceครบ runner→publicorchestrator→freshselector/equilibrium→privateสองpasses→adaptivehalfsteps→eventright→snapshot/DCledger→rawaudit. DefaultเทียบendpointAbsTol0และrateidenticalในruntimefixture, rollback/fixedpathsผ่าน; strict/unknown/currentnegativecasesผ่าน. Artifact/tmp/sourcearchivesและunrelatedworkingtreeไม่รวมcheckpoint. เฉพาะtaskfiles21รายการ; stageddeletions16รายการคงเดิม. ActualSGrecloseยังเป็นกลไกเดิมและรายงานแยก ไม่เปลี่ยนPm/rotor/synchronismเพื่อfakeclose.

Code checkpoint `8c891d6d7988a658bedbb099efa6652debe1bde7` commit/pushแล้วบนbranchเดิมขณะreal160ยังรัน; remotehashตรงHEAD. ใช้ `git commit --only`กับallowlist21ไฟล์ ไม่รวม16deletionsของผู้ใช้. ตรวจstageddiffSHA256ก่อน/หลังเท่ากัน `02F3EB7FB06F85983EF5E6CE1C50127D2552239096F43BFF2D773ED62128368C`; unrelatedtrackedworkingtreediffSHA256เท่ากัน `E58F4948499A07E61CA60BEC573141952F55A77ED0C90A1175EFB20E00BCF3AA`. Checkpointนี้รับรองimplementation/regression/shortevidenceเท่านั้น ไม่อ้าง160completionหรือactualrecloseก่อนjobจบ; ผลเต็มจะบันทึกcheckpointถัดไป.

### ผล real160 study-first — numerical/accepted-sample study จบ แต่ reclose ไม่ผ่าน (2026-10-10)

- สถานะนี้แทนข้อความยังรันด้านบน: parent เก็บผล `pwsh-23` แล้ว exit0, real chronology **160/160s**, converged1, elapsed2889.01s. Parentตรวจ [raw จริง](<C:/Users/User/Desktop/Power-flow/output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827/raw.mat>) อิสระด้วยh5pyและMATLAB audit/fullsummary ไม่ใช้exit0ลำพัง: **16051samples** เวลาไม่ลด, assessmentchecked16051/failed0, nonvoltagefailures0, UNKNOWN0, voltage-only169; study `STUDY_ACCEPTED_SAMPLES_VERIFIED`, strict_snapshot_pass=false, production_certified=false.
- Stepperเป็นadaptive ไม่ใช่fixed.025: dtmin6.103515488575795e-7s, dtmax.025000000000005684s, 1584uniquepositiveintervals; maxLTE.9445406089878208และfiniteทั้งหมด, flooraccepted0/rejected1. FullKCLmax4.78048659e-8, DCenergymax6.705978366464312e-10pu-s. Onlinef59.915312–60.0437892Hz, Imax.711335269converterpu; current/P/Q/DC/f/KCL/energy/LTE/synchronism gatesไม่เปลี่ยน.
- Voltage observation: Vmin.905089448pu bus15ที่85s, Vmax1.12146514pu bus35ที่85.15s; finalallbusinbandตั้งแต่sample145.00154178830223s/span14.998458211697766s. เป็นsampledobservation ไม่ใช่strictvoltagePASS/intersampleproofหรือdeadlineใหม่.
- Actualevents SGtrip20/load+20%50/fault85/clear85.15/line16–17trip110/restore145/sg_onrequest145 appliedtrueครบ; sg_reclose_timeout150 appliedfalse, actual_reclose_timeNaN, reclose_statusSYNC_TIMEOUT. Lastguard dV.20853053924627685>.05, df11.808209075419386pu>.001, dtheta87.51503400875991deg>10. Parentอ่านactualsc_f263ยืนยันofflinePe0/frozenpositivePm/sourceD0; finalclassicalSGomegaABS13.716532861548782pu/delta335581.688878963radคือofflinecoast **ไม่ใช่onlinegridfrequency**. ไม่implementgovernor/retune/resetrotor/ผ่อนsyncเพื่อfakeclose; ไม่อ้างrecloseหรือallmissionPASS.
- Privateaudit `STUDY_TRIAL_COMPLETE`: horizon4.19543709472991s, coarse1798/fine3596stepsทั้งสองรอบครบ; globalrefinement5.574331207430783e-6<1e-5/coverage1798, energy1.81134e-10/4.52779e-11pu-s. เป็นprivateevidence ไม่ใช่actualreclosecertificate. MATLABfullsummaryassertionsผ่านและบันทึก [full summary](<C:/Users/User/Desktop/Power-flow/output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827/verified_full_summary_20261010.mat>), แต่ outerfinalchecker `pwsh-74` **FAILED** ที่line20 `dissimilar structures` ขณะappendresource ไม่ใช่physicaltrajectoryFAIL; parent `pwsh-87`ยืนยันfieldlessstructschema. Existingcheckeragentกำลังแก้; finalper-device/private-assertchecker acceptanceยัง **PENDING** ไม่อ้างผ่านจากชื่อartifactหรือผลfullsummaryแทน.
- คำสั่งล่าสุดให้subagentsเป็นprimaryimplementers/parentเป็นPM-reviewer supersedesno-subagentเก่า; ใช้workingtreeหลักเดิม ไม่สร้างworktree/newagentsในงานต่อชุดนี้. ผู้ใช้ขอadaptivecap.001สำหรับถัดไป แล้วสั่ง “เอาตัวนี้ให้ผ่านก่อนก็ได้”: จบ/ตรวจcurrent.025ก่อน; **.001ยังไม่รัน** ไม่เปลี่ยนกลางรอบหรืออ้างfine-runแล้ว. Code8c891d6pushedแล้ว; factualledgerนี้ยังไม่commit/push ต้องรอfinalcheckerผ่านและparentreview. รักษา16stageddeletions/unrelatedworkและprotectionhashesเดิม; ไม่มีproduction/helpereditsจากผู้เขียนrecord.

### Superseding: final checker ผ่านแล้ว — device/mission checks verified (2026-10-10)

หัวข้อนี้ **supersede** สถานะ PENDING ของ finalchecker ในหัวข้อก่อนหน้า (บรรทัดบนยังเป็นประวัติจริง ณ เวลานั้น ไม่ลบ) และเป็นคำแถลงauthoritative ล่าสุดของ record นี้.

- Main final checker: parent รันคำสั่งผู้ใช้เองแบบ exact จบ **exit0 เมื่อ 2026-10-10 ~04:50:26**. Assertions ทั้งหมดใน [final checks:15–86](<C:/Users/User/Desktop/Power-flow/tmp/ne39_study_final_checks_20261010.m#L15-L86>) และ [full summary:49–59](<C:/Users/User/Desktop/Power-flow/tmp/ne39_full_study_summary_20261010.m#L49-L59>) ผ่าน; saveเกิดที่ [final:88](<C:/Users/User/Desktop/Power-flow/tmp/ne39_study_final_checks_20261010.m#L88>) และ [full summary:61](<C:/Users/User/Desktop/Power-flow/tmp/ne39_full_study_summary_20261010.m#L61>).
- Artifacts ที่ยืนยัน presence/size ใน [real-160 folder](<C:/Users/User/Desktop/Power-flow/output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827/>): [verified device/mission checks](<C:/Users/User/Desktop/Power-flow/output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827/verified_device_and_mission_checks_20261010.mat>) 1532272bytes, [full summary](<C:/Users/User/Desktop/Power-flow/output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827/verified_full_summary_20261010.mat>) 1368256bytes (04:50:26 overwrote รุ่น 04:25:11), [chronology audit](<C:/Users/User/Desktop/Power-flow/output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827/chronology_audit_20261010_045023_330.mat>) 34965136bytes. [raw.mat](<C:/Users/User/Desktop/Power-flow/output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827/raw.mat>) ไม่ถูกเขียนทับ: 557167983bytes, mtime04:18:18, SHA256 `ED4670EB853E4C29AAD426985F9BCA382D78004C61E947AB9B0C332DA696E85E` เท่าเดิม.
- ตัว checker script: SHA256 `745B85718494DDD6F3921CD7C7A579AE8D5CBE4E4C7425C8E50494956A477B45` (ไม่เปลี่ยนหลังรอบสุดท้าย). Artifact ที่ผ่านการยอมรับล่าสุด: [verified_device_and_mission_checks_20261010.mat](<C:/Users/User/Desktop/Power-flow/output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827/verified_device_and_mission_checks_20261010.mat>) SHA256 `71DF94CBD2EFA9CA231AA2D91891500FB0532204B06AFC51A19176312D10A16F`. Remote `origin/checkpoint/ne39-160s-20261009` ยืนยัน **`8c891d6d7988a658bedbb099efa6652debe1bde7`** ก่อน ledger commit ที่กำลังจะมาถึง; **ยังไม่มี commit ใหม่** ณ เวลาที่เขียน — parent จะ review และ commit ledger-only. Defect `fieldless struct` ที่เคยหยุด append resource **แก้แล้ว**: [L20](<C:/Users/User/Desktop/Power-flow/tmp/ne39_study_final_checks_20261010.m#L20>) สร้าง `rec` struct ตรง ๆ, [L26](<C:/Users/User/Desktop/Power-flow/tmp/ne39_study_final_checks_20261010.m#L26>) เป็น `if isempty(...)` first-direct/subsequent-append, [L28](<C:/Users/User/Desktop/Power-flow/tmp/ne39_study_final_checks_20261010.m#L28>) assert9IBR. เป็น schema/harness defect ไม่ใช่ physics; root cause เคย bounded-repro ไว้ที่ `pwsh-87` และ parent fresh run3 รอบนี้ยืนยัน acceptance. **ไม่ใช้** รอบ `pwsh-74`/`pwsh-90` เป็นหลักฐานผ่าน.
- ไม่มี duplicate/process residue: ก่อนรัน checker ของตัวเอง parent ตรวจแล้วว่า PID27276/6084 ไม่มีอยู่และไม่มี MATLAB; `pwsh-90` ของ session ก่อน **unavailable** และ outcome **ไม่ถูกเก็บ ไม่ assume ว่าผ่าน**. Parent ไม่รันซ้ำงานที่ยังค้างและไม่ terminate process ใด. Final process snapshot ล่าสุด: **NO_MATLAB_PROCESSES_REMAIN**; [raw.mat](<C:/Users/User/Desktop/Power-flow/output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827/raw.mat>) และ checker-script hashes ไม่เปลี่ยน.

**Device/mission checks ที่ผ่านในรอบนี้** (เทียบเท่าหลักฐาน accepted-sample ไม่ใช่ production certificate):

- P/Q/I/DC source constraints ของ IBR ทั้ง9 ตัวผ่านตาม [L82–87](<C:/Users/User/Desktop/Power-flow/tmp/ne39_study_final_checks_20261010.m#L82-L87>); [L28](<C:/Users/User/Desktop/Power-flow/tmp/ne39_study_final_checks_20261010.m#L28>) นับครบ9 records. Private trial สอง passes/`STUDY_TRIAL_COMPLETE` horizon4.19543709472991s, refinement5.574331207430783e-6, coverage1798, energy1.8113419e-10/4.52778805e-11pu-s, slip7.2077392/7.20768481deg, `commit_authorized=false`.
- Study160s จบ: samples16051, `STUDY_ACCEPTED_SAMPLES_VERIFIED`, converged, elapsed2889.01s, nonvoltage0/UNKNOWN0, voltage-only169; strictvoltageFALSE, `production_certified=false` ตามเดิม.
- Adaptive: dtmax.025 (ไม่ใช่ fixed), LTE สูงสุด.9445406089878208 finiteทั้งหมด, flooraccepted0/rejected1; KCLmax4.78048659e-8, DCenergymax6.705978366464312e-10pu-s; f59.915312–60.0437892Hz; Imax.711335269converterpu. Vmin.905089448pu bus15ที่85s, Vmax1.12146514pu bus35ที่85.15s; finalinbandตั้งแต่145.00154178830223s/span14.998458211697766s.
- Scheduled events applied ครบ7: trip20/load50/fault85/clear85.15/line110/restore145/sg_onrequest145. timeout150 `applied=false`, `actual_reclose_time=NaN`, `SYNC_TIMEOUT`; ยังไม่ใช่ actual reclose.

**Voltage excursions ของ real160 (10 records, ไม่มี censored; เท่ากับ 10 บรรทัด `V_EXCURSION` ที่ checker พิมพ์ออกมา)**: bus35 entry85.15, recoverybracket **85.1503153653–85.1503258043s**, duration **0.000325804342s**; longest bus30 entrybracket **145.000043459–145.000051687s**, recovery **145.001527584–145.001541788s**, duration **0.00149010081s**. แยกจาก bracket/duration ของ short 8.4s ในหัวข้อก่อนหน้าให้ชัด: short bus35 recovery5.55031158–5.55032001s/.000320010485s และ bus30 7.40001814–7.40157374s/.0015555971s. เป็น sampled brackets/left-hold ไม่ใช่ intersample proof, settling certificate หรือ protection setting. (จำนวน 169 ที่เรียกว่า voltage-only ในหัวข้อบนคือจำนวน **samples** ที่ strict voltage ไม่ผ่าน ไม่ใช่จำนวน excursion records.)

**Supplemental event/contract checks — resolved (parent ยืนยัน `pwsh-17` exit0)**: supplemental ที่รันก่อนหน้านี้ **assert ผิด contract** ไม่ใช่ lint problem; ปิดครบแล้วและ **ไม่มีการแก้ helper หรือ production**:

- `pwsh-13`: lint/codecheck ผ่าน `CHECKCODE_COUNT=0` (lint0 ผ่านจริง ไม่ได้ขัดแย้งอะไร) แต่ **supplemental assertions ผิด contract** จึง assertionFAIL. **ไม่ใช่ physics failure และไม่ใช่ lint failure**: เป็น harness assumptions ที่ผิดสองข้อ — สมมติว่า trip ไม่เปลี่ยน u (จริงคือ log input before/after แล้ว commit `u_new`) และสมมติว่า **ทุก event มีสอง samples left/right** (จริงคือ scheduled pairs ใช้ Tx เดียวกัน และ timeout150 เป็น 1 continuous sample). เก็บไว้เป็น breadcrumb พร้อมคำอธิบาย ไม่ลบ.
- `pwsh-16` diagnosis exit0: instrument แล้วพบว่าสมมติฐาน trip-unchanged ผิดจริง — [ts_simulate_ibr_hybrid.m](<C:/Users/User/Desktop/Power-flow/+stability/ts_simulate_ibr_hybrid.m>) [L750–768](<C:/Users/User/Desktop/Power-flow/+stability/ts_simulate_ibr_hybrid.m#L750-L768>) log input before/after แล้ว commit `u_new` จริง (actual delta .97943806046841786) และ [L1268–1280](<C:/Users/User/Desktop/Power-flow/+stability/ts_simulate_ibr_hybrid.m#L1268-L1280>) timeout เป็น status log เท่านั้น ไม่มี transaction.
- `pwsh-17` correct actual-contract check **exit0**: `RELOADED_FINAL_ARTIFACT_AND_CONTRACT_CORRECT_EVENT_CHECKS_PASS`, resources=9, samples=16051, roots=98, horizon=4.1954370947299102. Assertions ผ่าน: trip u bind exact logged before/after + actual-redispatch witness; network/request events x/u continuity; scheduled pairs **same-Tx** และ left/right exact x; timeout nontransactional **1 continuous, tx0 unapplied**; ทุกค่า finite.
- ขอบเขตที่ตรวจ: contract ที่รันนี้เท่านั้น. **ไม่อ้าง event-context continuity เกินนั้น** — private trip context binding ถูกตรวจแล้วใน main checker ([final checks:46–47](<C:/Users/User/Desktop/Power-flow/tmp/ne39_study_final_checks_20261010.m#L46-L47>)) ไม่ใช่ผลของ `pwsh-17`.
- สถานะ: MATLAB jobs ทั้งหมด settled และ process snapshot สุดท้าย **NO_MATLAB_PROCESSES_REMAIN**; ไม่มี final process check ค้างอยู่.

คำสั่ง exact (postprocessing เท่านั้น — **ห้ามรัน real160 ซ้ำ**; ไม่แตะ process ใด):

```powershell
& 'C:\Program Files\MATLAB\R2025a\bin\matlab.exe' -nojvm -batch "pf_init_paths(); addpath(fullfile(pwd,'tmp')); ne39_study_final_checks_20261010('C:/Users/User/Desktop/Power-flow/output/diagnostics/ne39_voltage_dispatch_run_20261010_032919_827');"
# เรียก full summary + chronology audit ในตัว; save verified_device_and_mission_checks_20261010.mat
# อย่าเรียก tmp/ne39_study_verify_and_run_20261010.m: นั่นเริ่ม real chronology ใหม่
```

ยังไม่มี Pm/change, reset rotor, fake close, sync relaxation, mitigation ใหม่ หรือการรัน adaptive cap.001. 16 staged deletions และ unrelated work คงเดิม; protection hashes `02F3EB7F…368C` และ `E58F4948…F3AA` ไม่เปลี่ยน. Git: ยังไม่มีการ mutate/index/commit/push จากงาน record นี้; checkpoint ถัดไปยัง pending parent review/commit ณ เวลาที่เขียน — เอกสารนี้ไม่ประดิษฐ์ commit hash ใหม่. Process snapshot สุดท้าย **NO_MATLAB_PROCESSES_REMAIN**; parent จะ review แล้ว commit **ledger-only** (ไฟล์นี้) เป็นขั้นถัดไป.
