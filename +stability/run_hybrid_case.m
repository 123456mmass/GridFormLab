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
    'selector_log', struct(), 'reclose_log', struct(), ...
    'domain_rejected_trials', 0, 'subdivision_depth', 0);

if ~isfield(scenario, 'case_data') || ~isfield(scenario, 'resources')
    result.metadata.failure = 'run_hybrid_case:invalidScenario';
    return;
end

case_data = scenario.case_data;
resources = scenario.resources;

% --- C0: Resolve automatic_gfm_switching canonical value EARLY ------------
% Normalize/validate the switching flag IMMEDIATELY after the scenario-schema
% check, BEFORE device build and equilibrium. A conflict or non-scalar/non-
% boolean value must fail closed here without wasting the expensive
% build_mixed_resource_devices + mixed_equilibrium_solve computation. The
% nested opt.ibr_events.automatic_gfm_switching is the validated event-schedule
% value (set by comparison runners); the top-level flag is backward-compat
% only. If both are explicitly set and conflict, fail closed with a structured
% result (do not throw an uncaught error).
has_ibr_events_field = isfield(opt,'ibr_events') && isstruct(opt.ibr_events);
has_nested = has_ibr_events_field && ...
    isfield(opt.ibr_events,'automatic_gfm_switching') && ...
    ~isempty(opt.ibr_events.automatic_gfm_switching);
has_top = isfield(opt,'automatic_gfm_switching') && ...
    ~isempty(opt.automatic_gfm_switching);
% Type validation: a valid flag is scalar and boolean (or convertible).
% Non-scalar or non-boolean values fail closed with a structured result.
nested_ok = true; nested_val = []; nested_reason = '';
if has_nested
    [nested_ok, nested_val, nested_reason] = validate_agfm( ...
        opt.ibr_events.automatic_gfm_switching, 'ibr_events');
end
top_ok = true; top_val = []; top_reason = '';
if has_top
    [top_ok, top_val, top_reason] = validate_agfm( ...
        opt.automatic_gfm_switching, 'top-level');
end
if ~nested_ok || ~top_ok
    result.converged = false;
    result.failure_id = 'run_hybrid_case:automaticGfmSwitchingInvalidType';
    if ~nested_ok, msg = nested_reason; else, msg = top_reason; end
    result.failure_reason = msg;
    result.metadata.failure = result.failure_id;
    result.metadata.error = msg;
    result.metadata.automatic_gfm_switching = [];
    return;
end
event_opt = struct();
if has_ibr_events_field, event_opt = opt.ibr_events; end
canonical_agfm = true;   % backward-compat default when neither is set
if has_top && ~has_nested
    % Top-level only: promote to the event schedule (canonical location).
    canonical_agfm = top_val;
    event_opt.automatic_gfm_switching = top_val;
elseif has_nested && ~has_top
    canonical_agfm = nested_val;
elseif has_nested && has_top
    if nested_val ~= top_val
        % Unresolvable conflict: structured fail-closed result.
        result.converged = false;
        result.failure_id = 'run_hybrid_case:automaticGfmSwitchingConflict';
        result.failure_reason = sprintf(['automatic_gfm_switching: ' ...
            'top-level (%d) conflicts with ibr_events (%d).'], ...
            top_val, nested_val);
        result.metadata.failure = result.failure_id;
        result.metadata.error = result.failure_reason;
        result.metadata.automatic_gfm_switching = [];
        return;
    end
    canonical_agfm = nested_val;
end
result.metadata.automatic_gfm_switching = canonical_agfm;

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
% Presentation-only long-run progress log (opt-in): forward the file/interval
% to the TS driver so a >1 h batch can be tailed live. No numerical output
% depends on these fields.
if isfield(opt,'progress_every') && ~isempty(opt.progress_every)
    ts_opt_base.progress_every = opt.progress_every;
end
if isfield(opt,'progress_file') && ~isempty(opt.progress_file)
    ts_opt_base.progress_file = opt.progress_file;
end
if isfield(opt,'max_step_subdivisions') && ~isempty(opt.max_step_subdivisions)
    ts_opt_base.max_step_subdivisions=opt.max_step_subdivisions;
end
if isfield(opt,'state_predictor') && ~isempty(opt.state_predictor)
    ts_opt_base.state_predictor=opt.state_predictor;
end
% FD Jacobian construction knobs. 'auto' grouping is the kernel default and
% builds the same dense Jacobian as the historical per-column path;
% 'off' forces per-column construction and 'fd_structure_check' builds both
% and requires exact equality. Forwarded so a verification run can pin them.
if isfield(opt,'fd_grouping') && ~isempty(opt.fd_grouping)
    ts_opt_base.fd_grouping=opt.fd_grouping;
end
if isfield(opt,'fd_structure_check') && ~isempty(opt.fd_structure_check)
    ts_opt_base.fd_structure_check=opt.fd_structure_check;
end
% Algebraic (y) column grouping. 'auto' (kernel default) combines y columns
% with disjoint closed network neighbourhoods after the per-device y-locality
% proof in stability.ts_fd_y_locality succeeds; 'off' keeps the historical one
% column per group. The grouped Jacobian is bit-identical to the per-column
% construction (verified by fd_structure_check). Forwarded so a run can pin it.
if isfield(opt,'fd_y_grouping') && ~isempty(opt.fd_y_grouping)
    ts_opt_base.fd_y_grouping=opt.fd_y_grouping;
end
% FD perturbation rule (opt-in). 'absolute' is the kernel and driver default, so
% an omitted option leaves the run byte-identical; 'scaled' selects the
% magnitude-proportional step h_j = fd_eps*(1+|z_j|).
if isfield(opt,'fd_perturbation') && ~isempty(opt.fd_perturbation)
    ts_opt_base.fd_perturbation=opt.fd_perturbation;
end
% Limiter-regime freezing inside the coupled Newton solve (opt-in). Forwarded
% only when the caller sets it, so an omitted option leaves the run
% byte-identical. Derivation and failure semantics in
% stability.ts_step_composite; the acceptance gates are untouched.
if isfield(opt,'limiter_regime_freeze') && ~isempty(opt.limiter_regime_freeze)
    ts_opt_base.limiter_regime_freeze=opt.limiter_regime_freeze;
end
if isfield(opt,'limiter_regime_max_outer') && ~isempty(opt.limiter_regime_max_outer)
    ts_opt_base.limiter_regime_max_outer=opt.limiter_regime_max_outer;
end
% Anti-windup blend width (opt-in). Forwarded only when set, so an omitted
% option leaves the run byte-identical: the models' reader returns 0 and the
% hard switch is taken.
if isfield(opt,'anti_windup_blend') && ~isempty(opt.anti_windup_blend)
    ts_opt_base.anti_windup_blend=opt.anti_windup_blend;
end
% Post-reclose field-voltage command timescale (opt-in). 'mode' is the default
% and historical behaviour; 'control' walks Efd over the declared actuator lags.
if isfield(opt,'handback_efd_timescale') && ~isempty(opt.handback_efd_timescale)
    ts_opt_base.handback_efd_timescale=opt.handback_efd_timescale;
end
% Adaptive-step options (opt-in, 2026-08-12). Forwarded only when the caller
% sets each; the fixed path reads none of them, so the default run is
% untouched. All defaults live in ts_simulate_ibr_hybrid's initialize and are
% declared NUMERICAL_METHOD in the adaptive-hybrid plan.
for afield = {'stepper','dt_min','dt_max','dt_max_armed', ...
        'atol_x','rtol_x','atol_y','rtol_y', ...
        'controller_fac','controller_fac_min','controller_fac_max', ...
        'reject_limit','rannacher_window_dt','rannacher_n','adaptive_strict_lte'}
    if isfield(opt,afield{1}) && ~isempty(opt.(afield{1}))
        ts_opt_base.(afield{1}) = opt.(afield{1});
    end
end
% Private NE39 trial เลือก mesh/budget/policy แบบ explicit; default strict คงเดิม.
for tfield={'ne39_trial_timestep_strategy','ne39_trial_max_steps','ne39_assessment_policy'}
    if isfield(opt,tfield{1}) && ~isempty(opt.(tfield{1}))
        ts_opt_base.(tfield{1})=opt.(tfield{1});
    end
end
% Reference-AGSI in-band overlay (opt-in, DIAGNOSTIC ONLY, 2026-08-13). The
% switching supervisor keeps consuming J_V and J_f alone; these options only
% enable a post-processed publication of the remaining standard sub-indices and
% let the caller override their band bases. Forwarded only when set, so a run
% that omits them is byte-identical and carries no extra result field.
for gfield = {'agsi_reference','agsi_rocof_base_Hz_s','agsi_dP_base_pu', ...
        'agsi_scr_floor','agsi_vq_base_pu'}
    if isfield(opt,gfield{1}) && ~isempty(opt.(gfield{1}))
        ts_opt_base.(gfield{1}) = opt.(gfield{1});
    end
end
% Post-reclose mode-reselection policy (opt-OUT, default true). Forwarded only
% when set, so a run that omits it is byte-identical. Declaring the option here
% rather than letting it ride on an unfiltered struct keeps the whitelist
% explicit: every option that reaches the kernel is named in this file.
if isfield(opt,'post_reclose_mode_reselection') && ~isempty(opt.post_reclose_mode_reselection)
    ts_opt_base.post_reclose_mode_reselection = opt.post_reclose_mode_reselection;
end
% Diagnostic-only suspension of the no-voltage-forming refusal at the SG trip
% (allow_no_vf_island, default absent = false). Forwarded only when set, so a
% run that omits it is byte-identical. The refusal remains the production
% behavior; the option exists for labeled diagnostic continuations only.
if isfield(opt,'allow_no_vf_island') && ~isempty(opt.allow_no_vf_island)
    ts_opt_base.allow_no_vf_island = opt.allow_no_vf_island;
end
% Opt-in phase-gauge pinning (angle_gauge_bus / angle_gauge_after,
% ASSUMED_DIAGNOSTIC): slack-gauge fix for sourceless all-GFL islands.
% Forwarded only when set; absent (the default) is byte-identical.
if isfield(opt,'angle_gauge_bus') && ~isempty(opt.angle_gauge_bus)
    ts_opt_base.angle_gauge_bus = opt.angle_gauge_bus;
end
if isfield(opt,'angle_gauge_after') && ~isempty(opt.angle_gauge_after)
    ts_opt_base.angle_gauge_after = opt.angle_gauge_after;
end
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
    % Phase 6: derived diagnostics for the no-event path (read-only
    % reconstruction). Core trajectory fields (t, x_traj, y_traj, converged,
    % residual_per_step, iter_per_step) remain bit-identical. u_history is a
    % new public field = eq.u_eq repeated across samples. bus_voltage_magnitude
    % is reconstructed from y_traj. Device-level diagnostics that require
    % device reconstruct (coi_frequency_Hz, device_P_MW, device_modes_history)
    % are NOT produced on the no-event path; Scenario-A quantitative
    % comparison is limited to voltage metrics, and the gap is documented.
    nt = numel(result.t);
    if nt > 0 && ~isempty(eq.u_eq)
        result.u_history = repmat(eq.u_eq(:), 1, nt);
    else
        result.u_history = [];
    end
    if ~isempty(result.y_traj) && mod(size(result.y_traj,1),2) == 0
        Vmat = complex(result.y_traj(1:2:end,:), result.y_traj(2:2:end,:));
        result.bus_voltage_magnitude = abs(Vmat);
    else
        result.bus_voltage_magnitude = [];
    end
    % First sample is 'initial' (matches the hybrid route's new_samples);
    % subsequent samples are 'continuous'.
    result.sample_side = repmat({'continuous'}, 1, nt);
    if nt >= 1, result.sample_side{1} = 'initial'; end
    result.transaction_id = zeros(1, nt);
    return;
end

% ---- IBR event route (opt-in) --------------------------------------------
% C0: automatic_gfm_switching was already resolved/validated EARLY (before
% device build). event_opt and canonical_agfm are in scope from that block.
% Validate schedule with canonical event_opt.
try
    sched = stability.ibr_event_schedule(case_data, ts_devices, event_opt, t_end, dt);
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
% Overrides may be supplied at top-level OR nested in opt.ibr_events. The
% nested location is the canonical event-schedule value (set by comparison
% runners); top-level is backward-compat. Nested takes precedence when both
% are present (it is the validated schedule value).
if isfield(opt,'synchronism_overrides') && isstruct(opt.synchronism_overrides)
    ts_opt_ibr.synchronism_overrides = opt.synchronism_overrides;
end
if isfield(opt,'delays_overrides') && isstruct(opt.delays_overrides)
    ts_opt_ibr.delays_overrides = opt.delays_overrides;
end
if isfield(event_opt,'synchronism_overrides') && isstruct(event_opt.synchronism_overrides)
    ts_opt_ibr.synchronism_overrides = event_opt.synchronism_overrides;
end
if isfield(event_opt,'delays_overrides') && isstruct(event_opt.delays_overrides)
    ts_opt_ibr.delays_overrides = event_opt.delays_overrides;
end
% Plumb the resource table and precomputed authenticated selector table
% (F1/C7). The TS driver uses the table for Phase-2 SG_ON reselection
% lookup; the resource table is needed by the reselection transaction.
ts_opt_ibr.resources = resources;
% Healthy per-bus reference voltage for the severity-gated SG_ON reselection.
% The gate needs the SG-ONLINE pre-fault PF profile (the healthy operating
% point), NOT the SG-off island equilibrium that eq.y0 holds (V well below 1).
% eq.y0 is therefore never used as a health reference.  Forward each caller
% field independently: the TS validator owns the atomic-pair contract and must
% reject an incomplete pair instead of this layer silently dropping it.  With
% neither field present, the authenticated SG_ON selector remains the legacy
% authority.
if isfield(opt,'healthy_pf_V')
    ts_opt_ibr.healthy_pf_V = opt.healthy_pf_V;
end
if isfield(opt,'healthy_pf_bus_ids')
    ts_opt_ibr.healthy_pf_bus_ids = opt.healthy_pf_bus_ids;
end
% Opt-in real-time two-line AGSI supervisor.  This is deliberately separate
% from automatic_gfm_switching: the latter authorizes the SG-trip formation,
% while this flag authorizes subsequent SG-off support augmentation/release.
if isfield(opt,'automatic_support_supervision')
    ts_opt_ibr.automatic_support_supervision = opt.automatic_support_supervision;
end
for rate_field={'online_rate_measurement','online_rate_options', ...
        'ne39_rate_policy','ne39_policy'}
    name=rate_field{1};
    if isfield(opt,name), ts_opt_ibr.(name)=opt.(name); end
end
severity_fields={'severity_gamma_on','severity_gamma_off', ...
    'severity_T_d_on','severity_T_d_off'};
for k=1:numel(severity_fields)
    name=severity_fields{k};
    if isfield(opt,name), ts_opt_ibr.(name)=opt.(name); end
end
% Propagate canonical value (resolved early, before device build).
ts_opt_ibr.automatic_gfm_switching = canonical_agfm;
if isfield(opt,'controller_mode') && ~isempty(opt.controller_mode)
    ts_opt_ibr.controller_mode=opt.controller_mode;
end
% Support transition certificate (opt-in, AGSI-2026-08-14-02). Forwarded only
% when the caller sets it, so an omitted run stays byte-identical and carries
% no extra field. The kernel default is OFF.
if isfield(opt,'support_transition_certificate') && ...
        ~isempty(opt.support_transition_certificate)
    ts_opt_ibr.support_transition_certificate = opt.support_transition_certificate;
end
if isfield(opt,'controller_trial_evidence') && ~isempty(opt.controller_trial_evidence)
    ts_opt_ibr.controller_trial_evidence=opt.controller_trial_evidence;
end
% network-only แบบไม่เปลี่ยนโหมดไม่มี candidate ให้ commit จึงไม่สร้าง selector.
% จำกัด fault/load/line profiles: ห้าม SG trip/reclose หรือ support supervision.
no_selection_fault = isfield(sched,'event_profile') && ...
    any(strcmp(sched.event_profile,{'fault_only','load_only','line_cycle'})) && ~canonical_agfm && ...
    (~isfield(opt,'automatic_support_supervision') || ...
    isequal(opt.automatic_support_supervision,false) || ...
    isequal(opt.automatic_support_supervision,0));
% Build the precomputed authenticated selector table (SG_OFF + SG_ON) before
% TS. Fail closed if the table cannot be built (no feasible candidate for a
% required context). The table is bound to an immutable selector_table_fingerprint.
if no_selection_fault
    ts_opt_ibr.automatic_support_supervision = false;
    if strcmp(sched.event_profile,'fault_only')
        result.metadata.selector_not_required = 'FAULT_ONLY_NO_MODE_CHANGE_AUTHORISED';
    else
        result.metadata.selector_not_required = 'NETWORK_EVENT_NO_MODE_CHANGE_AUTHORISED';
    end
else
try
    table_opt = struct();
    if isfield(opt,'gamma_req') && ~isempty(opt.gamma_req)
        table_opt.gamma_req = opt.gamma_req;
    end
    % SG_OFF table pinning is MODE-DEPENDENT (advisor #2 / root cause):
    %   automatic       -> NO pin; the table enumerates the full feasible
    %                       count band and the frozen policy picks the winner.
    %                       (Pinning from sched.* here was the defect that
    %                       kept automatic committing the caller's count.)
    %   manual_override -> pin to the manual_candidate tuple so the table
    %                       contains that exact candidate for authenticated
    %                       exact-match lookup at trip time.
    %   off              -> no SG_OFF candidate evidence required.
    if isfield(sched,'selection_request')
        req = sched.selection_request;
    else
        req = struct('mode','automatic');
    end
    if strcmp(req.mode,'manual_override') && isfield(req,'manual_candidate') && ...
            ~isempty(req.manual_candidate)
        mc = req.manual_candidate;
        table_opt.sg_off = struct('n_gfm_required', mc.n_gfm_required, ...
            'reference_resource_index', mc.reference_resource_index);
    elseif strcmp(req.mode,'off')
        % Firmware off: no GFM is committed, so the SG_OFF context is the
        % all-GFL candidate (n_gfm_required=0). Pin to 0 to avoid a full-band
        % enumeration that would attempt SCR/equilibrium/SSSA on candidates
        % the runtime will never commit (and may throw on structural-only
        % paths). This matches the pre-refactor behavior.
        table_opt.sg_off = struct('n_gfm_required', 0);
    else
        % automatic: no sg_off pin -> full-band enumeration.
    end
    % SG_ON context: SG owns the reference, so n_gfm_required may be 0
    % (all-GFL) or more, determined by the selector. The pre_fault dispatch
    % is the SG_ON contract (C2: pre_event_input is authoritative, so the
    % table uses the same dispatch the runtime will restore).
    % SG_ON is an authenticated online-reference context.  By default the
    % table must enumerate the complete 0..N GFM subset universe so staged
    % release can authenticate one-step candidates and the all-GFL endpoint.
    % A caller may explicitly pin a mission-specific count, but the runtime
    % contract never silently pins automatic operation to zero.
    if isfield(opt,'sg_on_n_gfm_required') && ~isempty(opt.sg_on_n_gfm_required)
        table_opt.sg_on = struct('n_gfm_required', opt.sg_on_n_gfm_required);
    end
    supplied_table = false; supplied_fp = ''; supplied_is_lazy = false;
    if isfield(opt,'selector_table') && isstruct(opt.selector_table) && ...
            isfield(opt.selector_table,'selector_table_fingerprint')
        supplied_table = true;
        supplied_is_lazy = is_lazy_style_table(opt.selector_table);
        if supplied_is_lazy && isfield(opt.selector_table,'state_validity_fingerprint')
            supplied_fp = opt.selector_table.state_validity_fingerprint;
        end
        selector_table = opt.selector_table;
    end
    lazy_flag = isfield(opt,'lazy_gfm_search') && isscalar(opt.lazy_gfm_search) && ...
        logical(opt.lazy_gfm_search);
    if (~supplied_table && lazy_flag) || (supplied_table && supplied_is_lazy)
        % --- LAZY path: opt-in build, OR REVALIDATION of a supplied table -----
        % A caller-SUPPLIED lazy table is NOT trusted.  We REBUILD from the live
        % inputs so the engine re-derives its OWN state fingerprint and
        % re-certifies against the ACTUAL state, then REQUIRE the supplied
        % fingerprint to MATCH the recomputed one.  A stale / tampered /
        % arbitrary ('foo') fingerprint therefore fails closed, and the commit
        % decision rests on the freshly certified table, never on a supplied
        % status.  (A caller wanting cheap reuse must use the search's own
        % opt.cache contract, not an unverified table.)
        table_opt.lazy_gfm_search = true;
        forward = {'certificate','budget','candidate_evaluator','state_validity', ...
            'gamma_req'};
        for fi = 1:numel(forward)
            f = forward{fi};
            if isfield(opt,f) && ~isempty(opt.(f)), table_opt.(f) = opt.(f); end
        end
        % Physically-required evidence is mandatory before ANY decision is
        % certified.  If the caller omits the flag we REQUIRE it; if the caller
        % explicitly disables it, that is a DIAGNOSTIC, non-production path and
        % MUST NOT commit.
        if isfield(table_opt,'certificate') && isstruct(table_opt.certificate)
            cert = table_opt.certificate;
        else
            cert = struct();
        end
        if ~isfield(cert,'require_physical_evidence') || isempty(cert.require_physical_evidence)
            cert.require_physical_evidence = true;
        end
        % --- DC-RESERVE gating -------------------------------------------------
        % A mission that can switch a device to GFM MUST prove the dc-source
        % ACTIVE-power reserve before ANY GFM commit.  We REQUIRE it here (rather
        % than omit the item): a context with no dc-reserve producer then becomes
        % CLEARLY INCONCLUSIVE -- the gate is never hidden by omission.  The
        % signal is the mission intent: automatic GFM switching enabled, or a
        % scheduled SG trip (which forces the SG_OFF context to pick GFM IBRs).
        require_dc = false;
        if exist('canonical_agfm','var') && ~isempty(canonical_agfm) && ...
                isscalar(canonical_agfm) && logical(canonical_agfm)
            require_dc = true;   % mission authorises automatic GFM switching
        end
        if isfield(opt,'ibr_events') && isstruct(opt.ibr_events) && ...
                isfield(opt.ibr_events,'sg_trip') && ~isempty(opt.ibr_events.sg_trip)
            require_dc = true;   % scheduled SG trip -> SG_OFF must pick GFM IBRs
        end
        if require_dc
            cert.require_dc_reserve = true;
        end
        % Observable record of the caller's DC-gating decision (regression probe).
        result.metadata.require_dc_reserve = double(require_dc);
        table_opt.certificate = cert;
        if ~logical(cert.require_physical_evidence)
            result.metadata.diagnostic_nonproduction = true;
            result.metadata.failure = 'run_hybrid_case:diagnosticNonProduction';
            result.failure_id = 'run_hybrid_case:diagnosticNonProduction';
            result.failure_reason = ['require_physical_evidence=false is a ' ...
                'diagnostic-only path; refusing to commit.'];
            result.converged = false;
            return;
        end
        % --- Designate the SG_ON reference OWNER (one per island) -----------
        % SG_ON is the pre-event ONLINE-reference context, so its owner is the
        % case's slack synchronous generator, resolved from the network slack
        % bus (NOT a hard-coded id, and NOT "the only online SG"): the search
        % accepts a multi-SG online island and needs exactly ONE designated
        % owner.  If the slack SG cannot be resolved/online we leave the owner
        % unpinned so the selector's own policy decides (a lone online SG
        % resolves itself; >1 without a policy fails closed).  Scoped to the
        % opt-in lazy path so the legacy selector table for IEEE14 is unchanged.
        owner = local_reference_sg_index(case_data, resources);
        if ~isempty(owner)
            if ~isfield(table_opt,'sg_on') || ~isstruct(table_opt.sg_on)
                table_opt.sg_on = struct();
            end
            table_opt.sg_on.reference_resource_index = owner;
        end
        fresh = stability.ibr_selector_search_lazy( ...
            case_data, resources, scenario, table_opt);
        if supplied_table
            % Freshness + tamper: the fingerprint recomputed from the LIVE state
            % must equal the one the caller's table claims.
            recomputed_fp = '';
            if isfield(fresh,'state_validity_fingerprint')
                recomputed_fp = fresh.state_validity_fingerprint;
            end
            if isempty(supplied_fp) || isempty(recomputed_fp) || ...
                    ~strcmp(char(supplied_fp), char(recomputed_fp))
                result.metadata.failure = 'run_hybrid_case:suppliedTableStale';
                result.failure_id = 'run_hybrid_case:suppliedTableStale';
                result.failure_reason = ['Supplied selector table ' ...
                    'state_validity_fingerprint does not match the fingerprint ' ...
                    'recomputed from the live state; a stale, tampered, or ' ...
                    'arbitrary table is refused.'];
                result.converged = false;
                return;
            end
            if isfield(opt.selector_table,'selector_table_fingerprint') && ...
                    isfield(fresh,'selector_table_fingerprint') && ...
                    ~strcmp(char(opt.selector_table.selector_table_fingerprint), ...
                            char(fresh.selector_table_fingerprint))
                result.metadata.failure = 'run_hybrid_case:suppliedTableMismatch';
                result.failure_id = 'run_hybrid_case:suppliedTableMismatch';
                result.failure_reason = ['Supplied selector_table_fingerprint ' ...
                    'does not match the recomputed table fingerprint.'];
                result.converged = false;
                return;
            end
        end
        selector_table = fresh;
        result.selector_table = selector_table;
        % Commit gate on the ACTIVE context only (SG_ON is the pre-event, online
        % reference context).  Same gate for the built and revalidated paths.
        [gate_ok, gate_fid, gate_reason, gate_status] = ...
            verify_lazy_active_commit(selector_table,resources);
        if ~gate_ok
            result.metadata.failure = 'run_hybrid_case:selectorLazyHold';
            result.metadata.selector_status = gate_status;
            result.failure_id = gate_fid;
            result.failure_reason = gate_reason;
            result.converged = false;
            return;
        end
    elseif ~supplied_table
        selector_table = stability.ibr_selector_table(case_data, resources, ...
            scenario, table_opt);
    end
    ts_opt_ibr.selector_table = selector_table;
    result.metadata.selector_table_fingerprint = selector_table.selector_table_fingerprint;
catch me
    result.metadata.failure = 'run_hybrid_case:selectorTableBuild';
    result.metadata.error = me.message;
    result.metadata.error_id = me.identifier;
    result.failure_id = 'run_hybrid_case:selectorTableBuild';
    result.failure_reason = me.message;
    result.converged = false;
    return;
end
end

[ts_res, ts_meta] = stability.ts_simulate_ibr_hybrid(case_data, ts_devices, ...
    eq.x0, eq.y0, ts_opt_ibr);

result.x_traj = ts_res.x_traj;
result.y_traj = ts_res.y_traj;
result.u_history = ts_res.u_history;
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
if isfield(ts_res,'accepted_residual_per_step')
    result.accepted_residual_per_step = ts_res.accepted_residual_per_step;
else
    result.accepted_residual_per_step = [];
end
result.iter_per_step = ts_res.iter_per_step;
result.requested_sg_on_time = ts_res.requested_sg_on_time;
result.actual_reclose_time = ts_res.actual_reclose_time;
result.reclose_status = ts_res.reclose_status;
copy_fields={'handback_status','handback_start_time','handback_duration_s', ...
    'handback_complete_time'};
for kcopy=1:numel(copy_fields)
    if isfield(ts_res,copy_fields{kcopy})
        result.(copy_fields{kcopy})=ts_res.(copy_fields{kcopy});
    end
end
result.sched = ts_res.sched;
% New Phase-2 reselection + reference-ownership fields (F1/C1/F5).
if isfield(ts_res,'actual_mode_reselection_time')
    result.actual_mode_reselection_time = ts_res.actual_mode_reselection_time;
else
    result.actual_mode_reselection_time = NaN;
end
if isfield(ts_res,'reselection_status')
    result.reselection_status = ts_res.reselection_status;
else
    result.reselection_status = 'NOT_REQUESTED';
end
% Structured refusal reasons behind the aggregate status above (diagnostic only).
if isfield(ts_res,'reselection_rejection_detail')
    result.reselection_rejection_detail = ts_res.reselection_rejection_detail;
else
    result.reselection_rejection_detail = {};
end
if isfield(ts_res,'reference_owner_indices')
    result.reference_owner_indices = ts_res.reference_owner_indices;
end
if isfield(ts_res,'gfm_reference_resource_indices')
    result.gfm_reference_resource_indices = ts_res.gfm_reference_resource_indices;
end
if isfield(ts_res,'reference_island_ids')
    result.reference_island_ids = ts_res.reference_island_ids;
end
if isfield(ts_res,'committed_config_fingerprint')
    result.committed_config_fingerprint = ts_res.committed_config_fingerprint;
end
if isfield(ts_res,'pre_event_input_fingerprint')
    result.pre_event_input_fingerprint = ts_res.pre_event_input_fingerprint;
end
if isfield(ts_res,'selector_table_fingerprint')
    result.selector_table_fingerprint = ts_res.selector_table_fingerprint;
end
if isfield(ts_res,'t_sg_trip'), result.t_sg_trip = ts_res.t_sg_trip; end
if isfield(ts_res,'failure_id')
    result.failure_id = ts_res.failure_id;
    result.metadata.failure = ts_res.failure_id;
end
if isfield(ts_res,'failure_reason')
    result.failure_reason = ts_res.failure_reason;
    result.metadata.error = ts_res.failure_reason;
end
% Additive domain-preserving diagnostics (default 0; absent on early-fail
% paths that never reached TS).
result.domain_rejected_trials = ts_safe_counter(ts_res,'domain_rejected_trials');
result.subdivision_depth = ts_safe_counter(ts_res,'subdivision_depth');
copy_fields = {'online_rate_log','online_rate_series','online_rate_jumps', ...
    'ne39_decision_log','ne39_policy','ne39_assessment', ...
    'sample_side','topology_history','active_state_history', ...
    'event_context_history', ...
    'device_online_history','device_frequency_Hz','coi_frequency_Hz', ...
    'device_P_pu','device_Q_pu','device_P_MW','device_Q_MVAr', ...
    'device_current_limit_sys','device_ids','device_bus_ids','bus_ids', ...
    'sg_sync_controller','resync_diagnostics','controller_audit', ...
    'last_synchronism_guard','transaction_id'};
for k = 1:numel(copy_fields)
    name = copy_fields{k};
    if isfield(ts_res,name), result.(name) = ts_res.(name); end
end
% Stepper provenance + adaptive-only diagnostics. res.stepper is always
% published by the TS driver; the dt/LTE/rejection records exist only on the
% adaptive path, so a fixed run keeps its exact prior field set aside from the
% additive provenance label.
adaptive_fields = {'stepper','dt_history','lte_history','rejected_steps', ...
    'floor_accepted_steps','adaptive_strict_lte','rejection_history', ...
    'agsi_reference'};
for k = 1:numel(adaptive_fields)
    name = adaptive_fields{k};
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

function tf = is_lazy_style_table(t)
%IS_LAZY_STYLE_TABLE  True for a lazy selector table (SG_ON/SG_OFF contexts).
%   Legacy exhaustive tables carry no per-context selection_status, so they keep
%   their own code path and are not routed through the lazy entry gate.
tf = isstruct(t) && isfield(t,'sg_on') && isstruct(t.sg_on) && ...
    isfield(t.sg_on,'selection_status');
end

function [ok, failure_id, reason, status] = verify_lazy_active_commit(table,resources)
%VERIFY_LAZY_ACTIVE_COMMIT  Pre-TS entry gate for a lazy-style selector table.
%   A table is admissible only when the ACTIVE (SG_ON) context is CERTIFIED,
%   ready_to_commit is set, AND the runtime state the table was computed for is
%   BOUND (state_validity_fingerprint present -> require_state is mandatory).  A
%   fingerprint match alone is NOT proof of certification and is never accepted
%   as one.  This gate is shared by the freshly-built lazy table and a
%   caller-SUPPLIED table so the two paths cannot disagree (fail-closed).
ok = false; failure_id = ''; reason = ''; status = 'UNINITIALIZED';
if ~isstruct(table) || ~isfield(table,'sg_on') || ~isstruct(table.sg_on)
    failure_id = 'run_hybrid_case:selectorEntryGate';
    reason = 'Selector table has no SG_ON active context.';
    return;
end
a = table.sg_on;
if isfield(a,'selection_status') && ~isempty(a.selection_status)
    status = char(a.selection_status);
end
if ~strcmp(status,'CERTIFIED')
    failure_id = 'run_hybrid_case:selectorEntryGate';
    if isfield(a,'failure_id') && ~isempty(a.failure_id)
        failure_id = char(a.failure_id);
    end
    if isfield(a,'selection_reason') && ~isempty(a.selection_reason)
        reason = char(a.selection_reason);
    end
    if isempty(reason)
        reason = sprintf('SG_ON context is %s, not CERTIFIED.', status);
    end
    return;
end
if ~isfield(a,'ready_to_commit') || ~logical(a.ready_to_commit)
    failure_id = 'run_hybrid_case:selectorEntryGate';
    reason = 'SG_ON is CERTIFIED but ready_to_commit is not set.';
    return;
end
if ~isfield(table,'state_validity_fingerprint') || isempty(table.state_validity_fingerprint)
    failure_id = 'run_hybrid_case:selectorEntryGate';
    reason = ['No bound state_validity_fingerprint: a table without the ' ...
        'runtime state it was computed for must not commit (require_state).'];
    return;
end
% ต้องมี certificate ของ initial modes จริง ไม่ใช่แค่มี subset อื่นที่ผ่าน.
matched = false;
if isfield(a,'configurations')
    for k=1:numel(a.configurations)
        c=a.configurations(k);
        if ~isfield(c,'ready_to_commit') || ~c.ready_to_commit || ...
                ~isfield(c,'feasible') || ~c.feasible || ...
                ~isfield(c,'modes') || numel(c.modes)~=numel(resources)
            continue;
        end
        same = true;
        for j=1:numel(resources)
            same = same && strcmpi(char(c.modes{j}),char(resources(j).initial_mode));
        end
        if same, matched=true; break; end
    end
end
if ~matched
    failure_id='run_hybrid_case:initialModesNotCertified';
    reason='No certified SG_ON candidate matches the actual initial device modes.';
    return;
end
ok = true;
end

function idx = local_reference_sg_index(case_data, resources)
%LOCAL_REFERENCE_SG_INDEX  Resource index of the case's slack synchronous SG.
%   Resolved from the network slack bus (mpc.bus type 1), never a hard-coded id.
%   Returns [] when the case exposes no slack bus or no online SG sits on it, so
%   the caller leaves the reference owner unpinned and the selector's own policy
%   decides.
idx = [];
if ~isfield(case_data,'mpc') || ~isfield(case_data.mpc,'bus') || ...
        isempty(case_data.mpc.bus)
    return;
end
bus = case_data.mpc.bus;
% case_data.mpc.bus is the RAW MATPOWER table: col 2 is MATPOWER's type, where
% 1=PQ, 2=PV, 3=SLACK.  (+cases/case_ne39.m:254 -- the project's INTERNAL
% 1=slack / 3=PQ remap is applied to a SEPARATE proj_type vector, NOT to
% case_data.mpc.bus, so it must not be used here.)  The slack bus is type 3.
srow = find(bus(:,2) == 3, 1);
if isempty(srow), return; end
slack_bus = bus(srow,1);
for k = 1:numel(resources)
    r = resources(k);
    if ~isfield(r,'bus_id') || ~isfield(r,'resource_type'), continue; end
    if strcmpi(char(r.resource_type),'sg') && ...
            isequal(double(r.bus_id), double(slack_bus)) && ...
            (~isfield(r,'initial_online') || logical(r.initial_online))
        idx = k; return;
    end
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
    'ts_newton_iterations',0,'event_transactions',numel(event_log), ...
    'domain_rejected_trials',ts_safe_counter(ts,'domain_rejected_trials'), ...
    'subdivision_depth',ts_safe_counter(ts,'subdivision_depth'));
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

function n = ts_safe_counter(ts, name)
%TS_SAFE_COUNTER  Read an additive TS counter with a stable 0 default so
%   early-fail paths (no TS run) and legacy no-event routes publish the
%   same field shape as the IBR event route.
n = 0;
if isstruct(ts) && isfield(ts,name) && isscalar(ts.(name)) && ...
        isnumeric(ts.(name)) && isfinite(ts.(name))
    n = double(ts.(name));
end
end

function [ok, val, reason] = validate_agfm(raw, where)
%VALIDATE_AGFM  Type-check an automatic_gfm_switching flag value.
%   A valid flag is scalar and boolean (or numeric 0/1 convertible). Returns
%   ok=false with a reason for non-scalar or non-boolean values so the caller
%   can fail closed with a structured result instead of throwing.
if isempty(raw)
    ok = true; val = []; reason = ''; return;
end
if ~isscalar(raw)
    ok = false; val = []; reason = sprintf( ...
        'automatic_gfm_switching (%s) must be scalar, got size [%s].', ...
        where, num2str(size(raw))); return;
end
if islogical(raw) || (isnumeric(raw) && (raw==0 || raw==1))
    ok = true; val = logical(raw); reason = ''; return;
end
ok = false; val = []; reason = sprintf( ...
    'automatic_gfm_switching (%s) must be boolean, got class %s.', ...
    where, class(raw));
end
