function tests = test_studio_dispatch_parity()
%TEST_STUDIO_DISPATCH_PARITY  Pin +studio/run_analysis to the shared dispatcher.
%   The ONE request dispatcher routes pf -> pfsolver.pf_resolve_method +
%   pfsolver.pf_method_strategy(...).solve, sssa -> stability.multicase_sssa,
%   ts -> stability.ts_simulate.  studio.run_analysis must reproduce those
%   three call sites so a GUI run and a programmatic run are numerically the
%   same computation:
%
%     - PF on ieee5: bus_voltage / bus_angle_deg bit-identical (isequal)
%     - SSSA on ieee5: eigenvalues bit-identical
%     - TS on ieee5 (event-free): t / Vbus bit-identical
%     - +studio/run_analysis.m never calls powerflow_newton_raphson directly
%
%   See also: studio.RUN_ANALYSIS.
tests = functiontests(localfunctions);
end

%% ---- PF: bit-identical bus_voltage / bus_angle_deg on ieee5 ----
function test_pf_bit_identical(tc)
pf_init_paths();
[user, case_data, opt] = common_setup('pf');
r_stu = studio.run_analysis('pf', case_data, opt);
r_wiz = wizard.dispatch_analysis(user);
tc.verifyTrue(isfield(r_stu, 'bus_voltage'), 'studio PF result has bus_voltage');
tc.verifyTrue(isfield(r_stu, 'bus_angle_deg'), 'studio PF result has bus_angle_deg');
tc.verifyTrue(isequal(r_stu.bus_voltage(:), r_wiz.bus_voltage(:)), ...
    'bus_voltage bit-identical to the shared dispatcher');
tc.verifyTrue(isequal(r_stu.bus_angle_deg(:), r_wiz.bus_angle_deg(:)), ...
    'bus_angle_deg bit-identical to the shared dispatcher');
end

%% ---- SSSA: eigenvalues bit-identical on ieee5 ----
function test_sssa_bit_identical(tc)
pf_init_paths();
[user, case_data, opt] = common_setup('sssa');
r_stu = studio.run_analysis('sssa', case_data, opt);
r_wiz = wizard.dispatch_analysis(user);
tc.verifyTrue(isfield(r_stu, 'eigenvalues'), 'studio SSSA result has eigenvalues');
tc.verifyTrue(isequal(r_stu.eigenvalues(:), r_wiz.eigenvalues(:)), ...
    'eigenvalues bit-identical to the shared dispatcher');
end

%% ---- TS (event-free): t / Vbus bit-identical on ieee5 ----
function test_ts_bit_identical(tc)
pf_init_paths();
[user, case_data, opt] = common_setup('ts');
% The UI layer folds the event state in; event-free is an EXPLICIT
% fault_enabled=false (TS defaults carry fault times).
opt.fault_enabled = false;
r_stu = studio.run_analysis('ts', case_data, opt);
r_wiz = wizard.dispatch_analysis(user);
tc.verifyTrue(isfield(r_stu, 't'), 'studio TS result has t');
tc.verifyTrue(isequal(r_stu.t(:), r_wiz.t(:)), ...
    't bit-identical to the shared dispatcher');
tc.verifyTrue(isequal(r_stu.Vbus, r_wiz.Vbus), ...
    'Vbus bit-identical to the shared dispatcher');
end

%% ---- run_analysis never calls the NR solver directly ----
function test_run_analysis_no_direct_solver_call(tc)
repo = fileparts(fileparts(mfilename('fullpath')));
src = fileread(fullfile(repo, '+studio', 'run_analysis.m'));
tc.verifyFalse(contains(src, 'powerflow_newton_raphson'), ...
    'run_analysis.m must not call powerflow_newton_raphson directly');
tc.verifyTrue(contains(src, 'pfsolver.pf_resolve_method'), ...
    'run_analysis pf arm reproduces pf_resolve_method');
tc.verifyTrue(contains(src, 'pfsolver.pf_method_strategy'), ...
    'run_analysis pf arm reproduces pf_method_strategy');
tc.verifyTrue(contains(src, 'stability.multicase_sssa'), ...
    'run_analysis sssa arm reproduces multicase_sssa');
tc.verifyTrue(contains(src, 'stability.ts_simulate'), ...
    'run_analysis ts arm reproduces ts_simulate');
end

%% ---- ibr is not routed (studio runs PF/SSSA/TS only) ----
function test_ibr_not_routed(tc)
pf_init_paths();
[~, case_data, opt] = common_setup('pf');
threw = false;
try
    studio.run_analysis('ibr', case_data, opt);
catch e
    threw = true;
    tc.verifyEqual(e.identifier, 'studio:run_analysis:unknownAnalysis');
end
tc.verifyTrue(threw, 'ibr must fail closed in the studio dispatcher');
end

%% ---- shared setup ----
function [req, case_data, opt] = common_setup(analysis)
user_opt = struct('verbose', false, 'plot_results', false);
req = wizard.build_request(analysis, 'ieee5', 'options', user_opt);
req = wizard.validate_request(req);
entries = wizard.discover_cases(analysis);
idx = find(strcmp('ieee5', {entries.id}), 1);
if isempty(idx)
    error('test_studio_dispatch_parity:noIeee5', 'ieee5 entry not found.');
end
case_data = entries(idx).loader();
opt = req.options;
end
