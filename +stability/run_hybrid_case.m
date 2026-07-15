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
index_dae=struct('devices',eq.devices,'device_offsets',device_offsets(eq.devices));
initial_status=stability.ibr_status_snapshot('initial_configuration',0,index_dae, ...
    eq.equilibrium_context,eq.dynamic_state_indices,eq.physical_kcl_norm);
result.status_log=initial_status;
if isfield(scenario,'selection_log'), result.selector_log=scenario.selection_log; end

% --- Composite TS -------------------------------------------------------
% Default/no-event path (Phase B2) must remain bit-identical.
% Opt-in IBR event route: opt.ibr_events.enabled==true

has_ibr_events = isfield(opt,'ibr_events') && isstruct(opt.ibr_events) && ...
    isfield(opt.ibr_events,'enabled') && isscalar(opt.ibr_events.enabled) && ...
    logical(opt.ibr_events.enabled);

ts_opt_base = struct('t_end', t_end, 'dt', dt, 'verbose', verbose, ...
    'load_model', load_model);
ts_devices = devices;
if isfield(eq,'reference') && isstruct(eq.reference) && ...
        isfield(eq.reference,'physical_kcl_enforced') && ...
        isequal(eq.reference.physical_kcl_enforced,true)
    ts_devices = eq.devices;
    ts_opt_base.u_eq = eq.u_eq;
    ts_opt_base.event_context = eq.equilibrium_context;
    ts_opt_base.dynamic_state_indices = eq.dynamic_state_indices;
    ts_opt_base.full_kcl = true;
end

if ~has_ibr_events
    % ---- Legacy no-event fixed-step path (must be unchanged) --------------
    [ts_res, ts_meta] = stability.ts_simulate_composite(case_data, ts_devices, ...
        eq.x0, eq.y0, ts_opt_base);

    result.x_traj = ts_res.x_traj;
    result.y_traj = ts_res.y_traj;
    result.t = ts_res.t;
    result.converged = ts_res.converged;
    result.metadata.device_build = dev_meta;
    result.metadata.ts_meta = ts_meta;
    result.metadata.resource_count = numel(resources);
    result.metadata.device_count = numel(devices);
    result.status_log=initial_status;
    result.execution_summary=build_execution_summary(eq,ts_res,[],scenario);
    result.fingerprint.scenario_id = '';
    if isfield(scenario, 'scenario_id')
        result.fingerprint.scenario_id = scenario.scenario_id;
    end
    return;
end

% ---- IBR event route (opt-in) --------------------------------------------
% Validate schedule fail-closed, no silent fallback.
try
    sched = stability.ibr_event_schedule(case_data, ts_devices, opt.ibr_events, t_end, dt);
catch me
    result.metadata.failure = 'run_hybrid_case:invalidEventSchedule';
    result.metadata.error = me.message;
    result.metadata.error_id = me.identifier;
    result.converged = false;
    return;
end

% Build TS options for hybrid driver
ts_opt_ibr = ts_opt_base;
ts_opt_ibr.ibr_event_schedule = sched;
if isfield(opt,'synchronism_overrides') && isstruct(opt.synchronism_overrides)
    ts_opt_ibr.synchronism_overrides = opt.synchronism_overrides;
end
if isfield(opt,'delays_overrides') && isstruct(opt.delays_overrides)
    ts_opt_ibr.delays_overrides = opt.delays_overrides;
end

[ts_res, ts_meta] = stability.ts_simulate_ibr_hybrid(case_data, ts_devices, ...
    eq.x0, eq.y0, ts_opt_ibr);

result.x_traj = ts_res.x_traj;
result.y_traj = ts_res.y_traj;
result.t = ts_res.t;
result.converged = ts_res.converged;
result.events = ts_res.events;
result.event_log = ts_res.event_log;
result.status_log = ts_res.status_log;
result.bus_voltage_magnitude = ts_res.bus_voltage_magnitude;
result.device_currents = ts_res.device_currents;
result.device_current_magnitude = ts_res.device_current_magnitude;
result.device_P = ts_res.device_P;
result.device_Q = ts_res.device_Q;
result.sg_omega = ts_res.sg_omega;
result.sg_freq = ts_res.sg_freq;
result.sg_indices = ts_res.sg_indices;
result.device_modes_history = ts_res.device_modes_history;
result.Y_log = ts_res.Y_log;
result.residual_per_step = ts_res.residual_per_step;
result.iter_per_step = ts_res.iter_per_step;
result.requested_sg_on_time = ts_res.requested_sg_on_time;
result.actual_reclose_time = ts_res.actual_reclose_time;
result.reclose_status = ts_res.reclose_status;
result.sched = ts_res.sched;
if isfield(ts_res,'t_sg_trip'), result.t_sg_trip = ts_res.t_sg_trip; end
if isfield(ts_res,'failure_id'), result.metadata.failure = ts_res.failure_id; end
if isfield(ts_res,'failure_reason'), result.metadata.error = ts_res.failure_reason; end
copy_fields = {'sample_side','topology_history','active_state_history', ...
    'device_online_history','device_frequency_Hz','coi_frequency_Hz', ...
    'device_P_pu','device_Q_pu','device_P_MW','device_Q_MVAr', ...
    'device_current_limit_sys','device_ids','device_bus_ids','bus_ids', ...
    'last_synchronism_guard'};
for k = 1:numel(copy_fields)
    name = copy_fields{k};
    if isfield(ts_res,name), result.(name) = ts_res.(name); end
end

result.metadata.device_build = dev_meta;
result.metadata.ts_meta = ts_meta;
result.metadata.resource_count = numel(resources);
result.metadata.device_count = numel(devices);
result.metadata.ibr_events = opt.ibr_events;
result.execution_summary=build_execution_summary(eq,ts_res,ts_res.event_log,scenario);
result.fingerprint.scenario_id = '';
if isfield(scenario, 'scenario_id')
    result.fingerprint.scenario_id = scenario.scenario_id;
end
end

function offsets=device_offsets(devices)
offsets=zeros(numel(devices),1); cursor=0;
for k=1:numel(devices), offsets(k)=cursor; cursor=cursor+devices(k).nx; end
end

function summary=build_execution_summary(eq,ts,event_log,scenario)
% Invocation counts are pipeline-owned calls, separate from Newton/FD work.
summary=struct('pf_stage_invocations',3, ...
    'pf_stage_names',{{'device_factory_warm_start','equilibrium_dae_warm_start','ts_dae_warm_start'}}, ...
    'equilibrium_invocations',1,'equilibrium_newton_iterations',eq.iterations, ...
    'sssa_invocations',0,'selector_candidate_evaluations',0, ...
    'ts_invocations',1,'ts_step_attempts',0,'ts_accepted_steps',0, ...
    'ts_newton_iterations',0,'event_transactions',numel(event_log));
if isfield(ts,'step_attempts'), summary.ts_step_attempts=ts.step_attempts;
elseif isfield(ts,'iter_per_step'), summary.ts_step_attempts=numel(ts.iter_per_step); end
if isfield(ts,'accepted_steps'), summary.ts_accepted_steps=ts.accepted_steps;
elseif isfield(ts,'converged') && ts.converged, summary.ts_accepted_steps=summary.ts_step_attempts;
else, summary.ts_accepted_steps=max(0,summary.ts_step_attempts-1); end
if isfield(ts,'iterations_per_step'), summary.ts_newton_iterations=sum(ts.iterations_per_step);
elseif isfield(ts,'iter_per_step'), summary.ts_newton_iterations=sum(ts.iter_per_step); end
if isfield(scenario,'selection_log') && scenario.selection_log.selector_evaluated
    summary.selector_candidate_evaluations=scenario.selection_log.candidate_count;
    summary.equilibrium_invocations=summary.equilibrium_invocations+ ...
        scenario.selection_log.equilibrium_evaluations;
    summary.sssa_invocations=scenario.selection_log.sssa_evaluations;
    % Each evaluated selector candidate builds a device PF warm-start and
    % assembles equilibrium + SSSA DAEs, each of which owns one PF warm-start.
    summary.pf_stage_invocations=summary.pf_stage_invocations+ ...
        3*scenario.selection_log.equilibrium_evaluations;
end
end
