function audit=audit_ne39_voltage_chronology(raw_file)
%AUDIT_NE39_VOLTAGE_CHRONOLOGY ตรวจ accepted samples กับ network ตาม event จริง.
% ไม่แก้ raw; strict/study แยกกัน และไม่ใช้ sg_on request แทน breaker reclose.
arguments
    raw_file (1,1) string
end
pf_init_paths(); data=load(raw_file,'request','result');
r=data.result; request=data.request; s=request.scenario; c=s.case_data;
if ~strcmp(request.options.ibr_events.event_profile,'chronology')
    error('audit_ne39_voltage_chronology:scope','ต้องเป็น chronology raw เท่านั้น');
end
[devices,~]=stability.build_mixed_resource_devices(c,s.resources,s.scenario_opt);
dae=stability.composite_dae(c,devices,struct('load_model','cz_p_cz_q'));
bounds=struct('v_min',.9,'v_max',1.1, ...
    'f_min',c.base_values.frequency_Hz-.5,'f_max',c.base_values.frequency_Hz+.5);
audit=struct('artifact',char(raw_file),'status','NO_TRAJECTORY', ...
    'scope','ACCEPTED_SAMPLES_NOT_INTERSAMPLE_OR_GLOBAL_REFINEMENT_CERTIFICATE', ...
    'samples_checked',0,'snapshot_failures',0,'snapshot_unknowns',0, ...
    'first_snapshot_failure_time',NaN,'first_snapshot_failure_reason','', ...
    'max_full_kcl',NaN,'max_kcl_time',NaN,'strict_lte_pass',false, ...
    'horizon_reached',false,'scheduled_events_applied',false, ...
    'actual_reclose_time',r.actual_reclose_time,'reclose_status',r.reclose_status, ...
    'physical_switching_certified',false,'nonvoltage_failures',0, ...
    'voltage_only_failures',0,'study_status','NOT_ASSESSED', ...
    'actual_reclose_applied',false,'strict_snapshot_pass',false,'production_certified',false);
if isempty(r.t), return; end
nt=numel(r.t); kcl=zeros(1,nt); status=cell(1,nt); failures=cell(1,nt);
vm=abs(complex(r.y_traj(1:2:end,:),r.y_traj(2:2:end,:)));
audit.voltage_min_pu=min(vm,[],'all'); audit.voltage_max_pu=max(vm,[],'all');
audit.voltage_observation=stability.ne39_voltage_observation(r.t,vm,c.mpc.bus(:,1),bounds);
e=request.options.ibr_events; Y0=dae.Ynet; Y=Y0; Ybase=Y0;
Sload=(c.mpc.bus(:,3)+1i*c.mpc.bus(:,4))/c.mpc.baseMVA;
load_stamp=e.load_step_factor*diag(conj(Sload)./(abs(dae.pf.bus_voltage(:)).^2+eps));
line_stamp=branch_stamp(c.mpc,e.line_from_bus,e.line_to_bus,dae.bus_ids);
fp=find(dae.bus_ids==e.fault_bus,1); cursor=1;
nd=numel(devices); energy=nan(nd,nt); net=nan(nd,nt); freq=[]; currents=[];
for k=1:nt
    % Event-left เก็บ network เดิม; event-right ใช้ทุก applied event ใน group เดียวกัน.
    isleft=strcmp(r.sample_side{k},'left');
    while cursor<=numel(r.event_log)
        q=r.event_log(cursor);
        if q.t>r.t(k)+1e-12 || (isleft && abs(q.t-r.t(k))<=1e-12), break; end
        if q.applied
            switch q.type
                case 'load_step'
                    Ybase=Ybase+load_stamp; Y=Ybase;
                case 'fault_on'
                    Y=Ybase; Y(fp,fp)=Y(fp,fp)+1/e.Zf;
                case 'fault_clear'
                    Y=Ybase;
                case 'line_trip'
                    Ybase=Ybase-line_stamp; Y=Ybase;
                case 'topology_restore'
                    Ybase=Y0; Y=Y0;
                case {'sg_trip','sg_on','sg_reclose'}
                otherwise
                    error('audit_ne39_voltage_chronology:event', ...
                        'ยังไม่มี network reconstruction สำหรับ applied event %s',q.type);
            end
        end
        cursor=cursor+1;
    end
    ec=r.event_context_history{k}; x=r.x_traj(:,k); y=r.y_traj(:,k); u=r.u_history(:,k);
    V=complex(y(1:2:end),y(2:2:end));
    kcl(k)=norm(Y*V-dae.current_injection(r.t(k),x,y,u,ec),inf);
    ev=stability.ne39_transition_snapshot(r.t(k),x,y,u,ec,dae,s.resources,c,bounds);
    status{k}=ev.status; failures{k}=ev.records(~[ev.records.pass]);
    study_allowed=stability.ne39_snapshot_policy(ev,"observe_voltage");
    audit.nonvoltage_failures=audit.nonvoltage_failures+(strcmp(ev.status,'FAIL') && ~study_allowed);
    audit.voltage_only_failures=audit.voltage_only_failures+(strcmp(ev.status,'FAIL') && study_allowed);
    audit.samples_checked=audit.samples_checked+1;
    audit.snapshot_failures=audit.snapshot_failures+strcmp(ev.status,'FAIL');
    audit.snapshot_unknowns=audit.snapshot_unknowns+~any(strcmp(ev.status,{'PASS','FAIL'}));
    if ~strcmp(ev.status,'PASS') && isnan(audit.first_snapshot_failure_time)
        audit.first_snapshot_failure_time=r.t(k);
        audit.first_snapshot_failure_reason=ev.reason;
        audit.first_snapshot_failure_records=failures{k};
    end
    for q=1:numel(ev.records)
        row=ev.records(q); j=find(strcmp({devices.device_id},row.resource_id),1);
        freq(end+1)=row.f_Hz; %#ok<AGROW>
        if strcmpi(s.resources(j).resource_type,'ibr')
            energy(j,k)=row.capacitor_energy_pu_s+row.source_inductor_energy_pu_s;
            net(j,k)=row.source_minus_losses_pu;
            currents(end+1)=row.I_converter_pu; %#ok<AGROW>
        end
    end
end
[audit.max_full_kcl,j]=max(kcl); audit.max_kcl_time=r.t(j);
audit.online_frequency_min_Hz=min(freq); audit.online_frequency_max_Hz=max(freq);
audit.current_max_converter_pu=max(currents);
audit.strict_lte_pass=r.adaptive_strict_lte && r.floor_accepted_steps==0 && ...
    numel(r.lte_history)==numel(r.dt_history) && all(isfinite(r.lte_history)) && ...
    all(r.lte_history<=1);
audit.horizon_reached=r.converged && abs(r.t(end)-request.options.t_end)<=1e-12;
expected={'sg_trip','load_step','fault_on','fault_clear','line_trip','topology_restore','sg_on'};
times=[e.sg_trip,e.load_step,e.fault_on,e.fault_clear,e.line_trip,e.restore_time,e.sg_on];
applied=false(size(times));
for j=1:numel(expected)
    hit=find(strcmp({r.event_log.type},expected{j}));
    applied(j)=isscalar(hit) && r.event_log(hit).applied && ...
        abs(r.event_log(hit).t-times(j))<=1e-12;
end
audit.scheduled_events_applied=all(applied);
audit.event_types=expected; audit.event_applied=applied;
% A request or a finite summary alone does not prove the breaker closed.
reclose_hit=find(strcmp({r.event_log.type},'sg_reclose') & [r.event_log.applied]);
audit.actual_reclose_applied=isscalar(reclose_hit) && isfinite(r.actual_reclose_time) && ...
    abs(r.event_log(reclose_hit).t-r.actual_reclose_time)<=1e-12 && ...
    strcmp(r.reclose_status,'SUCCESS');
audit.strict_snapshot_pass=audit.snapshot_failures==0 && audit.snapshot_unknowns==0;
audit.phase_summary=struct('phase',{},'samples',{},'failures',{},'unknowns',{});
phases={'pre_trip','post_trip','loaded','fault','post_fault','line_open','restored'};
edges=[0,e.sg_trip,e.load_step,e.fault_on,e.fault_clear,e.line_trip,e.restore_time,Inf];
for j=1:numel(phases)
    mask=r.t>=edges(j) & r.t<edges(j+1);
    audit.phase_summary(j)=struct('phase',phases{j},'samples',sum(mask), ...
        'failures',sum(strcmp(status(mask),'FAIL')), ...
        'unknowns',sum(~strcmp(status(mask),'PASS') & ~strcmp(status(mask),'FAIL')));
end
ib=find(strcmp({s.resources.resource_type},'ibr')); E=energy(ib,:); P=net(ib,:);
ledger=E-E(:,1); integral=zeros(size(E));
for k=2:nt
    integral(:,k)=integral(:,k-1)+.5*(P(:,k-1)+P(:,k))*(r.t(k)-r.t(k-1));
end
balance=ledger-integral;
audit.dc_energy_error_max_pu_s=max(abs(balance),[],'all');
audit.dc_energy_error_by_resource=max(abs(balance),[],2);
audit.dc_energy_resource_ids={devices(ib).device_id};
audit.dc_energy_scope='TRAPEZOIDAL_RAW_SAMPLE_LEDGER_NOT_REFINEMENT_CERTIFICATE';
audit.last_synchronism_guard=r.last_synchronism_guard;
sg=find(strcmp({devices.device_id},e.sg_id));
xr=dae.device_offsets(sg)+(1:devices(sg).nx); ur=dae.u_offsets(sg)+(1:devices(sg).nu);
audit.final_sg=devices(sg).reconstruct(r.t(end),r.x_traj(xr,end),r.y_traj(:,end), ...
    r.u_history(ur,end),r.event_context_history{end});
audit.status='CHRONOLOGY_NOT_VERIFIED';
if audit.horizon_reached && audit.strict_lte_pass && audit.scheduled_events_applied && ...
        isfinite(audit.max_full_kcl) && audit.max_full_kcl<=1e-6
    audit.status='CHRONOLOGY_NUMERICALLY_VERIFIED_PHYSICAL_OR_RECLOSE_INCOMPLETE';
    if audit.strict_snapshot_pass && audit.actual_reclose_applied && ...
            isfinite(audit.dc_energy_error_max_pu_s) && audit.dc_energy_error_max_pu_s<=1e-6
        audit.status='CHRONOLOGY_ACCEPTED_SAMPLES_AND_RECLOSE_VERIFIED';
    end
end
% Study completion ไม่แทน strict status/reclose และยังต้องผ่าน DC energy ledger.
if isfield(request.options,'ne39_assessment_policy') && ...
        strcmp(request.options.ne39_assessment_policy,'observe_voltage')
    audit.study_status='STUDY_INCOMPLETE';
    if audit.horizon_reached && audit.strict_lte_pass && audit.scheduled_events_applied && ...
            isfinite(audit.max_full_kcl) && audit.max_full_kcl<=1e-6 && ...
            audit.nonvoltage_failures==0 && audit.snapshot_unknowns==0 && ...
            isfinite(audit.dc_energy_error_max_pu_s) && audit.dc_energy_error_max_pu_s<=1e-6
        audit.study_status='STUDY_ACCEPTED_SAMPLES_VERIFIED';
    end
end
folder=fileparts(raw_file);
audit_file=fullfile(folder,['chronology_audit_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')) '.mat']);
save(audit_file,'audit','kcl','status','failures','balance','-v7.3');
fprintf(['CHRONOLOGY_AUDIT status=%s samples=%d fail=%d unknown=%d kcl=%.9g ' ...
    'V=[%.9g,%.9g] f=[%.9g,%.9g] Imax=%.9g energy_error=%.9g ' ...
    'strict_lte=%d events=%d reclose=%s\n'],audit.status,audit.samples_checked, ...
    audit.snapshot_failures,audit.snapshot_unknowns,audit.max_full_kcl, ...
    audit.voltage_min_pu,audit.voltage_max_pu,audit.online_frequency_min_Hz, ...
    audit.online_frequency_max_Hz,audit.current_max_converter_pu, ...
    audit.dc_energy_error_max_pu_s,audit.strict_lte_pass,audit.scheduled_events_applied, ...
    char(audit.reclose_status));
for j=1:numel(audit.phase_summary)
    q=audit.phase_summary(j);
    fprintf('CHRONOLOGY_PHASE %s samples=%d fail=%d unknown=%d\n', ...
        q.phase,q.samples,q.failures,q.unknowns);
end
fprintf('CHRONOLOGY_STUDY status=%s strict_snapshot_pass=%d actual_reclose_applied=%d production_certified=%d\n', ...
    audit.study_status,audit.strict_snapshot_pass,audit.actual_reclose_applied,audit.production_certified);
fprintf('artifact=%s\n',audit_file);
end

function stamp=branch_stamp(mpc,from_bus,to_bus,bus_ids)
% ตรวจ stamp จาก branch จริง รวม tap/phase shift/charging บน system base.
br=mpc.branch;
hit=find(((br(:,1)==from_bus & br(:,2)==to_bus) | ...
    (br(:,1)==to_bus & br(:,2)==from_bus)) & br(:,11)~=0);
if ~isscalar(hit), error('audit_ne39_voltage_chronology:branch','ต้องมี branch เดียว'); end
b=br(hit,:); ys=1/(b(3)+1i*b(4)); tap=b(9); if tap==0, tap=1; end
tap=tap*exp(1i*pi/180*b(10)); i=find(bus_ids==b(1),1); j=find(bus_ids==b(2),1);
stamp=zeros(numel(bus_ids),numel(bus_ids));
stamp(i,i)=(ys+1i*b(5)/2)/abs(tap)^2; stamp(i,j)=-ys/conj(tap);
stamp(j,i)=-ys/tap; stamp(j,j)=ys+1i*b(5)/2;
end
