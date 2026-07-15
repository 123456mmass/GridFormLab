function [configured,selection] = ibr_configure_scenario(scenario,opt)
%IBR_CONFIGURE_SCENARIO Resolve the normal-operation GFL/GFM composition.
%   Explicit resource-table indices are honored after capability validation.
%   A count without indices is delegated to ibr_config_selector; there is no
%   first-device fallback. Count zero is valid while an online SG forms the
%   voltage reference.

arguments
    scenario struct
    opt struct = struct()
end

if ~isfield(scenario,'resources') || ~isfield(scenario,'case_data')
    error('stability:ibr_configure_scenario:badScenario', ...
        'scenario.resources and scenario.case_data are required.');
end
resources = scenario.resources;
nr = numel(resources);
eligible = false(1,nr);
for k=1:nr
    r=resources(k);
    eligible(k)=strcmpi(char(r.resource_type),'ibr') && r.initial_online && ...
        r.can_switch_mode && any(strcmpi(string(r.supported_modes),'gfl')) && ...
        any(strcmpi(string(r.supported_modes),'gfm'));
end

has_indices=isfield(opt,'initial_gfm_indices') && ...
    ~isempty(opt.initial_gfm_indices);
has_count=isfield(opt,'initial_gfm_count') && ...
    ~isempty(opt.initial_gfm_count);
has_gfl_count=isfield(opt,'initial_gfl_count') && ...
    ~isempty(opt.initial_gfl_count);
existing=find(arrayfun(@(r) strcmpi(char(r.initial_mode),'gfm'),resources));

selection=struct('source','scenario_default','requested_count',[], ...
    'requested_indices',[],'selected_gfm_indices',existing, ...
    'reference_resource_index',[],'eligible_gfm_indices',find(eligible), ...
    'selector_evaluated',false,'selector_result',struct(), ...
    'candidate_count',0,'equilibrium_evaluations',0,'sssa_evaluations',0, ...
    'ready',true,'failure_id','','failure_reason','');

if ~has_indices && ~has_count
    configured=scenario;
    if ~isempty(existing), selection.reference_resource_index=min(existing); end
    return;
end

if has_count
    count=opt.initial_gfm_count;
    if ~isnumeric(count) || ~isscalar(count) || ~isfinite(count) || ...
            count~=fix(count) || count<0 || count>sum(eligible)
        error('stability:ibr_configure_scenario:badCount', ...
            'initial_gfm_count must be an integer in [0,%d].',sum(eligible));
    end
else
    count=[];
end
if has_gfl_count
    gfl_count=opt.initial_gfl_count;
    if ~isnumeric(gfl_count) || ~isscalar(gfl_count) || ~isfinite(gfl_count) || ...
            gfl_count~=fix(gfl_count) || gfl_count<0 || gfl_count>sum(eligible)
        error('stability:ibr_configure_scenario:badGflCount', ...
            'initial_gfl_count must be an integer in [0,%d].',sum(eligible));
    end
    if has_count && count+gfl_count~=sum(eligible)
        error('stability:ibr_configure_scenario:modeCountMismatch', ...
            'initial_gfm_count + initial_gfl_count must equal %d online IBRs.',sum(eligible));
    end
elseif has_count
    gfl_count=sum(eligible)-count;
else
    gfl_count=[];
end

if has_indices
    selected=reshape(opt.initial_gfm_indices,1,[]);
    if ~isnumeric(selected) || any(~isfinite(selected)) || ...
            any(selected~=fix(selected)) || numel(unique(selected))~=numel(selected) || ...
            any(selected<1 | selected>nr) || any(~eligible(selected))
        error('stability:ibr_configure_scenario:badIndices', ...
            'initial_gfm_indices must be unique eligible resource-table indices.');
    end
    if has_count && count~=numel(selected)
        error('stability:ibr_configure_scenario:countMismatch', ...
            'initial_gfm_count must equal numel(initial_gfm_indices).');
    end
    count=numel(selected);
    selection.source='explicit_indices';
    selection.requested_indices=selected;
elseif count==0
    selected=[];
    selection.source='explicit_count_zero';
else
    sel_opt=struct('n_gfm_required',count,'case_data',scenario.case_data, ...
        'sg_online',true);
    if isfield(opt,'initial_reference_resource_index') && ...
            ~isempty(opt.initial_reference_resource_index)
        sel_opt.reference_resource_index=opt.initial_reference_resource_index;
    end
    selected_result=stability.ibr_config_selector(resources, ...
        struct('case_data',scenario.case_data),scenario,sel_opt);
    selection.source='selector';
    selection.selector_evaluated=true;
    selection.selector_result=selected_result;
    selection.candidate_count=numel(selected_result.configurations);
    if ~isempty(selected_result.configurations)
        selection.equilibrium_evaluations=sum([selected_result.configurations.equilibrium_evaluated]);
        selection.sssa_evaluations=sum([selected_result.configurations.sssa_evaluated]);
    end
    selection.ready=selected_result.ready_to_commit;
    selection.failure_id=selected_result.failure_id;
    if isfield(selected_result,'selected_config') && ...
            isfield(selected_result.selected_config,'reason')
        selection.failure_reason=selected_result.selected_config.reason;
    end
    if ~selection.ready
        configured=scenario;
        selection.requested_count=count;
        selection.selected_gfm_indices=selected_result.selected_gfm_indices;
        selection.reference_resource_index=selected_result.reference_resource_index;
        return;
    end
    selected=selected_result.selected_gfm_indices;
end

selection.requested_count=count;
selection.requested_gfl_count=gfl_count;
selection.selected_gfm_indices=selected;
if isempty(selected)
    reference=[];
elseif isfield(opt,'initial_reference_resource_index') && ...
        ~isempty(opt.initial_reference_resource_index)
    reference=opt.initial_reference_resource_index;
    if ~isscalar(reference) || ~ismember(reference,selected)
        error('stability:ibr_configure_scenario:referenceNotSelected', ...
            'initial_reference_resource_index must be one selected index.');
    end
elseif selection.selector_evaluated
    reference=selection.selector_result.reference_resource_index;
else
    reference=min(selected);
end
selection.reference_resource_index=reference;

resources_out=resources;
for k=find(eligible)
    if ismember(k,selected), resources_out(k).initial_mode='gfm';
    else, resources_out(k).initial_mode='gfl'; end
end
scenario_opt=scenario.scenario_opt;
if isempty(selected)
    if isfield(scenario_opt,'committed_selection')
        scenario_opt=rmfield(scenario_opt,'committed_selection');
    end
else
    scenario_opt.committed_selection=struct( ...
        'selected_gfm_indices',selected,'n_gfm_required',numel(selected), ...
        'reference_resource_index',reference);
end
configured=stability.build_hybrid_scenario( ...
    scenario.case_data,resources_out,scenario_opt);
preserve={'resource_schema','scenario_id','provenance'};
for k=1:numel(preserve)
    if isfield(scenario,preserve{k}), configured.(preserve{k})=scenario.(preserve{k}); end
end
configured.selection_log=selection;
end
