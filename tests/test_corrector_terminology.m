function tests = test_corrector_terminology()
%TEST_CORRECTOR_TERMINOLOGY  Corrector naming unambiguous (plan §8).
%   'adaptive' is reserved for variable-dt (stepper field). The residual-checked
%   Picard corrector is 'iterative' (legacy alias 'adaptive' on corrector_mode
%   still maps to the iterative path during migration). fixed_iterations is the
%   exact-count mode.
tests = functiontests(localfunctions);
end
function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end
function test_stepper_field_selects_variable_dt(testCase)
c = cases.case_matpower6_case14();
r = stability.ts_simulate(c, struct('stepper','adaptive','t_end',1,'dt',0.02, ...
    'fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz', ...
    'corrector_mode','adaptive','verbose',false));
testCase.verifyEqual(r.stepper, 'adaptive');
% corrector_mode is separate from stepper.
testCase.verifyEqual(r.corrector_mode, 'adaptive');
end
function test_fixed_stepper_keeps_canonical_path(testCase)
c = cases.case_matpower6_case14();
r = stability.ts_simulate(c, struct('stepper','fixed','t_end',1,'dt',0.02, ...
    'fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz', ...
    'corrector_mode','adaptive','verbose',false));
testCase.verifyFalse(isfield(r,'stepper') && strcmp(r.stepper,'adaptive'), ...
    'fixed stepper does not set adaptive');
testCase.verifyEqual(r.corrector_mode, 'adaptive');
end
function test_corrector_mode_fixed_runs(testCase)
c = cases.case_matpower6_case14();
r = stability.ts_simulate(c, struct('stepper','fixed','t_end',1,'dt',0.02, ...
    'fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz', ...
    'corrector_mode','fixed','corrector_iter',5,'verbose',false));
testCase.verifyEqual(r.corrector_mode, 'fixed');
testCase.verifyTrue(all(isfinite(r.delta(:))));
end
