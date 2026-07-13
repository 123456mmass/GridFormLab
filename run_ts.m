%% RUN_TS Interactive in-house Transient Stability launcher.
% Select a case first. solve_case then opens the case-aware TS settings
% dialog, including the valid external fault-bus IDs for that case.
% The selected-case result is saved as ts_result in the workspace.

launcher_root = fileparts(mfilename('fullpath'));
if isempty(launcher_root), launcher_root = pwd; end
cd(launcher_root);
pf_init_paths;

% Multiple project worktrees may be open in one MATLAB session. Force this
% launcher's scripts directory to the front and discard stale plot/launcher
% function caches before opening the case selector.
addpath(fullfile(launcher_root,'scripts'),'-begin');
close all force;
clear solve_case plot_ts_result;
rehash;

plotter_path = which('plot_ts_result');
expected_plotter = fullfile(launcher_root,'scripts','plot_ts_result.m');
if ~strcmp(plotter_path,expected_plotter)
    error('run_ts:wrongPlotterPath', ...
        'Expected plotter %s but MATLAB resolved %s.', ...
        expected_plotter,plotter_path);
end
fprintf('TS plotter: %s\n',plotter_path);

% Flow: choose case -> edit case-aware TS settings -> run.
ts_result = solve_case('analysis','ts');
