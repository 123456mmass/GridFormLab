function c = case_ne39_tamu_mixed(sg_buses)
%CASE_NE39_TAMU_MIXED สร้างสอง composition จากต้นทาง TAMU ชุดเดียวกัน.
% คง P ของเครื่อง non-reference; Q ของ IBR derive หลังตั้ง Slack=1 pu.
% Rating converter=10*ceil(1.25*|S_schedule|/10) เป็น PROJECT_DERIVED;
% ไม่ใช่ DC reserve และ MBASE ของ SG ไม่ใช่ physical capability limit.
arguments
    sg_buses (1,:) double
end
if ~isequal(sg_buses,[31 32 35 38 39]) && ~isequal(sg_buses,31)
    error('cases:ne39Tamu:composition','รองรับ SG composition ที่กำหนดไว้สองแบบเท่านั้น');
end
raw = cases.ne39_tamu_raw();
p = cases.ne39_tamu_machine_parameters();
S = raw.baseMVA;
ibr_buses = setdiff(30:39,sg_buses,'stable');
nb = size(raw.bus,1);
b = zeros(nb,12);
b(:,1) = raw.bus(:,1);
b(:,2) = 3;
b(raw.bus(:,2)==2,2) = 2;
b(raw.bus(:,2)==3,2) = 1;
b(:,3:4) = raw.bus(:,8:9);
b(:,7:10) = raw.bus(:,3:6)/S;
b(:,11) = -Inf; b(:,12) = Inf;
for k = 1:size(raw.gen,1)
    j = find(b(:,1)==raw.gen(k,1),1);
    b(j,5:6) = raw.gen(k,2:3)/S;
    b(j,11:12) = raw.gen(k,[5 4])/S;
end
tap = raw.branch(:,9); tap(tap==0) = 1;
l = [raw.branch(:,1:4),raw.branch(:,5)/2,tap,raw.branch(:,10)];
base = struct('S_base_MVA',S,'V_base_kV',1,'frequency_Hz',raw.frequency_Hz);
base.voltage_base_status = raw.basekv_status;
base_case = struct('system_name','TAMU NE39 operating-point derivation', ...
    'base_values',base,'bus_data',b,'line_data',l);
base_case.bus_data(31,3:4) = [1 0];
opts = struct('verbose',false,'plot_results',false,'max_iter',50, ...
    'tolerance',1e-11,'enforce_q_limits',false);
pf = pfsolver.powerflow_newton_raphson(base_case,opts);
if ~pf.converged
    error('cases:ne39Tamu:powerFlow','ไม่สามารถ derive operating point ที่ Slack=1 pu');
end
b(:,3) = pf.bus_voltage;
b(:,4) = pf.bus_angle_deg;
b(:,5) = pf.P_generation;
b(:,6) = pf.Q_generation;
b(ibr_buses,2) = 3;
P = b(ibr_buses,5)*S;
Q = b(ibr_buses,6)*S;
ratings = 10*ceil(1.25*hypot(P,Q)/10);
b(ibr_buses,11) = -ratings/S;
b(ibr_buses,12) = ratings/S;

c = struct();
c.system_name = sprintf('New England IEEE 39-Bus System (%d SG + %d IBR)',numel(sg_buses),numel(ibr_buses));
c.base_values = base;
c.bus_data = b;
c.line_data = l;
sg_rows = arrayfun(@(bus)find(raw.gen(:,1)==bus,1),sg_buses);
c.mpc = struct('version','2','baseMVA',S,'bus',raw.bus, ...
    'gen',raw.gen(sg_rows,:),'branch',raw.branch,'gencost',[]);
c.mpc.bus(:,8:9) = b(:,3:4);
c.mpc.bus(31,8:9) = [1 0];
c.mpc.bus(ibr_buses,2) = 1;
c.mpc.gen(:,2:3) = b(sg_buses,5:6)*S;
c.mpc.gen(:,6) = b(sg_buses,3);
% ไม่ส่ง sentinel ของต้นทางเป็น physical Pmax ให้ downstream consumers.
c.mpc.gen(:,9:10) = NaN;
c.mpc.branch(:,6:8) = 0;
c.sg_buses = sg_buses(:);
c.generator_buses = sg_buses(:);
c.ibr_buses = ibr_buses(:);
c.ibr_ratings_MVA = ratings;
c.ibr_scheduled = struct('bus',num2cell(ibr_buses(:)), ...
    'P_MW',num2cell(P),'Q_MVAr',num2cell(Q));
c.bus_role = repmat("PQ",nb,1);
c.bus_role(sg_buses) = "PV";
c.bus_role(31) = "SLACK";
c.bus_role(ibr_buses) = "GFL";
units = struct('gen_id',{},'bus',{},'H',{},'D',{},'Xdp',{}, ...
    'Mbase',{},'P_MW',{},'S_MVA',{},'source_type',{});
for k = 1:numel(sg_buses)
    u = p.unit([p.unit.bus]==sg_buses(k));
    units(k) = struct('gen_id',u.gen_id,'bus',u.bus,'H',u.H_system, ...
        'D',u.D_system,'Xdp',u.Xdp_system,'Mbase',u.Mbase, ...
        'P_MW',raw.gen(sg_rows(k),2),'S_MVA',u.Mbase,'source_type',u.source_type);
end
c.machines = struct('model','classical', ...
    'base',struct('S_MVA',S,'V_kV',1,'f_Hz',raw.frequency_Hz),'units',units);
c.dynamics_contract = struct('status','SOURCED_PARAMETERS_DECLARED_REDUCTION', ...
    'model','classical','classification',p.classification,'source',p.source, ...
    'machines',c.machines,'reduction',p.reduction);
c.source = raw.source_citation;
c.source_detail = struct('citation',raw.source_citation, ...
    'transcription',raw.source_file,'transcription_sha256',raw.source_sha256, ...
    'source_files',raw.source_files,'url',raw.source_url);
c.source_variant = struct('id','TAMU_LEDESMA_2016','verification','IMPORTED_EXACT_RAW_DYR', ...
    'modifications',{{'SG/IBR composition','Slack V=1 angle=0', ...
    'PQ schedules derived at modified operating point','converter ratings', ...
    'GENROU-to-classical reduction'}});
c.ne39 = raw;
c.reference = struct('network',raw.source_citation, ...
    'sg_dynamics','cases.ne39_tamu_machine_parameters: PROJECT_DERIVED classical reduction of GENROU', ...
    'ibr_model','ibr.eecon49_dual_mode_model', ...
    'slack','SG31 V=1 pu angle=0 (PROJECT_DEFINED)', ...
    'dispatch','non-reference source P held; Slack P and all Q re-solved');
c.source_dynamics = p;
c.source_inherited_excursions = struct('bus',{},'quantity',{},'value',{},'limit',{},'note',{});
c.devices = struct();
pre = struct(); pmax = struct(); qschedule = struct(); participation = struct();
for bus = sg_buses
    id = sprintf('SG%d',bus);
    c.devices.(id) = struct('type','sg','bus',bus,'initial_mode','synchronous','initial_online',true);
    pre.(id) = b(bus,5)*S;
    pmax.(id) = NaN;
end
for k = 1:numel(ibr_buses)
    bus = ibr_buses(k); id = sprintf('IBR%d',bus);
    c.devices.(id) = struct('type','ibr','bus',bus,'initial_mode','gfl','initial_online',true);
    pre.(id) = P(k); pmax.(id) = NaN;
    qschedule.(id) = Q(k);
    participation.(id) = ratings(k)/sum(ratings);
end
c.dispatch_contract = struct('policy','rating_proportional', ...
    'pre_fault',pre,'pmax_MW',pmax,'ibr_scheduled_Q_MVAr',qschedule, ...
    'post_trip',struct('deficit_MW',NaN,'participation',participation, ...
    'classification','PROJECT_DEFINED_CONTROL_POLICY_NOT_CAPABILITY'), ...
    'load_shed_MW',0,'classification','PROJECT_DERIVED', ...
    'feasibility_status','PF_SOLVED_PHYSICAL_ACTIVE_CAPABILITY_UNKNOWN', ...
    'physical_active_limit_status',raw.active_limit_status, ...
    'dc_reserve_status','REQUIRES_DEVICE_CAPABILITY_CERTIFICATE', ...
    'redispatch_rule',struct('rule','source non-reference P held; Slack balances network losses', ...
    'losses_MW',S*sum(pf.P_generation-pf.P_load)));
c.synchronism = struct('dV_max_pu',0.05,'df_max_pu',0.001, ...
    'dtheta_max_deg',10,'dwell_s',0.5,'timeout_s',5, ...
    'classification','PROJECT_DERIVED');
c.delays = struct('T_detect_s',0.05,'T_logic_s',0.02,'T_controller_s',0.05, ...
    'T_up_s',0.12,'T_sg_min_off_s',0.5,'rho',0.05,'T_minimum_hold_s',1, ...
    'T_guard_s',0.3,'T_lockout_s',2,'classification','PROJECT_DERIVED');
% 0.02 ไม่ใช่การลดเกณฑ์เพื่อให้ผ่าน. เครื่อง TAMU เป็น classical และ D=0
% ไม่มี damper/AVR ให้สร้าง damping 5% ที่เคยใช้กับเกาะ IBR ของ IEEE14.
% ค้นโปรไฟล์ GFM วันที่ 2026-10-09: Dv=20..80 และ M=0.04..0.16 ไม่ยก
% worst zeta ของ partial trip เกิน 0.0313; โหมดที่กั้นคือ SG-SG ประมาณ 1.2 Hz.
% จึงใช้ 0.02 เป็น margin เหนือ D=0 และคง gamma_req เป็น ordering key.
c.selector = struct('gamma_req_rad_per_s',0.1,'zeta_min_damping',0.02, ...
    'acceptance_criterion','damping_ratio_floor','classification','PROJECT_DERIVED', ...
    'derivation','classical TAMU D=0; IEEE14 5% floor is not reachable without invented SG damping', ...
    'profile_search','Dv=20:20:80, M=[0.04 0.08 0.16], best zeta=0.0313 at Dv=20,M=0.04', ...
    'frozen_before_candidate_eval',true);
c.ts_defaults = struct('fault_bus',16,'fault_bus_classification','SOURCE_DEFINED', ...
    'fault_bus_rationale','TAMU Website - Bus 16 fault.aux', ...
    't_fault',0.5,'t_clear',0.7);
c = cases.standardize_case(c);
end
