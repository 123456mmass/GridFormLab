import os

content_dir = r"c:\Users\qwert\OneDrive\Desktop\api\n_bus_py\frontend\src\content\methodologies"

methods = {
    "cpf_ls": {
        "en": """# Continuation Power Flow - Load Scaling (CPF LS)

**Load Scaling CPF (CPF LS)** is a variation of Continuation Power Flow that scales the load iteratively using repeated standard Newton-Raphson executions, rather than using an exact predictor-corrector mathematical formulation.

## Concept
Instead of augmenting the Jacobian matrix with a continuation parameter $\lambda$, CPF LS simply runs a standard Power Flow. If it converges, it increases the total system load by a small step size $\Delta S_{step}$ and runs the Power Flow again using the previous solution as the initial guess (warm start).

$$ S_{load}^{(k)} = S_{base} + \lambda^{(k)} \Delta S_{direction} $$

## Advantages and Disadvantages
> **Pros**: Extremely simple to implement since it relies entirely on a standard NR solver. No need to modify the Jacobian matrix.
> **Cons**: Will fail exactly at the singular point (maximum loading limit) and cannot trace the lower portion of the P-V curve.

## References
- Ajjarapu, V. (2007). *Computational Techniques for Voltage Stability Assessment and Control*. Springer.
""",
        "th": """# Continuation Power Flow - Load Scaling (CPF LS)

**Load Scaling CPF (CPF LS)** เป็นรูปแบบประยุกต์อย่างง่ายของวิธี Continuation Power Flow โดยใช้วิธีการเพิ่มโหลด (Load scaling) ทีละสเตป แล้วรัน Newton-Raphson ซ้ำๆ แทนที่จะใช้การสร้างสมการคณิตศาสตร์แบบ Predictor-Corrector แบบเต็มรูปแบบ

## แนวคิดพื้นฐาน
แทนที่จะต้องไปยุ่งกับการเพิ่มตัวแปร $\lambda$ เข้าไปในเมทริกซ์ Jacobian วิธี CPF LS จะรัน Power Flow แบบปกติ ถ้าระบบสามารถหาคำตอบได้ (Converge) ก็จะทำการบวกโหลดในระบบเพิ่มขึ้นไปอีกสเตปเล็กๆ ($\Delta S_{step}$) แล้วนำคำตอบที่ได้จากรอบที่แล้วมาใช้เป็นค่าเริ่มต้น (Warm start) ในการรันรอบถัดไป

$$ S_{load}^{(k)} = S_{base} + \lambda^{(k)} \Delta S_{direction} $$

## ข้อดีและข้อเสีย
> **จุดเด่น**: เขียนโปรแกรมง่ายมาก เพราะแค่เขียน Loop ครอบวิธี NR มาตรฐานที่ทำงานได้อยู่แล้ว ไม่ต้องไปยุ่งกับสมการอนุพันธ์ใน Jacobian เลย
> **จุดด้อย**: ระบบจะล้มเหลว (Diverge) ทันทีเมื่อไปถึงจุดสูงสุดของกราฟ (Singular point) และไม่สามารถวาดกราฟ P-V ส่วนครึ่งล่าง (Lower bound) ได้

## เอกสารอ้างอิง (References)
- Ajjarapu, V. (2007). *Computational Techniques for Voltage Stability Assessment and Control*. Springer.
"""
    },
    "ed": {
        "en": """# Economic Dispatch (ED)

**Economic Dispatch (ED)** is an optimization problem that determines the most cost-effective power output for each generator in a system to meet the total load demand, ignoring the transmission network limits.

## Concept
The objective is to minimize the total generation cost $F_T$:
$$ \min F_T = \sum_{i=1}^{N_g} F_i(P_{gi}) $$
where $F_i(P_{gi})$ is the cost function of generator $i$, typically modeled as a quadratic polynomial: $F_i(P_{gi}) = a_i + b_i P_{gi} + c_i P_{gi}^2$.

### Equality Constraint
The total generation must exactly equal the total load plus losses (in standard ED, losses are often ignored or approximated using B-coefficients):
$$ \sum_{i=1}^{N_g} P_{gi} = P_{load} + P_{loss} $$

### Solution via KKT Conditions
Using Lagrange multipliers ($\lambda$), the condition for optimal dispatch without hitting limits is that the incremental cost of all active generators must be equal:
$$ \frac{dF_1}{dP_{g1}} = \frac{dF_2}{dP_{g2}} = \dots = \lambda $$

## References
- Wood, A. J., & Wollenberg, B. F. (2012). *Power Generation, Operation, and Control*. John Wiley & Sons.
""",
        "th": """# Economic Dispatch (ED)

**Economic Dispatch (ED)** คือปัญหาทางคณิตศาสตร์ด้านการหาค่าเหมาะที่สุด (Optimization) เพื่อหาว่าเครื่องกำเนิดไฟฟ้า (Generator) แต่ละตัวในระบบ ควรจะจ่ายไฟตัวละเท่าไหร่ จึงจะทำให้ **ต้นทุนรวมในการผลิตไฟฟ้าต่ำที่สุด** โดยยังคงตอบสนองโหลดรวมได้ครบถ้วน (วิธีนี้ยังไม่พิจารณาข้อจำกัดของสายส่ง)

## แนวคิดพื้นฐาน
เป้าหมายคือการหาจุดต่ำสุดของฟังก์ชันต้นทุนรวม (Minimize total cost) $F_T$:
$$ \min F_T = \sum_{i=1}^{N_g} F_i(P_{gi}) $$
โดยที่ $F_i(P_{gi})$ คือฟังก์ชันต้นทุนของ Generator ตัวที่ $i$ ซึ่งมักอยู่ในรูปสมการกำลังสอง: $F_i(P_{gi}) = a_i + b_i P_{gi} + c_i P_{gi}^2$

### เงื่อนไขบังคับ (Equality Constraint)
ผลรวมการผลิตไฟฟ้าทั้งหมด ต้องเท่ากับโหลดทั้งหมดรวมกับค่าสูญเสีย (Losses):
$$ \sum_{i=1}^{N_g} P_{gi} = P_{load} + P_{loss} $$

### การหาคำตอบ (KKT Conditions)
เมื่อใช้ทฤษฎีตัวคูณลากรางจ์ (Lagrange multipliers, $\lambda$) เงื่อนไขที่จะทำให้เกิดต้นทุนต่ำสุด (เมื่อไม่ชนขีดจำกัด) คือ Incremental cost (อัตราการเพิ่มของต้นทุน) ของทุกเครื่องกำเนิดไฟฟ้าต้องมีค่าเท่ากัน:
$$ \frac{dF_1}{dP_{g1}} = \frac{dF_2}{dP_{g2}} = \dots = \lambda $$

## เอกสารอ้างอิง (References)
- Wood, A. J., & Wollenberg, B. F. (2012). *Power Generation, Operation, and Control*. John Wiley & Sons.
"""
    },
    "opf": {
        "en": """# Optimal Power Flow (OPF)

**Optimal Power Flow (OPF)** extends Economic Dispatch by combining it with the full AC Power Flow equations. It optimizes a specific objective (like minimizing cost or losses) while ensuring that no physical limits of the network are violated.

## Concept
OPF is a large-scale non-linear programming (NLP) problem.

**Objective Function:**
$$ \min F(x, u) $$
(e.g., total fuel cost, total active power loss).

**Equality Constraints (Power Flow Equations):**
$$ g(x, u) = 0 $$
Active and reactive power balance at every bus (this is exactly the AC power flow constraints).

**Inequality Constraints (Security Limits):**
$$ h_{min} \le h(x, u) \le h_{max} $$
Includes generator limits ($P_{min}, P_{max}, Q_{min}, Q_{max}$), bus voltage limits ($V_{min}, V_{max}$), and line flow thermal limits ($S_{line} \le S_{max}$).

## Solution Methods
OPF can be solved using various advanced mathematical optimization techniques such as:
- Interior Point Method (IPM)
- Sequential Quadratic Programming (SQP)
- Particle Swarm Optimization (PSO)

## References
- Frank, S., Steponavice, I., & Rebennack, S. (2012). Optimal power flow: A bibliographic survey. *Energy Systems*.
- Zimmerman, R. D. (2011). MATPOWER.
""",
        "th": """# Optimal Power Flow (OPF)

**Optimal Power Flow (OPF)** คือการนำเอา Economic Dispatch มารวมเข้ากับสมการ AC Power Flow แบบเต็มรูปแบบ โดยมีเป้าหมายเพื่อหาจุดทำงานที่ดีที่สุด (เช่น ต้นทุนต่ำสุด หรือ ค่าสูญเสียต่ำสุด) ในขณะที่ต้องรับประกันว่าจะไม่มีอุปกรณ์ใดในเครือข่ายทำงานเกินพิกัดจำกัดทางกายภาพ

## แนวคิดพื้นฐาน
OPF ถือเป็นปัญหาการหาค่าเหมาะที่สุดแบบไม่เป็นเชิงเส้นขนาดใหญ่ (Large-scale Non-linear Programming - NLP)

**ฟังก์ชันเป้าหมาย (Objective Function):**
$$ \min F(x, u) $$
(ตัวอย่างเช่น ต้องการให้ต้นทุนเชื้อเพลิงรวมต่ำที่สุด)

**เงื่อนไขบังคับสมการ (Equality Constraints):**
$$ g(x, u) = 0 $$
ข้อนี้คือสมการสมดุลพลังงาน P และ Q ที่ทุกๆ Bus (พูดง่ายๆ คือระบบต้องผ่านกฎของ AC Power flow)

**เงื่อนไขข้อจำกัดความปลอดภัย (Inequality Constraints):**
$$ h_{min} \le h(x, u) \le h_{max} $$
ได้แก่ ขีดจำกัดของ Generator ($P_{min}, P_{max}, Q_{min}, Q_{max}$), ขีดจำกัดแรงดันตก/แรงดันเกิน ($V_{min}, V_{max}$), และขีดจำกัดความร้อนของสายส่ง ($S_{line} \le S_{max}$)

## วิธีการแก้ปัญหา (Solution Methods)
เนื่องจาก OPF มีความซับซ้อนสูงมาก จึงต้องอาศัยเทคนิคทางคณิตศาสตร์ขั้นสูงในการแก้ปัญหา เช่น:
- Interior Point Method (IPM)
- Sequential Quadratic Programming (SQP)
- หรืออัลกอริทึมปัญญาประดิษฐ์ (AI/Heuristics) เช่น Particle Swarm Optimization (PSO)

## เอกสารอ้างอิง (References)
- Frank, S., Steponavice, I., & Rebennack, S. (2012). Optimal power flow: A bibliographic survey. *Energy Systems*.
- Zimmerman, R. D. (2011). MATPOWER.
"""
    }
}

# Create missing methods
for method_id, texts in methods.items():
    method_dir = os.path.join(content_dir, method_id)
    os.makedirs(method_dir, exist_ok=True)
    with open(os.path.join(method_dir, "en.md"), "w", encoding="utf-8") as f:
        f.write(texts["en"])
    with open(os.path.join(method_dir, "th.md"), "w", encoding="utf-8") as f:
        f.write(texts["th"])


example_en = """

## Calculation Example

Consider a highly simplified 2-bus system to demonstrate the basic computational flow of this methodology.

**System Parameters:**
- Bus 1: Slack Bus, $V_1 = 1.0 \angle 0^\circ$ pu
- Bus 2: PQ Bus (Load), $P_D = 0.5$ pu, $Q_D = 0.2$ pu
- Line Admittance: $Y_{12} = -j10$ pu

**Step 1: Formulate the Matrix**
The admittance matrix ($Y_{bus}$) is formed directly from the line parameters:
$$
Y_{bus} = \\begin{bmatrix} -j10 & j10 \\\\ j10 & -j10 \\end{bmatrix}
$$

**Step 2: Initialization**
Set the initial guess for the unknown voltage at Bus 2:
$V_2^{(0)} = 1.0 \angle 0^\circ$

**Step 3: Execute Iteration Logic**
Following the algorithm's formulation, we calculate the active power mismatch at Bus 2:
$$ P_{2, calc} = |V_2| |V_1| |Y_{21}| \cos(\\theta_{21} - \delta_2 + \delta_1) + |V_2|^2 |Y_{22}| \cos(\\theta_{22}) $$

With the flat start ($V_2 = 1.0$), $P_{2, calc} = 0$, leading to a mismatch $\\Delta P_2 = -0.5 - 0 = -0.5$ pu.

**Step 4: Update State**
Using the solver's specific update mechanism (e.g., Jacobian inversion for NR, or sequential substitution for GS), we find the next voltage state:
$V_2^{(1)} \approx 0.98 \angle -2.8^\circ$

**Step 5: Convergence Check**
Since the mismatch is still greater than the tolerance $\epsilon$ ($10^{-4}$), the process repeats. In a typical scenario, it converges completely within 3-5 iterations.
"""

example_th = """

## ตัวอย่างการคำนวณ (Calculation Example)

ลองพิจารณาระบบจำลองขนาดจิ๋วแบบ 2 Bus เพื่อทำความเข้าใจลำดับการคำนวณพื้นฐานของระเบียบวิธีนี้

**พารามิเตอร์ของระบบ:**
- Bus 1: เป็น Slack Bus, บังคับแรงดัน $V_1 = 1.0 \angle 0^\circ$ pu
- Bus 2: เป็น PQ Bus (ฝั่งโหลด), มีการดึงพลังงาน $P_D = 0.5$ pu, $Q_D = 0.2$ pu
- ค่า Admittance ของสายส่ง: $Y_{12} = -j10$ pu

**ขั้นตอนที่ 1: สร้างเมทริกซ์ระบบ**
สร้างเมทริกซ์ $Y_{bus}$ จากข้อมูลสายส่ง:
$$
Y_{bus} = \\begin{bmatrix} -j10 & j10 \\\\ j10 & -j10 \\end{bmatrix}
$$

**ขั้นตอนที่ 2: กำหนดค่าเริ่มต้น (Initialization)**
สมมติค่าเริ่มต้น (Initial guess) สำหรับ Bus 2 ที่เรายังไม่ทราบค่าแรงดัน:
$V_2^{(0)} = 1.0 \angle 0^\circ$ (Flat start)

**ขั้นตอนที่ 3: คำนวณตามลอจิกของอัลกอริทึม**
ตามทฤษฎี เราจะเริ่มคำนวณหา Active Power ที่น่าจะเกิดขึ้นที่ Bus 2 ณ ปัจจุบัน:
$$ P_{2, calc} = |V_2| |V_1| |Y_{21}| \cos(\\theta_{21} - \delta_2 + \delta_1) + |V_2|^2 |Y_{22}| \cos(\\theta_{22}) $$

เมื่อใช้ค่าเริ่มต้น $V_2 = 1.0$ มาแทนค่า จะได้ $P_{2, calc} = 0$ 
นำไปหาค่าความคลาดเคลื่อน (Mismatch) $\\Delta P_2 = -0.5 - 0 = -0.5$ pu

**ขั้นตอนที่ 4: อัปเดตสถานะแรงดัน**
นำค่า Mismatch ที่ได้ไปอัปเดตแรงดันตามสมการของอัลกอริทึม (เช่น แก้สมการ Jacobian ถ้าเป็น NR หรือใช้วิธีแทนค่าถ้าเป็น GS) จะได้ค่าแรงดันรอบถัดไปเป็น:
$V_2^{(1)} \approx 0.98 \angle -2.8^\circ$

**ขั้นตอนที่ 5: ตรวจสอบการลู่เข้า (Convergence Check)**
เนื่องจากค่าความคลาดเคลื่อนยังมีค่ามากกว่า Tolerance $\epsilon$ ($10^{-4}$) ระบบจึงทำการวนซ้ำในขั้นตอนที่ 3 ใหม่ โดยปกติแล้วจะเข้าสู่จุดลู่เข้าสมบูรณ์แบบภายใน 3-5 รอบ Iteration
"""

# Append examples to ALL markdown files just before the References section
all_methods = ["newton-raphson", "gauss-seidel", "fast-decoupled", "dc-power-flow", "dnr", "helm", "h-nr", "homotopy", "cpf_pc", "cpf_ls", "ed", "opf"]

for m in all_methods:
    en_path = os.path.join(content_dir, m, "en.md")
    th_path = os.path.join(content_dir, m, "th.md")
    
    if os.path.exists(en_path):
        with open(en_path, "r", encoding="utf-8") as f:
            en_content = f.read()
        
        if "## Calculation Example" not in en_content:
            if "## References" in en_content:
                en_content = en_content.replace("## References", example_en + "\n\n## References")
            else:
                en_content += example_en
            with open(en_path, "w", encoding="utf-8") as f:
                f.write(en_content)

    if os.path.exists(th_path):
        with open(th_path, "r", encoding="utf-8") as f:
            th_content = f.read()
            
        if "## ตัวอย่างการคำนวณ" not in th_content:
            if "## เอกสารอ้างอิง" in th_content:
                th_content = th_content.replace("## เอกสารอ้างอิง", example_th + "\n\n## เอกสารอ้างอิง")
            else:
                th_content += example_th
            with open(th_path, "w", encoding="utf-8") as f:
                f.write(th_content)

print("Added missing methods and examples.")
