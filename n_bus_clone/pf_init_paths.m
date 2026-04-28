function root_dir = pf_init_paths()
%PF_INIT_PATHS Add internal toolbox subfolders to the MATLAB path.

persistent initialized cached_root

root_dir = fileparts(mfilename('fullpath'));
if isempty(initialized) || ~initialized || ~strcmp(cached_root, root_dir)
    addpath(genpath(fullfile(root_dir, 'internal')));
    addpath(fullfile(root_dir, 'docs'));
    initialized = true;
    cached_root = root_dir;
end
end
