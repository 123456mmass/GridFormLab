function out = run_ieee14_controller_comparison(opts)
%RUN_IEEE14_CONTROLLER_COMPARISON  Three-arm raw 160-s production study.
%   Reuses only the verified legacy raw cache. ET-FCSPS and BO each receive a
%   fresh long production run with identical case, chronology and solver.

arguments
    opts.reuse_completed (1,1) logical = true
    opts.case_id (1,1) string {mustBeMember(opts.case_id, ...
        ["chronology","reference_fault_stress", ...
         "reference_fault_recovery_stress"])} = "chronology"
end
pf_init_paths();
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
if opts.case_id == "chronology"
    artifact_name='ieee14_controller_compare';
elseif opts.case_id == "reference_fault_stress"
    artifact_name='ieee14_controller_reference_fault_stress';
else
    artifact_name='ieee14_controller_reference_fault_recovery_stress';
end
artifact_dir=fullfile(root,'output','diagnostics',artifact_name);
if ~exist(artifact_dir,'dir'), mkdir(artifact_dir); end
[scenario,runopt]=production_request(opts.case_id);
if opts.case_id == "chronology"
    baseline_file=fullfile(root,'output','diagnostics','regfm_post_trip_probe.mat');
else
    baseline_file=fullfile(artifact_dir,'legacy_160_raw.mat');
end
et_file=fullfile(artifact_dir,'et_fcsps_160_raw.mat');
bo_file=fullfile(artifact_dir,'bo_replay_160_raw.mat');
evidence_file=fullfile(artifact_dir,'common_trip_trial_evidence.mat');

if opts.reuse_completed && exist(baseline_file,'file')
    % The historical chronology cache stores `r`; fresh comparison caches
    % store `result`.  Request only the variable used by this case so MATLAB
    % does not emit a misleading "Variable r not found" warning.
    if opts.case_id == "chronology"
        b=load(baseline_file,'r','elapsed');
    else
        b=load(baseline_file,'result','elapsed');
    end
    if isfield(b,'r'), baseline=b.r; else, baseline=b.result; end
    baseline_elapsed=NaN; if isfield(b,'elapsed'), baseline_elapsed=b.elapsed; end
else
    fprintf('CONTROLLER_COMPARE: starting legacy-selector long run (%s)\n',opts.case_id); tic;
    baseline=stability.run_hybrid_case(scenario,runopt); baseline_elapsed=toc;
    result=baseline; elapsed=baseline_elapsed; save(baseline_file,'result','elapsed','-v7.3');
end
validate_long_result(baseline,'legacy baseline',runopt.t_end);

if opts.reuse_completed && exist(evidence_file,'file')
    q=load(evidence_file,'trial_evidence','selector_table');
    trial_evidence=q.trial_evidence; selector_table=q.selector_table;
else
    fprintf('CONTROLLER_COMPARE: building authenticated candidate universe\n');
    selector_table=stability.ibr_selector_table(scenario.case_data, ...
        scenario.resources,scenario,struct('sg_on',struct('n_gfm_required',0)));
    fprintf('CONTROLLER_COMPARE: generating common nonlinear 0.25-s trial table\n');
    trial_evidence=build_common_evidence(baseline,scenario,selector_table,runopt.dt);
    save(evidence_file,'trial_evidence','selector_table','-v7.3');
end

if opts.reuse_completed && exist(et_file,'file')
    q=load(et_file,'result','elapsed'); et=q.result; et_elapsed=q.elapsed;
else
    fprintf('CONTROLLER_COMPARE: starting ET-FCSPS long run\n'); tic;
    etopt=runopt; etopt.controller_mode='et_fcsps';
    etopt.controller_trial_evidence=trial_evidence; etopt.selector_table=selector_table;
    et=stability.run_hybrid_case(scenario,etopt); et_elapsed=toc;
    result=et; elapsed=et_elapsed; save(et_file,'result','elapsed','-v7.3');
end
validate_long_result(et,'ET-FCSPS',runopt.t_end);

if opts.reuse_completed && exist(bo_file,'file')
    q=load(bo_file,'result','elapsed'); bo=q.result; bo_elapsed=q.elapsed;
else
    fprintf('CONTROLLER_COMPARE: starting BO-replay long run\n'); tic;
    boopt=runopt; boopt.controller_mode='bo_replay';
    boopt.controller_trial_evidence=trial_evidence; boopt.selector_table=selector_table;
    bo=stability.run_hybrid_case(scenario,boopt); bo_elapsed=toc;
    result=bo; elapsed=bo_elapsed; save(bo_file,'result','elapsed','-v7.3');
end
validate_long_result(bo,'BO replay',runopt.t_end);

summary=[summarize('Legacy selector',baseline,baseline_elapsed,NaN), ...
    summarize('ET-FCSPS',et,et_elapsed,prediction_count(et)), ...
    summarize('BO replay',bo,bo_elapsed,prediction_count(bo))];
writetable(struct2table(summary),fullfile(artifact_dir,'summary.csv'));
out=struct('baseline',baseline,'et_fcsps',et,'bo',bo,'summary',summary, ...
    'trial_evidence',trial_evidence,'artifact_dir',artifact_dir, ...
    'case_id',char(opts.case_id));
save(fullfile(artifact_dir,'comparison_raw.mat'),'out','-v7.3');
fprintf('CONTROLLER_COMPARE_DONE: ET %.3f s, BO %.3f s\n',et_elapsed,bo_elapsed);
end

function evidence=build_common_evidence(r,s,table,dt)
idx=find(abs(r.t-r.sched.sg_trip)<1e-12 & strcmp(r.sample_side,'left'),1,'last');
if isempty(idx), error('run_ieee14_controller_comparison:noTripLeft','Cached baseline lacks SG-trip left limit.'); end
dae=stability.composite_dae(s.case_data,r.equilibrium.devices,struct('load_model','cz_p_cz_q'));
[~,audit]=stability.et_fcs_production_trip_decision(r.t(idx),r.x_traj(:,idx), ...
    r.y_traj(:,idx),dae.Ynet,r.u_history(:,idx),r.event_context_history{idx}, ...
    dae,r.sched,s.case_data,s.resources,table,'et_fcsps',struct('dt',dt));
evidence=struct('base_snapshot_fingerprint',audit.base_snapshot_fingerprint, ...
    'trial_table',audit.trial_table,'generated_from','accepted cached event-left state', ...
    'classification','PROJECT_DERIVED_PROTOTYPE');
end

function [s,opt]=production_request(case_id)
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
if case_id == "chronology"
    ev=struct('enabled',true,'event_profile','chronology','sg_trip',20, ...
        'load_step',50,'load_step_factor',0.20,'fault_on',85,'fault_clear',85.15, ...
        'fault_bus',9,'Zf',0.01+0.01i,'line_trip',110,'line_from_bus',6, ...
        'line_to_bus',13,'restore_time',145,'sg_on',145, ...
        'coordinated_handback',true,'selected_gfm_indices',2:5, ...
        'reference_resource_index',2,'automatic_gfm_switching',true, ...
        'delays_overrides',struct('timeout_s',5,'dwell_s',0.5));
elseif case_id == "reference_fault_stress"
    % PROJECT_DERIVED stress contract, frozen before its first run: a
    % three-phase fault at the legacy IBR1 reference PCC is cleared only one
    % fixed step before SG loss. This tests mode-set and owner selection from
    % a non-equilibrium accepted state without changing model/controller data.
    ev=struct('enabled',true,'event_profile','combined', ...
        'fault_on',19.75,'fault_clear',20.00,'fault_bus',2,'Zf',0.01+0.01i, ...
        'sg_trip',20.0125,'sg_on',145,'coordinated_handback',true, ...
        'selected_gfm_indices',2:5,'reference_resource_index',2, ...
        'automatic_gfm_switching',true, ...
        'delays_overrides',struct('timeout_s',5,'dwell_s',0.5));
else
    % PROJECT_DERIVED stress-in-domain contract, frozen before its first run:
    % retain the bus-2 PCC fault and SG-loss ordering but allow 0.5125 s of
    % post-clear recovery before the trip (41 fixed steps). It is not a
    % parameter fit; it is the next fixed-grid event boundary after the
    % one-step outside-domain diagnostic above.
    ev=struct('enabled',true,'event_profile','combined', ...
        'fault_on',19.25,'fault_clear',19.50,'fault_bus',2,'Zf',0.01+0.01i, ...
        'sg_trip',20.0125,'sg_on',145,'coordinated_handback',true, ...
        'selected_gfm_indices',2:5,'reference_resource_index',2, ...
        'automatic_gfm_switching',true, ...
        'delays_overrides',struct('timeout_s',5,'dwell_s',0.5));
end
opt=struct('t_end',160,'dt',0.0125,'verbose',false,'ibr_events',ev, ...
    'plot_results',false);
end

function validate_long_result(r,label,t_end)
if ~isstruct(r) || ~isfield(r,'converged') || ~r.converged || ...
        isempty(r.t) || abs(r.t(end)-t_end)>1e-10 || ...
        any(~isfinite(r.x_traj(:))) || any(~isfinite(r.y_traj(:)))
    endpoint=NaN; if isstruct(r) && isfield(r,'t') && ~isempty(r.t), endpoint=r.t(end); end
    error('run_ieee14_controller_comparison:longRunGate', ...
        '%s failed the raw %.6g-s gate (endpoint %.12g).',label,t_end,endpoint);
end
end

function s=summarize(name,r,elapsed,neval)
V=r.bus_voltage_magnitude; f=r.device_frequency_Hz;
ratio=r.device_current_magnitude./r.device_current_limit_sys;
ratio(~isfinite(ratio))=NaN;
sw=0; gfm_time=0; didx=find(startsWith(string(r.device_ids),'IBR'));
for k=didx
    m=strcmpi(r.device_modes_history(k,:),'gfm'); sw=sw+sum(diff(m)~=0);
    gfm_time=gfm_time+trapz(r.t,double(m));
end
acc=r.accepted_residual_per_step; acc=acc(isfinite(acc));
s=struct('method',name,'converged',r.converged,'end_time_s',r.t(end), ...
    'min_voltage_pu',min(V(:)),'max_voltage_pu',max(V(:)), ...
    'min_frequency_Hz',min(f(isfinite(f))),'max_frequency_Hz',max(f(isfinite(f))), ...
    'max_current_utilization',max(ratio,[],'all','omitnan'), ...
    'switch_count',sw,'aggregate_gfm_time_s',gfm_time, ...
    'actual_reclose_s',r.actual_reclose_time,'reselection_status',r.reselection_status, ...
    'max_accepted_residual',max(acc),'prediction_evaluations',neval, ...
    'wall_time_s',elapsed,'selected_gfm',selected_text(r), ...
    'reference_owner',reference_text(r));
end

function n=prediction_count(r)
n=NaN;
if ~isfield(r,'controller_audit') || isempty(fieldnames(r.controller_audit)), return; end
if strcmp(r.controller_audit.mode,'et_fcsps')
    n=sum([r.controller_audit.decision.candidates.prediction_pass]);
elseif isfield(r.controller_audit,'bo') && isfield(r.controller_audit.bo,'evaluation_count')
    n=r.controller_audit.bo.evaluation_count;
end
end

function s=selected_text(r)
s='';
if isfield(r,'controller_audit') && ~isempty(fieldnames(r.controller_audit))
    s=strjoin(string(r.controller_audit.selection.selected_gfm_indices),'-');
elseif isfield(r,'event_log')
    k=find(strcmp({r.event_log.type},'sg_trip') & [r.event_log.applied],1,'last');
    if ~isempty(k), s=strjoin(string(r.event_log(k).selected_gfm_indices),'-'); end
end
end

function s=reference_text(r)
s='';
if isfield(r,'controller_audit') && ~isempty(fieldnames(r.controller_audit))
    s=string(r.controller_audit.selection.reference_resource_index);
elseif isfield(r,'event_log')
    k=find(strcmp({r.event_log.type},'sg_trip') & [r.event_log.applied],1,'last');
    if ~isempty(k), s=string(r.event_log(k).reference_resource_index); end
end
end
