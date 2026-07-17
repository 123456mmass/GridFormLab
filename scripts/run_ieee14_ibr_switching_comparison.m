function [results, metrics, plot_paths] = run_ieee14_ibr_switching_comparison(opt)
%RUN_IEEE14_IBR_SWITCHING_COMPARISON  Four-trajectory GFL/GFM switching comparison.
%   [RESULTS, METRICS, PLOT_PATHS] = run_ieee14_ibr_switching_comparison(OPT)
%   executes four scenarios from IDENTICAL initial case data and produces
%   three audited figures that honestly separate natural physical evidence
%   from delay-workflow diagnostics.
%
%   Scenarios (identical network, dispatch, fault bus/impedance, dt,
%   tolerances, initial conditions, measurement definitions, resource-ID
%   mappings; vary only scenario options):
%     A (Normal)        - no fault, no SG trip, 15 s nominal reference.
%     B (No firmware)   - automatic_gfm_switching=false; fault 3.0/3.1,
%                          SG trip 5.0; opens breaker, no GFM commit;
%                          per-island voltage-forming check -> fail closed
%                          noVoltageFormingSource; trajectory ends at the
%                          event-left sample; NEVER extended to 15 s.
%     C-natural         - automatic_gfm_switching=true; physical synchronism
%                          thresholds; expected SYNC_TIMEOUT (physical
%                          evidence).
%     C-workflow        - automatic_gfm_switching=true; relaxed test-guard;
%                          exercises reclose/handback/reselection; labeled
%                          ASSUMED_DIAGNOSTIC / NOT PHYSICAL ACCEPTANCE.
%
%   Figures:
%     1. Main physical-evidence (A, B, C-natural): 6 subplots, 3 lines each.
%     2. Workflow-validation (C-natural vs C-workflow, C-workflow labeled
%        ASSUMED_DIAGNOSTIC).
%     3. Delay (C-workflow-delay-on vs C-workflow-delay-off; same relaxed
%        test-guard; differ ONLY in supervisory delay/hold/lockout; both
%        ASSUMED_DIAGNOSTIC; NEVER describe delay-off as natural synchronism).
%
%   Quantitative metrics (per scenario): frequency nadir + max deviation;
%   min voltage; max normalized current; max RoCoF (if reliable); event/
%   transition times; mode-change count; rejected-transition count;
%   synchronization outcome; max KCL residual; convergence/failure reason.
%
%   Plotting does NOT mutate numerical results. Deterministic PNG + .mat
%   artifacts under output/plots/ + output/comparison/.
%
%   Source: F5/F6/F7/F8/F9/C5/C6 user-approved plan.

arguments
    opt struct = struct()
end

root = pf_init_paths();
out_plots = fullfile(root, 'output', 'plots');
out_comparison = fullfile(root, 'output', 'comparison');
if ~isfolder(out_plots), mkdir(out_plots); end
if ~isfolder(out_comparison), mkdir(out_comparison); end

t_end = 15.0;
if isfield(opt,'t_end') && ~isempty(opt.t_end), t_end = opt.t_end; end
dt = 0.01;
if isfield(opt,'dt') && ~isempty(opt.dt), dt = opt.dt; end

% Common event defaults (IEEE14 demo defaults). The post-trip GFM set is pinned
% to [2 3 4 5] (manual_override) so the comparison isolates delay/synchronism
% behavior across scenarios rather than re-running the automatic selector.
% Automatic selection is exercised by the dedicated integration test.
common_events = struct('enabled',true,'fault_bus',4,'Zf',1i*0.1, ...
    'fault_on',3.0,'fault_clear',3.1,'sg_trip',5.0,'sg_on',8.0, ...
    'selected_gfm_indices',2:5,'reference_resource_index',2);

% Relaxed test-guard for C-workflow variants (ASSUMED_DIAGNOSTIC).
test_guard = struct('synchronism_overrides', ...
    struct('dV_max',10,'df_max',10,'dtheta_max',180), ...
    'delays_overrides',struct('T_sg_min_off_s',0,'dwell_s',0.01,'timeout_s',0.5));

% --- Scenario A: Normal (no events) -------------------------------------
opt_A = struct('t_end',t_end,'dt',dt,'verbose',false, ...
    'ibr_events',struct('enabled',false), ...
    'plot_results',false);
results.A = run_scenario(opt_A, 'A_normal');

% --- Scenario B: No firmware ---------------------------------------------
ev_B = common_events;
ev_B.automatic_gfm_switching = false;
opt_B = struct('t_end',t_end,'dt',dt,'verbose',false, ...
    'ibr_events',ev_B,'plot_results',false);
results.B = run_scenario(opt_B, 'B_no_firmware');

% --- Scenario C-natural: physical synchronism ---------------------------
ev_Cn = common_events;
ev_Cn.automatic_gfm_switching = true;
opt_Cn = struct('t_end',t_end,'dt',dt,'verbose',false, ...
    'ibr_events',ev_Cn,'plot_results',false);
results.C_natural = run_scenario(opt_Cn, 'C_natural');

% --- Scenario C-workflow: relaxed test-guard ----------------------------
ev_Cw = common_events;
ev_Cw.automatic_gfm_switching = true;
opt_Cw = struct('t_end',t_end,'dt',dt,'verbose',false, ...
    'ibr_events',ev_Cw,'plot_results',false);
opt_Cw = merge_struct(opt_Cw, test_guard);
results.C_workflow = run_scenario(opt_Cw, 'C_workflow');

% --- Delay comparison: C-workflow-delay-on vs delay-off ------------------
opt_Cw_delay_on = merge_struct(opt_Cw, test_guard);
results.C_workflow_delay_on = run_scenario(opt_Cw_delay_on, 'C_workflow_delay_on');

delay_off_overrides = struct('delays_overrides', ...
    struct('T_sg_min_off_s',0,'dwell_s',0,'timeout_s',0.5, ...
    'T_minimum_hold_s',0,'T_guard_s',0,'T_lockout_s',0));
opt_Cw_delay_off = merge_struct(opt_Cw, delay_off_overrides);
opt_Cw_delay_off = merge_struct(opt_Cw_delay_off, ...
    struct('synchronism_overrides',test_guard.synchronism_overrides));
results.C_workflow_delay_off = run_scenario(opt_Cw_delay_off, 'C_workflow_delay_off');

% --- Compute metrics -----------------------------------------------------
metrics.A = compute_metrics(results.A);
metrics.B = compute_metrics(results.B);
metrics.C_natural = compute_metrics(results.C_natural);
metrics.C_workflow = compute_metrics(results.C_workflow);
metrics.C_workflow_delay_on = compute_metrics(results.C_workflow_delay_on);
metrics.C_workflow_delay_off = compute_metrics(results.C_workflow_delay_off);

% --- Save .mat artifacts -------------------------------------------------
save(fullfile(out_comparison, 'ieee14_ibr_switching_comparison_results.mat'), ...
    'results', 'metrics', '-v7.3');

% --- Generate figures ----------------------------------------------------
plot_paths = struct();
plot_paths.main = stability.plot_ibr_switching_comparison( ...
    struct('A',results.A,'B',results.B,'C_natural',results.C_natural), ...
    struct('output_dir',out_plots,'figure','main_physical_evidence','visible',false));
plot_paths.workflow = stability.plot_ibr_switching_comparison( ...
    struct('C_natural',results.C_natural,'C_workflow',results.C_workflow), ...
    struct('output_dir',out_plots,'figure','workflow_validation','visible',false));
plot_paths.delay = stability.plot_ibr_switching_comparison( ...
    struct('delay_on',results.C_workflow_delay_on,'delay_off',results.C_workflow_delay_off), ...
    struct('output_dir',out_plots,'figure','delay_comparison','visible',false));

print_metrics(metrics);
end

% =========================================================================
function r = run_scenario(sopt, label)
base = cases.scenario_ieee14_1sg_4ibr();
[scenario, selection] = stability.ibr_configure_scenario(base, sopt);
if ~selection.ready
    r = struct('converged',false,'failure_id','initialSelection', ...
        'failure_reason',sprintf('%s: %s',selection.failure_id,selection.failure_reason), ...
        'label',label);
    return;
end
try
    r = stability.run_hybrid_case(scenario, sopt);
    r.label = label;
catch me
    r = struct('converged',false,'failure_id',me.identifier, ...
        'failure_reason',me.message,'label',label);
end
end

function m = compute_metrics(r)
m = struct();
m.label = '';
if isfield(r,'label'), m.label = r.label; end
m.converged = false;
if isfield(r,'converged'), m.converged = r.converged; end
m.failure_id = '';
if isfield(r,'failure_id'), m.failure_id = r.failure_id; end
m.failure_reason = '';
if isfield(r,'failure_reason'), m.failure_reason = r.failure_reason; end
m.frequency_nadir = NaN;
m.max_frequency_deviation = NaN;
m.min_voltage = NaN;
m.max_normalized_current = NaN;
m.max_rocof = NaN;
m.event_times = struct();
m.n_mode_changes = 0;
m.n_rejected_transitions = 0;
m.synchronization_outcome = '';
m.reselection_status = 'NOT_REQUESTED';
m.max_kcl_residual = NaN;
if ~m.converged, return; end
% Frequency metrics from COI frequency.
if isfield(r,'coi_frequency_Hz') && ~isempty(r.coi_frequency_Hz)
    f = r.coi_frequency_Hz;
    f = f(isfinite(f));
    if ~isempty(f)
        m.frequency_nadir = min(f);
        nominal = 60.0;
        if isfield(r,'sched') && isfield(r.sched,'base_frequency_Hz')
            nominal = r.sched.base_frequency_Hz;
        end
        m.max_frequency_deviation = max(abs(f - nominal));
    end
end
% Min voltage.
if isfield(r,'bus_voltage_magnitude') && ~isempty(r.bus_voltage_magnitude)
    v = r.bus_voltage_magnitude(:);
    v = v(isfinite(v));
    if ~isempty(v), m.min_voltage = min(v); end
end
% Max normalized current |I|/Ilimit.
if isfield(r,'device_current_magnitude') && isfield(r,'device_current_limit_sys')
    imag = r.device_current_magnitude;
    ilim = r.device_current_limit_sys;
    mask = isfinite(ilim) & ilim > 0;
    if any(mask(:))
        ratio = imag(mask) ./ ilim(mask);
        m.max_normalized_current = max(ratio);
    end
end
% Max RoCoF (finite difference of COI frequency).
if isfield(r,'coi_frequency_Hz') && isfield(r,'t') && ~isempty(r.t)
    f = r.coi_frequency_Hz;
    t = r.t;
    finite_mask = isfinite(f);
    if sum(finite_mask) >= 2
        dt_vec = diff(t(finite_mask));
        df_vec = diff(f(finite_mask));
        nonzero = dt_vec > 0;
        if any(nonzero)
            rocof = abs(df_vec(nonzero) ./ dt_vec(nonzero));
            m.max_rocof = max(rocof);
        end
    end
end
% Event/transition times.
if isfield(r,'requested_sg_on_time'), m.event_times.requested_reconnect = r.requested_sg_on_time; end
if isfield(r,'actual_reclose_time'), m.event_times.actual_reclose = r.actual_reclose_time; end
if isfield(r,'actual_mode_reselection_time'), m.event_times.actual_reselection = r.actual_mode_reselection_time; end
if isfield(r,'t_sg_trip'), m.event_times.sg_trip = r.t_sg_trip; end
% Synchronization outcome.
if isfield(r,'reclose_status'), m.synchronization_outcome = r.reclose_status; end
if isfield(r,'reselection_status'), m.reselection_status = r.reselection_status; end
% Mode-change count + rejected transitions from event log.
if isfield(r,'event_log') && ~isempty(r.event_log)
    applied = [r.event_log.applied];
    m.n_mode_changes = sum(applied & ismember({r.event_log.type}, ...
        {'sg_trip','sg_reclose','sg_reselection'}));
    m.n_rejected_transitions = sum(~applied);
end
% Max KCL residual.
if isfield(r,'residual_per_step') && ~isempty(r.residual_per_step)
    m.max_kcl_residual = max(r.residual_per_step(isfinite(r.residual_per_step)));
end
end

function out = merge_struct(base, over)
out = base;
names = fieldnames(over);
for k = 1:numel(names), out.(names{k}) = over.(names{k}); end
end

function print_metrics(metrics)
fprintf('\n=== IEEE14 IBR Switching Comparison Metrics ===\n');
fields = fieldnames(metrics);
for k = 1:numel(fields)
    m = metrics.(fields{k});
    fprintf('\n[%s] converged=%d\n', m.label, m.converged);
    if ~m.converged
        fprintf('  failure: %s -- %s\n', m.failure_id, m.failure_reason);
    end
    fprintf('  freq nadir=%.4f Hz, max dev=%.4f Hz\n', m.frequency_nadir, m.max_frequency_deviation);
    fprintf('  min voltage=%.4f pu, max |I|/Ilim=%.4f\n', m.min_voltage, m.max_normalized_current);
    fprintf('  max RoCoF=%.4f Hz/s, max KCL=%.3e\n', m.max_rocof, m.max_kcl_residual);
    fprintf('  sync outcome=%s, reselection=%s\n', m.synchronization_outcome, ...
        char(string(m.reselection_status)));
    fprintf('  mode changes=%d, rejected=%d\n', m.n_mode_changes, m.n_rejected_transitions);
end
end
