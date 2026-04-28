%% IEEE 5-Bus Power Flow Analysis using Newton-Raphson Method
%  ================================================================
%  โปรแกรมคำนวณ Power Flow สำหรับระบบ 5 Bus โดยใช้วิธี Newton-Raphson
%  อ้างอิงตามมาตรฐาน IEEE 5-bus test system
%
%  ผู้เขียน: Generated for Power System Analysis
%  วันที่: 2026-04-17
%  วิธีคำนวณ: Newton-Raphson Iterative Method
%
%  โครงสร้างไฟล์:
%    - ieee5bus_powerflow.m      : ไฟล์หลัก (Main script)
%    - BUS_DATA.m                : ข้อมูลบัส (Bus data functions)
%    - LINE_DATA.m               : ข้อมูลสายส่ง (Line data functions)

clear; clc; close all;

%% =========================================================================
%  ส่วนที่ 1: โหลดข้อมูลระบบ (Load System Data)
%  =========================================================================

fprintf('============================================================\n');
fprintf('       IEEE 5-BUS POWER FLOW ANALYSIS\n');
fprintf('       Newton-Raphson Method\n');
fprintf('============================================================\n\n');

% -------------------------------------------------------------------------
%  1.1 ข้อมูลบัส (BUS DATA) - เรียกจากฟังก์ชันในไฟล์ BUS_DATA.m
%  -------------------------------------------------------------------------
%  รูปแบบ: [Bus_no, Type, V_mag, V_angle, P_gen, Q_gen, P_load, Q_load]
%
%  ประเภทของบัส (Bus Types):
%    1 = Slack Bus (Swing Bus) - บัสอ้างอิง
%    2 = PV Bus (Generator Bus) - บัสที่มีเครื่องกำเนิดไฟฟ้า
%    3 = PQ Bus (Load Bus) - บัสโหลด

bus_data = BUS_DATA();        % โหลดข้อมูลบัสจากไฟล์ BUS_DATA.m

% ค่าฐานระบบ (Base Values) - กำหนดในไฟล์ BUS_DATA.m
S_base = 100;    % กำลังไฟฟ้าฐาน (MVA)
V_base = 230;    % แรงดันไฟฟ้าฐาน (kV)
f_base = 60;     % ความถี่ (Hz)

fprintf('System Base Values:\n');
fprintf('  S_base = %d MVA\n', S_base);
fprintf('  V_base = %d kV\n', V_base);
fprintf('  Frequency = %d Hz\n\n', f_base);

num_buses = size(bus_data, 1);    % จำนวนบัสทั้งหมด

fprintf('Bus Data:\n');
fprintf('  Number of buses: %d\n', num_buses);
fprintf('  Slack buses: %d\n', sum(bus_data(:,2) == 1));
fprintf('  PV buses: %d\n', sum(bus_data(:,2) == 2));
fprintf('  PQ buses: %d\n\n', sum(bus_data(:,2) == 3));

% -------------------------------------------------------------------------
%  1.2 ข้อมูลสายส่ง (LINE DATA) - เรียกจากฟังก์ชันในไฟล์ LINE_DATA.m
%  -------------------------------------------------------------------------
%  รูปแบบ: [From_bus, To_bus, R, X, B_charge/2] (หน่วย per-unit)
%
%  โมเดลสายส่ง: Pi-model (สำหรับสายส่งขนาดกลาง)

line_data = LINE_DATA();      % โหลดข้อมูลสายส่งจากไฟล์ LINE_DATA.m

num_lines = size(line_data, 1);   % จำนวนสายส่ง

fprintf('Transmission Line Data:\n');
fprintf('  Number of lines: %d\n\n', num_lines);

%% =========================================================================
%  ส่วนที่ 2: สร้างเมทริกซ์แอดมิทแตนซ์ (Y-Bus Matrix Formation)
%  =========================================================================
%  Ybus คือเมทริกซ์แสดง admittance ของระบบ ใช้ในการคำนวณกระแสและกำลังไฟฟ้า

fprintf('Building Y-bus matrix...\n');

% เริ่มต้นด้วยเมทริกซ์ศูนย์ขนาด num_buses x num_buses
Ybus = zeros(num_buses, num_buses);  % เมทริกซ์ Ybus (complex)
Gbus = zeros(num_buses, num_buses);  % เมทริกซ์ conductance (ส่วนจริง)
Bbus = zeros(num_buses, num_buses);  % เมทริกซ์ susceptance (ส่วนจินตภาพ)

% วนลูปทุกสายส่งเพื่อสะสมค่า admittance เข้า Ybus
for i = 1:num_lines
    from = line_data(i, 1);  % บัสต้นทาง
    to = line_data(i, 2);    % บัสปลายทาง
    R = line_data(i, 3);     % ความต้านทาน
    X = line_data(i, 4);     % ความรีแอกแตนซ์
    B_half = line_data(i, 5); % Charging susceptance/2

    % คำนวณ series admittance: y_series = 1/(R + jX)
    z = R + 1j * X;          % Impedance อนุกรม
    y = 1 / z;               % Admittance อนุกรม (G + jB)

    % อัปเดต diagonal elements (Y_ii, Y_jj)
    Ybus(from, from) = Ybus(from, from) + y + 1j * B_half;
    Ybus(to, to) = Ybus(to, to) + y + 1j * B_half;

    % อัปเดต off-diagonal elements (Y_ij, Y_ji)
    Ybus(from, to) = Ybus(from, to) - y;
    Ybus(to, from) = Ybus(to, from) - y;
end

% แยกส่วนจริง (G) และส่วนจินตภาพ (B) ของ Ybus
Gbus = real(Ybus);  % Conductance matrix
Bbus = imag(Ybus);  % Susceptance matrix

fprintf('Y-bus matrix constructed successfully.\n');
fprintf('  System has %d buses and %d transmission lines\n\n', num_buses, num_lines);

%% =========================================================================
%  ส่วนที่ 3: กำหนดค่าเริ่มต้นและจัดประเภทบัส (Initialization)
%  =========================================================================

% แยกข้อมูลบัสเป็น array ต่างๆ เพื่อความง่ายในการคำนวณ
bus_type = bus_data(:, 2);    % ชนิดของบัส (1=Slack, 2=PV, 3=PQ)
V_mag = bus_data(:, 3);       % ขนาดแรงดันเริ่มต้น (pu)
V_angle = bus_data(:, 4);     % มุมแรงดันเริ่มต้น (degree)
P_gen = bus_data(:, 5);       % กำลังไฟฟ้าจริงที่ผลิต (pu)
Q_gen = bus_data(:, 6);       % กำลังไฟฟ้ารีแอกทีฟที่ผลิต (pu)
P_load = bus_data(:, 7);      % กำลังไฟฟ้าจริงที่โหลด (pu)
Q_load = bus_data(:, 8);      % กำลังไฟฟ้ารีแอกทีฟที่โหลด (pu)

% คำนวณกำลังไฟฟ้าสุทธิที่ฉีดเข้าบัส (Net power injection)
P_net = P_gen - P_load;
Q_net = Q_gen - Q_load;

% -------------------------------------------------------------------------
%  3.1 จัดหมวดหมู่บัสและตัวแปรที่ไม่ทราบค่า
%  -------------------------------------------------------------------------
slack_buses = find(bus_type == 1);   % ดัชนี Slack bus
pv_buses = find(bus_type == 2);      % ดัชนี PV bus
pq_buses = find(bus_type == 3);      % ดัชนี PQ bus

num_slack = length(slack_buses);
num_pv = length(pv_buses);
num_pq = length(pq_buses);

fprintf('Bus Classification:\n');
fprintf('  Slack buses: '); disp(slack_buses');
fprintf('  PV buses: '); disp(pv_buses');
fprintf('  PQ buses: '); disp(pq_buses');
fprintf('\n');

% -------------------------------------------------------------------------
%  3.2 กำหนดตัวแปรที่ไม่ทราบค่า (Unknown Variables)
%  -------------------------------------------------------------------------
n_delta = num_pv + num_pq;  % จำนวนมุมที่ไม่ทราบ (PV + PQ buses)
n_V = num_pq;               % จำนวน |V| ที่ไม่ทราบ (PQ buses เท่านั้น)
n_total = n_delta + n_V;    % จำนวนตัวแปรทั้งหมด

fprintf('Number of unknowns:\n');
fprintf('  Voltage angles (delta): %d\n', n_delta);
fprintf('  Voltage magnitudes (|V|): %d\n', n_V);
fprintf('  Total unknowns: %d\n\n', n_total);

% สร้าง index mapping สำหรับตัวแปรแต่ละตัว
delta_idx = [pv_buses; pq_buses];  % ดัชนีของ delta ที่ต้องแก้
V_idx = pq_buses;                   % ดัชนีของ |V| ที่ต้องแก้

% -------------------------------------------------------------------------
%  3.3 กำหนดค่าเริ่มต้น (Initial Guess) - Flat Start
%  -------------------------------------------------------------------------
x = zeros(n_total, 1);  % เวกเตอร์ state vector เริ่มต้น

for i = 1:length(delta_idx)
    x(i) = V_angle(delta_idx(i)) * pi / 180;  % แปลง degree เป็น radian
end

for i = 1:length(V_idx)
    x(n_delta + i) = V_mag(V_idx(i));  % ใช้ค่า |V| เริ่มต้น
end

%% =========================================================================
%  ส่วนที่ 4: Newton-Raphson Iteration
%  =========================================================================

fprintf('============================================================\n');
fprintf('  NEWTON-RAPHSON ITERATION\n');
fprintf('============================================================\n\n');

% -------------------------------------------------------------------------
%  4.1 กำหนดพารามิเตอร์การคำนวณ (Iteration Parameters)
%  -------------------------------------------------------------------------
max_iter = 20;        % จำนวนรอบสูงสุดที่อนุญาต
tolerance = 1e-6;     % ค่าความผิดพลาดที่ยอมรับได้ (pu)
iter = 0;             % ตัวนับรอบ
converged = false;    % flag บอกสถานะการลู่เข้า

% Array สำหรับเก็บค่า mismatch ระหว่าง iteration (ใช้สำหรับ plot)
mismatch_history = zeros(max_iter, 1);

% -------------------------------------------------------------------------
%  4.2 เริ่ม Iteration Loop
%  -------------------------------------------------------------------------
while iter < max_iter
    iter = iter + 1;

    % ---------------------------------------------------------------------
    %  4.2.1 แยกตัวแปรจาก state vector
    %  ---------------------------------------------------------------------
    delta = zeros(num_buses, 1);
    V = zeros(num_buses, 1);

    % Slack bus
    for i = 1:num_slack
        delta(slack_buses(i)) = V_angle(slack_buses(i)) * pi / 180;
        V(slack_buses(i)) = V_mag(slack_buses(i));
    end

    % PV bus
    for i = 1:num_pv
        idx = pv_buses(i);
        delta_idx_in_x = find(delta_idx == idx);
        delta(idx) = x(delta_idx_in_x);
        V(idx) = V_mag(idx);
    end

    % PQ bus
    for i = 1:num_pq
        idx = pq_buses(i);
        delta_idx_in_x = find(delta_idx == idx);
        V_idx_in_x = n_delta + find(V_idx == idx);
        delta(idx) = x(delta_idx_in_x);
        V(idx) = x(V_idx_in_x);
    end

    % ---------------------------------------------------------------------
    %  4.2.2 คำนวณ Power Injection
    %  ---------------------------------------------------------------------
    P_calc = zeros(num_buses, 1);
    Q_calc = zeros(num_buses, 1);

    for i = 1:num_buses
        sum_P = 0;
        sum_Q = 0;
        for j = 1:num_buses
            delta_ij = delta(i) - delta(j);
            sum_P = sum_P + V(j) * (Gbus(i,j) * cos(delta_ij) + Bbus(i,j) * sin(delta_ij));
            sum_Q = sum_Q + V(j) * (Gbus(i,j) * sin(delta_ij) - Bbus(i,j) * cos(delta_ij));
        end
        P_calc(i) = V(i) * sum_P;
        Q_calc(i) = V(i) * sum_Q;
    end

    % ---------------------------------------------------------------------
    %  4.2.3 คำนวณ Mismatch
    %  --------------------------------------------------------------------
    mismatch = zeros(n_total, 1);

    for i = 1:n_delta
        bus_i = delta_idx(i);
        mismatch(i) = P_net(bus_i) - P_calc(bus_i);
    end

    for i = 1:n_V
        bus_i = V_idx(i);
        mismatch(n_delta + i) = Q_net(bus_i) - Q_calc(bus_i);
    end

    % ---------------------------------------------------------------------
    %  4.2.4 ตรวจสอบการลู่เข้า (Convergence Check)
    %  --------------------------------------------------------------------
    max_mismatch = max(abs(mismatch));
    mismatch_history(iter) = max_mismatch;  % เก็บค่า mismatch สำหรับ plot
    fprintf('Iteration %2d: Max Mismatch = %.6e\n', iter, max_mismatch);

    if max_mismatch < tolerance
        converged = true;
        fprintf('\n*** CONVERGED in %d iterations ***\n\n', iter);
        break;
    end

    % ---------------------------------------------------------------------
    %  4.2.5 สร้าง Jacobian Matrix
    %  --------------------------------------------------------------------
    J = zeros(n_total, n_total);

    % Submatrix H = dP/d_delta
    for i = 1:n_delta
        bus_i = delta_idx(i);
        for j = 1:n_delta
            bus_j = delta_idx(j);
            delta_ij = delta(bus_i) - delta(bus_j);
            if i == j
                J(i, j) = -Q_calc(bus_i) - Bbus(bus_i, bus_i) * V(bus_i)^2;
            else
                J(i, j) = V(bus_i) * V(bus_j) * (Gbus(bus_i, bus_j) * sin(delta_ij) ...
                                                - Bbus(bus_i, bus_j) * cos(delta_ij));
            end
        end
    end

    % Submatrix N = dP/d|V|
    for i = 1:n_delta
        bus_i = delta_idx(i);
        for j = 1:n_V
            bus_j = V_idx(j);
            delta_ij = delta(bus_i) - delta(bus_j);
            if bus_i == bus_j
                J(i, n_delta + j) = P_calc(bus_i) / V(bus_i) + Gbus(bus_i, bus_i) * V(bus_i);
            else
                J(i, n_delta + j) = V(bus_i) * (Gbus(bus_i, bus_j) * cos(delta_ij) ...
                                               + Bbus(bus_i, bus_j) * sin(delta_ij));
            end
        end
    end

    % Submatrix M = dQ/d_delta
    for i = 1:n_V
        bus_i = V_idx(i);
        for j = 1:n_delta
            bus_j = delta_idx(j);
            delta_ij = delta(bus_i) - delta(bus_j);
            if V_idx(i) == delta_idx(j)
                J(n_delta + i, j) = P_calc(bus_i) - Gbus(bus_i, bus_i) * V(bus_i)^2;
            else
                J(n_delta + i, j) = -V(bus_i) * V(bus_j) * (Gbus(bus_i, bus_j) * cos(delta_ij) ...
                                                           + Bbus(bus_i, bus_j) * sin(delta_ij));
            end
        end
    end

    % Submatrix L = dQ/d|V|
    for i = 1:n_V
        bus_i = V_idx(i);
        for j = 1:n_V
            bus_j = V_idx(j);
            delta_ij = delta(bus_i) - delta(bus_j);
            if i == j
                J(n_delta + i, n_delta + j) = Q_calc(bus_i) / V(bus_i) - Bbus(bus_i, bus_i) * V(bus_i);
            else
                J(n_delta + i, n_delta + j) = V(bus_i) * (Gbus(bus_i, bus_j) * sin(delta_ij) ...
                                                         - Bbus(bus_i, bus_j) * cos(delta_ij));
            end
        end
    end

    % ---------------------------------------------------------------------
    %  4.2.6 แก้สมการเชิงเส้น J * delta_x = mismatch
    %  ---------------------------------------------------------------------
    delta_x = J \ mismatch;

    % ---------------------------------------------------------------------
    %  4.2.7 อัปเดตตัวแปร
    %  ---------------------------------------------------------------------
    x = x + delta_x;

    % ตรวจสอบว่า |V| ไม่ติดลบ
    for i = 1:n_V
        if x(n_delta + i) < 0
            x(n_delta + i) = 0.1;
            fprintf('  Warning: |V| at bus %d was negative, set to 0.1 pu\n', V_idx(i));
        end
    end
end

if ~converged
    fprintf('\n*** WARNING: Did not converge in %d iterations ***\n', max_iter);
end

%% =========================================================================
%  ส่วนที่ 5: คำนวณผลลัพธ์สุดท้าย (Final Calculations)
%  =========================================================================

V_final = zeros(num_buses, 1);
delta_final = zeros(num_buses, 1);

for i = 1:num_slack
    delta_final(slack_buses(i)) = V_angle(slack_buses(i)) * pi / 180;
    V_final(slack_buses(i)) = V_mag(slack_buses(i));
end

for i = 1:num_pv
    idx = pv_buses(i);
    delta_idx_in_x = find(delta_idx == idx);
    delta_final(idx) = x(delta_idx_in_x);
    V_final(idx) = V_mag(idx);
end

for i = 1:num_pq
    idx = pq_buses(i);
    delta_idx_in_x = find(delta_idx == idx);
    V_idx_in_x = n_delta + find(V_idx == idx);
    delta_final(idx) = x(delta_idx_in_x);
    V_final(idx) = x(V_idx_in_x);
end

% -------------------------------------------------------------------------
%  5.1 คำนวณ Power Injection สุดท้าย
%  -------------------------------------------------------------------------
P_final = zeros(num_buses, 1);
Q_final = zeros(num_buses, 1);

for i = 1:num_buses
    sum_P = 0;
    sum_Q = 0;
    for j = 1:num_buses
        delta_ij = delta_final(i) - delta_final(j);
        sum_P = sum_P + V_final(j) * (Gbus(i,j) * cos(delta_ij) + Bbus(i,j) * sin(delta_ij));
        sum_Q = sum_Q + V_final(j) * (Gbus(i,j) * sin(delta_ij) - Bbus(i,j) * cos(delta_ij));
    end
    P_final(i) = V_final(i) * sum_P;
    Q_final(i) = V_final(i) * sum_Q;
end

% Actual generator outputs are reconstructed from the solved injections.
P_gen_actual = zeros(num_buses, 1);
Q_gen_actual = zeros(num_buses, 1);
generator_buses = [slack_buses; pv_buses];

for i = 1:length(generator_buses)
    bus_i = generator_buses(i);
    P_gen_actual(bus_i) = P_final(bus_i) + P_load(bus_i);
    Q_gen_actual(bus_i) = Q_final(bus_i) + Q_load(bus_i);
end

% -------------------------------------------------------------------------
%  5.3 คำนวณ Line Flow
%  -------------------------------------------------------------------------
fprintf('============================================================\n');
fprintf('  LINE FLOW CALCULATIONS\n');
fprintf('============================================================\n\n');

line_flow_P = zeros(num_lines, 1);
line_flow_Q = zeros(num_lines, 1);
line_loss_P = zeros(num_lines, 1);
line_loss_Q = zeros(num_lines, 1);

for i = 1:num_lines
    from = line_data(i, 1);
    to = line_data(i, 2);
    R = line_data(i, 3);
    X = line_data(i, 4);
    B_half = line_data(i, 5);

    V_from = V_final(from) * exp(1j * delta_final(from));
    V_to = V_final(to) * exp(1j * delta_final(to));

    y_series = 1 / (R + 1j * X);

    I_from = y_series * (V_from - V_to) + 1j * B_half * V_from;
    I_to = y_series * (V_to - V_from) + 1j * B_half * V_to;

    S_from = V_from * conj(I_from);
    S_to = V_to * conj(I_to);

    line_flow_P(i) = real(S_from);
    line_flow_Q(i) = imag(S_from);
    line_loss_P(i) = real(S_from + S_to);
    line_loss_Q(i) = imag(S_from + S_to);
end

%% =========================================================================
%  ส่วนที่ 6: แสดงผลลัพธ์ (Report Output)
%  =========================================================================

fprintf('\n');
fprintf('================================================================\n');
fprintf('                     POWER FLOW RESULTS\n');
fprintf('================================================================\n\n');

% -------------------------------------------------------------------------
%  6.1 Bus Voltage Summary
%  -------------------------------------------------------------------------
fprintf('------------------------------------------------------------\n');
fprintf('                    BUS VOLTAGES\n');
fprintf('------------------------------------------------------------\n');
fprintf('%-6s %-8s %-10s %-10s %-10s %-10s\n', ...
    'Bus', 'Type', '|V| (pu)', '|V| (kV)', 'Angle (deg)', 'Angle (rad)');
fprintf('------------------------------------------------------------\n');

bus_type_str = {'Slack', 'PV', 'PQ'};

for i = 1:num_buses
    type_str = bus_type_str{bus_type(i)};
    V_kv = V_final(i) * V_base;
    angle_deg = delta_final(i) * 180 / pi;
    fprintf('%-6d %-8s %-10.4f %-10.2f %-10.4f %-10.4f\n', ...
        i, type_str, V_final(i), V_kv, angle_deg, delta_final(i));
end
fprintf('\n');

% -------------------------------------------------------------------------
%  6.2 Power Generation and Load
%  -------------------------------------------------------------------------
fprintf('------------------------------------------------------------\n');
fprintf('              POWER GENERATION AND LOAD\n');
fprintf('------------------------------------------------------------\n');
fprintf('%-6s %-12s %-12s %-12s %-12s\n', ...
    'Bus', 'P_gen (pu)', 'Q_gen (pu)', 'P_load (pu)', 'Q_load (pu)');
fprintf('------------------------------------------------------------\n');

for i = 1:num_buses
    fprintf('%-6d %-12.4f %-12.4f %-12.4f %-12.4f\n', ...
        i, P_gen_actual(i), Q_gen_actual(i), P_load(i), Q_load(i));
end
fprintf('\n');

% -------------------------------------------------------------------------
%  6.3 Power Balance Summary
%  -------------------------------------------------------------------------
fprintf('------------------------------------------------------------\n');
fprintf('                 POWER BALANCE SUMMARY\n');
fprintf('------------------------------------------------------------\n');

P_total_gen = sum(P_gen_actual);
Q_total_gen = sum(Q_gen_actual);
P_total_load = sum(P_load);
Q_total_load = sum(Q_load);
P_total_loss = sum(line_loss_P);
Q_total_loss = sum(line_loss_Q);

fprintf('Total Generation:\n');
fprintf('  P_gen = %.4f pu (%.2f MW)\n', P_total_gen, P_total_gen * S_base);
fprintf('  Q_gen = %.4f pu (%.2f MVAr)\n', Q_total_gen, Q_total_gen * S_base);
fprintf('\n');
fprintf('Total Load:\n');
fprintf('  P_load = %.4f pu (%.2f MW)\n', P_total_load, P_total_load * S_base);
fprintf('  Q_load = %.4f pu (%.2f MVAr)\n', Q_total_load, Q_total_load * S_base);
fprintf('\n');
fprintf('Total Losses:\n');
fprintf('  P_loss = %.4f pu (%.2f MW)\n', P_total_loss, P_total_loss * S_base);
fprintf('  Q_loss = %.4f pu (%.2f MVAr)\n', Q_total_loss, Q_total_loss * S_base);
fprintf('\n');
fprintf('Balance Check:\n');
fprintf('  P_gen - P_load - P_loss = %.6e pu\n', P_total_gen - P_total_load - P_total_loss);
fprintf('  Q_gen - Q_load - Q_loss = %.6e pu\n', Q_total_gen - Q_total_load - Q_total_loss);
fprintf('\n');

% -------------------------------------------------------------------------
%  6.4 Line Flow Report
%  -------------------------------------------------------------------------
fprintf('------------------------------------------------------------\n');
fprintf('                    LINE FLOW REPORT\n');
fprintf('------------------------------------------------------------\n');
fprintf('%-4s %-4s %-10s %-10s %-10s %-10s\n', ...
    'From', 'To', 'P_from (pu)', 'Q_from (pu)', 'P_loss (pu)', 'Q_loss (pu)');
fprintf('------------------------------------------------------------\n');

for i = 1:num_lines
    fprintf('%-4d %-4d %-10.4f %-10.4f %-10.6f %-10.6f\n', ...
        line_data(i,1), line_data(i,2), ...
        line_flow_P(i), line_flow_Q(i), ...
        line_loss_P(i), line_loss_Q(i));
end
fprintf('\n');

%% =========================================================================
%  ส่วนที่ 7: Visualization
%  =========================================================================

% Voltage Profile Plot
figure(1);
bar(1:num_buses, V_final);  % ลบ 'filled' สำหรับ MATLAB เวอร์ชันเก่า
xlabel('Bus Number');
ylabel('Voltage Magnitude (pu)');
title('Voltage Profile - IEEE 5-Bus System');
grid on;
ylim([0.9 1.1]);

% เพิ่มเส้น nominal voltage (ใช้ plot แทน yline สำหรับเวอร์ชันเก่า)
hold on;
plot([0.5, num_buses+0.5], [1.0, 1.0], '--r', 'LineWidth', 1.5);
text(num_buses-0.5, 1.01, 'Nominal (1.0 pu)', 'Color', 'r', 'FontSize', 8);
hold off;

for i = 1:num_buses
    text(i, V_final(i) + 0.01, sprintf('%.4f', V_final(i)), ...
        'HorizontalAlignment', 'center', 'FontSize', 8);
end

% Voltage Angle Plot
figure(2);
bar(1:num_buses, delta_final * 180/pi);  % ลบ 'filled' สำหรับ MATLAB เวอร์ชันเก่า
xlabel('Bus Number');
ylabel('Voltage Angle (degree)');
title('Voltage Angle Profile - IEEE 5-Bus System');
grid on;
for i = 1:num_buses
    text(i, delta_final(i) * 180/pi + 0.1, sprintf('%.2f', delta_final(i) * 180/pi), ...
        'HorizontalAlignment', 'center', 'FontSize', 8);
end

% -------------------------------------------------------------------------
%  7.3 Convergence Plot (แสดงการลู่เข้าของ Newton-Raphson)
%  -------------------------------------------------------------------------
figure(3);

% ตัด array ให้พอดีกับจำนวน iteration ที่ใช้จริง
mismatch_plot = mismatch_history(1:iter);
semilogy(1:iter, mismatch_plot, '-bo', 'LineWidth', 2, 'MarkerSize', 6, 'MarkerFaceColor', 'b');
grid on;
xlabel('Iteration');
ylabel('Max Mismatch (pu)');
title('Newton-Raphson Convergence - IEEE 5-Bus System');

% เพิ่มเส้น tolerance (ใช้ plot แทน yline สำหรับ MATLAB เวอร์ชันเก่า)
hold on;
plot([1, iter], [tolerance, tolerance], '--r', 'LineWidth', 1.5);
text(iter/2, tolerance*1.1, sprintf('Tolerance = %.0e', tolerance), ...
    'Color', 'r', 'FontSize', 9, 'FontWeight', 'bold');
hold off;

% แสดงจำนวน iteration บนกราฟ
text(1, mismatch_plot(1), sprintf('  Start: %.2e', mismatch_plot(1)), ...
    'VerticalAlignment', 'bottom', 'FontSize', 9);
text(iter, mismatch_plot(end), sprintf('  End: %.2e', mismatch_plot(end)), ...
    'VerticalAlignment', 'bottom', 'FontSize', 9);

fprintf('================================================================\n');
fprintf('                    END OF REPORT\n');
fprintf('================================================================\n');

%% =========================================================================
%  ส่วนที่ 8: ส่งออกผลลัพธ์ (Export Results)
%  =========================================================================

results.bus_voltage = V_final;
results.bus_angle = delta_final;
results.bus_angle_deg = delta_final * 180 / pi;
results.bus_type = bus_type;
results.P_generation = P_gen_actual;
results.Q_generation = Q_gen_actual;
results.P_generation_specified = P_gen;
results.Q_generation_specified = Q_gen;
results.P_injection = P_final;
results.Q_injection = Q_final;
results.P_load = P_load;
results.Q_load = Q_load;
results.line_flow_P = line_flow_P;
results.line_flow_Q = line_flow_Q;
results.line_loss_P = line_loss_P;
results.line_loss_Q = line_loss_Q;
results.P_loss_total = P_total_loss;
results.Q_loss_total = Q_total_loss;
results.base_values = struct('S_base_MVA', S_base, 'V_base_kV', V_base, 'frequency_Hz', f_base);
results.mismatch_history = mismatch_history(1:iter);
results.iterations = iter;
results.converged = converged;
results.Ybus = Ybus;

fprintf('\nResults saved to variable ''results'' in workspace.\n');
fprintf('To save as .mat file: save(''powerflow_results.mat'', ''results'')\n');
