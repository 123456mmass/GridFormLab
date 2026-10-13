# NE39 weighted supervisor — design / implementation plan

วันที่ 2026-10-12; **PLAN ONLY**. รอบนี้แก้เอกสาร ไม่แก้ source/ไม่รัน MATLAB/tests/simulation/ไม่ commit.
Baseline checkout `checkpoint/ne39-160s-20261009` @ `f79bead`; WIP kernel27+/1-, probe33+/1-; diff blob fingerprint `62f1a21054a2e0e1d249ea4516427d82bb9a55a6` ต้องรักษา ไม่ใช่raw checksum.

## 1. เป้าหมายและลำดับ

SG31+9IBR; trip20, faultbus16 j0.1 60–60.15, request100, horizon160. เป้าหมายคือคืนGFLมากที่สุด เหลือGFMเท่าที่จำเป็นให้น้อยที่สุด และสมดุลจริง ภายใต้safety/certification/recoverygates. Initial/final mixเลือกจากcertified evidence ไม่บังคับall-GFL/9→0. Residualต้องมีevaluated justification+recovery ไม่ใช่missingcoverage. All9GFMที่ค้างเพราะrestorationขาดไม่ใช่success. Boundedsearchไม่พิสูจน์globalminimum.

**งาน implementation แรกหลังอนุมัติแยกต่างหาก:** weighted supervisorที่ใช้ตัดสินจริง พร้อมcontrolled decision tests ก่อนcoverage discovery. ไม่จำกัดงานแรกเป็นlogging/forwardingและไม่ต้องรอphysical9→8commit. Physical transaction/trialเป็นขั้นถัดไป.

## 2. Source findings ที่ตรวจ

| Source | สิ่งที่มีจริง |
|---|---|
| kernel3895–3969 `online_ibr_severity` | clip(.5Jv+.5Jf); Jfใช้COI ไม่มีrate-weightedterms |
| kernel1312–1327 | perdeviceSI/dwell สร้างrelease แล้วrate-enabledเขียนทับ`release=current_gfm` |
| `ne39_rate_policy.m:60–88` | hardrates/outwardpredictionแยก; globaldown=all(SI<off) AND safe; proposalไม่ใช่commit |
| kernel253–276,1820–1853 | exactlandingใช้severitydwell; policyoverride threshold/dwellได้แยก |
| kernel4483–4539 `record_accepted_rates` | device accessor→EtFcsRateAccumulator.step→alignment→policy; epoch/duplicate resetcaller |
| kernel500–504 | midpoint append record_rates=false; rate/decisionlogไม่ต้องยาวเท่าres.t |
| runner388–410 | healthyPFatomicpairและoptionwhitelist; weightedoptionsต้องforwardจริง |

Accumulator standalone defaults warmup.02s/ROCOValpha.2 และoptionaltau; kernel rate initialization97–111 **ตั้งtau.02และrequirepositiveเมื่อpolicyenabledอยู่แล้ว**. ต้องเก็บทั้งสองcontractตามจริง ไม่เพิ่มการบังคับtauใหม่ให้legacy pathsโดยเงียบ.
SG/GFM ROCOFมาจากactiveRHSเมื่อมี; GFL causaldevicePLL difference. ไม่อ้าง`et_fcs_causal_rates`เป็นcallerจริง.

## 3. Proposed opt-in study design

`SI_i=clip(wV*JV_i+wf*Jf_i+wrf*JROCOF_i+wrv*JROCOV_i,0,1)`

| Terms | นิยาม/base |
|---|---|
| JV | abs(V−Vhealthy)/.10pu |
| Jf | abs(flocal−60)/.50Hz |
| JROCOF | abs(localROCOF)/1Hz/s |
| JROCOV | abs(localROCOV)/1pu/s |

Weights `[.35,.35,.15,.15]`: **PROJECT_DERIVED STUDY DESIGN, unvalidated**, ไม่ใช่relaysetting. Opt-in frequencybasis explicit localf/localROCOFของdeviceเดียวกัน; COI diagnostic. Clipหลังรวม ไม่clipแต่ละterm.

Omissionต้องรักษาlegacy two-termCOI `[.5,.5,0,0]` และเดิมbehavior; เป็นregression requirement **ไม่ใช่claimว่าbyte-identicalพิสูจน์แล้ว**.
Validation: finite realnonnegativeweights sum1, finite realpositivebases, shapeถูก, rejectunknownoptions, healthyPFpairครบ. Helperถ้าแยกต้องรับrawsignalsและweights/**bases**หรือแยกnormalizationvalidatorที่มีtestครบ ไม่ใช้signatureไม่มีbasesแล้วอ้างvalidatebases.

## 4. Single canonical sample / resolved gates

1. Alignaccepted ratesด้วยtimestamp/device/epochก่อนสร้างweightedterms; canonicalsampleเดียวส่งloggingและทุกactualsupervisorgate ทั้งSG_OFFและSG_ON ไม่recomputeคนละbasis.
2. Resolve`si_on/off`กับ`severity_gamma_on/off` และ`on/off_dwell`กับ`severity_T_d_on/off`เป็นcontractเดียวในopt-in. Explicitconflicts error; omissionlegacyunchanged. Logresolvedvalues; exactlandingใช้deadlineเดียวกับgate.
3. แยก **per-GFM SI/off-dwell eligibility** จาก **global hard-safe/prediction dwell**. Opt-in globalrelease-safetyต้องไม่ยังใช้all(SI<off)เป็นbottleneckของทุกIBR; deviceที่eligibleยังเลือกได้เมื่อdeviceอื่นไม่eligibleแต่hard-safe. Allunsafe/predictiontriggerholdตามguardเดิม.
4. ไม่เขียนทับeligiblelistเป็นcurrent_gfmในopt-in. Routineเลือกboundeddevice; transactionauthorityยังต้องauthenticate.
5. Missing/invalid/warmup/epoch/duplicate evidence hold/resetdwell ไม่แทนrateด้วยzero. ทดสอบresetผ่านcallerจริง รวมmode/onlineeventsและduplicateatomicrightlimits ไม่ใช่policyเดี่ยวเท่านั้น.
6. Preservehardceilings,outwardprediction,minhold,handbackcapability,authentication,private trial,fullKCL,currentMVA/DCenergy. Decisionlogยังไม่grantcommitauthority.

## 5. Controlled decision tests — fixed weights/bases, rate-only change

ใช้si_off=.35,si_on=.65,hardrates1,predictionhorizon.25,Vband.9–1.1,fband59.5–60.5. Baselinevalidsafeต้องสะสมoffdwellก่อนassertrelease=true แล้วเปลี่ยนเฉพาะrate ณ advancingtimestamp.

| Test | Fixed signals | Rate | SI | Expected |
|---|---|---|---|---|
| ROCOF | V=Vhealthy=1,f60.35,rv0 | rf0→−.8 | .245→.365 | projectedf60.15safe; hard/predfalse; actualrelease true→hold/resetdwell |
| ROCOV | V1.07,Vhealthy1,f60.05,rf0 | rv0→−.6 | .28→.37 | projectedV.92safe; hard/predfalse; actualrelease true→hold/resetdwell |

Formula proofไม่พอ: actualdecisionpathต้องใช้canonicalSI. These arecontrolleddecisiontests ไม่ใช่physicaltrajectorycertificates. Legacytwo-termcomparisonแยก ไม่เปลี่ยนweightsระหว่างratepair.

Additionaltests: invalidweights/bases/unknownoptions, omittedlegacyCOI, forwarding metadata, threshold/dwellconflicts, individuallyeligibleGFM vs anotherhighSI buthardsafe, invalidrates, accepted-onlyrejects, epoch/duplicatecallerreset, timestamp/device/epoch/transaction-sidealignment. Noelement-wisezipกับres.t.

## 6. Ownership / dependencies / acceptance

| Step | Owner / files | Gate |
|---|---|---|
| W0 | Lead+studyowner freezeproposeddesign | explicitweights/bases/contracts approved beforeoutcomes |
| W1 FIRST | Supervisorowner: helper, kernelSI/caller/gates/settings, policy, runnerforwarding, controlledtests | bothratepairSI+releaseassertionsผ่าน ไม่logging-only |
| W2 | QA: legacy,invalid,clock,eligibility,caller/plumbingtests | nolegacyregression; resolvedthresholds/clocks; sampleactuallyconsumed |
| C | Coverageowner: nodes/edges/endpoints | appropriatecertifiedreachablepath ไม่mandatory9→0 |
| T | Transitionowner: authenticatedSG_ONprivate destinationtrial | KCL/trialguardsครบก่อนpublish |
| E/F | Integration/runowner: shortactualfixtures then160 | eventswithinfixturehorizon; preflight+baseline+recoveryfreezeผ่านก่อนlongrun |

Kernel/runner singlewriterต่อไฟล์; W1changesserializeก่อนcoverage/transitionแตะไฟล์เดียวกัน. Accumulatorไม่ต้องrefactorถ้าเดิมcontractพอ.

Stop: formulaonly/logonly, missingrateยังrelease, silentclockconflict, legacychange, fakecandidate/guardremoval, missingpath, unapprovedrecoverytolerances. Fullrunacceptanceต้องมีphysicalP/Q/V/f/rates/derivativespropergauge/KCL/current/DC/SGsourceevidence; numericwindow/tolerancespendingapproval. ไม่waivevoltageย้อนหลัง.

HistoricalMATnumbers owner-reported ไม่เปิดอ่านยืนยันในรอบนี้; h5py/scipyไม่มี. ดู [แผนรวม](ne39_gfl_restoration_continuation_plan_20261012.md) และ [QA](ne39_independent_qa_plan_20261012.md). ไม่มีการเริ่มimplementationโดยเอกสารนี้.
