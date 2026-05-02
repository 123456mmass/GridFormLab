import os

content_dir = r"c:\Users\qwert\OneDrive\Desktop\api\n_bus_py\frontend\src\content\methodologies"

methods = {
    "dnr": {
        "en": """# Dishonest Newton-Raphson (DNR)

The **Dishonest Newton-Raphson** (or Modified Newton-Raphson) method is a variant of the standard NR algorithm. Instead of recalculating and factoring the Jacobian matrix at every single iteration, DNR holds the Jacobian constant for $k$ iterations before rebuilding it.

## Concept

In standard NR, the most computationally expensive step is calculating $J^{-1}$. Since the system approaches a linear state near the solution, $J$ does not change significantly between late iterations. 

By freezing the Jacobian, we trade off the number of iterations for faster execution time per iteration:
$$ \\Delta x = J_{frozen}^{-1} \\begin{bmatrix} \\Delta P \\\\ \\Delta Q \\end{bmatrix} $$

> **Pros**: Faster per-iteration time, good for systems where building the Jacobian is very costly.
> **Cons**: More iterations required to converge. May fail if the initial guess is far from the solution.""",
        "th": """# Dishonest Newton-Raphson (DNR)

ระเบียบวิธี **Dishonest Newton-Raphson** (หรือ Modified Newton-Raphson) เป็นส่วนต่อขยายของอัลกอริทึม NR มาตรฐาน แทนที่จะคำนวณและหาอินเวอร์สของเมทริกซ์ Jacobian ใหม่ในทุกๆ รอบการทำงาน (Iteration) วิธี DNR จะตรึงค่า (Freeze) Jacobian เดิมไว้ใช้งานต่อเนื่องเป็นเวลา $k$ รอบ ก่อนที่จะสร้างใหม่

## แนวคิดพื้นฐาน

ในวิธี NR ปกติ ขั้นตอนที่ใช้เวลาประมวลผลนานที่สุดคือการคำนวณ $J^{-1}$ แต่เนื่องจากระบบมีพฤติกรรมใกล้เคียงเชิงเส้นเมื่อเข้าใกล้คำตอบ ค่า $J$ จึงแทบไม่เปลี่ยนแปลงในรอบท้ายๆ

การตรึงค่า Jacobian จะยอมแลกกับการเพิ่มจำนวนรอบ Iteration แต่ประหยัดเวลาต่อรอบได้มหาศาล:
$$ \\Delta x = J_{frozen}^{-1} \\begin{bmatrix} \\Delta P \\\\ \\Delta Q \\end{bmatrix} $$

> **จุดเด่น**: ใช้เวลาประมวลผลต่อรอบเร็วกว่า NR มาตรฐานมาก เหมาะสำหรับระบบที่การคำนวณ Jacobian กินทรัพยากรสูง
> **จุดด้อย**: ต้องใช้จำนวนรอบ Iteration มากขึ้น และอาจล้มเหลวในการลู่เข้าหากค่าเริ่มต้น (Initial guess) อยู่ไกลจากคำตอบจริงมากเกินไป"""
    },
    "helm": {
        "en": """# Holomorphic Embedding Load Flow Method (HELM)

The **Holomorphic Embedding Load Flow Method (HELM)** is a relatively modern approach that guarantees finding the correct, highest-voltage operable solution (the operable root) of the power flow equations, or unambiguously determines if no solution exists.

## Concept

HELM uses complex analysis by embedding a complex parameter $s$ into the power flow equations. The equations are mapped such that $s=0$ represents a trivial solved state (e.g., no load), and $s=1$ represents the actual target system.

The voltages are expressed as power series in $s$ (Maclaurin series), and analytic continuation techniques (like Padé approximants) are used to evaluate the series at $s=1$.

> **Pros**: No initial guess required! Guaranteed to find the operable root if one exists. Unambiguously detects voltage collapse.
> **Cons**: Mathematically complex and conceptually difficult. Can be slower than NR for well-behaved, non-stressed systems.""",
        "th": """# Holomorphic Embedding Load Flow Method (HELM)

ระเบียบวิธี **Holomorphic Embedding Load Flow Method (HELM)** เป็นแนวทางสมัยใหม่ที่การันตีว่าจะหาคำตอบที่ถูกต้องที่สุด (Operable root หรือคำตอบที่มีแรงดันสูงสุด) ของสมการ Power Flow ได้เสมอ และสามารถยืนยันได้อย่างชัดเจนหากระบบไม่มีคำตอบอยู่จริง (Voltage collapse)

## แนวคิดพื้นฐาน

HELM ประยุกต์ใช้การวิเคราะห์เชิงซ้อน (Complex analysis) โดยการฝังตัวแปรเชิงซ้อน $s$ (Embedding parameter) ลงไปในสมการ Power Flow โดยกำหนดให้ $s=0$ คือสถานะที่ระบบแก้สมการได้ง่ายที่สุด (เช่น ไม่มีโหลด) และ $s=1$ คือสถานะระบบจริงที่เราต้องการหาคำตอบ

ค่าแรงดันจะถูกจัดรูปให้อยู่ในรูปของอนุกรมกำลัง (Power series หรือ Maclaurin series) ของ $s$ จากนั้นใช้เทคนิค Analytic continuation (เช่น Padé approximants) เพื่อประเมินค่าของอนุกรมที่จุด $s=1$

> **จุดเด่น**: ไม่ต้องเดาค่าเริ่มต้น (No initial guess)! การันตีการหาคำตอบที่ใช้งานได้จริง และสามารถตรวจจับสภาวะ Voltage collapse ได้แม่นยำ 100%
> **จุดด้อย**: มีความซับซ้อนทางคณิตศาสตร์สูงมาก และอาจประมวลผลช้ากว่าวิธี NR ทั่วไปในระบบปกติที่ไม่มีความตึงเครียด (Non-stressed systems)"""
    },
    "h-nr": {
        "en": """# HELM-NR (H-NR)

The **HELM-NR** method is a hybrid algorithm that combines the robustness of HELM with the blistering quadratic convergence speed of the Newton-Raphson method.

## Concept

Newton-Raphson is incredibly fast but heavily dependent on a good initial guess (flat start is usually fine, but fails for highly stressed systems). HELM does not require an initial guess but is computationally heavy for the final refinement steps.

**H-NR** uses HELM to calculate a "Warm Start" — getting the system voltages very close to the actual solution. Then, it switches to Newton-Raphson for the final 1-2 iterations to rapidly snap to the exact tolerance limit.

> **Pros**: The best of both worlds. Unfailing robustness even in stressed systems, combined with ultra-fast final convergence.
> **Cons**: More complex implementation as it requires both solvers to be integrated.""",
        "th": """# HELM-NR (H-NR)

ระเบียบวิธี **HELM-NR** เป็นอัลกอริทึมลูกผสม (Hybrid) ที่นำเอาความเสถียรและความแม่นยำของวิธี HELM มารวมกับความเร็วในการลู่เข้าแบบ Quadratic ของวิธี Newton-Raphson

## แนวคิดพื้นฐาน

Newton-Raphson ทำงานได้เร็วมากแต่พึ่งพาค่าเริ่มต้น (Initial guess) ค่อนข้างมาก (ในระบบที่ตึงเครียด การกำหนด Flat start มักจะทำให้ระบบล้มเหลว) ส่วนวิธี HELM ไม่ต้องการค่าเริ่มต้น แต่จะใช้เวลาประมวลผลนานในขั้นตอนการหาคำตอบที่มีความละเอียดสูง

**H-NR** จะใช้วิธี HELM ในการทำ "Warm Start" เพื่อดึงค่าแรงดันให้เข้าใกล้คำตอบที่ถูกต้องมากๆ ก่อน จากนั้นจะสลับไปใช้วิธี Newton-Raphson เพื่อปิดจบงานใน 1-2 Iteration สุดท้าย ทำให้เข้าเป้าหมาย (Tolerance) ได้อย่างรวดเร็ว

> **จุดเด่น**: รวมข้อดีของทั้งสองวิธีเข้าด้วยกัน! มีความเสถียรสูงมากแม้ในระบบที่เสี่ยงต่อการล่ม (Stressed systems) และเข้าสู่คำตอบสุดท้ายได้รวดเร็วปานสายฟ้า
> **จุดด้อย**: การเขียนโปรแกรมมีความซับซ้อนสูง เนื่องจากต้องวางระบบเชื่อมต่อระหว่าง 2 อัลกอริทึม"""
    },
    "homotopy": {
        "en": """# Homotopy Continuation

**Homotopy Continuation** is an advanced numerical technique used for finding all isolated roots of polynomial systems, heavily used in power systems to trace the P-V curves up to the point of voltage collapse.

## Concept

Similar to HELM, Homotopy creates a continuous deformation from a known, solved system (the starting system $G(x)=0$) to the target system we want to solve ($F(x)=0$).

This deformation is defined by a Homotopy function $H(x, \\lambda)$, where $\\lambda$ goes from $0$ to $1$:
$$ H(x, \\lambda) = (1-\\lambda)G(x) + \\lambda F(x) = 0 $$

The solver starts at $\\lambda = 0$ and traces the path by incrementally increasing $\\lambda$ and solving for $x$ using a predictor-corrector method, until $\\lambda = 1$.

> **Pros**: Incredibly robust. Capable of finding multiple solutions (including low-voltage unstable roots).
> **Cons**: Extremely slow. Path tracing requires numerous matrix inversions along the curve.""",
        "th": """# Homotopy Continuation

**Homotopy Continuation** เป็นเทคนิคทางคณิตศาสตร์เชิงตัวเลขขั้นสูง ที่ใช้ในการหารากของสมการพหุนามทั้งหมด ในทางวิศวกรรมไฟฟ้า นิยมนำมาใช้เพื่อวาดเส้นโค้ง P-V (P-V curves) ไปจนสุดขอบของจุดที่เกิด Voltage collapse

## แนวคิดพื้นฐาน

คล้ายกับวิธี HELM วิธี Homotopy จะสร้างเส้นทางการเชื่อมต่อแบบต่อเนื่อง (Continuous deformation) จากระบบที่เรารู้คำตอบอยู่แล้ว (สมการเริ่มต้น $G(x)=0$) ไปยังระบบเป้าหมายที่เราต้องการแก้ปัญหา ($F(x)=0$)

กระบวนการนี้ถูกนิยามผ่านฟังก์ชัน Homotopy $H(x, \\lambda)$ โดยที่ตัวแปร $\\lambda$ จะวิ่งจาก $0$ ไปถึง $1$:
$$ H(x, \\lambda) = (1-\\lambda)G(x) + \\lambda F(x) = 0 $$

ตัวคำนวณจะเริ่มต้นจากจุด $\\lambda = 0$ แล้วค่อยๆ ลากเส้นทาง (Trace path) ไปทีละนิดโดยการเพิ่มค่า $\\lambda$ และหาค่า $x$ ควบคู่กันไป (ผ่านเทคนิค Predictor-Corrector) จนกระทั่งถึง $\\lambda = 1$

> **จุดเด่น**: มีความเสถียร (Robustness) สูงสุดๆ สามารถหาคำตอบได้หลายคำตอบในคราวเดียว (รวมถึงรากที่มีค่าแรงดันต่ำแบบ Unstable)
> **จุดด้อย**: ประมวลผลช้ามากๆ เพราะการลากเส้นตามเส้นโค้ง P-V จำเป็นต้องทำ Matrix inversion นับครั้งไม่ถ้วนระหว่างทาง"""
    },
    "cpf_pc": {
        "en": """# Continuation Power Flow (CPF)

**Continuation Power Flow (CPF)** is a specific application of continuation methods designed to trace the steady-state behavior of a power system as the load gradually increases. It is the primary tool for Voltage Stability Analysis.

## Concept

Standard Newton-Raphson diverges (fails to solve) when the system reaches its maximum loading point (the tip of the "nose" on the P-V curve) because the Jacobian matrix becomes singular (determinant approaches zero).

CPF overcomes this singularity by adding a load parameter $\\lambda$ directly into the state vector, and introducing an extra equation (usually an arclength or local parameterization equation). 

It uses a **Predictor-Corrector** scheme:
1. **Predictor**: Takes a tangent step along the P-V curve to estimate the next point.
2. **Corrector**: Uses Newton-Raphson to pull the estimated point back down perfectly onto the curve.

> **Pros**: The gold standard for Voltage Stability Analysis and finding the exact maximum loading limit of a network. Passes through the singular point effortlessly.
> **Cons**: Designed for tracing curves, not for finding a single operating point. Slower than standard NR.""",
        "th": """# Continuation Power Flow (CPF)

**Continuation Power Flow (CPF)** คือการประยุกต์ใช้วิธี Continuation แบบเจาะจง เพื่อลากเส้นประเมินพฤติกรรมในสภาวะคงตัว (Steady-state) ของระบบไฟฟ้าเมื่อมีโหลดเพิ่มขึ้นอย่างต่อเนื่อง ถือเป็นเครื่องมือหลักในการทำ Voltage Stability Analysis (การวิเคราะห์เสถียรภาพแรงดัน)

## แนวคิดพื้นฐาน

วิธี Newton-Raphson แบบปกติจะล้มเหลว (Diverge) ทันทีเมื่อระบบถูกใช้งานจนถึงขีดจำกัดสูงสุด (จุดปลายสุดของจมูกกราฟ P-V curve) เนื่องจากเมทริกซ์ Jacobian จะกลายเป็น Singular matrix (ค่า Determinant เข้าใกล้ศูนย์)

CPF แก้ปัญหาข้อจำกัดนี้โดยการรวมตัวแปรโหลด $\\lambda$ เข้าไปเป็นส่วนหนึ่งของ State vector ด้วย และเพิ่มสมการเงื่อนไขพิเศษ (เช่น Arclength หรือ Local parameterization) เข้าไปในระบบ

CPF จะทำงานผ่านกลไก **Predictor-Corrector**:
1. **Predictor (ตัวทำนาย):** คำนวณความชัน (Tangent) ของ P-V curve เพื่อก้าวไปหาจุดสมมติล่วงหน้า 1 สเต็ป
2. **Corrector (ตัวแก้ไข):** ใช้วิธี Newton-Raphson ดึงจุดสมมติเหล่านั้นให้ตกลงมาอยู่บนเส้นโค้ง P-V curve ที่ถูกต้องจริงๆ

> **จุดเด่น**: เป็นมาตรฐานสูงสุดระดับสากล (Gold standard) สำหรับการทำ Voltage Stability Analysis และการหาจุดรับโหลดสูงสุด (Maximum loading limit) สามารถผ่านจุด Singular point ได้อย่างไหลลื่น
> **จุดด้อย**: ถูกออกแบบมาเพื่อลากเส้นกราฟ ไม่ใช่เพื่อหาจุดทำงานจุดเดียว (Operating point) ทำให้รันได้ช้ากว่า NR มาตรฐานมาก"""
    }
}

for method_id, texts in methods.items():
    method_dir = os.path.join(content_dir, method_id)
    os.makedirs(method_dir, exist_ok=True)
    with open(os.path.join(method_dir, "en.md"), "w", encoding="utf-8") as f:
        f.write(texts["en"])
    with open(os.path.join(method_dir, "th.md"), "w", encoding="utf-8") as f:
        f.write(texts["th"])

print("Created all missing contents!")
