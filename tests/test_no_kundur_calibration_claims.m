function tests = test_no_kundur_calibration_claims()
%TEST_NO_KUNDUR_CALIBRATION_CLAIMS Guard: calibrated/legacy Kundur wrappers
%   are not called from the production path, and production/report docs do
%   not present a Kundur <0.5% match as validation.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_production_path_does_not_call_calibrated_wrappers(testCase)
% Recursively scan every .m file under the project root (except legacy/, 
% .git/, docs/probes/) for CALLS to the calibrated Kundur wrappers.
root = fileparts(fileparts(mfilename('fullpath')));
fl = dir(fullfile(root,'**','*.m'));
wrappers = {'kundur_ex126_kundur_ssa','kundur_ex126_book_e123_ssa', ...
    'kundur_ex126_genrou_ssa','kundur_ex126_sixth_order_ssa', ...
    'kundur_ex126_classical_analysis','kundur_e123_family_compare', ...
    'kundur_e123_primitive_compare','genpj6_dae','ts_simulate_genpj6'};
hits = strings(0,1);
for j=1:numel(fl)
    path_f = fullfile(fl(j).folder, fl(j).name);
    if contains(path_f, [filesep 'legacy' filesep]) || contains(path_f, [filesep 'legacy']) ...
            || contains(path_f, [filesep '.git' filesep]) || contains(path_f, [filesep 'probes' filesep])
        continue;
    end
    src = fileread(path_f);
    for q=1:numel(wrappers)
        wn = wrappers{q};
        % a CALL (name followed by '('), whole-word, not a quoted listing.
        call_pat = ['[^a-zA-Z0-9_]' wn '\s*\('];
        if ~isempty(regexp(src, call_pat, 'once'))
            hits(end+1,1) = string(sprintf('%s: %s', path_f, wn)); %#ok<AGROW>
        end
    end
end
testCase.verifyEmpty(hits, ...
    'Production .m files must not call calibrated/legacy Kundur wrappers.');
end

function test_no_kundur_validation_claim_in_production_docs(testCase)
% Production/report docs must not contain a Kundur `<0.5%` validation
% claim (the calibrated reproduction docs live in legacy/). The guard flags
% any literal `<0.5%` / `< 0.5 %` in production .md so the rule is
% unambiguous (no fuzzy allowlist).
root = fileparts(fileparts(mfilename('fullpath')));
scan_dirs = {'docs','+cases','+stability','+pfsolver','internal','compat','scripts','tests'};
hits = strings(0,1);
for d=1:numel(scan_dirs)
    base = fullfile(root, scan_dirs{d});
    if ~exist(base,'dir'), continue; end
    fl = dir(fullfile(base,'**','*.md'));
    for k=1:numel(fl)
        p = fullfile(fl(k).folder, fl(k).name);
        if contains(p, [filesep 'legacy' filesep]), continue; end
        src = fileread(p);
        if ~isempty(regexp(src, '<\s*0\.5\s*%', 'once'))
            hits(end+1,1) = string(p); %#ok<AGROW>
        end
    end
end
testCase.verifyEmpty(hits, ...
    'Production docs must not contain a Kundur <0.5% claim (move to legacy/).');
end
