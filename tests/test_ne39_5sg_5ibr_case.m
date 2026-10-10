function tests = test_ne39_5sg_5ibr_case()
%TEST_NE39_5SG_5IBR_CASE ตรวจ contract ที่เปลี่ยนเป็น TAMU ไม่ใช้ค่า MATPOWER เดิม.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
pf_init_paths();
tc.TestData.c = cases.case_ne39_5sg_5ibr();
end

function test_structure_and_composition(tc)
c=tc.TestData.c;
tc.verifySize(c.bus_data,[39 12]);
tc.verifySize(c.line_data,[46 7]);
tc.verifySize(c.mpc.gen,[5 21]);
tc.verifyEqual(c.sg_buses',[31 32 35 38 39]);
tc.verifyEqual(c.ibr_buses',[30 33 34 36 37]);
tc.verifyEqual(c.source_variant.id,'TAMU_LEDESMA_2016');
end

function test_slack_and_network(tc)
c=tc.TestData.c;
tc.verifyEqual(c.bus_data(31,[2 3 4]),[1 1 0],'AbsTol',1e-12);
tc.verifyEqual(c.bus_data([4 5],10),[1;2]);
tc.verifyEqual(sum(c.bus_data(:,7))*100,6124.5,'AbsTol',1e-9);
tc.verifyEqual(c.line_data(c.line_data(:,1)==31 & c.line_data(:,2)==6,6),.993);
end

function test_sg_dynamics_from_tamu(tc)
c=tc.TestData.c; p=cases.ne39_tamu_machine_parameters();
for k=1:numel(c.machines.units)
    u=c.machines.units(k); v=p.unit([p.unit.bus]==u.bus);
    tc.verifyEqual(u.H,v.H_system,'AbsTol',1e-12);
    tc.verifyEqual(u.D,v.D_system,'AbsTol',1e-12);
    tc.verifyEqual(u.Xdp,v.Xdp_system,'AbsTol',1e-12);
end
tc.verifyFalse(c.dynamics_contract.reduction.source_equivalent);
end

function test_ibr_schedule_and_ratings(tc)
c=tc.TestData.c;
for k=1:numel(c.ibr_scheduled)
    u=c.ibr_scheduled(k);
    tc.verifyEqual(c.bus_data(u.bus,2),3);
    tc.verifyEqual(c.bus_data(u.bus,5:6)*100,[u.P_MW u.Q_MVAr],'AbsTol',1e-10);
    tc.verifyEqual(c.ibr_ratings_MVA(k),10*ceil(1.25*hypot(u.P_MW,u.Q_MVAr)/10));
end
end

function test_pf_and_unknown_physical_capability(tc)
c=tc.TestData.c;
r=pfsolver.powerflow_newton_raphson(c,struct('verbose',false,'plot_results',false, ...
    'tolerance',1e-10,'enforce_q_limits',true));
tc.verifyTrue(r.converged);
tc.verifyEqual(r.bus_voltage,c.bus_data(:,3),'AbsTol',1e-9);
tc.verifyEqual(r.bus_angle_deg,c.bus_data(:,4),'AbsTol',1e-8);
tc.verifyTrue(isnan(c.dispatch_contract.pmax_MW.SG31));
tc.verifyEqual(c.dispatch_contract.feasibility_status,'PF_SOLVED_PHYSICAL_ACTIVE_CAPABILITY_UNKNOWN');
end
