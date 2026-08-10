function [candidate, found, audit] = select_support_release_candidate(selector_table,current_gfm)
%SELECT_SUPPORT_RELEASE_CANDIDATE  Smallest authenticated nonempty GFM subset.
%   This is the pure ranking step for SG-off severity release. AGSI decides
%   WHEN forming support may be reduced; the authenticated selector table
%   decides WHICH strict, nonempty subset remains admissible. Ranking is:
%     fewer retained GFMs -> larger SSSA margin -> resource tuple -> ref ID.
%   The nonempty requirement preserves a grid-forming reference while every
%   synchronous generator in the island is offline.

arguments
    selector_table struct
    current_gfm (1,:) double
end
current_gfm=unique(current_gfm,'stable');
if isempty(current_gfm) || any(~isfinite(current_gfm)) || any(current_gfm<1) || ...
        any(current_gfm~=fix(current_gfm))
    error('stability:select_support_release_candidate:badCurrent', ...
        'current_gfm must contain unique positive integer device indices.');
end
if ~isfield(selector_table,'sg_off') || ...
        ~isfield(selector_table.sg_off,'configurations') || ...
        ~isstruct(selector_table.sg_off.configurations)
    error('stability:select_support_release_candidate:badTable', ...
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
    if isempty(selected) || numel(selected)~=numel(c.selected_gfm_indices) || ...
            ~all(ismember(selected,current_gfm)) || ...
            numel(selected)>=numel(current_gfm)
        continue;
    end
    eligible(end+1)=k; %#ok<AGROW>
end

candidate=struct();
found=~isempty(eligible);
audit=struct('current_gfm_indices',current_gfm, ...
    'eligible_configuration_indices',eligible,'selected_configuration_index',NaN, ...
    'reason','NO_STRICT_FEASIBLE_NONEMPTY_SUBSET');
if ~found, return; end

best=eligible(1);
for k=eligible(2:end)
    if precedes(cfgs(k),cfgs(best)), best=k; end
end
candidate=cfgs(best);
audit.selected_configuration_index=best;
audit.reason='MINIMUM_AUTHENTICATED_FEASIBLE_NONEMPTY_SUBSET';
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
