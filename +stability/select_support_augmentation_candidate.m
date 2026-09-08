function [candidate, found, audit] = select_support_augmentation_candidate( ...
        selector_table,current_gfm,online_ibr)
%SELECT_SUPPORT_AUGMENTATION_CANDIDATE  Smallest authenticated GFM superset.
%   This is the pure ranking step for SG-off severity support. AGSI decides
%   WHEN more forming support is required; the authenticated selector table
%   decides WHICH strict superset is admissible. Ranking is deterministic:
%     fewer added GFMs -> larger SSSA margin -> resource-ID tuple -> ref ID.
%   No candidate is fabricated and no equilibrium/SSSA gate is relaxed here.
%
%   ONLINE_IBR (optional) lists the device indices still in service. A row
%   whose selected set or reference names a device outside it is not a
%   destination: committing it would publish ownership and a certified input
%   for a device that is gone (the defect former_outage exposed at t=64.037,
%   where the only feasible superset of [3 4] named the tripped IBR2). When
%   no survivor-only superset exists, found=false is the honest answer and
%   the supervisor holds its incumbent set; it must NOT fall back to a row
%   containing an out-of-service device.

arguments
    selector_table struct
    current_gfm (1,:) double
    online_ibr (1,:) double = []
end
current_gfm=unique(current_gfm,'stable');
if any(~isfinite(current_gfm)) || any(current_gfm<1) || ...
        any(current_gfm~=fix(current_gfm))
    error('stability:select_support_augmentation_candidate:badCurrent', ...
        'current_gfm must contain unique positive integer device indices.');
end
online_ibr=unique(online_ibr,'stable');
if any(~isfinite(online_ibr)) || any(online_ibr<1) || ...
        any(online_ibr~=fix(online_ibr))
    error('stability:select_support_augmentation_candidate:badOnline', ...
        'online_ibr must contain unique positive integer device indices.');
end
filter_online=~isempty(online_ibr);
if ~isfield(selector_table,'sg_off') || ...
        ~isfield(selector_table.sg_off,'configurations') || ...
        ~isstruct(selector_table.sg_off.configurations)
    error('stability:select_support_augmentation_candidate:badTable', ...
        'selector_table.sg_off.configurations is required.');
end

cfgs=selector_table.sg_off.configurations;
eligible=[];
for k=1:numel(cfgs)
    c=cfgs(k);
    if ~isfield(c,'feasible') || ~isequal(c.feasible,true) || ...
            ~isfield(c,'ready_to_commit') || ~isequal(c.ready_to_commit,true) || ...
            ~isfield(c,'selected_gfm_indices')
        continue;
    end
    selected=unique(c.selected_gfm_indices(:).','stable');
    if numel(selected)~=numel(c.selected_gfm_indices) || ...
            ~all(ismember(current_gfm,selected)) || ...
            numel(selected)<=numel(current_gfm)
        continue;
    end
    if filter_online
        % Every selected former must still be in service, and the reference
        % must be a member of the selected set AND a survivor. A row whose
        % reference is a device that just left is not a destination -- the
        % same two predicates select_post_outage_candidate enforces.
        if ~all(ismember(selected,online_ibr))
            continue;
        end
        if ~isfield(c,'reference_resource_index') || ...
                ~isscalar(c.reference_resource_index) || ...
                ~isfinite(c.reference_resource_index) || ...
                ~ismember(c.reference_resource_index,selected) || ...
                ~ismember(c.reference_resource_index,online_ibr)
            continue;
        end
    end
    eligible(end+1)=k; %#ok<AGROW>
end

candidate=struct();
if filter_online
    audit=struct('current_gfm_indices',current_gfm, ...
        'online_ibr_indices',online_ibr, ...
        'eligible_configuration_indices',eligible,'selected_configuration_index',NaN, ...
        'reason','NO_STRICT_FEASIBLE_SURVIVOR_SUPERSET');
else
    audit=struct('current_gfm_indices',current_gfm, ...
        'eligible_configuration_indices',eligible,'selected_configuration_index',NaN, ...
        'reason','NO_STRICT_FEASIBLE_SUPERSET');
end
found=~isempty(eligible);
if ~found, return; end

best=eligible(1);
for k=eligible(2:end)
    if precedes(cfgs(k),cfgs(best)), best=k; end
end
candidate=cfgs(best);
audit.selected_configuration_index=best;
audit.reason='MINIMUM_AUTHENTICATED_FEASIBLE_SUPERSET';
end

function tf=precedes(a,b)
sa=a.selected_gfm_indices(:).'; sb=b.selected_gfm_indices(:).';
if numel(sa)~=numel(sb), tf=numel(sa)<numel(sb); return; end
ma=margin_value(a); mb=margin_value(b);
if ma~=mb, tf=ma>mb; return; end
n=min(numel(sa),numel(sb));
for q=1:n
    if sa(q)~=sb(q), tf=sa(q)<sb(q); return; end
end
ra=reference_value(a); rb=reference_value(b);
tf=ra<rb;
end

function v=margin_value(c)
v=-Inf;
if isfield(c,'margin') && isscalar(c.margin) && isfinite(c.margin), v=c.margin; end
end

function v=reference_value(c)
v=Inf;
if isfield(c,'reference_resource_index') && ...
        isscalar(c.reference_resource_index) && isfinite(c.reference_resource_index)
    v=c.reference_resource_index;
end
end
