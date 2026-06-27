%% LINE_DATA.m - IEEE 5-Bus System Transmission Line Data
%  =======================================================
%  ไฟล์ข้อมูลสายส่งสำหรับระบบ IEEE 5-bus
%  ใช้ร่วมกับโปรแกรม Power Flow Analysis
%
%  รูปแบบข้อมูล: [From_bus, To_bus, R, X, B_charge/2]
%
%  หน่วย: ทั้งหมดเป็น per-unit (pu) บนฐาน S_base และ V_base
%
%  โมเดลสายส่ง: Pi-model (สำหรับสายส่งขนาดกลาง)
%    - R, X: อนุกรม impedance
%    - B/2: charging susceptance แบ่งเท่ากันทั้งสองฝั่ง

function line_data = LINE_DATA()

%% -------------------------------------------------------------------------
%  ข้อมูลสายส่ง (Transmission Line Data)
%  -------------------------------------------------------------------------
%  คอลัมน์: [From, To, R, X, B/2]
%
%  หมายเหตุ:
%    - R = ความต้านทาน (Resistance) ใน pu
%    - X = ความรีแอกแตนซ์ (Reactance) ใน pu
%    - B/2 = ครึ่งหนึ่งของ charging susceptance ใน pu
%
%  สูตรคำนวณ admittance:
%    y_series = 1 / (R + jX) = G + jB
%    y_shunt = j * (B/2)  (แต่ละฝั่งของ Pi-model)

line_data = [
    % From  To    R       X       B/2
    1      2     0.02    0.06    0.00;    % Line 1-2
    1      3     0.08    0.24    0.025;   % Line 1-3
    2      3     0.06    0.25    0.02;    % Line 2-3
    2      4     0.06    0.18    0.02;    % Line 2-4
    2      5     0.04    0.12    0.015;   % Line 2-5
    3      4     0.01    0.03    0.01;    % Line 3-4
    4      5     0.08    0.24    0.025    % Line 4-5
];

end

%% -------------------------------------------------------------------------
%  ฟังก์ชันเสริมสำหรับคำนวณค่าต่างๆ จากข้อมูลสายส่ง
%  -------------------------------------------------------------------------

function line_params = calculate_line_parameters(line_data)
%  คำนวณพารามิเตอร์ของสายส่ง
%  Input:  line_data  - ข้อมูลสายส่งจาก get_line_data()
%  Output: line_params - โครงสร้างข้อมูลพารามิเตอร์

num_lines = size(line_data, 1);

% Pre-allocate arrays
line_params.R = line_data(:, 3);
line_params.X = line_data(:, 4);
line_params.B_half = line_data(:, 5);

% คำนวณ series impedance และ admittance
line_params.Z = line_params.R + 1i * line_params.X;         % Impedance อนุกรม
line_params.Y_series = 1 ./ line_params.Z;                   % Admittance อนุกรม
line_params.G = real(line_params.Y_series);                  % Conductance
line_params.B = imag(line_params.Y_series);                  % Susceptance

% คำนวณกำลังไฟฟ้าสูญเสียสูงสุดที่รับได้ (สำหรับ reference)
line_params.S_max = ones(num_lines, 1);  % สามารถกำหนด rating ได้ที่นี่

end

function line_stats = get_line_statistics(line_data)
%  สถิติข้อมูลสายส่ง
%  Input:  line_data - ข้อมูลสายส่งจาก get_line_data()
%  Output: line_stats - โครงสร้างข้อมูลสถิติ

num_lines = size(line_data, 1);

line_stats.num_lines = num_lines;
line_stats.total_R = sum(line_data(:, 3));
line_stats.total_X = sum(line_data(:, 4));
line_stats.total_B_charge = 2 * sum(line_data(:, 5));

% คำนวณ X/R ratio เฉลี่ย (ตัวบ่งชี้คุณภาพสายส่ง)
XR_ratios = line_data(:, 4) ./ line_data(:, 3);
line_stats.avg_XR_ratio = mean(XR_ratios);
line_stats.min_XR_ratio = min(XR_ratios);
line_stats.max_XR_ratio = max(XR_ratios);

end

function connectivity = get_bus_connectivity(line_data, num_buses)
%  ตรวจสอบการเชื่อมต่อของบัส
%  Input:  line_data  - ข้อมูลสายส่ง
%          num_buses  - จำนวนบัสทั้งหมด
%  Output: connectivity - เมทริกซ์แสดงการเชื่อมต่อ

connectivity = zeros(num_buses, num_buses);

for i = 1:size(line_data, 1)
    from = line_data(i, 1);
    to = line_data(i, 2);
    connectivity(from, to) = 1;
    connectivity(to, from) = 1;  % สมมาตร
end

end
