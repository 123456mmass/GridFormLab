# แนวคำถาม-คำตอบสำหรับกรรมการ

เอกสารนี้ใช้เตรียมตอบคำถามเป็นภาษาไทย โดยเน้นผลลัพธ์และเหตุผลทางคณิตศาสตร์

## 1. ทำไมต้องสลับระหว่าง GFL และ GFM

GFL ต้องอาศัยมุมอ้างอิงจากแหล่งอื่น ส่วน GFM สามารถสร้างแรงดันและมุมอ้างอิงได้เอง เมื่อ SG หลุดออกจากระบบ หากทุก IBR ยังเป็น GFL จะไม่มีอุปกรณ์กำหนดมุมอ้างอิง แต่การให้ทุกตัวเป็น GFM ตลอดเวลาก็ไม่ใช่คำตอบ เพราะผลทดลองแสดงการ hunting จากปฏิสัมพันธ์ของโหมด จึงต้องเลือกทั้งจำนวน ตำแหน่ง และลำดับการสลับ

## 2. ทำไม severity index ใช้แรงดันและความถี่

แรงดันเป็นข้อมูลเฉพาะตำแหน่ง ส่วนความถี่ COI เป็นข้อมูลของระบบ ก่อนรวมกันทำให้เป็น dimensionless:

\[
J_V=\frac{\left||V_i|-V_i^\star\right|}{0.10},\qquad
J_f=\frac{|f_{\mathrm{COI}}-60|}{0.50},
\]

\[
S=\operatorname{sat}_{[0,1]}\left(0.5J_V+0.5J_f\right).
\]

น้ำหนักเท่ากันเป็นค่าที่ประกาศก่อนดูผล ไม่ได้อ้างว่าเหมาะสมที่สุดสำหรับทุกระบบ

## 3. ทำไมเลือก threshold 0.65 และ 0.35

ค่าทั้งสองเป็นค่ากำหนดของกรณีศึกษา ไม่ใช่ค่ามาตรฐานสากล ประเด็นทางคณิตศาสตร์คือ $\Gamma_{\mathrm{on}}>\Gamma_{\mathrm{off}}$ ทำให้เกิด hysteresis band จึงไม่สลับกลับไปกลับมาเมื่อ $S$ อยู่ใกล้ threshold และงานนี้ไม่ได้อ้างว่าคู่นี้ optimal สำหรับระบบอื่น

## 4. ทำไม dwell ตอนเปิด 0.10 s แต่ตอนปล่อย 1.00 s

เพื่อเพิ่ม voltage-forming support เร็ว แต่ถอน support ช้ากว่าเพื่อป้องกัน chatter และการปล่อยหลายอุปกรณ์ขณะ transient ยังไม่สงบ ค่านี้เป็นกรณีศึกษาที่กำหนดไว้ก่อน ไม่ใช่ค่าที่ปรับย้อนหลัง หากถามเรื่อง sensitivity ให้ตอบตรง ๆ ว่างานนี้ยังไม่ได้อ้างผล sweep ของ dwell และควรเป็นงานต่อยอด

## 5. ค่า DC-source time constant 5 ms มาจากไหน

ไม่ได้เลือกจากกราฟ เริ่มจากสมการวงจรแหล่ง DC อันดับสอง:

\[
C\dot V_{dc}=I_{dc}-\frac{P_{ac}}{V_{dc}},\qquad
\tau_s\dot I_{dc}=\frac{E_{dc}-V_{dc}}{R_{dc}}-I_{dc}.
\]

เมื่อ linearise จะได้ระบบอันดับสอง เลือกเกณฑ์ maximally flat ที่ $\zeta^\star=1/\sqrt2$ แล้วแก้ time constant ได้ $\tau_s=5.00$ ms ก่อนคำนวณ spectrum ระบบรวม ค่าทำนายคือประมาณ 15.5 Hz และ 0.7071 ส่วนค่าที่วัดได้คือ 15.18-15.66 Hz และ 0.7072-0.7079 จึงเป็น prediction check ไม่ใช่ tuning

## 6. ทำไมเลือก $\zeta=1/\sqrt2$

เป็นเกณฑ์ของระบบอันดับสองแบบ maximally flat หรือ Butterworth จุดสำคัญคือเลือกจากคุณสมบัติทางคณิตศาสตร์ก่อนดูผล ไม่ได้ reverse-engineer จาก eigenvalue ที่ต้องการ

## 7. ทำไม $R_{dc}$ ใช้ regulation 10 เปอร์เซ็นต์

กำหนด $\varepsilon=0.10$ และ $R_{dc}=\varepsilon(V_{dc}^0)^2/P_r$ จากนั้นตรวจเงื่อนไขการมี equilibrium:

\[
E_{dc}^2\ge4R_{dc}P_{\max}.
\]

เมื่อกำหนด margin เท่ากับ 2 จะได้ขอบบนประมาณ $\varepsilon\lesssim0.115$ ดังนั้น 0.10 อยู่ภายในขอบเขต และ margin จริงอยู่ประมาณ 2.07-2.15 ไม่ได้เลือกจาก timestep หรือเพื่อทำให้ผลผ่าน

## 8. ทำไมมี 17 coordinates แต่ GFL ใช้ 10 และ GFM ใช้ 11

17 เป็น coordinate superset ที่เก็บ shared power stage, DC source และพิกัด controller ของทั้งสองโหมดไว้ในรูปเดียว แต่ละโหมดเปิดใช้เฉพาะ branch ที่เกี่ยวข้อง GFL ใช้ 10 พิกัด ส่วน GFM ใช้ 11 พิกัด พิกัดที่ไม่ active จะไม่ถูกนับเป็น dynamic mode ของ operating point นั้น

## 9. ทำไม mode transfer ไม่ใช้ integration ต่อเนื่องธรรมดา

Controller คนละโหมดมีความหมายของ state ต่างกัน การนำ state เดิมไปใช้ตรง ๆ อาจทำให้กระแส terminal กระโดด จึงกำหนด destination states จาก operating point ก่อนสลับ และยอมรับเมื่อ

\[
\|I^+-I^-\|_\infty\le10^{-10}\ \mathrm{pu}.
\]

นี่คือเงื่อนไข current-continuous transfer

## 10. ทำไมหนึ่งหรือสอง GFM ดีกว่าสี่ GFM

Eigenvalues ขึ้นกับตำแหน่ง อิมพีแดนซ์เครือข่าย และปฏิสัมพันธ์ของ controller ผล enumeration 15 ชุดพบว่า 7 ชุด admissible ชุดดีที่สุดคือ buses 3 และ 6 ที่ margin $-0.568138\ \mathrm{s^{-1}}$ ขณะที่ all-four มี margin $-0.482909\ \mathrm{s^{-1}}$ และสามตัวทุกชุดไม่ผ่าน equilibrium หรือ limit conditions ดังนั้นประโยชน์ไม่ monotonic ตามจำนวน

## 11. ทำไม all-four ผ่าน SSSA แต่ล้มใน TS

SSSA ตรวจ local behaviour รอบ equilibrium เดียว Eigenvalues อยู่ซีกซ้ายหมายถึง perturbation เล็กใกล้จุดนั้นลดลง แต่ไม่ได้รับรองว่า state ขณะสลับอยู่ใน basin of attraction เมื่อ pin all-four ตั้งแต่ SG trip จะเกิด nonlinear hunting และ trajectory จบที่ประมาณ 25.49 s จึงแสดงว่า linear admissibility จำเป็นแต่ไม่เพียงพอ

## 12. ทำไม all-GFL ถูกปฏิเสธทันทีหลัง SG trip

เมื่อ SG หลุด ไม่มีแหล่งกำหนด voltage angle หาก IBR ทั้งหมดเป็น GFL ทุกตัวจะพยายามติดตาม reference ที่ไม่มีอยู่ ปัญหานี้ไม่ใช่เพียงการไม่ลู่เข้า แต่เป็นการขาด voltage-forming reference ตามโครงสร้างของสมการ จึงถูกปฏิเสธที่ $t=20$ s

## 13. PSAT มีบทบาทอะไร

ใช้เป็น independent validation reference เฉพาะ synchronous-machine baseline โดยเปรียบเทียบ inputs และ time grid ที่ตรงกัน ผลอ้างอิงไม่ถูกนำไปแก้ state, parameter หรือ switching decision ของกรณี IBR จึงเป็น validation ไม่ใช่ universal proof

## 14. ทำไมใช้ IEEE 14-bus และผล generalise ได้หรือไม่

IEEE 14-bus ซับซ้อนพอให้ตำแหน่ง IBR ส่งผล แต่ยังเล็กพอให้ enumerate ครบทั้ง 15 non-empty configurations และตรวจทุกชุดที่ equilibrium ของตัวเองได้ ข้อสรุปที่ยืนยันคือสำหรับ resource mix และ chronology นี้เท่านั้น ไม่ได้อ้างว่า buses 3 และ 6 เหมาะกับทุกระบบ

## 15. ทำไม terminal frequency 60.000001 Hz ไม่ใช่หลักฐานว่าใช้งานจริงได้

เป็นผลปลายทางของแบบจำลอง แสดงว่ากลับสู่ nominal operating point ตามสมการ แต่ไม่ครอบคลุม grid-code tests, protection coordination, measurement noise, communication delay, converter harmonics หรือ hardware limits จึงไม่ใช่ operational-readiness claim

## 16. ข้อจำกัด DC-to-AC coupling คืออะไร

แบบจำลอง DC ตอบสนองต่อกำลัง AC แต่คำสั่งแรงดัน AC ยังไม่ถูกจำกัดด้วย modulation index และ available $V_{dc}$ จึงเป็น one-way coupling ผล DC eigenvalue ยืนยัน dynamic ของวงจร DC ได้ แต่ห้ามสรุปเรื่อง DC-limited ride-through งานต่อยอดต้องเพิ่ม modulation limit หรือใช้ EMT model

## 17. งานนี้พิสูจน์อะไร และอะไรเป็นหลักฐานเชิงตัวเลข

ผลทางคณิตศาสตร์ ได้แก่ Schur-complement linearisation, current-continuity condition และ proposition ของ block structure ส่วน PF/SSSA/TS agreement, candidate enumeration และ 250 s chronology เป็น numerical evidence ภายใต้ inputs และเกณฑ์ที่ประกาศไว้ ควรใช้คำว่า "validated" หรือ "established for this case" ไม่ใช้ "proved universally"
