function m = ieee14_arm_metrics(r,arm,t_end_requested)
%IEEE14_ARM_METRICS  Per-arm metrics for the IEEE 14-bus chronology study.
%
%   m = ieee14_arm_metrics(r, arm, t_end_requested)
%
% Every field is defined on a TRUNCATED arm as well as on a full-horizon one:
% numeric fields default to NaN (never []) and char fields to '', so a struct
% array of arms of different lengths always survives struct2table. That is a
% deliberate departure from the older summarize() helper in
% run_ieee14_controller_comparison.m, whose min(f(isfinite(f))) idiom returns []
% on an arm with no finite frequency sample and silently produces an empty
% field.
%
% Nothing here is a cross-arm comparison. Trajectory-length-dependent
% quantities (integrals, whole-run extrema, switch counts) are DELIBERATELY not
% reported as comparable numbers: an arm that ends at t = 20 s and an arm that
% ends at t = 250 s are exposed to different disturbances, so comparing their
% whole-run extrema measures horizon length, not control performance. Use
% ieee14_arm_common_window for anything compared between arms.
%
% Classification: ASSUMED_DIAGNOSTIC reporting metrics. No value returned here
% feeds a solver, selector, controller or acceptance decision.

arguments
    r struct
    arm struct
    t_end_requested (1,1) double
end

m = empty_record();
m.id = arm.id;
m.label = arm.label;
m.short_label = arm.short_label;
m.expectation = arm.expectation;
m.expected_failure_id = arm.expected_failure_id;
m.classification = arm.classification;
m.requested_t_end_s = t_end_requested;

m.converged = isfield(r,'converged') && logical(r.converged);
if isfield(r,'t') && ~isempty(r.t)
    m.t_end_s = r.t(end);
    m.n_accepted_samples = numel(r.t);
    m.horizon_fraction = r.t(end)/t_end_requested;
end
m.failure_id     = char_field(r,'failure_id');
m.failure_reason = char_field(r,'failure_reason');
m.reclose_status = char_field(r,'reclose_status');
m.reselection_status = char_field(r,'reselection_status');
m.stepper        = char_field(r,'stepper');
m.actual_reclose_time = nan_field(r,'actual_reclose_time');
m.rejected_steps      = nan_field(r,'rejected_steps');
m.floor_accepted_steps = nan_field(r,'floor_accepted_steps');

if isfield(r,'sample_side') && ~isempty(r.sample_side)
    m.last_sample_side = char(string(r.sample_side{end}));
end
if isfield(r,'sched') && isstruct(r.sched) && isfield(r.sched,'sg_trip')
    m.sg_trip_s = r.sched.sg_trip;
end
if isfield(r,'device_online_history') && ~isempty(r.device_online_history)
    m.sg_online_at_end = logical(r.device_online_history(1,end));
end
if isfield(r,'coi_frequency_Hz') && ~isempty(r.coi_frequency_Hz)
    f = r.coi_frequency_Hz(:);
    f = f(isfinite(f));
    if ~isempty(f), m.terminal_f_coi_Hz = f(end); end
end
if isfield(r,'bus_voltage_magnitude') && ~isempty(r.bus_voltage_magnitude)
    V = r.bus_voltage_magnitude(:,end);
    V = V(isfinite(V));
    if ~isempty(V)
        m.terminal_min_V_pu = min(V);
        m.terminal_max_V_pu = max(V);
    end
end

% --- GFM population, from the accepted mode history ------------------------
if isfield(r,'device_modes_history') && ~isempty(r.device_modes_history)
    gfm = strcmpi(r.device_modes_history,'gfm');
    n_gfm = sum(gfm,1);
    m.n_gfm_at_end = n_gfm(end);
    m.n_gfm_max    = max(n_gfm);
    m.n_gfm_min    = min(n_gfm);
end

% --- Supervisor and transaction counts, from the event log -----------------
if isfield(r,'event_log') && ~isempty(r.event_log)
    ty = string({r.event_log.type});
    ap = false(1,numel(r.event_log));
    for k = 1:numel(r.event_log)
        if isfield(r.event_log(k),'applied') && ~isempty(r.event_log(k).applied)
            ap(k) = logical(r.event_log(k).applied);
        end
    end
    m.n_events = numel(r.event_log);
    m.n_support_augment_applied  = sum(ty=="gfm_support_augment" &  ap);
    m.n_support_augment_rejected = sum(ty=="gfm_support_augment" & ~ap);
    m.n_support_release_applied  = sum(ty=="gfm_support_release" &  ap);
    m.n_support_release_rejected = sum(ty=="gfm_support_release" & ~ap);
    m.n_reselection              = sum(ty=="sg_reselection");
    m.n_sg_trip_entries          = sum(ty=="sg_trip");
    trip = find(ty=="sg_trip",1);
    if ~isempty(trip)
        m.sg_trip_applied = ap(trip);
        m.n_failing_islands_at_trip = ...
            nan_field(r.event_log(trip),'n_failing_islands');
    end
end

m.agsi_reference_status = 'ABSENT';
if isfield(r,'agsi_reference') && isstruct(r.agsi_reference) && ...
        isfield(r.agsi_reference,'status')
    m.agsi_reference_status = char(string(r.agsi_reference.status));
end

[m.expectation_met,m.expectation_detail] = ...
    check_expectation(r,arm,t_end_requested,m);
end

% ==========================================================================
function [ok,detail] = check_expectation(r,arm,t_end,m)
%CHECK_EXPECTATION  A predicted fail-closed is a PASS for this study.
%   The FAILS_CLOSED branch is deliberately strict. A loose test would let an
%   arm that died at an unrelated time for an unrelated reason count as the
%   predicted refusal, which would make the whole comparison worthless.
detail = struct('checks',{{}},'passed',[],'first_failure','');
switch upper(arm.expectation)
    case 'REACHES_T_END'
        c = { ...
          'converged',            m.converged; ...
          'reached_t_end',        isfinite(m.t_end_s) && abs(m.t_end_s-t_end)<=1e-10; ...
          'no_failure_id',        isempty(m.failure_id); ...
          'states_finite',        traj_finite(r)};
    case 'FAILS_CLOSED'
        tsg = m.sg_trip_s;
        c = { ...
          'not_converged',        ~m.converged; ...
          'failure_id_matches',   strcmp(m.failure_id,arm.expected_failure_id); ...
          'flag_reached_metadata', flag_false_in_metadata(r); ...
          'one_sg_trip_entry',    isequaln(m.n_sg_trip_entries,1); ...
          'sg_trip_not_applied',  isequaln(m.sg_trip_applied,false); ...
          'failing_islands_seen', isfinite(m.n_failing_islands_at_trip) && ...
                                  m.n_failing_islands_at_trip>=1; ...
          'stopped_short',        isfinite(m.t_end_s) && m.t_end_s < t_end-1e-9; ...
          'stopped_at_the_trip',  isfinite(tsg) && isfinite(m.t_end_s) && ...
                                  abs(m.t_end_s-tsg) <= 1e-6; ...
          'no_right_sample_after_trip', no_right_sample_after(r,tsg); ...
          'last_sample_is_left',  strcmp(m.last_sample_side,'left'); ...
          'sg_still_online',      isequaln(m.sg_online_at_end,true); ...
          'reclose_not_requested', strcmp(m.reclose_status,'NOT_REQUESTED'); ...
          'states_finite',        traj_finite(r)};
    case 'TRAJECTORY_THEN_ANY'
        % The arm must integrate past the trip and produce a usable trajectory.
        % Whether it survives to the horizon is the RESULT, not the gate: the
        % point of this arm is to measure how far one pinned grid-forming unit
        % gets, and tuning anything to make it survive would destroy the answer.
        tsg = m.sg_trip_s;
        c = { ...
          'integrated_past_trip', isfinite(m.t_end_s) && isfinite(tsg) && ...
                                  m.t_end_s > tsg + 1e-9; ...
          'states_finite',        traj_finite(r); ...
          'has_samples',          isfinite(m.n_accepted_samples) && ...
                                  m.n_accepted_samples > 1};
    otherwise
        error('ieee14_arm_metrics:badExpectation', ...
            'Unknown expectation "%s".',arm.expectation);
end
detail.checks  = c(:,1).';
detail.passed  = logical(cell2mat(c(:,2)));
ok = all(detail.passed);
if ~ok
    detail.first_failure = detail.checks{find(~detail.passed,1)};
end
end

% ==========================================================================
function tf = traj_finite(r)
tf = true;
for f = {'x_traj','y_traj'}
    if isfield(r,f{1}) && ~isempty(r.(f{1}))
        tf = tf && all(isfinite(r.(f{1})(:)));
    end
end
end

function tf = flag_false_in_metadata(r)
tf = isfield(r,'metadata') && isstruct(r.metadata) && ...
    isfield(r.metadata,'automatic_gfm_switching') && ...
    isequal(logical(r.metadata.automatic_gfm_switching),false);
end

function tf = no_right_sample_after(r,tsg)
tf = false;
if ~isfield(r,'sample_side') || ~isfield(r,'t') || ~isfinite(tsg), return; end
right = strcmp(r.sample_side(:).','right');
tf = ~any(right & r.t(:).' >= tsg - 1e-9);
end

function v = nan_field(s,name)
v = NaN;
if isfield(s,name) && ~isempty(s.(name)) && isnumeric(s.(name)) && ...
        isscalar(s.(name))
    v = double(s.(name));
end
end

function v = char_field(s,name)
v = '';
if isfield(s,name) && ~isempty(s.(name))
    v = char(string(s.(name)));
end
end

% ==========================================================================
function m = empty_record()
%EMPTY_RECORD  Every field present, numeric NaN and char '' -- never [].
m = struct( ...
    'id','','label','','short_label','','classification','', ...
    'expectation','','expected_failure_id','', ...
    'expectation_met',false,'expectation_detail',struct(), ...
    'converged',false,'t_end_s',NaN,'requested_t_end_s',NaN, ...
    'horizon_fraction',NaN,'n_accepted_samples',NaN, ...
    'failure_id','','failure_reason','', ...
    'reclose_status','','actual_reclose_time',NaN,'reselection_status','', ...
    'last_sample_side','','sg_trip_s',NaN,'sg_online_at_end',false, ...
    'sg_trip_applied',false,'n_failing_islands_at_trip',NaN, ...
    'terminal_f_coi_Hz',NaN,'terminal_min_V_pu',NaN,'terminal_max_V_pu',NaN, ...
    'n_gfm_at_end',NaN,'n_gfm_max',NaN,'n_gfm_min',NaN, ...
    'n_events',NaN,'n_sg_trip_entries',NaN, ...
    'n_support_augment_applied',NaN,'n_support_augment_rejected',NaN, ...
    'n_support_release_applied',NaN,'n_support_release_rejected',NaN, ...
    'n_reselection',NaN,'rejected_steps',NaN,'floor_accepted_steps',NaN, ...
    'stepper','','agsi_reference_status','', ...
    'wall_time_s',NaN,'reused_cache',false,'artifact','');
end
