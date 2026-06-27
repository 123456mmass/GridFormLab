# IEEE 5-Bus Power Flow Using Newton-Raphson

## 1. บทนำ

โปรเจคนี้เป็นการวิเคราะห์ Power Flow ของระบบ IEEE 5-bus ด้วยวิธี Newton-Raphson ใน MATLAB เพื่อหาค่าแรงดัน มุมแรงดัน การไหลกำลังในสายส่ง และการสูญเสียกำลังในระบบไฟฟ้า

## 2. แหล่งข้อมูลที่ใช้

ข้อมูลระบบ IEEE 5-bus ในโปรเจคนี้อ้างอิงจาก Appendix A ของบทความใน IEEE Xplore:

- Ravi Shankar Tiwari, Anurag Priyadarshi, and Om Hari Gupta, "A Comparative Analysis of Numerical Iterative Methods for Power Flow Using IEEE 5-Bus Test System," AESPC 2021, DOI: [10.1109/AESPC52704.2021.9708525](https://doi.org/10.1109/AESPC52704.2021.9708525)

โดยใช้

- `Table A1` เป็นข้อมูล bus
- `Table A2` เป็นข้อมูลสายส่ง

## 3. โครงสร้างไฟล์

| ไฟล์ | หน้าที่ |
|---|---|
| `ieee5bus_powerflow.m` | สคริปต์หลัก |
| `BUS_DATA.m` | ข้อมูล bus |
| `LINE_DATA.m` | ข้อมูลสายส่ง |

## 4. ข้อมูลระบบ

ระบบที่ใช้ประกอบด้วย

- 1 Slack bus
- 1 PV bus
- 3 PQ bus
- 7 สายส่ง

ค่าฐานของระบบ

- `S_base = 100 MVA`
- `V_base = 230 kV`
- `f_base = 60 Hz`

ตัวอย่างข้อมูลที่ใช้

| Bus | Type | |V| เริ่มต้น (pu) | Pgen (pu) | Pload (pu) | Qload (pu) |
|---|---|---:|---:|---:|---:|
| 1 | Slack | 1.06 | 0.00 | 0.00 | 0.00 |
| 2 | PV | 1.00 | 0.40 | 0.20 | 0.10 |
| 3 | PQ | 1.00 | 0.00 | 0.45 | 0.15 |
| 4 | PQ | 1.00 | 0.00 | 0.40 | 0.05 |
| 5 | PQ | 1.00 | 0.00 | 0.60 | 0.10 |

| From | To | R (pu) | X (pu) | B/2 (pu) |
|---|---|---:|---:|---:|
| 1 | 2 | 0.02 | 0.06 | 0.000 |
| 1 | 3 | 0.08 | 0.24 | 0.025 |
| 2 | 3 | 0.06 | 0.25 | 0.020 |
| 2 | 4 | 0.06 | 0.18 | 0.020 |
| 2 | 5 | 0.04 | 0.12 | 0.015 |
| 3 | 4 | 0.01 | 0.03 | 0.010 |
| 4 | 5 | 0.08 | 0.24 | 0.025 |

หมายเหตุ:

- Bus 2 ถูกจำลองเป็น PV bus ดังนั้น reactive power ของบัสนี้จะเป็นค่าที่โปรแกรมคำนวณได้

## 5. วิธีการโดยสรุป

โปรแกรมทำงานตามลำดับดังนี้

1. โหลดข้อมูล bus และ line
2. สร้างเมทริกซ์ `Ybus`
3. คำนวณ mismatch ของกำลังจริงและกำลังรีแอกทีฟ
4. สร้าง Jacobian matrix
5. แก้สมการด้วย Newton-Raphson จนกว่าค่า mismatch จะต่ำกว่าเกณฑ์
6. คำนวณ line flow และ line loss

เกณฑ์การลู่เข้าที่ใช้คือ

```text
max(abs(mismatch)) < 10^-6
```

## 6. วิธีใช้งาน

เปิด MATLAB แล้วรันคำสั่ง

```matlab
cd('C:\Users\qwert\OneDrive\Desktop\api')
ieee5bus_powerflow
```

## 7. ผลลัพธ์หลัก

จากการรันโปรแกรม ระบบลู่เข้าใน `4 iterations`

| Bus | Type | |V| (pu) | Angle (deg) |
|---|---|---:|---:|
| 1 | Slack | 1.0600 | 0.0000 |
| 2 | PV | 1.0000 | -2.0046 |
| 3 | PQ | 0.9871 | -4.8642 |
| 4 | PQ | 0.9840 | -5.1277 |
| 5 | PQ | 0.9716 | -5.7837 |

| รายการ | per-unit | หน่วยจริง |
|---|---:|---:|
| Total Generation P | 1.7115 pu | 171.15 MW |
| Total Generation Q | 0.3595 pu | 35.95 MVAr |
| Total Load P | 1.6500 pu | 165.00 MW |
| Total Load Q | 0.4000 pu | 40.00 MVAr |
| Total Loss P | 0.0615 pu | 6.15 MW |
| Total Loss Q | -0.0405 pu | -4.05 MVAr |

## 8. หมายเหตุ

ตารางผลลัพธ์ในบทความต้นทางมีบางจุดที่ไม่สอดคล้องกับข้อมูลใน Appendix A แบบตรงตัว ดังนั้นในงานนี้จึงใช้ Appendix A เป็นแหล่งข้อมูลตั้งต้นของโจทย์ และใช้ผลลัพธ์ที่คำนวณได้จากโปรแกรมเป็นผลลัพธ์หลักของโครงงาน

## 9. เอกสารอ้างอิง

1. Ravi Shankar Tiwari, Anurag Priyadarshi, and Om Hari Gupta, "A Comparative Analysis of Numerical Iterative Methods for Power Flow Using IEEE 5-Bus Test System," AESPC 2021, IEEE Xplore. DOI: [10.1109/AESPC52704.2021.9708525](https://doi.org/10.1109/AESPC52704.2021.9708525)
2. H. Saadat, *Power System Analysis*.
3. J. D. Glover, M. S. Sarma, and T. J. Overbye, *Power System Analysis and Design*.
