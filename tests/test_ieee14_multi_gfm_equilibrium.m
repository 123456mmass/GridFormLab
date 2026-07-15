function tests = test_ieee14_multi_gfm_equilibrium
%TEST_IEEE14_MULTI_GFM_EQUILIBRIUM  Index-selected 1/2/3-GFM all-KCL gates.
%   Exactly one selected GFM balances active power and owns the angle
%   coordinate. Every other selected GFM remains physically voltage-forming;
%   it is not relabeled as GFL or as another slack.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_one_gfm_reference(testCase)
r = solve_selected(testCase,1);
verify_physical_result(testCase,r,1);
end

function test_two_gfm_exact_indices(testCase)
r = solve_selected(testCase,2);
verify_physical_result(testCase,r,2);
testCase.verifyEqual(r.reference.device_id,'IBR2');
end

function test_three_gfm_exact_indices(testCase)
r = solve_selected(testCase,3);
verify_physical_result(testCase,r,3);
testCase.verifyEqual(r.reference.device_id,'IBR2');
end

function test_reference_must_belong_to_selection(testCase)
[c,devices,selected] = build_selected(2);
cfg = struct('devices',devices,'selected_gfm_indices',selected, ...
    'n_gfm_required',2,'reference_resource_index',5);
r = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
testCase.verifyFalse(r.converged);
testCase.verifyEqual(r.failure_id,'mixed_equilibrium_solve:badReference');
end

function test_count_mismatch_fails_closed(testCase)
[c,devices,selected] = build_selected(3);
cfg = struct('devices',devices,'selected_gfm_indices',selected, ...
    'n_gfm_required',2,'reference_resource_index',selected(1));
r = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
testCase.verifyFalse(r.converged);
testCase.verifyEqual(r.failure_id,'mixed_equilibrium_solve:badReference');
end

function test_extra_runtime_gfm_fails_closed(testCase)
[c,devices,~] = build_selected(3);
cfg = struct('devices',devices,'selected_gfm_indices',[2 3], ...
    'n_gfm_required',2,'reference_resource_index',2);
r = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
testCase.verifyFalse(r.converged);
testCase.verifyEqual(r.failure_id,'mixed_equilibrium_solve:badReference');
testCase.verifyTrue(contains(r.failure_reason,'complete online runtime GFM'));
end

function test_offline_selected_gfm_fails_closed(testCase)
[c,devices,selected] = build_selected(2);
devices(selected(2)).initial_online = false;
cfg = struct('devices',devices,'selected_gfm_indices',selected, ...
    'n_gfm_required',2,'reference_resource_index',selected(1));
r = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
testCase.verifyFalse(r.converged);
testCase.verifyEqual(r.failure_id,'mixed_equilibrium_solve:badReference');
end

function test_sg_off_requires_atomic_selection(testCase)
[c,devices,~] = build_selected(1);
r = stability.mixed_equilibrium_solve(c,struct('devices',devices), ...
    struct('verbose',false));
testCase.verifyFalse(r.converged);
testCase.verifyEqual(r.failure_id,'mixed_equilibrium_solve:badReference');
testCase.verifyTrue(contains(r.failure_reason,'requires an explicit selected GFM'));
end

function test_noncontiguous_selection_and_nonfirst_reference(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
ids = {'IBR2','IBR3','IBR6','IBR8'};
modes = struct('device_id',ids,'mode',{'gfl','GFM','gfl','GFM'});
dispatch = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
devices = ibr.build_ieee14_sg_ibr_devices(c,modes,dispatch);
devices(1).initial_online = false;
devices(1).mode = 'breaker_open';
cfg = struct('devices',devices,'selected_gfm_indices',[3 5], ...
    'n_gfm_required',2,'reference_resource_index',5);
r = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
testCase.assertTrue(r.converged,r.failure_reason);
testCase.verifyEqual(r.reference.device_index,5,'AbsTol',0);
testCase.verifyEqual(r.reference.device_id,'IBR8');
testCase.verifyLessThan(r.physical_kcl_norm,1e-6);
end

function test_resource_device_order_drift_fails_closed(testCase)
[c,devices,selected] = build_selected(1);
cfg = struct('devices',devices, ...
    'resource_ids',{{'IBR2','SG1','IBR3','IBR6','IBR8'}}, ...
    'selected_gfm_indices',selected,'n_gfm_required',1, ...
    'reference_resource_index',selected(1));
r = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
testCase.verifyFalse(r.converged);
testCase.verifyEqual(r.failure_id,'mixed_equilibrium_solve:badReference');
testCase.verifyTrue(contains(r.failure_reason,'do not align exactly'));
end

function test_offline_dual_ibr_is_open_circuit_in_every_mode(testCase)
[~,devices,~] = build_selected(1);
dev = devices(3); % IBR3
y = zeros(28,1); y(1:2:end) = 1;
for mode = {'gfl','GFM'}
    hs = stability.ts_hybrid_state_init(devices);
    key = matlab.lang.makeValidName(dev.device_id,'ReplacementStyle','underscore');
    hs.device_online.(key) = false;
    hs.device_modes.(key) = mode{1};
    ec = struct('hybrid_state',hs);
    x = dev.x0; x(1) = x(1)+0.37; x(end) = x(end)-0.21;
    testCase.verifyEqual(dev.current_injection(0,x,y,dev.u0,ec),0,'AbsTol',0);
    testCase.verifyEqual(dev.electrical_power(0,x,y,dev.u0,ec),0,'AbsTol',0);
    testCase.verifyEqual(dev.f(0,x,y,dev.u0,ec),zeros(dev.nx,1),'AbsTol',0);
    testCase.verifyEmpty(dev.active_state_indices_for_context(ec));
    out = dev.reconstruct(0,x,y,dev.u0,ec);
    testCase.verifyFalse(out.online);
    testCase.verifyTrue(out.breaker_open);
end
end

function test_candidate_mode_override_is_single_truth(testCase)
% Devices may be constructed in GFL mode, then a candidate configuration
% commits IBR2 to GFM. Mask, RHS/current closures and returned devices must all
% consume that same immutable context.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
ids = {'IBR2','IBR3','IBR6','IBR8'};
modes = struct('device_id',ids,'mode',repmat({'gfl'},1,4));
dispatch = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
devices = ibr.build_ieee14_sg_ibr_devices(c,modes,dispatch);
devices(1).initial_online = false;
devices(1).mode = 'breaker_open';
override = struct('device_id',ids,'mode',{'GFM','gfl','gfl','gfl'});
cfg = struct('devices',devices,'device_modes',override, ...
    'selected_gfm_indices',2,'n_gfm_required',1, ...
    'reference_resource_index',2);
r = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
testCase.verifyTrue(r.converged,r.failure_reason);
testCase.verifyEqual(r.partition.nx_active,34,'AbsTol',0);
testCase.verifyEqual(r.partition.nx_frozen,52,'AbsTol',0);
testCase.verifyEqual(r.partition.ny_free,27,'AbsTol',0);
testCase.verifyEqual(r.partition.newton_dimension,62,'AbsTol',0);
testCase.verifyEqual(r.devices(2).initial_mode,'GFM');
testCase.verifyLessThan(r.physical_kcl_norm,1e-6);
sg = r.devices(1);
I0 = sg.current_injection(0,r.x0(1:sg.nx),r.y0,[],r.equilibrium_context);
xpert = r.x0(1:sg.nx); xpert(1) = xpert(1)+0.37;
Ipert = sg.current_injection(0,xpert,r.y0,[],r.equilibrium_context);
testCase.verifyEqual(I0,0,'AbsTol',0,'Offline SG injects zero current.');
testCase.verifyEqual(Ipert,0,'AbsTol',0, ...
    'Offline SG-state perturbation cannot change network injection.');
end

function test_hybrid_snapshot_commitment_cannot_be_overridden(testCase)
[c,devices,selected] = build_selected(2);
hs = stability.ts_hybrid_state_init(devices);
hs.selected_gfm_indices = selected;
hs.n_gfm_required = 2;
hs.reference_resource_index = selected(2);
hs.committed_selection = struct('selected_gfm_indices',selected, ...
    'n_gfm_required',2,'reference_resource_index',selected(2));
cfg = struct('devices',devices,'hybrid_state',hs, ...
    'selected_gfm_indices',selected,'n_gfm_required',2, ...
    'reference_resource_index',selected(1));
r = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
testCase.verifyFalse(r.converged);
testCase.verifyEqual(r.failure_id, ...
    'mixed_equilibrium_solve:selectionContextMismatch');
testCase.verifyTrue(contains(r.failure_reason,'immutable hybrid-state'));
end

function test_online_sg_owns_ref_despite_posttrip_gfm_commitment(testCase)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
ids = {'IBR2','IBR3','IBR6','IBR8'};
modes = struct('device_id',ids,'mode',{'GFM','gfl','gfl','gfl'});
dispatch = struct('IBR2',40,'IBR3',0,'IBR6',0,'IBR8',0);
devices = ibr.build_ieee14_sg_ibr_devices(c,modes,dispatch);
cfg = struct('devices',devices,'selected_gfm_indices',2, ...
    'n_gfm_required',1,'reference_resource_index',2);
r = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
testCase.assertTrue(r.converged,r.failure_reason);
testCase.verifyEqual(r.reference.device_id,'SG1');
testCase.verifyEqual(r.reference.slack_input_names,{'Tm','Efd'});
testCase.verifyLessThan(r.physical_kcl_norm,1e-6);
testCase.verifyEqual(r.vcon_type,'coordinate_elimination_all_kcl');
testCase.verifyLessThan(abs(r.limit_checks.devices.IBR3.P_MW),1e-9);
testCase.verifyTrue(r.limit_checks.devices.IBR3.within_active_power_limit, ...
    'Machine-roundoff around a true zero schedule is not reverse power.');
end

function test_material_negative_dispatch_fails_source_limit(testCase)
% The former oracle expected the generic post-solve limit gate.  WECC
% REEC_A defines Pmin=0 in this selected option, so negative scheduled power
% is invalid at device construction and must fail before Newton.
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
ids = {'IBR2','IBR3','IBR6','IBR8'};
modes = struct('device_id',ids,'mode',{'gfl','gfl','gfl','gfl'});
dispatch = struct('IBR2',40,'IBR3',-1,'IBR6',0,'IBR8',0);
testCase.verifyError(@() ibr.build_ieee14_sg_ibr_devices(c,modes,dispatch), ...
    'ibr:wecc_regca_reeca_model:equilibriumPowerLimit');
end

function r = solve_selected(testCase,n_gfm)
[c,devices,selected] = build_selected(n_gfm);
cfg = struct('devices',devices,'selected_gfm_indices',selected, ...
    'n_gfm_required',n_gfm,'reference_resource_index',selected(1));
r = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
testCase.assertTrue(r.converged,r.failure_reason);
end

function verify_physical_result(testCase,r,n_gfm)
testCase.verifyLessThan(r.residual_norm,1e-6);
testCase.verifyLessThan(r.physical_kcl_norm,1e-6);
testCase.verifyGreaterThan(r.rcond,1e-10);
testCase.verifyTrue(r.reference.balances_active_power);
testCase.verifyTrue(r.reference.physical_kcl_enforced);
testCase.verifyGreaterThan(r.reference.P_solved_MW,0);
testCase.verifyLessThanOrEqual(r.reference.P_solved_MW,140);
testCase.verifyEqual(r.reference.P_deviation_MW, ...
    r.reference.P_solved_MW-r.reference.P_scheduled_MW,'AbsTol',0);
testCase.verifyEqual(r.vcon_vars,4,'AbsTol',0, ...
    'IBR2 is the selected reference for deterministic first-n subsets.');
testCase.verifyEqual(numel(r.reference.device_index),1);
for id = {'IBR3','IBR6','IBR8'}
    if isfield(r.limit_checks.devices,id{1}) && ...
            ~strcmp(id{1},r.reference.device_id)
        testCase.verifyEqual(r.limit_checks.devices.(id{1}).P_MW,49.8, ...
            'AbsTol',1e-6, ...
            'Only the selected reference may move from scheduled active power.');
    end
end

% Count actual runtime GFM modes; only one owns the balancing input.
hs = stability.ts_hybrid_state_init(r.devices);
modes = fieldnames(hs.device_modes);
count = 0;
for k = 1:numel(modes)
    count = count + strcmpi(hs.device_modes.(modes{k}),'gfm');
end
testCase.verifyEqual(count,n_gfm,'AbsTol',0);
testCase.verifyLessThan(r.limit_checks.power_balance.mismatch_norm_pu,1e-6);
end

function [c,devices,selected] = build_selected(n_gfm)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
ids = {'IBR2','IBR3','IBR6','IBR8'};
modes_cell = repmat({'gfl'},1,numel(ids));
modes_cell(1:n_gfm) = repmat({'GFM'},1,n_gfm);
modes = struct('device_id',ids,'mode',modes_cell);
dispatch = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
devices = ibr.build_ieee14_sg_ibr_devices(c,modes,dispatch);
devices(1).initial_online = false;
devices(1).mode = 'breaker_open';
selected = 2:(n_gfm+1);  % resource/device table indices, not bus IDs
end
