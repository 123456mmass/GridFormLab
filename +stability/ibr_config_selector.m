function result = ibr_config_selector(resources, topology, scenario, opt)
%IBR_CONFIG_SELECTOR  Enumerate deterministic index-selected GFM subsets.
%   RESULT = stability.ibr_config_selector(RESOURCES, TOPOLOGY, SCENARIO, OPT)
%   enumerates exact-size subsets of online, switchable, dual-mode IBRs.
%   Resource-table indices are the only selector identity: bus numbers and
%   device names are never decision keys.
%
%   OPT.n_gfm_required freezes the exact committed GFM count. If omitted, the
%   selector uses scenario.config/scenario.selector and otherwise fails closed;
%   it never guesses that one GFM is sufficient.
%   OPT.reference_resource_index may constrain the numerical angle-reference
%   resource; every retained candidate must contain that index. Otherwise the
%   lowest selected resource-table index is the deterministic reference.
%
%   This function currently has no project SSSA/topology-island evaluator API.
%   It therefore reports structural candidates without fabricating a damping
%   PASS or margin. A caller may commit only after a separate approved evaluator
%   supplies the missing evidence.
%
%   Classification: subset enumeration and ordering are PROJECT_DERIVED;
%   gamma_req is the frozen selector acceptance contract.

arguments
    resources struct
    topology struct = struct()
    scenario struct = struct()
    opt struct = struct()
end

gamma_req = resolve_gamma_req(scenario, opt);
if ~isscalar(gamma_req) || ~isfinite(gamma_req) || gamma_req < 0
    error('stability:ibr_config_selector:badGammaReq', ...
        'gamma_req must be a finite nonnegative scalar.');
end

nr = numel(resources);
result = empty_result(gamma_req, nr);
if nr == 0
    result.selection_status = 'NO_RESOURCES';
    result.failure_id = 'stability:ibr_config_selector:noResources';
    result.fingerprint = 'selector_v2:noResources';
    return;
end

[resource_ids, modes, online, hold, lockout, alignment_ok, alignment_reason] = ...
    committed_arrays(resources, scenario);
if ~alignment_ok
    result.selection_status = 'INVALID_CONFIG_ALIGNMENT';
    result.failure_id = 'stability:ibr_config_selector:configDrift';
    result.feasibility_log = {alignment_reason};
    result.fingerprint = ['selector_v2:configDrift:' alignment_reason];
    return;
end

n_required = resolve_required_count(scenario, opt);
result.n_gfm_required = n_required;
if ~is_scalar_integer(n_required) || n_required < 1
    result.selection_status = 'INVALID_REQUIRED_COUNT';
    result.failure_id = 'stability:ibr_config_selector:badRequiredCount';
    result.feasibility_log = {'n_gfm_required must be a positive integer.'};
    result.fingerprint = sprintf('selector_v2:badRequiredCount:%g', n_required);
    return;
end

[preferred_reference, reference_specified] = resolve_reference(scenario, opt);
if reference_specified && (~is_scalar_integer(preferred_reference) || ...
        preferred_reference < 1 || preferred_reference > nr)
    result.selection_status = 'INVALID_REFERENCE';
    result.failure_id = 'stability:ibr_config_selector:badReferenceIndex';
    result.feasibility_log = {'reference_resource_index is outside the resource table.'};
    result.fingerprint = 'selector_v2:badReferenceIndex';
    return;
end

eligible = false(1, nr);
resource_type = cell(1, nr);
for k = 1:nr
    r = resources(k);
    resource_type{k} = lower(char(r.resource_type));
    eligible(k) = online(k) && ~hold(k) && ~lockout(k) && ...
        strcmp(resource_type{k}, 'ibr') && logical(r.can_switch_mode) && ...
        mode_supported(r, 'gfl') && mode_supported(r, 'gfm') && ...
        voltage_forming_mode(r, 'gfm');
end
eligible_indices = find(eligible);
result.eligible_gfm_indices = eligible_indices;

if n_required > numel(eligible_indices)
    result.selection_status = 'NO_STRUCTURAL_CANDIDATE';
    result.failure_id = 'stability:ibr_config_selector:insufficientEligibleGfm';
    result.feasibility_log = {sprintf( ...
        'Requested %d GFM resources, but only %d are eligible.', ...
        n_required, numel(eligible_indices))};
    result.fingerprint = sprintf('selector_v2:n%d:eligible%d:none', ...
        n_required, numel(eligible_indices));
    result.selected_config = current_config(resource_ids, modes, online, resource_type, ...
        n_required, 'insufficientEligibleGfm');
    return;
end

subsets = nchoosek(eligible_indices, n_required);
if isvector(subsets) && n_required == 1
    subsets = subsets(:);
end

candidates = repmat(candidate_template(), 0, 1);
for row = 1:size(subsets, 1)
    selected = reshape(subsets(row, :), 1, []);
    if reference_specified && ~ismember(preferred_reference, selected)
        continue;
    end
    if reference_specified
        reference_index = preferred_reference;
    else
        reference_index = min(selected);
    end

    candidate_modes = modes;
    for j = 1:numel(eligible_indices)
        idx = eligible_indices(j);
        if ismember(idx, selected)
            candidate_modes{idx} = 'gfm';
        else
            candidate_modes{idx} = 'gfl';
        end
    end

    changed = 0;
    for k = 1:nr
        changed = changed + ~strcmpi(candidate_modes{k}, modes{k});
    end
    selected_ids = resource_ids(selected);
    sorted_ids = sort(selected_ids);

    c = candidate_template();
    c.resource_ids = resource_ids;
    c.resource_type = resource_type;
    c.modes = candidate_modes;
    c.online = online;
    c.selected_gfm_indices = selected;
    c.n_gfm_required = n_required;
    c.reference_resource_index = reference_index;
    c.structural_feasible = true;
    c.topology_evaluated = false;
    c.sssa_evaluated = false;
    c.sssa_pass = [];
    c.margin = NaN;
    c.ready_to_commit = false;
    c.feasible = false;
    c.reason = 'structuralOnlyNoTopologyOrSssaEvidence';
    c.n_mode_changes = changed;
    c.tie_break = strjoin(sorted_ids, ',');
    c.ordering_key = sprintf('%09d|%s', changed, c.tie_break);
    candidates(end+1, 1) = c; %#ok<AGROW>
end

if isempty(candidates)
    result.selection_status = 'NO_STRUCTURAL_CANDIDATE';
    result.failure_id = 'stability:ibr_config_selector:referenceNotInSubset';
    result.feasibility_log = { ...
        'No exact-size eligible subset contains reference_resource_index.'};
    result.fingerprint = sprintf('selector_v2:n%d:reference%d:none', ...
        n_required, preferred_reference);
    return;
end

keys = {candidates.ordering_key};
[~, order] = sort(keys);
candidates = candidates(order);
selected_config = candidates(1);

result.selected_config = selected_config;
result.configurations = candidates;
result.selected_gfm_indices = selected_config.selected_gfm_indices;
result.reference_resource_index = selected_config.reference_resource_index;
result.structural_feasible = true;
result.topology_evaluated = false;
result.sssa_evaluated = false;
result.ready_to_commit = false;
result.selection_status = 'STRUCTURAL_CANDIDATES_ONLY';
result.failure_id = 'stability:ibr_config_selector:sssaNotEvaluated';
result.feasibility_log = {sprintf( ...
    '%d exact-size structural candidate(s); topology/SSSA evidence absent.', ...
    numel(candidates))};
result.sssa_log = {'No SSSA evaluator contract is connected to this selector.'};
result.fingerprint = selection_fingerprint(result, resource_ids);

% TOPOLOGY is accepted for API compatibility, but no topology schema is
% established in this repository. Do not infer island membership from fields.
if ~isempty(fieldnames(topology))
    result.feasibility_log{end+1} = ...
        'Topology supplied but not evaluated: no approved island-membership schema.';
end
end

% =========================================================================
function result = empty_result(gamma_req, nr)
result = struct();
result.selected_config = struct();
result.configurations = repmat(candidate_template(), 0, 1);
result.selected_gfm_indices = [];
result.n_gfm_required = [];
result.reference_resource_index = [];
result.eligible_gfm_indices = [];
result.structural_feasible = false;
result.topology_evaluated = false;
result.sssa_evaluated = false;
result.ready_to_commit = false;
result.selection_status = 'UNINITIALIZED';
result.failure_id = '';
result.gamma_req = gamma_req;
result.fingerprint = sprintf('selector_v2:nr%d:uninitialized', nr);
result.feasibility_log = {};
result.sssa_log = {};
result.failed_configs = {};
end

function c = candidate_template()
c = struct('resource_ids', {{}}, 'resource_type', {{}}, 'modes', {{}}, ...
    'online', [], 'selected_gfm_indices', [], 'n_gfm_required', [], ...
    'reference_resource_index', [], 'structural_feasible', false, ...
    'topology_evaluated', false, 'sssa_evaluated', false, ...
    'sssa_pass', [], 'margin', NaN, 'ready_to_commit', false, ...
    'feasible', false, 'reason', '', 'n_mode_changes', Inf, ...
    'tie_break', '', 'ordering_key', '');
end

function c = current_config(ids, modes, online, resource_type, n_required, reason)
c = candidate_template();
c.resource_ids = ids;
c.resource_type = resource_type;
c.modes = modes;
c.online = online;
c.n_gfm_required = n_required;
c.reason = reason;
end

function [ids, modes, online, hold, lockout, ok, reason] = committed_arrays(resources, scenario)
nr = numel(resources);
ids = arrayfun(@(r) char(r.resource_id), resources, 'UniformOutput', false);
modes = arrayfun(@(r) char(r.initial_mode), resources, 'UniformOutput', false);
online = logical(arrayfun(@(r) r.initial_online, resources));
hold = false(1, nr);
lockout = false(1, nr);
ok = true;
reason = '';
if ~isfield(scenario, 'config') || isempty(scenario.config)
    return;
end
cfg = scenario.config;
if ~isfield(cfg, 'resource_ids') || numel(cfg.resource_ids) ~= nr || ...
        ~all(strcmp(reshape(cfg.resource_ids, 1, []), reshape(ids, 1, [])))
    ok = false;
    reason = 'scenario.config.resource_ids do not align with the resource table.';
    return;
end
if isfield(cfg, 'mode') && numel(cfg.mode) == nr
    modes = reshape(cellstr(string(cfg.mode)), 1, []);
elseif isfield(cfg, 'modes') && numel(cfg.modes) == nr
    modes = reshape(cellstr(string(cfg.modes)), 1, []);
else
    ok = false;
    reason = 'scenario.config mode array is missing or has the wrong size.';
    return;
end
if ~isfield(cfg, 'online') || numel(cfg.online) ~= nr
    ok = false;
    reason = 'scenario.config.online is missing or has the wrong size.';
    return;
end
online = reshape(logical(cfg.online), 1, []);
if isfield(cfg, 'hold') && numel(cfg.hold) == nr
    hold = reshape(logical(cfg.hold), 1, []);
end
if isfield(cfg, 'lockout') && numel(cfg.lockout) == nr
    lockout = reshape(logical(cfg.lockout), 1, []);
end
end

function value = resolve_required_count(scenario, opt)
if isfield(opt, 'n_gfm_required') && ~isempty(opt.n_gfm_required)
    value = opt.n_gfm_required;
elseif isfield(scenario, 'committed_selection') && ...
        isfield(scenario.committed_selection, 'n_gfm_required') && ...
        ~isempty(scenario.committed_selection.n_gfm_required)
    value = scenario.committed_selection.n_gfm_required;
elseif isfield(scenario, 'config') && isfield(scenario.config, 'n_gfm_required') && ...
        ~isempty(scenario.config.n_gfm_required)
    value = scenario.config.n_gfm_required;
elseif isfield(scenario, 'selector') && isfield(scenario.selector, 'n_gfm_required') && ...
        ~isempty(scenario.selector.n_gfm_required)
    value = scenario.selector.n_gfm_required;
else
    value = [];
end
end

function [value, specified] = resolve_reference(scenario, opt)
value = [];
specified = false;
if isfield(opt, 'reference_resource_index') && ...
        ~isempty(opt.reference_resource_index)
    value = opt.reference_resource_index;
    specified = true;
elseif isfield(scenario, 'committed_selection') && ...
        isfield(scenario.committed_selection, 'reference_resource_index') && ...
        ~isempty(scenario.committed_selection.reference_resource_index)
    value = scenario.committed_selection.reference_resource_index;
    specified = true;
elseif isfield(scenario, 'config') && ...
        isfield(scenario.config, 'reference_resource_index') && ...
        ~isempty(scenario.config.reference_resource_index)
    value = scenario.config.reference_resource_index;
    specified = true;
elseif isfield(scenario, 'reference_policy') && ...
        isfield(scenario.reference_policy, 'reference_resource_index') && ...
        ~isempty(scenario.reference_policy.reference_resource_index)
    value = scenario.reference_policy.reference_resource_index;
    specified = true;
end
end

function tf = mode_supported(resource, mode)
tf = isfield(resource, 'supported_modes') && ...
    any(strcmpi(string(resource.supported_modes), mode));
end

function tf = voltage_forming_mode(resource, mode)
tf = isfield(resource, 'voltage_forming_modes') && ...
    any(strcmpi(string(resource.voltage_forming_modes), mode));
end

function tf = is_scalar_integer(value)
tf = isnumeric(value) && isscalar(value) && isfinite(value) && value == fix(value);
end

function value = resolve_gamma_req(scenario, opt)
if isfield(opt, 'gamma_req') && ~isempty(opt.gamma_req)
    value = opt.gamma_req;
elseif isfield(scenario, 'selector') && ...
        isfield(scenario.selector, 'gamma_req') && ...
        ~isempty(scenario.selector.gamma_req)
    value = scenario.selector.gamma_req;
elseif isfield(scenario, 'selector') && ...
        isfield(scenario.selector, 'gamma_req_rad_per_s') && ...
        ~isempty(scenario.selector.gamma_req_rad_per_s)
    value = scenario.selector.gamma_req_rad_per_s;
else
    value = 0.1;
end
end

function fp = selection_fingerprint(result, resource_ids)
selected_ids = resource_ids(result.selected_gfm_indices);
fp = sprintf('selector_v2|n=%d|selected=%s|ref=%d|gamma=%.12g|evidence=structural_only', ...
    result.n_gfm_required, strjoin(selected_ids, ','), ...
    result.reference_resource_index, result.gamma_req);
end
