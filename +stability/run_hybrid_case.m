function result = run_hybrid_case(scenario, opt)
%RUN_HYBRID_CASE  Top-level mixed SG+IBR transient stability orchestrator.
%   RESULT = run_hybrid_case(SCENARIO, OPT) runs PF init → composite equilibrium
%   → composite TS for a scenario built by stability.build_hybrid_scenario.
%
%   This is the single public entry point for the generic mixed-resource engine.
%   It is case-agnostic: IEEE14 IDs never appear here. The scenario carries the
%   validated resource table + case_data; the engine derives all indices from
%   the resource table.
%
%   Inputs:
%     scenario  - struct from stability.build_hybrid_scenario (Layer 2):
%                   .case_data  - immutable network case
%                   .resources  - validated resource table (Layer 1 contract)
%                   .config     - committed configuration arrays
%     opt       - struct with:
%                   .t_end, .dt, .fault_bus, .t_fault, .t_clear, .Zf,
%                   .method ('fixed'|'adaptive'), .verbose
%
%   Output: RESULT struct with .converged, .x_traj, .y_traj, .t, .events,
%   .metadata, .fingerprint, .selector_log, .reclose_log.
%
%   STATUS: STRUCTURAL_ONLY (Phase B2 vertical slice). No events, no limiter,
%   no adaptation. Fixed-step trapezoidal only. See execution plan for full scope.
%
%   Source: plan agent-a-atomic-lagoon.md (Layer 1 generic engine).

arguments
    scenario struct
    opt struct = struct()
end

% --- Defaults -------------------------------------------------------------
t_end    = 5.0;    if isfield(opt,'t_end') && ~isempty(opt.t_end), t_end = opt.t_end; end
dt       = 0.01;   if isfield(opt,'dt') && ~isempty(opt.dt), dt = opt.dt; end
verbose  = false;  if isfield(opt,'verbose') && ~isempty(opt.verbose), verbose = opt.verbose; end
load_model = 'cz_p_cz_q';
if isfield(opt,'load_model') && ~isempty(opt.load_model), load_model = opt.load_model; end

result = struct('converged', false, 'x_traj', [], 'y_traj', [], 't', [], ...
    'events', [], 'metadata', struct(), 'fingerprint', struct(), ...
    'selector_log', struct(), 'reclose_log', struct());

if ~isfield(scenario, 'case_data') || ~isfield(scenario, 'resources')
    result.metadata.failure = 'run_hybrid_case:invalidScenario';
    return;
end

case_data = scenario.case_data;
resources = scenario.resources;

% --- Build devices from the resource table (uniform schema) ---------------
try
    % The scenario owns dispatch and t0 mode/online commitments. Runtime TS
    % options (dt/t_end) must not silently replace those construction inputs.
    device_build_opt = struct();
    if isfield(scenario,'scenario_opt') && isstruct(scenario.scenario_opt) && ...
            isscalar(scenario.scenario_opt)
        device_build_opt = scenario.scenario_opt;
    end
    [devices, dev_meta] = stability.build_mixed_resource_devices( ...
        case_data, resources, device_build_opt);
catch me
    result.metadata.failure = 'run_hybrid_case:deviceBuild';
    result.metadata.error = me.message;
    return;
end

% --- Equilibrium -----------------------------------------------------------
config = struct('devices', devices);
% Preserve an explicitly committed selector/reference decision. For SG-off
% GFM operation the three selection fields are required atomically and an
% empty commitment fails closed; no device-order or first-GFM fallback exists.
if isfield(scenario,'config') && isstruct(scenario.config)
    selection_fields = {'resource_ids','selected_gfm_indices','n_gfm_required', ...
        'reference_resource_index'};
    for k = 1:numel(selection_fields)
        name = selection_fields{k};
        if isfield(scenario.config,name) && ~isempty(scenario.config.(name))
            config.(name) = scenario.config.(name);
        end
    end
end
eq_opt = struct('verbose', verbose, 'tolerance', 1e-8, 'max_iter', 300, ...
    'load_model', load_model);
eq = stability.mixed_equilibrium_solve(case_data, config, eq_opt);
if ~eq.converged
    result.metadata.failure = 'run_hybrid_case:equilibrium';
    result.metadata.equilibrium = eq;
    return;
end
result.equilibrium = eq;

% --- Composite TS (fixed-step, no events for Phase B2) --------------------
ts_opt = struct('t_end', t_end, 'dt', dt, 'verbose', verbose, ...
    'load_model', load_model);
ts_devices = devices;
if isfield(eq,'reference') && isstruct(eq.reference) && ...
        isfield(eq.reference,'physical_kcl_enforced') && ...
        isequal(eq.reference.physical_kcl_enforced,true)
    ts_devices = eq.devices;
    ts_opt.u_eq = eq.u_eq;
    ts_opt.event_context = eq.equilibrium_context;
    ts_opt.dynamic_state_indices = eq.dynamic_state_indices;
    ts_opt.full_kcl = true;
end
[ts_res, ts_meta] = stability.ts_simulate_composite(case_data, ts_devices, ...
    eq.x0, eq.y0, ts_opt);

result.x_traj = ts_res.x_traj;
result.y_traj = ts_res.y_traj;
result.t = ts_res.t;
result.converged = ts_res.converged;
result.metadata.device_build = dev_meta;
result.metadata.ts_meta = ts_meta;
result.metadata.resource_count = numel(resources);
result.metadata.device_count = numel(devices);
result.fingerprint.scenario_id = '';
if isfield(scenario, 'scenario_id')
    result.fingerprint.scenario_id = scenario.scenario_id;
end
end
