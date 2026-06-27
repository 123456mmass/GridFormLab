# รายงานสรุปสำหรับพรีเซ้น
## โครงสร้างโปรเจค สถาปัตยกรรม ทฤษฎีที่ใช้ และโมเดลที่ส่ง

โครงการนี้เป็นการทำ **Power Flow + Small-Signal Stability Analysis + Fault Time-Domain Simulation** ของระบบ **Kundur Two-Area Four-Machine System, Example 12.6** โดยใช้โค้ด MATLAB ที่เขียนเองภายในโปรเจค ไม่ใช้ MATLAB Power System Toolbox, Simscape Power Systems, MATPOWER หรือ external power-system library

เอกสารนี้ทำไว้สำหรับอ่านก่อนพรีเซ้นและใช้ตอบคำถามอาจารย์/พี่ที่ถามว่า:

- เขียนเป็น script กี่ไฟล์ หรือทำเป็น OOP?
- ใช้ generator กี่ order?
- ใช้สมการอะไร?
- ใช้ทฤษฎีอะไรจาก Kundur?
- โค้ดของเราเชื่อมกับทฤษฎียังไง?
- โมเดลที่ส่งคือโมเดลแบบไหน?

---

# 1. ภาพรวมงานที่ทำ

งานนี้ศึกษา benchmark system จากหนังสือ Kundur:

> Prabha Kundur, *Power System Stability and Control*, Example 12.6 / Table E12.3

ระบบเป็น **two-area four-machine system**:

- Area 1: Generator G1, G2
- Area 2: Generator G3, G4
- ทั้งสอง area เชื่อมกันด้วยสายส่ง 230 kV tie-line
- มี interarea transfer ประมาณ 400 MW
- จุดเด่นของระบบนี้คือเกิด **interarea oscillation** ความถี่ต่ำ ประมาณ 0.5 Hz

สิ่งที่โค้ดเราทำ:

1. แก้ **Power Flow** ด้วย Newton--Raphson ที่เขียนเอง
2. สร้าง operating point จากผล power flow
3. สร้างโมเดล generator แบบ **6th-order Sauer--Pai synchronous machine** สำหรับ SSSA
4. Linearize ระบบ DAE แล้วหา eigenvalues
5. เทียบ mode กับ Kundur Table E12.3
6. ทำ plot eigenvalue real-imaginary / complex plane
7. ทำ time-domain simulation กรณี 3-phase fault ที่ bus 8
8. Generate report PDF พร้อมรูปและตาราง

---

# 2. คำตอบสั้นสำหรับถามว่า “เขียนเป็น scripting กี่ไฟล์ / OOP ไหม”

คำตอบที่ใช้พูดได้:

> งานนี้ไม่ได้ทำเป็น OOP class ครับ เป็น MATLAB script + modular function packages ครับ ไฟล์หลักสำหรับ generate report คือ `generate_kundur_ex126_report.m` แล้วเรียก function ใน package ต่าง ๆ เช่น `+pfsolver`, `+stability`, `+cases` ครับ

โครงสร้างหลัก:

| หน้าที่ | ไฟล์ |
|---|---|
| main script สำหรับ generate report/figures/tables | `generate_kundur_ex126_report.m` |
| ข้อมูลระบบ Kundur Example 12.6 | `+cases/case_kundur_two_area_classical.m` |
| Power-flow Newton--Raphson solver | `+pfsolver/powerflow_newton_raphson.m` |
| SSSA 6th-order public entry point | `+stability/kundur_ex126_sixth_order_ssa.m` |
| SSSA implementation จริงแบบ Sauer--Pai | `+stability/kundur_ex126_sauer_pai_ssa.m` |
| Fault time-domain simulation | `+stability/kundur_fault_simulation.m` |
| ไฟล์สมการ 6-order แบบย่อ ส่งให้อาจารย์อ่านได้ | `kundur_6order_sauer_pai_equations.m` |
| รายงาน PDF | `docs/source/report_kundur_ex126_classical.pdf` |
| checklist feedback | `FEEDBACK_CHECKLIST.md` |

สรุปคือ:

- ไม่ใช่ OOP class
- เป็น script + function modules
- ใช้ MATLAB package folder เช่น `+stability`, `+pfsolver`, `+cases`
- entry point ที่ควรรันคือ `generate_kundur_ex126_report.m`

---

# 3. สถาปัตยกรรมของระบบโค้ด

## 3.1 Pipeline หลักของรายงาน

```text
+cases/case_kundur_two_area_classical.m
        |
        v
+pfsolver/powerflow_newton_raphson.m
        |
        v
Power-flow operating point: V, theta, Pgen, Qgen
        |
        +-------------------------------+
        |                               |
        v                               v
+stability/kundur_ex126_sixth_order_ssa.m   +stability/kundur_fault_simulation.m
        |                               |
        v                               v
6th-order DAE linearisation             Time-domain fault simulation
        |                               |
        v                               v
Eigenvalues / damping / mode plot       Vbus, Pgen, delta, omega plots
        |                               |
        +---------------+---------------+
                        v
generate_kundur_ex126_report.m
                        |
                        v
docs/source/report_kundur_ex126_classical.pdf
```

## 3.2 Layer ของโปรเจค

### Layer 1: Case/Data Layer
ไฟล์:

```text
+cases/case_kundur_two_area_classical.m
```

เก็บข้อมูล:

- bus data
- line data
- transformer reactance
- shunt compensation
- generator dynamic data
- base values: 100 MVA, 230 kV
- machine base: 900 MVA, 20 kV

### Layer 2: Power Flow Layer
ไฟล์:

```text
+pfsolver/powerflow_newton_raphson.m
```

ทำหน้าที่:

- สร้าง mismatch \(\Delta P, \Delta Q\)
- สร้าง Jacobian ของ power flow
- update voltage magnitude/angle
- คืนค่า operating point

ผลลัพธ์สำคัญ:

- bus voltage magnitude \(|V|\)
- bus angle \(\theta\)
- generator injections \(P_G, Q_G\)
- line flows
- convergence history

### Layer 3: Small-Signal Stability Layer
ไฟล์:

```text
+stability/kundur_ex126_sixth_order_ssa.m
+stability/kundur_ex126_sauer_pai_ssa.m
```

ทำหน้าที่:

- ใช้ผล power flow เป็น operating point
- initialize generator states
- สร้าง DAE residual \(f(x,y), g(x,y)\)
- linearize โดย numerical differentiation
- eliminate algebraic variables ด้วย Schur complement
- หา eigenvalues ด้วย `eig`

### Layer 4: Fault Simulation Layer
ไฟล์:

```text
+stability/kundur_fault_simulation.m
```

ทำหน้าที่:

- สร้าง network ก่อน fault / ระหว่าง fault / หลัง fault
- ใช้ classical transient-stability model สำหรับ time-domain fault plot
- integrate ด้วย RK4 ที่เขียนเอง
- output:
  - rotor angle differences
  - generator active power
  - bus voltage magnitudes ทุก bus
  - rotor speed deviations

### Layer 5: Report Generation Layer
ไฟล์:

```text
generate_kundur_ex126_report.m
```

ทำหน้าที่:

- เรียก power flow
- เรียก stability benchmark
- เรียก fault simulation
- export figures เป็น PNG
- write LaTeX tables
- ใช้ `docs/source/report_kundur_ex126_classical.tex` compile เป็น PDF

---

# 4. ทฤษฎีที่ใช้จาก Kundur

## 4.1 Power Flow

Power flow ใช้สมการกำลังไฟฟ้าในรูป polar:

\[
P_i = |V_i| \sum_{j=1}^{n} |V_j| \left(G_{ij}\cos\theta_{ij} + B_{ij}\sin\theta_{ij}\right)
\]

\[
Q_i = |V_i| \sum_{j=1}^{n} |V_j| \left(G_{ij}\sin\theta_{ij} - B_{ij}\cos\theta_{ij}\right)
\]

โดย:

- \(V_i\) คือ voltage phasor ที่ bus i
- \(G_{ij}+jB_{ij}\) คือสมาชิกของ Ybus
- \(\theta_{ij}=\theta_i-\theta_j\)

Newton--Raphson แก้สมการ mismatch:

\[
\begin{bmatrix}
\Delta P \\
\Delta Q
\end{bmatrix}
=
\begin{bmatrix}
J_{11} & J_{12} \\
J_{21} & J_{22}
\end{bmatrix}
\begin{bmatrix}
\Delta \theta \\
\Delta |V|
\end{bmatrix}
\]

ในงานนี้ power flow converges ภายใน 6 iterations

---

## 4.2 Small-Signal Stability Analysis หรือ SSSA

จาก Kundur แนวคิดคือระบบไฟฟ้ามี nonlinear differential-algebraic equations:

\[
\dot{x}=f(x,y)
\]

\[
0=g(x,y)
\]

โดย:

- \(x\) = dynamic states ของ generator
- \(y\) = algebraic variables เช่น bus voltages

เมื่อมี disturbance ขนาดเล็ก เรา linearize รอบ operating point \((x_0,y_0)\):

\[
\Delta \dot{x}=J_{xx}\Delta x + J_{xy}\Delta y
\]

\[
0=J_{yx}\Delta x + J_{yy}\Delta y
\]

eliminate \(\Delta y\):

\[
\Delta y = -J_{yy}^{-1}J_{yx}\Delta x
\]

จึงได้ reduced state matrix:

\[
A_{red}=J_{xx}-J_{xy}J_{yy}^{-1}J_{yx}
\]

แล้วหา eigenvalues:

\[
\lambda_i = eig(A_{red})
\]

เกณฑ์ stability:

- ถ้า \(\Re(\lambda_i)<0\) ทุกตัว ระบบ stable
- ถ้า eigenvalue อยู่ขวาของ imaginary axis ระบบ unstable
- complex pair \(\lambda=\sigma \pm j\omega\) แสดง oscillatory mode

ความถี่:

\[
f=\frac{|\omega|}{2\pi}
\]

Damping ratio:

\[
\zeta=\frac{-\sigma}{\sqrt{\sigma^2+\omega^2}}
\]

---

# 5. Generator model ที่ใช้: 6th-order Sauer--Pai

## 5.1 ตอบสั้น

> Generator ใช้ 6th-order Sauer--Pai synchronous-machine model ครับ หนึ่ง generator มี 6 states คือ \(\delta, \omega, E'_q, E'_d, \psi''_d, \psi''_q\) ดังนั้น 4 generators มี 24 dynamic states ก่อนตัด reference angle ครับ

## 5.2 State variables ต่อ generator

\[
x_i =
\begin{bmatrix}
\delta_i \\
\omega_i \\
E'_{qi} \\
E'_{di} \\
\psi''_{di} \\
\psi''_{qi}
\end{bmatrix}
\]

ความหมาย:

| State | ความหมาย |
|---|---|
| \(\delta\) | rotor angle |
| \(\omega\) | rotor speed deviation |
| \(E'_q\) | q-axis transient EMF |
| \(E'_d\) | d-axis transient EMF |
| \(\psi''_d\) | d-axis subtransient flux state |
| \(\psi''_q\) | q-axis subtransient flux state |

---

## 5.3 Gamma factors ของ Sauer--Pai

Sauer--Pai model ใช้ gamma factor เพื่อเชื่อม transient flux กับ subtransient flux:

\[
\gamma_{d1}=\frac{X''_d-X_l}{X'_d-X_l}
\]

\[
\gamma_{q1}=\frac{X''_q-X_l}{X'_q-X_l}
\]

\[
\gamma_{d2}=\frac{1-\gamma_{d1}}{X'_d-X_l}
\]

\[
\gamma_{q2}=\frac{1-\gamma_{q1}}{X'_q-X_l}
\]

ในโค้ด \(\gamma_{d2}\) และ \(\gamma_{q2}\) คำนวณบน per-unit base เดียวกับ state/reactance หลังแปลง base แล้ว

---

## 5.4 Subtransient internal voltage

\[
E''_q = \gamma_{d1}E'_q + (1-\gamma_{d1})\psi''_d
\]

\[
E''_d = \gamma_{q1}E'_d + (1-\gamma_{q1})\psi''_q
\]

นี่คือจุดสำคัญของ Sauer--Pai model: ไม่ได้ใช้แค่ transient EMF ตรง ๆ แต่สร้าง subtransient internal voltage จาก transient state + subtransient flux state

---

## 5.5 Stator algebraic equations

ใน generator-current convention ที่ใช้ในโค้ด:

\[
V_d = E''_d - R_a I_d + X''_q I_q
\]

\[
V_q = E''_q - R_a I_q - X''_d I_d
\]

สมการนี้เชื่อม generator internal states กับ terminal voltage/current ใน network

---

## 5.6 Effective currents ใน transient-flux equations

\[
I_{d,eff}=\gamma_{d1}I_d + \gamma_{d2}(E'_q-\psi''_d)
\]

\[
I_{q,eff}=\gamma_{q1}I_q + \gamma_{q2}(\psi''_q-E'_d)
\]

---

## 5.7 Differential equations ครบ 6-order

Swing equations:

\[
\dot{\delta}=\omega_0\omega
\]

\[
\dot{\omega}=\frac{T_m-T_e-D\omega}{2H}
\]

Transient flux equations:

\[
\dot{E}'_q = \frac{E_{fd}-E'_q-(X_d-X'_d)I_{d,eff}}{T'_{d0}}
\]

\[
\dot{E}'_d = \frac{-E'_d+(X_q-X'_q)I_{q,eff}}{T'_{q0}}
\]

Subtransient flux equations:

\[
\dot{\psi}''_d = \frac{E'_q-\psi''_d-(X'_d-X_l)I_d}{T''_{d0}}
\]

\[
\dot{\psi}''_q = \frac{E'_d-\psi''_q+(X'_q-X_l)I_q}{T''_{q0}}
\]

Electromagnetic air-gap torque:

\[
T_e=V_dI_d+V_qI_q+R_a(I_d^2+I_q^2)
\]

ใน operating point กำหนด:

\[
T_m=T_e
\]

\[
E_{fd}=E'_q+(X_d-X'_d)I_{d,eff}
\]

---

# 6. Per-unit base ที่ใช้

ระบบ network ใช้:

\[
S_{base}=100\text{ MVA}
\]

Generator dynamic data อยู่บน machine base:

\[
S_{machine}=900\text{ MVA}
\]

ใน case นี้ transformer per-unit data แปลง voltage-base มาใน network แล้ว ดังนั้น dynamic reactance ใน DAE แปลงด้วย MVA ratio:

\[
X_{system}=X_{machine}\frac{100}{900}
\]

ตัวอย่าง:

\[
X_d=1.8\times\frac{100}{900}=0.2\text{ pu on system base}
\]

เหตุผลที่สำคัญ:

- ถ้า base scaling ไม่ตรง eigenvalues จะเพี้ยนมาก
- \(\gamma_{d2}\), \(\gamma_{q2}\) ต้องใช้ reactance difference บน base เดียวกับ state/current

---

# 7. วิธีโยงทฤษฎีกับโค้ดจริง

| ทฤษฎี | โค้ด |
|---|---|
| Kundur two-area system data | `+cases/case_kundur_two_area_classical.m` |
| Newton--Raphson power flow | `+pfsolver/powerflow_newton_raphson.m` |
| SSSA DAE \(f(x,y),g(x,y)\) | `+stability/kundur_ex126_sauer_pai_ssa.m` |
| 6th-order Sauer--Pai equations | `kundur_6order_sauer_pai_equations.m` |
| Schur complement \(A_{red}\) | `+stability/kundur_ex126_sauer_pai_ssa.m` |
| Eigenvalue calculation | MATLAB base `eig` |
| Kundur Table E12.3 benchmark | `+stability/kundur_ex126_classical_analysis.m` |
| Real-imag eigenvalue plot | `generate_kundur_ex126_report.m` → `full_eigenvalue_map.png` |
| Fault time-domain simulation | `+stability/kundur_fault_simulation.m` |
| Report generation | `generate_kundur_ex126_report.m` + LaTeX source |

---

# 8. โมเดลที่ส่งคืออะไร

## 8.1 โมเดลหลักในรายงาน

โมเดลในรายงานหลักคือ:

> Kundur Example 12.6 two-area four-machine system, manual-excitation / classical benchmark, compared against Kundur Table E12.3

สิ่งที่รายงานแสดง:

- Power-flow result ของระบบ 11-bus
- Eigenvalue table เทียบ Kundur Table E12.3
- Complex-plane eigenvalue plot real-imag ของทุก mode/state group
- Mode shape ของ interarea/local modes
- Time-domain response
- Fault simulation ที่ bus 8

## 8.2 โมเดล dynamic ที่ implement เพิ่ม

โมเดล SSSA ที่ implement ในโค้ดคือ:

> 6th-order Sauer--Pai synchronous-machine model, 4 generators, 24 states before reference reduction

สถานะปัจจุบัน:

- DAE operating point residual ใกล้ machine precision
- local swing modes และ damper modes ใกล้ Kundur Table E12.3
- interarea damping real part ยัง sensitive กับ reference/load/damping assumptions จึงระบุเป็นประเด็นสำหรับคุยกับอาจารย์

## 8.3 โมเดล fault simulation

Fault simulation ใช้:

> Classical transient-stability model: constant \(E'\) behind \(X'_d\), integrate rotor swing equations ด้วย RK4

เหตุผล:

- ใช้สำหรับ time-domain visualization ของ disturbance
- แสดง \(V\) ทุกบัส, \(P\) ทุก generator, rotor angle difference, speed deviation
- fault ที่ใช้: temporary 3-phase fault at bus 8, clear ที่ 0.1 s

---

# 9. ผลลัพธ์สำคัญที่เอาไปพูด

## 9.1 Power flow

- Newton--Raphson converges ใน 6 iterations
- minimum voltage ประมาณ 0.949 pu
- total active loss ประมาณ 85.1 MW
- Area 1 export power ไป Area 2 ผ่าน tie-line

## 9.2 Eigenvalues / Table 4

กราฟที่พี่ Sorasak ขอคือ:

```text
docs/source/figures/kundur_ex126/full_eigenvalue_map.png
```

เป็นกราฟ:

- x-axis = real part \(\sigma\)
- y-axis = imaginary part \(\omega\)
- complex pair แสดง oscillation mode
- real-only eigenvalues แสดง field/damper flux modes
- label ครบทุก Table 4 / Table E12.3 group

## 9.3 Fault simulation

รูป fault simulation:

```text
docs/source/figures/kundur_ex126/fault_simulation.png
```

มี:

- rotor angle differences relative to G1
- Pgen ของ G1--G4
- voltage magnitude ของ Bus 1--11
- rotor speed deviations ของ G1--G4

---

# 10. วิธีรันงานทั้งหมด

## 10.1 Generate report assets

```matlab
addpath(pwd);
generate_kundur_ex126_report
```

## 10.2 Compile report PDF

```bash
cd docs/source
xelatex -interaction=nonstopmode report_kundur_ex126_classical.tex
xelatex -interaction=nonstopmode report_kundur_ex126_classical.tex
```

## 10.3 Run 6-order SSSA

```matlab
addpath(pwd);
r = stability.kundur_ex126_sixth_order_ssa();
r.eigenvalues
r.frequency_Hz
r.damping_ratio
```

## 10.4 Run equation/reference file

```matlab
addpath(pwd);
kundur_6order_sauer_pai_equations
```

## 10.5 Run fault simulation

```matlab
addpath(pwd);
res = stability.kundur_fault_simulation();
```

---

# 11. Script สำหรับพูดพรีเซ้นแบบ 3 นาที

> งานนี้ผมทำ power-flow และ stability study ของ Kundur two-area four-machine system จาก Example 12.6 ครับ ระบบนี้เป็น benchmark สำหรับ interarea oscillation โดยมีเครื่องกำเนิด 4 ตัวใน 2 area และมี tie-line ระหว่าง area

> ขั้นแรกผมแก้ power flow ด้วย Newton--Raphson solver ที่เขียนเองในโปรเจค ไม่ได้ใช้ MATPOWER หรือ Power System Toolbox ครับ ได้ operating point เช่น bus voltage, bus angle, P/Q generation แล้วเอาผลนี้ไปใช้ต่อใน stability analysis

> ส่วน small-signal stability ผมใช้แนวคิดจาก Kundur คือเขียนระบบเป็น DAE: \(\dot{x}=f(x,y)\), \(0=g(x,y)\) แล้ว linearize รอบ operating point จากนั้น eliminate algebraic variables ด้วย Schur complement ได้ \(A_{red}\) แล้วหา eigenvalues ด้วย `eig`

> Generator model ที่ implement เป็น 6th-order Sauer--Pai synchronous machine ครับ หนึ่งเครื่องมี states คือ \(\delta, \omega, E'_q, E'_d, \psi''_d, \psi''_q\) รวม 4 เครื่องเป็น 24 states ก่อนตัด reference angle

> ในรายงานมี Table 4 เทียบ Kundur Table E12.3 และมี complex-plane plot ที่แกน x เป็น real part, แกน y เป็น imaginary part แสดงทุก mode/state group ครับ

> เพิ่มเติมผมทำ time-domain fault simulation โดยใส่ temporary 3-phase fault ที่ bus 8 clearing time 0.1 s แล้ว plot voltage ทุก bus และ active power ทุก generator ตาม feedback ครับ

> ทั้งหมดเป็น MATLAB base code ที่เขียนเอง ใช้ built-in เช่น matrix backslash, eig, plot เท่านั้น ไม่ใช้ power-system toolbox หรือ external library ครับ

---

# 12. คำถามที่อาจโดนถามและคำตอบ

## Q1: ใช้ generator กี่ order?

ใช้ 6th-order Sauer--Pai synchronous-machine model สำหรับ SSSA ครับ

## Q2: state มีอะไรบ้าง?

\[
[\delta,\omega,E'_q,E'_d,\psi''_d,\psi''_q]
\]

## Q3: ทำไมต้อง linearize DAE?

เพราะระบบ power system มีทั้ง differential states ของ generator และ algebraic network equations ของ bus voltages ถ้าจะทำ SSSA ต้อง linearize ทั้งสองส่วน แล้ว eliminate algebraic variables เพื่อหา eigenvalues ของ dynamic system

## Q4: ทำไมต้องตัด reference angle?

เพราะ absolute rotor angle ไม่มีความหมายทางฟิสิกส์ ถ้าเลื่อน rotor angle ทุกเครื่องเท่ากัน ระบบไม่เปลี่ยน จึงเกิด zero/null mode ต้อง fix reference เช่น G1 แล้ว drop reference state

## Q5: Fault simulation ใช้โมเดลเดียวกับ SSSA ไหม?

ไม่เหมือนทั้งหมดครับ SSSA ใช้ 6th-order Sauer--Pai แต่ fault time-domain plot ใช้ classical transient-stability model \(E'\) behind \(X'_d\) เพื่อแสดง dynamic response ต่อ 3-phase fault แบบชัดเจนและคำนวณได้ robust

## Q6: ใช้ library ภายนอกไหม?

ไม่ใช้ครับ ใช้ MATLAB base built-ins เช่น `eig`, `plot`, matrix backslash และโค้ด solver ที่เขียนเองในโปรเจค

## Q7: อะไรยังต้องคุยกับอาจารย์?

ประเด็นที่ควรคุยคือ interarea damping real part ของ 6th-order model ยัง sensitive กับ load model/reference/damping assumptions แม้ DAE residual และ local/damper modes จะดีแล้ว

---

# 13. ไฟล์ที่ควรเปิดตอนพรีเซ้น

1. รายงาน PDF:

```text
docs/source/report_kundur_ex126_classical.pdf
```

2. กราฟ eigen real-imag:

```text
docs/source/figures/kundur_ex126/full_eigenvalue_map.png
```

3. กราฟ fault:

```text
docs/source/figures/kundur_ex126/fault_simulation.png
```

4. ไฟล์สมการ 6-order:

```text
kundur_6order_sauer_pai_equations.m
```

5. ไฟล์ SSSA implementation:

```text
+stability/kundur_ex126_sauer_pai_ssa.m
```

6. Checklist feedback:

```text
FEEDBACK_CHECKLIST.md
```

---

# 14. สรุปสุดท้าย

โมเดลที่เราทำคือการเอา Kundur Example 12.6 มาสร้าง workflow เองครบชุด:

```text
Power Flow -> Operating Point -> 6th-order Generator DAE -> Linearisation -> Eigenvalues -> Report/Figures
```

ส่วนที่ใช้ทฤษฎีหลักคือ:

- Newton--Raphson power flow
- DAE modelling
- 6th-order Sauer--Pai synchronous machine
- small-signal linearisation
- Schur complement reduction
- eigenvalue/damping/frequency analysis
- transient fault simulation ด้วย swing equation + RK4

จุดขายของงานคือ:

- ใช้ benchmark จาก Kundur
- ไม่ใช้ power-system toolbox/external library
- โค้ดเป็น in-house MATLAB ทั้งหมด
- มีทั้ง eigenvalue analysis และ time-domain fault response
- มีไฟล์สมการ 6-order แยกให้ตรวจได้
