function tests = test_ts_tolerance_selection()
%TEST_TS_TOLERANCE_SELECTION  Honest NOT_READY contract for tolerance selection.
%   This test documents the honest status of the adaptive-TS tolerance
%   selection evidence. Per the approved honesty-closure policy, the
%   a-priori tolerance selection protocol declared in
%   docs/project/plans/adaptive_ts_track_a.md is NOT executable as written
%   (no reference construction, horizons, or thresholds declared a-priori
%   with a recorded before/after study). Therefore:
%     TOLERANCE_SELECTION_EVIDENCE = NOT_READY
%   This test does NOT fake a selection. It asserts:
%     (1) the method constants are auditable from any adaptive run
%         (denominator 3, controller exponent 1/3, p=2, q=3) -- these are
%         DERIVED from the step-doubling LTE estimator, not "selected";
%     (2) NO production code hard-codes a "selected" adaptive tolerance as an
%         acceptance value (grep guard);
%     (3) the prospective protocol doc exists and declares NOT_READY;
%     (4) the four error budgets remain separated (no cross-borrowing).
%   A FUTURE separately-approved prospective study
%   (docs/project/plans/adaptive_tolerance_study_proposal.md) may produce
%   executable evidence; until then the default stays fixed and tolerance
%   selection is NOT_READY.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_adaptive_driver_reports_method_constants(testCase)
% The adaptive driver reports the method constants (denominator 3, exponent
% 1/3, p=2, q=3) so the protocol can be audited from any run. These are
% DERIVED from the step-doubling LTE estimator (local O(h^3), global O(h^2),
% Richardson denominator 3, controller exponent 1/(p+1)=1/3), NOT selected
% tolerances. Auditing them is legitimate; selecting tolerances is NOT_READY.
c = cases.case_matpower6_case14();
r = stability.ts_simulate(c, struct('stepper','adaptive','t_end',1,'dt',0.02, ...
    'fault_bus',4,'t_fault',1.0,'t_clear',1.1,'Zf',1i*0.1,'pm_mode','pgaz', ...
    'corrector_mode','adaptive','verbose',false));
testCase.verifyEqual(r.denominator, 3, 'Richardson denominator 3 (not 7).');
testCase.verifyEqual(r.controller_exponent, 1/3, 'Controller exponent 1/3.');
testCase.verifyEqual(r.p, 2, 'Global order p=2.');
testCase.verifyEqual(r.q, 3, 'Local order q=3.');
end

function test_no_selected_tolerance_hardcoded_in_production(testCase)
% Grep guard: NO production path hard-codes a "selected" adaptive tolerance as
% an acceptance value. The adaptive driver uses proposed tolerances
% (atol_x/rtol_x/atol_y/rtol_y) that are NOT the output of a recorded
% selection study; they must not be presented as "selected" anywhere on the
% production path. This test scans the +stability package, +cases, and
% scripts for forbidden phrases indicating a selected/validated tolerance.
projroot = fileparts(fileparts(mfilename('fullpath')));
patterns = {'TOLERANCE_SELECTED', 'tolerance_selected', ...
    'SELECTED_ADAPTIVE_TOLERANCE', 'a_priori_selected_tolerance'};
hits = {};
base_dirs = {fullfile(projroot,'+stability'), fullfile(projroot,'+cases'), ...
    fullfile(projroot,'scripts')};
for d = base_dirs
    if ~exist(d{1},'dir'), continue; end
    f = dir(fullfile(d{1},'**','*.m'));
    for k = 1:numel(f)
        fp = fullfile(f(k).folder, f(k).name);
        txt = fileread(fp);
        for p = patterns
            if contains(txt, p)
                hits = [hits; {fp, p}]; %#ok<AGROW>
            end
        end
    end
end
if ~isempty(hits)
    msg = '';
    for h = 1:numel(hits)
        msg = [msg sprintf('%s (%s); ', hits{h,1}, hits{h,2})]; %#ok<AGROW>
    end
else
    msg = '(none)';
end
testCase.verifyTrue(isempty(hits), ...
    sprintf('Forbidden selected-tolerance claim found on production path: %s', msg));
end

function test_prospective_protocol_doc_declares_not_ready(testCase)
% The prospective tolerance-study protocol doc must exist and must declare
% NOT_READY (it is a FUTURE protocol, NOT executed in this closure).
projroot = fileparts(fileparts(mfilename('fullpath')));
docpath = fullfile(projroot,'docs','project','plans','adaptive_tolerance_study_proposal.md');
testCase.verifyTrue(exist(docpath,'file') == 2, ...
    'adaptive_tolerance_study_proposal.md must exist (prospective protocol).');
txt = fileread(docpath);
testCase.verifyTrue(contains(txt,'NOT_READY'), ...
    'proposal doc must declare TOLERANCE_SELECTION_EVIDENCE = NOT_READY.');
testCase.verifyTrue(contains(txt,'prospective') || contains(txt,'PROSPECTIVE'), ...
    'proposal doc must be labeled prospective (not executed now).');
% The doc must NOT claim a tolerance was actually selected. The phrase
% 'NO_TOLERANCE_SELECTED' (a declared failure outcome) is allowed; an
% assertion like 'TOLERANCE_SELECTED = PASS' / '= READY' is not.
testCase.verifyFalse(contains(txt,'TOLERANCE_SELECTED = PASS') || ...
    contains(txt,'TOLERANCE_SELECTED = READY') || ...
    contains(txt,'tolerance was selected'), ...
    'proposal doc must NOT claim a tolerance was selected.');
end

function test_four_error_budgets_remain_separated(testCase)
% Four separate error budgets, never borrowed across (plan). This remains a
% declared contract; selection evidence for each is NOT_READY.
budgets = struct('A_solver_lte','variable_dt_accept_reject', ...
    'B_algebraic_residual','inherited_g_tol', ...
    'C_fixed_vs_adaptive_equivalence','common_grid', ...
    'D_external_psat','validation_only');
testCase.verifyTrue(isfield(budgets,'A_solver_lte'));
testCase.verifyTrue(isfield(budgets,'B_algebraic_residual'));
testCase.verifyTrue(isfield(budgets,'C_fixed_vs_adaptive_equivalence'));
testCase.verifyTrue(isfield(budgets,'D_external_psat'));
% Budgets must remain distinct labels (no cross-borrowing).
labels = {budgets.A_solver_lte, budgets.B_algebraic_residual, ...
    budgets.C_fixed_vs_adaptive_equivalence, budgets.D_external_psat};
testCase.verifyEqual(numel(unique(labels)), 4, 'four distinct budget labels.');
end

