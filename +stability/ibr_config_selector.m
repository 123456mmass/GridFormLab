function result = ibr_config_selector(resources, topology, scenario, opt)
%IBR_CONFIG_SELECTOR  Enumerate deterministic index-selected GFM subsets with optional full-stack evaluation.
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
%   FULL EVALUATION MODE (new, PROJECT_DERIVED):
%   When caller supplies complete case_data/evaluator context:
%     case_data via opt.case_data or scenario.case_data or topology.case_data
%     containing .mpc with baseMVA/bus/branch (SOURCE_DEFINED)
%   the selector optionally evaluates:
%     - topology Ybus singularity / island (rcond)
%     - SCR per online GFL using stablity.ibr_scr_metrics:
%         Ybus branch+shunt only, Zth = (Y\ek)(k), S_sc=|V|^2/|Zth|*Sbase,
%         SCR=S_sc/S_rated, threshold 3.0 frozen, REGC_A <=3 reject fail closed
%     - equilibrium via production builder + mixed_equilibrium_solve (all-KCL, KCL<=1e-6)
%     - full-KCL composite_sssa_model with exact u_eq/context/active indices
%     - stability gate: gamma_req frozen before results, pass when max(real(lambda))<=-gamma_req
%   No inv/pinv, no external solver, no eigenvalue deletion.
%
%   When case_data context is absent, the selector preserves the structural-only
%   path (STRUCTURAL_CANDIDATES_ONLY) for backward compatibility.
%
%   Output fields include (always):
%     selected_gfm_indices, n_gfm_required, reference_resource_index,
%     topology_evaluated, scr_evaluated, equilibrium_evaluated, sssa_evaluated,
%     margin, ready_to_commit, fingerprint, per-candidate failure ID/reason
%
%   Classification: subset enumeration and ordering PROJECT_DERIVED;
%   gamma_req frozen CASE_DEFINED; SCR Ybus SOURCE_DEFINED, Zth PROJECT_DERIVED.

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
    result.fingerprint = 'selector_v3:noResources';
    return;
end

[resource_ids, modes, online, hold, lockout, alignment_ok, alignment_reason] = ...
    committed_arrays(resources, scenario);
if ~alignment_ok
    result.selection_status = 'INVALID_CONFIG_ALIGNMENT';
    result.failure_id = 'stability:ibr_config_selector:configDrift';
    result.feasibility_log = {alignment_reason};
    result.fingerprint = ['selector_v3:configDrift:' alignment_reason];
    return;
end

n_required = resolve_required_count(scenario, opt);
result.n_gfm_required = n_required;
if ~is_scalar_integer(n_required) || n_required < 1
    result.selection_status = 'INVALID_REQUIRED_COUNT';
    result.failure_id = 'stability:ibr_config_selector:badRequiredCount';
    result.feasibility_log = {'n_gfm_required must be a positive integer.'};
    result.fingerprint = sprintf('selector_v3:badRequiredCount:%g', n_required);
    return;
end

[preferred_reference, reference_specified] = resolve_reference(scenario, opt);
if reference_specified && (~is_scalar_integer(preferred_reference) || ...
        preferred_reference < 1 || preferred_reference > nr)
    result.selection_status = 'INVALID_REFERENCE';
    result.failure_id = 'stability:ibr_config_selector:badReferenceIndex';
    result.feasibility_log = {'reference_resource_index is outside the resource table.'};
    result.fingerprint = 'selector_v3:badReferenceIndex';
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
    result.fingerprint = sprintf('selector_v3:n%d:eligible%d:none', ...
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
    c.scr_evaluated = false;
    c.scr_pass = [];
    c.equilibrium_evaluated = false;
    c.sssa_evaluated = false;
    c.sssa_pass = [];
    c.margin = NaN;
    c.omega = NaN;
    c.physical_kcl_norm = Inf;
    c.eigenvalues = [];
    c.ready_to_commit = false;
    c.feasible = false;
    c.reason = 'structuralOnlyNoTopologyOrSssaEvidence';
    c.failure_id = 'stability:ibr_config_selector:sssaNotEvaluated';
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
    result.fingerprint = sprintf('selector_v3:n%d:reference%d:none', ...
        n_required, preferred_reference);
    return;
end

% --- structural ordering first ---
keys = {candidates.ordering_key};
[~, order] = sort(keys);
candidates = candidates(order);
selected_config = candidates(1);

% --- Attempt full evaluation if case_data context is complete ---
case_data_full = extract_case_data(topology, scenario, opt);
has_case = ~isempty(case_data_full) && isfield(case_data_full,'mpc') && ...
    isfield(case_data_full.mpc,'bus') && isfield(case_data_full.mpc,'branch') && ...
    isfield(case_data_full.mpc,'baseMVA');

% Ensure opt carries case_data for downstream evaluators
eval_opt = opt;
if has_case
    eval_opt.case_data = case_data_full;
    if isfield(scenario,'config') && isfield(scenario.config,'dispatch')
        if ~isfield(eval_opt,'dispatch')
            eval_opt.dispatch = scenario.config.dispatch;
        end
    end
    if isfield(scenario,'scenario_opt') && isstruct(scenario.scenario_opt)
        eval_opt.scenario_opt = scenario.scenario_opt;
        if isfield(scenario.scenario_opt,'dispatch') && ~isfield(eval_opt,'dispatch')
            eval_opt.dispatch = scenario.scenario_opt.dispatch;
        end
    end
end

if has_case
    % --- SCR metrics ---
    try
        scr = stability.ibr_scr_metrics(case_data_full, resources, topology, eval_opt);
    catch me
        scr = struct('Ybus',[],'Y_rcond',NaN,'is_singular',true,'topology_ok',false,...
            'per_resource',[],'failure_id','stability:ibr_scr_metrics:exception',...
            'failure_reason',me.message,'threshold',3.0);
    end
    result.scr_metrics = scr;
    result.topology_evaluated = isfield(scr,'Ybus') && ~isempty(scr.Ybus);
    if isfield(scr,'is_singular') && scr.is_singular
        result.topology_evaluated = true;
    end
    result.scr_evaluated = isfield(scr,'per_resource') && ~isempty(scr.per_resource);
    % Also set bus for fingerprint
    if ~isfield(scr,'threshold'), scr.threshold=3.0; end

    % If Y singular -> all candidates infeasible fail closed, but evaluated
    if isfield(scr,'is_singular') && scr.is_singular
        for ic=1:numel(candidates)
            candidates(ic).topology_evaluated = true;
            candidates(ic).scr_evaluated = true;
            candidates(ic).scr_pass = false;
            candidates(ic).equilibrium_evaluated = false;
            candidates(ic).sssa_evaluated = false;
            candidates(ic).feasible = false;
            candidates(ic).ready_to_commit = false;
            candidates(ic).reason = sprintf('topology singular/island Y rcond=%.3e fail closed', scr.Y_rcond);
            candidates(ic).failure_id = 'stability:ibr_config_selector:singularY';
            candidates(ic).margin = NaN;
            candidates(ic).ordering_key = sprintf('1|%09d|%s', candidates(ic).n_mode_changes, candidates(ic).tie_break);
        end
        % ordering: feasible none, so keep structural ordering but with fail flag
        result.configurations = candidates;
        result.selected_config = candidates(1);
        result.selected_gfm_indices = result.selected_config.selected_gfm_indices;
        result.reference_resource_index = result.selected_config.reference_resource_index;
        result.structural_feasible = true;
        result.equilibrium_evaluated = false;
        result.sssa_evaluated = false;
        result.margin = NaN;
        result.ready_to_commit = false;
        result.selection_status = 'TOPOLOGY_SINGULAR';
        result.failure_id = 'stability:ibr_config_selector:singularY';
        result.feasibility_log = {sprintf('Ybus singular rcond=%.3e, all candidates fail closed', scr.Y_rcond)};
        result.sssa_log = {scr.failure_reason};
        result.fingerprint = full_fingerprint(result, resource_ids, scr, gamma_req, candidates);
        result.failed_configs = candidates;
        return;
    end

    % --- Per-candidate full evaluation ---
    for ic=1:numel(candidates)
        cand_in = candidates(ic);
        % Call candidate evaluator
        try
            cand_out = stability.ibr_candidate_evaluate(case_data_full, resources, cand_in, scr, gamma_req, eval_opt);
        catch me
            cand_out = cand_in;
            cand_out.topology_evaluated = true;
            cand_out.scr_evaluated = true;
            cand_out.equilibrium_evaluated = false;
            cand_out.sssa_evaluated = false;
            cand_out.feasible = false;
            cand_out.ready_to_commit = false;
            cand_out.reason = sprintf('candidate evaluate exception: %s', me.message);
            cand_out.failure_id = 'stability:ibr_config_selector:candidateException';
        end
        % Ensure flags propagated
        candidates(ic) = cand_out;
    end

    % --- Ordering for full eval: feasible first, mode changes less, margin better, deterministic tie-break ---
    % Build composite ordering key
    for ic=1:numel(candidates)
        c = candidates(ic);
        feasible_flag = 0; % 0 for feasible (sort first), 1 for infeasible
        if ~c.feasible
            feasible_flag = 1;
        end
        % margin: larger margin is better, so invert for sorting ascending
        % Use -margin, with NaN treated as large
        if isfinite(c.margin)
            margin_key = -c.margin;
        else
            margin_key = 1e12;
        end
        % deterministic key includes resource index order as well
        candidates(ic).full_ordering_key = sprintf('%d|%09d|%+012.6f|%s|%s', ...
            feasible_flag, c.n_mode_changes, margin_key, c.tie_break, mat2str(c.selected_gfm_indices));
    end
    fkeys = {candidates.full_ordering_key};
    [~, forder] = sort(fkeys);
    candidates = candidates(forder);

    % Select best feasible if any, else first
    feasible_idx = find([candidates.feasible],1);
    if ~isempty(feasible_idx)
        selected_config = candidates(feasible_idx);
        sel_status = 'FEASIBLE';
        fail_id = '';
        fea_log = {sprintf('%d/%d candidates feasible; selected margin %.4g', ...
            numel(feasible_idx), numel(candidates), selected_config.margin)};
    else
        selected_config = candidates(1);
        sel_status = 'NO_FEASIBLE_CANDIDATE';
        fail_id = 'stability:ibr_config_selector:noFeasibleCandidate';
        fea_log = {sprintf('All %d candidates infeasible after full eval', numel(candidates))};
        % collect per-candidate reasons
        for fc=1:numel(candidates)
            fea_log{end+1} = sprintf('cand %s ref %d: %s (%s)', ...
                mat2str(candidates(fc).selected_gfm_indices), ...
                candidates(fc).reference_resource_index, candidates(fc).reason, candidates(fc).failure_id);
        end
    end

    result.configurations = candidates;
    result.failed_configs = candidates(~[candidates.feasible]);
    result.selected_config = selected_config;
    result.selected_gfm_indices = selected_config.selected_gfm_indices;
    result.reference_resource_index = selected_config.reference_resource_index;
    result.structural_feasible = true;
    result.topology_evaluated = true;
    result.scr_evaluated = true;
    result.equilibrium_evaluated = any([candidates.equilibrium_evaluated]);
    result.sssa_evaluated = any([candidates.sssa_evaluated]);
    result.margin = selected_config.margin;
    result.omega = selected_config.omega;
    result.physical_kcl_norm = selected_config.physical_kcl_norm;
    result.ready_to_commit = selected_config.ready_to_commit && selected_config.feasible;
    result.selection_status = sel_status;
    result.failure_id = fail_id;
    result.feasibility_log = fea_log;
    result.sssa_log = {sprintf('Full eval: %d/%d feasible, gamma=%.3g', ...
        sum([candidates.feasible]), numel(candidates), gamma_req)};
    result.fingerprint = full_fingerprint(result, resource_ids, scr, gamma_req, candidates);
    return;
end

% --- Structural-only fallback ---
result.selected_config = selected_config;
result.configurations = candidates;
result.selected_gfm_indices = selected_config.selected_gfm_indices;
result.reference_resource_index = selected_config.reference_resource_index;
result.structural_feasible = true;
result.topology_evaluated = false;
result.scr_evaluated = false;
result.equilibrium_evaluated = false;
result.sssa_evaluated = false;
result.ready_to_commit = false;
result.margin = NaN;
result.selection_status = 'STRUCTURAL_CANDIDATES_ONLY';
result.failure_id = 'stability:ibr_config_selector:sssaNotEvaluated';
result.feasibility_log = {sprintf( ...
    '%d exact-size structural candidate(s); topology/SSSA evidence absent.', ...
    numel(candidates))};
result.sssa_log = {'No SSSA evaluator contract is connected to this selector.'};
result.fingerprint = selection_fingerprint_old(result, resource_ids);

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
result.failed_configs = repmat(candidate_template(), 0, 1);
result.selected_gfm_indices = [];
result.n_gfm_required = [];
result.reference_resource_index = [];
result.eligible_gfm_indices = [];
result.structural_feasible = false;
result.topology_evaluated = false;
result.scr_evaluated = false;
result.equilibrium_evaluated = false;
result.sssa_evaluated = false;
result.ready_to_commit = false;
result.selection_status = 'UNINITIALIZED';
result.failure_id = '';
result.gamma_req = gamma_req;
result.fingerprint = sprintf('selector_v3:nr%d:uninitialized', nr);
result.feasibility_log = {};
result.sssa_log = {};
result.scr_metrics = struct();
result.margin = NaN;
result.omega = NaN;
result.physical_kcl_norm = Inf;
end

function c = candidate_template()
c = struct('resource_ids', {{}}, 'resource_type', {{}}, 'modes', {{}}, ...
    'online', [], 'selected_gfm_indices', [], 'n_gfm_required', [], ...
    'reference_resource_index', [], 'structural_feasible', false, ...
    'topology_evaluated', false, 'scr_evaluated', false, 'scr_pass', [], ...
    'equilibrium_evaluated', false, 'sssa_evaluated', false, ...
    'sssa_pass', [], 'margin', NaN, 'omega', NaN, 'physical_kcl_norm', Inf, ...
    'eigenvalues', [], 'gy_rcond', NaN, 'ready_to_commit', false, ...
    'feasible', false, 'reason', '', 'failure_id', '', 'n_mode_changes', Inf, ...
    'tie_break', '', 'ordering_key', '', 'full_ordering_key', '', ...
    'eq_x0', [], 'eq_y0', [], 'eq_u_eq', [], 'eq_context', struct(), ...
    'eq_active_indices', [], 'eq_rcond', NaN, 'eq_partition', struct(), ...
    'reduction_method', '', 'sssa_f0_norm', NaN, 'sssa_g0_norm', NaN, ...
    'full_kcl', false);
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

function fp = selection_fingerprint_old(result, resource_ids)
if isempty(result.selected_gfm_indices)
    fp = sprintf('selector_v3|n=%d|selected=none|ref=none|gamma=%.12g|evidence=structural_only', ...
        result.n_gfm_required, result.gamma_req);
else
    selected_ids = resource_ids(result.selected_gfm_indices);
    fp = sprintf('selector_v3|n=%d|selected=%s|ref=%d|gamma=%.12g|evidence=structural_only', ...
        result.n_gfm_required, strjoin(selected_ids, ','), ...
        result.reference_resource_index, result.gamma_req);
end
end

function fp = full_fingerprint(result, resource_ids, scr, gamma_req, candidates)
try
    if isempty(result.selected_gfm_indices)
        sel_str = 'none';
        ref_str = 'none';
    else
        sel_ids = resource_ids(result.selected_gfm_indices);
        sel_str = strjoin(sel_ids, ',');
        ref_str = sprintf('%d', result.reference_resource_index);
    end
    feas = sum([candidates.feasible]);
    scr_thr = 3.0;
    if isfield(scr,'threshold'), scr_thr=scr.threshold; end
    rcond_val = NaN;
    if isfield(scr,'Y_rcond'), rcond_val=scr.Y_rcond; end
    scr_fp = '';
    if isfield(scr,'fingerprint'), scr_fp = scr.fingerprint; end
    % include margin and topology flags
    fp = sprintf('selector_v3|n=%d|selected=%s|ref=%s|gamma=%.12g|thr=%.1f|rcond=%.3e|feas=%d/%d|margin=%.6g|topo=%d|scr=%d|eq=%d|sssa=%d|ready=%d|scr_fp=%s', ...
        result.n_gfm_required, sel_str, ref_str, gamma_req, scr_thr, rcond_val, feas, numel(candidates), result.margin, ...
        result.topology_evaluated, result.scr_evaluated, result.equilibrium_evaluated, result.sssa_evaluated, result.ready_to_commit, scr_fp);
catch
    fp = sprintf('selector_v3|n=%d|gamma=%.12g|feas=unknown', result.n_gfm_required, gamma_req);
end
end

function cd = extract_case_data(topology, scenario, opt)
cd = [];
% priority: opt.case_data, scenario.case_data, topology.case_data, topology as case_data itself (if has mpc)
if isfield(opt,'case_data') && ~isempty(opt.case_data) && isstruct(opt.case_data) && isfield(opt.case_data,'mpc')
    cd = opt.case_data;
    return;
end
if isfield(scenario,'case_data') && ~isempty(scenario.case_data) && isstruct(scenario.case_data) && isfield(scenario.case_data,'mpc')
    cd = scenario.case_data;
    return;
end
if isfield(topology,'case_data') && ~isempty(topology.case_data) && isstruct(topology.case_data) && isfield(topology.case_data,'mpc')
    cd = topology.case_data;
    return;
end
if isfield(opt,'mpc') && isstruct(opt) % opt itself is case_data?
    % not standard, but check
    if isfield(opt,'mpc')
        % opt is actually case_data
    end
end
% also if topology itself has mpc (when caller passes case_data as topology arg)
if isfield(topology,'mpc') && isstruct(topology) && isfield(topology,'bus')
    % topology is actually mpc? No, but check
    if isfield(topology,'mpc')
        cd = topology;
    else
        % if topology has bus/branch directly, treat as mpc wrapper?
        % Build minimal case_data
        if isfield(topology,'bus') && isfield(topology,'branch')
            cd = struct('mpc', topology);
        end
    end
end
% scenario itself could be case_data
if isfield(scenario,'mpc') && isfield(scenario,'bus') % scenario is mpc?
    cd = struct('mpc', scenario);
elseif isfield(scenario,'mpc') && isstruct(scenario.mpc)
    cd = scenario;
end
end
