function tests = test_wizard_ibr_subanalysis()
%TEST_WIZARD_IBR_SUBANALYSIS  IBR PF/SSSA/TS/Full orchestration contract.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_backward_compatible_default_is_ts(tc)
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'events', struct('enabled', false));
tc.verifyEqual(req.options.ibr_analysis, 'ts');
tc.verifyEqual(req.options.ibr_profile, 'rms10_profile_b');
tc.verifyEqual(req.options.initial_gfm_indices, 2);
end

function test_invalid_product_fails_closed(tc)
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'options', struct('ibr_analysis', 'invented'), ...
    'events', struct('enabled', false));
tc.verifyError(@() wizard.validate_request(req), ...
    'wizard:validate_request:badIbrAnalysis');
end

function test_interactive_mode_count_normalization(tc)
opt = wizard.defaults_for_method('ibr');
opt.initial_gfm_count = 0;
opt.initial_gfl_count = 4;
opt.initial_gfm_indices = 2; % stale value from the previous UI selection
opt.initial_reference_resource_index = 2;
opt = wizard.normalize_ibr_mode_selection(opt);
tc.verifyEmpty(opt.initial_gfm_indices);
tc.verifyEmpty(opt.initial_reference_resource_index);
tc.verifyEqual(opt.initial_gfl_count, 4);

opt.initial_gfm_count = 2;
opt = wizard.normalize_ibr_mode_selection(opt);
tc.verifyEqual(opt.initial_gfm_indices, [2 3]);
tc.verifyEqual(opt.initial_reference_resource_index, 2);
tc.verifyEqual(opt.initial_gfl_count, 2);
end

function test_pf_rejects_explicit_events(tc)
ev = struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*.1, ...
    'fault_on', 1, 'fault_clear', 1.1, 'sg_trip', 2, 'sg_on', 3);
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'options', struct('ibr_analysis', 'pf'), 'events', ev);
tc.verifyError(@() wizard.validate_request(req), ...
    'wizard:validate_request:ibrEventsNotApplicable');
end

function test_pf_publishes_network_result(tc)
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'options', struct('ibr_analysis', 'pf', 'plot_results', false));
r = wizard.dispatch_analysis(req);
tc.verifyTrue(r.converged);
tc.verifyEqual(r.ibr_analysis, 'pf');
tc.verifyTrue(r.pf.converged);
tc.verifyEmpty(r.equilibrium);
tc.verifyEmpty(r.sssa);
tc.verifyEmpty(r.ts);
end

function test_pf_log_identifies_resource_pq_and_reconciles(tc)
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'options', struct('ibr_analysis', 'pf', 'plot_results', false, ...
    'pf_verbose', false));
text = evalc('r = wizard.dispatch_analysis(req);');
tc.verifyTrue(r.converged);
tc.verifySubstring(text, 'RESOURCE INJECTION BREAKDOWN');
tc.verifySubstring(text, 'SG1');
tc.verifySubstring(text, 'GFM-13');
tc.verifySubstring(text, 'GFL-RMS10');
tc.verifySubstring(text, 'active=48');
tc.verifySubstring(text, 'dP=+0.000e+00 pu');
tc.verifyEqual(r.pf.bus_voltage_kV, 69*r.pf.bus_voltage, 'AbsTol', 0);
end

function test_sssa_uses_exact_mixed_equilibrium(tc)
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'options', struct('ibr_analysis', 'sssa', 'plot_results', false));
r = wizard.dispatch_analysis(req);
tc.verifyTrue(r.converged);
tc.verifyTrue(r.equilibrium.converged);
tc.verifyTrue(r.sssa.execution_converged);
tc.verifyEqual(size(r.sssa.A, 1), ...
    numel(r.equilibrium.active_state_indices));
tc.verifyEqual(size(r.sssa.A, 1), 48);
types = string({r.equilibrium.devices.device_type});
tc.verifyEqual(sum(types == "ibr_dual_mode_rms10"), 4);
tc.verifyLessThan(r.sssa.active_f_residual_norm, 1e-8);
tc.verifyLessThan(r.sssa.physical_kcl_residual_norm, 1e-8);
end

function test_full_publishes_four_products_on_shared_equilibrium(tc)
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'options', struct('ibr_analysis', 'full', 't_end', .02, 'dt', .01, ...
        'plot_results', false, 'plot_visible', false), ...
    'events', struct('enabled', false));
r = wizard.dispatch_analysis(req);
tc.verifyTrue(r.converged);
tc.verifyTrue(r.pf.converged);
tc.verifyTrue(r.equilibrium.converged);
tc.verifyTrue(r.sssa.execution_converged);
tc.verifyTrue(r.ts.converged);
tc.verifyEqual(r.sssa.x0, r.equilibrium.x0);
tc.verifyEqual(r.ts.equilibrium.x0, r.equilibrium.x0);
tc.verifyEqual(r.execution_summary.sssa_invocations, 1);
tc.verifyEqual(r.execution_summary.ts_invocations, 1);
end
