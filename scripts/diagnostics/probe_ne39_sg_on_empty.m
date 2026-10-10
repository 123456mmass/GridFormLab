function probe_ne39_sg_on_empty()
pf_init_paths();
evaluate('1sg_9ibr',{},true);
evaluate('1sg_9ibr',{'IBR32'},true);
evaluate('5sg_5ibr',{},true);
evaluate('5sg_5ibr',{'IBR34','IBR36'},false);
end

function evaluate(composition,ids,sg_online)
if composition=="1sg_9ibr"
    s = cases.scenario_ne39_1sg_9ibr(struct('study_capability',true));
else
    s = cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
end
selected = zeros(1,numel(ids));
for k = 1:numel(ids)
    selected(k) = find(strcmp({s.resources.resource_id},ids{k}),1);
end
owner = find(strcmp({s.resources.resource_id},'SG31'),1);
if ~sg_online, owner = min(selected); end
cand = struct('selected_gfm_indices',selected,'n_gfm_required',numel(selected), ...
    'reference_resource_index',owner);
c = stability.ibr_candidate_evaluate(s.case_data,s.resources,cand, ...
    struct(),s.case_data.selector.gamma_req_rad_per_s,struct('sg_online',sg_online));
fprintf('%s sg_online=%d ids=%s feasible=%d zeta=%g omega=%g id=%s\n', ...
    composition,sg_online,strjoin(ids,','),c.feasible,field_or(c,'zeta_worst'), ...
    field_or(c,'omega'),c.failure_id);
end

function v = field_or(s,name)
v = NaN;
if isfield(s,name) && ~isempty(s.(name)), v = s.(name); end
end
