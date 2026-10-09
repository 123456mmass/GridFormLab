function folder=probe_ne39_voltage_operating_point(v_floor)
%PROBE_NE39_VOLTAGE_OPERATING_POINT ออกแบบ voltage dispatch ก่อนเหตุการณ์.
% คง source archive, network, SG H/D/Xdp และ acceptance gates; ไม่ติดตั้ง default.
arguments
    v_floor (1,1) double {mustBeFinite,mustBePositive} = 1.02
end
if v_floor>1.06
    error('probe_ne39_voltage_operating_point:voltage','study setpoint ต้องไม่เกิน1.06pu');
end
root=pf_init_paths();
folder=fullfile(root,'output','diagnostics', ...
    ['ne39_voltage_op_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder);
c=cases.case_ne39_1sg_9ibr();
% ใช้ P non-reference เดิมและปรับ voltage setpoint ของ generator buses เท่านั้น.
% PF stage นี้ derive reactive schedules ก่อนแปลง IBR เป็น PQ resources.
pfcase=c;
pfcase.bus_data(c.ibr_buses,2)=2;
resource_buses=[c.sg_buses;c.ibr_buses];
pfcase.bus_data(resource_buses,3)=max(c.bus_data(resource_buses,3),v_floor);
pf=pfsolver.powerflow_newton_raphson(pfcase,struct('verbose',false, ...
    'plot_results',false,'max_iter',50,'tolerance',1e-11,'enforce_q_limits',false));
assert(pf.converged,'study voltage-dispatch PF ต้อง converged');
c.bus_data(:,3:6)=[pf.bus_voltage pf.bus_angle_deg pf.P_generation pf.Q_generation];
c.mpc.bus(:,8:9)=c.bus_data(:,3:4);
c.mpc.gen(:,2:3)=c.bus_data(c.sg_buses,5:6)*c.mpc.baseMVA;
c.mpc.gen(:,6)=c.bus_data(c.sg_buses,3);
for bus=resource_buses(:)'
    id=sprintf('IBR%d',bus);
    if ismember(bus,c.sg_buses), id=sprintf('SG%d',bus); end
    c.dispatch_contract.pre_fault.(id)=c.bus_data(bus,5)*c.mpc.baseMVA;
end
for k=1:numel(c.ibr_buses)
    bus=c.ibr_buses(k); id=sprintf('IBR%d',bus);
    c.ibr_scheduled(k).P_MW=c.bus_data(bus,5)*c.mpc.baseMVA;
    c.ibr_scheduled(k).Q_MVAr=c.bus_data(bus,6)*c.mpc.baseMVA;
    c.dispatch_contract.ibr_scheduled_Q_MVAr.(id)=c.ibr_scheduled(k).Q_MVAr;
end
c.reference.slack=sprintf('SG31 V=%.6g pu angle=0 (PROJECT_DERIVED_VOLTAGE_DISPATCH)',c.bus_data(31,3));
c.voltage_dispatch=struct('classification','PROJECT_DERIVED_DIAGNOSTIC_DESIGN', ...
    'minimum_generator_setpoint_pu',v_floor,'raw_source_modified',false, ...
    'rule','raise generator setpoints below floor; derive Q by pre-event PF');
c=cases.standardize_case(c);
im=struct('device_id',{'IBR33','IBR37'},'mode',{'gfm','gfm'});
s=cases.scenario_ne39_tamu_mixed(c,struct('study_capability',true,'initial_modes',im));
ii=find(strcmp({s.resources.resource_type},'ibr'));
e=struct('enabled',true,'event_profile','sg_cycle','sg_trip',.02, ...
    'sg_on',.1,'automatic_gfm_switching',true,'gfm_selection_mode','manual_override', ...
    'selected_gfm_indices',ii,'n_gfm_required',numel(ii),'reference_resource_index',ii(1));
op=struct('t_end',.12,'dt',.0025,'verbose',false,'ibr_events',e, ...
    'lazy_gfm_search',true,'budget',struct('max_full_evaluations',4, ...
    'stop_on_first_certified',true),'progress_every',.01, ...
    'progress_file',fullfile(folder,'progress.log'));
request=struct('scenario',s,'options',op); timer=tic;
result=stability.run_hybrid_case(s,op); elapsed=toc(timer);
save(fullfile(folder,'raw.mat'),'request','result','elapsed','-v7.3');
reached=0; if ~isempty(result.t), reached=result.t(end); end
fprintf('[NE39-voltage-op] floor=%g reached=%g/.12 converged=%d elapsed=%gs\n', ...
    v_floor,reached,result.converged,elapsed);
if isfield(result,'failure_reason'), fprintf('reason=%s\n',result.failure_reason); end
if isfield(result,'selector_table')
    for name={'sg_on','sg_off'}
        for candidate=result.selector_table.(name{1}).configurations
            fprintf('%s selected=%s feasible=%d zeta=%g omega=%g reason=%s\n', ...
                name{1},mat2str(candidate.selected_gfm_indices),candidate.feasible, ...
                candidate.zeta_worst,candidate.omega,candidate.reason);
        end
    end
end
if isfield(result,'controller_audit') && isfield(result.controller_audit,'ne39_transition')
    a=result.controller_audit.ne39_transition;
    for k=1:numel(a.passes)
        fprintf('trial=%d reached=%g reason=%s\n',k,a.passes{k}.t_reached,a.passes{k}.reason);
        if isfield(a.passes{k},'failed_snapshot')
            for record=a.passes{k}.failed_snapshot.records
                if ~record.pass
                    fprintf('FAIL %s %s V=%g f=%g P=%g Q=%g I=%g\n', ...
                        record.resource_id,record.failure,record.V_pu,record.f_Hz, ...
                        record.P_MW,record.Q_MVAr,record.I_converter_pu);
                end
            end
        end
    end
end
fprintf('artifact=%s\n',folder);
end
