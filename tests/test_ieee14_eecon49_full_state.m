function tests=test_ieee14_eecon49_full_state
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function testFullStateRouteAndEquilibrium(testCase)
s=ibr.build_ieee14_switch_system(case_profile="eecon49_figure4",index_mode="agsi_pp", ...
    T_d_on=0.10,T_d_off=1.0);
verifyEqual(testCase,s.sg.device_type,'sg_emf6');
verifyEqual(testCase,s.sg.nx,6);
for j=1:numel(s.devs)
    verifyEqual(testCase,s.devs{j}.nx(),10);
    verifyEqual(testCase,s.devs{j}.gfl_dev.device_type,'ibr_gfl_eecon49_full');
    verifyEqual(testCase,s.devs{j}.gfm_dev.device_type,'ibr_gfm_eecon49_full');
    verifyLessThan(testCase,norm(s.devs{j}.f(s.x_ibr0{j},s.y0),inf),1e-9);
end
verifyLessThan(testCase,norm(s.sg.f(s.x_sg0,s.y0),inf),1e-9);
end

function testCompositeBuilderPreservesCaseDefinedGflPqDispatch(testCase)
% Regression: the generic builder previously consumed only scenario P dispatch
% and silently forced every Q_ref to zero.  That contradicted this case's mapped
% PQ-resource operating point and made its healthy PF voltage an invalid release
% reference. Independent oracle: external-bus-ID mapping of bus_data P/Q inputs.
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
[devices,~]=stability.build_mixed_resource_devices( ...
    s.case_data,s.resources,s.scenario_opt);
for k=2:5
    row=find(s.case_data.bus_data(:,1)==devices(k).bus_id);
    verifyNumElements(testCase,row,1);
    verifyEqual(testCase,devices(k).u0(1:2), ...
        s.case_data.bus_data(row,5:6).','AbsTol',1e-14);
end

% Backward compatibility: a profile with no declared Q schedule retains the
% historical unity-PF default rather than inheriting EECON49 values.
legacy=cases.scenario_ieee14_1sg_4ibr();
[legacy_devices,~]=stability.build_mixed_resource_devices( ...
    legacy.case_data,legacy.resources,legacy.scenario_opt);
verifyEqual(testCase,arrayfun(@(d)d.u0(2),legacy_devices(2:5)),zeros(4,1),'AbsTol',0);
end

function testOperationalEmf6SingularLimitIsFinite(testCase)
s=cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
[devices,~]=stability.build_mixed_resource_devices( ...
    s.case_data,s.resources,s.scenario_opt);
eq=stability.mixed_equilibrium_solve(s.case_data,struct('devices',devices), ...
    struct('verbose',false));
verifyTrue(testCase,eq.converged,eq.failure_reason);
verifyLessThan(testCase,eq.residual_norm,1e-8);
verifyEqual(testCase,eq.x0(4),0,'AbsTol',0);
dae=stability.composite_dae(s.case_data,eq.devices,struct('load_model','cz_p_cz_q'));
f0=dae.dae_f(0,eq.x0,eq.y0,eq.u_eq,struct());
verifyTrue(testCase,all(isfinite(f0)));
verifyEqual(testCase,f0(4),0,'AbsTol',0);
end

function testExact160SecondEventContract(testCase)
% Phase G updated this contract: T_end 160 -> 200 s so the trajectory covers
% the SG reclose and settling after coordinated handback.
s=ibr.build_ieee14_switch_system(case_profile="eecon49_figure4",index_mode="agsi_pp", ...
    T_d_on=0.10,T_d_off=1.0);
e=s.switching_event_contract;
verifyEqual(testCase,e.T_end,200,'AbsTol',0);
verifyEqual(testCase,e.sg_trip_time,20,'AbsTol',0);
verifyEqual(testCase,e.step_on,50,'AbsTol',0);
verifyEqual(testCase,e.step_factor,0.20,'AbsTol',0);
verifyTrue(testCase,e.step_all_loads);
verifyEqual(testCase,[e.fault_on e.fault_clear e.fault_bus],[85 85.15 9],'AbsTol',0);
verifyEqual(testCase,[e.line_trip_time e.line_from_bus e.line_to_bus],[110 6 13],'AbsTol',0);
verifyEqual(testCase,e.restore_time,145,'AbsTol',0);
verifyTrue(testCase,e.restore_sg && e.restore_line && e.restore_base_loads);
end

function testFixedBusBranchesHaveNoUnstableLocalPole(testCase)
for mode=["gfl","GFM"]
    if mode=="gfl"
        d=ibr.gfl_eecon49_full_model("T",2,1,2,1,struct(),0.30,0.10);
    else
        d=ibr.gfm_eecon49_full_model("T",2,1,2,1,struct(),0.30,0.10);
    end
    y=[1;0]; x=d.x0(:); f0=d.f(0,x,y,d.u0,struct()); n=numel(x); A=zeros(n); h=1e-6;
    for k=1:n
        xp=x; xp(k)=xp(k)+h;
        A(:,k)=(d.f(0,xp,y,d.u0,struct())-f0)/h;
    end
    verifyLessThanOrEqual(testCase,max(real(eig(A))),1e-6, ...
        sprintf('%s fixed-bus branch contains a right-half-plane local pole.',mode));
end
end

function testCoordinatedIdealSlackHandbackReturnsAllGfl(testCase)
s=ibr.build_ieee14_switch_system(case_profile="eecon49_figure4",index_mode="agsi_pp", ...
    T_d_on=0.10,T_d_off=1.0);
o=ibr.padiyar_switch_tds(s,T=4,dt=0.01,sg_trip_time=1,sg_reclose_time=3, ...
    sg_reclose_mode="ideal_slack",coordinated_reclose_handback=true, ...
    coordinated_gfm_reference=true);
verifyFalse(testCase,o.diverged);
verifyTrue(testCase,o.newton_all_converged);
verifyEqual(testCase,o.mode(end,:),zeros(1,4));
verifyEqual(testCase,o.dev_n_switch,[2 2 2 2]);
verifyLessThan(testCase,abs(o.Vmin(end)-min(abs(complex(s.y0(1:2:end),s.y0(2:2:end))))),1e-8);
verifyEqual(testCase,o.ref_code(end),0);
end
