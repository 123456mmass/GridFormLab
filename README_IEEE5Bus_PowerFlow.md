# IEEE 5-Bus Power Flow Analysis

เอกสารนี้อธิบายโปรเจค MATLAB สำหรับคำนวณ Power Flow ของระบบ IEEE 5-bus ด้วยวิธี Newton-Raphson โดยจัดให้ตอบได้ทั้งในเชิงใช้งานและเชิงนำเสนอหน้าห้อง

## 1. ภาพรวมโปรเจค

ไฟล์หลักของโปรเจคคือ [ieee5bus_powerflow.m](/C:/Users/qwert/OneDrive/Desktop/api/ieee5bus_powerflow.m:1) ทำหน้าที่

- โหลดข้อมูล bus และ line
- สร้างเมทริกซ์ `Ybus`
- แยกประเภทบัสเป็น Slack, PV, PQ
- แก้สมการกำลังไฟฟ้าด้วย Newton-Raphson
- คำนวณ line flow และ line loss
- แสดงผลลัพธ์และเก็บไว้ในตัวแปร `results`

ไฟล์ข้อมูลที่ใช้คือ

- [BUS_DATA.m](/C:/Users/qwert/OneDrive/Desktop/api/BUS_DATA.m:1)
- [LINE_DATA.m](/C:/Users/qwert/OneDrive/Desktop/api/LINE_DATA.m:1)

## 2. แหล่งอ้างอิงของโจทย์

ชุดข้อมูลหลักของโปรเจคยึดจากบทความใน IEEE Xplore:

- Ravi Shankar Tiwari, Anurag Priyadarshi, and Om Hari Gupta, "A Comparative Analysis of Numerical Iterative Methods for Power Flow Using IEEE 5-Bus Test System," 2021 International Conference on Applied Electromagnetics, Signal Processing and Communication (AESPC), DOI: [10.1109/AESPC52704.2021.9708525](https://doi.org/10.1109/AESPC52704.2021.9708525)

จุดที่ใช้เป็น "โจทย์" จริงอยู่ใน `Appendix A`

- `Table A1` = bus data
- `Table A2` = line data
- `Table A3` = line MW limits

หมายเหตุสำคัญ:

- บทความนี้เป็น `conference paper` บน IEEE Xplore ไม่ใช่ journal article
- บทความนี้ใช้ได้ดีในฐานะแหล่ง `input data`
- แต่ตารางผลลัพธ์ในตัวบทความ (`Table 2-6`) มีบางจุดที่ไม่สอดคล้องกับ Appendix A แบบตรงตัว จึงไม่ควรอ้างว่าเป็น baseline เชิงตัวเลขแบบ 1:1 โดยไม่อธิบาย

## 3. โครงสร้างไฟล์

| ไฟล์ | หน้าที่ |
|---|---|
| `ieee5bus_powerflow.m` | สคริปต์หลักสำหรับคำนวณ Newton-Raphson power flow |
| `BUS_DATA.m` | ข้อมูล bus ของระบบ IEEE 5-bus |
| `LINE_DATA.m` | ข้อมูลสายส่งของระบบ IEEE 5-bus |
| `README_IEEE5Bus_PowerFlow.md` | เอกสารอธิบายฉบับละเอียด |
| `README_IEEE5Bus_PowerFlow_Submission.md` | เอกสารฉบับย่อสำหรับส่งอาจารย์ |

## 4. ข้อมูลระบบที่ใช้ในโปรเจค

### 4.1 Bus Data

รูปแบบข้อมูลใน [BUS_DATA.m](/C:/Users/qwert/OneDrive/Desktop/api/BUS_DATA.m:1)

```matlab
[Bus_no, Type, V_mag, V_angle, P_gen, Q_gen, P_load, Q_load]
```

ความหมายของชนิดบัส

- `Type = 1` คือ Slack bus
- `Type = 2` คือ PV bus
- `Type = 3` คือ PQ bus

ข้อมูลที่ใช้

| Bus | Type | |V| เริ่มต้น (pu) | Pgen (pu) | Qgen (pu) | Pload (pu) | Qload (pu) |
|---|---|---:|---:|---:|---:|---:|
| 1 | Slack | 1.06 | 0.00 | 0.00 | 0.00 | 0.00 |
| 2 | PV | 1.00 | 0.40 | 0.00 | 0.20 | 0.10 |
| 3 | PQ | 1.00 | 0.00 | 0.00 | 0.45 | 0.15 |
| 4 | PQ | 1.00 | 0.00 | 0.00 | 0.40 | 0.05 |
| 5 | PQ | 1.00 | 0.00 | 0.00 | 0.60 | 0.10 |

หมายเหตุ:

- ในบทความ Appendix A1 ระบุที่ Bus 2 ว่ามี generation `40 MW` และ `30 MVAr`
- แต่ในตัวบทความเองก็ระบุว่า Bus 2 เป็น `PV bus`
- สำหรับการแก้ power flow แบบ PV bus จะกำหนด `P` และ `|V|` ส่วน `Q` เป็นค่าที่ต้องคำนวณออกมา
- ดังนั้นในโค้ดจึงเก็บ Bus 2 เป็น PV bus และให้ `Q_gen` ถูกหาจากผลเฉลยจริง

### 4.2 Line Data

รูปแบบข้อมูลใน [LINE_DATA.m](/C:/Users/qwert/OneDrive/Desktop/api/LINE_DATA.m:1)

```matlab
[From_bus, To_bus, R, X, B_half]
```

ข้อมูลที่ใช้ตาม Appendix A2

| From | To | R (pu) | X (pu) | B/2 (pu) ที่ใช้ในโค้ด |
|---|---|---:|---:|---:|
| 1 | 2 | 0.02 | 0.06 | 0.000 |
| 1 | 3 | 0.08 | 0.24 | 0.025 |
| 2 | 3 | 0.06 | 0.25 | 0.020 |
| 2 | 4 | 0.06 | 0.18 | 0.020 |
| 2 | 5 | 0.04 | 0.12 | 0.015 |
| 3 | 4 | 0.01 | 0.03 | 0.010 |
| 4 | 5 | 0.08 | 0.24 | 0.025 |

หมายเหตุ:

- ใน `Table A2` ของบทความมีหัวคอลัมน์เรื่อง charging ที่เขียนกำกวม
- ในโค้ดนี้ตีความค่าท้ายบรรทัดเป็น per-end charging term ที่ใช้กับ Pi-model
- กรณีสาย `1-2` ในตารางมีเครื่องหมาย `-` จึงตีความเป็น `0`

### 4.3 Base Values

- `S_base = 100 MVA`
- `V_base = 230 kV`
- `f_base = 60 Hz`

ดังนั้น

- `1.0 pu` ของกำลังเท่ากับ `100 MW` หรือ `100 MVAr`
- `1.0 pu` ของแรงดันเท่ากับ `230 kV`

## 5. หลักการทำงานของโปรแกรม

ลำดับหลักของสคริปต์มีดังนี้

1. โหลด `bus_data` และ `line_data`
2. สร้าง `Ybus` จากค่า `R`, `X`, `B/2`
3. แยกบัสเป็น Slack, PV, PQ
4. สร้าง state vector ของมุมแรงดันและแรงดันที่ไม่ทราบค่า
5. คำนวณ `P_calc` และ `Q_calc`
6. สร้าง mismatch vector
7. สร้าง Jacobian matrix
8. แก้สมการ `J * delta_x = mismatch`
9. อัปเดต state vector และวนซ้ำจนกว่าจะลู่เข้า
10. คำนวณ line flow, line loss และสรุปผล

## 6. เกณฑ์การลู่เข้า

ในโค้ดใช้เกณฑ์

```text
max(abs(mismatch)) < tolerance
```

โดยตั้ง

```matlab
tolerance = 1e-6
```

ดังนั้นถ้าจะพูดหน้าห้องสามารถพูดได้ว่า

> โปรแกรมจะหยุด iteration เมื่อค่า mismatch สูงสุดมีค่าน้อยกว่า epsilon ที่กำหนด ซึ่งในงานนี้กำหนดไว้เท่ากับ 10^-6

## 7. ผลการรันที่ตรวจสอบแล้ว

รันจริงด้วย MATLAB จากไฟล์หลักปัจจุบันแล้วระบบลู่เข้าใน `4 iterations`

### 7.1 Mismatch ต่อรอบ

| Iteration | Max mismatch |
|---|---:|
| 1 | 6.000000e-01 |
| 2 | 2.122212e-02 |
| 3 | 8.231133e-05 |
| 4 | 1.150734e-09 |

### 7.2 Bus Voltage Results

| Bus | Type | |V| (pu) | |V| (kV) | Angle (deg) |
|---|---|---:|---:|---:|
| 1 | Slack | 1.0600 | 243.80 | 0.0000 |
| 2 | PV | 1.0000 | 230.00 | -2.0046 |
| 3 | PQ | 0.9871 | 227.02 | -4.8642 |
| 4 | PQ | 0.9840 | 226.31 | -5.1277 |
| 5 | PQ | 0.9716 | 223.46 | -5.7837 |

### 7.3 Generation, Load, and Loss Summary

| รายการ | per-unit | หน่วยจริง |
|---|---:|---:|
| Total Generation P | 1.7115 pu | 171.15 MW |
| Total Generation Q | 0.3595 pu | 35.95 MVAr |
| Total Load P | 1.6500 pu | 165.00 MW |
| Total Load Q | 0.4000 pu | 40.00 MVAr |
| Total Loss P | 0.0615 pu | 6.15 MW |
| Total Loss Q | -0.0405 pu | -4.05 MVAr |

### 7.4 Line Flow Results

| From | To | P_from (pu) | Q_from (pu) | P_loss (pu) | Q_loss (pu) |
|---|---|---:|---:|---:|---:|
| 1 | 2 | 0.8774 | 0.7783 | 0.024487 | 0.073461 |
| 1 | 3 | 0.4341 | 0.1651 | 0.016072 | -0.004232 |
| 2 | 3 | 0.1991 | -0.0111 | 0.002384 | -0.029554 |
| 2 | 4 | 0.2972 | -0.0218 | 0.005301 | -0.023462 |
| 2 | 5 | 0.5566 | 0.0539 | 0.012582 | 0.008585 |
| 3 | 4 | 0.1647 | 0.0378 | 0.000302 | -0.018519 |
| 4 | 5 | 0.0563 | 0.0080 | 0.000348 | -0.046760 |

## 8. ทำไมผลของโปรแกรมไม่เท่ากับ Table 4 ในบทความทุกตัว

จุดนี้สำคัญมากสำหรับการนำเสนอ

เมื่อใช้ข้อมูลจาก `Appendix A1/A2` ของบทความนี้ตรง ๆ แล้ว ผลจากโค้ดจะไม่ทับกับ `Table 4` แบบ 1:1 เช่น

- บทความระบุว่า Bus 2 เป็น PV bus แต่ `Table 4` แสดง `|V| = 1.02`
- `Table 4` ยังมี reactive injection ที่บางบัสซึ่งไม่ได้อธิบายชัดใน Appendix A
- ในตัวบทความเองยังมีการอ้างเลขตารางคลาดเคลื่อนบางจุด

ดังนั้นแนวที่ใช้ในโปรเจคนี้คือ

- ใช้ `Appendix A` เป็นแหล่งของ `โจทย์`
- ใช้ผลจากโปรแกรมเป็นผลเฉลยของ Newton-Raphson สำหรับ dataset นั้น
- ไม่อ้างว่า `Table 4` เป็น baseline ที่ต้องตรงทุกหลัก

ถ้าอาจารย์ถาม สามารถตอบได้ว่า

> งานนี้ยึด Appendix A ของบทความ IEEE Xplore เป็นแหล่งข้อมูล bus และ line ของระบบ IEEE 5-bus ส่วนผลลัพธ์ใช้ค่าที่คำนวณได้จากโปรแกรม Newton-Raphson โดยตรง เนื่องจากตารางผลในบทความมีบางจุดที่ไม่สอดคล้องกับข้อมูลตั้งต้นอย่างสมบูรณ์

## 9. วิธีรันโปรแกรม

เปิด MATLAB แล้วรัน

```matlab
cd('C:\Users\qwert\OneDrive\Desktop\api')
ieee5bus_powerflow
```

โปรแกรมจะแสดง

- รายงานผลใน Command Window
- กราฟแรงดันไฟฟ้า
- กราฟมุมแรงดัน
- กราฟการลู่เข้าของ Newton-Raphson

## 10. สรุปสำหรับใช้พูดหน้าห้อง

ประโยคสั้นที่ใช้ได้:

> โครงงานนี้เป็นการคำนวณ Power Flow ของระบบ IEEE 5-bus ด้วยวิธี Newton-Raphson ใน MATLAB โดยใช้ข้อมูลตั้งต้นจาก Appendix A ของบทความใน IEEE Xplore แล้วสร้าง Ybus, คำนวณ mismatch, สร้าง Jacobian และวนซ้ำจนลู่เข้า ผลที่ได้ลู่เข้าใน 4 iterations และให้ค่าการสูญเสียกำลังจริงรวมประมาณ 6.15 MW

ถ้าต้องอธิบายเพิ่ม:

- Slack bus คือ Bus 1
- PV bus คือ Bus 2
- PQ bus คือ Bus 3, 4, 5
- เกณฑ์หยุดคือ `max mismatch < 10^-6`
- ข้อมูล bus/line อ้างอิงจาก Appendix A ของบทความ IEEE Xplore
- ผลลัพธ์หลักใช้ค่าที่โปรแกรมคำนวณได้จริง ไม่ยึดตารางผลในบทความแบบตรงตัวทุกช่อง

## 11. References

1. Ravi Shankar Tiwari, Anurag Priyadarshi, and Om Hari Gupta, "A Comparative Analysis of Numerical Iterative Methods for Power Flow Using IEEE 5-Bus Test System," 2021 International Conference on Applied Electromagnetics, Signal Processing and Communication (AESPC), IEEE Xplore, 2021. DOI: [10.1109/AESPC52704.2021.9708525](https://doi.org/10.1109/AESPC52704.2021.9708525)
2. J. D. Glover, M. S. Sarma, and T. J. Overbye, *Power System Analysis and Design*.
3. H. Saadat, *Power System Analysis*.
