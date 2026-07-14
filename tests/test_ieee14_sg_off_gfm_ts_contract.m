function tests = test_ieee14_sg_off_gfm_ts_contract()
%TEST_IEEE14_SG_OFF_GFM_TS_CONTRACT  Physical operating-point TS contract.
%   The selected GFM P_ref is solved once by equilibrium and then held
%   constant. No-disturbance fixed-step TS must retain every physical KCL
%   row. Online resources remain at equilibrium while the breaker-open SG
%   follows its open-circuit flux and rotor-coast equations.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();

c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
    'mode',{'GFM','gfl','gfl','gfl'});
dispatch = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
devices = ibr.build_ieee14_sg_ibr_devices(c,modes,dispatch);
devices(1).initial_online = false;
devices(1).mode = 'breaker_open';
config = struct('devices',devices,'selected_gfm_indices',2, ...
    'n_gfm_required',1,'reference_resource_index',2);
eq = stability.mixed_equilibrium_solve(c,config,struct('verbose',false));
testCase.assertTrue(eq.converged,eq.failure_reason);
testCase.assertTrue(eq.reference.physical_kcl_enforced);

testCase.TestData.case_data = c;
testCase.TestData.eq = eq;
end

function test_no_disturbance_holds_with_all_physical_kcl(testCase)
c = testCase.TestData.case_data;
eq = testCase.TestData.eq;

% Make the constructor/default input intentionally stale. The audited path
% must use opt.u_eq, not silently rebuild the scheduled reference P.
devices = eq.devices;
ref = eq.reference.device_index;
p_slot = find(strcmpi(string(devices(ref).input_names),'P_ref'),1);
u_index = sum([devices(1:ref-1).nu]) + p_slot;
devices(ref).u0(p_slot) = eq.reference.P_scheduled_pu;
testCase.verifyNotEqual(devices(ref).u0(p_slot),eq.u_eq(u_index));

opt = struct('t_end',0.02,'dt',0.01,'verbose',false, ...
    'u_eq',eq.u_eq,'event_context',eq.equilibrium_context, ...
    'dynamic_state_indices',eq.dynamic_state_indices,'full_kcl',true);
[ts,meta] = stability.ts_simulate_composite(c,devices,eq.x0,eq.y0,opt);

testCase.verifyTrue(ts.converged);
testCase.verifyTrue(meta.full_kcl);
testCase.verifyEqual(meta.input_source,'opt.u_eq_constant');
testCase.verifyEqual(size(ts.x_traj,2),3,'AbsTol',0);

dx = ts.x_traj - eq.x0;
dy = ts.y_traj - eq.y0;
sg_dynamic = intersect(1:6,eq.dynamic_state_indices,'stable');
testCase.verifyEqual(sg_dynamic,[1 2 3 5 6],'AbsTol',0, ...
    'Tpq0=0 keeps Edp frozen while breaker-open SG states remain dynamic.');
testCase.verifyGreaterThan(max(abs(dx(sg_dynamic,:)),[],'all'),1e-8, ...
    'Breaker-open SG must coast/decay; it must not be frozen by equilibrium masking.');
online_dynamic = setdiff(eq.dynamic_state_indices,sg_dynamic,'stable');
testCase.verifyLessThan(max(abs(dx(online_dynamic,:)),[],'all'),1e-6, ...
    'Online resources remain at their no-disturbance equilibrium.');
testCase.verifyLessThan(max(abs(dy(:))),1e-6, ...
    'Offline SG coast is decoupled from the network by zero breaker current.');

inactive = setdiff(1:numel(eq.x0),eq.dynamic_state_indices,'stable');
expected_anchor = repmat(eq.x0(inactive),1,size(ts.x_traj,2));
testCase.verifyEqual(ts.x_traj(inactive,:),expected_anchor,'AbsTol',0);

% Independent all-row KCL oracle: composite DAE is assembled without vcon,
% and every stored sample is checked using the exact solved input/context.
dae = stability.composite_dae(c,devices,struct('load_model','cz_p_cz_q'));
f0 = dae.dae_f(0,eq.x0,eq.y0,eq.u_eq,eq.equilibrium_context);
testCase.verifyGreaterThan(norm(f0(sg_dynamic),inf),1e-8, ...
    'Independent RHS confirms the breaker-open SG has physical dynamics.');
max_kcl = 0;
for k = 1:size(ts.x_traj,2)
    g = dae.dae_g(ts.t(k),ts.x_traj(:,k),ts.y_traj(:,k), ...
        dae.Ynet,eq.u_eq,eq.equilibrium_context);
    max_kcl = max(max_kcl,norm(g,inf));
end
testCase.verifyLessThan(max_kcl,1e-6);
end

function test_generic_scenario_preserves_offline_and_selection_contract(testCase)
dispatch = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
    'mode',{'GFM','gfl','gfl','gfl'});
online = struct('device_id','SG1','online',false);
committed = struct('selected_gfm_indices',2, ...
    'n_gfm_required',1,'reference_resource_index',2);
scenario = cases.scenario_ieee14_1sg_4ibr(struct( ...
    'dispatch',dispatch,'initial_modes',modes,'initial_online',online, ...
    'committed_selection',committed));

result = stability.run_hybrid_case(scenario,struct( ...
    't_end',0.02,'dt',0.01,'verbose',false));
testCase.assertTrue(result.converged, ...
    'Generic scenario must preserve SG_OFF and committed index selection.');
eq = result.equilibrium;
testCase.verifyTrue(eq.reference.physical_kcl_enforced);
testCase.verifyEqual(eq.reference.device_index,2,'AbsTol',0);
testCase.verifyEqual(eq.reference.device_id,'IBR2');
testCase.verifyLessThan(eq.physical_kcl_norm,1e-6);
testCase.verifyFalse(eq.devices(1).initial_online);
testCase.verifyEqual(lower(eq.devices(2).initial_mode),'gfm');
testCase.verifyTrue(result.metadata.ts_meta.full_kcl);
end

function test_dynamic_partition_mismatch_fails_closed(testCase)
c = testCase.TestData.case_data;
eq = testCase.TestData.eq;
bad = struct('t_end',0.01,'dt',0.01,'verbose',false, ...
    'u_eq',eq.u_eq,'event_context',eq.equilibrium_context, ...
    'dynamic_state_indices',eq.dynamic_state_indices(2:end), ...
    'full_kcl',true);
testCase.verifyError(@() stability.ts_simulate_composite( ...
    c,eq.devices,eq.x0,eq.y0,bad), ...
    'ts_simulate_composite:dynamicStateMismatch');
end
