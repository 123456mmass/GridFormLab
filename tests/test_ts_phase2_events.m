function tests = test_ts_phase2_events()
%TEST_TS_PHASE2_EVENTS  Phase 2 generic scheduled+guard event architecture.
%   Unit tests for the generic event contracts (corrections 1-3) WITHOUT
%   requiring the driver-loop modifications (ts_simulate/ts_adaptive_driver
%   generic-path integration is a follow-up commit). These tests exercise:
%     - ts_hybrid_state_init / ts_hybrid_state_snapshot
%     - ts_transitions_from_legacy (bit-identical adapter)
%     - ts_prevalidate_transitions (coincident semantics)
%     - ts_apply_transition (topology by event_id, hybrid_commit)
%     - ts_evaluate_guards (committed-state evaluation, dwell, timeout)
%
%   Source: project Phase 2 design (user corrections 1-3). Synthetic
%   scaffolding; guard thresholds/dwell ASSUMED_DIAGNOSTIC (excluded from
%   production).
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

% =========================================================================
function test_hybrid_state_init_defaults(testCase)
devices = struct('device_id', {'IBR2','IBR3'}, 'initial_mode', {'gfl','GFM'});
hs = stability.ts_hybrid_state_init(devices);
testCase.verifyEqual(hs.device_modes.IBR2, 'gfl', 'IBR2 default mode.');
testCase.verifyEqual(hs.device_modes.IBR3, 'GFM', 'IBR3 explicit mode.');
testCase.verifyTrue(hs.device_online.IBR2, 'default online=true.');
testCase.verifyEqual(hs.active_configuration_id, '', 'default cfg id empty.');
testCase.verifyEqual(hs.selector_table_version, 0, 'default version 0.');
end

function test_hybrid_state_init_empty(testCase)
hs = stability.ts_hybrid_state_init(struct());
testCase.verifyEqual(numel(fieldnames(hs.device_modes)), 0, 'empty devices.');
end

function test_hybrid_state_snapshot_is_deep_copy(testCase)
devices = struct('device_id','IBR2','initial_mode','gfl');
hs = stability.ts_hybrid_state_init(devices);
snap = stability.ts_hybrid_state_snapshot(hs);
% Mutate the snapshot; live hs must be unchanged (copy-on-write + deep copy).
snap.device_modes.IBR2 = 'GFM';
testCase.verifyEqual(hs.device_modes.IBR2, 'gfl', 'live hs unchanged after snapshot mutation.');
end

function test_hybrid_state_snapshot_rejects_handles(testCase)
hs = struct('device_modes', struct('IBR2', 'gfl'), 'bad_field', @() 0);
testCase.verifyError(@() stability.ts_hybrid_state_snapshot(hs), ...
    'ts_hybrid_state_snapshot:noHandles', 'function_handle rejected.');
end

% =========================================================================
function test_legacy_adapter_fault_on_off(testCase)
events_old = struct('fault_enabled', true, 't_fault', 1.0, 't_clear', 1.1, ...
    'Ypre', 1, 'Yfault', 2, 'Ypost', 3);
events_new = stability.ts_transitions_from_legacy(events_old, [0, 2]);
testCase.verifyEqual(numel(events_new.transitions), 2, 'two transitions.');
testCase.verifyEqual(string(events_new.transitions(1).event_id), "fault_on");
testCase.verifyEqual(events_new.transitions(1).time, 1.0, 'AbsTol', 0);
testCase.verifyEqual(string(events_new.transitions(1).topology_id), "fault");
testCase.verifyEqual(events_new.topologies.fault, 2, 'Yfault preserved.');
testCase.verifyEqual(events_new.topologies.post, 3, 'Ypost preserved.');
testCase.verifyEqual(string(events_new.transitions(2).event_id), "fault_off");
testCase.verifyEqual(string(events_new.transitions(2).topology_id), "post");
end

function test_legacy_adapter_fault_disabled(testCase)
events_old = struct('fault_enabled', false, 't_fault', 1.0, 't_clear', 1.1, ...
    'Ypre', 1, 'Yfault', 2, 'Ypost', 3);
events_new = stability.ts_transitions_from_legacy(events_old, [0, 2]);
testCase.verifyEqual(numel(events_new.transitions), 0, 'no transitions when disabled.');
end

function test_legacy_adapter_preserves_legacy_fields(testCase)
events_old = struct('fault_enabled', true, 't_fault', 1.0, 't_clear', 1.1, ...
    'Ypre', 1, 'Yfault', 2, 'Ypost', 3);
events_new = stability.ts_transitions_from_legacy(events_old, [0, 2]);
testCase.verifyTrue(events_new.fault_enabled, 'legacy fault_enabled preserved.');
testCase.verifyEqual(events_new.t_fault, 1.0, 'AbsTol', 0, 't_fault preserved.');
testCase.verifyEqual(events_new.Yfault, 2, 'Yfault field preserved.');
end

% =========================================================================
function test_prevalidate_scheduled_only(testCase)
[~, events, ~, ~, ~, ~, t_span] = fixtures.synthetic_guard_fixture('scheduled_only');
[times, ids] = stability.ts_prevalidate_transitions(events, t_span, 1e-10);
testCase.verifyEqual(times, [0.5; 1.0; 1.5], 'AbsTol', 0, 'three event times sorted.');
testCase.verifyEqual(ids, ["ev1"; "ev2"; "ev3"], 'event_ids in order.');
end

function test_prevalidate_coincident_ordered_valid(testCase)
[~, events, ~, ~, ~, ~, t_span] = fixtures.synthetic_guard_fixture('coincident_ordered');
[times, ids] = stability.ts_prevalidate_transitions(events, t_span, 1e-10);
testCase.verifyEqual(numel(times), 2, 'two transitions at same time, distinct orders.');
testCase.verifyEqual(times(1), times(2), 'AbsTol', 0, 'same time.');
testCase.verifyEqual(ids(1), "evA", 'order 1 first.');
testCase.verifyEqual(ids(2), "evB", 'order 2 second.');
end

function test_prevalidate_ambiguous_order_fails(testCase)
[~, events, ~, ~, ~, ~, t_span] = fixtures.synthetic_guard_fixture('ambiguous_order');
testCase.verifyError(@() stability.ts_prevalidate_transitions(events, t_span, 1e-10), ...
    'ts_prevalidate_transitions:ambiguousOrder', 'same (time, order) fails closed.');
end

function test_prevalidate_duplicate_event_id_fails(testCase)
events = struct();
events.topologies = struct('A', 1, 'B', 1);
events.transitions = repmat(struct('event_id',"",'time',NaN,'order',0, ...
    'topology_id',"",'atomic_updates',struct(),'hybrid_commit',struct(), ...
    'source','t'), 0, 1);
events.transitions(1) = struct('event_id',"dup",'time',0.5,'order',1, ...
    'topology_id',"A",'atomic_updates',struct(),'hybrid_commit',struct(),'source','t');
events.transitions(2) = struct('event_id',"dup",'time',1.0,'order',1, ...
    'topology_id',"B",'atomic_updates',struct(),'hybrid_commit',struct(),'source','t');
testCase.verifyError(@() stability.ts_prevalidate_transitions(events, [0,2], 1e-10), ...
    'ts_prevalidate_transitions:duplicateEventId', 'duplicate event_id fails.');
end

function test_prevalidate_missing_topology_fails(testCase)
events = struct();
events.topologies = struct('A', 1);   % only 'A'; 'B' missing
events.transitions = repmat(struct('event_id',"",'time',NaN,'order',0, ...
    'topology_id',"",'atomic_updates',struct(),'hybrid_commit',struct(), ...
    'source','t'), 0, 1);
events.transitions(1) = struct('event_id',"ev1",'time',0.5,'order',1, ...
    'topology_id',"B",'atomic_updates',struct(),'hybrid_commit',struct(),'source','t');
testCase.verifyError(@() stability.ts_prevalidate_transitions(events, [0,2], 1e-10), ...
    'ts_prevalidate_transitions:missingTopology', 'missing topology fails.');
end

% =========================================================================
function test_apply_transition_selects_topology_by_id(testCase)
[~, events, hs, x, y, ~, ~] = fixtures.synthetic_guard_fixture('scheduled_only');
strat = struct('needs_algebraic_solve', false);
kopt = struct('algebraic_tolerance', 1e-12);
tr = events.transitions(2);   % ev2: topology_id 'fault'
[y_right, Y_right, hs_new, ec, ~] = stability.ts_apply_transition( ...
    1.0, tr, events, x, y, hs, strat, kopt, false, 1e-10);
testCase.verifyEqual(Y_right, events.topologies.fault, 'AbsTol', 0, ...
    'topology selected by topology_id.');
testCase.verifyEqual(y_right, y, 'AbsTol', 0, 'classical: y unchanged.');
testCase.verifyEqual(ec.event_id, 'ev2', 'event_id threaded.');
testCase.verifyEqual(string(ec.topology_name), "fault", 'topology_name threaded.');
end

function test_apply_transition_no_t_plus_eps_grep(testCase)
% Grep guard: ts_apply_transition must NOT call ts_topology_at (no t+eps).
src = fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+stability', 'ts_apply_transition.m'));
testCase.verifyFalse(~isempty(strfind(src, 'ts_topology_at')), ...
    'ts_apply_transition must not call ts_topology_at (no t+eps discovery).');
testCase.verifyFalse(~isempty(strfind(src, 'eps_floor')), ...
    'no eps_floor-based topology discovery.');
end

function test_apply_transition_hybrid_commit(testCase)
[~, events, hs, x, y, ~, ~] = fixtures.synthetic_guard_fixture('scheduled_plus_guard');
strat = struct('needs_algebraic_solve', false);
kopt = struct('algebraic_tolerance', 1e-12);
g = events.guards(1);
[~, ~, hs_new, ~, ~] = stability.ts_apply_transition( ...
    0.5, g.transition, events, x, y, hs, strat, kopt, false, 1e-10);
testCase.verifyEqual(hs_new.device_modes.IBR2, 'GFM', 'hybrid_commit applied.');
end

% =========================================================================
function test_guards_no_guards_returns_empty(testCase)
events = struct('guards', struct([]));
hs = stability.ts_hybrid_state_init(struct());
ec = struct('t', 0, 'side', 'right', 'topology_name', 'pre', 'event_id', '');
[fired, ~, ~] = stability.ts_evaluate_guards(0, [1;0], [], hs, events, ec, 0.01);
testCase.verifyTrue(isempty(fired), 'no guards => no firing.');
end

function test_guard_fires_after_threshold_and_dwell(testCase)
[~, events, hs, x, y, ~, ~] = fixtures.synthetic_guard_fixture('scheduled_plus_guard');
ec = struct('t', 0, 'side', 'right', 'topology_name', 'pre', 'event_id', '');
% |x(1)| = 1.0 >= 0.8 threshold; dwell=0.05. After 6 steps of dt=0.01 -> 0.06 >= 0.05.
for k = 1:6
    [fired, hs, ~] = stability.ts_evaluate_guards(0.01*k, x, y, hs, events, ec, 0.01);
    if ~isempty(fired)
        break;
    end
end
testCase.verifyFalse(isempty(fired), 'guard fires after threshold+dwell.');
testCase.verifyEqual(string(fired.guard_id), "g1", 'correct guard fired.');
end

function test_guard_disarm_resets_dwell(testCase)
[~, events, hs, x, y, ~, ~] = fixtures.synthetic_guard_fixture('scheduled_plus_guard');
ec = struct('t', 0, 'side', 'right', 'topology_name', 'pre', 'event_id', '');
% 3 steps threshold met (dwell=0.03 < 0.05), then measurement drops below.
[fired, hs, ~] = stability.ts_evaluate_guards(0.01, x, y, hs, events, ec, 0.01);
testCase.verifyTrue(isempty(fired), 'not fired yet (dwell 0.01 < 0.05).');
[fired, hs, ~] = stability.ts_evaluate_guards(0.02, x, y, hs, events, ec, 0.01);
testCase.verifyTrue(isempty(fired), 'not fired yet (dwell 0.02 < 0.05).');
[fired, hs, ~] = stability.ts_evaluate_guards(0.03, x, y, hs, events, ec, 0.01);
testCase.verifyTrue(isempty(fired), 'not fired yet (dwell 0.03 < 0.05).');
% Now measurement drops below threshold: x(1) = 0.7 < 0.8.
x_low = [0.7; 0.0];
[fired, hs, ~] = stability.ts_evaluate_guards(0.04, x_low, y, hs, events, ec, 0.01);
testCase.verifyTrue(isempty(fired), 'still not fired.');
% Dwell timer must have reset to 0.
dwell_key = 'g1';
testCase.verifyEqual(hs.dwell_timers.(dwell_key), 0, 'AbsTol', 0, ...
    'dwell timer reset on disarm.');
end

function test_guard_timeout_fails_closed(testCase)
[~, events, hs, x, y, ~, ~] = fixtures.synthetic_guard_fixture('guard_timeout');
ec = struct('t', 0, 'side', 'right', 'topology_name', 'pre', 'event_id', '');
% threshold met (|x(1)|=1.0>=0.8); timeout=0.01, dwell=0.5. After 2 steps
% (0.02s armed > timeout 0.01) without dwell -> fail closed.
testCase.verifyError(@() stability.ts_evaluate_guards(0.02, x, y, hs, events, ec, 0.01), ...
    'ts_evaluate_guards:timeoutExceeded', 'timeout exceeded fails closed.');
end

function test_guard_priority_deterministic(testCase)
[~, events, hs, x, y, ~, ~] = fixtures.synthetic_guard_fixture('priority_deterministic');
ec = struct('t', 0, 'side', 'right', 'topology_name', 'pre', 'event_id', '');
% dwell=0.01; one step of dt=0.01 fires both. Priority 1 (g1) wins.
[fired, ~, ~] = stability.ts_evaluate_guards(0.01, x, y, hs, events, ec, 0.01);
testCase.verifyFalse(isempty(fired), 'a guard fired.');
testCase.verifyEqual(string(fired.guard_id), "g1", 'priority 1 wins.');
end

function test_guard_priority_ambiguous_fails(testCase)
[~, events, hs, x, y, ~, ~] = fixtures.synthetic_guard_fixture('priority_ambiguous');
ec = struct('t', 0, 'side', 'right', 'topology_name', 'pre', 'event_id', '');
% Both guards priority 1, both fire -> ambiguous.
testCase.verifyError(@() stability.ts_evaluate_guards(0.01, x, y, hs, events, ec, 0.01), ...
    'ts_evaluate_guards:ambiguousPriority', 'ambiguous priority fails closed.');
end
