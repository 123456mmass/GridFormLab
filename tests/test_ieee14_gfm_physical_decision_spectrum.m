function tests = test_ieee14_gfm_physical_decision_spectrum()
%TEST_IEEE14_GFM_PHYSICAL_DECISION_SPECTRUM  Full roots plus physical quotient.
%   Independent oracle: a fixed active-bound equality removes its owned
%   differential coordinate before eig, and a simultaneous rotation of all
%   PLL angles is one network-frame gauge coordinate.  The complete active
%   state eig(A) set remains available and is never filtered after eig.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
ids = {'IBR2','IBR3','IBR6','IBR8'};
modes = struct('device_id',ids,'mode',{'GFM','GFM','GFM','GFM'});
devices = ibr.build_ieee14_sg_ibr_devices( ...
    c,modes,c.dispatch_contract.post_trip.post_trip_Pg_MW);
devices(1).initial_online = false;
devices(1).mode = 'breaker_open';
cfg = struct('devices',devices,'selected_gfm_indices',2:5, ...
    'n_gfm_required',4,'reference_resource_index',2);
eq = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
testCase.assertTrue(eq.converged,eq.failure_reason);
testCase.assertFalse(isempty(eq.active_bound_regime_history));
opt = struct('full_kcl',true,'u_eq',eq.u_eq, ...
    'event_context',eq.equilibrium_context, ...
    'active_state_indices',eq.active_state_indices, ...
    'active_bound_regimes',eq.active_bound_regime_history{end}, ...
    'reference_device_index',2);
sssa = stability.composite_sssa_model(devices,eq.x0,eq.y0,c,opt);
dae = stability.composite_dae(c,devices,struct('load_model','cz_p_cz_q'));
testCase.TestData.eq = eq;
testCase.TestData.sssa = sssa;
testCase.TestData.dae = dae;
end

function test_full_state_spectrum_is_retained_exactly(testCase)
s = testCase.TestData.sssa;
testCase.verifyEqual(numel(s.eigenvalues),52,'AbsTol',0);
testCase.verifyEqual(sort_eigs(s.eigenvalues),sort_eigs(eig(s.A)),'AbsTol',1e-11);
testCase.verifyTrue(s.no_eig_delete);
testCase.verifyGreaterThan(max(real(s.eigenvalues)),-0.1, ...
    'The raw table deliberately retains constrained/gauge roots.');
end

function test_fixed_active_bound_equalities_are_projected_before_eig(testCase)
s = testCase.TestData.sssa;
d = testCase.TestData.dae;
expected = reshape([d.device_offsets(2:5)+12;d.device_offsets(2:5)+13],1,[]);
testCase.verifyEqual(sort(s.active_bound_constraint_global_indices),sort(expected), ...
    'AbsTol',0);
testCase.verifyEqual(s.active_bound_constraint_count,8,'AbsTol',0);
testCase.verifyGreaterThan(s.active_bound_pivot_rcond,1e-10);
testCase.verifyLessThan(norm(s.active_bound_constraint_residual,inf),1e-8);
end

function test_common_pll_angle_is_quotiented_as_a_coordinate(testCase)
s = testCase.TestData.sssa;
d = testCase.TestData.dae;
testCase.verifyEqual(s.coordinate_mode_count,1,'AbsTol',0);
testCase.verifyEqual(s.coordinate_gauge_global_index,d.device_offsets(2)+5,'AbsTol',0);
testCase.verifyEqual(s.coordinate_gauge_state_name,'IBR2/gfm_delta_PLL');
testCase.verifyEqual(s.coordinate_quotient_left_map*s.coordinate_quotient_right_map, ...
    eye(size(s.coordinate_quotient_left_map,1)),'AbsTol',0);
end

function test_physical_decision_spectrum_meets_frozen_margin(testCase)
s = testCase.TestData.sssa;
testCase.verifyEqual(numel(s.physical_eigenvalues),43,'AbsTol',0);
testCase.verifyEqual(s.physical_state_dimension,43,'AbsTol',0);
testCase.verifyLessThanOrEqual(s.physical_omega,-0.1);
testCase.verifyTrue(s.physical_stable);
testCase.verifyTrue(contains(s.physical_reduction_method, ...
    'fixed_active_bound_tangent_elimination'));
testCase.verifyTrue(contains(s.physical_reduction_method, ...
    'common_gfm_pll_angle_quotient'));
end

function out = sort_eigs(lambda)
pair = sortrows([real(lambda(:)),imag(lambda(:))],[1 2]);
out = complex(pair(:,1),pair(:,2));
end
