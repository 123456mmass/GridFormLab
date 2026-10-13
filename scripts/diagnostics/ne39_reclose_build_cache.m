function note = ne39_reclose_build_cache(evidence_folder)
%NE39_RECLOSE_BUILD_CACHE Write a replay cache for an ALREADY-FINISHED run.
%
%   note = ne39_reclose_build_cache(EVIDENCE_FOLDER)
%
% Loads <FOLDER>/raw.mat once and calls ne39_replay_cache_write to produce
% <FOLDER>/replay_cache.mat for fast presentation replays.
%
% This is the back-fill path for runs completed before the probe wrote the
% cache itself. Loading the full artifact is slow by construction (measured
% ~390 s for a 1.8 GB NE39 raw.mat on MATLAB R2026b); the resulting cache loads
% in about a second. Prefer letting ne39_reclose_applied_probe write the cache
% during the run, where the arrays are already in memory and the extra cost is
% negligible.
%
% No simulation runs here and no gate is touched: the cache is a view of the
% stored result.
%
% See also ne39_replay_cache_write, ne39_reclose_demo_cached.

arguments
    evidence_folder (1,1) string
end
raw_file = fullfile(evidence_folder,'raw.mat');
assert(isfile(raw_file),'ne39_reclose_build_cache:missingRaw', ...
    'No raw.mat in %s',evidence_folder);
fprintf('loading %s (%.1f MB); this is the slow step by construction ...\n', ...
    raw_file,dir(raw_file).bytes/1e6);
t0 = tic;
S = load(raw_file,'request','result','elapsed');
fprintf('  loaded in %.1f s\n',toc(t0));
note = ne39_replay_cache_write(evidence_folder,S.result,S.request,S.elapsed);
fprintf('replay cache %s\n',note);
end
