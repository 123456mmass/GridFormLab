function tests = test_ieee14_arm_metrics()
%TEST_IEEE14_ARM_METRICS  Per-arm metric contract (no graphics, no simulation).
%   Falsification targets:
%     1. An empty ([]) field on a truncated arm. The older summarize() helper in
%        run_ieee14_controller_comparison.m assigns min(f(isfinite(f))) directly,
%        which returns [] when no sample is finite; a [] lands in the struct as an
%        empty field and struct2table then fails or drops the row. Every numeric
%        field here must be NaN instead, and a struct array of arms of different
%        lengths must survive struct2table.
%     2. A loose fail-closed gate. If any one element of the documented refusal
%        signature is broken, expectation_met must go false. A gate that passes on
%        "any failure" would let an unrelated early death count as the predicted
%        refusal and would make the whole comparison worthless.
%     3. Hard-coded arm count. A three-arm table must flow through unchanged, so
%        the deferred all-synchronous arm can be appended without a redesign.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath')))); pf_init_paths();
end

% =========================================================================
function test_no_numeric_field_is_empty_on_either_arm_shape(tc)
% An empty NUMERIC field is the hazard: [] lands in the struct as an empty field
% and breaks struct2table. An empty char is fine and is the convention for
% "not applicable" (it prints as '--').
for r = {full_arm(), refused_arm()}
    m = ieee14_arm_metrics(r{1},arm_spec('TRAJECTORY_THEN_ANY'),250);
    f = fieldnames(m);
    for k = 1:numel(f)
        v = m.(f{k});
        if isstruct(v) || ischar(v) || isstring(v), continue; end
        tc.verifyFalse(isempty(v), ...
            sprintf('numeric field %s is empty; it must be NaN instead',f{k}));
    end
end
end

function test_struct_array_of_mixed_length_arms_survives_struct2table(tc)
% The exact failure mode the older summarize() helper produces.
m1 = ieee14_arm_metrics(full_arm(),   arm_spec('REACHES_T_END'),250);
m2 = ieee14_arm_metrics(refused_arm(),arm_spec('FAILS_CLOSED'), 250);
M = [m1 m2];
M = rmfield(M,'expectation_detail');
T = struct2table(M);
tc.verifyEqual(height(T),2);
tc.verifyTrue(all(ismember({'t_end_s','failure_id','n_gfm_max'}, ...
    T.Properties.VariableNames)));
end

function test_reaches_t_end_arm_meets_its_expectation(tc)
m = ieee14_arm_metrics(full_arm(),arm_spec('REACHES_T_END'),250);
tc.verifyTrue(m.expectation_met);
tc.verifyEqual(m.t_end_s,250,'AbsTol',0);
tc.verifyTrue(m.converged);
end

function test_refused_arm_meets_the_fails_closed_expectation(tc)
m = ieee14_arm_metrics(refused_arm(),arm_spec('FAILS_CLOSED'),250);
tc.verifyTrue(m.expectation_met,m.expectation_detail.first_failure);
tc.verifyEqual(m.failure_id,'ts_simulate_ibr_hybrid:noVoltageFormingSource');
tc.verifyEqual(m.t_end_s,20,'AbsTol',0);
end

function test_breaking_any_one_signature_element_fails_the_gate(tc)
% Loop the signature: each mutation must be caught individually.
base = refused_arm();
spec = arm_spec('FAILS_CLOSED');
muts = { ...
  'converged',            @(r) setfield(r,'converged',true); ...
  'failure_id',           @(r) setfield(r,'failure_id','ts_simulate_ibr_hybrid:rightLimit'); ...
  'metadata_flag',        @(r) setfield(r,'metadata',struct('automatic_gfm_switching',true)); ...
  'trip_applied',         @(r) mutate_trip(r,'applied',true); ...
  'failing_islands',      @(r) mutate_trip(r,'n_failing_islands',0); ...
  'stopped_at_the_trip',  @(r) truncate_at(r,12.0); ...
  'right_sample_after',   @(r) add_right_sample(r); ...
  'last_sample_side',     @(r) set_last_side(r,'right'); ...
  'sg_offline',           @(r) set_sg_offline(r); ...
  'reclose_status',       @(r) setfield(r,'reclose_status','SUCCESS'); ...
  'nonfinite_state',      @(r) poison_state(r)};
for k = 1:size(muts,1)
    m = ieee14_arm_metrics(muts{k,2}(base),spec,250);
    tc.verifyFalse(m.expectation_met, ...
        sprintf('mutation "%s" was not caught by the gate',muts{k,1}));
end
end

function test_reaching_the_horizon_does_not_satisfy_fails_closed(tc)
m = ieee14_arm_metrics(full_arm(),arm_spec('FAILS_CLOSED'),250);
tc.verifyFalse(m.expectation_met);
end

function test_refusal_does_not_satisfy_trajectory_then_any(tc)
% The pinned arm's gate requires integrating PAST the trip; a refusal at the trip
% must not pass it.
m = ieee14_arm_metrics(refused_arm(),arm_spec('TRAJECTORY_THEN_ANY'),250);
tc.verifyFalse(m.expectation_met);
tc.verifyEqual(m.expectation_detail.first_failure,'integrated_past_trip');
end

function test_unknown_expectation_fails_closed(tc)
tc.verifyError(@() ieee14_arm_metrics(full_arm(),arm_spec('SOMETHING'),250), ...
    'ieee14_arm_metrics:badExpectation');
end

function test_three_arm_table_flows_through_unchanged(tc)
% The deferred all-synchronous arm gate.
rs = {full_arm(),refused_arm(),full_arm()};
ex = {'REACHES_T_END','FAILS_CLOSED','TRAJECTORY_THEN_ANY'};
M = ieee14_arm_metrics(rs{1},arm_spec(ex{1}),250);
for k = 2:3
    M(end+1) = ieee14_arm_metrics(rs{k},arm_spec(ex{k}),250); %#ok<AGROW>
end
tc.verifyEqual(numel(M),3);
tc.verifyTrue(all([M.expectation_met]));
end

function test_supervisor_counts_separate_applied_from_refused(tc)
m = ieee14_arm_metrics(full_arm(),arm_spec('REACHES_T_END'),250);
tc.verifyEqual(m.n_support_augment_applied,1);
tc.verifyEqual(m.n_support_augment_rejected,1);
tc.verifyEqual(m.n_support_release_applied,1);
end

% =========================================================================
% Common-window pairing (the controlled-experiment guarantee)
% =========================================================================

function test_common_window_is_bit_identical_for_identical_prefixes(tc)
a = full_arm(); b = refused_arm();
c = ieee14_arm_common_window(a,b,20);
tc.verifyTrue(c.bit_identical);
tc.verifyTrue(c.identical_to_tolerance);
tc.verifyEqual(c.split_time_s,20,'AbsTol',0);
tc.verifyGreaterThan(c.n_common,1);
end

function test_common_window_detects_a_perturbed_prefix(tc)
a = full_arm(); b = refused_arm();
b.x_traj(1,3) = b.x_traj(1,3) + 1e-3;
c = ieee14_arm_common_window(a,b,20);
tc.verifyFalse(c.bit_identical);
tc.verifyFalse(c.identical_to_tolerance);
tc.verifyGreaterThan(c.max_abs_x,0);
end

function test_common_window_is_unchanged_by_data_past_the_split(tc)
% The window must genuinely be common: extending one arm must not move it.
a = full_arm(); b = refused_arm();
c1 = ieee14_arm_common_window(a,b,20);
a2 = a; a2.x_traj(:,end) = a2.x_traj(:,end) + 5;  % well past the split
c2 = ieee14_arm_common_window(a2,b,20);
tc.verifyEqual(c2.n_common,c1.n_common);
tc.verifyEqual(c2.max_abs_x,c1.max_abs_x,'AbsTol',0);
end

function test_common_window_with_no_split_returns_a_reason(tc)
c = ieee14_arm_common_window(full_arm(),refused_arm(),NaN);
tc.verifyEqual(c.n_common,0);
tc.verifyNotEmpty(c.note);
tc.verifyFalse(c.bit_identical);
end

% =========================================================================
% Fixtures. Both arms share an IDENTICAL prefix on [0,20), which is what the
% common-window tests exercise.
% =========================================================================
function a = arm_spec(expectation)
a = struct('id','fixture','label','fixture arm','short_label','fixture', ...
    'classification','PROJECT_RESULT','expectation',expectation, ...
    'expected_failure_id','ts_simulate_ibr_hybrid:noVoltageFormingSource');
end

function r = prefix()
%PREFIX  The shared [0,20] s prefix: 41 samples at dt = 0.5 s.
t = (0:0.5:20)';
n = numel(t);
r = struct();
r.t = t;
r.x_traj = repmat(sin(t.'/7),6,1) + (1:6).';
r.y_traj = repmat(cos(t.'/5),28,1);
r.u_history = repmat(0.5*ones(1,n),10,1);
r.device_P_pu = repmat(linspace(0.3,0.4,n),5,1);
r.device_Q_pu = repmat(linspace(0.1,0.2,n),5,1);
r.device_currents = repmat(linspace(0.3,0.4,n),5,1);
r.bus_voltage_magnitude = repmat(1 - 0.001*t.',14,1);
r.coi_frequency_Hz = 60 - 0.01*t;
r.accepted_residual_per_step = 1e-10*ones(n,1);
r.residual_per_step = 1e-10*ones(n,1);
r.sample_side = repmat({'left'},1,n);
r.device_ids = {'SG1','IBR2','IBR3','IBR6','IBR8'};
r.device_bus_ids = [1 2 3 6 8];
r.device_online_history = true(5,n);
r.device_modes_history = [repmat({'synchronous'},1,n); repmat({'gfl'},4,n)];
r.sched = struct('t_end',250,'sg_trip',20,'load_step',50, ...
    'load_step_factor',0.20,'fault_on',85,'fault_clear',85.15, ...
    'line_trip',110,'line_from_bus',6,'line_to_bus',13,'restore_time',145);
r.stepper = 'adaptive';
r.rejected_steps = 3;
r.floor_accepted_steps = 0;
r.reselection_status = 'NO_FEASIBLE_SG_ON_ONE_STEP';
end

function r = full_arm()
%FULL_ARM  Reaches the horizon, promotes and releases grid-forming units.
r = prefix();
t2 = (20.5:0.5:250)';
n2 = numel(t2);
r.t = [r.t; t2];
n = numel(r.t);
r.x_traj = [r.x_traj, repmat(sin(t2.'/7),6,1) + (1:6).'];
r.y_traj = [r.y_traj, repmat(cos(t2.'/5),28,1)];
r.u_history = [r.u_history, repmat(0.5*ones(1,n2),10,1)];
r.device_P_pu = [r.device_P_pu, repmat(linspace(0.4,0.5,n2),5,1)];
r.device_Q_pu = [r.device_Q_pu, repmat(linspace(0.2,0.3,n2),5,1)];
r.device_currents = [r.device_currents, repmat(linspace(0.4,0.5,n2),5,1)];
r.bus_voltage_magnitude = [r.bus_voltage_magnitude, ...
    repmat(0.98 + 0.0001*t2.',14,1)];
r.coi_frequency_Hz = [r.coi_frequency_Hz; 59.8 + 0.0008*t2];
r.accepted_residual_per_step = [r.accepted_residual_per_step; 1e-10*ones(n2,1)];
r.residual_per_step = [r.residual_per_step; 1e-10*ones(n2,1)];
r.sample_side = [r.sample_side, repmat({'left'},1,n2)];
r.device_online_history = [r.device_online_history, true(5,n2)];
modes = [repmat({'synchronous'},1,n2); repmat({'gfm'},4,n2)];
r.device_modes_history = [r.device_modes_history, modes];
r.converged = true;
r.failure_id = '';
r.failure_reason = '';
r.reclose_status = 'SUCCESS';
r.actual_reclose_time = 159.3436;
r.metadata = struct('automatic_gfm_switching',true);
r.event_log = struct( ...
    'type',{'sg_trip','gfm_support_augment','gfm_support_augment','gfm_support_release'}, ...
    't',{20,22.05,53.4025,148.2}, ...
    'applied',{true,true,false,true}, ...
    'n_failing_islands',{0,0,0,0});
tc_check_lengths(r,n);
end

function r = refused_arm()
%REFUSED_ARM  The documented noVoltageFormingSource refusal at the SG trip.
r = prefix();
r.converged = false;
r.failure_id = 'ts_simulate_ibr_hybrid:noVoltageFormingSource';
r.failure_reason = ['noVoltageFormingSource: per-island checks: island has ' ...
    'no VF. Failing islands: 1.'];
r.reclose_status = 'NOT_REQUESTED';
r.actual_reclose_time = NaN;
r.metadata = struct('automatic_gfm_switching',false);
r.event_log = struct('type',{'sg_trip'},'t',{20},'applied',{false}, ...
    'n_failing_islands',{1});
end

% -------------------------------------------------------------------------
function tc_check_lengths(r,n)
assert(size(r.x_traj,2)==n && size(r.y_traj,2)==n && ...
    numel(r.sample_side)==n && numel(r.coi_frequency_Hz)==n, ...
    'fixture length mismatch');
end

function r = mutate_trip(r,field,value)
j = find(strcmp({r.event_log.type},'sg_trip'),1);
r.event_log(j).(field) = value;
end

function r = truncate_at(r,t_stop)
k = find(r.t <= t_stop);
r.t = r.t(k);
r.x_traj = r.x_traj(:,k); r.y_traj = r.y_traj(:,k);
r.u_history = r.u_history(:,k);
r.sample_side = r.sample_side(k);
r.coi_frequency_Hz = r.coi_frequency_Hz(k);
r.bus_voltage_magnitude = r.bus_voltage_magnitude(:,k);
r.device_online_history = r.device_online_history(:,k);
r.device_modes_history = r.device_modes_history(:,k);
end

function r = add_right_sample(r)
r.t(end+1) = r.t(end);
r.sample_side{end+1} = 'right';
r.x_traj(:,end+1) = r.x_traj(:,end);
r.y_traj(:,end+1) = r.y_traj(:,end);
r.u_history(:,end+1) = r.u_history(:,end);
r.coi_frequency_Hz(end+1) = r.coi_frequency_Hz(end);
r.bus_voltage_magnitude(:,end+1) = r.bus_voltage_magnitude(:,end);
r.device_online_history(:,end+1) = r.device_online_history(:,end);
r.device_modes_history(:,end+1) = r.device_modes_history(:,end);
end

function r = set_last_side(r,side)
r.sample_side{end} = side;
end

function r = set_sg_offline(r)
r.device_online_history(1,end) = false;
end

function r = poison_state(r)
r.x_traj(1,end) = Inf;
end
