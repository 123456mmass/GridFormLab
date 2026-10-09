function c = ne39_study_capability(c)
%NE39_STUDY_CAPABILITY ออกแบบ active capability สำหรับการศึกษา ไม่ใช่ source rating.
% เปิดใช้เฉพาะเมื่อผู้เรียกเลือก study_capability=true; source case ไม่เปลี่ยน.
% Pmax=ปัดขึ้นทีละ10 MW จาก1.25*P0 เป็นสมมติฐานกำลังต้นทางที่จัดหาเพิ่ม25%.
% ค่า DC design ใช้ operating envelope |Vac|>=.9 pu ไม่ใช่ protection setting.
if ~isfield(c,'source_variant') || ~strcmp(c.source_variant.id,'TAMU_LEDESMA_2016')
    error('cases:ne39StudyCapability:source','ต้องใช้ mixed case จากต้นทางที่กำหนด');
end
ids = fieldnames(c.dispatch_contract.pre_fault);
records = struct([]);
for k = 1:numel(ids)
    id = ids{k}; P0 = c.dispatch_contract.pre_fault.(id);
    Pmax = 10*ceil(1.25*P0/10);
    c.dispatch_contract.pmax_MW.(id) = Pmax;
    row = struct('resource_id',id,'P0_MW',P0,'Pmax_MW',Pmax, ...
        'active_reserve_MW',Pmax-P0,'converter_rating_MVA',NaN, ...
        'Vac_envelope_min_pu',NaN,'converter_Pmax_pu',NaN, ...
        'Edc_pu',NaN,'Rdc_pu',NaN,'Vdc_at_design_power_pu',NaN, ...
        'Idc_continuous_design_pu',NaN,'dc_source_power_design_MW',NaN);
    if startsWith(id,'IBR')
        bus = c.devices.(id).bus;
        j = find(c.ibr_buses==bus,1);
        M = c.ibr_ratings_MVA(j); Q0 = c.ibr_scheduled(j).Q_MVAr;
        V0 = c.bus_data(bus,3); Vmin = .9; Rf = .015;
        p0 = P0/M; q0 = Q0/M;
        Pac0 = p0+Rf*(p0^2+q0^2)/V0^2;
        % ทั้ง Pmax และ Q0 ต้องอยู่ใน current circle ที่ขอบ operating envelope.
        Ineed = hypot(Pmax,Q0)/(M*Vmin);
        if Ineed>1.2
            error('cases:ne39StudyCapability:acCurrent','%s เกิน current envelope',id);
        end
        Pacmax = Pmax/M+Rf*Ineed^2;
        Rdc = .1; Edc = 1+Rdc*Pac0;
        disc = Edc^2-4*Rdc*Pacmax;
        if disc<=0
            error('cases:ne39StudyCapability:dcFold','%s ไม่มี high-voltage DC equilibrium',id);
        end
        Vdc = (Edc+sqrt(disc))/2;
        Idc = Pacmax/Vdc;
        % เกณฑ์ determinant/trace ของ source-current/DC-link block ที่ design point.
        Cdc = .1; tau = .005;
        if Pacmax/Vdc^2>=1/Rdc || tau>=Cdc*Vdc^2/Pacmax
            error('cases:ne39StudyCapability:dcLocal','%s ไม่ผ่าน local DC stability',id);
        end
        row.converter_rating_MVA = M;
        row.Vac_envelope_min_pu = Vmin;
        row.converter_Pmax_pu = Pacmax;
        row.Edc_pu = Edc; row.Rdc_pu = Rdc;
        row.Vdc_at_design_power_pu = Vdc;
        row.Idc_continuous_design_pu = 1.05*Idc;
        row.dc_source_power_design_MW = Edc*row.Idc_continuous_design_pu*M;
    end
    records = [records;row]; %#ok<AGROW>
end
for k = 1:numel(c.sg_buses)
    id = sprintf('SG%d',c.sg_buses(k));
    c.mpc.gen(k,9) = c.dispatch_contract.pmax_MW.(id);
    c.mpc.gen(k,10) = 0;
end
c.study_capability = struct('classification','PROJECT_DERIVED_DESIGN_ASSUMPTION', ...
    'source_hardware_verified',false,'reserve_fraction',.25, ...
    'active_sizing_rule','10*ceil(1.25*P0_MW/10)', ...
    'dc_sizing_rule','Idc_design=1.05*Pacmax/Vdc_high; Psource=Edc*Idc_design*Mbase', ...
    'records',records,'transition_certified',false, ...
    'scope','steady active design; not SG capability curve, fault or transition certificate');
% กรณี SG เดียว: dispatch หลังสูญเสีย SG31 แจกตาม active headroom จริง.
% network losses หลัง trip ให้ reference GFM balance ใน full-KCL equilibrium.
% กรณีหลาย SG: catalog กำหนดเหตุการณ์ SG trip ตาม sg_id (SG31) เป็น partial
% contingency — SG ที่เหลือ online คง non-reference schedule ไม่สร้าง
% all-SG-off certificate แทน; deficit จัดสรรบน IBR headroom เช่นเดียวกัน.
lost_id = 'SG31';
% sg_buses เป็น column vector จาก case builder; ต้องระบุ UniformOutput=false
% เพื่อให้ได้ cellstr ไม่ใช่ char matrix ที่ต่อทุกชื่อติดกัน.
sg_names = arrayfun(@(b)sprintf('SG%d',b),c.sg_buses(:).','UniformOutput',false);
if numel(c.sg_buses)==1
    lost_id = sprintf('SG%d',c.sg_buses(1));
end
if any(strcmp(sg_names,lost_id))
    deficit = c.dispatch_contract.pre_fault.(lost_id);
    ii = find(startsWith({records.resource_id},'IBR'));
    headroom = [records(ii).active_reserve_MW];
    if deficit>sum(headroom) || deficit<0
        error('cases:ne39StudyCapability:tripReserve','Active headroom ไม่พอทดแทน SG');
    end
    dispatch = struct();
    for j=1:numel(ii)
        row = records(ii(j));
        dispatch.(row.resource_id) = row.P0_MW+deficit*headroom(j)/sum(headroom);
    end
    % remaining_sg_ids เป็น cell ว่างได้เมื่อ composition มี SG เดียว
    % partition ต้องครบทุก SG และไม่มีตัวซ้ำระหว่าง tripped กับ remaining
    others = sg_names(~strcmp(sg_names,lost_id));
    c.dispatch_contract.post_trip.deficit_MW = deficit;
    c.dispatch_contract.post_trip.sg_ids = {lost_id};
    c.dispatch_contract.post_trip.remaining_sg_ids = others;
    c.dispatch_contract.post_trip.post_trip_Pg_MW = dispatch;
    c.dispatch_contract.post_trip.post_trip_Qg_MVAr = c.dispatch_contract.ibr_scheduled_Q_MVAr;
    c.dispatch_contract.post_trip.policy = 'FIXED_ACTIVE_HEADROOM_PROPORTIONAL';
    c.dispatch_contract.post_trip.loss_balance = 'REFERENCE_GFM_FULL_KCL';
    if isempty(others)
        c.dispatch_contract.post_trip.classification = 'SINGLE_SG_CONTINGENCY';
    else
        % partial-SG contingency: SG ที่เหลือ online คง Pm/Emag เดิม
        % deficit แจกครั้งเดียวบน IBR headroom ไม่แจกซ้ำบน SG
        % (PROJECT_DERIVED study contract; reserve arithmetic ตรวจ 2026-10-09)
        c.dispatch_contract.post_trip.classification = ['PARTIAL_SG_CONTINGENCY_' ...
            num2str(numel(others)) '_SG_REMAIN'];
    end
    c.dispatch_contract.post_trip.provenance = ...
        'cases.ne39_study_capability: trip contract per catalog sg_id';
end
c.dispatch_contract.physical_active_limit_status = 'PROJECT_DERIVED_STUDY_DESIGN_NOT_SOURCE_HARDWARE';
c.dispatch_contract.feasibility_status = 'STUDY_ACTIVE_DESIGN_REQUIRES_RUNTIME_CONSTRAINT_CHECKS';
end
