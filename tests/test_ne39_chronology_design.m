function tests=test_ne39_chronology_design()
%TEST_NE39_CHRONOLOGY_DESIGN ตรวจ derivation/ฐานหน่วยและ default isolation.
tests=functiontests(localfunctions);
end

function setupOnce(tc)
p=path; tc.addTeardown(@()path(p)); pf_init_paths();
b=cases.case_ne39_1sg_9ibr();
tc.TestData.base=b; tc.TestData.design=cases.ne39_chronology_design(b);
end

function test_source_and_default_unchanged(tc)
b=tc.TestData.base; c=tc.TestData.design;
tc.verifyFalse(isfield(b,'chronology_design'));
tc.verifyEqual(c.ne39,b.ne39);
tc.verifyEqual(c.source_dynamics,b.source_dynamics);
tc.verifyEqual(c.machines,b.machines);
tc.verifyEqual(c.line_data,b.line_data);
tc.verifyEqual(c.mpc.branch,b.mpc.branch);
tc.verifyEqual(c.mpc.bus(:,3:7),b.mpc.bus(:,3:7));
tc.verifyEqual(c.selector,b.selector); tc.verifyEqual(c.synchronism,b.synchronism);
tc.verifyEqual(c.source_detail,b.source_detail);
tc.verifyFalse(c.study_capability.transition_certified);
tc.verifyFalse(c.chronology_design.endpoint_certified);
end

function test_capacity_accounts_for_cz_envelope(tc)
c=tc.TestData.design; t=c.chronology_design.targets;
loadmax=sum(1.2*c.mpc.bus(:,3).*(1.1./c.bus_data(:,3)).^2);
need=loadmax*(1+t.loss_allowance_fraction)*(1+t.active_margin_fraction);
tc.verifyEqual(c.chronology_design.Pload_envelope_max_MW,loadmax,'RelTol',1e-14);
tc.verifyEqual(c.chronology_design.Pcapacity_required_MW,need,'RelTol',1e-14);
r=c.study_capability.records;
tc.verifyGreaterThanOrEqual(sum([r.Pmax_MW]),need);
tc.verifyLessThan(sum([r.Pmax_MW])-need,90);
for k=1:numel(r)
    a=r(k);
    tc.verifyLessThanOrEqual(hypot(a.Pmax_MW,a.Qmax_MVAr)/(a.converter_rating_MVA*.9),1);
end
end

function test_dynamic_derivations_and_shared_factory_plant(tc)
c=tc.TestData.design; d=c.chronology_design; t=d.targets;
tc.verifyEqual(d.H_s,d.M_s/2,'AbsTol',0);
tc.verifyEqual(60*d.imbalance_converter_pu/d.M_s,t.rocof_target_Hz_s,'RelTol',1e-14);
tc.verifyEqual(60*d.imbalance_converter_pu/d.Dv,t.frequency_error_target_Hz,'RelTol',1e-14);
s=cases.scenario_ne39_tamu_mixed(c);
[dev,~]=stability.build_mixed_resource_devices(c,s.resources,s.scenario_opt);
for k=find(strcmp({s.resources.resource_type},'ibr'))
    r=s.resources(k); p=dev(k).provenance.branch_params;
    a=c.study_capability.records(strcmp({c.study_capability.records.resource_id},r.resource_id));
    tc.verifyEqual(r.ratings.Mbase,a.converter_rating_MVA,'AbsTol',0);
    tc.verifyEqual(r.limits.Qmax_MVAr,a.Qmax_MVAr,'AbsTol',0);
    tc.verifyEqual(p.gfl.dc_source,p.gfm.dc_source);
    tc.verifyEqual(p.gfm.M,d.M_s,'AbsTol',0);
    tc.verifyEqual(p.gfm.Dv,d.Dv,'AbsTol',0);
    tc.verifyEqual(p.gfm.kQ/p.gfm.kE,t.voltage_droop_pu,'RelTol',1e-14);
    tc.verifyEqual(p.gfm.tauE/p.gfm.kE,t.voltage_response_s,'RelTol',1e-14);
    tc.verifyEqual(p.gfm.kiV/p.gfm.kpV,d.voltage_bandwidth_per_s,'RelTol',1e-14);
    tc.verifyEqual(.5*p.gfm.Cdc*(1-.9^2),a.converter_Pmax_pu*t.dc_energy_hold_s,'RelTol',1e-14);
    tc.verifyLessThan(a.converter_Pmax_pu/a.Vdc_at_design_power_pu^2,1/a.Rdc_pu);
end
end

function test_real_endpoint_screen_is_fail_closed(tc)
folder=probe_ne39_chronology_design();
data=load(fullfile(folder,'screen.mat'),'screen'); a=data.screen;
tc.assertEqual(a.status,'SCREENED_NOT_PRODUCTION_CERTIFIED',a.reason);
tc.verifyFalse(a.production_ready); tc.verifyFalse(a.endpoint_pass);
for name={'sg_on','post_trip','loaded','line_open'}
    tc.verifyEqual(a.(name{1}).evidence.status,'PASS');
    tc.verifyLessThanOrEqual(a.(name{1}).kcl,1e-6);
end
for name={'load_right','restore_right'}
    z=a.(name{1});
    tc.verifyEqual(z.evidence.status,'FAIL');
    tc.verifyTrue(z.state_continuity_exact); tc.verifyTrue(z.input_continuity_exact);
    tc.verifyEqual(z.current_jump_pu,0,'AbsTol',0);
    tc.verifyLessThanOrEqual(z.kcl,1e-6);
end
end

function test_fixed_reactor_witness_is_not_production_certificate(tc)
b=tc.TestData.base; qr=2000*ones(9,1);
op=struct('voltage_setpoints_pu',ones(10,1),'fixed_port_reactor_MVAr',qr);
c=cases.ne39_chronology_design(b,op);
tc.verifyEqual(c.mpc.branch,b.mpc.branch);
tc.verifyEqual(c.mpc.bus(:,3:4),b.mpc.bus(:,3:4));
tc.verifyEqual(c.mpc.bus(c.ibr_buses,6),b.mpc.bus(c.ibr_buses,6)-qr);
tc.verifyEqual(c.bus_data(c.ibr_buses,10),b.bus_data(c.ibr_buses,10)-qr/100);
tc.verifyEqual(c.source_detail,b.source_detail);
tc.verifyEqual(c.machines,b.machines);
tc.verifyFalse(c.chronology_design.physical_network_extension.selected_for_production);
folder=probe_ne39_chronology_design(op,struct('sssa',true));
data=load(fullfile(folder,'screen.mat'),'screen'); a=data.screen;
tc.assertEqual(a.status,'SCREENED_NOT_PRODUCTION_CERTIFIED',a.reason);
tc.verifyTrue(a.load_restore_pass); tc.verifyFalse(a.endpoint_pass);
tc.verifyFalse(a.production_ready);
tc.verifyEqual(a.fault_right.evidence.status,'FAIL');
tc.verifyEqual(a.line_right.evidence.status,'PASS');
for name={'sg_on','post_trip','loaded','line_open','load_right','restore_right'}
    tc.verifyEqual(a.(name{1}).evidence.status,'PASS');
    tc.verifyLessThanOrEqual(a.(name{1}).kcl,1e-6);
end
for name={'load_right','restore_right'}
    z=a.(name{1}); tc.verifyEqual(z.current_jump_pu,0,'AbsTol',0);
    tc.verifyTrue(z.state_continuity_exact); tc.verifyTrue(z.input_continuity_exact);
end
for name={'sg_on','post_trip'}
    rows=a.(name{1}).sssa;
    for k=1:3
        tc.verifyTrue(rows{k}.gate_pass);
        tc.verifyTrue(rows{k}.no_eig_delete);
        tc.verifyGreaterThanOrEqual(rows{k}.zeta_worst,c.selector.zeta_min_damping);
    end
end
end

function test_case_bound_all_gfm_witness(tc)
[op,analysis]=ne39_endpoint_design_options();
c=cases.ne39_chronology_design(tc.TestData.base,op);
tc.verifyEqual(sum(op.fixed_port_reactor_MVAr),16168.30560442528,'AbsTol',1e-9);
tc.verifyEqual(c.chronology_design.Dv,60*c.chronology_design.imbalance_converter_pu/.1,'RelTol',1e-14);
folder=probe_ne39_chronology_design(op,analysis);
data=load(fullfile(folder,'screen.mat')); a=data.screen;
tc.assertEqual(a.status,'SCREENED_NOT_PRODUCTION_CERTIFIED',a.reason);
tc.verifyTrue(a.endpoint_pass); tc.verifyTrue(a.sssa_pass);
tc.verifyFalse(a.production_ready);
tc.verifyTrue(all(strcmp({data.request.scenario.resources(2:end).initial_mode},'gfm')));
for name={'sg_on','post_trip','loaded','line_open','load_right','restore_right','fault_right','line_right'}
    tc.verifyEqual(a.(name{1}).evidence.status,'PASS');
    tc.verifyLessThanOrEqual(a.(name{1}).kcl,1e-6);
end
end

function test_invalid_options_fail_closed(tc)
b=tc.TestData.base;
tc.verifyError(@()probe_ne39_chronology_design(struct(),struct('sssa',2)), ...
    'probe_ne39_chronology_design:sssa');
tc.verifyError(@()probe_ne39_chronology_design(struct(),struct('unknown',true)), ...
    'probe_ne39_chronology_design:option');
tc.verifyError(@()cases.ne39_chronology_design(b,struct('fixed_port_reactor_MVAr',-ones(9,1))), ...
    'MATLAB:expectedNonnegative');
tc.verifyError(@()cases.ne39_chronology_design(b,struct('rocof_target_Hz_s',[1 2])), ...
    'MATLAB:expectedScalar');
tc.verifyError(@()cases.ne39_chronology_design(b,struct('unknown',1)), ...
    'cases:ne39ChronologyDesign:option');
tc.verifyError(@()cases.ne39_chronology_design(b,struct('voltage_setpoints_pu',1.2*ones(10,1))), ...
    'cases:ne39ChronologyDesign:voltage');
tc.verifyError(@()cases.ne39_chronology_design(b,struct('frequency_error_target_Hz',.5)), ...
    'cases:ne39ChronologyDesign:targets');
tc.verifyError(@()cases.ne39_chronology_design(tc.TestData.design), ...
    'cases:ne39ChronologyDesign:alreadyDesigned');
five=cases.case_ne39_5sg_5ibr();
tc.verifyError(@()cases.ne39_chronology_design(five), ...
    'cases:ne39ChronologyDesign:composition');
end
