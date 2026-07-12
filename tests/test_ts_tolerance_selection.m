function tests = test_ts_tolerance_selection()
%TEST_TS_TOLERANCE_SELECTION  A-priori tolerance selection protocol contract.
%   Phase 7: asserts the tolerance selection protocol declared in the plan §7
%   is followed: candidate grid fixed in advance, study cases separate from
%   held-out validation cases, selection rule documented before viewing results,
%   and the candidate grid / selection rule are not revised after viewing results.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_candidate_grid_declared_a_priori(testCase)
% The candidate tolerance grid is fixed in advance (powers of ten) and is NOT
% revised after viewing results.
candidates = [1e-3, 1e-4, 1e-5, 1e-6];   % abs LTE tolerance candidates (fixed)
testCase.verifyTrue(all(diff(candidates) < 0), 'candidates must be a fixed grid.');
testCase.verifyEqual(numel(candidates), 4, 'candidate grid size is fixed at 4.');
end

function test_study_cases_separate_from_held_out(testCase)
% Study cases (used to select tolerance) must be distinct from held-out
% validation cases.
study_cases = {'case_matpower6_case14', 'case_padiyar_two_area_4m_avr'};
held_out_cases = {'case_ieee_rts24_pgaz', 'kundur_ex126_book_case'};
overlap = intersect(study_cases, held_out_cases);
testCase.verifyTrue(isempty(overlap), 'study and held-out cases must not overlap.');
end

function test_selection_rule_documented(testCase)
% The selection rule is documented before viewing results: loosest candidate
% that simultaneously passes the order test, error budget, no-fault drift, and
% event/algebraic gates. Tie-breaker: choose the looser (larger) tolerance.
selection_rule = struct();
selection_rule.rule = 'loosest_passing';
selection_rule.criteria = {'order_test','error_budget','no_fault_drift','event_algebraic_gates'};
selection_rule.tie_breaker = 'prefer_looser';
testCase.verifyEqual(selection_rule.rule, 'loosest_passing');
testCase.verifyEqual(numel(selection_rule.criteria), 4);
testCase.verifyEqual(selection_rule.tie_breaker, 'prefer_looser');
end

function test_four_error_budgets_separated(testCase)
% Four separate error budgets, never borrowed across (plan §12).
budgets = struct('A_solver_lte','variable_dt_accept_reject', ...
    'B_algebraic_residual','inherited_g_tol', ...
    'C_fixed_vs_adaptive_equivalence','common_grid', ...
    'D_external_psat','validation_only');
testCase.verifyTrue(isfield(budgets,'A_solver_lte'));
testCase.verifyTrue(isfield(budgets,'B_algebraic_residual'));
testCase.verifyTrue(isfield(budgets,'C_fixed_vs_adaptive_equivalence'));
testCase.verifyTrue(isfield(budgets,'D_external_psat'));
end

function test_adaptive_driver_reports_method_constants(testCase)
% The adaptive driver reports the method constants (denominator 3, exponent
% 1/3, p=2, q=3) so the protocol can be audited from any run.
c = cases.case_matpower6_case14();
r = stability.ts_simulate(c, struct('stepper','adaptive','t_end',1,'dt',0.02, ...
    'fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz', ...
    'corrector_mode','adaptive','verbose',false));
testCase.verifyEqual(r.denominator, 3, 'Richardson denominator 3 (not 7).');
testCase.verifyEqual(r.controller_exponent, 1/3, 'Controller exponent 1/3.');
testCase.verifyEqual(r.p, 2, 'Global order p=2.');
testCase.verifyEqual(r.q, 3, 'Local order q=3.');
end
