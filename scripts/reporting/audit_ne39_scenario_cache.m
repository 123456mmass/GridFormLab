function audit = audit_ne39_scenario_cache(artifact)
%AUDIT_NE39_SCENARIO_CACHE ตรวจ accepted raw samples โดยไม่แก้ trajectory.
% ผล snapshot ไม่ใช่ stability/transition certificate; blocked arm ไม่มีข้อมูลให้ตรวจ.
arguments
    artifact (1,1) string
end
pf_init_paths();
S=load(artifact,'request','result');
if ~all(isfield(S,{'request','result'})) || ...
        ~isstruct(S.request) || ~isscalar(S.request) || ...
        ~isstruct(S.result) || ~isscalar(S.result) || ...
        ~isfield(S.request,'model_sha256')
    error('audit_ne39_scenario_cache:artifact','ขาด request/result/model hash');
end
r=S.result; request=S.request;
audit=struct('artifact',char(artifact),'samples_checked',0, ...
    'requested_model_sha256',request.model_sha256, ...
    'audit_equations','CURRENT_CHECKOUT_MODEL_RHS', ...
    'status','NO_TRAJECTORY','first_failure_time',NaN, ...
    'first_failure_reason','','first_failure_records',struct([]), ...
    'snapshot_failures',0,'snapshot_unknowns',0, ...
    'voltage_min_pu',NaN,'voltage_max_pu',NaN, ...
    'current_max_converter_pu',NaN,'source_current_max_pu',NaN, ...
    'dc_voltage_min_pu',NaN,'dc_voltage_max_pu',NaN, ...
    'max_energy_rhs_error_pu',NaN,'max_ac_dc_power_error_pu',NaN, ...
    'physical_switching_certified',false, ...
    'scope','ACCEPTED_SAMPLE_SNAPSHOT_NOT_INTERSAMPLE_OR_TRANSITION_CERTIFICATE');
if ~isfield(r,'t'), audit.status='MISSING_RAW_CONTEXT'; return; end
if isempty(r.t), return; end
if ~all(isfield(r,{'equilibrium','u_history','x_traj','y_traj'})) || ...
        ~all(isfield(request,{'case_data','resources','options'})) || ...
        ~all(isfield(r.equilibrium,{'devices','equilibrium_context'}))
    audit.status='MISSING_RAW_CONTEXT'; return;
end
c=request.case_data; resources=request.resources;
load_model='cz_p_cz_q';
if isfield(request.options,'load_model'), load_model=request.options.load_model; end
dae=stability.composite_dae(c,r.equilibrium.devices,struct('load_model',load_model));
nt=numel(r.t);
if ~isvector(r.t) || ~isreal(r.t) || any(~isfinite(r.t)) || any(diff(r.t)<0) || ...
        ~isequal(size(r.x_traj),[sum([dae.devices.nx]),nt]) || ...
        ~isequal(size(r.y_traj),[2*size(c.bus_data,1),nt]) || ...
        ~isequal(size(r.u_history),[sum([dae.devices.nu]),nt])
    audit.status='INVALID_RAW_DIMENSIONS_OR_TIME'; return;
end
has_context=isfield(r,'event_context_history');
if has_context && (~iscell(r.event_context_history) || ...
        numel(r.event_context_history)~=nt || ...
        ~all(cellfun(@(ec)isstruct(ec)&&isscalar(ec),r.event_context_history)))
    audit.status='MISSING_RAW_CONTEXT'; return;
end
if ~has_context && isfield(request.options,'ibr_events') && ...
        request.options.ibr_events.enabled
    audit.status='MISSING_EVENT_CONTEXT'; return;
end
bounds=struct('v_min',.9,'v_max',1.1,'f_min',c.base_values.frequency_Hz-.5, ...
    'f_max',c.base_values.frequency_Hz+.5);
if isfield(request.options,'ne39_policy')
    for name=fieldnames(bounds).'
        if isfield(request.options.ne39_policy,name{1})
            bounds.(name{1})=request.options.ne39_policy.(name{1});
        end
    end
end
audit.bounds=bounds;
vm=abs(complex(r.y_traj(1:2:end,:),r.y_traj(2:2:end,:)));
audit.voltage_min_pu=min(vm,[],'all'); audit.voltage_max_pu=max(vm,[],'all');
current=[]; idc=[]; vdc=[]; error_dc=[]; error_ac=[];
for k=1:numel(r.t)
    ec=r.equilibrium.equilibrium_context;
    if has_context, ec=r.event_context_history{k}; end
    e=stability.ne39_transition_snapshot(r.t(k),r.x_traj(:,k),r.y_traj(:,k), ...
        r.u_history(:,k),ec,dae,resources,c,bounds);
    audit.samples_checked=audit.samples_checked+1;
    if strcmp(e.status,'FAIL')
        audit.snapshot_failures=audit.snapshot_failures+1;
    elseif ~strcmp(e.status,'PASS')
        audit.snapshot_unknowns=audit.snapshot_unknowns+1;
    end
    if ~strcmp(e.status,'PASS') && isnan(audit.first_failure_time)
        audit.first_failure_time=r.t(k);
        audit.first_failure_reason=e.reason;
        if ~isempty(e.records)
            audit.first_failure_records=e.records(~[e.records.pass]);
        end
    end
    if isempty(e.records), continue; end
    rows=e.records(startsWith({e.records.resource_id},'IBR'));
    current=[current,[rows.I_converter_pu]]; %#ok<AGROW>
    idc=[idc,[rows.Idc_pu]]; vdc=[vdc,[rows.Vdc_pu]]; %#ok<AGROW>
    error_dc=[error_dc,[rows.energy_rhs_error_pu]]; %#ok<AGROW>
    error_ac=[error_ac,[rows.ac_dc_power_error_pu]]; %#ok<AGROW>
end
if ~isempty(current)
    audit.current_max_converter_pu=max(current);
    audit.source_current_max_pu=max(idc);
    audit.dc_voltage_min_pu=min(vdc); audit.dc_voltage_max_pu=max(vdc);
    audit.max_energy_rhs_error_pu=max(error_dc); audit.max_ac_dc_power_error_pu=max(error_ac);
end
if audit.snapshot_unknowns>0
    audit.status='UNKNOWN_SNAPSHOT_EVIDENCE';
elseif audit.snapshot_failures>0
    audit.status='SNAPSHOT_CONSTRAINT_FAILURE';
else
    audit.status='ACCEPTED_SNAPSHOTS_PASS_NOT_TRANSITION_CERTIFIED';
end
end
