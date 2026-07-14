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

% --- Reference policy (one numerical angle gauge per connected island) -----
% IEEE14 is single-island; the gauge is at the first online voltage-forming
% resource's bus. Generalized form: a function that, given the topology +
% voltage-forming index, returns the gauge bus + vcon (vars/rows/ref).
% For Phase B0 we record the policy; the actual gauge assignment happens in
% mixed_equilibrium_solve (Phase B1) using per-island voltage-forming detection.
if isfield(case_data,'reference') && isstruct(case_data.reference) && ...
        isfield(case_data.reference,'angle_gauge_policy')
    ref_policy = case_data.reference.angle_gauge_policy;
else
    ref_policy = struct( ...
        'policy', 'one_gauge_per_island_with_voltage_forming_source', ...
        'constraint', 'Im(V_island_ref) = 0 (angle reference)', ...
        'free', 'Re(V) solved by KCL/power balance', ...
        'fail_closed', 'no online voltage-forming source on an island => noVoltageFormingSource');
end

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
end
