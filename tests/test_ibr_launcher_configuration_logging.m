function tests=test_ibr_launcher_configuration_logging()
%TEST_IBR_LAUNCHER_CONFIGURATION_LOGGING Independent configuration/log gates.
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath')))); pf_init_paths();
end

function test_zero_gfm_normal_configuration(tc)
s=cases.scenario_ieee14_1sg_4ibr();
[c,log]=stability.ibr_configure_scenario(s,struct('initial_gfm_count',0));
tc.verifyEqual(c.config.mode,{'synchronous';'gfl';'gfl';'gfl';'gfl'});
tc.verifyEqual(log.selected_gfm_indices,[]);
tc.verifyEqual(log.source,'explicit_count_zero');
tc.verifyTrue(log.ready);
end

function test_explicit_indices_are_exact_not_first_fallback(tc)
s=cases.scenario_ieee14_1sg_4ibr();
[c,log]=stability.ibr_configure_scenario(s,struct( ...
    'initial_gfm_count',2,'initial_gfm_indices',[3 5], ...
    'initial_reference_resource_index',5));
tc.verifyEqual(c.config.mode,{'synchronous';'gfl';'gfm';'gfl';'gfm'});
tc.verifyEqual(log.selected_gfm_indices,[3 5]);
tc.verifyEqual(log.reference_resource_index,5);
tc.verifyEqual(c.config.selected_gfm_indices,[3 5]);
end

function test_count_only_uses_full_selector_and_fails_closed_before_sssa(tc)
s=cases.scenario_ieee14_1sg_4ibr();
[~,log]=stability.ibr_configure_scenario(s,struct('initial_gfm_count',1));
tc.verifyTrue(log.selector_evaluated);
tc.verifyGreaterThan(log.candidate_count,0);
tc.verifyGreaterThan(log.equilibrium_evaluations,0);
tc.verifyEqual(log.sssa_evaluations,0, ...
    ['Every one-GFM candidate is rejected by the frozen SCR gate or an ' ...
     'equilibrium device limit before SSSA; the selector must not bypass ' ...
     'those earlier fail-closed gates merely to populate an SSSA count.']);
tc.verifyFalse(log.ready);
tc.verifyEqual(log.failure_id,'stability:ibr_config_selector:noFeasibleCandidate');
end

function test_count_index_mismatch_rejected(tc)
s=cases.scenario_ieee14_1sg_4ibr();
tc.verifyError(@() stability.ibr_configure_scenario(s,struct( ...
    'initial_gfm_count',1,'initial_gfm_indices',[2 3])), ...
    'stability:ibr_configure_scenario:countMismatch');
end

function test_post_trip_selector_evaluates_sg_breaker_open(tc)
s=cases.scenario_ieee14_1sg_4ibr();
q=stability.ibr_config_selector(s.resources,struct('case_data',s.case_data),s, ...
    struct('n_gfm_required',4,'case_data',s.case_data, ...
    'dispatch',s.case_data.dispatch_contract.post_trip.post_trip_Pg_MW));
tc.assertNotEmpty(q.configurations);
c=q.configurations(1);
tc.assertTrue(c.equilibrium_evaluated);
key=matlab.lang.makeValidName('SG1','ReplacementStyle','underscore');
tc.verifyFalse(c.eq_context.hybrid_state.device_online.(key));
tc.verifyEqual(c.eq_context.hybrid_state.device_modes.(key),'breaker_open');
end

function test_index_status_uses_assembled_ranges(tc)
s=cases.scenario_ieee14_1sg_4ibr();
[d,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
eq=stability.mixed_equilibrium_solve(s.case_data,struct('devices',d),struct('verbose',false));
tc.assertTrue(eq.converged,eq.failure_reason);
dae=struct('devices',eq.devices,'device_offsets',[0;6;26;46;66]);
q=stability.ibr_status_snapshot('oracle',0,dae,eq.equilibrium_context, ...
    eq.dynamic_state_indices,eq.physical_kcl_norm);
tc.verifyEqual(q.n_sg_online,1); tc.verifyEqual(q.n_gfm,0); tc.verifyEqual(q.n_gfl,4);
tc.verifyEqual([q.device_entries.state_start],[1 7 27 47 67]);
tc.verifyEqual([q.device_entries.state_end],[6 26 46 66 86]);
tc.verifyEqual(q.total_state_count,86);
end

function test_solve_case_ibr_logs_trip_counts_and_work(tc)
ev=struct('enabled',true,'fault_bus',4,'Zf',1i*.1, ...
    'fault_on',.02,'fault_clear',.03,'sg_trip',.04,'sg_on',.06, ...
    'selected_gfm_indices',2:5,'reference_resource_index',2);
run_opt=struct('t_end',.1,'dt',.01,'plot_results',false,'ibr_events',ev);
txt=evalc("r=solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',run_opt);");
tc.assertTrue(r.converged);
tc.verifyEqual(r.status_log(1).n_gfl,4);
trip=find(strcmp({r.status_log.stage},'sg_trip'),1);
tc.assertNotEmpty(trip);
tc.verifyEqual(r.status_log(trip).n_sg_online,0);
tc.verifyEqual(r.status_log(trip).gfm_indices,2:5);
tc.verifyEqual(r.execution_summary.ts_step_attempts,10);
tc.verifyTrue(contains(txt,'RESOURCE/STATE INDEX STATUS'));
tc.verifyTrue(contains(txt,'PF stage invocations'));
tc.verifyTrue(contains(txt,'01 SG1'));
end

function test_sg_identity_never_falls_back_to_first_device(tc)
s=cases.scenario_ieee14_1sg_4ibr();
[d,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
for k=1:numel(d), d(k).capabilities.resource_type='ibr'; end
ev=struct('enabled',true,'fault_bus',4,'Zf',1i*.1,'fault_on',.02, ...
    'fault_clear',.03,'sg_trip',.04,'sg_on',.06, ...
    'selected_gfm_indices',2:5,'reference_resource_index',2);
tc.verifyError(@() stability.ibr_event_schedule(s.case_data,d,ev,.1,.01), ...
    'stability:ibr_event_schedule:ambiguousSg');
end

function test_launcher_source_has_case_driven_ibr_controls(tc)
src=fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))),'solve_case.m'));
for token={'Initial GFM count','Fault bus (valid external IDs','fault_on (s)', ...
        'Post-trip GFM indices','stability.run_hybrid_case'}
    tc.verifyTrue(contains(src,token{1}));
end
tc.verifyFalse(contains(src,'W=inv(V)'));
end
