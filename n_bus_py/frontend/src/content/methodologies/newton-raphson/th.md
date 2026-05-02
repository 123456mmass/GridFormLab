# Newton-Raphson Method

ระเบียบวิธี **Newton-Raphson (NR)** เป็นมาตรฐานระดับอุตสาหกรรมสำหรับการแก้ปัญหา Power Flow แบบ Non-linear โดยประยุกต์ใช้การกระจายอนุกรม Taylor (Taylor series expansion) ในการวนซ้ำ (Iteration) เพื่อหาค่าขนาดและมุมของแรงดันไฟฟ้า (Voltage magnitude & angle) ที่แต่ละ Bus

## 1. แนวคิดพื้นฐาน (Core Concept)

ปัญหา Power Flow ถูกตั้งสมมติฐานบนพื้นฐานของ Mismatch (ความคลาดเคลื่อน) ระหว่างกำลังไฟฟ้าที่ระบุ (Specified power) และกำลังไฟฟ้าที่คำนวณได้จริง สำหรับ Bus $i$ ใดๆ ค่า Active Power ($P_i$) และ Reactive Power ($Q_i$) สามารถเขียนสมการได้ดังนี้:

$$
P_i = |V_i| \sum_{j=1}^{N} |V_j| |Y_{ij}| \cos(\theta_{ij} - \delta_i + \delta_j)
$$

$$
Q_i = -|V_i| \sum_{j=1}^{N} |V_j| |Y_{ij}| \sin(\theta_{ij} - \delta_i + \delta_j)
$$

โดยที่:
- $|V_i|, \delta_i$ คือ Voltage magnitude และ Voltage angle ที่ Bus $i$
- $|Y_{ij}|, \theta_{ij}$ คือขนาดและมุมของสมาชิกในเมทริกซ์ $Y_{bus}$

## 2. เมทริกซ์ Jacobian (The Jacobian Matrix)

วิธี NR จะจัดรูปปัญหาเพื่อหาคำตอบของสมการ $\Delta f(x) = 0$ ในแต่ละรอบการวนซ้ำ $k$ เวกเตอร์คำตอบ $\Delta x$ (ซึ่งประกอบด้วย $\Delta \delta$ และ $\Delta |V|$) จะถูกอัปเดตผ่านการแก้ระบบสมการเชิงเส้น:

$$
\begin{bmatrix} \Delta P \\ \Delta Q \end{bmatrix} = \begin{bmatrix} J_{11} & J_{12} \\ J_{21} & J_{22} \end{bmatrix} \begin{bmatrix} \Delta \delta \\ \Delta |V| \end{bmatrix}
$$

เมทริกซ์ $J$ คือ **Jacobian Matrix** ซึ่งประกอบไปด้วยค่าอนุพันธ์ย่อย (Partial derivatives) ของ $P$ และ $Q$ เทียบกับตัวแปร $\delta$ และ $|V|$

## 3. ขั้นตอนการแก้ปัญหา (Iteration Process)

1. **Initialize:** กำหนดค่าเริ่มต้น Flat start (เช่น $1.0 \angle 0^\circ$ สำหรับ PQ bus)
2. **Calculate Mismatches:** คำนวณค่า $\Delta P$ และ $\Delta Q$
3. **Check Convergence:** หาก $\max(|\Delta P|, |\Delta Q|) < \epsilon$ ให้หยุดการคำนวณ ถือว่าลู่เข้า (Converged)
4. **Form the Jacobian:** คำนวณค่าอนุพันธ์ย่อย (Partial derivatives) เพื่อสร้าง Jacobian matrix จากค่าแรงดันล่าสุด
5. **Solve:** คำนวณ $\Delta x = J^{-1} \begin{bmatrix} \Delta P \\ \Delta Q \end{bmatrix}$
6. **Update State:** $x^{(k+1)} = x^{(k)} + \Delta x$
7. วนซ้ำตั้งแต่ขั้นตอนที่ 2 จนกว่าจะลู่เข้า

> **จุดเด่น**: มีอัตราการลู่เข้าแบบ Quadratic (Quadratic convergence rate) ซึ่งรวดเร็วมากเมื่อเข้าใกล้คำตอบที่ถูกต้อง มีความเสถียร (Robust) สูงมากสำหรับระบบเครือข่ายขนาดใหญ่
> **จุดด้อย**: ใช้พลังการประมวลผล (Computational cost) สูง เนื่องจากต้องสร้างและหาอินเวอร์ส (Invert) ของเมทริกซ์ Jacobian ใหม่ในทุกๆ รอบ Iteration






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
