function opt = normalize_ibr_mode_selection(opt)
%NORMALIZE_IBR_MODE_SELECTION Make interactive RMS10 GFM/GFL fields coherent.
% Explicit indices win when their cardinality matches the requested count;
% otherwise the first N eligible resources are selected deterministically.
% This is UI configuration mapping, not a numerical fallback.

eligible = 2:5;
n = opt.initial_gfm_count;
if ~(isscalar(n) && isfinite(n) && n == fix(n) && n >= 0 && n <= numel(eligible))
    error('wizard:normalize_ibr_mode_selection:initialGfmCount', ...
        'Initial GFM count must be an integer from 0 through 4.');
end
% The mode selector owns the complement atomically.  Dialogs may display and
% validate both counts, but stale caller/default GFL counts cannot make a
% newly selected GFM map internally inconsistent.
ngfl = numel(eligible) - n;
idx = opt.initial_gfm_indices(:).';
valid = numel(idx) == n && numel(unique(idx)) == numel(idx) && ...
    all(ismember(idx, eligible));
if ~valid, idx = eligible(1:n); end
opt.initial_gfm_indices = idx;
opt.initial_gfl_count = ngfl;
if isempty(idx)
    opt.initial_reference_resource_index = [];
elseif isempty(opt.initial_reference_resource_index) || ...
        ~ismember(opt.initial_reference_resource_index, idx)
    opt.initial_reference_resource_index = idx(1);
end
end
