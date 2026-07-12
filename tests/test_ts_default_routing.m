function tests = test_ts_default_routing()
%TEST_TS_DEFAULT_ROUTING  Phase 8 default stepper routing.
%   After Phase 8, the production default (run_ts + catalog base) is
%   stepper='adaptive'. Fixed-step remains a permanent explicit option. This
%   test asserts the default routing and that fixed is still selectable.

tests = functiontests(localfunctions);
end
function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end
function test_catalog_base_default_is_adaptive(testCase)
cat = cases.network_case_catalog();
base_field = cat(1).ts_options;
% Every catalog entry inherits stepper='adaptive' from base (Phase 8).
for k = 1:numel(cat)
    testCase.verifyEqual(cat(k).ts_options.stepper, 'adaptive', ...
        sprintf('catalog entry %s default stepper must be adaptive', cat(k).id));
end
end
function test_run_ts_default_is_adaptive(testCase)
% run_ts.m sets stepper='adaptive' by default (Phase 8). Verify the file content.
projroot = fileparts(fileparts(mfilename('fullpath')));
src = fileread(fullfile(projroot, 'run_ts.m'));
testCase.verifyTrue(contains(src, "ts_options.stepper = 'adaptive'"), ...
    'run_ts.m must set stepper=adaptive as the production default.');
end
function test_fixed_still_selectable(testCase)
% Fixed-step remains a permanent explicit option.
c = cases.case_matpower6_case14();
r = stability.ts_simulate(c, struct('stepper','fixed','t_end',1,'dt',0.02, ...
    'fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz', ...
    'corrector_mode','adaptive','verbose',false));
testCase.verifyFalse(isfield(r,'stepper') && strcmp(r.stepper,'adaptive'), ...
    'fixed stepper explicitly selected');
testCase.verifyTrue(all(isfinite(r.delta(:))));
end
function test_adaptive_default_runs_classical(testCase)
% With stepper='adaptive' (the new default), classical runs through the
% adaptive driver and reports the adaptive schema.
c = cases.case_matpower6_case14();
r = stability.ts_simulate(c, struct('stepper','adaptive','t_end',1,'dt',0.02, ...
    'fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz', ...
    'corrector_mode','adaptive','verbose',false));
testCase.verifyEqual(r.stepper, 'adaptive');
testCase.verifyEqual(r.denominator, 3);
testCase.verifyEqual(r.controller_exponent, 1/3);
end
