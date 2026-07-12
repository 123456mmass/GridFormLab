function tests = test_ts_default_routing()
%TEST_TS_DEFAULT_ROUTING  Default stepper routing after honesty closure.
%   The production default is FIXED-step (canonical). Adaptive is reached
%   ONLY when opt.stepper is explicitly 'adaptive'. As of this closure,
%   run_ts.m and the catalog base both set stepper='fixed', so the
%   catalog/run_ts path is fixed unless the user overrides. This test asserts:
%     (1) catalog base default is 'fixed' for every entry;
%     (2) run_ts.m source sets stepper='fixed' (and NOT 'adaptive');
%     (3) direct ts_simulate without stepper => fixed (no stepper field);
%     (4) explicit stepper='fixed' => fixed;
%     (5) explicit stepper='adaptive' => adaptive schema (still selectable);
%     (6) end-to-end solve_case via catalog => fixed by default;
%     (7) end-to-end solve_case with user override stepper='adaptive' => adaptive.
%   Routing contract (verified by this test): direct ts_simulate checks
%   isfield(opt,'stepper')&&strcmpi(opt.stepper,'adaptive'); the catalog path
%   uses merge_options(entry.options,user_opt) so entry.stepper='fixed' wins
%   unless the user passes stepper='adaptive'.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_catalog_base_default_is_fixed(testCase)
cat = cases.network_case_catalog();
for k = 1:numel(cat)
    testCase.verifyEqual(cat(k).ts_options.stepper, 'fixed', ...
        sprintf('catalog entry %s base stepper must be fixed (default restored)', cat(k).id));
end
end

function test_run_ts_default_is_fixed(testCase)
projroot = fileparts(fileparts(mfilename('fullpath')));
src = fileread(fullfile(projroot, 'run_ts.m'));
testCase.verifyTrue(contains(src, "ts_options.stepper = 'fixed'"), ...
    'run_ts.m must set stepper=fixed as the production default.');
testCase.verifyFalse(contains(src, "ts_options.stepper = 'adaptive'"), ...
    'run_ts.m must NOT default to adaptive.');
end

function opt = quick_opt(overrides)
% Short-horizon Case14 classical opt (no fault inside the 0.3 s window, so
% the run is fast and topology stays pre-fault).
opt = struct('t_end',0.3,'dt',0.1,'fault_bus',4,'t_fault',1.0,'t_clear',1.1, ...
    'Zf',1i*0.1,'pm_mode','pgaz','corrector_mode','adaptive','verbose',false);
if nargin >= 1
    fn = fieldnames(overrides);
    for k = 1:numel(fn), opt.(fn{k}) = overrides.(fn{k}); end
end
end

function test_direct_ts_simulate_default_is_fixed(testCase)
% Direct ts_simulate WITHOUT a stepper field => fixed path.
c = cases.case_matpower6_case14();
r = stability.ts_simulate(c, quick_opt());
testCase.verifyFalse(isfield(r,'stepper') && strcmpi(r.stepper,'adaptive'), ...
    'direct ts_simulate without stepper must stay fixed.');
testCase.verifyTrue(all(isfinite(r.delta(:))));
end

function test_explicit_fixed_stays_fixed(testCase)
c = cases.case_matpower6_case14();
r = stability.ts_simulate(c, quick_opt(struct('stepper','fixed')));
testCase.verifyFalse(isfield(r,'stepper') && strcmpi(r.stepper,'adaptive'), ...
    'explicit stepper=fixed must stay fixed.');
testCase.verifyTrue(all(isfinite(r.delta(:))));
end

function test_explicit_adaptive_runs_classical(testCase)
% Adaptive remains a permanent explicit production candidate.
c = cases.case_matpower6_case14();
r = stability.ts_simulate(c, quick_opt(struct('stepper','adaptive')));
testCase.verifyEqual(r.stepper, 'adaptive');
testCase.verifyEqual(r.denominator, 3);
testCase.verifyEqual(r.controller_exponent, 1/3);
testCase.verifyGreaterThan(r.accepted_steps, 0);
end

function test_solve_case_catalog_default_is_fixed(testCase)
% End-to-end: solve_case via catalog (case 'matpower14') with NO user stepper
% override => catalog base stepper='fixed' wins => fixed path.
res = solve_case('analysis','ts','case','matpower14', ...
    'options',struct('t_end',0.3,'dt',0.1,'verbose',false,'plot_results',false));
testCase.verifyFalse(isfield(res,'stepper') && strcmpi(res.stepper,'adaptive'), ...
    'solve_case via catalog (default) must be fixed.');
testCase.verifyTrue(all(isfinite(res.delta(:))));
end

function test_solve_case_user_override_adaptive(testCase)
% End-to-end: solve_case via catalog with user override stepper='adaptive'
% => adaptive path (adaptive schema).
res = solve_case('analysis','ts','case','matpower14', ...
    'options',struct('stepper','adaptive','t_end',0.3,'dt',0.1, ...
    'verbose',false,'plot_results',false));
testCase.verifyEqual(res.stepper, 'adaptive', ...
    'solve_case with user override stepper=adaptive must reach adaptive path.');
testCase.verifyEqual(res.denominator, 3);
end
