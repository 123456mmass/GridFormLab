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
    [devices, dev_meta] = stability.build_mixed_resource_devices( ...
        case_data, resources, opt);
catch me
    result.metadata.failure = 'run_hybrid_case:deviceBuild';
    result.metadata.error = me.message;
    return;
end

% --- Equilibrium -----------------------------------------------------------
config = struct('devices', devices);
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
[ts_res, ts_meta] = stability.ts_simulate_composite(case_data, devices, ...
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
