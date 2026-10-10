function tests = test_studio_no_wizard_dependency()
%TEST_STUDIO_NO_WIZARD_DEPENDENCY  +studio must never reference the wizard.
%   The studio dispatches through studio.run_analysis, which reproduces the
%   three production call sites directly.  A source scan over every .m under
%   +studio/ (technique: fileread + contains, as in
%   test_wizard_characterization.m) enforces that no studio file references
%   the wizard package -- no shared-request plumbing, no defaults table, no
%   dispatch, nothing.
%
%   See also: studio.RUN_ANALYSIS.
tests = functiontests(localfunctions);
end

function test_no_wizard_token_in_studio_sources(tc)
repo = fileparts(fileparts(mfilename('fullpath')));
files = [dir(fullfile(repo, '+studio', '*.m')); ...
         dir(fullfile(repo, '+studio', '+ui', '*.m'))];
tc.verifyGreaterThan(numel(files), 0, 'found +studio sources to scan');
for k = 1:numel(files)
    src = fileread(fullfile(files(k).folder, files(k).name));
    tc.verifyFalse(contains(src, 'wizard.'), ...
        sprintf('+studio file %s references the wizard package', files(k).name));
end
end

function test_run_analysis_is_the_only_dispatch_in_studio(tc)
repo = fileparts(fileparts(mfilename('fullpath')));
files = [dir(fullfile(repo, '+studio', '*.m')); ...
         dir(fullfile(repo, '+studio', '+ui', '*.m'))];
for k = 1:numel(files)
    if strcmp(files(k).name, 'run_analysis.m')
        continue
    end
    src = fileread(fullfile(files(k).folder, files(k).name));
    % Only run_analysis may name the production solver entries.  A second
    % dispatch sneaking into the UI layer is exactly what the shared-
    % dispatcher rule forbids.
    tc.verifyFalse(contains(src, 'stability.multicase_sssa'), ...
        sprintf('%s must not dispatch sssa itself', files(k).name));
    tc.verifyFalse(contains(src, 'stability.ts_simulate'), ...
        sprintf('%s must not dispatch ts itself', files(k).name));
    tc.verifyFalse(contains(src, 'pfsolver.pf_method_strategy'), ...
        sprintf('%s must not dispatch pf itself', files(k).name));
end
end
