# รายงานย่อ
## IEEE 5-Bus Power Flow ด้วยวิธี Newton-Raphson

## 1. บทนำ

รายงานฉบับย่อนี้สรุปการวิเคราะห์การไหลของกำลังไฟฟ้าในระบบ IEEE 5-bus ด้วยวิธี Newton-Raphson โดยใช้ MATLAB เพื่อหาค่าขนาดแรงดัน มุมแรงดัน การไหลกำลังในสายส่ง และกำลังสูญเสียของระบบ

## 2. แหล่งข้อมูลอ้างอิง

งานนี้อ้างอิงข้อมูลจาก 2 แหล่งหลักตามข้อกำหนด ได้แก่

- `IEEE Xplore` ใช้เป็นแหล่งข้อมูลตั้งต้นของระบบ  
  Ravi Shankar Tiwari, Anurag Priyadarshi, and Om Hari Gupta, "A Comparative Analysis of Numerical Iterative Methods for Power Flow Using IEEE 5-Bus Test System," AESPC 2021, DOI: [10.1109/AESPC52704.2021.9708525](https://doi.org/10.1109/AESPC52704.2021.9708525)

- `ScienceDirect` ใช้เป็นแหล่งตรวจสอบความสมเหตุสมผลของผลลัพธ์  
  E. O. Ezugwu et al., "Wind energy penetration impact on active power flow in developing grids," *Scientific African*, 2022, DOI: [10.1016/j.sciaf.2022.e01422](https://doi.org/10.1016/j.sciaf.2022.e01422)

## 3. ข้อมูลระบบ

### 3.1 ประเภทบัส

- Bus 1 เป็น `Slack Bus`
- Bus 2 เป็น `PV Bus`
- Bus 3, 4 และ 5 เป็น `PQ Bus`

### 3.2 ค่าฐาน

- `S_base = 100 MVA`
- `V_base = 230 kV`
- `f_base = 60 Hz`

### 3.3 ข้อมูลบัส

| Bus | Type | \|V\| เริ่มต้น (pu) | Pgen (pu) | Pload (pu) | Qload (pu) |
|---|---|---:|---:|---:|---:|
| 1 | Slack | 1.06 | 0.00 | 0.00 | 0.00 |
| 2 | PV | 1.00 | 0.40 | 0.20 | 0.10 |
| 3 | PQ | 1.00 | 0.00 | 0.45 | 0.15 |
| 4 | PQ | 1.00 | 0.00 | 0.40 | 0.05 |
| 5 | PQ | 1.00 | 0.00 | 0.60 | 0.10 |

### 3.4 ข้อมูลสายส่ง

| From | To | R (pu) | X (pu) | B/2 (pu) |
|---|---|---:|---:|---:|
| 1 | 2 | 0.02 | 0.06 | 0.000 |
| 1 | 3 | 0.08 | 0.24 | 0.025 |
| 2 | 3 | 0.06 | 0.25 | 0.020 |
| 2 | 4 | 0.06 | 0.18 | 0.020 |
| 2 | 5 | 0.04 | 0.12 | 0.015 |
| 3 | 4 | 0.01 | 0.03 | 0.010 |
| 4 | 5 | 0.08 | 0.24 | 0.025 |

## 4. วิธีการคำนวณ

โปรแกรมสร้างเมทริกซ์ `Ybus` จากข้อมูลสายส่ง แล้วใช้วิธี Newton-Raphson ในการแก้สมการ Power Flow แบบเชิงซ้ำ โดยในแต่ละรอบจะคำนวณ mismatch และ Jacobian matrix เพื่อปรับค่าตัวแปรสถานะจนกว่าระบบจะลู่เข้า

เกณฑ์การลู่เข้าที่ใช้คือ

```text
max(abs(mismatch)) < 10^-6
```

## 5. ผลการคำนวณ

โปรแกรมลู่เข้าใน `4 iterations`

### 5.1 ค่าความคลาดเคลื่อนสูงสุด

| Iteration | Max mismatch |
|---|---:|
| 1 | 6.000000e-01 |
| 2 | 2.122212e-02 |
| 3 | 8.231133e-05 |
| 4 | 1.150734e-09 |

### 5.2 ผลแรงดันของแต่ละบัส

| Bus | Type | \|V\| (pu) | Angle (deg) |
|---|---|---:|---:|
| 1 | Slack | 1.0600 | 0.0000 |
| 2 | PV | 1.0000 | -2.0046 |
| 3 | PQ | 0.9871 | -4.8642 |
| 4 | PQ | 0.9840 | -5.1277 |
| 5 | PQ | 0.9716 | -5.7837 |

### 5.3 สรุปกำลังรวมของระบบ

| รายการ | per-unit | หน่วยจริง |
|---|---:|---:|
| Total Generation P | 1.7115 pu | 171.15 MW |
| Total Generation Q | 0.3595 pu | 35.95 MVAr |
| Total Load P | 1.6500 pu | 165.00 MW |
| Total Load Q | 0.4000 pu | 40.00 MVAr |
| Total Loss P | 0.0615 pu | 6.15 MW |
| Total Loss Q | -0.0405 pu | -4.05 MVAr |

### 5.4 ผลการไหลกำลังในสายส่ง

| From | To | P_from (pu) | Q_from (pu) |
|---|---|---:|---:|
| 1 | 2 | 0.8774 | 0.7783 |
| 1 | 3 | 0.4341 | 0.1651 |
| 2 | 3 | 0.1991 | -0.0111 |
| 2 | 4 | 0.2972 | -0.0218 |
| 2 | 5 | 0.5566 | 0.0539 |
| 3 | 4 | 0.1647 | 0.0378 |
| 4 | 5 | 0.0563 | 0.0080 |

## 6. สรุป

ผลการศึกษาแสดงให้เห็นว่าโปรแกรม MATLAB ที่พัฒนาขึ้นสามารถคำนวณ Power Flow ของระบบ IEEE 5-bus ได้สำเร็จด้วยวิธี Newton-Raphson โดยลู่เข้าได้อย่างรวดเร็วภายใน 4 iterations และให้ค่าผลลัพธ์ของแรงดัน กำลังผลิต และกำลังสูญเสียในระดับที่สมเหตุสมผล

แนวทางการอ้างอิงในรายงานนี้ใช้ `IEEE Xplore` เป็นแหล่งข้อมูลโจทย์หลัก และใช้ `ScienceDirect` เป็นแหล่งช่วยตรวจสอบความสมเหตุสมผลของผลลัพธ์ ซึ่งเป็นแนวทางที่เหมาะสมและสามารถอธิบายได้ชัดเจนในเชิงวิชาการ

## 7. เอกสารอ้างอิง

1. Ravi Shankar Tiwari, Anurag Priyadarshi, and Om Hari Gupta, "A Comparative Analysis of Numerical Iterative Methods for Power Flow Using IEEE 5-Bus Test System," AESPC 2021, IEEE Xplore. DOI: [10.1109/AESPC52704.2021.9708525](https://doi.org/10.1109/AESPC52704.2021.9708525)
2. E. O. Ezugwu et al., "Wind energy penetration impact on active power flow in developing grids," *Scientific African*, 2022. DOI: [10.1016/j.sciaf.2022.e01422](https://doi.org/10.1016/j.sciaf.2022.e01422)
