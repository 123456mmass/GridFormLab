function scenario = scenario_ne39_tamu_mixed(case_data, scenario_opt)
%SCENARIO_NE39_TAMU_MIXED resource table ร่วมสำหรับ TAMU ทั้งสอง composition.
arguments
    case_data struct
    scenario_opt struct = struct()
end
if isfield(scenario_opt,'study_capability')
    flag = scenario_opt.study_capability;
    validateattributes(flag,{'logical','double'},{'scalar','finite'});
    if ~ismember(flag,[0 1])
        error('cases:ne39StudyCapability:flag','study_capability ต้องเป็น boolean');
    end
    if flag, case_data = cases.ne39_study_capability(case_data); end
end
if ~isfield(scenario_opt,'dispatch') || isempty(fieldnames(scenario_opt.dispatch))
    scenario_opt.dispatch = struct();
    for k = 1:numel(case_data.ibr_scheduled)
        s = case_data.ibr_scheduled(k);
        scenario_opt.dispatch.(sprintf('IBR%d',s.bus)) = s.P_MW;
    end
end
if isfield(case_data,'study_capability')
    % DC sizing ผูกกับ operating point นี้: ห้าม reuse design หลังเปลี่ยน dispatch.
    for k = 1:numel(case_data.ibr_scheduled)
        id = sprintf('IBR%d',case_data.ibr_scheduled(k).bus);
        if ~isfield(scenario_opt.dispatch,id) || ...
                ~isequal(scenario_opt.dispatch.(id),case_data.ibr_scheduled(k).P_MW)
            error('cases:ne39StudyCapability:dispatchChanged', ...
                'ต้องออกแบบ DC capability ใหม่เมื่อเปลี่ยน dispatch ของ %s',id);
        end
    end
end
spec = [];
for k = 1:numel(case_data.sg_buses)
    bus = case_data.sg_buses(k);
    u = case_data.machines.units([case_data.machines.units.bus]==bus);
    r = entry(sprintf('SG%d',bus),bus,'sg','sg_classical');
    r.supported_modes = ["synchronous","breaker_open"];
    r.voltage_forming_modes = "synchronous";
    r.initial_mode = "synchronous";
    r.ratings = struct('Mbase',u.Mbase,'Sbase',case_data.base_values.S_base_MVA);
    if isfield(case_data,'study_capability')
        r.limits.Pmax_MW = case_data.dispatch_contract.pmax_MW.(r.resource_id);
    end
    r.provenance = struct('model','sg_classical','source',case_data.reference.sg_dynamics, ...
        'classification','PROJECT_DERIVED_CLASSICAL_REDUCTION', ...
        'details','TAMU GENROU H/Xdp; system-base swing; frozen internal EMF; no AVR/PSS dynamics');
    spec = [spec,r]; %#ok<AGROW>
end
for k = 1:numel(case_data.ibr_buses)
    bus = case_data.ibr_buses(k);
    M = case_data.ibr_ratings_MVA(k);
    Q = case_data.ibr_scheduled(k).Q_MVAr;
    r = entry(sprintf('IBR%d',bus),bus,'ibr','eecon49_dual');
    r.supported_modes = ["gfl","gfm","tripped"];
    r.voltage_forming_modes = "gfm";
    r.initial_mode = "gfl";
    r.has_current_limiter = true;
    r.has_frt = true;
    % Pmax_MW ไม่ใช้ MVA rating เป็น active-power reserve.
    r.limits = struct('ImaxSS',1.2,'ImaxF',1.2,'Pmax_MW',[], ...
        'Qmax_MVAr',M,'Emax',1.2,'Emin',0.8);
    if isfield(case_data,'study_capability')
        r.limits.Pmax_MW = case_data.dispatch_contract.pmax_MW.(r.resource_id);
    end
    r.ratings = struct('Mbase',M,'Sbase',case_data.base_values.S_base_MVA, ...
        'default_P_MW',0,'default_Q_MVAr',Q);
    r.dynamic_params = struct('Mbase',M,'Sbase',case_data.base_values.S_base_MVA, ...
        'fbase',case_data.base_values.frequency_Hz,'f_sw_Hz',5000, ...
        'gfl_eecon49',struct('Lf',0.15,'Rf',0.015,'Cdc',0.10,'Vdc_ref',1, ...
        'Imax',1.2,'kpPLL',1.2,'kiPLL',5,'kpP',0.8,'kiP',2.5,'kpQ',0.8, ...
        'kiQ',2.5,'kpI',0.3,'kiI',4), ...
        'gfm_eecon49',struct('Lf',0.15,'Rf',0.015,'Cdc',0.10,'Vdc_ref',1, ...
        'Imax',1.2,'M',0.08,'Dv',20,'tauE',0.05,'kQ',0.25,'kE',8, ...
        'kpV',1.2,'kiV',4.5,'kpI',0.3,'kiI',4), ...
        'dc_source',struct('Tdc',0.10,'eps_dc',0.10,'Pr',1,'Vdc_max',1.10, ...
        'delta_ch',0.02,'Pmax',1.06*1.2,'tau_s',0.005, ...
        'zeta_target',1/sqrt(2),'source_state',true));
    if isfield(case_data,'study_capability')
        rows = case_data.study_capability.records;
        design = rows(strcmp({rows.resource_id},r.resource_id));
        r.dynamic_params.dc_source.Edc = design.Edc_pu;
        r.dynamic_params.dc_source.Rdc = design.Rdc_pu;
        r.dynamic_params.dc_source.Idc_max = design.Idc_continuous_design_pu;
        r.dynamic_params.dc_source.Psource_max = design.dc_source_power_design_MW/M;
    end
    r.provenance = struct('model','eecon49_dual', ...
        'source','EECON49-P4 Eqs.(6)-(29); project converter/DC design', ...
        'classification','AC_SOURCE_MAPPED_PARAMETERS_PROJECT_DEFINED', ...
        'details',sprintf('17-state shared plant; %.0f MVA converter; DC design bound is not certified reserve',M));
    spec = [spec,r]; %#ok<AGROW>
end
[resources,schema] = stability.resource_table(case_data,spec,scenario_opt);
scenario = stability.build_hybrid_scenario(case_data,resources,scenario_opt);
scenario.resource_schema = schema;
scenario.scenario_id = sprintf('ne39_%dsg_%dibr',numel(case_data.sg_buses),numel(case_data.ibr_buses));
scenario.provenance = struct('case_source',case_data.reference.network, ...
    'sg_dynamics',case_data.reference.sg_dynamics,'ibr_model','eecon49_dual', ...
    'classification','TAMU_SOURCE_NETWORK_PROJECT_DEFINED_HYBRID_REDUCTION', ...
    'source_variant',case_data.source_variant.id);
end

function r = entry(id,bus,type,model)
r = struct('resource_id',id,'bus_id',bus,'resource_type',type,'model_id',model, ...
    'supported_modes',strings(1,0),'voltage_forming_modes',strings(1,0), ...
    'initial_mode',"",'initial_online',true,'can_switch_mode',true, ...
    'can_switch_online',true,'has_current_limiter',false,'has_frt',false, ...
    'can_black_start',false, ...
    'limits',struct('ImaxSS',[],'ImaxF',[],'Pmax_MW',[],'Qmax_MVAr',[], ...
    'Emax',[],'Emin',[]),'ratings',struct(),'dynamic_params',struct(), ...
    'provenance',struct());
end
