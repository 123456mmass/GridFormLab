%% BUS_DATA.m - IEEE 5-Bus System Bus Data
%  ==========================================
%  ไฟล์ข้อมูลบัสสำหรับระบบ IEEE 5-bus
%  ใช้ร่วมกับโปรแกรม Power Flow Analysis
%
%  รูปแบบข้อมูล: [Bus_no, Type, V_mag, V_angle, P_gen, Q_gen, P_load, Q_load]
%
%  ประเภทของบัส (Bus Types):
%    1 = Slack Bus (Swing Bus) - บัสอ้างอิง
%    2 = PV Bus (Generator Bus) - บัสที่มีเครื่องกำเนิดไฟฟ้า
%    3 = PQ Bus (Load Bus) - บัสโหลด
%
%  หน่วย:
%    - V_mag: per-unit (pu)
%    - V_angle: องศา (degree)
%    - P_gen, Q_gen, P_load, Q_load: per-unit (pu) บนฐาน S_base

function bus_data = BUS_DATA()

%% -------------------------------------------------------------------------
%  ข้อมูลบัส (Bus Data)
%  -------------------------------------------------------------------------
%  คอลัมน์: [Bus#, Type, |V|, angle, Pgen, Qgen, Pload, Qload]
%
%  หมายเหตุ:
%    - Slack Bus (Type=1): P_gen และ Q_gen จะถูกคำนวณโดยโปรแกรม
%    - PV Bus (Type=2): Q_gen จะถูกคำนวณ, P_gen กำหนดไว้แล้ว
%    - PQ Bus (Type=3): P_gen = Q_gen = 0 (ไม่มีเครื่องกำเนิด)

bus_data = [
    % Bus  Type  |V|   angle   Pgen   Qgen   Pload   Qload
    1     1      1.06  0       0      0      0       0;       % Slack Bus
    2     2      1.00  0       0.40   0      0.20    0.10;    % PV Bus (Generator + Load)
    3     3      1.00  0       0      0      0.45    0.15;    % PQ Bus (Load)
    4     3      1.00  0       0      0      0.40    0.05;    % PQ Bus (Load)
    5     3      1.00  0       0      0      0.60    0.10     % PQ Bus (Load)
];

end

%% -------------------------------------------------------------------------
%  ฟังก์ชันเสริมสำหรับดึงข้อมูลบัสเฉพาะส่วน
%  -------------------------------------------------------------------------

function base_values = get_base_values()
%  ค่าฐานระบบ (Base Values)
%
%  ใช้สำหรับแปลงค่า per-unit เป็นค่าจริง และกลับกัน

base_values.S_base = 100;    % กำลังไฟฟ้าฐาน (MVA)
base_values.V_base = 230;    % แรงดันไฟฟ้าฐาน (kV)
base_values.f_base = 60;     % ความถี่ (Hz)

end

function bus_types = get_bus_types_info()
%  คำอธิบายประเภทของบัส
%  ใช้สำหรับแสดงผลและเอกสาร

bus_types = struct( ...
    'slack', struct('code', 1, 'name', 'Slack Bus', 'desc', 'บัสอ้างอิง - กำหนด |V| และ angle'), ...
    'pv',    struct('code', 2, 'name', 'PV Bus', 'desc', 'บัส generator - กำหนด P และ |V|'), ...
    'pq',    struct('code', 3, 'name', 'PQ Bus', 'desc', 'บัสโหลด - กำหนด P และ Q') ...
);

end

function stats = get_bus_statistics(bus_data)
%  สถิติข้อมูลบัส
%  Input:  bus_data - ข้อมูลบัสจาก get_bus_data()
%  Output: stats    - โครงสร้างข้อมูลสถิติ

num_buses = size(bus_data, 1);

stats.total_buses = num_buses;
stats.num_slack = sum(bus_data(:, 2) == 1);
stats.num_pv = sum(bus_data(:, 2) == 2);
stats.num_pq = sum(bus_data(:, 2) == 3);

stats.total_P_load = sum(bus_data(:, 7));
stats.total_Q_load = sum(bus_data(:, 8));
stats.total_P_gen = sum(bus_data(:, 5));

end
