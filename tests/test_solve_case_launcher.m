function tests=test_solve_case_launcher
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_pf_launcher_and_log(testCase)
r=solve_case('analysis','pf','case','ieee5', ...
    'options',struct('verbose',false,'plot_results',false));
verifyTrue(testCase,r.converged);
verifyEqual(testCase,r.launcher.analysis,'pf');
verifyTrue(testCase,isfile(r.launcher.log_file));
text=fileread(r.launcher.log_file);
verifyNotEmpty(testCase,strfind(text,'IN-HOUSE ANALYSIS LAUNCHER')); %#ok<STRIFCND>
verifyNotEmpty(testCase,strfind(text,'STATUS: COMPLETE')); %#ok<STRIFCND>
end
