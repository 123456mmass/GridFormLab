function scenario = build_hybrid_scenario(case_data, resources, scenario_opt)
%BUILD_HYBRID_SCENARIO  Bind case_data + resource table + runtime options into a scenario.
%   scenario = build_hybrid_scenario(CASE_DATA, RESOURCES, SCENARIO_OPT) binds
%   the IMMUTABLE case data (network/base, dynamic params, provenance) with a
%   validated indexed RESOURCES table and runtime SCENARIO_OPT into a single
%   scenario struct consumed by stability.run_hybrid_case.
%
%   This is the Layer-1/Layer-2 seam: case_data is NEVER mutated; runtime
%   choices (count, selection, modes, fault, SG trip, timestep) live in
%   SCENARIO_OPT and are applied to the scenario's committed configuration,
%   never written back into case_data.
%
%   Committed configuration is represented as arrays ALIGNED WITH THE RESOURCE
%   INDEX (the "real index" decision basis the engine uses):
%     config.resource_ids = {"SG1","IBR2",...}    % == resources.resource_id
%     config.online        = [true, true, ...]     % == resources.initial_online (+opt)
%     config.mode          = ["synchronous","gfl",...] % == resources.initial_mode (+opt)
%     config.hold          = false(nr,1)            % per-resource hold flag
%     config.lockout       = false(nr,1)           % per-resource lockout flag
%   A resource_ids-vs-table drift guard is embedded so index ordering cannot
%   silently drift.
%
%   Scenario fields:
%     scenario.case_data       - immutable network/base + dynamic data
%     scenario.resources       - validated indexed resource table
%     scenario.config         - committed configuration (index-aligned arrays)
%     scenario.scenario_opt   - runtime options (fault, SG trip, timestep, ...)
%     scenario.reference_policy - angle-gauge policy (one per island)
%     scenario.load_model     - load model string
%     scenario.synchronism    - ΔV/Δf/Δθ/dwell/timeout (from case_data or opt)
%     scenario.delays         - T_up/T_sg_min_off/ρ/T_min_hold/T_guard/T_lockout
%     scenario.selector       - γ_req + policy
%     scenario.metadata       - case + config fingerprint
%
%   STATUS: STRUCTURAL_ONLY (Phase B0 foundation).
%
%   Source: plan agent-a-atomic-lagoon.md (Layer 1/Layer 2 seam).

arguments
    case_data struct
    resources struct
    scenario_opt struct = struct()
end

nr = numel(resources);
if nr == 0
    error('stability:build_hybrid_scenario:noResources', ...
        'Resource table is empty — cannot build a scenario.');
end

% --- Drift guard: resource_ids unique + match table order -------------------
resource_ids = arrayfun(@(k) char(resources(k).resource_id), (1:nr).', ...
    'UniformOutput', false).';
if numel(unique(resource_ids)) ~= nr
    error('stability:build_hybrid_scenario:dupIds', ...
        'Resource table has duplicate resource_ids.');
end

% --- Committed configuration (index-aligned arrays) -------------------------
% Start from the resource table's initial values; apply scenario_opt overrides
% (resolved by resource_table when it was built, but we also accept direct
% per-index overrides here for the runtime-config mutation path).
config = struct();
config.resource_ids = resource_ids;
config.online = arrayfun(@(k) resources(k).initial_online, 1:nr);
config.mode = arrayfun(@(k) resources(k).initial_mode, 1:nr, ...
    'UniformOutput', false).';
config.hold = false(nr, 1);
config.lockout = false(nr, 1);
config.dispatch = struct();
if isfield(scenario_opt,'dispatch') && ~isempty(scenario_opt.dispatch)
    config.dispatch = scenario_opt.dispatch;
end

% Explicit selector commitment. Empty means no GFM subset has been committed;
% downstream event code must not infer a resource from struct-field order.
committed_selection = struct('selected_gfm_indices', [], ...
    'n_gfm_required', [], 'reference_resource_index', []);
if isfield(scenario_opt, 'committed_selection') && ...
        ~isempty(scenario_opt.committed_selection)
    committed_selection = validate_committed_selection( ...
        scenario_opt.committed_selection, resources, config.online);
end
config.selected_gfm_indices = committed_selection.selected_gfm_indices;
config.n_gfm_required = committed_selection.n_gfm_required;
config.reference_resource_index = committed_selection.reference_resource_index;

% --- Reference policy (one numerical reference per connected island) -------
% IEEE14 is single-island. For SG-off operation the gauge is anchored at the
% explicitly committed reference_resource_index, which must be one member of
% the exact selected GFM subset. For an online SG REF, the case REF bus fixes
% both rectangular voltage coordinates while [Tm;Efd] provide the two solved
% balancing controls. mixed_equilibrium_solve owns the final assignment and
% keeps every physical KCL row in either formulation.
if isfield(case_data,'reference') && isstruct(case_data.reference) && ...
        isfield(case_data.reference,'angle_gauge_policy')
    ref_policy = case_data.reference.angle_gauge_policy;
else
    ref_policy = struct( ...
        'policy', 'one_gauge_per_island_with_voltage_forming_source', ...
        'constraint', 'GFM: Im(Vref)=0; SG REF: Re/Im(Vref)=case target', ...
        'free', 'GFM solves reference P; SG REF solves Tm/Efd; all KCL retained', ...
        'fail_closed', 'no online voltage-forming source on an island => noVoltageFormingSource');
end
if ~isstruct(ref_policy) || ~isscalar(ref_policy)
    error('stability:build_hybrid_scenario:badReferencePolicy', ...
        'case_data.reference.angle_gauge_policy must be a scalar struct.');
end
ref_policy.reference_resource_index = ...
    committed_selection.reference_resource_index;
ref_policy.reference_selection_contract = ...
    'exactly one selected GFM member; empty until explicitly committed';

% --- Load model ------------------------------------------------------------
if isfield(scenario_opt,'load_model') && ~isempty(scenario_opt.load_model)
    load_model = scenario_opt.load_model;
elseif isfield(case_data,'operating_point') && isfield(case_data.operating_point,'load_model')
    load_model = case_data.operating_point.load_model;
else
    load_model = 'cz_p_cz_q';
end

% --- Synchronism + delays + selector (sourced from case_data, frozen) -------
synchronism = struct();
if isfield(case_data,'synchronism'), synchronism = case_data.synchronism; end
delays = struct();
if isfield(case_data,'delays'), delays = case_data.delays; end
selector = struct();
if isfield(case_data,'selector'), selector = case_data.selector; end
if ~isempty(committed_selection.n_gfm_required)
    selector.n_gfm_required = committed_selection.n_gfm_required;
end

% --- Scenario metadata fingerprint -----------------------------------------
meta = struct();
meta.case_system_name = '';
if isfield(case_data,'system_name'), meta.case_system_name = case_data.system_name; end
meta.resource_ids = resource_ids;
meta.nr = nr;
meta.config_hash = config_hash(config);
meta.scenario_opt_keys = string(fieldnames(scenario_opt)).';
meta.built_at = '';   % filled by run_hybrid_case at execution time

scenario = struct();
scenario.case_data = case_data;
scenario.resources = resources;
scenario.config = config;
scenario.committed_selection = committed_selection;
scenario.scenario_opt = scenario_opt;
scenario.reference_policy = ref_policy;
scenario.load_model = load_model;
scenario.synchronism = synchronism;
scenario.delays = delays;
scenario.selector = selector;
scenario.metadata = meta;
end

% =========================================================================
function h = config_hash(config)
% Index-based fingerprint: resource_ids + online + mode + dispatch, NOT sg_status.
h = sprintf('nr=%d|ids=', numel(config.resource_ids));
for k = 1:numel(config.resource_ids)
    h = [h config.resource_ids{k} ':' config.mode{k} ':' num2str(config.online(k)) ';']; %#ok<AGROW>
end
if ~isempty(config.dispatch)
    dk = sort(fieldnames(config.dispatch));
    for k = 1:numel(dk)
        h = [h 'd:' dk{k} '=' num2str(config.dispatch.(dk{k})) ';']; %#ok<AGROW>
    end
end
if ~isempty(config.n_gfm_required)
    h = [h 'n_gfm=' num2str(config.n_gfm_required) ';'];
    h = [h 'selected=' sprintf('%d,', config.selected_gfm_indices) ';'];
    h = [h 'reference=' num2str(config.reference_resource_index) ';'];
else
    h = [h 'n_gfm=uncommitted;'];
end
end

% =========================================================================
function committed = validate_committed_selection(value, resources, online)
if ~isstruct(value) || ~isscalar(value)
    error('stability:build_hybrid_scenario:badCommittedSelection', ...
        'scenario_opt.committed_selection must be one scalar struct.');
end
required = {'selected_gfm_indices','n_gfm_required','reference_resource_index'};
for k = 1:numel(required)
    if ~isfield(value, required{k})
        error('stability:build_hybrid_scenario:incompleteCommittedSelection', ...
            'committed_selection lacks %s.', required{k});
    end
end

nr = numel(resources);
selected = value.selected_gfm_indices;
n_required = value.n_gfm_required;
reference_index = value.reference_resource_index;
if ~isnumeric(selected) || isempty(selected) || any(~isfinite(selected(:))) || ...
        any(selected(:) ~= fix(selected(:))) || ...
        any(selected(:) < 1 | selected(:) > nr)
    error('stability:build_hybrid_scenario:badSelectedIndices', ...
        'selected_gfm_indices must be finite in-range resource indices.');
end
selected = reshape(selected, 1, []);
if numel(unique(selected)) ~= numel(selected)
    error('stability:build_hybrid_scenario:duplicateSelectedIndices', ...
        'selected_gfm_indices must be unique.');
end
if ~is_scalar_integer(n_required) || n_required < 1 || ...
        numel(selected) ~= n_required
    error('stability:build_hybrid_scenario:selectionCountMismatch', ...
        'n_gfm_required must equal the positive selected index count.');
end
if ~is_scalar_integer(reference_index) || ...
        ~ismember(reference_index, selected)
    error('stability:build_hybrid_scenario:referenceNotSelected', ...
        'reference_resource_index must be one selected GFM member.');
end

for k = selected
    r = resources(k);
    eligible = online(k) && strcmpi(char(r.resource_type), 'ibr') && ...
        logical(r.can_switch_mode) && ...
        any(strcmpi(string(r.supported_modes), 'gfl')) && ...
        any(strcmpi(string(r.supported_modes), 'gfm')) && ...
        any(strcmpi(string(r.voltage_forming_modes), 'gfm'));
    if ~eligible
        error('stability:build_hybrid_scenario:selectedResourceIneligible', ...
            'Selected resource index %d is not an online dual-mode GFM-capable IBR.', k);
    end
end

committed = struct('selected_gfm_indices', selected, ...
    'n_gfm_required', n_required, ...
    'reference_resource_index', reference_index);
end

function tf = is_scalar_integer(value)
tf = isnumeric(value) && isscalar(value) && isfinite(value) && value == fix(value);
end
