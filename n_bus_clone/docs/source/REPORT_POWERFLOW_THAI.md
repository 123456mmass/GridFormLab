# รายงานสรุปการอัปเกรด n-bus Power Flow

## อ้างอิงหลัก

ใช้หนังสือ `Power System Analysis` ของ Hadi Saadat จากไฟล์:

`C:\Users\qwert\OneDrive\Desktop\api\power system analysis - hadi saadat_320503100.pdf`

เคสที่นำมาใช้ตรวจสอบ:

- Example 6.7: ระบบ 3 bus แบบ PQ load, หน้า 212-216
- Example 6.8: ระบบ 3 bus ที่มี PV generator bus, หน้า 216-219
- Example 6.9: IEEE 30-bus sample system, หน้า 224-228

## สิ่งที่เพิ่มในโปรแกรม

- เพิ่ม Newton-Raphson พร้อม PV-to-PQ switching เมื่อค่า reactive generation เกิน `Qmin/Qmax`
- เพิ่ม Gauss-Seidel สำหรับ Slack/PV/PQ bus
- เพิ่ม CPF 2 แบบ: load-scaling และ predictor-corrector
- เพิ่ม helper กลาง `pf_*.m` สำหรับสร้าง Ybus, mismatch, Jacobian, report, plot และ export
- เพิ่ม benchmark cases จาก Saadat: `case_saadat_example_6_7`, `case_saadat_example_6_8`, `case_saadat_ieee30bus`
- เพิ่ม `run_powerflow_tests.m` สำหรับตรวจผลอัตโนมัติ
- เพิ่ม export เป็น CSV, summary text และ PNG figure

## วิธีรันทดสอบ

```matlab
cd('C:\Users\qwert\OneDrive\Desktop\api\n_bus_clone')
summary = run_powerflow_tests();
```

## วิธีเปิด GUI

```matlab
cd('C:\Users\qwert\OneDrive\Desktop\api\n_bus_clone')
run_gui
```

ใน GUI สามารถเลือกได้:

- Case built-in เช่น 5-bus demo, 14-bus demo, Saadat 3-bus PQ/PV, Saadat 30-bus reference
- Custom n-bus case ผ่านปุ่ม `Browse Custom n-bus Case` โดยเลือกไฟล์ `.m` ที่ return `case_data` หรือ `.mat` ที่มี `case_data`
- Method เช่น Newton-Raphson, Gauss-Seidel, CPF Load Scaling, CPF Predictor-Corrector
- ค่า tolerance, max iteration, acceleration factor, Q-limit switching และ CPF options
- ปุ่ม `Run Tests` สำหรับทดสอบ reference ทั้งหมด
- ปุ่ม `Export Last Result` สำหรับ export CSV, summary text และ PNG
- ปุ่ม `Open Separate Plots` สำหรับเปิดกราฟแยกหน้าต่างใหญ่ โดยมีทั้ง voltage magnitude, voltage angle, convergence และ CPF curve
- ปุ่ม `3D / CPF Ref Plots` สำหรับเปิดกราฟ 3D benchmark แบบ solver เทียบ system และกราฟ CPF predictor-corrector แบบมี predictor/corrector/nose point/loadability margin

หมายเหตุ: กราฟ 3D ที่เพิ่มเป็นผลของ PF เท่านั้น เช่น loss, iteration, computation time, minimum voltage, voltage angle spread ยังไม่ใช่ OPF เพราะโปรเจกต์นี้ยังไม่มี OPF solver

## วิธีรันเคสจากหนังสือ

```matlab
opt = struct('plot_results', false, 'verbose', true);

r67 = powerflow_gauss_seidel(case_saadat_example_6_7(), opt);
r68 = powerflow_gauss_seidel(case_saadat_example_6_8(), opt);
r30 = powerflow_newton_raphson(case_saadat_ieee30bus(), opt);
```

## วิธี export ผล

```matlab
paths = pf_export_results(r30, fullfile(pwd, 'output'), 'saadat_ieee30_nr');
```

ไฟล์ที่ได้ประกอบด้วย:

- ตาราง bus result เป็น CSV
- ตาราง line flow/loss เป็น CSV
- summary text
- รูปกราฟ PNG

## หมายเหตุ

ผลของ Example 6.7 และ 6.8 เทียบกับค่าที่พิมพ์ในหนังสือโดยตรง ส่วน IEEE 30-bus เทียบ selected bus values และ generation totals เพราะผลในหนังสือมาจากโปรแกรม Gauss-Seidel พร้อมวิธีจัดการ var limit เฉพาะของผู้เขียน จึงอาจต่างจาก Newton-Raphson เล็กน้อยในค่า Q รวม แต่แรงดันและมุมอยู่ใน tolerance ที่กำหนด
