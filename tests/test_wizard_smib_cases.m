function tests = test_wizard_smib_cases
%TEST_WIZARD_SMIB_CASES  Separate GFL/GFM infinite-bus launcher routes.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_discovery_has_two_distinct_smib_entries(tc)
r=wizard.discover_cases('ibr');
ids={r.id};
tc.verifyEqual(sum(endsWith(ids,'_smib')),2);
tc.verifyTrue(any(strcmp(ids,'gfl_rms10_smib')));
tc.verifyTrue(any(strcmp(ids,'gfm_no_pll_smib')));
end

function test_gfl_pf_route_uses_ten_state_device(tc)
r=run_case('gfl_rms10_smib','pf');
tc.verifyTrue(r.converged);
tc.verifyEqual(r.metadata.device_state_count,10);
tc.verifyEqual(r.pf.device_type,'ibr_gfl_rms10');
tc.verifyLessThan(r.pf.power_identity_error,1e-10);
tc.verifyEmpty(r.sssa);
tc.verifyEmpty(r.ts);
end

function test_gfm_sssa_route_is_four_state_no_pll(tc)
r=run_case('gfm_no_pll_smib','sssa');
tc.verifyTrue(r.converged);
tc.verifyEqual(r.metadata.device_state_count,4);
tc.verifyEqual(r.sssa.eigenvalue_count,4);
tc.verifyFalse(any(contains(lower(string(r.sssa.state_names)),'pll')));
tc.verifyLessThan(r.sssa.schur_direct_relative_error,1e-7);
end

function test_gfl_and_gfm_are_not_combined(tc)
gfl=run_case('gfl_rms10_smib','sssa');
gfm=run_case('gfm_no_pll_smib','sssa');
tc.verifyNotEqual(gfl.pf.device_type,gfm.pf.device_type);
tc.verifyEqual(gfl.sssa.eigenvalue_count,10);
tc.verifyEqual(gfm.sssa.eigenvalue_count,4);
end

function test_gfm_full_includes_event_free_tds(tc)
r=run_case('gfm_no_pll_smib','full');
tc.verifyTrue(r.converged);
tc.verifyNotEmpty(r.pf);
tc.verifyNotEmpty(r.equilibrium);
tc.verifyNotEmpty(r.sssa);
tc.verifyNotEmpty(r.ts);
tc.verifyEqual(r.execution_summary.event_transactions,0);
tc.verifyTrue(r.ts.newton_info_drift.all_converged);
end

function test_smib_rejects_comparison_and_events(tc)
o=smib_options('pf_compare');
req=wizard.build_request('ibr','gfl_rms10_smib','options',o, ...
    'events',struct('enabled',false));
tc.verifyError(@() wizard.validate_request(req), ...
    'wizard:validate_request:smibAnalysis');

o=smib_options('ts');
ev=struct('enabled',true,'fault_on',0.01,'fault_clear',0.02);
req=wizard.build_request('ibr','gfm_no_pll_smib','options',o,'events',ev);
tc.verifyError(@() wizard.validate_request(req), ...
    'wizard:validate_request:smibEventsNotSupported');
end

function r=run_case(id,product)
o=smib_options(product);
req=wizard.build_request('ibr',id,'options',o, ...
    'events',struct('enabled',false));
req=wizard.validate_request(req);
r=wizard.dispatch_analysis(req);
end

function o=smib_options(product)
o=struct('ibr_analysis',product,'plot_results',false, ...
    'plot_visible',false,'verbose',false,'t_end',0.05,'dt',1e-3);
end
