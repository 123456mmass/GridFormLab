function feat = ai_extract_features(snap, window_idx, committed_buses)
%AI_EXTRACT_FEATURES  Physics indices over one transient window, per IBR bus.
%
%   FEAT = ai.ai_extract_features(SNAP, WINDOW_IDX)
%   FEAT = ai.ai_extract_features(SNAP, WINDOW_IDX, COMMITTED_BUSES)
%
%   WINDOW_IDX selects the samples of the snapshot the decision is made from --
%   typically the first 50-100 ms after the trigger. Everything below is read
%   from that window only; no sample outside it can influence the verdict.
%
%   WHAT IS RANKED ON. ESCR and voltage drop are both summarized by the window
%   MEDIAN, not by the last sample and not by the extreme. A 100 ms window
%   during a fault transient regularly contains one spiky sample; ranking on
%   the last sample would let that sample decide, and ranking on the minimum
%   would act on a state the grid may already have left. The median is the
%   value the window actually held. FEAT.buses keeps min, max and last beside
%   it, so a reader can see how much the choice mattered.
%
%   FEAT fields:
%     t_start_s, t_end_s, n_samples, f0_Hz
%     f_end_Hz, f_nadir_Hz, rocof_peak_Hz_s, rocof_end_Hz_s, rocof_source
%     V_min_pu, t_vmin_s
%     buses           struct array, one entry per IBR bus:
%                       bus_id, device_id, mode, escr_median, escr_min,
%                       escr_max, escr_end, V_median_pu, V_min_pu,
%                       V_drop_pu, V_drop_source
%     rank_by_escr    IBR indices, lowest window-median ESCR first
%     rank_by_vdrop   IBR indices, deepest window-median voltage drop first
%     gfm_indices     IBR indices already forming at window end, counting BOTH
%                     the run's own modes and anything the supervisor has
%                     already committed (COMMITTED_BUSES)
%     committed_indices  the subset the supervisor itself committed
%     rule_primary    IBR index the rule-based selector would commit
%     escr_source, notes
%
%   COMMITTED_BUSES is what closes the loop. The snapshot records the modes the
%   ENGINE ran, not the modes the supervisor has since imposed; without this
%   argument a committed bus looks idle again at the next trigger and the
%   supervisor spends its next selection re-selecting it. Passing its own
%   committed buses is what makes the exclusion real across triggers.
%
%   See also ai.ai_build_prompt, ai.ai_fallback_selector.

arguments
    snap struct
    window_idx (1,:) double {mustBePositive, mustBeInteger}
    committed_buses (1,:) double = []
end

w = window_idx(:)';
if isempty(w) || any(w > snap.n)
    error('ai:ai_extract_features:badWindow', ...
        'window_idx must be non-empty and lie within 1..%d.', snap.n);
end
% One check naming the whole contract, rather than a defensive default at each
% use site: a snapshot that skipped ai.snapshot_from_state should be refused
% here, not silently produce a feature set with quietly-missing indices.
req = {'t','n','bus_ids','V_bus_pu','V_min_pu','V_ibr_pu','ibr_bus_ids', ...
    'f_coi_Hz','rocof_Hz_s','rocof_source','S','escr','escr_source','modes_ibr'};
for k = 1:numel(req)
    if ~isfield(snap, req{k})
        error('ai:ai_extract_features:incompleteSnapshot', ...
            ['SNAP is missing "%s". Build it with ai.snapshot_from_state ' ...
             'or ai.snapshot_from_cache.'], req{k});
    end
end

m = numel(snap.ibr_bus_ids);
feat = struct();
feat.t_start_s = snap.t(w(1));
feat.t_end_s = snap.t(w(end));
feat.n_samples = numel(w);
% Nominal frequency, carried as a field rather than assumed at each use site,
% so a 50 Hz case would be a change to the options and not to this file.
feat.f0_Hz = 60.0;

% --- frequency and its rate ----------------------------------------------
fw = snap.f_coi_Hz(w);
roc = snap.rocof_Hz_s(w);
feat.f_end_Hz = fw(end);
if any(isfinite(fw))
    feat.f_nadir_Hz = min(fw(isfinite(fw)));
else
    feat.f_nadir_Hz = NaN;
end
if any(isfinite(roc))
    [~, j] = max(abs(roc));
    feat.rocof_peak_Hz_s = roc(j);
else
    feat.rocof_peak_Hz_s = NaN;
end
feat.rocof_end_Hz_s = roc(end);
feat.rocof_source = unique(snap.rocof_source(w));

% --- voltage --------------------------------------------------------------
Vw = snap.V_min_pu(w);
feat.V_min_pu = min(Vw);
[~, j] = min(Vw);
feat.t_vmin_s = snap.t(w(j));

% --- per-bus table --------------------------------------------------------
buses = repmat(struct('bus_id', NaN, 'device_id', "", 'mode', "", ...
    'escr_median', NaN, 'escr_min', NaN, 'escr_max', NaN, 'escr_end', NaN, ...
    'V_median_pu', NaN, 'V_min_pu', NaN, ...
    'V_drop_pu', NaN), 1, m);
has_healthy = isfield(snap,'healthy_V') && ~isempty(snap.healthy_V);
committed = ismember(snap.ibr_bus_ids, committed_buses);
for k = 1:m
    buses(k).bus_id = snap.ibr_bus_ids(k);
    if isfield(snap,'device_ids') && numel(snap.device_ids) >= ...
            snap.ibr_device_indices(k)
        buses(k).device_id = string(snap.device_ids{snap.ibr_device_indices(k)});
    end
    if ~isempty(snap.modes_ibr)
        buses(k).mode = string(snap.modes_ibr{k, w(end)});
    end
    e = snap.escr(k, w);
    if any(isfinite(e))
        buses(k).escr_median = median(e(isfinite(e)));
        buses(k).escr_min = min(e(isfinite(e)));
        buses(k).escr_max = max(e(isfinite(e)));
    end
    buses(k).escr_end = snap.escr(k, w(end));
    v = snap.V_ibr_pu(k, w);
    if any(isfinite(v))
        buses(k).V_median_pu = median(v(isfinite(v)));
        buses(k).V_min_pu = min(v(isfinite(v)));
    end
end
if has_healthy
    for k = 1:m
        r = find(snap.healthy_bus_ids == snap.ibr_bus_ids(k), 1);
        if ~isempty(r) && isfinite(buses(k).V_median_pu)
            buses(k).V_drop_pu = snap.healthy_V(r) - buses(k).V_median_pu;
        end
    end
end
feat.buses = buses;

% --- rankings -------------------------------------------------------------
feat.rank_by_escr = rank_ascending([buses.escr_median]);
feat.rank_by_vdrop = rank_descending([buses.V_drop_pu]);

gfm = false(1, m);
for k = 1:m
    gfm(k) = strcmpi(buses(k).mode, "gfm");
end
% The supervisor's own commitments are folded into the mode the prompt and the
% selector both see, so "already forming" means it for both sources.
for k = find(committed)
    buses(k).mode = "gfm";
end
gfm = gfm | committed;
feat.buses = buses;
feat.gfm_indices = find(gfm);
feat.committed_indices = find(committed);

% --- rule-based primary, for the fallback and as a cross-check -------------
% A bus already forming cannot be the answer: switching it again is a no-op,
% and spending the one permitted selection on it would leave the emergency
% unanswered. The rule skips them; the prompt states the same constraint.
feat.rule_primary = first_not_forming(feat.rank_by_escr, gfm);

feat.escr_source = snap.escr_source;
feat.notes = notes_for(snap, feat);
end

% =========================================================================
function r = rank_ascending(v)
%RANK_ASCENDING  Indices by ascending value, NaN last, ties by index.
idx = 1:numel(v);
key = v;
key(~isfinite(key)) = inf;
[~, order] = sortrows([key(:), idx(:)], [1 2]);
r = order(:)';
end

function r = rank_descending(v)
%RANK_DESCENDING  Indices by descending value, NaN last, ties by index.
idx = 1:numel(v);
key = v;
key(~isfinite(key)) = -inf;
[~, order] = sortrows([-key(:), idx(:)], [1 2]);
r = order(:)';
end

function k = first_not_forming(rank, gfm)
%FIRST_NOT_FORMING  Highest-ranked index that is not already forming.
k = NaN;
for q = rank
    if ~gfm(q)
        k = q;
        return;
    end
end
end

function c = notes_for(snap, feat)
%NOTES_FOR  Caveats a reader (or the model) must not have to infer.
c = {};
if snap.escr_source == "unavailable"
    c{end+1} = ['ESCR is unavailable for this run; a selection claimed to ' ...
        'rest on grid strength would rest on nothing.'];
end
if any(snap.rocof_source == "finite_difference")
    c{end+1} = ['Some or all RoCoF values are finite differences of the ' ...
        'recorded frequency, not the engine''s analytic rate; the analytic ' ...
        'trace is NaN while no GFM is online.'];
end
if all(~isfinite(snap.S))
    c{end+1} = ['Severity S is unavailable (no pre-disturbance voltage ' ...
        'profile in this cache); the production trigger rule cannot fire.'];
end
if ~isempty(feat.gfm_indices)
    c{end+1} = sprintf(['%d converter(s) are already forming at the window ' ...
        'end and are excluded from the rule-based primary.'], ...
        numel(feat.gfm_indices));
end
if isfield(feat,'committed_indices') && ~isempty(feat.committed_indices)
    c{end+1} = sprintf(['%d of them were committed by this supervisor at an ' ...
        'earlier trigger, not by the underlying run.'], ...
        numel(feat.committed_indices));
end
end
