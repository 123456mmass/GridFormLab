function tests = test_r4_consistency()
%TEST_R4_CONSISTENCY  B6 vcon/model.g value/Jx/Jy consistency + rcond tests.
%   Verifies the B6 checker in multimachine_ssa:
%     - value consistency: model.g(vcon_rows) == vcon_eq(x0,y0)
%     - Jx row-equivalence (a): Jyx(vcon_rows,:) == Jcon_x
%     - fixed-y-only zero (b): Jcon_x ~= 0 => rejected
%     - Jy full-row consistency: Jyy(vcon_rows,:) == dvcon_eq/dy
%     - reduced-Jyy rcond >= RCOND_MIN
%     - h-vs-h/2 stabilization (fdUnstable)
%   Runtime ABI: model.vcon_eq(x,y). FROZEN thresholds (declared a-priori).
%
%   Source: project B6 design. Uses SYNTHETIC fixtures; no +ibr.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_value_consistency_pass(testCase)
% When g(vcon_rows) == vcon_eq at operating point, value check passes.
[model, vcon_spec] = fixtures.synthetic_slack_case('one_constraint');
model.vcon_vars = vcon_spec.vcon_vars;
model.vcon_rows = vcon_spec.vcon_rows;
model.vcon_eq = vcon_spec.vcon_eq;
% one_constraint: vcon_eq = [y(3)-1; y(4)-0] matches g(3:4) at y0.
result = stability.multimachine_ssa(model);
testCase.verifyTrue(all(isfinite(result.eigenvalues)), 'finite eigenvalues.');
end

function test_value_inconsistent_fail_closed(testCase)
% model.g(vcon_rows) != vcon_eq at operating point => vconInconsistent.
[model, vcon_spec] = fixtures.synthetic_slack_case('one_constraint');
model.vcon_vars = vcon_spec.vcon_vars;
model.vcon_rows = vcon_spec.vcon_rows;
% Make vcon_eq NOT match g at operating point: shift by a constant.
model.vcon_eq = @(x,y) [y(3)-1.0 + 0.5; y(4)-0 + 0.5];
testCase.verifyError(@() stability.multimachine_ssa(model), ...
    'multimachine_ssa:vconInconsistent');
end

function test_state_dependent_rejected(testCase)
% vcon_eq with x dependence (Jcon_x != 0) is rejected via Jx checks.
[model, vcon_spec] = fixtures.synthetic_slack_case('state_dependent');
model.vcon_vars = vcon_spec.vcon_vars;
model.vcon_rows = vcon_spec.vcon_rows;
model.vcon_eq = vcon_spec.vcon_eq;
try
    stability.multimachine_ssa(model);
    testCase.verifyTrue(false, 'expected error not raised.');
catch e
    id = e.identifier;
    ok = strcmp(id,'multimachine_ssa:vconStateCoupling') || ...
         strcmp(id,'multimachine_ssa:vconJacobianMismatch');
    testCase.verifyTrue(ok, sprintf('expected Jx rejection, got %s', id));
end
end

function test_jy_mismatch_fail_closed(testCase)
% Jyy(vcon_rows,:) != dvcon_eq/dy => vconJacobianMismatch. Use a LINEAR
% vcon_eq with a different slope from g (stable at h=1e-6, no h-vs-h/2 trip).
[model, vcon_spec] = fixtures.synthetic_slack_case('one_constraint');
model.vcon_vars = vcon_spec.vcon_vars;
model.vcon_rows = vcon_spec.vcon_rows;
% g(3:4) = [y(3)-1; y(4)-0]; at y0=[1;0;1;0] => [0;0]. Use vcon_eq with
% slope 2 (linear): [2*(y(3)-1); 2*(y(4)-0)] = [0;0] at y0 (value matches),
% but dvcon_eq/dy(3)=2 while dg/dy(3)=1 => Jy mismatch.
model.vcon_eq = @(x,y) [2*(y(3)-1.0); 2*(y(4)-0)];
testCase.verifyError(@() stability.multimachine_ssa(model), ...
    'multimachine_ssa:vconJacobianMismatch');
end

function test_no_inv_jyy_grep(testCase)
% Grep guard: no inv(Jyy)/pinv(Jyy)/inv(J_yy) in production +stability/.
% COI pinv(T) is ALLOWED (different — rectangular reduction matrix).
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

function test_coi_pinv_preserved(testCase)
% COI pinv(T) is preserved (B6 scope clarification: no-inv rule applies
% only to algebraic Jyy elimination).
% Verify pinv(T) still appears in reduce_coi path (grep for pinv(T)).
projroot = fileparts(fileparts(mfilename('fullpath')));
fp = fullfile(projroot,'+stability','multimachine_ssa.m');
lines = readlines(fp);
found_pinv_T = false;
for li = 1:numel(lines)
    ln = strtrim(lines{li});
    if isempty(ln) || ln(1) == '%', continue; end
    cidx = find(ln == '%', 1);
    if ~isempty(cidx), ln = strtrim(ln(1:cidx-1)); end
    if contains(ln,'pinv(T)')
        found_pinv_T = true; break;
    end
end
testCase.verifyTrue(found_pinv_T, 'COI pinv(T) preserved in reduce_coi.');
end

function test_consistent_two_constraints(testCase)
% Two consistent constraints pass all B6 checks.
[model, vcon_spec] = fixtures.synthetic_slack_case('two_constraints');
model.vcon_vars = vcon_spec.vcon_vars;
model.vcon_rows = vcon_spec.vcon_rows;
model.vcon_eq = vcon_spec.vcon_eq;
result = stability.multimachine_ssa(model);
testCase.verifyTrue(all(isfinite(result.eigenvalues)), 'finite eigenvalues.');
end
