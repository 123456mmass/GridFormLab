# Merge readiness — experiment worktree (2026-10-13)

Branch: `exp/ts-optimize-20261013` @ worktree `D:\4-year-project\GridFormLab-experiment`
Base: `097d770` (same as `backup/pre-ts-optimize-20261013`)
**ยังไม่มี commit ใดๆ** — ทุกอย่างอยู่ใน working tree

## Regression snapshot (2026-10-14, MATLAB session เดียว)

| suite | pass | fail | เวลา |
|---|---|---|---|
| `test_ts_residual_reuse` | 7 | 0 | 4.3s |
| `test_ibr_residual_reuse_forward` | 3 | 0 | 1.6s |
| `test_ts_fd_column_groups` | 20 | 0 | 1.8s |
| `test_ts_forward_fd_parallel` | 9 | 0 | 12.8s |
| `test_mex_fd_kernel` | 4 | 0 | 1.0s |
| `test_composite_newton_contract` | 17 | 0 | 0.9s |
| **รวม** | **60** | **0** | **22.4s** |

หมายเหตุ: `test_mex_fd_kernel` เคยรายงาน FAIL=2 ชั่วคราว — สาเหตุคือเรียก function-based test ผิดวิธี
(ต้องใช้ `runtests` ไม่ใช่เรียกชื่อฟังก์ชัน) **ไม่ใช่ regression** ยืนยันแล้ว 4/4

Git inventory: modified 5 (+550/−6), untracked 15 (โค้ด 9 + docs 3 + binary 2) — ไม่มี commit

---

## A — Residual value threading ✅ เสร็จสมบูรณ์ (รวม follow-up)

| | |
|---|---|
| สถานะ | เสร็จ, tests **PASS=32 FAIL=0**, re-verify บน PCT ผ่าน, cross-tree bit-identity verified, **equivalence PASS ที่ tol=0** |
| วัดได้ | **2.2x** บน composite arm (t_end=2.0s): 0.74s → 0.34s |
| default | `residual_reuse=false` → **production behavior ไม่เปลี่ยน** |
| ไฟล์แก้ | `+stability/ts_step_composite.m` (+133/−1), `+stability/ts_simulate_ibr_hybrid.m` (+10/−2), `tests/test_composite_newton_contract.m` (+33) |
| ไฟล์ใหม่ | `tests/test_ts_residual_reuse.m` (7), `tests/test_ibr_residual_reuse_forward.m` (3), `scripts/diagnostics/compare_reuse_equivalence_composite.m` |
| ไม่แตะ | `+stability/composite_newton.m` ✅ |

**กลไก:** nested function `memo_residual` keyed on `(z, full_closure_token)` ครอบคลุม 3 reuse sites
(FD `r0`, line-search `r_new`, terminal `:291`) ด้วย wrapper เดียว

**Fail-closed:**
- default off → byte-identical กับเดิม
- ห้าม memoize residual ที่ไม่ finite (reset cache แทน)
- cache ช่องเดียว most-recent-wins
- limiter frozen/live สร้าง wrapper คนละตัว → reuse ข้าม context เป็นไปไม่ได้
- context token เทียบด้วย `isequaln` ครอบคลุม `ec` (event_context + limiter_freeze)

**ผลวัด:** หลบ residual ได้ 3 ครั้ง/step (scalar), 14 ครั้งบน IEEE14 limiter-frozen faulted step

**Follow-up:**
- [x] `ts_simulate_ibr_hybrid` forward `residual_reuse` แล้ว (`:303-312` adaptive arm, `:534-539` fixed-path, `:1777-1783` settings sink) — **แต่ default ยัง `false`** production จึงไม่เปลี่ยน
- [ ] `compare_ts_equivalence` trajectory assertion (ต้องใช้ hybrid runs)

---

## E — MEX + OpenMP kernel ✅ kernel + parity ผ่าน (ยังไม่ integrate production)

| | |
|---|---|
| สถานะ | compile ผ่าน, **tests 4/4** (forward_fd parity, fallback, serial=OpenMP bit-identical, parity gate) |
| ไฟล์ใหม่ | `src/mex/gridform_fd_kernel.cpp` (30 KB), `gridform_fd_kernel.mexw64` (132 KB), `+stability/mex_fd_jacobian.m`, `tests/test_mex_fd_kernel.m`, `scripts/build_mex_fd_kernel.m` |
| docs | `docs/project/defects/2026-10-13-mex-openmp-kernel-design.md` (26 KB) |
| default | fail-closed → ไม่มี binary หรือ parity ไม่ผ่าน = fallback MATLAB |

**บัคที่เจอระหว่างทำ (แก้แล้วใน kernel):**
1. `dev_params` scalar broadcast — แก้ใน `local_param_vec`
2. C++ column-major stride ผิด (`kp[row*ndev+k]` → `row + col*4`) — parity gate จับได้
3. FD quotient ไม่ลบ `r0` — **serial vs OpenMP ผ่านเพราะผิดเหมือนกัน** ต้องเทียบ MATLAB ground truth

**ข้อจำกัดทางสถาปัตยกรรม:** MATLAB C API ไม่ thread-safe → OpenMP ใช้ได้จริงต่อเมื่อ
สมการ f/g ของ device อยู่ใน C++ ล้วน ไม่ callback กลับ MATLAB

**ยังไม่ integrate เข้า production path** — ห้ามเปิดพร้อม parfor (oversubscription)

---

## E — parfor FD column groups ✅ integration patch applied (default off)

| | |
|---|---|
| สถานะ | helper + integration + tests แล้ว, **regression 66/66** (รวม suite ใหม่ 9 ตัว) |
| วัดได้ | **2.53x** (IEEE14, 33 groups) / **3.33x** (NE39, 88 groups) ที่ 4 workers |
| กับดัก | zero-dwell floor **0.02x** (ช้าลง 50 เท่า) → ต้องมี `fd_parallel_min_groups>=20` |
| ไฟล์แก้ | `ts_step_composite.m` (+234), `ts_simulate_ibr_hybrid.m` (+30), `ts_simulate_composite.m` (+16), `run_hybrid_case.m` (+9) |
| ไฟล์ใหม่ | `+stability/ts_forward_fd_parallel.m`, `tests/test_ts_forward_fd_parallel.m`, `tests/test_ts_step_composite_fd_parallel.m` (9), `scripts/diagnostics/bench_parfor_fd_groups.m` |
| default | `fd_parallel_mode="off"` → **bit-identical** กับ path เดิม (AbsTol=0) |

**option:** `fd_parallel_mode` = `"off"` (default) / `"serial"` / `"parfor"` / `"auto"` + `fd_parallel_min_groups` (แนะนำ 20)

**Fail-closed:** helper throw / ไม่มี pool / `n_groups<min_groups` / structure fail → ลง serial พร้อม `fallback_reason`
**Exclusive guard:** `fd_parallel_mode` ≠ off + `jacobian_backend="mex"` → **error ทันที** (ห้าม oversubscribe)
**ไม่แตะ:** `composite_newton.m`, `forward_fd` ตัวเดิม, `src/mex/`, counter convention

---

## หลักการ merge ที่ตกลง

1. **ค่า default ของ option ใหม่ทุกตัว = off** → merge แล้ว production ไม่เปลี่ยนพฤติกรรม
2. **ทุก numerical path มี legacy fallback แบบ fail-closed**
3. **ห้าม**เปลี่ยน `jacobian_evaluations` counter convention
4. **ห้าม** reuse residual/Jacobian ข้ามเวลา/input/context/limiter regime
5. ต้องผ่าน `tests/test_ts_fd_column_groups.m:167,248` (`step.rcond` bit-identical)
6. ต้องผ่าน `tests/test_composite_newton_contract.m` 17/17
7. Pre-existing failures (`test_ieee14_ibr_ts_event_runner` 3 ตัว) **ไม่ใช่ความรับผิดชอบของการเปลี่ยนแปลงนี้** — ล้มเหมือนกันบน original tree

---

## ลำดับที่แนะนำสำหรับ commit (ยังไม่ทำ)

1. Lane A (residual reuse) — เสร็จแล้ว พร้อมสุด แยก commit ได้ทันที
2. Lane E parfor helper — ยังไม่มี integration เข้า production จึงเป็น additive-only
3. Lane E MEX — ต้องได้ parity result ก่อน
4. ย้ายสคริปต์ baseline extract เข้า `scripts/diagnostics/` (รอผู้ใช้สั่ง)
5. แก้รายงานผิด 3 บรรทัด (รอผู้ใช้สั่ง)

---

## สิ่งที่ต้องวัดก่อนอ้าง speedup

- **ห้าม** benchmark ตอนมี MATLAB แย่ง CPU
- เทียบ wall clock บน hardware เดียวกัน + settings เดียวกัน
- รายงาน: call counts, step counts, rejections, hardware, checks ที่ตัดออก
- ค่า timing จาก cached replay ไม่นับเป็น solver speedup
- แยกให้ชัด: ลดงานซ้ำ (A) vs เปลี่ยน numerical method (D) vs ลด certification (F) vs ขนาน (E)
