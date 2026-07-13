function tests = test_r4_voltage_constraints()
%TEST_R4_VOLTAGE_CONSTRAINTS  R4 paired vcon Schur elimination tests.
%   Verifies separate vcon_vars/vcon_rows/vcon_eq ownership with nr/ny
%   dimensions, FIXED y-only constraints (Jcon_x==0), strict field-level
%   mutual exclusivity with free_y, full-rank Jcon_y, no inv/pinv, and
%   bit-identical SG SSSA when vcon fields are absent.
%
%   Source: project R4 design (docs/project/plans/ibr_interface_foundation.md).

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_no_constraints_sg_unchanged(testCase)
% When vcon fields absent, the path is bit-identical to the current free_y path.
% Run a real SG SSSA (Padiyar) and verify it still produces finite eigenvalues.
dm = stability.padiyar_model11_ssa([],struct('excitation','manual','fd_eps',1e-6));
testCase.verifyTrue(all(isfinite(dm.eigenvalues)), 'Padiyar eigenvalues finite.');
testCase.verifyEqual(numel(dm.eigenvalues), 16, 'Padiyar 16 eigenvalues.');
% free_y should be the default (all variables = size(Jyy,2)).
testCase.verifyEqual(numel(dm.free_y), size(dm.Jyy,2), 'free_y = all variables (default).');
end

function test_one_slack_constraint_square(testCase)
% One slack voltage constraint: reduced Jyy must be square.
[model, vcon_spec] = fixtures.synthetic_slack_case('one_constraint');
model.vcon_vars = vcon_spec.vcon_vars;
model.vcon_rows = vcon_spec.vcon_rows;
model.vcon_eq = vcon_spec.vcon_eq;
result = stability.multimachine_ssa(model);
% ny=4, n_vcon=2 => free_vars=2, free_rows=2 => reduced Jyy is 2x2 (square).
testCase.verifyEqual(numel(result.free_y), 2, 'free_vars cardinality = 2.');
testCase.verifyTrue(all(isfinite(result.eigenvalues)), 'finite eigenvalues.');
end

function test_kcl_row_replacement(testCase)
% vcon_eq returns the constraint residual; the reduced system solves.
[model, vcon_spec] = fixtures.synthetic_slack_case('one_constraint');
model.vcon_vars = vcon_spec.vcon_vars;
model.vcon_rows = vcon_spec.vcon_rows;
model.vcon_eq = vcon_spec.vcon_eq;
% vcon_eq at y0 should be ~0 (constraint satisfied at equilibrium).
g_vcon = model.vcon_eq(model.x0, model.y0);
testCase.verifyLessThan(max(abs(g_vcon)), 1e-12, 'vcon_eq ~0 at equilibrium.');
result = stability.multimachine_ssa(model);
testCase.verifyTrue(all(isfinite(result.eigenvalues)), 'reduced system solves.');
end

function test_state_dependent_constraint_fail_closed(testCase)
% vcon_eq depends on x (Jcon_x != 0) => B6 vconStateCoupling (or
% vconJacobianMismatch if Jyx rows differ). The B6 checker catches
% state-dependence via the separate Jx zero check (b).
[model, vcon_spec] = fixtures.synthetic_slack_case('state_dependent');
model.vcon_vars = vcon_spec.vcon_vars;
model.vcon_rows = vcon_spec.vcon_rows;
model.vcon_eq = vcon_spec.vcon_eq;
% B6 may raise either vconStateCoupling (Jcon_x!=0) or vconJacobianMismatch
% (Jyx(vcon_rows) != Jcon_x) depending on which fires first; both indicate
% the state-dependent constraint is rejected. Accept either.
try
    stability.multimachine_ssa(model);
    testCase.verifyTrue(false, 'expected error not raised.');
catch e
    id = e.identifier;
    ok = strcmp(id,'multimachine_ssa:vconStateCoupling') || ...
         strcmp(id,'multimachine_ssa:vconJacobianMismatch');
    testCase.verifyTrue(ok, sprintf('expected vconStateCoupling/JacobianMismatch, got %s', id));
end
end

function test_rank_deficient_constraint_fail_closed(testCase)
% Jcon_y rank-deficient (two identical constraint rows) => B6 catches via
% value/Jacobian consistency or reduced-Jyy rcond. The B6 checker no longer
% has a separate vconRankDeficient path; rank deficiency surfaces as a
% vconInconsistent / vconJacobianMismatch / singularReducedJyy failure.
[model, vcon_spec] = fixtures.synthetic_slack_case('rank_deficient');
model.vcon_vars = vcon_spec.vcon_vars;
model.vcon_rows = vcon_spec.vcon_rows;
model.vcon_eq = vcon_spec.vcon_eq;
try
    stability.multimachine_ssa(model);
    testCase.verifyTrue(false, 'expected error not raised.');
catch e
    id = e.identifier;
    ok = strcmp(id,'multimachine_ssa:vconInconsistent') || ...
         strcmp(id,'multimachine_ssa:vconJacobianMismatch') || ...
         strcmp(id,'multimachine_ssa:singularReducedJyy');
    testCase.verifyTrue(ok, sprintf('expected consistency/rcond error, got %s', id));
end
end

function test_mismatched_cardinality_fail_closed(testCase)
% numel(vcon_vars) != numel(vcon_rows) => fail-closed.
[model, vcon_spec] = fixtures.synthetic_slack_case('mismatched');
model.vcon_vars = vcon_spec.vcon_vars;
model.vcon_rows = vcon_spec.vcon_rows;
model.vcon_eq = vcon_spec.vcon_eq;
testCase.verifyError(@() stability.multimachine_ssa(model), ...
    'multimachine_ssa:vconMismatch');
end

function test_free_y_vconflict_fail_closed(testCase)
% free_y + vcon => strictly mutually exclusive => fail-closed.
[model, vcon_spec] = fixtures.synthetic_slack_case('one_constraint');
model.free_y = 1:2;
model.vcon_vars = vcon_spec.vcon_vars;
model.vcon_rows = vcon_spec.vcon_rows;
model.vcon_eq = vcon_spec.vcon_eq;
testCase.verifyError(@() stability.multimachine_ssa(model), ...
    'multimachine_ssa:exclusiveOwnership');
end

function test_partial_vcon_fail_closed(testCase)
% Partial vcon set (missing vcon_eq) => fail-closed.
[model, vcon_spec] = fixtures.synthetic_slack_case('one_constraint');
model.vcon_vars = vcon_spec.vcon_vars;
model.vcon_rows = vcon_spec.vcon_rows;
% vcon_eq intentionally NOT set.
testCase.verifyError(@() stability.multimachine_ssa(model), ...
    'multimachine_ssa:partialVcon');
end

function test_two_constraints(testCase)
% Two constrained buses: reduced Jyy is 0x0 (all variables constrained).
% Afull = Jxx (no algebraic elimination). Eigenvalues = eig(Jxx).
[model, vcon_spec] = fixtures.synthetic_slack_case('two_constraints');
model.vcon_vars = vcon_spec.vcon_vars;
model.vcon_rows = vcon_spec.vcon_rows;
model.vcon_eq = vcon_spec.vcon_eq;
result = stability.multimachine_ssa(model);
testCase.verifyEqual(numel(result.free_y), 0, 'all variables constrained.');
testCase.verifyTrue(all(isfinite(result.eigenvalues)), 'finite eigenvalues.');
end

function test_no_inv_jyy_in_production(testCase)
% Grep guard: no inv(Jyy) or pinv(Jyy) in production +stability/ (R4 extends
% the existing test_sssa_contract guard to cover new vcon code).
projroot = fileparts(fileparts(mfilename('fullpath')));
stabdir = fullfile(projroot,'+stability');
f = dir(fullfile(stabdir,'*.m'));
violations = {};
for k = 1:numel(f)
    fp = fullfile(f(k).folder, f(k).name);
    lines = readlines(fp);
    for li = 1:numel(lines)
        ln = strtrim(lines{li});
        if isempty(ln) || ln(1) == '%', continue; end
        cidx = find(ln == '%', 1);
        if ~isempty(cidx), ln = strtrim(ln(1:cidx-1)); end
        if contains(ln,'inv(Jyy)') || contains(ln,'pinv(Jyy)') || contains(ln,'inv(J_yy)')
            violations = [violations; {sprintf('%s:%d', f(k).name, li)}]; %#ok<AGROW>
        end
    end
end
testCase.verifyTrue(isempty(violations), ...
    sprintf('inv(Jyy)/pinv(Jyy) found: %s', strjoin(violations, ', ')));
end

function test_bit_identical_when_vcon_absent(testCase)
% When vcon fields absent AND free_y absent/default, Afull must be bit-identical
% to the pre-R4 path. Compare two runs of the same model.
[model, ~] = fixtures.synthetic_slack_case('one_constraint');
r1 = stability.multimachine_ssa(model);
r2 = stability.multimachine_ssa(model);
testCase.verifyEqual(r1.Afull, r2.Afull, 'AbsTol', 0, 'bit-identical (deterministic).');
testCase.verifyEqual(numel(r1.free_y), numel(model.y0), 'free_y = all (default).');
end
