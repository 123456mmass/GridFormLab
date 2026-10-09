function tests=test_ne39_study_runtime()
%TEST_NE39_STUDY_RUNTIME ตรวจ opt-in บน public orchestrator/canonical adaptive.
tests=functiontests(localfunctions);
end

function setupOnce(tc)
p=path; tc.addTeardown(@()path(p)); pf_init_paths();
[op,analysis]=ne39_endpoint_design_options();
c=cases.ne39_chronology_design(cases.case_ne39_1sg_9ibr(),op);
tc.TestData.s=cases.scenario_ne39_tamu_mixed(c,struct('initial_modes',analysis.initial_modes));
end

function op=runtime_options()
% Network-only fixture: no mode transition is requested. Keep the production
% selector gate intact (nine-IBR automatic selection requires lazy search).
e=struct('enabled',true,'event_profile','fault_only','fault_bus',16, ...
    'fault_on',.001,'fault_clear',.002,'Zf',1i*1e6,'automatic_gfm_switching',false);
op=struct('t_end',.003,'dt',.0005,'verbose',false,'ibr_events',e, ...
    'stepper','adaptive','adaptive_strict_lte',true,'dt_min',.0025/4096, ...
    'dt_max',.025,'dt_max_armed',.01,'rannacher_n',0, ...
    'atol_x',2e-8,'rtol_x',1e-7,'atol_y',2e-8,'rtol_y',1e-7, ...
    'online_rate_measurement',true);
end

function test_study_adds_midpoint_not_new_trajectory(tc)
s=tc.TestData.s; op=runtime_options();
a=stability.run_hybrid_case(s,op); tc.assertTrue(a.converged,a.metadata.error);
op.ne39_assessment_policy='observe_voltage';
b=stability.run_hybrid_case(s,op); tc.assertTrue(b.converged,b.failure_reason);
tc.verifyFalse(isfield(a,'ne39_assessment'));
for k=1:numel(a.t)
    hit=find(abs(b.t-a.t(k))<1e-14 & strcmp(b.sample_side,a.sample_side{k}));
    tc.assertEqual(numel(hit),1);
    tc.verifyEqual(b.x_traj(:,hit),a.x_traj(:,k),'AbsTol',0);
    tc.verifyEqual(b.y_traj(:,hit),a.y_traj(:,k),'AbsTol',0);
end
tc.verifyEqual(b.lte_history,a.lte_history,'AbsTol',0);
tc.verifyEqual(b.online_rate_log,a.online_rate_log);
tc.verifyEqual(b.online_rate_series,a.online_rate_series);
tc.verifyEqual(b.online_rate_jumps,a.online_rate_jumps);
tc.verifyTrue(all(diff(b.t)>=0));
tc.verifyEqual(sum(strcmp(b.sample_side,'left')),sum(strcmp(a.sample_side,'left')));
tc.verifyEqual(sum(strcmp(b.sample_side,'right')),sum(strcmp(a.sample_side,'right')));
tc.verifyEqual(b.ne39_assessment.samples_checked,numel(b.t));
tc.verifyFalse(b.ne39_assessment.failed); tc.verifyFalse(b.ne39_assessment.production_certified);
tc.verifyLessThanOrEqual(b.ne39_assessment.energy_error_pu_s,1e-6);
% Audit must not treat a fabricated summary time / sg_on request as a close.
catalog=stability.ne39_scenario_catalog(); row=catalog(strcmp({catalog.id},'chronology'));
request=struct('scenario',s,'options',struct('t_end',160, ...
    'ibr_events',row.events,'ne39_assessment_policy','observe_voltage'));
result=b; result.actual_reclose_time=0; result.reclose_status='SUCCESS';
folder=tempname; mkdir(folder); tc.addTeardown(@()rmdir(folder,'s'));
raw=fullfile(folder,'raw.mat'); save(raw,'request','result');
audit=audit_ne39_voltage_chronology(raw);
tc.verifyFalse(audit.actual_reclose_applied);
tc.verifyFalse(audit.horizon_reached); tc.verifyEqual(audit.study_status,'STUDY_INCOMPLETE');
tc.verifyFalse(audit.production_certified);
end

function test_study_rejects_actual_ac_capability_failure(tc)
s=tc.TestData.s; op=runtime_options(); op.ne39_assessment_policy='observe_voltage';
k=find(strcmp({s.resources.resource_type},'ibr'),1); s.resources(k).limits.ImaxF=.001;
a=stability.run_hybrid_case(s,op); tc.verifyFalse(a.converged);
tc.assertTrue(isfield(a,'ne39_assessment'));
tc.verifyTrue(a.ne39_assessment.failed);
tc.verifyTrue(contains(a.ne39_assessment.failed_snapshot.records(k).failure,'ac_current'));
tc.verifyEqual(a.t,0);
end

function test_invalid_study_policy_fails_closed(tc)
op=runtime_options(); op.ne39_assessment_policy='ignore_all';
a=stability.run_hybrid_case(tc.TestData.s,op); tc.verifyFalse(a.converged);
tc.verifyEqual(a.failure_id,'ts_simulate_ibr_hybrid:ne39AssessmentPolicy');
end
