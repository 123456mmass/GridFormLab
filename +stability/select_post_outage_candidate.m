function [candidate, found, audit] = select_post_outage_candidate( ...
        selector_table, surviving_ibr, current_gfm)
%SELECT_POST_OUTAGE_CANDIDATE  Authenticated GFM set after a converter outage.
%   [CANDIDATE, FOUND, AUDIT] = select_post_outage_candidate(SELECTOR_TABLE,
%   SURVIVING_IBR, CURRENT_GFM) is the pure ranking step for the loss of a
%   converter while every synchronous machine in the island is offline. The
%   outage decides WHICH devices remain; the authenticated SG_OFF selector table
%   decides WHICH configuration of the survivors is admissible. Nothing is
%   fabricated and no equilibrium or SSSA gate is relaxed here.
%
%   Why this is not select_support_augmentation_candidate or
%   select_support_release_candidate: both of those express a SEVERITY decision
%   and enforce a strict set relation against the incumbent GFM set -- a
%   superset for augmentation (select_support_augmentation_candidate.m:36-39),
%   a strict nonempty subset for release (select_support_release_candidate.m:37-40).
%   An outage is neither. The device is simply gone, and the admissible
%   destination may add a former, drop one, or keep the same count while
%   changing which devices hold it. The one hard constraint is that every
%   selected device must still be in service.
%
%   Inputs:
%     selector_table  the precomputed authenticated table (needs .sg_off)
%     surviving_ibr   device indices still in service after the outage
%     current_gfm     device indices in GFM before the outage (audit + ranking
%                     tie-break only; it does NOT constrain the result)
%
%   Ranking, deterministic and identical in spirit to the severity selectors:
%     fewer runtime mode changes -> fewer GFMs -> larger stability margin ->
%     resource tuple -> reference ID.
%   "Fewer runtime mode changes" leads because the least-intervention principle
%   applies here too: a destination that leaves the surviving converters in the
%   modes they are already in perturbs fewer integrators than one that reshuffles
%   them, and the incumbent-arriving-state hazard recorded in AGSI-2026-08-14-01
%   is driven by exactly that kind of perturbation.
%
%   FOUND=false is a legitimate and expected outcome: the SG_OFF table is built
%   with cmin=1 (ibr_selector_table.m), so if the lost converter was the only
%   voltage-forming source there is no zero-GFM row to fall back to and no
%   admissible destination exists. The caller must fail closed on that, not
%   improvise one.
%
%   Classification: PROJECT_DERIVED ranking over cached authenticated evidence.
%   Pure function: no solver, no equilibrium, no SSSA, no state is touched.

arguments
    selector_table struct
    surviving_ibr (1,:) double
    current_gfm (1,:) double = []
end

surviving_ibr = unique(surviving_ibr,'stable');
if any(~isfinite(surviving_ibr)) || any(surviving_ibr < 1) || ...
        any(surviving_ibr ~= fix(surviving_ibr))
    error('stability:select_post_outage_candidate:badSurviving', ...
        'surviving_ibr must contain unique positive integer device indices.');
end
current_gfm = unique(current_gfm,'stable');
if any(~isfinite(current_gfm)) || any(current_gfm < 1) || ...
        any(current_gfm ~= fix(current_gfm))
    error('stability:select_post_outage_candidate:badCurrent', ...
        'current_gfm must contain unique positive integer device indices.');
end
if ~isfield(selector_table,'sg_off') || ...
        ~isfield(selector_table.sg_off,'configurations') || ...
        ~isstruct(selector_table.sg_off.configurations)
    error('stability:select_post_outage_candidate:badTable', ...
        'selector_table.sg_off.configurations is required.');
end

cfgs = selector_table.sg_off.configurations;
eligible = [];
for k = 1:numel(cfgs)
    c = cfgs(k);
    if ~isfield(c,'feasible') || ~isequal(c.feasible,true) || ...
            ~isfield(c,'ready_to_commit') || ~isequal(c.ready_to_commit,true) || ...
            ~isfield(c,'selected_gfm_indices')
        continue;
    end
    selected = unique(c.selected_gfm_indices(:).','stable');
    if isempty(selected) || numel(selected) ~= numel(c.selected_gfm_indices)
        continue;
    end
    % Every selected former must have survived the outage. This is the whole
    % constraint the outage imposes.
    if ~all(ismember(selected,surviving_ibr))
        continue;
    end
    % The reference must be a member of the selected set AND a survivor. A row
    % whose reference is the device that just left is not a destination.
    if ~isfield(c,'reference_resource_index') || ...
            ~isscalar(c.reference_resource_index) || ...
            ~isfinite(c.reference_resource_index) || ...
            ~ismember(c.reference_resource_index,selected) || ...
            ~ismember(c.reference_resource_index,surviving_ibr)
        continue;
    end
    eligible(end+1) = k; %#ok<AGROW>
end

candidate = struct();
found = ~isempty(eligible);
audit = struct('surviving_ibr_indices',surviving_ibr, ...
    'current_gfm_indices',current_gfm, ...
    'eligible_configuration_indices',eligible, ...
    'selected_configuration_index',NaN, ...
    'reason','NO_AUTHENTICATED_FEASIBLE_SURVIVOR_CONFIGURATION');
if ~found, return; end

best = eligible(1);
for k = eligible(2:end)
    if precedes(cfgs(k),cfgs(best),current_gfm), best = k; end
end
candidate = cfgs(best);
audit.selected_configuration_index = best;
audit.reason = 'MINIMUM_INTERVENTION_AUTHENTICATED_SURVIVOR_CONFIGURATION';
end

% =========================================================================
function tf = precedes(a,b,current_gfm)
%PRECEDES  Deterministic total order over admissible destinations.
sa = unique(a.selected_gfm_indices(:).','stable');
sb = unique(b.selected_gfm_indices(:).','stable');

% 1. fewer runtime mode changes among the devices that remain in service.
ca = numel(setxor(sa,current_gfm));
cb = numel(setxor(sb,current_gfm));
if ca ~= cb, tf = ca < cb; return; end

% 2. fewer grid-forming units.
if numel(sa) ~= numel(sb), tf = numel(sa) < numel(sb); return; end

% 3. larger stability margin. `margin` = -omega - gamma_req, so larger is
%    better damped -- the same comparison the severity selectors make.
ma = margin_value(a); mb = margin_value(b);
if ma ~= mb, tf = ma > mb; return; end

% 4. resource tuple, then reference ID. Both are pure tie-breaks whose only
%    purpose is determinism.
for q = 1:numel(sa)
    if sa(q) ~= sb(q), tf = sa(q) < sb(q); return; end
end
ra = reference_value(a); rb = reference_value(b);
tf = ra < rb;
end

function v = margin_value(c)
% Exactly the reference definition used by the severity selectors
% (select_support_release_candidate.m). `margin` is -omega - gamma_req
% (ibr_candidate_evaluate.m:459), so larger is better damped. No -omega
% fallback: that would order rows by values offset from each other by
% gamma_req.
v = -Inf;
if isfield(c,'margin') && isscalar(c.margin) && isfinite(c.margin)
    v = double(c.margin);
end
end

function v = reference_value(c)
v = Inf;
if isfield(c,'reference_resource_index') && ...
        isscalar(c.reference_resource_index) && ...
        isfinite(c.reference_resource_index)
    v = double(c.reference_resource_index);
end
end
