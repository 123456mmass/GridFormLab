# แผน QA อิสระ: NE39 certified mode restoration และ operating-point recovery

วันที่ 2026-10-12; **PLAN ONLY** — อนุมัติรอบนี้เฉพาะการแก้เอกสาร ไม่ใช่ implementation/tests/simulation
ไม่แก้ source ไม่รัน MATLAB ไม่ติดตั้ง reader ไม่ stage/commit/push ไม่ cleanup worktrees และไม่แตะ IEEE14 PDF/TEX
Baseline: `checkpoint/ne39-160s-20261009` @ `f79bead`; kernel WIP 27+/1-, probe 33+/1-; diff blob hash `62f1a21054a2e0e1d249ea4516427d82bb9a55a6` ไม่ใช่ raw checksum

## 1. เป้าหมายและระดับหลักฐาน

SG31 + 9 IBR: normal ก่อน20 s, trip20, fault bus16 `Zf=j0.1` 60–60.15, return request100, horizon160. Close จริงเป็นผล guard/dwell
เป้าหมายคือคืนGFLให้มากที่สุด เหลือGFMเท่าที่จำเป็นให้น้อยที่สุด และสมดุลจริงภายใต้safety/certification/recoverygates; ไม่หยุดที่mixed setแรกที่ผ่านและไม่อ้างglobalminimumจากboundedsearch. Initial/final mix เลือกจาก evaluated/certified evidence **ไม่บังคับ all-nine GFL หรือ9→0**. Residual GFM ต้องมี evaluated justification และ recovery evidence; missing coverage ไม่ใช่ success. `SUCCESS`, `converged` หรือชื่อโหมดไม่แทน physical certificate

| ระดับ | ความหมาย |
|---|---|
| Source-verified | อ่าน implementation/fixture ที่อ้าง ไม่ใช่ผลรัน |
| Artifact-verified | ตรวจ filesystem/text ของ artifact จริง ไม่ขยายความเป็นข้อมูลภายใน MAT |
| Owner-reported | ตัวเลขจากการส่งมอบ ยังไม่ได้อ่านยืนยันในรอบนี้ |
| Unverified / pending | ยังไม่มี reader, result manifest หรือ approval ที่จำเป็น |

[หลักฐานเดิม](../output/diagnostics/ne39_reclose_applied_probe_20261012_024613_920/):

| ระดับ | สิ่งที่ทราบ |
|---|---|
| Artifact-verified | raw1,850,924,388 B; cache549,979 B; request2,012,152 B; audit171,520 B |
| Artifact-verified | progress.log บันทึก applied trip20, fault60, clear60.15, request100, reclose119.5200; progress สุดท้าย155.1355 |
| Owner-reported | close119.520000610, right KCL4.845e-10, accepted31,448, rejected steps7, horizon160, final9GFM/no GFL return, 0 matching rows ต่อ8GFM target |
| Owner-reported | simulation~9,913 s; cache load~0.03 s; continuity/guard/SG bounds/current/private-trial audit และ selector summary |
| Unverified | ข้อมูลภายใน MAT, per-bus voltage, final recovery, metric/provenance consistency และ load timing จริง |

Python ที่ตรวจด้วย `python -I` ไม่มี h5py/scipy. **ไม่ได้อ่าน audit/cache/raw MAT ในรอบนี้** และไม่ติดตั้งเพิ่ม. ถอนคำกล่าวอ้างเดิมว่า QA อ่าน MAT ด้วย h5py แล้ว VERIFIED
progress `rejects=0` ไม่ยืนยันยอด rejected steps สุดท้าย; progress จบ155.1355 ไม่ยืนยัน160. Candidate evaluation count กับ integrator rejection countเป็นคนละตัวนับ; ห้ามปน9กับ7

### Voltage/frequency ที่รายงานเดิม — ยังไม่ยืนยันจาก MAT

ฉบับเดิมระบุ strict failures64, nonvoltage PASS, Vmax1.12836 และ out-of-band ที่60.150000–60.150404; Vmin0.90704; final f~60.0279 Hz และ late ROCOF~8.6e-5 Hz/s. เก็บเป็น **owner-reported/unverified** ไม่ใช้ตัดสิน PASS/FAIL ใหม่หรือแก้รายงานนอก scope

- ถ้า interval ถูกต้อง ระยะคือ0.000404 s =0.404 ms ไม่ใช่308 ms
- `t_clear` right-limit เป็น **post-clear**. Interval `[60.15,119.52)` รวมช่วง violation ที่รายงาน จึงห้ามเรียก interval ทั้งช่วงว่า violation-free
- ต้องอ่าน per-sample/per-bus, transaction-side และ decomposition จริงก่อนยืนยันว่าทั้ง64เป็น voltage-only, ไม่มี dip หรือช่วงใดปลอด violation. Aggregate counts ไม่ได้ให้ identity ของแต่ละ failure และ failures อาจมีหลายหมวดพร้อมกัน
- Strict voltage status เดิมต้องคงตามหลักฐาน/contract เดิม. **ไม่มี retrospective10ms/+M1 waiver** เพื่อทำ runเก่าผ่าน. Observe-voltage trial completion ไม่เท่ากับ strict certificate

## 2. Source findings และผลต่อ QA

| Source | สิ่งที่ตรวจพบ / requirement |
|---|---|
| kernel3895–3969 `online_ibr_severity` | SI=clip(.5Jv+.5Jf), Jfใช้COI; ยังไม่มี weighted rate terms |
| kernel1312–1327/1297–1307 | rate policy เป็น global release gate และเขียนทับรายตัว `release=current_gfm`; opt-in ต้องไม่ลบ per-GFM eligibility |
| `ne39_rate_policy.m:60–88` | hard rate ceilings/outward predictionแยก; `down=all(s<si_off)&&safe&&~prediction`; proposalไม่ใช่commit |
| kernel253–276/1820–1853 | exact landingใช้ severity dwell; policy override threshold/dwellได้; ต้องresolve thresholds/clocksเดียวกัน |
| kernel4483–4539 | device frequency accessor→`EtFcsRateAccumulator.step`→alignment→policy; caller resetเมื่อepoch/duplicate |
| `EtFcsRateAccumulator.m:153–215` | SG/GFM ROCOFใช้active RHSเมื่อมี; GFL causal frequency difference; ROCOV causal/filter; mode/onlineเปลี่ยนepoch; duplicate right-limitปรับstencilฐาน ไม่กินเวลา |
| kernel97–111 | initialization warmup.02/tau.02; policy-enabledต้องpositive tau. Standalone accumulator alpha.2/optional tau เป็นคนละcontract |
| kernel500–504/4435–4443 | midpoint appendใช้record_rates=false; **ห้ามzipdecision/rate logกับres.t** |
| probe95–112/lazy252–269,343–358 | SG_ON pin9, budget4, stop-firstจำกัดcoverage; ไม่มี8target rowไม่ใช่evaluated instability |
| kernel2963–3146/3756–3837 | authenticate candidateเต็มภายในhelper แต่คืนtarget/audit/ok; study guardปฏิเสธหลังKCLเพราะtransitionEvidenceMissing |
| `certify_ne39_transition.m:33–61` | ready/feasibleจริง, finite omega<0; suppliedphysical spectrum finite/nonempty/stable และ`omega>=max(real(lambda))` |
| kernel3373–3383 + support rankers | SG_OFF strictsubset/supersetไม่จำกัดdelta1; legacyอาจmulti-device. SG_ON authenticated one-stepบังคับหนึ่งตัวที่3782–3789 |
| runner388–410/503–518 | weightedoptionsยังต้องforward; selector cacheไม่อยู่forward list |
| demo53–55/256–259 + writer102–124 | demoโหลดinfoโดยไม่ตรวจSHA; writerassignmentหลีกcellstructarray แต่raw fallbackยังใช้cell-valued constructor |

Gauge fixture `tests/test_ne39_reclose_dynamic_sssa.m:114–135` ตรวจ common rotating directionผ่านquotient maps ไม่ใช่ข้ออนุญาตให้ตัดทุกangle stateทิ้ง. Fixtureonlineใช้initial9GFM; ไม่เป็นNE39all-GFLendpointproof. `test_ibr_sg_on_all_gfl_equilibrium`เป็นIEEE14 SG+4IBR ไม่ใช่NE39

`actual_reclose` assignmentและ`compute_tdown`เป็นตำแหน่งที่ต้องตรวจcaller lifecycle. จำนวนassignmentในsourceไม่พิสูจน์จำนวนexecutionหรือการรองรับrecloseซ้ำ; ต้องมีduplicate-request/deadlinefixturesก่อนอ้างsingle-close/re-armcontract
IEEE14 `diagnostic_overrides(0.05)`ตั้งrequest/t_end0.05จริง แต่sourceไม่พิสูจน์ว่าเป็นroot causeของหกfailures. ต้องมีper-name diagnosticsและfixtureที่asserteventsจริง

## 3. Recovery contract — pending approval ก่อน outcomes ใหม่

**ถอน freeze timestamp06:51 และnumeric acceptanceที่ไม่มีapproval**. ไม่ใช้runเก่ามาเลือกtolerancesให้ผ่าน. Studyowner+Leadต้องอนุมัติและrecord revisionก่อนเห็นoutcomesใหม่

ต้องfreeze:
- certified initial/final mixed endpoints, context/topology/dispatch/reference provenance; P/Q/V targetsจากequilibriumที่ใช้จริง ไม่สมมติinitialall-GFL
- numeric tolerancesและหน่วยต่อquantity: P/Q/V/f, per-deviceROCOF/ROCOV, physical derivatives, fullKCL, current/MVA, cumulativeDCenergy, SG Psv/Pm/field/source bounds
- settling window, samplecoverage/minimumcount, event/mode restrictionsและdeadline. `[140,160]`ไม่ถือว่าapprovedwindowโดยเอกสารนี้
- physical derivativesในproperrotating/gaugecoordinates: removeเฉพาะcommon gaugeที่พิสูจน์แล้ว ตรวจrelativeangledynamicsด้วย
- recovery fรายdeviceและCOIdiagnostic; ROCOFmethodต้องตรงactiveRHS/causalGFLcontract; bus/deviceROCOVต้องระบุmethod/filterชัด
- แยกcontinuous/event-left/event-rightKCLและstrictvoltageevidence; ตรวจsource/ratingbasisจริง

P/Qนอกtargetพร้อมคำอธิบายdroop **ไม่ใช่PASSอัตโนมัติ**. เปลี่ยนtarget/acceptanceได้เฉพาะprospectiveapprovedrevision. ยังไม่อ้างproduction/hardwarecertification

## 4. FIRST implementation slice — controlled actual-decision tests

**Weighted supervisorเข้าgateจริง+controlleddecisiontestsก่อนcoverage discovery**. ไม่ใช่logging-only/helper-only; **ไม่ต้องรอphysical9→8commit**. Physicaltransitioncertificationเป็นขั้นถัดไป

Proposedopt-in: weights`[.35,.35,.15,.15]`, bases`[.10pu,.50Hz,1Hz/s,1pu/s]`; **PROJECT_DERIVED STUDY DESIGN, unvalidated**
`SI=clip(wV*JV+wf*Jf+wrf*JROCOF+wrv*JROCOV,0,1)`; clipหลังรวม; localf/localROCOFdeviceเดียวกัน. Omissionต้องรักษาlegacyCOI`[.5,.5,0,0]`เป็นregressionrequirement ไม่ใช่พิสูจน์byte-identicalแล้ว

Fixedtestconfig: si_off.35/si_on.65, hardrates1, predictionhorizon.25, Vband.9–1.1, fband59.5–60.5; validbaselineสะสมoffdwellจนactualrelease=true ก่อนเปลี่ยนเฉพาะrate ณ advancingtimestamp

| Test | Fixedsignals | Ratechange | SI | Actualdecisionexpected |
|---|---|---|---|---|
| ROCOF | V=Vhealthy=1,f60.35,rv0 | rf0→−.8 | .245→.365 | projectedf60.15safe; hard/predfalse; release true→hold/resetdwell |
| ROCOV | V1.07,Vhealthy1,f60.05,rf0 | rv0→−.6 | .28→.37 | projectedV.92safe; hard/predfalse; release true→hold/resetdwell |
| Legacycomparison | sameforcing,separatelegacyconfig | samepair | no rate contribution | independentlegacyassertions ไม่เปลี่ยนweightsกลางratepair |
| Hard/predictionnegatives | controlledunsafe/rate/predictioninput | crossedlimits | SIไม่กลบguard | refusalตามguardจริง |

ROCOVbaselineรวมf contribution.035ด้วย จึงไม่ใช่.245→.335. SIอยู่hysteresisbandหลังratechange ไม่ใช่augmentationexpectation. Formula/calculationอย่างเดียวไม่พอ ต้องassertcanonicalSIที่actualgateconsume

Additionaltests: validateweights/bases/shapes/unknownoptions, healthyPFatomicpair, runnerforwarding, omissionlegacyCOI, threshold/dwellconflicts, oneeligibleGFMเมื่ออีกตัวhighSIแต่hardsafe, missing/invalid/warmupratehold/reset, callerจริงepoch/mode/online/duplicateatomicrightlimits, rejected-onlynonconsumption

## 5. Alignment และ test gate

- Canonicalsampleเดียวเข้าล็อกและactualSG_OFF/SG_ONgates; aligntimestamp/device/epoch/transaction-side ไม่recomputeคนละfrequencybasis
- Policyduplicate-timeunitbehaviorกับcallerresetเป็นคนละชั้น ต้องทดสอบทั้งคู่
- Midpointsไม่มีrateentry; rightlimitsอาจtimestampซ้ำ. ห้ามassertloglength=res.tlengthหรือelement-wisezip
- พิสูจน์gateอ่านlatest**eligible accepted**sampleด้วยcallerfixture; อย่าclaimไม่มีlagเพราะชื่อlog. Rejectsampleห้ามกินrate/dwellhistory
- Decision/trialaudit `commit_authorized=false`ไม่grantauthority; callerต้องผ่านauthentication/KCL/private destinationtrialก่อนpublish

| Gate / Owner | Acceptance | Dependency / stop |
|---|---|---|
| W0 Studyowner+Lead | opt-in design/contractsapproved | ไม่มีapprovalไม่implementation |
| W1 Supervisorowner | bothratepairsเข้าactualdecisionpathและreleaseassertionsผ่าน | FIRSTก่อนcoverage; log-onlyไม่ผ่าน |
| W2 QA | invalid/legacy/alignment/clock/eligibility/callerplumbingผ่าน | unresolvedclock/unknownbaselineไม่ผ่าน |
| C Coverageowner | certifiedinitial/endpointsและreachablepermittedpath; residualevaluated | ไม่mandatory9→0; missing/budget/inconclusiveไม่ใช่success |
| T Transitionowner | fullauthenticatedcandidate/input/context, mappedrightstate, KCL+SG_ONprivatetrialก่อนpublish | ห้ามfakeflags/removeguard/truncatehorizon; failedtrialไม่publish |
| E Integration+QA | shortfixturesมีappliedeventsจริงในhorizon, expectedrefusal, per-namebaseline | eventนอกhorizonไม่ผ่าน |
| F Runowner | full160chronology+mode/transactionevidence | C/T/E+approvedrecoverycontractก่อนlongrun; ไม่ขยายhorizonเงียบ |
| G QA | recoveryผ่านapprovedcontractและendpointตรงevidence | failureรายงานตามจริง; ไม่มีretrospectivewaiver |
| H Evidenceowner | both-pathcache/rawroundtrip+provenance/stalenesstests | replayไม่ใช่newrun/certificate |

Kernel/runnersinglewriter; serializeW1ก่อนcoverage/transitionที่แตะไฟล์ร่วม. GateW1ไม่ต้องพึ่งphysicalcoverage; fullrunต้องพึ่งทุกphysicalgate

## 6. Historical regression — owner-reported ไม่ใช่ผลรันรอบนี้

| Suite | Functioncountที่ตรวจ | Historicalreportedresult |
|---|---|---|
| Scopedplant/wiring/dynamicSSSA | 14+13+3=30 | 30Passed/0Failed/0Incomplete |
| Handback3files | 2+2+5=9 | 9Passed |
| IEEE14workflow | 20 (`f79bead`/`3cbb7ea`เช่นกัน) | **20total/14Passed/6Failed/1Incompleteflag** |
| Combinedhandback+workflow | 9+20=29 | **29total/23Passed/6Failed/1Incompleteflag** |

IncompleteflagอาจoverlapFailed; ห้ามบวกเป็น21/30หรือเขียน20Passedสำหรับworkflow. Functioncountไม่ใช่testresult. ยังไม่มีper-namebaselineของหกfailures จึงไม่claimno-regressionหรือequivalence
Futurebaselineต้องเก็บname, Passed/Failed/Incompleteflags, failureid, diagnostics, code/env/requestprovenance ก่อนเปรียบเทียบpostchange. ผลaggregatedคนละsuiteแทนกันไม่ได้

## 7. Cache/demo QA requirements — future implementation

| Requirement | Currentfinding / futuretest |
|---|---|
| Content | writerคัดลอกtraces/head/config/appliedeventKCLจริง แต่ยังไม่มีweighteddecision/path/recoverycontractครบ; ตรวจschemaจากsourceไม่ใช่MATdatasetlist |
| Provenance | source_rawpath/created_at/elapsed/selectorfpมี; code/request/rawhashและschemaversionยังไม่มีในwriter |
| Staleness | demo53–55โหลดinfoตรง ไม่ตรวจSHAตามcomment20–24; futurehash/request/state/schema validation+refusaltests |
| Bothreadpaths | cachedwriterใช้assignment; **rawfallbackdemo256–259**cell-valuedsg_plant_state_namesอาจสร้างstructarray ต้องแก้และทดสอบทั้งสองpathภายหลัง ไม่กล่าวwriterแก้ครบแล้ว |
| Roundtrip | เทียบarrays/scalarsเฉพาะfieldที่copy/normalizeจริง; includeoptional/missingfields, rejectiondetailsและcellshape; invalidationสำหรับraw/request/hash/schema/statechanges |
| Selectorcache | แยกจากreplaycache: runnerforwarding+adapter output`fp`/input`state_validity_fingerprint`, roundtripและinvalidationตามcoverageplan |
| Presentation/performance | ประกาศcachedreplay/notlive/production_certified=false; loadtimingcold/warmต้องวัดจริง ไม่ใช้0.03sเป็นverifiedbenchmark |

## 8. Future evidence/reportงานนอกscope

หลังได้reader/resultschemaที่ทำซ้ำได้ ให้ตรวจMATmetrics/per-busvoltage/left-rightside/failuredecompositionจริง. ก่อนนั้นห้ามใช้owner-reportedตัวเลขแก้success/defectreportว่าverified
การแก้ `docs/ne39_reclose_160s_success_report_20261011.md` หรือ `docs/project/defects/2026-10-11-sg-handback-gate-unsatisfiable.md` ต้องมีscopeapprovalแยก. ไม่แตะในรอบสี่แผนนี้; IEEE14PDF/TEXไม่แตะ

## 9. Dependencyและข้อสรุป

`Approveddesign → W1actualweighteddecisions → W2QA → coverage/endpoints → authenticatedtransition → shortfixtures+baseline+recoveryfreeze → full160 → recovery/evidencereview`

ยืนยันได้รอบนี้: sourceblockers, artifactsizes, progressreclose119.5200 และข้อจำกัดreader. ยังไม่ยืนยันMAT/horizon/finalmix/recovery/no-regression. ไม่มีimplementationหรือnumericaltestเริ่มจากเอกสารนี้

ดู [แผนรวม](ne39_gfl_restoration_continuation_plan_20261012.md), [Supervisor](ne39_supervisor_design_plan_20261012.md), [Coverage](ne39_selective_coverage_plan_20261012.md)
