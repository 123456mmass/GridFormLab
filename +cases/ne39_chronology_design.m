function c=ne39_chronology_design(c,opt)
%NE39_CHRONOLOGY_DESIGN ออกแบบ plant สำหรับ trip พร้อมโหลดเพิ่ม ไม่เปลี่ยน source.
% ค่าเป้าหมายทั้งหมดเป็น PROJECT_DERIVED ไม่ใช่พิกัด hardware ของ TAMU.
arguments
    c (1,1) struct
    opt (1,1) struct = struct()
end
if ~isfield(c,'source_variant') || ~strcmp(c.source_variant.id,'TAMU_LEDESMA_2016') || ...
        ~isequal(c.sg_buses(:),31)
    error('cases:ne39ChronologyDesign:composition','design นี้ใช้เฉพาะ TAMU 1SG+9IBR');
end
if isfield(c,'study_capability')
    error('cases:ne39ChronologyDesign:alreadyDesigned','ต้องออกแบบจาก case ที่ยังไม่มี study capability');
end
allowed={'voltage_setpoints_pu','loss_allowance_fraction','active_margin_fraction', ...
    'reactive_margin_fraction','rocof_target_Hz_s','frequency_error_target_Hz', ...
    'voltage_droop_pu','voltage_response_s','dc_energy_hold_s'};
for name=fieldnames(opt)'
    if ~ismember(name{1},allowed)
        error('cases:ne39ChronologyDesign:option','ไม่รู้จัก design option %s',name{1});
    end
end
loss=getv(opt,'loss_allowance_fraction',.05);
margin=getv(opt,'active_margin_fraction',.10);
qmargin=getv(opt,'reactive_margin_fraction',.20);
rocof=getv(opt,'rocof_target_Hz_s',1);
df=getv(opt,'frequency_error_target_Hz',.4);
qdrop=getv(opt,'voltage_droop_pu',.025);
tv=getv(opt,'voltage_response_s',.05);
thold=getv(opt,'dc_energy_hold_s',.02);
for target={loss,margin,qmargin,rocof,df,qdrop,tv,thold}
    validateattributes(target{1},{'double'},{'scalar','real','finite','positive'});
end
if loss>.2 || margin>.5 || qmargin>1 || df>=.5 || qdrop>.1
    error('cases:ne39ChronologyDesign:targets','design targets ต้องอยู่ใน envelope ที่ประกาศ');
end
S=c.base_values.S_base_MVA; f=c.base_values.frequency_Hz;
if S~=100 || f~=60
    error('cases:ne39ChronologyDesign:base','ต้องใช้ฐาน 100 MVA / 60 Hz');
end
rb=[c.sg_buses;c.ibr_buses];
v=getv(opt,'voltage_setpoints_pu',1.04*ones(numel(rb),1));
validateattributes(v,{'double'},{'real','finite','vector','numel',numel(rb)});
if any(v<.9 | v>1.1)
    error('cases:ne39ChronologyDesign:voltage','setpoints ต้องอยู่ใน physical voltage gate เดิม');
end
% PV PF ใช้ derive Q ของ operating point ใหม่ ก่อนแปลง IBR กลับเป็น PQ.
p=c; p.bus_data(rb,2)=2; p.bus_data(31,2)=1;
p.bus_data(rb,3)=v(:);
pfopt=struct('verbose',false,'plot_results',false,'max_iter',60, ...
    'tolerance',1e-11,'enforce_q_limits',false);
pf=pfsolver.powerflow_newton_raphson(p,pfopt);
if ~pf.converged
    error('cases:ne39ChronologyDesign:powerFlow','operating-point PF ไม่ converged');
end
c.bus_data(:,3:6)=[pf.bus_voltage pf.bus_angle_deg pf.P_generation pf.Q_generation];
c.mpc.bus(:,8:9)=c.bus_data(:,3:4);
c.mpc.gen(:,2:3)=c.bus_data(c.sg_buses,5:6)*S;
c.mpc.gen(:,6)=c.bus_data(c.sg_buses,3);
P0=c.bus_data(c.ibr_buses,5)*S; Q0=c.bus_data(c.ibr_buses,6)*S;
Psg=c.bus_data(31,5)*S;
if Psg<=0 || any(P0<=0)
    error('cases:ne39ChronologyDesign:dispatch','design นี้ต้องใช้ exporting pre-event dispatch');
end
% CZ demand ที่ขอบ V=1.1: ใช้ Vpf ของ case นี้ ไม่ใช่โหลด MW คงที่.
Vpf=c.bus_data(:,3); Vmin=.9; Vmax=1.1; load_factor=1.2;
Pload_max=sum(c.mpc.bus(:,3).*(Vmax./Vpf).^2)*load_factor;
Ptotal=Pload_max*(1+loss)*(1+margin);
weights=P0/sum(P0);
Pmax=10*ceil(Ptotal*weights/10);
% คัดกรอง Q ของ base/loaded/line-open PV PF เพื่อ sizing ไม่ใช่ transition proof.
Qenv=abs(Q0);
for line_open=[false true]
    qcase=p;
    % sizing contingency: SG31 offline; ใช้ IBR30 เป็น reference ของ PV PF.
    qcase.bus_data(31,[2 5 6])=[3 0 0];
    qcase.bus_data(c.ibr_buses(1),2)=1;
    qcase.bus_data(:,7:8)=load_factor*p.bus_data(:,7:8).*(Vmax./Vpf).^2;
    qcase.bus_data(c.ibr_buses,5)=Pload_max*(1+loss)*weights/S;
    if line_open
        hit=all(qcase.line_data(:,1:2)==[16 17],2) | all(qcase.line_data(:,1:2)==[17 16],2);
        if nnz(hit)~=1
            error('cases:ne39ChronologyDesign:line','ต้องพบ line 16-17 เพียงหนึ่งวงจร');
        end
        qcase.line_data(hit,:)=[];
    end
    qpf=pfsolver.powerflow_newton_raphson(qcase,pfopt);
    if ~qpf.converged
        error('cases:ne39ChronologyDesign:reactiveScreen','loaded PV sizing PF ไม่ converged');
    end
    Qenv=max(Qenv,abs(qpf.Q_generation(c.ibr_buses)*S));
end
Qmax=10*ceil((1+qmargin)*Qenv/10);
% design I=1.0 pu ที่ V=.9 ทิ้ง transient current margin ถึง gate เดิม 1.2 pu.
Idesign=1; Mbase=10*ceil(hypot(Pmax,Qmax)/(Vmin*Idesign)/10);
Lf=.15; Rf=.015; wb=2*pi*f;
% M d(omega)/dt=DeltaP: M=f*DeltaP/RoCoF; Dv=DeltaP/(Deltaf/f).
imbalance=max(Psg,.2*Pload_max)/sum(Mbase);
M=f*imbalance/rocof; Dv=f*imbalance/df;
% คง inner PI ต้นทาง; วาง voltage-PI zero ต่ำกว่า slow current root อย่างน้อย 5 เท่า.
inner_roots=roots([Lf/wb,.3,4]);
voltage_bandwidth=min(1/tv,min(abs(real(inner_roots)))/5);
% kiV/kpV เป็น PI-zero frequency ไม่ใช่ closed-loop bandwidth ของทั้ง network.
% อัตราส่วนนี้เป็น design heuristic; ต้องตรวจ spectrum/response จริงก่อนใช้ production.
kpV=1.2; kiV=kpV*voltage_bandwidth;
kE=8; kQ=kE*qdrop; tauE=kE*tv;
records=struct([]); dynamics=struct();
for k=1:numel(c.ibr_buses)
    bus=c.ibr_buses(k); id=sprintf('IBR%d',bus); rating=Mbase(k);
    Ineed=hypot(Pmax(k),Qmax(k))/(rating*Vmin);
    Pacmax=Pmax(k)/rating+Rf*Ineed^2;
    % capacitor energy: .5*C*(1^2-.9^2)>=Pacmax*t_hold.
    Cdc=2*Pacmax*thold/(1-.9^2);
    seed=struct('eps_dc',.1,'Pr',1,'Pmax',Pacmax,'source_state',true, ...
        'Vdc_max',1.1,'delta_ch',.02,'zeta_target',1/sqrt(2));
    dc=ibr.dc_source_thevenin_params(seed,1,Cdc,Rf,S/rating, ...
        P0(k)/S,Q0(k)/S,Vpf(bus));
    disc=dc.Edc^2-4*dc.Rdc*Pacmax;
    if disc<=0
        error('cases:ne39ChronologyDesign:dcFold','%s ไม่มี DC high branch',id);
    end
    Vdc=(dc.Edc+sqrt(disc))/2; Idc=Pacmax/Vdc;
    if Ineed>1.2 || Vdc<.9 || Vdc>1.1 || Pacmax/Vdc^2>=1/dc.Rdc || ...
            dc.tau_s>=Cdc*Vdc^2/Pacmax
        error('cases:ne39ChronologyDesign:plantEnvelope','%s ไม่ผ่าน plant sizing',id);
    end
    row=struct('resource_id',id,'P0_MW',P0(k),'Pmax_MW',Pmax(k), ...
        'active_reserve_MW',Pmax(k)-P0(k),'Qmax_MVAr',Qmax(k), ...
        'converter_rating_MVA',rating,'Vac_envelope_min_pu',Vmin, ...
        'converter_Pmax_pu',Pacmax,'Edc_pu',dc.Edc,'Rdc_pu',dc.Rdc, ...
        'Vdc_at_design_power_pu',Vdc,'Idc_continuous_design_pu',1.05*Idc, ...
        'dc_source_power_design_MW',dc.Edc*1.05*Idc*rating, ...
        'Cdc_pu_s',Cdc,'tau_s_s',dc.tau_s,'I_at_design_power_pu',Ineed);
    records=[records;row]; %#ok<AGROW>
    shared=struct('Lf',Lf,'Rf',Rf,'Cdc',Cdc,'Vdc_ref',1,'Imax',1.2);
    gfl=shared; gfl.kpPLL=1.2; gfl.kiPLL=5; gfl.kpP=.8; gfl.kiP=2.5;
    gfl.kpQ=.8; gfl.kiQ=2.5; gfl.kpI=.3; gfl.kiI=4;
    gfm=shared; gfm.M=M; gfm.Dv=Dv; gfm.tauE=tauE; gfm.kQ=kQ;
    gfm.kE=kE; gfm.kpV=kpV; gfm.kiV=kiV; gfm.kpI=.3; gfm.kiI=4;
    seed.Edc=dc.Edc; seed.Rdc=dc.Rdc; seed.tau_s=dc.tau_s;
    seed.Idc_max=row.Idc_continuous_design_pu;
    seed.Psource_max=row.dc_source_power_design_MW/rating;
    dynamics.(id)=struct('gfl_eecon49',gfl,'gfm_eecon49',gfm,'dc_source',seed);
    c.ibr_scheduled(k).P_MW=P0(k); c.ibr_scheduled(k).Q_MVAr=Q0(k);
    c.dispatch_contract.pre_fault.(id)=P0(k);
    c.dispatch_contract.pmax_MW.(id)=Pmax(k);
    c.dispatch_contract.ibr_scheduled_Q_MVAr.(id)=Q0(k);
    c.dispatch_contract.post_trip.post_trip_Pg_MW.(id)=P0(k)+Psg*weights(k);
end
c.ibr_ratings_MVA=Mbase;
c.bus_data(c.ibr_buses,11:12)=[-Qmax Qmax]/S;
c.dispatch_contract.pre_fault.SG31=Psg;
c.dispatch_contract.pmax_MW.SG31=10*ceil(1.1*Psg/10);
c.mpc.gen(:,9)=c.dispatch_contract.pmax_MW.SG31; c.mpc.gen(:,10)=0;
c.dispatch_contract.post_trip.deficit_MW=Psg;
c.dispatch_contract.post_trip.sg_ids={'SG31'};
c.dispatch_contract.post_trip.remaining_sg_ids={};
c.dispatch_contract.post_trip.post_trip_Qg_MVAr=c.dispatch_contract.ibr_scheduled_Q_MVAr;
c.dispatch_contract.post_trip.policy='PRE_DISPATCH_SHARE_WITH_REFERENCE_GFM_FULL_KCL';
c.dispatch_contract.post_trip.classification='SINGLE_SG_CONTINGENCY';
c.dispatch_contract.post_trip.loss_balance='REFERENCE_GFM_FULL_KCL';
c.dispatch_contract.physical_active_limit_status='PROJECT_DERIVED_STUDY_DESIGN_NOT_SOURCE_HARDWARE';
c.dispatch_contract.feasibility_status='DESIGN_REQUIRES_ENDPOINT_AND_TRAJECTORY_SCREEN';
c.study_capability=struct('classification','PROJECT_DERIVED', ...
    'source_hardware_verified',false,'records',records,'transition_certified',false, ...
    'scope','simultaneous trip/load envelope; no runtime certificate');
c.chronology_design=struct('id','NE39_1SG9IBR_CHRONOLOGY_DESIGN_V1', ...
    'classification','PROJECT_DERIVED','source_archive_modified',false, ...
    'targets',struct('Vmin_pu',Vmin,'Vmax_pu',Vmax,'load_factor',load_factor, ...
    'loss_allowance_fraction',loss,'active_margin_fraction',margin, ...
    'reactive_margin_fraction',qmargin,'rocof_target_Hz_s',rocof, ...
    'frequency_error_target_Hz',df,'voltage_droop_pu',qdrop, ...
    'voltage_response_s',tv,'dc_energy_hold_s',thold,'I_design_pu',Idesign), ...
    'Pload_envelope_max_MW',Pload_max,'Pcapacity_required_MW',Ptotal, ...
    'imbalance_converter_pu',imbalance,'M_s',M,'H_s',M/2,'Dv',Dv, ...
    'inner_current_roots_per_s',inner_roots,'voltage_bandwidth_per_s',voltage_bandwidth, ...
    'dynamic_params',dynamics,'voltage_setpoints_pu',v(:), ...
    'derivation',struct('active','sum(1.2*Pd*(1.1/Vpf)^2)*(1+loss)*(1+margin)', ...
    'rating','ceil_10MVA(hypot(Pmax,Qmax)/(.9*1.0))', ...
    'inertia','M=fbase*max(Psg,.2*Pload_max)/sum(Mbase)/RoCoF; H=M/2', ...
    'droop','Dv=fbase*DeltaP_converter/Deltaf_target', ...
    'voltage','kQ/kE=qdrop; tauE/kE=tV; kiV/kpV=min(1/tV,slow_current_root/5)', ...
    'dc','C=2*Pacmax*t_hold/(1-.9^2); R=.1; Edc=1+R*Pac0; tau_s=maxflat helper'), ...
    'endpoint_certified',false,'sg_mechanical_policy','SOURCE_CLASSICAL_UNCHANGED_NOT_RECLOSE_READY');
c.source_variant.modifications{end+1}='PROJECT_DERIVED chronology plant/voltage design V1';
c=cases.standardize_case(c);
end

function v=getv(s,n,d)
if isfield(s,n), v=s.(n); else, v=d; end
end
