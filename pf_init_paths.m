function root_dir = pf_init_paths()
%PF_INIT_PATHS Add internal toolbox subfolders to the MATLAB path.

persistent initialized cached_root

root_dir = fileparts(mfilename('fullpath'));
internal_dir = fullfile(root_dir, 'internal');
path_missing = ~contains([path pathsep], [internal_dir pathsep]);
if isempty(initialized) || ~initialized || ~strcmp(cached_root, root_dir) || path_missing
    addpath(genpath(internal_dir));
    addpath(fullfile(root_dir, 'docs'));
    initialized = true;
    cached_root = root_dir;
end
end
