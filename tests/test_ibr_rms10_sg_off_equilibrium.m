function tests = test_ibr_rms10_sg_off_equilibrium()
%TEST_IBR_RMS10_SG_OFF_EQUILIBRIUM  SG-off reduced-initializer regression.
%   Independent oracle: the registered dual device exposes the same
%   equilibrium_initialize/current-injection/active-state ABI as the legacy
%   dual device. With SG offline and all four IBRs committed GFM, the existing
%   all-KCL reduced initializer must solve rather than reject the registered
%   device_type by a legacy-only string comparison.
%
%   Retargeted 2026-09-26: the profile no longer selects a GFL family (every
%   IBR is built by the single surviving ibr.eecon49_dual_mode_model), so the
%   device_type assertion and the active-state count below were re-derived for
%   that family instead of the retired 'ibr_dual_mode_rms10'.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_all_gfm_sg_off_uses_generic_reduced_initializer(tc)
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
tc.verifyEqual(unique(string({devices(2:end).device_type})),"ibr_eecon49_dual");
cfg = struct('devices',devices,'resource_ids',{{resources.resource_id}}, ...
    'selected_gfm_indices',2:5,'n_gfm_required',4, ...
    'reference_resource_index',2);
eq = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
tc.verifyTrue(eq.converged,eq.failure_reason);
% Active-count derivation for the surviving family (measured, not copied): the
% production profile enables dc_source.source_state, so each converter is a
% 17-state superset; its GFM active set is the shared plant (1:3), the GFM
% controller (10:16) and the Thevenin source current (17) = 11 states. Four
% converters in an SG-off island give 4 * 11 = 44 active states. The former
% expectation of 52 described the retired 23-state family (4 * 13).
tc.verifyEqual(numel(eq.active_state_indices),44);
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
