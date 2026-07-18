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

function test_compare_products_are_accepted(tc)
for value = {'pf_compare','sssa_compare'}
    req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
        'options', struct('ibr_analysis', value{1}, 'plot_results', false));
    req = wizard.validate_request(req);
    tc.verifyEqual(req.options.ibr_analysis, value{1});
end
end

function test_compare_rejects_explicit_events(tc)
ev = struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*.1, ...
    'fault_on', 1, 'fault_clear', 1.1, 'sg_trip', 2, 'sg_on', 3);
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'options', struct('ibr_analysis', 'pf_compare'), 'events', ev);
tc.verifyError(@() wizard.validate_request(req), ...
    'wizard:validate_request:ibrEventsNotApplicable');
end

function test_pf_sg_cycle_comparison_has_shared_indices(tc)
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'options', struct('ibr_analysis', 'pf_compare', 'plot_results', false));
r = wizard.dispatch_analysis(req);
tc.verifyTrue(r.converged, r.failure_reason);
tc.verifyEqual(r.ibr_analysis, 'pf_compare');
tc.verifyEqual({r.points.label}, {'PRE_TRIP','SG_TRIPPED','SG_RETURNED'});
tc.verifyEqual([r.device_rows.index], 1:numel(r.device_rows));
tc.verifyEqual({r.device_rows.device_id}, {'SG1','IBR2','IBR3','IBR6','IBR8'});
tc.verifyEqual(arrayfun(@(p) p.snapshot.active_state_count,r.points), [48 52 57]);
tc.verifyFalse(r.device_rows(1).tripped.online);
tc.verifyTrue(r.device_rows(1).returned.online);
tc.verifyEqual(r.device_rows(1).tripped.P_MW, 0, 'AbsTol', 1e-9);
end

function test_sssa_sg_cycle_comparison_preserves_state_and_mode_indices(tc)
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'options', struct('ibr_analysis', 'sssa_compare', 'plot_results', false));
r = wizard.dispatch_analysis(req);
tc.verifyTrue(r.converged, r.failure_reason);
tc.verifyEqual(r.ibr_analysis, 'sssa_compare');
tc.verifyEqual(arrayfun(@(p) size(p.sssa.A,1),r.points), [48 52 57]);
tc.verifyEqual(numel(r.state_rows), 98);
tc.verifyTrue(all(strcmp({r.spectrum_rows.pairing_status},'NOT_MODE_MATCHED')));
tc.verifyGreaterThanOrEqual(numel(r.spectrum_rows), 57);
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

function test_explicit_per_device_mode_map_is_preserved(tc)
opt = wizard.defaults_for_method('ibr');
opt.initial_gfm_count = 2;
opt.initial_gfm_indices = [3 5];
opt.initial_reference_resource_index = [];
opt = wizard.normalize_ibr_mode_selection(opt);
tc.verifyEqual(opt.initial_gfm_indices,[3 5]);
tc.verifyEqual(opt.initial_reference_resource_index,3);
tc.verifyEqual(opt.initial_gfl_count,2);
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

function test_full_accepts_independent_pf_sssa_ts_device_maps(tc)
cfg=@(idx) struct('initial_gfm_count',numel(idx), ...
    'initial_gfl_count',4-numel(idx),'initial_gfm_indices',idx, ...
    'initial_reference_resource_index',ternary_ref(idx));
modes=struct('linked',false,'pf',cfg([]),'sssa',cfg(2),'ts',cfg([2 3]));
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'options', struct('ibr_analysis', 'full', 'ibr_method_modes',modes, ...
        't_end', .01, 'dt', .01, 'plot_results', false, 'plot_visible', false), ...
    'events', struct('enabled', false));
r = wizard.dispatch_analysis(req);
tc.verifyTrue(r.converged,r.failure_reason);
tc.verifyEqual(r.cross_analysis_identity,'INDEPENDENT_MODE_CONFIGURATIONS');
tc.verifyEqual(r.separate_stage_results.pf.selector_log.selected_gfm_indices,[]);
tc.verifyEqual(r.separate_stage_results.sssa.selector_log.selected_gfm_indices,2);
tc.verifyEqual(r.separate_stage_results.ts.selector_log.selected_gfm_indices,[2 3]);
end

function test_full_fault_profile_b_completes_with_lvrt(tc)
ev=struct('enabled',true,'event_profile','fault_only','fault_bus',4, ...
    'Zf',1i*.1,'fault_on',.02,'fault_clear',.04,'sg_trip',.06,'sg_on',.08);
req=wizard.build_request('ibr','ieee14_1sg_4ibr', ...
    'options',struct('ibr_analysis','full','t_end',.08,'dt',.01, ...
        'plot_results',false,'plot_visible',false),'events',ev);
r=wizard.dispatch_analysis(req);
tc.verifyTrue(r.converged,r.failure_reason);
tc.verifyTrue(r.pf.converged);
tc.verifyTrue(r.equilibrium.converged);
tc.verifyTrue(r.sssa.execution_converged);
tc.verifyTrue(r.ts.converged);
tc.verifyEqual({r.ts.event_log.type},{'fault_on','fault_clear'});
tc.verifyTrue(all([r.ts.event_log.applied]));
tc.verifyLessThanOrEqual(max([r.ts.event_log.right_kcl_norm]),1e-6);
tc.verifyGreaterThan(r.ts.internal_substeps,r.ts.accepted_steps);
end

function test_ts_publishes_separate_sg_and_ibr_standard_plots(tc)
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'options', struct('ibr_analysis', 'ts', 't_end', .02, 'dt', .01, ...
        'plot_results', true, 'plot_visible', false), ...
    'events', struct('enabled', false));
r = wizard.dispatch_analysis(req);
tc.verifyTrue(r.converged);
files=r.figure_files(~cellfun(@isempty,r.figure_files));
tc.verifyGreaterThanOrEqual(numel(files),12);
tc.verifyTrue(all(cellfun(@isfile,files)));
tc.verifyTrue(any(contains(files,'sg_angle')));
tc.verifyTrue(any(contains(files,'ibr_angle')));
tc.verifyTrue(any(contains(files,'sg_frequency')));
tc.verifyTrue(any(contains(files,'ibr_frequency')));
tc.verifyTrue(any(contains(files,'sg_power')));
tc.verifyTrue(any(contains(files,'ibr_power')));
tc.verifyTrue(any(contains(files,'sg_voltage')));
tc.verifyTrue(any(contains(files,'ibr_voltage')));
end


function value=ternary_ref(idx)
if isempty(idx), value=[]; else, value=idx(1); end
end
