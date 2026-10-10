function root_dir = pf_init_paths()
%PF_INIT_PATHS Add internal toolbox subfolders to the MATLAB path.

persistent initialized cached_root

root_dir = fileparts(mfilename('fullpath'));
internal_dir = fullfile(root_dir, 'internal');
compat_dir = fullfile(root_dir, 'compat');
scripts_dir = fullfile(root_dir, 'scripts');
% events/ holds the hand-editable event configuration files (evt_*.m). It is a
% PLAIN folder, not the +events package: MATLAB always resolves events.foo to
% the package, so a name in here is only ever reached explicitly -- which is
% why every file in it carries the evt_ prefix, and why +events/list.m fails
% closed unless which('evt_...') resolves inside this folder.
events_dir = fullfile(root_dir, 'events');
managed_dirs = {internal_dir, compat_dir, scripts_dir, events_dir};
path_text = [path pathsep];
path_missing = any(cellfun(@(d) ~contains(path_text,[d pathsep]),managed_dirs));
% The repo root itself must be on the path or package calls made from inside a
% callback (studio.ui.*, cases.*, pfsolver.*, ...) resolve against the current
% folder only -- a GUI launched from another cwd (e.g. Documents/MATLAB) threw
% "Unresolved name 'studio.ui.append_log' / 'cases.case_ne39'" the moment a
% dropdown fired, even though launch() had just run this function.
root_on_path = contains(path_text, [root_dir pathsep]);
if isempty(initialized) || ~initialized || ~strcmp(cached_root, root_dir) || ...
        path_missing || ~root_on_path
    addpath(root_dir);
    addpath(genpath(internal_dir));
    addpath(genpath(compat_dir));
    addpath(genpath(scripts_dir));
    addpath(events_dir);
    addpath(fullfile(root_dir, 'docs'));
    initialized = true;
    cached_root = root_dir;
end
end
