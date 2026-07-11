function tests = test_no_table95_acceptance_gate()
%TEST_NO_TABLE95_ACCEPTANCE_GATE  Guard: Padiyar Table 9.5 (an external
%   published reference) is never used as a numerical acceptance gate in
%   tests or production docs. The Table 9.5 comparison is diagnostic-only
%   (required_for_acceptance = false); a hard eigenvalue-distance
%   assertion to Table 9.5 would re-introduce a hidden acceptance gate and
%   must be caught here. The guard avoids false positives in comments and
%   diagnostic-only paths.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_no_table95_proximity_assertion_in_tests(testCase)
% Recursive guard: scan tests/ for a hard eigenvalue-distance assertion
% against Table 9.5. A production test must NOT gate regression acceptance
% on how close computed eigenvalues are to the published Table 9.5 values.
% The comparison must be diagnostic-only (finite-metric + metadata
% pipeline, required_for_acceptance = false).
%
% Pattern flagged: a test that BOTH references the Table 9.5 reference copy
% (table95 / Table 9.5) AND applies a verifyLessThan / assertLessThan on an
% eigenvalue-distance metric that is produced by the Table 9.5 comparison
% (variables named err/abs_err/rel_err returned from a table95 helper, or
% a numeric tolerance literal like 0.06 next to a verifyLessThan on an err).
%
% The guard is deliberately narrow to avoid false positives on legitimate
% structural assertions (e.g. max|delta-delta(1)| drift checks) that happen
% to live in a file that also mentions table95 for an unrelated reason.
root = fileparts(fileparts(mfilename('fullpath')));
tests_dir = fullfile(root,'tests');
fl = dir(fullfile(tests_dir,'*.m'));
hits = strings(0,1);
for k=1:numel(fl)
    p = fullfile(fl(k).folder, fl(k).name);
    src = fileread(p);
    % Strip comments and string literals to avoid false positives in
    % explanatory text that mentions the guard's own intent.
    code = strip_comments_and_strings(src);
    % Reference to the Table 9.5 comparison copy.
    has_table95_ref = ~isempty(regexpi(code, '(table95|Table\s*9[\._]\s*5)', 'once'));
    if ~has_table95_ref, continue; end
    % A verifyLessThan on a Table 9.5 error metric. The pre-closure hidden
    % gate was `verifyLessThan(testCase,max(err),0.06)` after a
    % table95/greedy_error call. Flag three specific signatures:
    %   (a) verifyLessThan(...,max(err),...)        — old greedy_error form
    %   (b) verifyLessThan(...,max(abs_err),...)    — new helper field form
    %   (c) verifyLessThan(...,max(cmp.absolute_errors),...) — struct form
    has_lt_err = ~isempty(regexpi(code, ...
        'verifyLessThan\s*\([^)]*max\s*\(\s*err\s*\)', 'once')) || ...
        ~isempty(regexpi(code, ...
        'verifyLessThan\s*\([^)]*max\s*\(\s*abs_err\s*\)', 'once')) || ...
        ~isempty(regexpi(code, ...
        'verifyLessThan\s*\([^)]*absolute_errors', 'once'));
    if has_lt_err
        hits(end+1,1) = string(p); %#ok<AGROW>
    end
end
testCase.verifyEmpty(hits, ...
    ['Tests must not gate regression on Table 9.5 eigenvalue distance. ' ...
     'Use diagnostic-only comparison with required_for_acceptance=false.']);
end

function test_table95_metadata_states_not_acceptance(testCase)
% Structural guard: the Table 9.5 comparison helper (table95_comparison in
% tests/test_padiyar_two_area_reference.m) must declare
% required_for_acceptance = false. This is the in-code contract that the
% comparison is diagnostic-only.
root = fileparts(fileparts(mfilename('fullpath')));
p = fullfile(root,'tests','test_padiyar_two_area_reference.m');
testCase.verifyTrue(exist(p,'file')==2,'test_padiyar_two_area_reference.m exists');
src = fileread(p);
% The helper must set the field to false (not true, not absent).
has_field = ~isempty(regexp(src, 'required_for_acceptance\s*=\s*false', 'once'));
testCase.verifyTrue(has_field, ...
    'table95_comparison must declare required_for_acceptance = false');
% It must NOT set it to true anywhere.
no_true = isempty(regexp(src, 'required_for_acceptance\s*=\s*true', 'once'));
testCase.verifyTrue(no_true, ...
    'table95_comparison must never set required_for_acceptance = true');
end

function test_sssa_solver_does_not_read_table95(testCase)
% Structural guard: the production SSSA solver must not read the Table 9.5
% reference copy. padiyar_model11_ssa.m attaches case_data.reference to the
% output for reporting only; multimachine_ssa.m must not reference it at
% all. This complements the runtime falsification test.
root = fileparts(fileparts(mfilename('fullpath')));
ssa_path = fullfile(root,'+stability','padiyar_model11_ssa.m');
mm_path = fullfile(root,'+stability','multimachine_ssa.m');
testCase.verifyTrue(exist(ssa_path,'file')==2,'padiyar_model11_ssa.m exists');
testCase.verifyTrue(exist(mm_path,'file')==2,'multimachine_ssa.m exists');
mm_src = fileread(mm_path);
% multimachine_ssa must not mention table95 or reference at all.
no_table95 = isempty(regexpi(mm_src, 'table95', 'once'));
testCase.verifyTrue(no_table95, ...
    'multimachine_ssa.m must not reference Table 9.5');
% It must not read case_data.reference.* fields (the reference is attached
% by the wrapper, not consumed by the solver).
no_ref_read = isempty(regexpi(mm_src, 'case_data\.reference|\.table95', 'once'));
testCase.verifyTrue(no_ref_read, ...
    'multimachine_ssa.m must not read case_data.reference fields');
end

function code = strip_comments_and_strings(src)
% Remove line comments (% ...) and single-quoted string literals from MATLAB
% source so the guard matches code intent, not explanatory text. Block
% comments %{ ... %} are also removed. This is a conservative stripper: it
% errs on the side of keeping code, which is the safe direction for a guard
% (a false negative would only let a real gate slip through, so we also
% cross-check with the runtime falsification test).
lines = splitlines(src);
out = cell(numel(lines),1);
in_block = false;
for k = 1:numel(lines)
    ln = lines{k};
    t = strtrim(ln);
    if in_block
        if strcmp(t,'%}'), in_block=false; end
        out{k}=''; continue;
    end
    if strcmp(t,'%{'), in_block=true; out{k}=''; continue; end
    % Strip line comment (first unquoted %).
    code_line = ln;
    in_str = false;
    for c = 1:numel(code_line)
        ch = code_line(c);
        if ch == '''' && (c==1 || code_line(c-1) ~= '''') %#ok<STRMATCH>
            in_str = ~in_str;
        end
        if ch == '%' && ~in_str
            code_line = code_line(1:c-1);
            break;
        end
    end
    out{k} = code_line;
end
code = strjoin(out, newline);
end
