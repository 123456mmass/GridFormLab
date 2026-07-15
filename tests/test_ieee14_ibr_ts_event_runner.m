function tests=test_ieee14_ibr_ts_event_runner()
%TEST_IEEE14_IBR_TS_EVENT_RUNNER Falsification gates for mixed SG+IBR events.
% The previous draft only checked timestamps/file existence and accepted
% failed synchronism paths. These tests use independent canonical-TS, KCL,
% device-mode, state-partition, and phasor synchronism oracles.
tests=functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath')))); pf_init_paths();
s=cases.scenario_ieee14_1sg_4ibr();
[devices,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
eq=stability.mixed_equilibrium_solve(s.case_data,struct('devices',devices),struct('verbose',false));
tc.assertTrue(eq.converged,eq.failure_reason);
dae=stability.composite_dae(s.case_data,eq.devices,struct('load_model','cz_p_cz_q'));
tc.TestData.scenario=s; tc.TestData.eq=eq; tc.TestData.dae=dae;
end

function test_event_disabled_is_canonical_bit_identical(tc)
[a,b]=no_event_pair(tc.TestData,0.02,0.01);
tc.verifyEqual(b.t,a.t,'AbsTol',0);
tc.verifyEqual(b.x_traj,a.x_traj,'AbsTol',0);
tc.verifyEqual(b.y_traj,a.y_traj,'AbsTol',0);
end

function test_prefix_before_fault_is_canonical_bit_identical(tc)
r=event_run(tc.TestData,2:5,2,struct());
tc.assertTrue(r.converged,r.failure_reason);
o=base_opt(tc.TestData.eq,0.02,0.01);
[base,~]=stability.ts_simulate_composite(tc.TestData.scenario.case_data, ...
    tc.TestData.eq.devices,tc.TestData.eq.x0,tc.TestData.eq.y0,o);
left=find(abs(r.t-0.02)<1e-12 & strcmp(r.sample_side,'left'),1);
tc.assertNotEmpty(left);
tc.verifyEqual(r.x_traj(:,1:left),base.x_traj,'AbsTol',0);
tc.verifyEqual(r.y_traj(:,1:left),base.y_traj,'AbsTol',0);
end

function test_events_have_exact_left_right_and_finite_kcl(tc)
r=event_run(tc.TestData,2:5,2,struct());
tc.assertTrue(r.converged,r.failure_reason);
for te=[0.02 0.03 0.04 0.06]
    tc.verifyEqual(sum(abs(r.t-te)<1e-12),2, ...
        sprintf('Event %.3f must publish one left and one right sample.',te));
end
tc.verifyTrue(all([r.event_log.applied]));
tc.verifyTrue(all(isfinite([r.event_log.right_kcl_norm])));
tc.verifyLessThan(max([r.event_log.right_kcl_norm]),1e-6);
right_fault=find(abs(r.t-0.02)<1e-12 & strcmp(r.sample_side,'right'),1);
right_clear=find(abs(r.t-0.03)<1e-12 & strcmp(r.sample_side,'right'),1);
tc.verifyEqual(r.topology_history{right_fault},'fault');
tc.verifyEqual(r.topology_history{right_clear},'post');
end

function test_trip_commits_modes_partition_and_zero_sg_current(tc)
r=event_run(tc.TestData,2:5,2,struct());
tc.assertTrue(r.converged,r.failure_reason);
j=find(abs(r.t-0.04)<1e-12 & strcmp(r.sample_side,'right'),1);
tc.assertNotEmpty(j);
tc.verifyEqual(r.device_modes_history(:,j),{'sg';'GFM';'GFM';'GFM';'GFM'});
tc.verifyFalse(r.device_online_history(1,j));
tc.verifyEqual(r.device_current_magnitude(1,j),0,'AbsTol',0);
expected=stability.ts_dynamic_state_indices(tc.TestData.dae,r.event_context_history{j});
tc.verifyEqual(r.active_state_history{j},expected,'AbsTol',0);
for d=2:5
    off=tc.TestData.dae.device_offsets(d);
    inactive=off+(14:20);
    tc.verifyEqual(r.x_traj(inactive,j:end),repmat(r.x_traj(inactive,j),1,size(r.x_traj,2)-j+1),'AbsTol',0);
end
end

function test_one_gfm_configuration_fails_closed_and_rolls_back(tc)
r=event_run(tc.TestData,2,2,struct());
tc.verifyFalse(r.converged);
tc.verifyEqual(r.failure_id,'ts_simulate_ibr_hybrid:rightLimit');
trip=find(strcmp({r.event_log.type},'sg_trip'),1);
tc.assertNotEmpty(trip); tc.verifyFalse(r.event_log(trip).applied);
tc.verifyEqual(r.event_log(trip).right_kcl_norm,inf);
tc.verifyFalse(any(abs(r.t-0.04)<1e-12 & strcmp(r.sample_side,'right')));
end

function test_reclose_guard_uses_phasor_angle_and_pu_slip(tc)
g=stability.synchronism_guard(exp(1i*0.05),exp(1i*0.04),99,5e-4,0, ...
    struct('dV_max',0.05,'df_max',0.001,'dtheta_max',10));
tc.verifyTrue(g.passes);
tc.verifyEqual(g.df,5e-4,'AbsTol',0);
tc.verifyEqual(g.dtheta,rad2deg(0.01),'AbsTol',1e-12);
bad=stability.synchronism_guard(1,exp(-1i*0.3),0,0,0, ...
    struct('dV_max',1,'df_max',1,'dtheta_max',10));
tc.verifyFalse(bad.passes);
end

function test_reclose_requires_dwell_and_preserves_sg_state(tc)
over=struct('synchronism_overrides',struct('dV_max',10,'df_max',10,'dtheta_max',180), ...
    'delays_overrides',struct('T_sg_min_off_s',0,'dwell_s',0.01,'timeout_s',0.04));
r=event_run(tc.TestData,2:5,2,over);
tc.assertTrue(r.converged,r.failure_reason);
tc.verifyEqual(r.reclose_status,'SUCCESS');
tc.verifyEqual(r.actual_reclose_time,0.07,'AbsTol',1e-12);
left=find(abs(r.t-0.07)<1e-12 & ~strcmp(r.sample_side,'right'),1,'last');
right=find(abs(r.t-0.07)<1e-12 & strcmp(r.sample_side,'right'),1,'last');
tc.assertNotEmpty(left); tc.assertNotEmpty(right);
tc.verifyEqual(r.x_traj(1:6,right),r.x_traj(1:6,left),'AbsTol',0, ...
    'Reclose changes the breaker context and algebraic right limit, not SG state.');
tc.verifyTrue(r.device_online_history(1,right));
st=find(strcmp({r.status_log.stage},'sg_reclose'),1);
tc.assertNotEmpty(st);
tc.verifyEqual(r.status_log(st).n_sg_online,1);
tc.verifyEqual(r.status_log(st).gfm_indices,2:5);
end

function test_reclose_timeout_stays_offline(tc)
over=struct('synchronism_overrides',struct('dV_max',1e-12,'df_max',1e-12,'dtheta_max',1e-9), ...
    'delays_overrides',struct('T_sg_min_off_s',0,'dwell_s',0.01,'timeout_s',0.02));
r=event_run(tc.TestData,2:5,2,over);
tc.assertTrue(r.converged,r.failure_reason);
tc.verifyEqual(r.reclose_status,'SYNC_TIMEOUT');
tc.verifyTrue(isnan(r.actual_reclose_time));
tc.verifyFalse(r.device_online_history(1,end));
end

function test_schedule_validation_is_fail_closed(tc)
ev=event_spec(2:5,2); ev.fault_clear=ev.fault_on;
tc.verifyError(@() stability.ibr_event_schedule(tc.TestData.scenario.case_data, ...
    tc.TestData.eq.devices,ev,0.10,0.01),'stability:ibr_event_schedule:badOrdering');
end

function test_plots_use_audited_data_and_create_exactly_two_png(tc)
r=event_run(tc.TestData,2:5,2,struct()); tc.assertTrue(r.converged,r.failure_reason);
out=fullfile(tempdir,'ibr_ts_plot_gate'); if ~isfolder(out),mkdir(out);end
p=stability.plot_ibr_ts_results(r,struct('output_dir',out,'prefix','gate','visible',false));
tc.verifyTrue(isfile(p.freq_plot)); tc.verifyTrue(isfile(p.power_plot));
tc.verifyGreaterThan(dir(p.freq_plot).bytes,1000); tc.verifyGreaterThan(dir(p.power_plot).bytes,1000);
tc.verifyTrue(any(isfinite(r.device_frequency_Hz(2,:))));
tc.verifyTrue(any(isfinite(r.device_current_limit_sys(2,:))));
src=fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))),'+stability','plot_ibr_ts_results.m'));
tc.verifyFalse(contains(src,'yline(1.5'));
tc.verifyFalse(contains(src,'row = tb'));
end

function test_hybrid_runner_contains_no_duplicate_integrator(tc)
root=fileparts(fileparts(mfilename('fullpath')));
src=fileread(fullfile(root,'+stability','ts_simulate_ibr_hybrid.m'));
tc.verifyFalse(contains(src,'trapezoid_res'));
tc.verifyFalse(contains(src,'composite_newton'));
tc.verifyFalse(contains(src,'forward_fd'));
tc.verifyTrue(contains(src,'stability.ts_step_composite'));
for token={'fsolve','fmincon','lsqnonlin','pinv('}
    tc.verifyFalse(contains(lower(src),token{1}));
end
end

function [a,b]=no_event_pair(data,tend,dt)
o=base_opt(data.eq,tend,dt);
[a,~]=stability.ts_simulate_composite(data.scenario.case_data,data.eq.devices, ...
    data.eq.x0,data.eq.y0,o);
o.ibr_event_schedule=struct('enabled',false,'t_end',tend,'dt',dt,'events',[]);
[b,~]=stability.ts_simulate_ibr_hybrid(data.scenario.case_data,data.eq.devices, ...
    data.eq.x0,data.eq.y0,o);
end

function r=event_run(data,selected,ref,extra)
ev=event_spec(selected,ref);
sched=stability.ibr_event_schedule(data.scenario.case_data,data.eq.devices,ev,0.10,0.01);
o=base_opt(data.eq,0.10,0.01); o.ibr_event_schedule=sched;
names=fieldnames(extra); for k=1:numel(names),o.(names{k})=extra.(names{k});end
[r,~]=stability.ts_simulate_ibr_hybrid(data.scenario.case_data,data.eq.devices, ...
    data.eq.x0,data.eq.y0,o);
end

function ev=event_spec(selected,ref)
ev=struct('enabled',true,'fault_bus',4,'Zf',1i*0.1, ...
    'fault_on',0.02,'fault_clear',0.03,'sg_trip',0.04,'sg_on',0.06, ...
    'selected_gfm_indices',selected,'reference_resource_index',ref);
end

function o=base_opt(eq,tend,dt)
o=struct('t_end',tend,'dt',dt,'verbose',false,'load_model','cz_p_cz_q', ...
    'u_eq',eq.u_eq,'event_context',eq.equilibrium_context, ...
    'dynamic_state_indices',eq.dynamic_state_indices,'full_kcl',true);
end
