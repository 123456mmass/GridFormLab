function tests = test_path_bootstrap()
%TEST_PATH_BOOTSTRAP pf_init_paths must repair a removed internal path.
%   fsolve-free contract: only the path-bootstrap behaviour is tested here.
%   The historical fsolve-vs-Newton reference comparison now lives in
%   legacy/test_fsolve_powerflow.m (off the production path).
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_path_bootstrap_repairs_removed_internal_path(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
internal = fullfile(root,'internal');
old = path; %#ok<NASGU>
cleanup = onCleanup(@() path(old)); %#ok<NASGU>
rmpath(genpath(internal));
testCase.verifyEmpty(which('pf_get_option'), 'internal must be off path after rmpath');
pf_init_paths();
testCase.verifyNotEmpty(which('pf_get_option'), 'pf_init_paths must re-add internal');
end
