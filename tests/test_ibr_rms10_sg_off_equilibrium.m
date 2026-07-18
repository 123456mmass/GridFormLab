function tests = test_ibr_rms10_sg_off_equilibrium()
%TEST_IBR_RMS10_SG_OFF_EQUILIBRIUM  RMS10 dual-family initializer regression.
%   Independent oracle: the registered RMS10 dual device exposes the same
%   equilibrium_initialize/current-injection/active-state ABI as the legacy
%   dual device. With SG offline and all four RMS10 IBRs committed GFM, the
%   existing all-KCL reduced initializer must solve rather than reject the
%   registered device_type by a legacy-only string comparison.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_all_rms10_gfm_sg_off_uses_generic_reduced_initializer(tc)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
post = c.dispatch_contract.post_trip.post_trip_Pg_MW;
scenario = cases.scenario_ieee14_1sg_4ibr(struct( ...
    'ibr_profile','rms10_profile_b','dispatch',post));
resources = scenario.resources;
resources(1).initial_online = false;
resources(1).initial_mode = 'breaker_open';
for k = 2:numel(resources)
    resources(k).initial_mode = 'gfm';
end
[devices,~] = stability.build_mixed_resource_devices(c,resources,scenario.scenario_opt);
tc.verifyEqual(unique(string({devices(2:end).device_type})),"ibr_dual_mode_rms10");
cfg = struct('devices',devices,'resource_ids',{{resources.resource_id}}, ...
    'selected_gfm_indices',2:5,'n_gfm_required',4, ...
    'reference_resource_index',2);
eq = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
tc.verifyTrue(eq.converged,eq.failure_reason);
tc.verifyEqual(numel(eq.active_state_indices),52);
tc.verifyLessThan(eq.physical_kcl_norm,1e-6);
tc.verifyEqual(eq.reference.device_id,'IBR2');
end

function test_unknown_online_device_type_still_fails_closed(tc)
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
post = c.dispatch_contract.post_trip.post_trip_Pg_MW;
scenario = cases.scenario_ieee14_1sg_4ibr(struct( ...
    'ibr_profile','rms10_profile_b','dispatch',post));
resources = scenario.resources;
resources(1).initial_online = false;
resources(1).initial_mode = 'breaker_open';
for k = 2:numel(resources), resources(k).initial_mode = 'gfm'; end
[devices,~] = stability.build_mixed_resource_devices(c,resources,scenario.scenario_opt);
devices(3).device_type = 'invented_dual_device';
cfg = struct('devices',devices,'resource_ids',{{resources.resource_id}}, ...
    'selected_gfm_indices',2:5,'n_gfm_required',4, ...
    'reference_resource_index',2);
eq = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
tc.verifyFalse(eq.converged);
tc.verifyEqual(eq.failure_id,'mixed_ibr_reduced_initialize:notPureIBRIsland');
end
