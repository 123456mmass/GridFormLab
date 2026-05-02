import os

content_dir = r"c:\Users\qwert\OneDrive\Desktop\api\n_bus_py\frontend\src\content\methodologies"

# Raw strings!
example_en = r"""

## Calculation Example

Consider a highly simplified 2-bus system to demonstrate the basic computational flow of this methodology.

**System Parameters:**
- Bus 1: Slack Bus, $V_1 = 1.0 \angle 0^\circ$ pu
- Bus 2: PQ Bus (Load), $P_D = 0.5$ pu, $Q_D = 0.2$ pu
- Line Admittance: $Y_{12} = -j10$ pu

**Step 1: Formulate the Matrix**
The admittance matrix ($Y_{bus}$) is formed directly from the line parameters:
$$
Y_{bus} = \begin{bmatrix} -j10 & j10 \\ j10 & -j10 \end{bmatrix}
$$

**Step 2: Initialization**
Set the initial guess for the unknown voltage at Bus 2:
$V_2^{(0)} = 1.0 \angle 0^\circ$

**Step 3: Execute Iteration Logic**
Following the algorithm's formulation, we calculate the active power mismatch at Bus 2:
$$ P_{2, calc} = |V_2| |V_1| |Y_{21}| \cos(\theta_{21} - \delta_2 + \delta_1) + |V_2|^2 |Y_{22}| \cos(\theta_{22}) $$

With the flat start ($V_2 = 1.0$), $P_{2, calc} = 0$, leading to a mismatch $\Delta P_2 = -0.5 - 0 = -0.5$ pu.

**Step 4: Update State**
Using the solver's specific update mechanism (e.g., Jacobian inversion for NR, or sequential substitution for GS), we find the next voltage state:
$V_2^{(1)} \approx 0.98 \angle -2.8^\circ$

**Step 5: Convergence Check**
Since the mismatch is still greater than the tolerance $\epsilon$ ($10^{-4}$), the process repeats. In a typical scenario, it converges completely within 3-5 iterations.
"""

example_th = r"""

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
"""

all_methods = ["newton-raphson", "gauss-seidel", "fast-decoupled", "dc-power-flow", "dnr", "helm", "h-nr", "homotopy", "cpf_pc", "cpf_ls", "ed", "opf"]

for m in all_methods:
    en_path = os.path.join(content_dir, m, "en.md")
    th_path = os.path.join(content_dir, m, "th.md")
    
    if os.path.exists(en_path):
        with open(en_path, "r", encoding="utf-8") as f:
            en_content = f.read()
        
        # Remove broken section
        if "## Calculation Example" in en_content:
            en_content = en_content.split("## Calculation Example")[0]
            
        # Insert raw example properly
        if "## References" in en_content:
            en_content = en_content.replace("## References", example_en + "\n\n## References")
        else:
            en_content += example_en
            
        with open(en_path, "w", encoding="utf-8") as f:
            f.write(en_content)

    if os.path.exists(th_path):
        with open(th_path, "r", encoding="utf-8") as f:
            th_content = f.read()
            
        # Remove broken section
        if "## ตัวอย่างการคำนวณ" in th_content:
            th_content = th_content.split("## ตัวอย่างการคำนวณ")[0]
            
        # Insert raw example properly
        if "## เอกสารอ้างอิง" in th_content:
            th_content = th_content.replace("## เอกสารอ้างอิง", example_th + "\n\n## เอกสารอ้างอิง")
        else:
            th_content += example_th
            
        with open(th_path, "w", encoding="utf-8") as f:
            f.write(th_content)

print("Fixed calculation examples with raw strings!")
