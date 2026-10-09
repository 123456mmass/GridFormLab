function folder=probe_ne39_voltage_dispatch_run(raw_file,chronology,extra)
%PROBE_NE39_VOLTAGE_DISPATCH_RUN รัน production จาก pre-event design ที่บันทึกไว้.
% ไม่ใช้ private trial/replay แทน trajectory; selector ประเมินใหม่ใน production.
arguments
    raw_file (1,1) string
    chronology (1,1) logical = false
    extra (1,1) struct = struct()
end
root=pf_init_paths(); data=load(raw_file,'request'); s=data.request.scenario;
folder=fullfile(root,'output','diagnostics', ...
    ['ne39_voltage_dispatch_run_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder);
if chronology
    catalog=stability.ne39_scenario_catalog(); row=catalog(strcmp({catalog.id},'chronology'));
    e=row.events; T=row.horizon_s;
else
    e=struct('enabled',true,'event_profile','sg_cycle','sg_id','SG31', ...
        'sg_trip',.02,'sg_on',.1,'automatic_gfm_switching',true);
    T=.12;
end
ii=find(strcmp({s.resources.resource_type},'ibr'));
e.gfm_selection_mode='manual_override'; e.selected_gfm_indices=ii;
e.n_gfm_required=numel(ii); e.reference_resource_index=ii(1);
op=struct('t_end',T,'dt',.0025,'verbose',false,'ibr_events',e, ...
    'lazy_gfm_search',true,'budget',struct('max_full_evaluations',4, ...
    'stop_on_first_certified',true),'progress_every',1, ...
    'progress_file',fullfile(folder,'progress.log'), ...
    'ne39_trial_timestep_strategy','adaptive','ne39_trial_max_steps',32000, ...
    'stepper','adaptive','dt_min',.0025/4096,'dt_max',.025, ...
    'dt_max_armed',.01,'atol_x',2e-8,'rtol_x',1e-7, ...
    'atol_y',2e-8,'rtol_y',1e-7,'rannacher_n',0,'reject_limit',16, ...
    'adaptive_strict_lte',true);
for name=fieldnames(extra)'
    op.(name{1})=extra.(name{1});
end
request=struct('source_raw',raw_file,'scenario',s,'options',op, ...
    'classification','PROJECT_DERIVED_VOLTAGE_DISPATCH_PRODUCTION_EXPERIMENT');
save(fullfile(folder,'request.mat'),'request','-v7.3');
fprintf('[NE39-voltage-dispatch-run] start artifact=%s horizon=%g\n',folder,op.t_end);
timer=tic; result=stability.run_hybrid_case(s,op); elapsed=toc(timer);
save(fullfile(folder,'raw.mat'),'request','result','elapsed','-v7.3');
reached=0; if ~isempty(result.t), reached=result.t(end); end
fprintf('[NE39-voltage-dispatch-run] reached=%g/%g converged=%d elapsed=%g\n', ...
    reached,op.t_end,result.converged,elapsed);
if isfield(result,'failure_reason'), fprintf('reason=%s\n',result.failure_reason); end
if isfield(result,'controller_audit') && isfield(result.controller_audit,'ne39_transition')
    a=result.controller_audit.ne39_transition;
    fprintf('trial status=%s reason=%s\n',a.status,a.reason);
    for k=1:numel(a.passes)
        p=a.passes{k};
        fprintf('trial pass=%d reached=%g steps=%d energy_error=%g reason=%s\n', ...
            k,p.t_reached,p.steps,p.energy_error_pu_s,p.reason);
    end
end
if isfield(result,'floor_accepted_steps')
    fprintf('floor_accepted_steps=%d\n',result.floor_accepted_steps);
end
fprintf('artifact=%s\n',folder);
end
