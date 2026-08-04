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
    verifyEqual(testCase,s.devs{j}.nx(),12);
    verifyEqual(testCase,s.devs{j}.gfl_dev.device_type,'ibr_gfl_eecon49_full');
    verifyEqual(testCase,s.devs{j}.gfm_dev.device_type,'ibr_gfm_eecon49_full');
    verifyLessThan(testCase,norm(s.devs{j}.f(s.x_ibr0{j},s.y0),inf),1e-9);
end
verifyLessThan(testCase,norm(s.sg.f(s.x_sg0,s.y0),inf),1e-9);
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
