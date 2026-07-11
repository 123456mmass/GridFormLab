function tests=test_no_external_solver_dependency
%TEST_NO_EXTERNAL_SOLVER_DEPENDENCY Guard: no external nonlinear solver in
%   the production scope. The guard recursively scans EVERY .m file under
%   the project root EXCEPT legacy/ (off-path reference code), .git/, and
%   docs/probes/ (off-path probes) -- i.e. everything that pf_init_paths can
%   put on the MATLAB path: root launchers, the +package folders, internal/,
%   compat/, scripts/, docs/.
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function files = production_m_files(root)
% Production scope: everything pf_init_paths puts on the path EXCEPT tests/
% (tests contain synthetic fixtures that intentionally reference forbidden
% symbols) and the off-path legacy/ and docs/probes/ directories.
fl = dir(fullfile(root,'**','*.m'));
files = strings(0,1);
this_file = mfilename('fullpath');
for k=1:numel(fl)
    p = fullfile(fl(k).folder, fl(k).name);
    if contains(p, [filesep 'legacy' filesep]) || contains(p, [filesep 'legacy']) ...
            || contains(p, [filesep '.git' filesep]) || contains(p, [filesep 'probes' filesep]) ...
            || contains(p, [filesep 'tests' filesep])
        continue;
    end
    % Never scan this test file itself (it holds synthetic scanner fixtures).
    [~,~,fe] = fileparts(p);
    if strcmp(fe, this_file), continue; end
    files(end+1,1) = string(p); %#ok<AGROW>
end
end

function test_production_scope_has_no_external_solver(testCase)
% Two-pass scanner (Phase B, mandatory correction B):
%   Pass A -- strip MATLAB comments, KEEP string literals.
%            Detects string-dispatch forms that execute the solver:
%              feval('fsolve', ...), feval("fsolve", ...)
%              str2func('fsolve'), str2func("fsolve")
%              eval('fsolve(...)'), eval("fsolve(...)")
%              dynamic function-name strings assigned/used as names.
%   Pass B -- strip MATLAB comments AND string literals.
%            Detects direct calls, function handles, package-qualified:
%              fsolve(...), @fsolve, optim.fsolve(...)
%   A plain comment or a documentation string must NOT trip either pass.
%   A string-dispatch that executes the solver MUST trip Pass A.
%   A function handle MUST trip Pass B.
root = fileparts(fileparts(mfilename('fullpath')));
files = production_m_files(root);
forbidden = {'fsolve','optimoptions','fmincon','fminsearch','lsqnonlin','optimset'};
hits = strings(0,3);
for k=1:numel(files)
    src = fileread(files(k));
    src_nocomment = strip_matlab_comments(src);
    src_clean     = strip_matlab_strings(src_nocomment);
    for q=1:numel(forbidden)
        sym = forbidden{q};
        % Pass A: string-dispatch forms (comments stripped, strings KEPT).
        % Character class matches an opening single OR double quote.
        pat_feval    = ['(feval|str2func|eval)\s*\(\s*['''', ''""]' sym];
        if ~isempty(regexp(src_nocomment, pat_feval, 'once'))
            hits(end+1,:) = {files(k), sym, 'string_dispatch'}; %#ok<AGROW>
        end
        % Pass B: direct call, function handle, package-qualified
        % (comments AND strings stripped, so only real code remains).
        pat_direct   = ['[^a-zA-Z0-9_]' sym '\s*\('];
        % Function handle: @<sym> not followed by a word character (avoids
        % matching @fsolveX while still matching @fsolve; @fsolve( ...).
        pat_handle   = ['@' sym '(?![a-zA-Z0-9_])'];
        if ~isempty(regexp(src_clean, pat_direct, 'once'))
            hits(end+1,:) = {files(k), sym, 'direct_call'}; %#ok<AGROW>
        end
        if ~isempty(regexp(src_clean, pat_handle, 'once'))
            hits(end+1,:) = {files(k), sym, 'function_handle'}; %#ok<AGROW>
        end
    end
end
testCase.verifyEmpty(hits, ...
    sprintf('Production .m files must not call external solvers. Hits:\n%s', ...
        strjoin(cellfun(@(r) sprintf('  %s: %s (%s)', r{1}, r{2}, r{3}), ...
            num2cell(hits, 2), 'UniformOutput', false), newline)));
end

function src = strip_matlab_comments(src)
% Strip MATLAB comments (% to end of line). Preserve string literals so that
% a quoted '%' inside a string is not mistaken for a comment start (best-effort:
% this is a guard, not a full MATLAB parser).
% Remove % comments that are not inside single-quoted strings: do a line-by-line
% scan, tracking only the simplest single-quote state.
lines = regexp(src, '\r\n|\n', 'split');
keep = cell(numel(lines), 1);
for k = 1:numel(lines)
    ln = lines{k};
    in_str = false;
    cut = numel(ln) + 1;
    j = 1;
    while j <= numel(ln)
        c = ln(j);
        if c == '''' && ~(j > 1 && ln(j-1) == '''')
            in_str = ~in_str;
        elseif c == '%' && ~in_str
            cut = j;
            break;
        end
        j = j + 1;
    end
    keep{k} = ln(1:cut-1);
end
src = strjoin(keep, newline);
end

function src = strip_matlab_strings(src)
% Strip MATLAB string literals (single-quoted '...' and double-quoted "...").
% Replace their contents with empty quotes so direct-call / function-handle
% detection no longer sees symbol text that lives only inside a string.
% Best-effort: handles non-nested single-quoted strings and double-quoted strings.
src = regexprep(src, '''[^''\r\n]*''', '''''');
src = regexprep(src, '"[^"\r\n]*"', '""');
end

function test_scanner_catches_direct_call(testCase)
% Synthetic FAIL: direct call must trip Pass B.
src = 'x = fsolve(fun, x0);';
testCase.verifyTrue(detect_forbidden(src, 'fsolve', 'direct_call'), ...
    'Direct fsolve call must be detected.');
end

function test_scanner_catches_function_handle(testCase)
% Synthetic FAIL: function handle must trip Pass B.
src = 'h = @fsolve;';
testCase.verifyTrue(detect_forbidden(src, 'fsolve', 'function_handle'), ...
    '@fsolve handle must be detected.');
end

function test_scanner_catches_feval_string_single_quote(testCase)
% Synthetic FAIL: feval('fsolve', ...) must trip Pass A.
src = 'x = feval(''fsolve'', fun, x0);';
testCase.verifyTrue(detect_forbidden(src, 'fsolve', 'string_dispatch'), ...
    'feval(''fsolve'') must be detected.');
end

function test_scanner_catches_feval_string_double_quote(testCase)
% Synthetic FAIL: feval("fsolve", ...) must trip Pass A.
src = 'x = feval("fsolve", fun, x0);';
testCase.verifyTrue(detect_forbidden(src, 'fsolve', 'string_dispatch'), ...
    'feval("fsolve") must be detected.');
end

function test_scanner_catches_str2func_single(testCase)
% Synthetic FAIL: str2func('fsolve') must trip Pass A.
src = 'h = str2func(''fsolve'');';
testCase.verifyTrue(detect_forbidden(src, 'fsolve', 'string_dispatch'), ...
    'str2func(''fsolve'') must be detected.');
end

function test_scanner_catches_str2func_double(testCase)
% Synthetic FAIL: str2func("fsolve") must trip Pass A.
src = 'h = str2func("fsolve");';
testCase.verifyTrue(detect_forbidden(src, 'fsolve', 'string_dispatch'), ...
    'str2func("fsolve") must be detected.');
end

function test_scanner_ignores_comment(testCase)
% Synthetic PASS: a comment mentioning fsolve must NOT trip either pass.
src = '% x = fsolve(fun, x0);';
testCase.verifyFalse(detect_forbidden(src, 'fsolve', 'direct_call'), ...
    'Commented fsolve must not be flagged as direct_call.');
testCase.verifyFalse(detect_forbidden(src, 'fsolve', 'string_dispatch'), ...
    'Commented fsolve must not be flagged as string_dispatch.');
end

function test_scanner_ignores_doc_string(testCase)
% Synthetic PASS: a documentation string mentioning fsolve must NOT trip
% the direct-call guard (Pass B strips strings).
src = 'disp(''fsolve is forbidden in production'');';
testCase.verifyFalse(detect_forbidden(src, 'fsolve', 'direct_call'), ...
    'Doc string mentioning fsolve must not be flagged as direct_call.');
end

function test_scanner_ignores_double_quoted_doc_string(testCase)
% Synthetic PASS: a double-quoted documentation string mentioning fsolve
% must NOT trip the direct-call guard.
src = 'message = "do not use fsolve";';
testCase.verifyFalse(detect_forbidden(src, 'fsolve', 'direct_call'), ...
    'Double-quoted doc string must not be flagged.');
end

function tf = detect_forbidden(src, sym, form)
% Helper for synthetic scanner self-tests. Mirrors the production two-pass
% logic on a single source snippet.
src_nocomment = strip_matlab_comments(src);
src_clean     = strip_matlab_strings(src_nocomment);
tf = false;
switch form
    case 'string_dispatch'
        pat = ['(feval|str2func|eval)\s*\(\s*['''', ''""]' sym];
        tf = ~isempty(regexp(src_nocomment, pat, 'once'));
    case 'direct_call'
        pat = ['[^a-zA-Z0-9_]' sym '\s*\('];
        tf = ~isempty(regexp(src_clean, pat, 'once'));
    case 'function_handle'
        pat = ['@' sym '(?![a-zA-Z0-9_])'];
        tf = ~isempty(regexp(src_clean, pat, 'once'));
end
end

function test_legacy_is_off_production_path(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
p = path;
entries = regexp(p, regexptranslate('escape', pathsep), 'split');
legacy_entry = fullfile(root,'legacy');
testCase.verifyFalse(any(strcmp(entries, legacy_entry)), 'legacy/ must not be on the path.');
legacy_fns = {'powerflow_fsolve','synchronous_flux_ssa','kundur_ex126_kundur_ssa', ...
    'kundur_ex126_book_e123_ssa','kundur_ex126_genrou_ssa','kundur_ex126_sixth_order_ssa', ...
    'genpj6_dae','ts_simulate_genpj6','kundur_fault_simulation_6th_order', ...
    'calibrate_kundur_e123_full','calibrate_all_24','kundur_e123_family_compare'};
found = strings(0,1);
for k=1:numel(legacy_fns)
    if ~isempty(which(legacy_fns{k})), found(end+1,1)=string(legacy_fns{k}); end %#ok<AGROW>
end
testCase.verifyEmpty(found, 'Legacy functions must not be reachable on the production path.');
end

function test_production_catalog_has_no_calibrated_kundur(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
files = {fullfile(root,'solve_case.m'), ...
    fullfile(root,'+cases','network_case_catalog.m'), ...
    fullfile(root,'+stability','multicase_sssa.m'), ...
    fullfile(root,'+stability','ts_simulate.m')};
forbidden = {'ts_simulate_genpj6','genpj6_dae','kundur_ex126_kundur_ssa', ...
    'kundur_ex126_book_e123_ssa','kundur_ex126_genrou_ssa','kundur_ex126_sixth_order_ssa', ...
    'synchronous_flux_ssa','kundur_ex126_book_flux_ssa','kundur_fault_simulation_6th_order', ...
    'calibrate_kundur_e123_full','calibrate_all_24'};
hits = strings(0,1);
for f=1:numel(files)
    src = fileread(files{f});
    for q=1:numel(forbidden)
        if ~isempty(regexp(src, ['[^a-zA-Z0-9_]' forbidden{q}],'once'))
            hits(end+1,1)=string(sprintf('%s: %s',files{f},forbidden{q})); %#ok<AGROW>
        end
    end
end
testCase.verifyEmpty(hits, ...
    'Production catalog/launcher must not reference calibrated/legacy Kundur paths.');
end
