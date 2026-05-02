# Fast Decoupled Load Flow (FDLF)

ระเบียบวิธี **Fast Decoupled Load Flow (FDLF)** เป็นเวอร์ชันที่ถูกปรับปรุงและลดทอนความซับซ้อนมาจากวิธี Newton-Raphson โดยถูกออกแบบมาเพื่อเพิ่มความเร็วในการคำนวณและลดการใช้หน่วยความจำ อาศัยคุณสมบัติทางกายภาพของระบบสายส่งไฟฟ้า (Transmission systems) ส่วนใหญ่

## 1. แนวคิดพื้นฐาน (Core Concept)

ในระบบเครือข่ายสายส่งทั่วไป มักจะพบคุณสมบัติทางกายภาพดังนี้:
1. **Strong coupling** (มีความสัมพันธ์กันสูง) ระหว่าง Active Power ($P$) และ Voltage Angle ($\delta$)
2. **Strong coupling** ระหว่าง Reactive Power ($Q$) และ Voltage Magnitude ($|V|$)
3. **Weak coupling** (มีความสัมพันธ์กันต่ำ) ระหว่าง $P$ กับ $|V|$ และระหว่าง $Q$ กับ $\delta$

วิธี FDLF นำคุณสมบัติเหล่านี้มาใช้ประโยชน์ โดยการตัดสมาชิกที่มีความสัมพันธ์กันต่ำ (Weak coupling elements) ออกจากเมทริกซ์ Jacobian (ตัด $J_{12}$ และ $J_{21}$ ทิ้ง)

## 2. การแยกส่วน Jacobian (Decoupling)

จากสมการตั้งต้นของ Newton-Raphson:

$$
\begin{bmatrix} \Delta P \\ \Delta Q \end{bmatrix} = \begin{bmatrix} J_{11} & J_{12} \\ J_{21} & J_{22} \end{bmatrix} \begin{bmatrix} \Delta \delta \\ \Delta |V| \end{bmatrix}
$$

เมื่อสมมติให้ $J_{12} \approx 0$ และ $J_{21} \approx 0$ สมการจะถูกแยกออก (Decoupled) เป็น 2 ส่วนที่ไม่ขึ้นต่อกัน:

$$
\Delta P = J_{11} \Delta \delta
$$
$$
\Delta Q = J_{22} \Delta |V|
$$

## 3. รูปแบบ XB และ BX (The XB and BX Schemes)

มีการประมาณค่าเพิ่มเติม โดยสมมติให้ $\cos(\theta) \approx 1$, $G_{ij} \ll B_{ij}$, และ $|V_i| \approx 1.0$ pu ทำให้สามารถแทนที่อนุพันธ์ย่อยใน Jacobian ด้วยเมทริกซ์แอดมิตแตนซ์ค่าคงที่ (Constant admittance matrices) $B'$ และ $B''$:

$$
\frac{\Delta P}{|V|} = -B' \Delta \delta
$$
$$
\frac{\Delta Q}{|V|} = -B'' \Delta |V|
$$

จุดเด่นคือเมทริกซ์ $B'$ และ $B''$ มีค่า **คงที่ (Constant)** ตลอดการรัน ทำให้สามารถทำ Factorization (Triangulation) เพียงแค่ **ครั้งเดียว** ก่อนเริ่ม Iteration ซึ่งช่วยลดระยะเวลาในการประมวลผลต่อรอบได้อย่างมหาศาล

## 4. ขั้นตอนการแก้ปัญหา (Iteration Process)

1. **Calculate:** คำนวณ $\Delta P$ และ $\Delta Q$
2. **Solve P- $\delta$:** คำนวณหา $\Delta \delta$ โดยใช้เมทริกซ์ $B'$: $\Delta \delta = -[B']^{-1} (\frac{\Delta P}{|V|})$
3. **Update:** อัปเดตมุม $\delta$ ใหม่
4. **Solve Q- $|V|$:** คำนวณหา $\Delta |V|$ โดยใช้เมทริกซ์ $B''$: $\Delta |V| = -[B'']^{-1} (\frac{\Delta Q}{|V|})$
5. **Update:** อัปเดตขนาด $|V|$ ใหม่
6. ทำซ้ำจนกว่าระบบจะลู่เข้า (Convergence)

> **จุดเด่น**: การคำนวณในแต่ละ Iteration รวดเร็วมาก ใช้หน่วยความจำน้อย เหมาะสำหรับการทำ Contingency analysis (การวิเคราะห์กรณีฉุกเฉิน) ที่ต้องรันระบบซ้ำๆ หลายครั้ง
> **จุดด้อย**: อัตราการลู่เข้าช้ากว่าแบบ NR (เป็นแบบ Linear) และอาจจะล้มเหลว (Fail to converge) ในระบบที่มีค่า R/X ratio สูง (เช่น ระบบสายจำหน่าย หรือ Distribution networks)






## ตัวอย่างการคำนวณ (Calculation Example)

ลองพิจารณาระบบจำลองขนาดจิ๋วแบบ 2 Bus เพื่อทำความเข้าใจลำดับการคำนวณพื้นฐานของระเบียบวิธีนี้

**พารามิเตอร์ของระบบ:**
- Bus 1: เป็น Slack Bus, บังคับแรงดัน $V_1 = 1.0 \angle 0^\circ$ pu
- Bus 2: เป็น PQ Bus (ฝั่งโหลด), มีการดึงพลังงาน $P_D = 0.5$ pu, $Q_D = 0.2$ pu
- ค่า Admittance ของสายส่ง: $Y_{12} = -j10$ pu

**ขั้นตอนที่ 1: สร้างเมทริกซ์ระบบ**
สร้างเมทริกซ์ $Y_{bus}$ จากข้อมูลสายส่ง:
$$
Y_{bus} = \begin{bmatrix} -j10 & j10 \\ j10 & -j10 \end{bmatrix}
$$

**ขั้นตอนที่ 2: กำหนดค่าเริ่มต้น (Initialization)**
สมมติค่าเริ่มต้น (Initial guess) สำหรับ Bus 2 ที่เรายังไม่ทราบค่าแรงดัน:
$V_2^{(0)} = 1.0 \angle 0^\circ$ (Flat start)

**ขั้นตอนที่ 3: คำนวณตามลอจิกของอัลกอริทึม**
ตามทฤษฎี เราจะเริ่มคำนวณหา Active Power ที่น่าจะเกิดขึ้นที่ Bus 2 ณ ปัจจุบัน:
$$ P_{2, calc} = |V_2| |V_1| |Y_{21}| \cos(\theta_{21} - \delta_2 + \delta_1) + |V_2|^2 |Y_{22}| \cos(\theta_{22}) $$

เมื่อใช้ค่าเริ่มต้น $V_2 = 1.0$ มาแทนค่า จะได้ $P_{2, calc} = 0$ 
นำไปหาค่าความคลาดเคลื่อน (Mismatch) $\Delta P_2 = -0.5 - 0 = -0.5$ pu

**ขั้นตอนที่ 4: อัปเดตสถานะแรงดัน**
นำค่า Mismatch ที่ได้ไปอัปเดตแรงดันตามสมการของอัลกอริทึม (เช่น แก้สมการ Jacobian ถ้าเป็น NR หรือใช้วิธีแทนค่าถ้าเป็น GS) จะได้ค่าแรงดันรอบถัดไปเป็น:
$V_2^{(1)} \approx 0.98 \angle -2.8^\circ$

**ขั้นตอนที่ 5: ตรวจสอบการลู่เข้า (Convergence Check)**
เนื่องจากค่าความคลาดเคลื่อนยังมีค่ามากกว่า Tolerance $\epsilon$ ($10^{-4}$) ระบบจึงทำการวนซ้ำในขั้นตอนที่ 3 ใหม่ โดยปกติแล้วจะเข้าสู่จุดลู่เข้าสมบูรณ์แบบภายใน 3-5 รอบ Iteration
