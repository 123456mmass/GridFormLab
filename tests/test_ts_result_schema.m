function tests = test_ts_result_schema()
%TEST_TS_RESULT_SCHEMA  Adaptive result schema dimension contract (plan §5).
tests = functiontests(localfunctions);
end
function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end
function r = run_adaptive()
c = cases.case_matpower6_case14();
r = stability.ts_simulate(c, struct('stepper','adaptive','t_end',3,'dt',0.01, ...
    'fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz', ...
    'corrector_mode','adaptive','verbose',false));
end
function test_r_t_strictly_increasing_unique(testCase)
r = run_adaptive();
testCase.verifyTrue(all(diff(r.t) > 0), 'r.t strictly increasing');
testCase.verifyEqual(numel(unique(r.t)), numel(r.t), 'r.t unique timestamps');
end
function test_dt_is_scalar_nominal(testCase)
r = run_adaptive();
testCase.verifyTrue(isscalar(r.dt), 'r.dt scalar nominal');
testCase.verifyEqual(r.dt, r.dt_nominal);
end
function test_dt_history_equals_diff_t(testCase)
r = run_adaptive();
testCase.verifyEqual(numel(r.dt_history), numel(r.t)-1);
testCase.verifyEqual(r.dt_history, diff(r.t), 'AbsTol', 1e-14);
end
function test_lte_history_one_per_accepted_step(testCase)
r = run_adaptive();
testCase.verifyEqual(numel(r.lte_history), numel(r.t)-1);
end
function test_accepted_rejected_counts_scalar(testCase)
r = run_adaptive();
testCase.verifyTrue(isscalar(r.accepted_steps));
testCase.verifyTrue(isscalar(r.rejected_steps));
testCase.verifyEqual(r.accepted_steps + 1, numel(r.t), 'nt = accepted+1');
end
function test_rejection_history_is_struct_array(testCase)
r = run_adaptive();
testCase.verifyTrue(isstruct(r.rejection_history));
if ~isempty(r.rejection_history)
    f = r.rejection_history(1);
    testCase.verifyTrue(isfield(f,'attempted_dt') && isfield(f,'error_norm') && ...
        isfield(f,'reason') && isfield(f,'retry_dt') && isfield(f,'rejection_count'));
end
end
function test_no_t_raw_duplicate_field(testCase)
r = run_adaptive();
testCase.verifyFalse(isfield(r,'t_raw'), 'no t_raw duplicate of r.t');
end
function test_stepper_field_set(testCase)
r = run_adaptive();
testCase.verifyEqual(r.stepper, 'adaptive');
end
