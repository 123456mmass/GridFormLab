function root_dir = pf_init_paths()
%PF_INIT_PATHS Add internal toolbox subfolders to the MATLAB path.

persistent initialized cached_root

root_dir = fileparts(mfilename('fullpath'));
internal_dir = fullfile(root_dir, 'internal');
compat_dir = fullfile(root_dir, 'compat');
scripts_dir = fullfile(root_dir, 'scripts');
managed_dirs = {internal_dir, compat_dir, scripts_dir};
path_text = [path pathsep];
path_missing = any(cellfun(@(d) ~contains(path_text,[d pathsep]),managed_dirs));
if isempty(initialized) || ~initialized || ~strcmp(cached_root, root_dir) || path_missing
    addpath(genpath(internal_dir));
    addpath(genpath(compat_dir));
    addpath(genpath(scripts_dir));
    addpath(fullfile(root_dir, 'docs'));
    initialized = true;
    cached_root = root_dir;
end
end
