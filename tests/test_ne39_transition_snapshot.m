function tests=test_ne39_transition_snapshot()
%TEST_NE39_TRANSITION_SNAPSHOT ตรวจฐานหน่วยและ negative constraints จาก model จริง.
tests=functiontests(localfunctions);
end

function setupOnce(tc)
p=path; tc.addTeardown(@()path(p)); pf_init_paths();
s=cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
[dev,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
eq=stability.mixed_equilibrium_solve(s.case_data,struct('devices',dev),struct('verbose',false));
tc.assertTrue(eq.converged,eq.failure_reason);
tc.TestData.s=s; tc.TestData.eq=eq;
tc.TestData.dae=stability.composite_dae(s.case_data,dev,struct('load_model','cz_p_cz_q'));
tc.TestData.bounds=struct('v_min',.9,'v_max',1.1,'f_min',59.5,'f_max',60.5);
end

function test_equilibrium_energy_and_converter_base(tc)
a=snapshot(tc,tc.TestData.eq.x0,tc.TestData.s.resources);
tc.verifyEqual(a.status,'PASS',a.reason);
tc.verifyFalse(a.trajectory_certified);
rows=a.records(startsWith({a.records.resource_id},'IBR'));
tc.verifyLessThan(max([rows.energy_rhs_error_pu]),1e-10);
tc.verifyLessThan(max([rows.ac_dc_power_error_pu]),1e-10);
tc.verifyGreaterThan(min([rows.stored_energy_MJ]),0);
end

function test_branch_plant_mismatch_is_unknown(tc)
eq=tc.TestData.eq; s=tc.TestData.s; d=tc.TestData.dae;
i=find(strcmp({s.resources.resource_type},'ibr'),1);
d.devices(i).provenance.branch_params.gfm.dc_source.Edc=2;
a=stability.ne39_transition_snapshot(0,eq.x0,eq.y0,eq.u_eq, ...
    eq.equilibrium_context,d,s.resources,s.case_data,tc.TestData.bounds);
tc.verifyEqual(a.status,'UNKNOWN');
tc.verifyEqual(a.reason,'GFL/GFM DC plant ไม่ตรงกัน');
end

function test_source_limit_failure(tc)
r=tc.TestData.s.resources; d=tc.TestData.dae;
i=find(strcmp({r.resource_type},'ibr'),1);
x=tc.TestData.eq.x0;
x(d.device_offsets(i)+17)=100;
a=snapshot(tc,x,r);
tc.verifyEqual(a.status,'FAIL');
tc.verifyTrue(contains(a.records(i).failure,'dc_current'));
tc.verifyTrue(contains(a.records(i).failure,'source_power'));
tc.verifyFalse(a.trajectory_certified);
end

function test_ac_limit_failure_and_unknown_capability(tc)
r=tc.TestData.s.resources;
i=find(strcmp({r.resource_type},'ibr'),1);
r(i).limits.ImaxF=.001;
a=snapshot(tc,tc.TestData.eq.x0,r);
tc.verifyEqual(a.status,'FAIL');
r(i).limits.Pmax_MW=NaN;
a=snapshot(tc,tc.TestData.eq.x0,r);
tc.verifyEqual(a.status,'UNKNOWN');
end

function test_transient_filter_energy_balance(tc)
x=tc.TestData.eq.x0; d=tc.TestData.dae;
i=find(strcmp({tc.TestData.s.resources.resource_type},'ibr'),1);
x(d.device_offsets(i)+8)=x(d.device_offsets(i)+8)+.01;
a=snapshot(tc,x,tc.TestData.s.resources);
rows=a.records(startsWith({a.records.resource_id},'IBR'));
tc.assertNotEmpty(rows,a.reason);
tc.verifyLessThan(max([rows.ac_dc_power_error_pu]),1e-10);
tc.verifyLessThan(max([rows.energy_rhs_error_pu]),1e-10);
end

function test_single_former_still_checks_constraints(tc)
[s,candidate,opt]=trial_inputs(tc);
eq=tc.TestData.eq; d=tc.TestData.dae;
x=eq.x0; i=find(strcmp({s.resources.resource_type},'ibr'),1);
x(d.device_offsets(i)+17)=100;
[ok,a]=stability.certify_ne39_transition(0,x,eq.y0,eq.u_eq, ...
    eq.equilibrium_context,d.Ynet,d,s.resources,s.case_data, ...
    tc.TestData.bounds,candidate,opt);
tc.verifyFalse(ok); tc.verifyEqual(a.status,'FAIL');
tc.verifyFalse(a.commit_authorized);
end

function test_private_trial_runs_and_does_not_mutate_inputs(tc)
[s,candidate,opt]=trial_inputs(tc);
eq=tc.TestData.eq; d=tc.TestData.dae;
x=eq.x0; y=eq.y0; u=eq.u_eq; ec=eq.equilibrium_context;
[ok,a]=stability.certify_ne39_transition(0,x,y,u,ec,d.Ynet,d,s.resources, ...
    s.case_data,tc.TestData.bounds,candidate,opt);
tc.verifyTrue(ok,a.reason);
tc.verifyEqual(numel(a.passes),2);
tc.verifyGreaterThan(a.passes{2}.steps,0);
tc.verifyEqual(a.refinement_scope,'ALL_COARSE_ACCEPTED_TIMES');
tc.verifyEqual(a.refinement_samples,a.passes{1}.steps);
tc.verifyEqual(x,eq.x0); tc.verifyEqual(y,eq.y0);
tc.verifyEqual(u,eq.u_eq); tc.verifyEqual(ec,eq.equilibrium_context);
tc.verifyFalse(a.commit_authorized);
end

function test_adaptive_private_trial_checks_every_coarse_time(tc)
[s,candidate,opt]=trial_inputs(tc); opt.timestep_strategy='adaptive';
eq=tc.TestData.eq; d=tc.TestData.dae;
[ok,a]=stability.certify_ne39_transition(0,eq.x0,eq.y0,eq.u_eq, ...
    eq.equilibrium_context,d.Ynet,d,s.resources,s.case_data, ...
    tc.TestData.bounds,candidate,opt);
tc.verifyTrue(ok,a.reason);
tc.verifyEqual(a.timestep_strategy,'adaptive');
tc.verifyEqual(a.refinement_samples,a.passes{1}.steps);
tc.verifyEqual(a.passes{2}.steps,2*a.passes{1}.steps);
tc.verifyEqual(a.passes{1}.t_reached,a.horizon_s,'AbsTol',1e-12);
tc.verifyLessThanOrEqual(a.refinement_error,opt.refinement_tol);
tc.verifyLessThanOrEqual(a.passes{1}.peak_local_refinement_error,opt.refinement_tol/20);
tc.verifyGreaterThan(a.passes{1}.min_dt,0);
tc.verifyLessThanOrEqual(a.passes{1}.max_dt,opt.dt);
tc.verifyGreaterThanOrEqual(a.passes{1}.step_attempts,3*a.passes{1}.steps);
tc.verifyFalse(a.commit_authorized);
end

function test_fixed_strategy_matches_default(tc)
[s,candidate,opt]=trial_inputs(tc); eq=tc.TestData.eq; d=tc.TestData.dae;
[ok,a]=stability.certify_ne39_transition(0,eq.x0,eq.y0,eq.u_eq, ...
    eq.equilibrium_context,d.Ynet,d,s.resources,s.case_data, ...
    tc.TestData.bounds,candidate,opt);
opt.timestep_strategy='fixed';
[ok2,b]=stability.certify_ne39_transition(0,eq.x0,eq.y0,eq.u_eq, ...
    eq.equilibrium_context,d.Ynet,d,s.resources,s.case_data, ...
    tc.TestData.bounds,candidate,opt);
tc.verifyTrue(ok,a.reason); tc.verifyTrue(ok2,b.reason);
tc.verifyEqual(a.passes,b.passes);
tc.verifyEqual(a.refinement_error,b.refinement_error);
end

function test_progress_does_not_change_trial_evidence(tc)
[s,candidate,opt]=trial_inputs(tc); opt.timestep_strategy='adaptive';
eq=tc.TestData.eq; d=tc.TestData.dae;
[ok,a]=stability.certify_ne39_transition(0,eq.x0,eq.y0,eq.u_eq, ...
    eq.equilibrium_context,d.Ynet,d,s.resources,s.case_data, ...
    tc.TestData.bounds,candidate,opt);
opt.progress_interval_s=60;
text=evalc('[ok2,b]=stability.certify_ne39_transition(0,eq.x0,eq.y0,eq.u_eq,eq.equilibrium_context,d.Ynet,d,s.resources,s.case_data,tc.TestData.bounds,candidate,opt);');
tc.verifyTrue(ok,a.reason); tc.verifyTrue(ok2,b.reason);
tc.verifyTrue(contains(text,'[NE39-private-trial]'));
tc.verifyEqual(a.passes,b.passes);
tc.verifyEqual(a.refinement_error,b.refinement_error);
tc.verifyEqual(a.refinement_samples,b.refinement_samples);
end

function test_adaptive_keeps_physical_and_budget_gates(tc)
[s,candidate,opt]=trial_inputs(tc); opt.timestep_strategy='adaptive';
eq=tc.TestData.eq; d=tc.TestData.dae; x=eq.x0;
i=find(strcmp({s.resources.resource_type},'ibr'),1); x(d.device_offsets(i)+17)=100;
[ok,a]=stability.certify_ne39_transition(0,x,eq.y0,eq.u_eq, ...
    eq.equilibrium_context,d.Ynet,d,s.resources,s.case_data, ...
    tc.TestData.bounds,candidate,opt);
tc.verifyFalse(ok); tc.verifyEqual(a.status,'FAIL');
opt.max_steps=1;
[ok,a]=stability.certify_ne39_transition(0,eq.x0,eq.y0,eq.u_eq, ...
    eq.equilibrium_context,d.Ynet,d,s.resources,s.case_data, ...
    tc.TestData.bounds,candidate,opt);
tc.verifyFalse(ok); tc.verifyEqual(a.status,'UNKNOWN');
tc.verifyEqual(a.reason,'TRIAL_BUDGET_EXHAUSTED');
end

function test_wrong_right_kcl_is_not_certified(tc)
[s,candidate,opt]=trial_inputs(tc);
eq=tc.TestData.eq; d=tc.TestData.dae; y=eq.y0;
y(1)=y(1)+.001;
[ok,a]=stability.certify_ne39_transition(0,eq.x0,y,eq.u_eq, ...
    eq.equilibrium_context,d.Ynet,d,s.resources,s.case_data, ...
    tc.TestData.bounds,candidate,opt);
tc.verifyFalse(ok); tc.verifyEqual(a.status,'UNKNOWN');
tc.verifyEqual(a.reason,'RIGHT_KCL_NOT_RESOLVED');
end

function test_nonfinite_kcl_is_not_certified(tc)
[s,candidate,opt]=trial_inputs(tc);
eq=tc.TestData.eq; d=tc.TestData.dae;
d.dae_g=@(varargin)nan(size(eq.y0));
[ok,a]=stability.certify_ne39_transition(0,eq.x0,eq.y0,eq.u_eq, ...
    eq.equilibrium_context,d.Ynet,d,s.resources,s.case_data, ...
    tc.TestData.bounds,candidate,opt);
tc.verifyFalse(ok); tc.verifyEqual(a.status,'UNKNOWN');
tc.verifyEqual(a.reason,'RIGHT_KCL_NOT_RESOLVED');
end

function test_bad_or_faster_claimed_spectrum_is_unknown(tc)
[s,candidate,opt]=trial_inputs(tc);
eq=tc.TestData.eq; d=tc.TestData.dae;
for spectrum={NaN,1,-1,[]}
    candidate.physical_eigenvalues=spectrum{1};
    [ok,a]=stability.certify_ne39_transition(0,eq.x0,eq.y0,eq.u_eq, ...
        eq.equilibrium_context,d.Ynet,d,s.resources,s.case_data, ...
        tc.TestData.bounds,candidate,opt);
    tc.verifyFalse(ok); tc.verifyEqual(a.status,'UNKNOWN');
    tc.verifyEqual(a.reason,'INVALID_OR_INCONSISTENT_PHYSICAL_SPECTRUM');
end
end

function test_budget_is_unknown_not_pass(tc)
[s,candidate,opt]=trial_inputs(tc); opt.max_steps=1;
eq=tc.TestData.eq; d=tc.TestData.dae;
[ok,a]=stability.certify_ne39_transition(0,eq.x0,eq.y0,eq.u_eq, ...
    eq.equilibrium_context,d.Ynet,d,s.resources,s.case_data, ...
    tc.TestData.bounds,candidate,opt);
tc.verifyFalse(ok); tc.verifyEqual(a.status,'UNKNOWN');
tc.verifyEqual(a.reason,'TRIAL_BUDGET_EXHAUSTED');
end

function [s,candidate,opt]=trial_inputs(tc)
s=tc.TestData.s;
% fixture ทดสอบ early gates/private stationary trial ไม่ใช่ authenticated production spectrum.
candidate=struct('ready_to_commit',true,'feasible',true,'omega',-100);
opt=struct('dt',.005,'max_steps',100,'rho',.05,'sync_dwell',.01, ...
    'newton_tol',1e-8,'max_iter',50,'fd_eps',3e-6,'kcl_tol',1e-6, ...
    'energy_tol_pu_s',1e-5,'refinement_tol',1e-5,'slip_limit_deg',180);
end

function a=snapshot(tc,x,resources)
eq=tc.TestData.eq; s=tc.TestData.s;
a=stability.ne39_transition_snapshot(0,x,eq.y0,eq.u_eq, ...
    eq.equilibrium_context,tc.TestData.dae,resources,s.case_data,tc.TestData.bounds);
end
