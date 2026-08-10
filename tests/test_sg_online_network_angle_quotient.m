function tests = test_sg_online_network_angle_quotient()
%TEST_SG_ONLINE_NETWORK_ANGLE_QUOTIENT  SG-owned full-KCL gauge oracle.
%   A simultaneous rigid rotation of SG rotor angle, VSG internal angles and
%   bus phasors is a coordinate choice, not a physical damping mode.  This
%   test keeps the complete active-state spectrum for reporting and verifies
%   that the SG-owned angle coordinate is removed before the physical eig.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
s = cases.scenario_ieee14_1sg_4ibr(struct('case_profile','eecon49_figure4'));
resources = s.resources;
for k = 2:5
    resources(k).initial_mode = 'GFM';
end
[devices,~] = stability.build_mixed_resource_devices( ...
    s.case_data,resources,s.scenario_opt);
hs = stability.ts_hybrid_state_init(devices);
hs.selected_gfm_indices = 2:5;
hs.n_gfm_required = 4;
hs.reference_resource_index = 1;
hs.committed_selection = struct('selected_gfm_indices',2:5, ...
    'n_gfm_required',4,'reference_resource_index',1);
cfg = struct('devices',devices,'hybrid_state',hs, ...
    'selected_gfm_indices',2:5,'n_gfm_required',4, ...
    'reference_resource_index',1,'resource_ids',{{devices.device_id}});
eq = stability.mixed_equilibrium_solve(s.case_data,cfg,struct( ...
    'verbose',false,'tolerance',1e-8,'max_iter',300, ...
    'load_model','cz_p_cz_q'));
tc.assertTrue(eq.converged,eq.failure_reason);
opt = struct('full_kcl',true,'u_eq',eq.u_eq, ...
    'event_context',eq.equilibrium_context, ...
    'active_state_indices',eq.active_state_indices, ...
    'reference_device_index',1);
if isfield(eq,'active_bound_regime_history') && ...
        ~isempty(eq.active_bound_regime_history)
    opt.active_bound_regimes = eq.active_bound_regime_history{end};
end
tc.TestData.sssa = stability.composite_sssa_model( ...
    devices,eq.x0,eq.y0,s.case_data,opt);
end

function test_sg_reference_angle_is_quotiented_before_physical_eig(tc)
s = tc.TestData.sssa;
tc.verifyEqual(s.coordinate_mode_count,1,'AbsTol',0);
tc.verifyEqual(s.coordinate_gauge_global_index,1,'AbsTol',0);
tc.verifyEqual(s.coordinate_gauge_state_name,'SG1/delta');
tc.verifyTrue(contains(s.physical_reduction_method, ...
    'common_sg_ibr_network_angle_quotient'));
tc.verifyEqual(numel(s.physical_eigenvalues),numel(s.eigenvalues)-1,'AbsTol',0);
tc.verifyEqual(s.coordinate_quotient_left_map*s.coordinate_quotient_right_map, ...
    eye(size(s.coordinate_quotient_left_map,1)),'AbsTol',0);
end

function test_coordinate_pole_does_not_set_physical_handback_rate(tc)
s = tc.TestData.sssa;
% The complete spectrum intentionally retains the near-zero rigid-angle
% coordinate; the physical spectrum must expose the actual damped mode.
tc.verifyGreaterThan(max(real(s.eigenvalues)),-0.01);
tc.verifyLessThan(max(real(s.physical_eigenvalues)),-0.1);
end
