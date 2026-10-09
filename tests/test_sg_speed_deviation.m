function tests=test_sg_speed_deviation()
%TEST_SG_SPEED_DEVIATION ตรวจฐานความเร็วด้วย SG/GFM จริง และ fail-closed ABI.
tests=functiontests(localfunctions);
end

function setupOnce(tc)
p=path; tc.addTeardown(@()path(p)); pf_init_paths();
s=cases.scenario_ne39_1sg_9ibr(struct('study_capability',true, ...
    'initial_modes',struct('device_id','IBR33','mode','gfm')));
[dev,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
tc.TestData.s=s; tc.TestData.dev=dev;
end

function test_real_classical_and_gfm_nominal_slip_is_zero(tc)
dev=tc.TestData.dev; sg=dev(strcmp({dev.device_type},'sg_classical'));
gfm=dev(strcmp({dev.device_id},'IBR33'));
% reconstruct ต้องใช้ shared y จริง ไม่ใช่ nominal speed fixture.
y=zeros(2*size(tc.TestData.s.case_data.bus_data,1),1);
y(1:2:end)=tc.TestData.s.case_data.bus_data(:,3);
sr=sg.reconstruct(0,sg.x0,y,sg.u0,struct());
gr=gfm.reconstruct(0,gfm.x0,y,gfm.u0,struct());
w=stability.sg_speed_deviation(sg,sr);
tc.verifyEqual(sr.omega,1,'AbsTol',0);
tc.verifyEqual(w,0,'AbsTol',0);
tc.verifyEqual(w,gr.gfm.omega_m,'AbsTol',0);
g=stability.synchronism_guard(1,1,0,w,gr.gfm.omega_m);
tc.verifyTrue(g.passes); tc.verifyEqual(g.df,0,'AbsTol',0);
end

function test_hybrid_reclose_guard_uses_classical_deviation(tc)
s=tc.TestData.s;
[dev,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
eq=stability.mixed_equilibrium_solve(s.case_data,struct('devices',dev),struct('verbose',false));
tc.assertTrue(eq.converged,eq.failure_reason);
e=struct('enabled',true,'event_profile','sg_cycle','sg_id','SG31', ...
    'sg_trip',.001,'sg_on',.002,'automatic_gfm_switching',false);
sched=stability.ibr_event_schedule(s.case_data,dev,e,.003,.001);
o=struct('t_end',.003,'dt',.001,'u_eq',eq.u_eq, ...
    'event_context',eq.equilibrium_context,'ibr_event_schedule',sched, ...
    'full_kcl',true,'automatic_gfm_switching',false);
[r,~]=stability.ts_simulate_ibr_hybrid(s.case_data,dev,eq.x0,eq.y0,o);
tc.assertTrue(r.converged,r.failure_reason);
tc.assertTrue(isfield(r.last_synchronism_guard,'df'));
sg=find(strcmp({dev.device_type},'sg_classical'));
gfm=find(strcmp({dev.device_id},'IBR33'));
xo=[0,cumsum([dev.nx])]; uo=[0,cumsum([dev.nu])];
sr=dev(sg).reconstruct(r.t(end),r.x_traj(xo(sg)+(1:dev(sg).nx),end), ...
    r.y_traj(:,end),r.u_history(uo(sg)+(1:dev(sg).nu),end),r.event_context_history{end});
gr=dev(gfm).reconstruct(r.t(end),r.x_traj(xo(gfm)+(1:dev(gfm).nx),end), ...
    r.y_traj(:,end),r.u_history(uo(gfm)+(1:dev(gfm).nu),end),r.event_context_history{end});
expected=abs((sr.omega-1)-gr.gfm.omega_m);
tc.verifyEqual(r.last_synchronism_guard.df,expected,'AbsTol',1e-14);
tc.verifyLessThan(r.last_synchronism_guard.df,.1);
tc.verifyTrue(isnan(r.actual_reclose_time));
end

function test_classical_slip_and_emf6_deviation_are_equivalent(tc)
a=struct('device_type','sg_classical'); b=struct('device_type','sg_emf6_composite');
wa=stability.sg_speed_deviation(a,struct('omega',1.01));
wb=stability.sg_speed_deviation(b,struct('omega',.01));
tc.verifyEqual(wa,wb,'AbsTol',1e-15);
g=stability.synchronism_guard(1,1,0,wa,0);
tc.verifyFalse(g.passes); tc.verifyEqual(g.df,.01,'AbsTol',1e-15);
end

function test_invalid_speed_and_unknown_model_fail_closed(tc)
d=struct('device_type','sg_classical');
for speed={NaN,Inf,1i,[1 1]}
    tc.verifyError(@()stability.sg_speed_deviation(d,struct('omega',speed{1})), ...
        'stability:sg_speed_deviation:missingSpeed');
end
tc.verifyError(@()stability.sg_speed_deviation(struct('device_type','unknown'), ...
    struct('omega',1)),'stability:sg_speed_deviation:unsupportedModel');
end
