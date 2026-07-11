function tests = test_no_kundur_calibration_claims()
%TEST_NO_KUNDUR_CALIBRATION_CLAIMS Ensure accepted paths do not use the fit.
tests = functiontests(localfunctions);
end

function test_production_does_not_call_calibrated_wrapper(testCase)
% The calibrated kundur_ex126_book_e123_ssa wrapper must not be referenced
% by production code or acceptance tests. (The historical book-flux path
% that referenced it has been relocated to legacy/.)
root = fileparts(fileparts(mfilename('fullpath')));
files = { ...
    fullfile(root,'+cases','dynamic_accuracy_benchmark_catalog.m'), ...
    fullfile(root,'tests','test_multimachine_machine_count_ladder.m')};
for k=1:numel(files)
    verifyEmpty(testCase,regexp(fileread(files{k}), ...
        'kundur_ex126_book_e123_ssa','once'),files{k});
end
% Additionally, no file under the production packages may CALL the wrapper
% (the wrapper's own definition in +stability is allowed).
dirs = {'+pfsolver','+stability','+smib','+pfapp','+pfchecks','+cases','internal'};
hits = strings(0,1);
for d=1:numel(dirs)
    fl = dir(fullfile(root,dirs{d},'**','*.m'));
    for k=1:numel(fl)
        p = fullfile(fl(k).folder,fl(k).name);
        src = fileread(p);
        % a CALL, not the function's own definition line
        calls = regexp(src,'[^a-zA-Z0-9_]kundur_ex126_book_e123_ssa\s*\(','once');
        if ~isempty(calls) && isempty(regexp(src,'^function.*kundur_ex126_book_e123_ssa','once'))
            hits(end+1,1) = string(p); %#ok<AGROW>
        end
    end
end
verifyEmpty(testCase,hits,'Production code must not call the calibrated kundur_ex126_book_e123_ssa wrapper.');
end
