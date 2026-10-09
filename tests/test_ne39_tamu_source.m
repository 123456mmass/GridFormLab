function tests = test_ne39_tamu_source()
%TEST_NE39_TAMU_SOURCE ตรวจ source literals, ฐานหน่วย และทั้งสอง composition.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
pf_init_paths();
tc.TestData.raw = cases.ne39_tamu_raw();
tc.TestData.p = cases.ne39_tamu_machine_parameters();
end

function test_exact_source_values(tc)
r = tc.TestData.raw;
tc.verifySize(r.bus,[39 13]);
tc.verifySize(r.gen,[10 21]);
tc.verifySize(r.branch,[46 13]);
tc.verifyEqual(r.source_sha256,'800b65ed18e25957eba636b1c58e555fcf1b5990e918e2a982413085304b4689');
tc.verifyEqual(r.bus(:,10),ones(39,1));
tc.verifyEqual(sum(r.bus(:,3)),6124.5,'AbsTol',1e-9);
tc.verifyEqual(r.bus([4 5],6),[100;200]);
tc.verifyEqual(r.bus(31,[2 8 9]),[3 .982 0]);
tc.verifyEqual(r.gen(:,7),[200;100;200;200;100;200;200;200;200;2000]);
tc.verifyEqual(r.branch(r.branch(:,1)==31 & r.branch(:,2)==6,9),.993);
tc.verifyEqual(r.gen(:,9),9999.9*ones(10,1));
end

function test_archived_source_hashes(tc)
root = fileparts(fileparts(mfilename('fullpath')));
files = tc.TestData.raw.source_files;
for k = 1:numel(files)
    path = fullfile(root,'docs','benchmark_sources','ne39_tamu',files(k).path);
    fid = fopen(path,'rb');
    tc.assertGreaterThanOrEqual(fid,0,sprintf('ไม่พบ source archive: %s',files(k).path));
    cleanup = onCleanup(@()fclose(fid));
    bytes = fread(fid,Inf,'*uint8');
    clear cleanup;
    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(typecast(bytes(:),'int8'));
    digest = typecast(md.digest(),'uint8');
    actual = lower(reshape(dec2hex(digest,2).',1,[]));
    tc.verifyEqual(actual,files(k).sha256,files(k).path);
end
end

function test_genrou_base_conversion_and_raw_controls(tc)
p = tc.TestData.p;
tc.verifySize(p.genrou,[10 15]);
tc.verifyEqual(p.genrou_fields{12},'Xl');
tc.verifyEqual(p.genrou(1,13),.025);
tc.verifySize(p.ieeest_psse_raw,[10 20]);
tc.verifySize(p.exst1_pslf_raw,[10 20]);
tc.verifyEqual([p.unit.H_system],[42 30.299999 35.8 28.6 26 34.8 26.4 24.3 34.5 500],'AbsTol',1e-10);
tc.verifyEqual([p.unit.Xdp_system],[.031 .0697 .0531 .0436 .132 .05 .049 .057 .057 .006],'AbsTol',1e-12);
tc.verifyFalse(p.reduction.source_equivalent);
end

function test_source_solved_voltage_independent_kcl(tc)
r = tc.TestData.raw;
V = r.bus(:,8).*exp(1i*deg2rad(r.bus(:,9)));
Y = complex(zeros(39));
for k = 1:size(r.branch,1)
    z = r.branch(k,:); y = 1/complex(z(3),z(4));
    a = z(9); if a==0, a=1; end
    a = a*exp(1i*deg2rad(z(10)));
    i = z(1); j = z(2); sh = 1i*z(5)/2;
    Y(i,i) = Y(i,i)+(y+sh)/abs(a)^2;
    Y(i,j) = Y(i,j)-y/conj(a);
    Y(j,i) = Y(j,i)-y/a;
    Y(j,j) = Y(j,j)+y+sh;
end
Y = Y+diag(complex(r.bus(:,5),r.bus(:,6))/r.baseMVA);
S = -complex(r.bus(:,3),r.bus(:,4))/r.baseMVA;
for k = 1:10
    S(r.gen(k,1)) = S(r.gen(k,1))+complex(r.gen(k,2),r.gen(k,3))/r.baseMVA;
end
% RAW Vm/Va เก็บเพียง 5/4 ตำแหน่งทศนิยม จึงมี rounding residual.
tc.verifyLessThan(max(abs(V.*conj(Y*V)-S)),.003);
end

function test_both_compositions_and_pf_reproduction(tc)
for ns = [5 1]
    if ns==5, c=cases.case_ne39_5sg_5ibr(); else, c=cases.case_ne39_1sg_9ibr(); end
    tc.verifyEqual(numel(c.sg_buses),ns);
    tc.verifyEqual(numel(c.ibr_buses),10-ns);
    tc.verifyEqual(sort([c.sg_buses;c.ibr_buses]),(30:39)');
    tc.verifyEqual(c.bus_data(31,[2 3 4]),[1 1 0],'AbsTol',1e-12);
    tc.verifyEqual(c.source_variant.id,'TAMU_LEDESMA_2016');
    tc.verifyTrue(all(isnan(c.mpc.gen(:,9))));
    tc.verifyEqual(c.ibr_ratings_MVA,10*ceil(1.25*hypot( ...
        [c.ibr_scheduled.P_MW]',[c.ibr_scheduled.Q_MVAr]')/10));
    pf=pfsolver.powerflow_newton_raphson(c,struct('verbose',false, ...
        'plot_results',false,'tolerance',1e-10,'enforce_q_limits',true));
    tc.verifyTrue(pf.converged);
    tc.verifyEqual(pf.bus_voltage,c.bus_data(:,3),'AbsTol',1e-9);
    tc.verifyEqual(pf.bus_angle_deg,c.bus_data(:,4),'AbsTol',1e-8);
end
end

function test_both_mixed_equilibria(tc)
for ns=[5 1]
    if ns==5, s=cases.scenario_ne39_5sg_5ibr(); else, s=cases.scenario_ne39_1sg_9ibr(); end
    tc.verifyEqual(numel(s.resources),10);
    [dev,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
    tc.verifyEqual(sum([dev.nx]),2*ns+17*(10-ns));
    eq=stability.mixed_equilibrium_solve(s.case_data,struct('devices',dev),struct('verbose',false));
    % KCL equilibrium มีคำตอบ แต่ physical active capability ยัง unknown:
    % ต้องไม่ประกาศว่า constraint certification ผ่านจาก PF เพียงอย่างเดียว.
    tc.verifyFalse(eq.converged);
    tc.verifyTrue(contains(eq.failure_reason,'operating limit'));
    tc.verifyFalse(eq.limit_checks.devices.SG31.within_active_power_limit);
    tc.verifyLessThan(eq.residual_norm,1e-8);
    tc.verifyLessThan(eq.physical_kcl_norm,1e-8);
    tc.verifyEqual(eq.reference.device_id,'SG31');
end
end
