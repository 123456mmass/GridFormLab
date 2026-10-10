function tests=test_ne39_scenario_audit()
%TEST_NE39_SCENARIO_AUDIT ตรวจ raw evidence และปฏิเสธ context ที่หายไป.
tests=functiontests(localfunctions);
end

function setupOnce(tc)
p=path; tc.addTeardown(@()path(p)); pf_init_paths();
s=cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
[dev,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
eq=stability.mixed_equilibrium_solve(s.case_data,struct('devices',dev),struct('verbose',false));
tc.assertTrue(eq.converged,eq.failure_reason);
tc.TestData.request=struct('model_sha256','fixture_current_checkout', ...
    'case_data',s.case_data,'resources',s.resources,'options',struct());
tc.TestData.result=struct('t',0,'equilibrium',eq,'x_traj',eq.x0, ...
    'y_traj',eq.y0,'u_history',eq.u_eq);
end

function test_stationary_snapshot_not_transition_certificate(tc)
a=run_audit(tc,tc.TestData.request,tc.TestData.result);
tc.verifyEqual(a.status,'ACCEPTED_SNAPSHOTS_PASS_NOT_TRANSITION_CERTIFIED');
tc.verifyEqual(a.samples_checked,1);
tc.verifyFalse(a.physical_switching_certified);
tc.verifyLessThan(a.max_energy_rhs_error_pu,1e-10);
end

function test_first_failure_keeps_device_evidence(tc)
r=tc.TestData.result;
i=find(strcmp({r.equilibrium.devices.device_type},'ibr_eecon49_dual'),1);
off=sum([r.equilibrium.devices(1:i-1).nx]);
r.x_traj(off+17)=100;
a=run_audit(tc,tc.TestData.request,r);
tc.verifyEqual(a.status,'SNAPSHOT_CONSTRAINT_FAILURE');
tc.verifyEqual(a.first_failure_time,0);
tc.verifyEqual(a.snapshot_failures,1);
tc.verifyNotEmpty(a.first_failure_records);
tc.verifyEqual(a.first_failure_records(1).resource_id,r.equilibrium.devices(i).device_id);
end

function test_missing_event_context_cannot_use_initial_context(tc)
q=tc.TestData.request; q.options.ibr_events=struct('enabled',true);
a=run_audit(tc,q,tc.TestData.result);
tc.verifyEqual(a.status,'MISSING_EVENT_CONTEXT');
tc.verifyEqual(a.samples_checked,0);
r=tc.TestData.result; r.event_context_history={r.equilibrium.equilibrium_context};
a=run_audit(tc,q,r);
tc.verifyEqual(a.samples_checked,1);
end

function test_bad_raw_dimensions_and_context_are_not_evidence(tc)
r=tc.TestData.result; r.u_history=[];
a=run_audit(tc,tc.TestData.request,r);
tc.verifyEqual(a.status,'INVALID_RAW_DIMENSIONS_OR_TIME');
r=tc.TestData.result; r.event_context_history={[]};
a=run_audit(tc,tc.TestData.request,r);
tc.verifyEqual(a.status,'MISSING_RAW_CONTEXT');
end

function test_blocked_request_has_no_trajectory(tc)
r=struct('t',[]);
a=run_audit(tc,tc.TestData.request,r);
tc.verifyEqual(a.status,'NO_TRAJECTORY');
tc.verifyEqual(a.samples_checked,0);
tc.verifyFalse(a.physical_switching_certified);
end

function a=run_audit(~,request,result)
f=[tempname '.mat'];
save(f,'request','result');
cleanup=onCleanup(@()delete(f));
a=audit_ne39_scenario_cache(string(f));
end
