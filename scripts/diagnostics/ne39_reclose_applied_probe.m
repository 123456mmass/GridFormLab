function folder = ne39_reclose_applied_probe_resume()
%NE39_RECLOSE_APPLIED_PROBE_RESUME Fresh true-trip SG31 reclose diagnostic.
% Explicitly called only. Builds the designed NE39 SG31+9-IBR case with the
% opt-in seven-state SG plant and all nine IBRs in GFM, trips SG31 at 0.02 s,
% then requests reclose at 125.02 s: a real 125-s offline recovery interval.
% Initially-offline startup is deliberately NOT used: the canonical simulator
% requires its own finite t_trip before the unchanged min-off gate can arm.
%
% Uses public stability.run_hybrid_case -> fresh trusted lazy SG_OFF/SG_ON
% selector equilibria/spectra -> canonical stability.ts_simulate_ibr_hybrid.
% The close request is not forced. No fabricated certificate, private replay,
% rotor/state reset, old160 raw access, synchronism/delay override, or gate
% relaxation is used. The SG_ON selector is count-pinned to the physical current
% nine-GFM set, not given ready flags. The 131-s horizon includes the unchanged
% 5-s request timeout and a short tail; this is not the full 160-s chronology.
%
% observe_voltage affects accepted-sample study reporting ONLY: strict voltage
% excursions are separate from nonvoltage sample checks; the private transition
% trial/numerical-refinement, all physical gates, and actual transactional
% right-limit KCL remain fail-closed. Always production_certified=false.
%
% Usage (after project paths are available):
%   folder = ne39_reclose_applied_probe_resume();

root = pf_init_paths();
folder = unique_folder(root);
mkdir(folder);
request = struct('created_at',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss.SSS')), ...
    'artifact_folder',folder, ...
    'classification','PROJECT_DERIVED_TRUE_TRIP_RECLOSE_DIAGNOSTIC', ...
    'production_certified',false,'hardware_certified',false, ...
    'full_chronology',false,'old160_raw_read_or_modified',false);
result = struct('converged',false,'failure_id','','failure_reason','');
run_error = struct('occurred',false,'failure_id','','message','','stack',[]);
elapsed = 0;

try
    [design_options,design_analysis] = ne39_endpoint_design_options();
    c = cases.ne39_chronology_design(cases.case_ne39_1sg_9ibr(),design_options);
    scenario = cases.scenario_ne39_tamu_mixed(c,struct( ...
        'sg_reclose_plant',true,'initial_modes',design_analysis.initial_modes));
    ibr = find(strcmpi({scenario.resources.resource_type},'ibr'));
    sg = find(strcmpi({scenario.resources.resource_id},'SG31'));
    if numel(ibr)~=9 || numel(sg)~=1 || numel(scenario.resources)~=10 || ...
            ~all(strcmpi(string({scenario.resources(ibr).initial_mode}),'gfm')) || ...
            ~strcmpi(char(scenario.resources(sg).model_id),'sg_classical_reclose')
        error('ne39_reclose_applied_probe_resume:composition', ...
            'Expected designed SG31 seven-state plant and all nine GFM IBRs.');
    end
    t_trip = 0.02; t_request = 125.02; t_end = 131.0;
    events = struct('enabled',true,'event_profile','sg_cycle','sg_id','SG31', ...
        'sg_trip',t_trip,'sg_on',t_request,'automatic_gfm_switching',true, ...
        'gfm_selection_mode','manual_override', ...
        'selected_gfm_indices',ibr,'n_gfm_required',numel(ibr), ...
        'reference_resource_index',ibr(1));
    options = struct('t_end',t_end,'dt',0.001,'verbose',false, ...
        'ibr_events',events,'lazy_gfm_search',true, ...
        'budget',struct('max_full_evaluations',4,'stop_on_first_certified',true), ...
        'sg_on_n_gfm_required',9,'post_reclose_mode_reselection',false, ...
        'stepper','adaptive','adaptive_strict_lte',true, ...
        'dt_min',0.0025/4096,'dt_max',0.025,'dt_max_armed',0.01, ...
        'atol_x',2e-8,'rtol_x',1e-7,'atol_y',2e-8,'rtol_y',1e-7, ...
        'rannacher_n',0,'reject_limit',16, ...
        'ne39_trial_timestep_strategy','adaptive','ne39_trial_max_steps',32000, ...
        'ne39_assessment_policy','observe_voltage', ...
        'progress_every',5,'progress_file',fullfile(folder,'progress.log'));
    request.case_data=c; request.scenario=scenario;
    request.design_options=design_options; request.events=events; request.options=options;
    request.initial_gfm_resource_ids={scenario.resources(ibr).resource_id};
    request.sg_plant_state_names={'delta','omega','Psv','Pm','Emag','theta_hat','nu_hat'};
    request.declared_synchronism=c.synchronism;
    request.declared_minimum_off_s=c.delays.T_sg_min_off_s;
    request.sg_offline_interval_s=t_request-t_trip;
    save(fullfile(folder,'request.mat'),'request','-v7.3');

    fprintf('[NE39-reclose-probe] start folder=%s trip=%.6f request=%.6f horizon=%.6f\n', ...
        folder,t_trip,t_request,t_end);
    timer=tic;
    try
        result=stability.run_hybrid_case(scenario,options);
    catch me
        run_error=struct('occurred',true,'failure_id',me.identifier, ...
            'message',me.message,'stack',me.stack);
        result=struct('converged',false,'failure_id',me.identifier, ...
            'failure_reason',me.message);
    end
    elapsed=toc(timer);
    % Persist exact raw public-run evidence before any post-processing.
    result.production_certified=false;
    result.hardware_certified=false;
    result.full_chronology=false;
    result.classification=request.classification;
    % Persist exact raw public-run evidence before any post-processing.
    save(fullfile(folder,'raw.mat'),'request','result','elapsed','run_error','-v7.3');
    try
        audit=summarize_result(result,scenario,options);
    catch audit_error
        audit=struct('status','POSTPROCESSING_FAILED','production_certified',false, ...
            'actual_close',false,'actual_reclose_time',value(result,'actual_reclose_time',NaN), ...
            'reclose_status',char(string(value(result,'reclose_status','UNKNOWN'))), ...
            'failure_id',audit_error.identifier,'failure_reason',audit_error.message, ...
            'accepted_path_status','RAW_RESULT_PRESERVED');
        audit.audit_error_stack=audit_error.stack;
    end
    audit.run_error=run_error;
    save(fullfile(folder,'audit.mat'),'audit','-v7.3');
    try
        print_summary(folder,audit,elapsed);
    catch summary_error
        fprintf('[NE39-reclose-probe] summary printing failed: %s: %s; raw preserved in %s\\n', ...
            summary_error.identifier,summary_error.message,fullfile(folder,'raw.mat'));
    end
catch me
    run_error=struct('occurred',true,'failure_id',me.identifier, ...
        'message',me.message,'stack',me.stack);
    request.setup_failure_id=me.identifier; request.setup_failure_reason=me.message;
    audit=struct('status','SETUP_FAILED','production_certified',false, ...
        'actual_close',false,'actual_reclose_time',NaN,'reclose_status','NOT_REQUESTED', ...
        'failure_id',me.identifier,'failure_reason',me.message);
    raw_file=fullfile(folder,'raw.mat');
    if isfile(raw_file)
        % A raw public-run result is immutable even if later audit/report work fails.
        save(fullfile(folder,'audit_failure.mat'),'audit','run_error','-v7.3');
        fprintf('[NE39-reclose-probe] post-run failure; preserved raw=%s id=%s reason=%s\\n', ...
            raw_file,me.identifier,me.message);
    else
        result=struct('converged',false,'failure_id',me.identifier,'failure_reason',me.message, ...
            'production_certified',false);
        save(fullfile(folder,'request.mat'),'request','-v7.3');
        save(raw_file,'request','result','audit','elapsed','run_error','-v7.3');
        try, print_summary(folder,audit,elapsed); catch, end
    end
end
end

function folder=unique_folder(root)
base=['ne39_reclose_applied_probe_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))];
folder=fullfile(root,'output','diagnostics',base); k=0;
while isfolder(folder), k=k+1; folder=fullfile(root,'output','diagnostics',sprintf('%s_%02d',base,k)); end
end

function a=summarize_result(r,s,op)
a=struct('status','NO_ACTUAL_CLOSE','production_certified',false, ...
    'hardware_certified',false,'full_chronology',false,'actual_close',false, ...
    'actual_reclose_time',NaN,'reclose_status','NOT_REQUESTED', ...
    'strict_voltage_status','UNKNOWN','strict_nonvoltage_status','UNKNOWN', ...
    'accepted_path_status','UNKNOWN','private_trial_status','UNKNOWN', ...
    'sg_state_bounds_status','UNKNOWN','sg_actual_current_mva_status','UNKNOWN', ...
    'close_state_continuity_status','UNKNOWN');
if isfield(r,'converged'), a.run_converged=logical(r.converged); end
if isfield(r,'failure_id'), a.failure_id=char(string(r.failure_id)); end
if isfield(r,'failure_reason'), a.failure_reason=char(string(r.failure_reason)); end
if isfield(r,'t'), a.accepted_sample_count=numel(r.t); else, a.accepted_sample_count=0; end
for f={'accepted_steps','step_attempts','requested_sg_on_time','actual_reclose_time','reclose_status'}
    if isfield(r,f{1}), a.(f{1})=r.(f{1}); end
end
if isfield(r,'t_sg_trip'), a.actual_trip_time=r.t_sg_trip; else, a.actual_trip_time=NaN; end
if isfield(r,'reclose_status'), a.reclose_status=char(string(r.reclose_status)); end
trip=false; req=false; close=struct();
if isfield(r,'event_log') && isstruct(r.event_log)
    for k=1:numel(r.event_log)
        e=r.event_log(k);
        if strcmp(e.type,'sg_trip'), trip=logical(e.applied); end
        if strcmp(e.type,'sg_on'), req=logical(e.applied); end
        if strcmp(e.type,'sg_reclose') && logical(e.applied), close=e; end
    end
end
a.sg_trip_event_applied=trip; a.sg_on_request_event_applied=req;
a.sg_reclose_event_applied=~isempty(fieldnames(close));
a.actual_close=isfinite(a.actual_reclose_time) && ...
    strcmp(a.reclose_status,'SUCCESS') && a.sg_reclose_event_applied;
if a.actual_close, a.status='ACTUAL_STRICT_TRANSACTIONAL_CLOSE_OBSERVED'; end
a.minimum_off_s=s.case_data.delays.T_sg_min_off_s;
if isfinite(a.actual_trip_time)&&isfinite(a.actual_reclose_time)
    a.actual_offline_age_s=a.actual_reclose_time-a.actual_trip_time;
    a.minimum_off_pass=a.actual_offline_age_s>=a.minimum_off_s-1e-12;
else
    a.actual_offline_age_s=NaN; a.minimum_off_pass=false;
end
a.sync_thresholds=s.case_data.synchronism; a.dwell_s=s.case_data.synchronism.dwell_s;
a.timeout_s=s.case_data.synchronism.timeout_s;
a.guard_overrides_supplied=isfield(op,'synchronism_overrides')||isfield(op,'delays_overrides');
if ~isempty(fieldnames(close))&&isfield(close,'guard'), a.guard=close.guard;
elseif isfield(r,'last_synchronism_guard'), a.guard=r.last_synchronism_guard;
else, a.guard=struct(); end
a.guard_metric_checks=guard_checks(a.guard,s.case_data.synchronism);
if isfield(r,'resync_diagnostics')&&~isempty(r.resync_diagnostics), a.last_resync_diagnostic=r.resync_diagnostics(end); end

% Strict voltage and nonvoltage accepted-sample evidence are not conflated.
if isfield(r,'ne39_assessment')
    n=r.ne39_assessment;
    a.assessment_samples_checked=n.samples_checked;
    a.assessment_strict_snapshot_failures=n.strict_snapshot_failures;
    a.voltage_excursion_samples=n.voltage_excursion_samples;
    a.energy_error_pu_s=n.energy_error_pu_s;
    a.accepted_sample_audit_complete=n.samples_checked==a.accepted_sample_count&&a.accepted_sample_count>0;
    if n.voltage_excursion_samples>0, a.strict_voltage_status='FAIL_ON_OBSERVED_SAMPLES';
    elseif a.accepted_sample_audit_complete, a.strict_voltage_status='PASS_ON_OBSERVED_SAMPLES'; end
    if n.failed, a.strict_nonvoltage_status='FAIL_OR_INCOMPLETE';
    elseif a.accepted_sample_audit_complete, a.strict_nonvoltage_status='PASS_ON_OBSERVED_SAMPLES'; end
    if isfield(n,'failed_snapshot')&&isstruct(n.failed_snapshot), a.failed_snapshot=n.failed_snapshot; end
end
if isfield(r,'converged')&&r.converged&&~isempty(r.t)&&r.t(end)>=op.t_end-1e-10
    a.accepted_path_status='NUMERICAL_HORIZON_COMPLETE';
elseif a.accepted_sample_count>0, a.accepted_path_status='NUMERICAL_FAILED_OR_SHORT_AFTER_SAMPLES';
else, a.accepted_path_status='NUMERICAL_FAILED_BEFORE_ACCEPTED_SAMPLE'; end
if isfield(r,'controller_audit')&&isfield(r.controller_audit,'ne39_transition')
    p=r.controller_audit.ne39_transition; a.private_transition_trial=p;
    if isfield(p,'status'), a.private_trial_status=char(string(p.status)); end
    if isfield(p,'reason'), a.private_trial_reason=char(string(p.reason)); end
end
% Fresh selector evidence generated by this invocation, not injected flags.
if isfield(r,'selector_table')
    a.selector_table_fingerprint=r.selector_table.selector_table_fingerprint;
    ii=find(strcmpi({s.resources.resource_type},'ibr'));
    a.sg_off_selector=selector_summary(r.selector_table,'sg_off',ii);
    a.sg_on_selector=selector_summary(r.selector_table,'sg_on',ii);
end
% SG mechanical/field bounds and actual online current/MVA against the explicit
% positive PROJECT_DERIVED stator rating (never source MBASE).
if isfield(r,'equilibrium')&&isfield(r.equilibrium,'devices')&&isfield(r,'x_traj')
    d=r.equilibrium.devices; sg=find(strcmp({d.device_id},'SG31'));
    if numel(sg)==1
        a.sg_state_bounds=sg_bounds(r,d,sg); a.sg_state_bounds_status=a.sg_state_bounds.status;
        a.sg_actual_current_mva=sg_rating_audit(r,s,d,sg);
        a.sg_actual_current_mva_status=a.sg_actual_current_mva.status;
        a.per_device_bounds=per_device_bounds(r,s);
        if a.actual_close
            [a.close_state_continuity,a.sg_right_kcl_norm]=close_continuity(r,s,d,close,a.actual_reclose_time);
            a.close_state_continuity_status=a.close_state_continuity.status;
        end
    end
end
a.production_certified=false;
end

function z=guard_checks(g,sync)
z=struct('dV_pu',NaN,'df_pu',NaN,'dtheta_deg',NaN, ...
    'dV_max_pu',sync.dV_max_pu,'df_max_pu',sync.df_max_pu, ...
    'dtheta_max_deg',sync.dtheta_max_deg,'dV_pass',false,'df_pass',false, ...
    'dtheta_pass',false,'all_three_pass',false,'prospective',struct());
if isfield(g,'dV'), z.dV_pu=g.dV; end
if isfield(g,'df'), z.df_pu=g.df; end
if isfield(g,'dtheta'), z.dtheta_deg=g.dtheta; end
z.dV_pass=isfinite(z.dV_pu)&&z.dV_pu<=sync.dV_max_pu;
z.df_pass=isfinite(z.df_pu)&&z.df_pu<=sync.df_max_pu;
z.dtheta_pass=isfinite(z.dtheta_deg)&&z.dtheta_deg<=sync.dtheta_max_deg;
z.all_three_pass=z.dV_pass&&z.df_pass&&z.dtheta_pass;
if isfield(g,'prospective'), z.prospective=g.prospective; end
end

function z=selector_summary(t,name,indices)
z=struct('available',false,'status','UNKNOWN','ready_to_commit',false, ...
    'exact_all_nine_spectrum_ready',false,'candidate_count',0,'failure_id','');
if ~isfield(t,name), return; end
c=t.(name); z.available=true;
if isfield(c,'selection_status'), z.status=char(string(c.selection_status)); end
if isfield(c,'ready_to_commit'), z.ready_to_commit=logical(c.ready_to_commit); end
if isfield(c,'failure_id'), z.failure_id=char(string(c.failure_id)); end
if isfield(c,'configurations')
    z.candidate_count=numel(c.configurations);
    for k=1:numel(c.configurations)
        q=c.configurations(k);
        if ~isfield(q,'selected_gfm_indices')||~isequal(sort(q.selected_gfm_indices),sort(indices))|| ...
                ~logical(value(q,'ready_to_commit',false))||~logical(value(q,'feasible',false)), continue; end
        z.exact_all_nine_spectrum_ready=logical(value(q,'equilibrium_evaluated',false))&& ...
            logical(value(q,'sssa_evaluated',false))&&logical(value(q,'full_kcl',false))&& ...
            isfield(q,'physical_eigenvalues')&&~isempty(q.physical_eigenvalues)&& ...
            isfield(q,'eq_x0')&&~isempty(q.eq_x0)&&isfield(q,'eq_y0')&&~isempty(q.eq_y0);
        if z.exact_all_nine_spectrum_ready, break; end
    end
end
end

function z=sg_bounds(r,d,k)
p=d(k).provenance.params; off=sum([d(1:k-1).nx]); ix=off+(1:d(k).nx);
n=string(d(k).state_names); a=find(n=="Psv"); b=find(n=="Pm"); c=find(n=="Emag");
z=struct('status','UNKNOWN','Pmax_pu',p.Pmax_pu, ...
    'Emag_limits_pu',[p.Emag_min_pu p.Emag_max_pu]);
if numel(a)~=1||numel(b)~=1||numel(c)~=1||size(r.x_traj,1)<max(ix), return; end
x=r.x_traj(ix,:); psv=x(a,:); pm=x(b,:); E=x(c,:); tol=1e-10*max(1,p.Pmax_pu);
z.Psv_min_pu=min(psv);z.Psv_max_pu=max(psv);z.Pm_min_pu=min(pm);z.Pm_max_pu=max(pm);
z.Emag_min_pu=min(E);z.Emag_max_pu=max(E);
z.Psv_pass=all(isfinite(psv))&&all(psv>=-tol&psv<=p.Pmax_pu+tol);
z.Pm_pass=all(isfinite(pm))&&all(pm>=-tol&pm<=p.Pmax_pu+tol);
z.Emag_pass=all(isfinite(E))&&all(E>=p.Emag_min_pu-1e-10&E<=p.Emag_max_pu+1e-10);
if z.Psv_pass&&z.Pm_pass&&z.Emag_pass,z.status='PASS_ACCEPTED_STATES';else,z.status='FAIL_ACCEPTED_STATES';end
end

function z=sg_rating_audit(r,s,d,k)
p=d(k).provenance.params; z=struct('status','UNKNOWN', ...
    'rating_MVA',p.S_rated_MVA,'classification',p.classification, ...
    'rating_basis','PROJECT_DERIVED S_rated_MVA; never machine MBASE', ...
    'online_sample_count',0,'max_current_system_pu',NaN, ...
    'max_apparent_power_MVA',NaN,'current_pass',false,'MVA_pass',false);
if ~all(isfield(r,{'device_ids','device_current_magnitude','t','y_traj','event_context_history'})),return;end
ids=cellstr(string(r.device_ids)); j=find(strcmp(ids,'SG31'),1); if isempty(j),return;end
V=complex(r.y_traj(2*d(k).bus_position-1,:),r.y_traj(2*d(k).bus_position,:)); I=r.device_current_magnitude(j,:);
online=false(1,numel(r.t)); key=matlab.lang.makeValidName('SG31','ReplacementStyle','underscore');
for n=1:numel(r.t), ec=r.event_context_history{n}; online(n)=ec.hybrid_state.device_online.(key); end
ix=find(online&isfinite(I)&isfinite(abs(V))); if isempty(ix),return;end
base=s.case_data.mpc.baseMVA; pu=p.S_rated_MVA/base;
S=abs(V(ix).*I(ix))*base; Ilim=pu./max(abs(V(ix)),sqrt(eps));
z.online_sample_count=numel(ix);z.max_current_system_pu=max(I(ix));z.max_apparent_power_MVA=max(S);
z.current_pass=all(I(ix)<=Ilim+100*eps(max(1,max(Ilim))));
z.MVA_pass=all(S<=p.S_rated_MVA+100*eps(max(1,p.S_rated_MVA)));
if strcmp(p.classification,'PROJECT_DERIVED')&&z.current_pass&&z.MVA_pass,z.status='PASS_ACTUAL_ONLINE_SAMPLES';else,z.status='FAIL_ACTUAL_ONLINE_SAMPLES';end
end

function rows=per_device_bounds(r,s)
% Public accepted-trace envelopes. IBR DC state/current/energy detail is also
% gated at every accepted sample by ne39_transition_snapshot in the run itself.
rows=struct('resource_id',{},'kind',{},'P_min_MW',{},'P_max_MW',{}, ...
    'Q_min_MVAr',{},'Q_max_MVAr',{},'V_min_pu',{},'V_max_pu',{}, ...
    'f_min_Hz',{},'f_max_Hz',{},'I_converter_max_pu',{}, ...
    'Imax_declared_pu',{},'MVA_max',{},'rating_MVA',{}, ...
    'P_bound_pass',{},'Q_bound_pass',{},'current_bound_pass',{},'MVA_bound_pass',{});
if ~all(isfield(r,{'device_ids','device_P_MW','device_Q_MVAr','device_current_magnitude', ...
        'device_frequency_Hz','device_bus_ids','bus_ids','bus_voltage_magnitude'})),return;end
ids=cellstr(string(r.device_ids)); busids=r.bus_ids(:); Sbase=s.case_data.mpc.baseMVA;
for k=1:numel(ids)
    resource=find(strcmp({s.resources.resource_id},ids{k}),1); if isempty(resource),continue;end
    R=s.resources(resource); ix=strcmp(busids,R.bus_id); if nnz(ix)~=1,continue;end
    P=r.device_P_MW(k,:); Q=r.device_Q_MVAr(k,:); I=r.device_current_magnitude(k,:);
    V=r.bus_voltage_magnitude(ix,:); F=r.device_frequency_Hz(k,:);
    on=true(size(P)); if isfield(r,'device_online_history'),on=logical(r.device_online_history(k,:));end
    good=on&isfinite(P)&isfinite(Q)&isfinite(I)&isfinite(V);
    if ~any(good),continue;end
    limP=NaN;limQ=NaN;limI=NaN;rating=NaN;Iconv=NaN(size(I));
    if isfield(R,'limits')
        if isfield(R.limits,'Pmax_MW'),limP=R.limits.Pmax_MW;end
        if isfield(R.limits,'Qmax_MVAr'),limQ=R.limits.Qmax_MVAr;end
        if isfield(R.limits,'ImaxF'),limI=R.limits.ImaxF;end
    end
    if strcmpi(R.resource_type,'ibr')&&isfield(R,'ratings')&&isfield(R.ratings,'Mbase')
        rating=R.ratings.Mbase; Iconv=I*Sbase/rating;
    elseif strcmpi(R.resource_type,'sg')
        di=find(strcmp({r.equilibrium.devices.device_id},ids{k}),1);
        if ~isempty(di)&&isfield(r.equilibrium.devices(di).provenance,'params')
            pp=r.equilibrium.devices(di).provenance.params;rating=pp.S_rated_MVA;
        end
    end
    isSG=strcmpi(R.resource_type,'sg');
    if isSG,limI=rating/Sbase./max(V,sqrt(eps)); Iconv=I;end
    if isfinite(limI)&&~isSG, Ipass=all(Iconv(good)<=limI+100*eps(max(1,limI)));
    elseif isSG,Ipass=all(I(good)<=limI(good)+100*eps(max(1,max(limI(good)))));
    else,Ipass=NaN;end
    mva=abs(complex(P,Q)); Mpass=NaN;
    if isfinite(rating), Mpass=all(mva(good)<=rating+100*eps(max(1,rating)));end
    Pmin=0; Ppass=all(P(good)>=Pmin-1e-8);
    if isfinite(limP),Ppass=Ppass&&all(P(good)<=limP+1e-6);end
    Qpass=NaN;if isfinite(limQ),Qpass=all(abs(Q(good))<=limQ+1e-6);end
    row=struct('resource_id',ids{k},'kind',char(R.resource_type), ...
        'P_min_MW',min(P(good)),'P_max_MW',max(P(good)), ...
        'Q_min_MVAr',min(Q(good)),'Q_max_MVAr',max(Q(good)), ...
        'V_min_pu',min(V(good)),'V_max_pu',max(V(good)), ...
        'f_min_Hz',min(F(good&isfinite(F))),'f_max_Hz',max(F(good&isfinite(F))), ...
        'I_converter_max_pu',max(Iconv(good)),'Imax_declared_pu',limI, ...
        'MVA_max',max(mva(good)),'rating_MVA',rating, ...
        'P_bound_pass',Ppass,'Q_bound_pass',Qpass,'current_bound_pass',Ipass, ...
        'MVA_bound_pass',Mpass);
    rows(end+1)=row; %#ok<AGROW>
end
end

function [z,kcl]=close_continuity(r,s,d,e,tclose)
z=struct('status','UNKNOWN','transaction_id',e.transaction_id, ...
    'state_exact',false,'input_exact',false,'state_difference_inf',NaN, ...
    'input_difference_inf',NaN,'SG_online_left',false,'SG_online_right',false);
kcl=NaN;
if ~all(isfield(r,{'transaction_id','sample_side','t','x_traj','y_traj','u_history','event_context_history'})),return;end
hit=find(r.transaction_id==e.transaction_id&abs(r.t-tclose)<=1e-9);if isempty(hit),return;end
side=r.sample_side(hit); left=hit(strcmp(side,'left'));right=hit(strcmp(side,'right'));
if isempty(left)||isempty(right),return;end
il=left(1);ir=right(end);z.left_sample_index=il;z.right_sample_index=ir;
z.state_exact=isequal(r.x_traj(:,il),r.x_traj(:,ir));
z.input_exact=isequal(r.u_history(:,il),r.u_history(:,ir));
z.state_difference_inf=norm(r.x_traj(:,il)-r.x_traj(:,ir),inf);
z.input_difference_inf=norm(r.u_history(:,il)-r.u_history(:,ir),inf);
key=matlab.lang.makeValidName('SG31','ReplacementStyle','underscore');
ecl=r.event_context_history{il};ecr=r.event_context_history{ir};
z.SG_online_left=ecl.hybrid_state.device_online.(key);z.SG_online_right=ecr.hybrid_state.device_online.(key);
if z.state_exact&&z.input_exact&&~z.SG_online_left&&z.SG_online_right,z.status='PASS_NO_STATE_OR_INPUT_RESET';else,z.status='FAIL_CONTINUITY';end
try
    dae=stability.composite_dae(s.case_data,d,struct('load_model','cz_p_cz_q'));
    kcl=norm(dae.dae_g(tclose,r.x_traj(:,ir),r.y_traj(:,ir),dae.Ynet,r.u_history(:,ir),ecr),inf);
    z.right_kcl_norm=kcl;z.right_kcl_pass=isfinite(kcl)&&kcl<=1e-6;
catch me,z.right_kcl_failure_id=me.identifier;z.right_kcl_failure_reason=me.message;end
end

function print_summary(folder,a,elapsed)
fprintf('NE39_RECLOSE_PROBE folder=%s elapsed_s=%.6g production_certified=false\n',folder,elapsed);
fprintf('close_applied=%d status=%s actual_time=%.12g trip=%.12g offline_age=%.12g min_off=%g min_off_pass=%d\n', ...
    a.actual_close,a.reclose_status,a.actual_reclose_time,value(a,'actual_trip_time',NaN), ...
    value(a,'actual_offline_age_s',NaN),a.minimum_off_s,a.minimum_off_pass);
fprintf('guard dV=%g/%g pass=%d df=%g/%g pass=%d dtheta=%g/%gdeg pass=%d; voltage=%s nonvoltage=%s accepted=%s private=%s\n', ...
    a.guard_metric_checks.dV_pu,a.guard_metric_checks.dV_max_pu,a.guard_metric_checks.dV_pass, ...
    a.guard_metric_checks.df_pu,a.guard_metric_checks.df_max_pu,a.guard_metric_checks.df_pass, ...
    a.guard_metric_checks.dtheta_deg,a.guard_metric_checks.dtheta_max_deg,a.guard_metric_checks.dtheta_pass, ...
    a.strict_voltage_status,a.strict_nonvoltage_status,a.accepted_path_status,a.private_trial_status);
if isfield(a,'close_state_continuity')
 fprintf('continuity=%s x_exact=%d u_exact=%d online_left=%d right=%d right_KCL=%.9g\n', ...
  a.close_state_continuity_status,a.close_state_continuity.state_exact, ...
  a.close_state_continuity.input_exact,a.close_state_continuity.SG_online_left, ...
  a.close_state_continuity.SG_online_right,value(a,'sg_right_kcl_norm',NaN));
end
if isfield(a,'sg_state_bounds')
 z=a.sg_state_bounds;
 fprintf('SG_bounds=%s Psv=[%g,%g] Pm=[%g,%g] Emag=[%g,%g] Pmax=%g\n', ...
  a.sg_state_bounds_status,value(z,'Psv_min_pu',NaN),value(z,'Psv_max_pu',NaN), ...
  value(z,'Pm_min_pu',NaN),value(z,'Pm_max_pu',NaN), ...
  value(z,'Emag_min_pu',NaN),value(z,'Emag_max_pu',NaN),value(z,'Pmax_pu',NaN));
end
if isfield(a,'sg_actual_current_mva')
 z=a.sg_actual_current_mva;
 fprintf('SG_current_MVA=%s rating=%.9g MVA I_system_max=%.9g pu S_max=%.9g MVA basis=%s\n', ...
  a.sg_actual_current_mva_status,z.rating_MVA,z.max_current_system_pu,z.max_apparent_power_MVA,z.rating_basis);
end
if isfield(a,'per_device_bounds')
 for k=1:numel(a.per_device_bounds)
  z=a.per_device_bounds(k);
  fprintf('DEVICE %s P=[%g,%g]MW Q=[%g,%g]MVAr V=[%g,%g]pu f=[%g,%g]Hz Imax=%gpu P/Q/I/MVA=%s/%s/%s/%s\n', ...
   z.resource_id,z.P_min_MW,z.P_max_MW,z.Q_min_MVAr,z.Q_max_MVAr, ...
   z.V_min_pu,z.V_max_pu,z.f_min_Hz,z.f_max_Hz,z.Imax_declared_pu, ...
   pass_word(z.P_bound_pass),pass_word(z.Q_bound_pass),pass_word(z.current_bound_pass),pass_word(z.MVA_bound_pass));
 end
end
if isfield(a,'sg_off_selector'), fprintf('SELECTOR SG_OFF=%s exact9Spectrum=%d SG_ON=%s exact9Spectrum=%d\n', ...
 a.sg_off_selector.status,a.sg_off_selector.exact_all_nine_spectrum_ready, ...
 a.sg_on_selector.status,a.sg_on_selector.exact_all_nine_spectrum_ready);end
fprintf('raw=%s request=%s\n',fullfile(folder,'raw.mat'),fullfile(folder,'request.mat'));
end

function v=value(s,n,d)
v=d;if isstruct(s)&&isfield(s,n)&&~isempty(s.(n)),v=s.(n);end
end
function w=pass_word(v)
if islogical(v)||isnumeric(v),if isscalar(v)&&isfinite(v),if logical(v),w='PASS';else,w='FAIL';end;else,w='UNKNOWN';end
else,w='UNKNOWN';end
end