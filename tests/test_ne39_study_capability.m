function tests = test_ne39_study_capability()
%TEST_NE39_STUDY_CAPABILITY แยก design assumptions จาก source hardware และ transition.
tests = functiontests(localfunctions);
end

function test_source_profile_remains_unknown(tc)
pf_init_paths();
c = cases.case_ne39_5sg_5ibr();
tc.verifyFalse(isfield(c,'study_capability'));
tc.verifyTrue(all(isnan(c.mpc.gen(:,9))));
end

function test_both_study_designs(tc)
pf_init_paths();
for ns = [5 1]
    if ns==5
        s = cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
    else
        s = cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
    end
    c = s.case_data;
    tc.verifyFalse(c.study_capability.source_hardware_verified);
    tc.verifyFalse(c.study_capability.transition_certified);
    rows = c.study_capability.records;
    for k = 1:numel(rows)
        r = rows(k);
        tc.verifyEqual(r.Pmax_MW,10*ceil(1.25*r.P0_MW/10));
        if startsWith(r.resource_id,'IBR')
            tc.verifyGreaterThan(r.Vdc_at_design_power_pu,r.Edc_pu/2);
            delivered = r.Vdc_at_design_power_pu*(r.Edc_pu-r.Vdc_at_design_power_pu)/r.Rdc_pu;
            tc.verifyEqual(delivered,r.converter_Pmax_pu,'AbsTol',1e-12);
            tc.verifyGreaterThan(r.Idc_continuous_design_pu, ...
                r.converter_Pmax_pu/r.Vdc_at_design_power_pu);
        end
    end
    [dev,~] = stability.build_mixed_resource_devices(c,s.resources,s.scenario_opt);
    for k = 1:numel(dev)
        if ~startsWith(dev(k).device_id,'IBR'), continue; end
        row = rows(strcmp({rows.resource_id},dev(k).device_id));
        branches = dev(k).provenance.branch_params;
        tc.verifyEqual(branches.gfl.dc_source.Edc,row.Edc_pu,'AbsTol',1e-12);
        tc.verifyEqual(branches.gfl.dc_source.Rdc,row.Rdc_pu,'AbsTol',1e-12);
        tc.verifyEqual(branches.gfl.dc_source.Edc,branches.gfm.dc_source.Edc,'AbsTol',1e-12);
        tc.verifyEqual(branches.gfl.dc_source.Rdc,branches.gfm.dc_source.Rdc,'AbsTol',1e-12);
    end
    eq = stability.mixed_equilibrium_solve(c,struct('devices',dev),struct('verbose',false));
    tc.verifyTrue(eq.converged,eq.failure_reason);
    tc.verifyLessThan(eq.physical_kcl_norm,1e-8);
end
end

function test_fault_only_does_not_enumerate_unused_candidates(tc)
pf_init_paths();
s = cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
e = struct('enabled',true,'event_profile','fault_only','fault_bus',16, ...
    'Zf',1i*.1,'fault_on',.02,'fault_clear',.04,'automatic_gfm_switching',false);
r = stability.run_hybrid_case(s,struct('t_end',.06,'dt',.005, ...
    'verbose',false,'ibr_events',e));
tc.verifyTrue(r.converged);
tc.verifyEqual(r.metadata.selector_not_required,'FAULT_ONLY_NO_MODE_CHANGE_AUTHORISED');
tc.verifyFalse(r.metadata.automatic_gfm_switching);
tc.verifyFalse(isfield(r.metadata,'selector_table_fingerprint'));
rr = stability.run_hybrid_case(s,struct('t_end',.06,'dt',.005, ...
    'verbose',false,'ibr_events',e,'online_rate_measurement',true));
tc.verifyTrue(rr.converged);
tc.verifyEqual(rr.x_traj,r.x_traj);
tc.verifyEqual(rr.y_traj,r.y_traj);
tc.verifyEqual(numel(rr.online_rate_log),numel(rr.t));
tc.verifyTrue(any(rr.online_rate_series.valid,'all'));
% เปิด policy measurement ไม่ให้อำนาจ switching ใน fault-only arm.
v=abs(complex(r.y_traj(1:2:end,1),r.y_traj(2:2:end,1)));
rp=stability.run_hybrid_case(s,struct('t_end',.06,'dt',.005, ...
    'verbose',false,'ibr_events',e,'ne39_rate_policy',true, ...
    'healthy_pf_V',v,'healthy_pf_bus_ids',s.case_data.bus_data(:,1)));
tc.verifyTrue(rp.converged,rp.failure_reason);
tc.verifyEqual(rp.x_traj,r.x_traj);
tc.verifyEqual(rp.y_traj,r.y_traj);
tc.verifyEqual(numel(rp.ne39_decision_log),numel(rp.t));
tc.verifyTrue(any(cellfun(@(d)d.valid,rp.ne39_decision_log)));
tc.verifyFalse(any(cellfun(@(d)d.commit_authorized,rp.ne39_decision_log)));
for k=1:numel(rp.ne39_decision_log)
    q=rp.ne39_decision_log{k};
    if ~q.valid, continue; end
    si=min(1,max(0,.5*q.si_components.Jv+.5*q.si_components.Jf));
    tc.verifyEqual(q.sample.severity,si,'AbsTol',1e-12);
    [~,j]=max(si); tc.verifyEqual(q.trigger_argmax.si,q.device_indices(j));
end
end

function test_gfm_rate_uses_active_rhs(tc)
pf_init_paths();
s = cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
[dev,~] = stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
d = dev(find(startsWith({dev.device_id},'IBR'),1));
ec = struct();
x = d.x0; x(11) = 1.001;
y = reshape([real(s.case_data.bus_data(:,3).*exp(1i*deg2rad(s.case_data.bus_data(:,4)))) ...
    imag(s.case_data.bus_data(:,3).*exp(1i*deg2rad(s.case_data.bus_data(:,4))))].',[],1);
% ใช้ default GFM ที่ constructor ประกาศ เพื่อไม่สมมติ event-context schema.
d = ibr.eecon49_dual_mode_model(string(d.device_id),d.bus_id,d.bus_position, ...
    d.bus_ids,complex(y(2*d.bus_position-1),y(2*d.bus_position)), ...
    s.resources(find(strcmp({s.resources.resource_id},d.device_id),1)).dynamic_params, ...
    d.u0(1),d.u0(2),d.u0(3),"GFM");
x = d.x0; x(11) = 1.001;
a = stability.et_fcs_device_frequency(d,0,x,y,d.u0,ec,s.case_data);
dx = d.f(0,x,y,d.u0,ec);
tc.verifyEqual(a.source,'gfm_omega');
tc.verifyEqual(a.fdot_hz_s,60*dx(11),'AbsTol',1e-12);
end

function test_changed_dispatch_requires_redesign(tc)
pf_init_paths();
tc.verifyError(@()cases.scenario_ne39_5sg_5ibr(struct('study_capability',true, ...
    'dispatch',struct('IBR30',1))),'cases:ne39StudyCapability:dispatchChanged');
end

function test_candidate_dispatch_keeps_fixed_dc_plant(tc)
pf_init_paths();
s = cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
r = s.resources(find(strcmp({s.resources.resource_type},'ibr'),1));
b = r.bus_id; c = s.case_data;
V = c.bus_data(b,3)*exp(1i*deg2rad(c.bus_data(b,4)));
P = s.scenario_opt.dispatch.(r.resource_id)/c.mpc.baseMVA;
Q = r.ratings.default_Q_MVAr/c.mpc.baseMVA;
a = ibr.eecon49_dual_mode_model(string(r.resource_id),b,b,c.bus_data(:,1)', ...
    V,r.dynamic_params,P,Q,abs(V),"gfl");
z = ibr.eecon49_dual_mode_model(string(r.resource_id),b,b,c.bus_data(:,1)', ...
    V,r.dynamic_params,1.1*P,Q,abs(V),"GFM");
for branch = ["gfl","gfm"]
    pa = a.provenance.branch_params.(branch).dc_source;
    pz = z.provenance.branch_params.(branch).dc_source;
    tc.verifyEqual(pz.Edc,pa.Edc);
    tc.verifyEqual(pz.Rdc,pa.Rdc);
    tc.verifyEqual(pz.tau_s,pa.tau_s);
    tc.verifyEqual(pz.Cdc,pa.Cdc);
end
tc.verifyLessThan(z.x0(3),a.x0(3));
tc.verifyGreaterThan(z.x0(17),a.x0(17));
tc.verifyEqual(ibr.dc_source_thevenin_rhs(z.x0(3),z.x0(17), ...
    z.provenance.params.dc_source.Pac0,z.provenance.params.dc_source), ...
    [0;0],'AbsTol',1e-11);
% เพิ่ม P_ref ต้องไม่เพิ่มกำลังแหล่งจ่ายที่แรงดัน/กระแส DC เดิม.
x = a.x0; y = reshape([real(V);imag(V)]*ones(1,39),[],1);
dx0 = a.f(0,x,y,a.u0,struct());
u = a.u0; u(1) = 1.1*u(1);
dx1 = a.f(0,x,y,u,struct());
tc.verifyEqual(dx1(17),dx0(17),'AbsTol',1e-12);
tc.verifyLessThan(dx1(3),dx0(3));
end

function test_single_sg_post_trip_dispatch(tc)
pf_init_paths();
s = cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
c = s.case_data; post = c.dispatch_contract.post_trip;
tc.verifyEqual(post.sg_ids,{'SG31'});
tc.verifyEqual(post.deficit_MW,c.dispatch_contract.pre_fault.SG31);
added = 0;
for id=string(fieldnames(post.post_trip_Pg_MW))'
    p = post.post_trip_Pg_MW.(id);
    tc.verifyLessThanOrEqual(p,c.dispatch_contract.pmax_MW.(id));
    added = added+p-c.dispatch_contract.pre_fault.(id);
end
tc.verifyEqual(added,post.deficit_MW,'AbsTol',1e-10);
s5 = cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
post5 = s5.case_data.dispatch_contract.post_trip;
tc.verifyTrue(isfield(post5,'post_trip_Pg_MW'));
tc.verifyEqual(sort(string(post5.sg_ids)),"SG31");
tc.verifyEqual(sort(string(post5.remaining_sg_ids)),["SG32","SG35","SG38","SG39"]);
tc.verifyEmpty(intersect(string(post5.sg_ids),string(post5.remaining_sg_ids)));
added5 = 0;
for id=string(fieldnames(post5.post_trip_Pg_MW))'
    p5 = post5.post_trip_Pg_MW.(id);
    tc.verifyLessThanOrEqual(p5,s5.case_data.dispatch_contract.pmax_MW.(id));
    added5 = added5+p5-s5.case_data.dispatch_contract.pre_fault.(id);
end
tc.verifyEqual(added5,post5.deficit_MW,'AbsTol',1e-10);
tc.verifyTrue(isfield(post,'remaining_sg_ids'));
tc.verifyEmpty(post.remaining_sg_ids);
end

function test_missing_contingency_fails_before_device_build(tc)
pf_init_paths();
s = cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
i = find(strcmp({s.resources.resource_type},'ibr'),1);
cand = struct('selected_gfm_indices',i,'reference_resource_index',i, ...
    'n_gfm_required',1);
bad = s.case_data;
bad.dispatch_contract.post_trip = rmfield(bad.dispatch_contract.post_trip,'post_trip_Pg_MW');
c = stability.ibr_candidate_evaluate(bad,s.resources,cand, ...
    struct(),s.case_data.selector.gamma_req_rad_per_s,struct('sg_online',false));
tc.verifyFalse(c.feasible);
tc.verifyFalse(c.ready_to_commit);
tc.verifyEqual(c.failure_id, ...
    'stability:ibr_candidate_evaluate:missingContingencyDispatch');
overlap = s.case_data;
overlap.dispatch_contract.post_trip.remaining_sg_ids = {'SG31','SG32'};
c2 = stability.ibr_candidate_evaluate(overlap,s.resources,cand, ...
    struct(),s.case_data.selector.gamma_req_rad_per_s,struct('sg_online',false));
tc.verifyEqual(c2.failure_id,'stability:ibr_candidate_evaluate:contingencyMismatch');
end

function test_other_certified_modes_do_not_authorize_initial_modes(tc)
pf_init_paths(); rehash;
s = cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
e = struct('enabled',true,'event_profile','sg_cycle','sg_trip',.02, ...
    'sg_on',.04,'automatic_gfm_switching',true);
o = struct('t_end',.06,'dt',.005,'verbose',false,'ibr_events',e, ...
    'lazy_gfm_search',true,'budget',struct('max_full_evaluations',3, ...
    'stop_on_first_certified',true));
r = stability.run_hybrid_case(s,o);
tc.verifyFalse(r.converged);
tc.verifyEqual(r.failure_id,'run_hybrid_case:initialModesNotCertified');
tc.verifyEmpty(r.t);
end

function test_reduced_amplitude_formula_matches_active_rhs(tc)
pf_init_paths();
s=cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
r=s.resources(find(strcmp({s.resources.resource_id},'IBR32'),1));
b=r.bus_id; ids=s.case_data.bus_data(:,1)';
V=s.case_data.bus_data(b,3)*exp(1i*deg2rad(s.case_data.bus_data(b,4)));
P=s.scenario_opt.dispatch.(r.resource_id)/100;
Q=r.ratings.default_Q_MVAr/100;
d=ibr.eecon49_dual_mode_model(string(r.resource_id),b,b,ids,V, ...
    r.dynamic_params,P,Q,abs(V),"GFM");
y=reshape([real(V);imag(V)]*ones(1,39),[],1);
for dq=[-.1 0 .1]
    x=d.equilibrium_initialize(V,P,Q+dq,struct());
    dx=d.f(0,x,y,d.u0,struct());
    p=d.provenance.branch_params.gfm;
    expected=(p.kQ*p.kappa*(Q-(Q+dq))-p.kE*(abs(V)-d.u0(3)))/p.tauE;
    tc.verifyEqual(dx(12),expected,'AbsTol',1e-11);
end
end

function test_fixed_dc_steady_reserve(tc)
pf_init_paths();
s = cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
[dev,~] = stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
eq = stability.mixed_equilibrium_solve(s.case_data,struct('devices',dev),struct('verbose',false));
tc.assertTrue(eq.converged,eq.failure_reason);
e = stability.ibr_dc_steady_reserve(dev,s.resources,eq,s.case_data);
tc.verifyEqual(e.status,'PASS');
tc.verifyGreaterThan(e.value,0);
% ลด continuous source limit ต่ำกว่าจุดทำงานต้อง FAIL ไม่ถูก margin เครื่องอื่นกลบ.
i = find(strcmp({s.resources.resource_type},'ibr'),1);
bad = dev;
for branch=["gfl","gfm"]
    bad(i).provenance.branch_params.(branch).dc_source.Idc_max = .01;
end
failed = stability.ibr_dc_steady_reserve(bad,s.resources,eq,s.case_data);
tc.verifyEqual(failed.status,'FAIL');
tc.verifyLessThan(failed.value,0);
% ข้อมูล capability หายไปต้อง UNKNOWN ไม่ใช่ pass.
dev(i).provenance.branch_params.gfl.dc_source.Idc_max = NaN;
e = stability.ibr_dc_steady_reserve(dev,s.resources,eq,s.case_data);
tc.verifyEqual(e.status,'UNKNOWN');
tc.verifyTrue(isnan(e.value));
end

function test_incomplete_fixed_dc_plant_rejected(tc)
pf_init_paths();
dc = struct('Edc',1.1);
tc.verifyError(@()ibr.dc_source_thevenin_params(dc,1,.1,.015,1,.8,0,1), ...
    'ibr:dc_source_thevenin:fixedPlant');
end

function test_invalid_flag_rejected(tc)
pf_init_paths();
tc.verifyError(@()cases.scenario_ne39_5sg_5ibr(struct('study_capability',2)), ...
    'cases:ne39StudyCapability:flag');
end
