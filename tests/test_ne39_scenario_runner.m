function tests=test_ne39_scenario_runner()
%TEST_NE39_SCENARIO_RUNNER catalog/event execution/cache จาก production จริง.
tests=functiontests(localfunctions);
end

function setupOnce(tc)
p=path; tc.addTeardown(@()path(p)); pf_init_paths();
end

function test_catalog_valid_for_both_compositions(tc)
rows=stability.ne39_scenario_catalog();
for ns=[5 1]
    if ns==5, s=cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
    else, s=cases.scenario_ne39_1sg_9ibr(struct('study_capability',true)); end
    [dev,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
    for row=rows
        if isfield(row.events,'load_step_factor')
            tc.verifyEqual(row.events.load_step_factor,.2);
        end
        sched=stability.ibr_event_schedule(s.case_data,dev,row.events,row.horizon_s,.01);
        tc.verifyEqual(sched.enabled,row.events.enabled);
    end
    branch=s.case_data.mpc.branch;
    keep=~((branch(:,1)==16 & branch(:,2)==17) | ...
        (branch(:,1)==17 & branch(:,2)==16));
    G=graph(branch(keep,1),branch(keep,2),[],39);
    tc.verifyEqual(numel(unique(conncomp(G))),1);
end
end

function test_request_is_not_execution(tc)
rows=stability.ne39_scenario_catalog(); row=rows(strcmp({rows.id},'sg_cycle'));
r=struct('t',[0 .01],'converged',true,'event_log', ...
    struct('type','sg_reclose','applied',false));
m=stability.ne39_event_metrics(r,row,120);
tc.verifyFalse(m.defining_event_executed);
tc.verifyFalse(m.horizon_reached);
tc.verifyFalse(m.physical_switching_certified);
r.event_log.applied=true; r.actual_reclose_time=.01;
m=stability.ne39_event_metrics(r,row,120);
tc.verifyTrue(m.defining_event_executed);
tc.verifyFalse(m.physical_switching_certified);
end

function test_catalog_horizon_cannot_silently_skip_events(tc)
s=cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
[dev,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
e=struct('enabled',true,'event_profile','line_cycle','line_trip',.5, ...
    'restore_time',.4,'line_from_bus',16,'line_to_bus',17, ...
    'automatic_gfm_switching',false);
tc.verifyError(@()stability.ibr_event_schedule(s.case_data,dev,e,1,.01), ...
    'stability:ibr_event_schedule:badOrdering');
e=struct('enabled',true,'event_profile','load_only','load_step',2, ...
    'load_step_factor',.2,'automatic_gfm_switching',false);
tc.verifyError(@()stability.ibr_event_schedule(s.case_data,dev,e,1,.01), ...
    'stability:ibr_event_schedule:badOrdering');
end

function test_network_only_profiles_execute_without_mode_selection(tc)
s=cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
for profile={'load_only','line_cycle'}
    e=struct('enabled',true,'event_profile',profile{1}, ...
        'automatic_gfm_switching',false);
    if strcmp(profile{1},'load_only')
        e.load_step=.02; e.load_step_factor=.2; expected='load_step';
    else
        e.line_trip=.02; e.restore_time=.04;
        e.line_from_bus=16; e.line_to_bus=17; expected='topology_restore';
    end
    r=stability.run_hybrid_case(s,struct('t_end',.06,'dt',.005, ...
        'verbose',false,'ibr_events',e));
    tc.verifyTrue(r.converged);
    tc.verifyEqual(r.metadata.selector_not_required,'NETWORK_EVENT_NO_MODE_CHANGE_AUTHORISED');
    tc.verifyTrue(any(strcmp({r.event_log.type},expected) & [r.event_log.applied]));
end
end

function test_real_fault_cache_and_policy_invalidation(tc)
folder=tempname; mkdir(folder); tc.addTeardown(@()rmdir(folder,'s'));
a=run_ne39_scenario_suite(compositions="1sg_9ibr",scenarios="fault_bus16", ...
    policies="enhanced",dt=.005,t_end=.75,outdir=string(folder));
tc.verifyTrue(a.results.numerically_converged);
tc.verifyTrue(a.results.defining_event_executed);
tc.verifyFalse(a.results.cache_reused);
b=run_ne39_scenario_suite(compositions="1sg_9ibr",scenarios="fault_bus16", ...
    policies="enhanced",dt=.005,t_end=.75,outdir=string(folder));
tc.verifyTrue(b.results.cache_reused);
stored=load(b.results.artifact,'request','result');
tc.verifyTrue(isfield(stored.result,'ne39_decision_log'));
stored.request.options.dt=.1;
request=stored.request; result=stored.result; elapsed=0; %#ok<NASGU>
save(b.results.artifact,'request','result','elapsed','-v7.3');
d=run_ne39_scenario_suite(compositions="1sg_9ibr",scenarios="fault_bus16", ...
    policies="enhanced",dt=.005,t_end=.75,outdir=string(folder));
tc.verifyFalse(d.results.cache_reused);
tc.verifyEqual(d.results.cache_rejection,'REQUEST_OR_MODEL_CHANGED_OR_REUSE_DISABLED');
end
