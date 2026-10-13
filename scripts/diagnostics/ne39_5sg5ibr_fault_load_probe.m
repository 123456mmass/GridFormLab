function folder = ne39_5sg5ibr_fault_load_probe()
%NE39_5SG5IBR_FAULT_LOAD_PROBE 5 SG + 5 IBR fault + load-step diagnostic.
% Explicitly called only. Builds the NE39 5SG+5IBR case (SG buses 31/32/35/38/39,
% IBR buses 30/33/34/36/37) with the opt-in study capability sizing, and runs a
% chronology with NO SG breaker events at all: because five machines stay
% online throughout, the synchronous fleet remains the voltage/frequency
% reference and there is no SG trip, no SG reclose, and no hand-back question.
% The fault is the frozen catalog row's bus-16 150 ms shunt
% (Zf = j0.1) applied at 60 s, cleared at 60.15 s, followed by a global +20%
% load step at 100 s, horizon 160 s -- event instants aligned with the
% delivered 160-s study so the fault windows compare directly.
%
% The five SGs use the two-state classical model x=[delta, omega] with inputs
% [Pm, Emag]; the five IBR converters use the 17-state Dual-mode-IBR plant.
% Two converters run GFM and three GFL by a deterministic design rule (the two
% largest scheduled active powers, ties by lower bus -- PROJECT_DERIVED, stated
% in the report): with five machines as reference, distinct GFM/GFL behavior in
% one chronology is visible without any mode change event.
%
% Initial modes are fixed at t=0 and neither the fault nor the load step
% changes them (automatic_gfm_switching=false): the run is a ride-through and
% absorption study under intact SG reference, NOT a mode-transfer study. The
% support supervisor is a no-op here BY CONFIG (automatic_support_supervision
% =false): no SG is ever offline, so there is nothing to support, and the run
% stays in the "network event, no mode change" path that builds no selector
% table. Severity/policy evidence is still recorded through
% online_rate_measurement + ne39_rate_policy for the report.
%
% Uses public stability.run_hybrid_case -> canonical
% stability.ts_simulate_ibr_hybrid. No fabricated certificate, private replay,
% state reset, synchronism/delay override, or gate relaxation is used. Always
% production_certified=false.
%
% Usage (after project paths are available):
%   folder = ne39_5sg5ibr_fault_load_probe();

root = pf_init_paths();
folder = unique_folder(root);
mkdir(folder);
request = struct('created_at',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss.SSS')), ...
    'artifact_folder',folder, ...
    'classification','PROJECT_DERIVED_FAULT_LOAD_NO_SG_TRIP_STUDY', ...
    'production_certified',false,'hardware_certified',false, ...
    'full_chronology',true);
result = struct('converged',false,'failure_id','','failure_reason','');
run_error = struct('occurred',false,'failure_id','','message','','stack',[]);
elapsed = 0;

try
    scenario = cases.scenario_ne39_5sg_5ibr(struct('study_capability',true, ...
        'initial_modes',initial_mode_overrides(cases.case_ne39_5sg_5ibr())));
    ibr = find(strcmpi({scenario.resources.resource_type},'ibr'));
    sg = find(strcmpi({scenario.resources.resource_type},'sg'));
    if numel(ibr)~=5 || numel(sg)~=5 || numel(scenario.resources)~=10 || ...
            any(strcmpi(string({scenario.resources.model_id}),'sg_classical_reclose'))
        error('ne39_5sg5ibr_fault_load_probe:composition', ...
            'Expected five two-state classical SGs and five Dual-mode-IBR converters.');
    end
    t_fault = 60; t_fault_clear = 60.15; t_load_step = 100; t_end = 160.0;
    % No sg_id, no sg_trip/sg_on, no selected_gfm_indices, no reference index:
    % the profile arms fault + load step only, has_sg_cycle stays false, and the
    % schedule never asks for an SG identity (with five SGs the ambiguousSg
    % default would refuse one).
    events = struct('enabled',true,'event_profile','fault_load_step', ...
        'fault_bus',16,'Zf',1i*0.1,'fault_on',t_fault, ...
        'fault_clear',t_fault_clear,'load_step',t_load_step, ...
        'load_step_factor',0.2,'automatic_gfm_switching',false);
    options = struct('t_end',t_end,'dt',0.001,'verbose',false, ...
        'ibr_events',events, ...
        'stepper','adaptive','adaptive_strict_lte',true, ...
        'dt_min',0.0025/4096,'dt_max',0.025,'dt_max_armed',0.01, ...
        'atol_x',2e-8,'rtol_x',1e-7,'atol_y',2e-8,'rtol_y',1e-7, ...
        'rannacher_n',0,'reject_limit',16, ...
        'jacobian_reuse',true, ...
        'healthy_pf_V',scenario.case_data.bus_data(:,3).', ...
        'healthy_pf_bus_ids',scenario.case_data.bus_data(:,1).', ...
        'online_rate_measurement',true, ...
        'automatic_support_supervision',false, ...
        'ne39_rate_policy',true,'ne39_weighted_severity',true, ...
        'progress_every',5,'progress_file',fullfile(folder,'progress.log'));
    % automatic_support_supervision=false keeps the run in the "network
    % event, no mode change" path (no selector table is built: with five
    % GFM-capable IBRs the exhaustive enumeration exceeds N_exhaustive_max=4,
    % and lazy search is a separate mission). Nothing here can ever change a
    % mode -- automatic_gfm_switching=false and no SG breaker event -- so
    % the supervisor has nothing to govern; severity/policy evidence is
    % still recorded through online_rate_measurement + ne39_rate_policy.
    request.case_data=scenario.case_data; request.scenario=scenario;
    request.events=events; request.options=options;
    request.initial_mode_resource_ids=initial_gfm_resource_ids(scenario);
    request.declared_synchronism=scenario.case_data.synchronism;
    save(fullfile(folder,'request.mat'),'request','-v7.3');

    fprintf('[NE39-5sg5ibr-probe] start folder=%s fault=%.3g-%.3g step=%.3g horizon=%.3g\n', ...
        folder,t_fault,t_fault_clear,t_load_step,t_end);
    timer=tic; %#ok<NASGU>
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
    result.full_chronology=true;
    result.classification=request.classification;
    save(fullfile(folder,'raw.mat'),'request','result','elapsed','run_error','-v7.3');
    % Presentation cache, written HERE because the result is still in memory.
    try
        cache_note=ne39_replay_cache_write(folder,result,request,elapsed);
        fprintf('[NE39-5sg5ibr-probe] replay cache %s\n',cache_note);
    catch cache_error
        fprintf(['[NE39-5sg5ibr-probe] replay cache skipped (%s); ' ...
            'raw.mat is unaffected\n'],cache_error.message);
    end
    try
        audit=summarize_result(result,scenario,options);
    catch audit_error
        audit=struct('status','POSTPROCESSING_FAILED','production_certified',false, ...
            'failure_id',audit_error.identifier,'failure_reason',audit_error.message, ...
            'accepted_path_status','RAW_RESULT_PRESERVED');
    end
    audit.run_error=run_error;
    save(fullfile(folder,'audit.mat'),'audit','-v7.3');
    try
        print_summary(folder,audit,elapsed);
    catch summary_error
        fprintf('[NE39-5sg5ibr-probe] summary printing failed: %s: %s; raw preserved in %s\n', ...
            summary_error.identifier,summary_error.message,fullfile(folder,'raw.mat'));
    end
catch me
    run_error=struct('occurred',true,'failure_id',me.identifier, ...
        'message',me.message,'stack',me.stack);
    request.setup_failure_id=me.identifier; request.setup_failure_reason=me.message;
    audit=struct('status','SETUP_FAILED','production_certified',false, ...
        'failure_id',me.identifier,'failure_reason',me.message);
    raw_file=fullfile(folder,'raw.mat');
    if isfile(raw_file)
        % A raw public-run result is immutable even if later audit/report work fails.
        save(fullfile(folder,'audit_failure.mat'),'audit','run_error','-v7.3');
        fprintf('[NE39-5sg5ibr-probe] post-run failure; preserved raw=%s id=%s reason=%s\n', ...
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

function om = initial_mode_overrides(case_data)
% Deterministic design rule (PROJECT_DERIVED): the TWO largest scheduled
% active powers run GFM, the remaining three GFL; ties break to the lower bus.
% Stated in the report, never deciding anything at run time: initial modes are
% fixed at t=0 and no event changes them.
q=case_data.ibr_scheduled;
entries=arrayfun(@(r) r.bus, q);
Pm=arrayfun(@(r) r.P_MW, q);
[~,order]=sortrows([(-Pm(:)) entries(:)]);   % descending P, then ascending bus
gfm_buses=entries(order(1:min(2,numel(order))));   % BUS numbers, not indices
om=struct('device_id',{},'mode',{});
for k=1:numel(entries)
    if ismember(entries(k),gfm_buses), mode='gfm'; else, mode='gfl'; end
    om(end+1)=struct('device_id',sprintfc('IBR%d',entries(k)),'mode',mode); %#ok<AGROW>
end
end

function ids = initial_gfm_resource_ids(scenario)
ids={};
for k=1:numel(scenario.resources)
    if strcmpi(string(scenario.resources(k).resource_type),'ibr') && ...
            strcmpi(string(scenario.resources(k).initial_mode),'gfm')
        ids{end+1}=char(string(scenario.resources(k).resource_id)); %#ok<AGROW>
    end
end
end

function folder=unique_folder(root)
base=['ne39_5sg5ibr_fault_load_study_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))];
folder=fullfile(root,'output','diagnostics',base); k=0;
while isfolder(folder), k=k+1; folder=fullfile(root,'output','diagnostics',sprintf('%s_%02d',base,k)); end
end

function a=summarize_result(r,s,op)
a=struct('status','NO_EVALUATED_EVIDENCE','production_certified',false, ...
    'hardware_certified',false,'full_chronology',true, ...
    'strict_voltage_status','UNKNOWN','strict_nonvoltage_status','UNKNOWN', ...
    'accepted_path_status','UNKNOWN');
if isfield(r,'converged'), a.run_converged=logical(r.converged); end
if isfield(r,'failure_id'), a.failure_id=char(string(r.failure_id)); end
if isfield(r,'failure_reason'), a.failure_reason=char(string(r.failure_reason)); end
if isfield(r,'t'), a.accepted_sample_count=numel(r.t); else, a.accepted_sample_count=0; end
for f={'accepted_steps','step_attempts'}
    if isfield(r,f{1}), a.(f{1})=r.(f{1}); end
end
% Events: fault_on/fault_clear/load_step applied evidence. There is no SG
% breaker event in this chronology by design.
a.sg_breaker_events_armed=false;
if isfield(r,'event_log') && isstruct(r.event_log)
    types={r.event_log.type};
    a.event_types_applied=types([r.event_log.applied]);
    a.fault_on_applied=any(strcmp(types,'fault_on') & [r.event_log.applied]);
    a.fault_clear_applied=any(strcmp(types,'fault_clear') & [r.event_log.applied]);
    a.load_step_applied=any(strcmp(types,'load_step') & [r.event_log.applied]);
end
if isfield(r,'sched')&&isfield(r.sched,'has_load_step'), a.has_load_step=r.sched.has_load_step; end
if isfield(r,'sched')&&isfield(r.sched,'load_step_factor'), a.load_step_factor=r.sched.load_step_factor; end

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
% All five SGs online throughout: read from the device online history; any
% offline sample is the failure of the no-trip claim the chronology declares.
if isfield(r,'device_online_history')&&isfield(r,'device_ids')
    ids=cellstr(string(r.device_ids));
    online_all=true;
    sg_summary=repmat(struct('resource_id','','offline_samples',NaN,'online_samples',NaN),0,1);
    for k=1:numel(ids)
        if ~ismember(ids{k},{'SG31','SG32','SG35','SG38','SG39'}), continue; end
        h=logical(r.device_online_history(k,:));
        sg_summary(end+1)=struct('resource_id',ids{k}, ...
            'offline_samples',nnz(~h),'online_samples',nnz(h));
        if ~all(h), online_all=false; end
    end
    a.sg_online_summary=sg_summary;
    a.all_five_sg_online_every_sample=online_all;
    a.sg_online_status=ternary(online_all,'PASS_ALL_ONLINE','FAIL_OFFLINE_SAMPLES');
end
% Per-device accepted-trace envelopes (public, unchanged from the reclose
% probe): bounds against declared limits on every good accepted sample.
a.per_device_bounds=per_device_bounds(r,s);
a.production_certified=false;
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

function print_summary(folder,a,elapsed)
fprintf('NE39_5SG5IBR_FAULT_LOAD folder=%s elapsed_s=%.6g production_certified=false\n',folder,elapsed);
fprintf('converged=%d horizon=%s samples=%d voltage=%s nonvoltage=%s\n', ...
    value(a,'run_converged',false),a.accepted_path_status, ...
    value(a,'accepted_sample_count',0),a.strict_voltage_status,a.strict_nonvoltage_status);
fprintf('fault_on=%d fault_clear=%d load_step=%d step_factor=%g fiveSG=%s\n', ...
    value(a,'fault_on_applied',false),value(a,'fault_clear_applied',false), ...
    value(a,'load_step_applied',false),value(a,'load_step_factor',NaN), ...
    value(a,'sg_online_status','UNKNOWN'));
if isfield(a,'per_device_bounds')
 for k=1:numel(a.per_device_bounds)
  z=a.per_device_bounds(k);
  fprintf('DEVICE %s P=[%g,%g]MW Q=[%g,%g]MVAr V=[%g,%g]pu f=[%g,%g]Hz Imax=%gpu P/Q/I/MVA=%s/%s/%s/%s\n', ...
   z.resource_id,z.P_min_MW,z.P_max_MW,z.Q_min_MVAr,z.Q_max_MVAr, ...
   z.V_min_pu,z.V_max_pu,z.f_min_Hz,z.f_max_Hz,z.Imax_declared_pu, ...
   pass_word(z.P_bound_pass),pass_word(z.Q_bound_pass),pass_word(z.current_bound_pass),pass_word(z.MVA_bound_pass));
 end
end
fprintf('raw=%s request=%s\n',fullfile(folder,'raw.mat'),fullfile(folder,'request.mat'));
end

function v=value(s,n,d)
v=d;if isstruct(s)&&isfield(s,n)&&~isempty(s.(n)),v=s.(n);end
end
function w=pass_word(v)
if islogical(v)||isnumeric(v),if isscalar(v)&&isfinite(v),if logical(v),w='PASS';else,w='FAIL';end;else,w='UNKNOWN';end
else,w='UNKNOWN';end
end
function out=ternary(c,a,b)
if c, out=a; else, out=b; end
end
