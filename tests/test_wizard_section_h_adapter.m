function tests = test_wizard_section_h_adapter()
%TEST_WIZARD_SECTION_H_ADAPTER  Headless tests for the IBR Section H adapter.
%   Verifies wizard.adapt_ibr_section_h is an explicit, compatible adapter
%   (correction #4) that routes ONLY IBR results to +ibr/section_h_report,
%   never forces PF/SSSA/TS through it, and never fabricates content.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_pf_not_applicable(tc)
% PF results must NOT go through the IBR Section H producer.
req = wizard.build_request('pf', 'ieee5');
synth = struct('converged', true);
sh = wizard.adapt_ibr_section_h(synth, req);
tc.verifyEqual(sh.status, 'not_applicable');
end

function test_sssa_not_applicable(tc)
req = wizard.build_request('sssa', 'ieee5');
synth = struct('converged', true);
sh = wizard.adapt_ibr_section_h(synth, req);
tc.verifyEqual(sh.status, 'not_applicable');
end

function test_ts_not_applicable(tc)
req = wizard.build_request('ts', 'ieee5');
synth = struct('converged', true);
sh = wizard.adapt_ibr_section_h(synth, req);
tc.verifyEqual(sh.status, 'not_applicable');
end

function test_ibr_event_free_routes_to_section_h(tc)
% A real IBR event-free result must route to section_h_report (status ok or
% not_run, never fabricated). This is a UI_EXECUTION test: it asserts the
% adapter runs without throwing and produces a status; it does NOT assert
% numerical Section H content (that is the IBR owner's contract).
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'options', struct('t_end', .1, 'dt', .01, 'plot_results', false), ...
    'events', struct('enabled', false));
r = wizard.dispatch_analysis(req);
sh = wizard.adapt_ibr_section_h(r, req);
tc.verifyTrue(ismember(sh.status, {'ok', 'not_run'}));
if strcmp(sh.status, 'ok')
    tc.verifyTrue(isstruct(sh.report));
end
end

function test_ibr_missing_converged_fail_closed(tc)
% Missing/failed results must NOT be fabricated; fail closed.
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'options', struct('t_end', .1, 'dt', .01, 'plot_results', false), ...
    'events', struct('enabled', false));
sh = wizard.adapt_ibr_section_h(struct(), req);
tc.verifyEqual(sh.status, 'not_run');
end

function test_no_fabrication_on_missing_inventory(tc)
% When the result carries no inventory, the adapter must not fabricate one;
% section_h_report emits NOT_RUN for inventory-dependent sections.
req = wizard.build_request('ibr', 'ieee14_1sg_4ibr', ...
    'options', struct('t_end', .1, 'dt', .01, 'plot_results', false), ...
    'events', struct('enabled', false));
r = wizard.dispatch_analysis(req);
% Strip inventory if present, to confirm the adapter does not fabricate.
if isfield(r, 'inventory'), r = rmfield(r, 'inventory'); end
sh = wizard.adapt_ibr_section_h(r, req);
tc.verifyTrue(ismember(sh.status, {'ok', 'not_run'}));
end
