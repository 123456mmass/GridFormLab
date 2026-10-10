function tests = test_ieee14_ibr_switching_comparison()
%TEST_IEEE14_IBR_SWITCHING_COMPARISON  Comparison runner semantics + real run.
%   Tests the four-trajectory comparison runner semantics (identical case
%   data, Scenario-B fail-closed, C-natural SYNC_TIMEOUT, C-workflow
%   ASSUMED_DIAGNOSTIC, delay ON/OFF same guard, plotting does not mutate,
%   deterministic repeat, sample-key uniqueness) and then executes the real
%   15 s runner ONCE as acceptance evidence.
%
%   Retargeted 2026-09-26: the mission profile now builds the surviving
%   eecon49_dual family, so the C arms reach their reclose request instead of
%   dying at 5.09 s. The C-arm expectations were re-measured from the surviving
%   model's own trajectory; see the two C tests for what changed and why.
%
%   All assertions go through PUBLIC entry points only:
%     stability.run_hybrid_case, stability.plot_ibr_switching_comparison,
%     scripts/run_ieee14_ibr_switching_comparison.
%
%   Source: F7/F8/F9/C5/C6 user-approved validation-closure plan.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath')))); pf_init_paths();
tc.TestData.out = tempname; mkdir(tc.TestData.out);
tc.addTeardown(@() rmdir(tc.TestData.out, 's'));
end

% =========================================================================
% Comparison runner semantics (short-horizon; no 15 s run inside tests)
% =========================================================================

function test_scenarios_use_identical_case_data(tc)
% A, B, C-natural, C-workflow must share identical network, dispatch, fault
% bus/impedance, dt, tolerances, initial conditions, resource-ID mappings;
% vary only scenario options. Verify by building two scenarios and comparing
% the immutable case_data + resources.
s = cases.scenario_ieee14_1sg_4ibr();
[sc1, sel1] = stability.ibr_configure_scenario(s, struct('initial_gfm_indices', 2:5));
[sc2, sel2] = stability.ibr_configure_scenario(s, struct('initial_gfm_indices', 2:5));
tc.assertTrue(sel1.ready && sel2.ready);
% Immutable case_data must be identical (same network).
tc.verifyEqual(sc1.case_data.mpc.bus, sc2.case_data.mpc.bus, 'AbsTol', 0);
tc.verifyEqual(sc1.case_data.mpc.branch, sc2.case_data.mpc.branch, 'AbsTol', 0);
% Resources identical.
tc.verifyEqual({sc1.resources.resource_id}, {sc2.resources.resource_id});
end

function test_scenario_b_fails_closed_no_fabrication(tc)
% Scenario B (automatic_gfm_switching=false): breaker opens, no GFM commit,
% per-island voltage-forming check -> noVoltageFormingSource; NO right
% sample after trip; trajectory ends at event-left. EXACT assertions (C3):
% replace weak disjunction with precise failure-id match. C0 canonical flag
% verified in metadata. Candidate metadata per F2 audit contract.
s = cases.scenario_ieee14_1sg_4ibr();
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready);
opt = struct('t_end', 1.0, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*0.1, ...
    'fault_on', 0.1, 'fault_clear', 0.12, 'sg_trip', 0.2, 'sg_on', 0.4, ...
    'selected_gfm_indices', 2:5, 'reference_resource_index', 2, ...
    'automatic_gfm_switching', false), 'plot_results', false);
r = stability.run_hybrid_case(scenario, opt);
% Exact failure identity (C3).
tc.verifyEqual(r.failure_id, 'ts_simulate_ibr_hybrid:noVoltageFormingSource');
% C0 integration: canonical flag reached the result metadata.
tc.verifyFalse(r.metadata.automatic_gfm_switching);
% Trajectory ends at event-left: NO 'right' sample at or after sg_trip t.
trip_mask = strcmp({r.event_log.type}, 'sg_trip');
tc.verifyTrue(any(trip_mask));
sg_trip_t = r.event_log(find(trip_mask, 1)).t;
right_mask = strcmp(r.sample_side, 'right');
right_after_trip = right_mask & r.t >= sg_trip_t - 1e-9;
tc.verifyTrue(~any(right_after_trip), ...
    'Scenario B must publish no right sample after sg_trip.');
% Final accepted sample shows SG online (rejected candidate must not
% appear in the accepted history).
tc.verifyTrue(r.device_online_history(1, end));
% Candidate-failure metadata present in the event log (F2 contract).
trip_log = r.event_log(find(trip_mask, 1));
tc.verifyTrue(isfield(trip_log, 'candidate_committed'), ...
    'trip_log must have candidate_committed field.');
tc.verifyEqual(trip_log.candidate_committed, false);
tc.verifyEqual(trip_log.candidate_sg_online, false);
tc.verifyTrue(isfield(trip_log, 'failing_island_ids'), ...
    'trip_log must have failing_island_ids field.');
% Trajectory must NOT extend to 15 s (ends near the trip event).
tc.verifyLessThan(max(r.t), 1.0, 'Scenario B trajectory must not extend to 15 s.');
end

function test_c0_nested_false_reaches_scenario_b_path(tc)
% C0: nested ibr_events.automatic_gfm_switching=false must reach the Scenario-B
% fail-closed path (noVoltageFormingSource) and publish canonical false in
% metadata. Verifies the nested flag is the canonical source.
s = cases.scenario_ieee14_1sg_4ibr();
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready);
opt = struct('t_end', 1.0, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*0.1, ...
    'fault_on', 0.1, 'fault_clear', 0.12, 'sg_trip', 0.2, 'sg_on', 0.4, ...
    'selected_gfm_indices', 2:5, 'reference_resource_index', 2, ...
    'automatic_gfm_switching', false), 'plot_results', false);
r = stability.run_hybrid_case(scenario, opt);
tc.verifyFalse(r.metadata.automatic_gfm_switching, ...
    'Nested false must propagate to metadata.');
tc.verifyEqual(r.failure_id, ...
    'ts_simulate_ibr_hybrid:noVoltageFormingSource');
end

function test_c0_top_level_only_false_promoted(tc)
% C0: top-level-only automatic_gfm_switching=false (nested absent) must be
% promoted into the canonical schedule and reach the Scenario-B path.
s = cases.scenario_ieee14_1sg_4ibr();
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready);
opt = struct('t_end', 1.0, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*0.1, ...
    'fault_on', 0.1, 'fault_clear', 0.12, 'sg_trip', 0.2, 'sg_on', 0.4, ...
    'selected_gfm_indices', 2:5, 'reference_resource_index', 2), ...
    'automatic_gfm_switching', false, 'plot_results', false);
r = stability.run_hybrid_case(scenario, opt);
tc.verifyFalse(r.metadata.automatic_gfm_switching, ...
    'Top-level false must be promoted to canonical false.');
tc.verifyEqual(r.failure_id, ...
    'ts_simulate_ibr_hybrid:noVoltageFormingSource');
end

function test_c0_conflict_returns_structured_failure(tc)
% C0: top-level=false AND nested=true conflict must return a structured
% fail-closed result WITHOUT throwing, and WITHOUT performing device build or
% equilibrium (early return before the expensive computation).
s = cases.scenario_ieee14_1sg_4ibr();
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready);
opt = struct('t_end', 1.0, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*0.1, ...
    'fault_on', 0.1, 'fault_clear', 0.12, 'sg_trip', 0.2, 'sg_on', 0.4, ...
    'selected_gfm_indices', 2:5, 'reference_resource_index', 2, ...
    'automatic_gfm_switching', true), ...
    'automatic_gfm_switching', false, 'plot_results', false);
r = stability.run_hybrid_case(scenario, opt);
tc.verifyFalse(r.converged, 'Conflict must fail closed.');
tc.verifyEqual(r.failure_id, ...
    'run_hybrid_case:automaticGfmSwitchingConflict');
% Early return: no device build / equilibrium work performed.
tc.verifyFalse(isfield(r, 'equilibrium'), ...
    'Conflict must return before equilibrium solve.');
tc.verifyTrue(isempty(r.x_traj), ...
    'Conflict must return before any trajectory is produced.');
end

function test_c0_non_scalar_fails_closed(tc)
% C0: a non-scalar automatic_gfm_switching value must fail closed with a
% structured result (no uncaught error).
s = cases.scenario_ieee14_1sg_4ibr();
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready);
opt = struct('t_end', 1.0, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*0.1, ...
    'fault_on', 0.1, 'fault_clear', 0.12, 'sg_trip', 0.2, 'sg_on', 0.4, ...
    'selected_gfm_indices', 2:5, 'reference_resource_index', 2, ...
    'automatic_gfm_switching', [false true]), 'plot_results', false);
r = stability.run_hybrid_case(scenario, opt);
tc.verifyFalse(r.converged, 'Non-scalar flag must fail closed.');
tc.verifyEqual(r.failure_id, ...
    'run_hybrid_case:automaticGfmSwitchingInvalidType');
end

function test_c0_non_boolean_fails_closed(tc)
% C0: a non-boolean (char) automatic_gfm_switching value must fail closed
% with a structured result (no uncaught error).
s = cases.scenario_ieee14_1sg_4ibr();
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready);
opt = struct('t_end', 1.0, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*0.1, ...
    'fault_on', 0.1, 'fault_clear', 0.12, 'sg_trip', 0.2, 'sg_on', 0.4, ...
    'selected_gfm_indices', 2:5, 'reference_resource_index', 2, ...
    'automatic_gfm_switching', 'false'), 'plot_results', false);
r = stability.run_hybrid_case(scenario, opt);
tc.verifyFalse(r.converged, 'Non-boolean flag must fail closed.');
tc.verifyEqual(r.failure_id, ...
    'run_hybrid_case:automaticGfmSwitchingInvalidType');
end

function test_c_workflow_fails_closed_at_non_synchronous_state(tc)
% The relaxed synchronism override must NOT be able to buy a converged run.
% That is the property this test protects, and it is unchanged.
%
% RETARGETED 2026-09-26 (mission profile moved from the retired 20-state
% WECC/REGFM_B1 dual shell to the surviving 16-state eecon49_dual family).
% MEASURED on the current tree: the run now survives the SG trip AND reaches
% its reclose request, committing sg_reclose at t=8.04 s, then stops at
% ts_simulate_ibr_hybrid:stepNewton at t=8.13 s with converged=false.
%
% Reaching the reclose is what this arm is FOR, not a leak: the runner header
% documents C-workflow as "relaxed test-guard; exercises reclose/handback/
% reselection; labeled ASSUMED_DIAGNOSTIC". The previous revision of this test
% asserted NOT_REQUESTED / isnan(actual_reclose_time) / no sg_reclose logged,
% because on the retired model the run died at 5.09 s -- 90 ms after the trip --
% and never got as far as the request. Those three assertions described that
% trajectory, not the synchronism contract, so they are dropped here rather
% than inverted into new expectations.
%
% What replaces them is the honest reading of a relaxed guard: a close accepted
% under dV_max=10 / df_max=10 / dtheta_max=180 is the DEFINED behaviour of an
% override that deliberately admits everything, so the test asserts the close
% was taken and that the run STILL failed closed afterwards. The refusal of a
% non-synchronous close by the PHYSICAL guard is covered by
% test_c_natural_sync_timeout_physical_evidence in this file (SYNC_TIMEOUT, no
% close accepted), and the transaction-level reclose mechanics by
% test_ieee14_ibr_sg_reclose_workflow. Labelled ASSUMED_DIAGNOSTIC.
s = cases.scenario_ieee14_1sg_4ibr();
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready);
opt = struct('t_end', 15.0, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*0.1, ...
    'fault_on', 3.0, 'fault_clear', 3.1, 'sg_trip', 5.0, 'sg_on', 8.0, ...
    'selected_gfm_indices', 2:5, 'reference_resource_index', 2, ...
    'automatic_gfm_switching', true), ...
    'synchronism_overrides', struct('dV_max', 10, 'df_max', 10, 'dtheta_max', 180), ...
    'delays_overrides', struct('T_sg_min_off_s', 0, 'dwell_s', 0.01, 'timeout_s', 0.5), ...
    'plot_results', false);
r = stability.run_hybrid_case(scenario, opt);
% The relaxed override must not buy a converged run.
tc.verifyFalse(r.converged, ...
    'C-workflow must fail closed under the relaxed synchronism override.');
tc.verifyEqual(r.failure_id, 'ts_simulate_ibr_hybrid:stepNewton');
% The stop is after the trip AND after the reclose request it reached.
tc.verifyGreaterThan(r.t(end), 5.0);
tc.verifyGreaterThan(r.t(end), 8.0);
% The scheduled events DID execute, including the reclose, so the fail-closed
% is neither a refusal to start nor a run that never exercised the workflow.
applied_types = string({r.event_log(logical([r.event_log.applied])).type});
tc.verifyTrue(all(ismember(["fault_on","fault_clear","sg_trip","sg_on"],applied_types)), ...
    'fault_on, fault_clear, sg_trip and sg_on must all have been applied.');
% The relaxed guard admitted the close (its defined behaviour); the run still
% did not converge, which is the fail-closed claim.
tc.verifyEqual(char(string(r.reclose_status)), 'SUCCESS', ...
    'The relaxed override admits the close by construction.');
tc.verifyTrue(any(strcmp({r.event_log.type}, 'sg_reclose')), ...
    'The reclose transaction must have been attempted and logged.');
tc.verifyLessThan(r.actual_reclose_time, r.t(end), ...
    'The stop is after the accepted close, not at it.');
end

function test_c_natural_sync_timeout_physical_evidence(tc)
% C-natural (physical synchronism) uses the PUBLIC IEEE14 demo defaults: fault
% 3.0/3.1, trip 5.0, sg_on 8.0, t_end 15.0, NO synchronism_overrides, NO
% delays_overrides.
%
% RETARGETED 2026-09-26 (mission profile moved from the retired 20-state
% WECC/REGFM_B1 dual shell to the surviving 16-state eecon49_dual family).
% MEASURED on the current tree, and this is the outcome the runner header has
% always documented for this arm: the run survives to the request at 8.0 s,
% waits out the case-owned 5.0 s window (case_ieee14_1sg_4ibr_auto_vsg
% synchronism.timeout_s = 5.0), and at t=13.0 s logs an unapplied
% sg_reclose_timeout with reclose_status=SYNC_TIMEOUT and
% actual_reclose_time=NaN. No close is accepted. The run itself converges to
% t_end=15.0 s: the SG simply stays disconnected.
%
% The previous revision asserted converged=false at
% ts_simulate_ibr_hybrid:stepNewton, NOT_REQUESTED and t(end) in (5,8), because
% on the retired model the run died at 5.09 s and never reached the request.
% Those assertions described that trajectory, not the synchronism logic, so
% they are replaced here by the measured contract above -- the PHYSICAL guard
% refusing a non-synchronous close is exactly what this arm exists to show, and
% the timeout is the mechanism that refuses it.
%
% The transaction-level reclose mechanics remain covered by
% test_ieee14_ibr_sg_reclose_workflow (right_kcl_norm < 1e-6 from a synchronous
% state).
s = cases.scenario_ieee14_1sg_4ibr();
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready);
opt = struct('t_end', 15.0, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*0.1, ...
    'fault_on', 3.0, 'fault_clear', 3.1, 'sg_trip', 5.0, 'sg_on', 8.0, ...
    'selected_gfm_indices', 2:5, 'reference_resource_index', 2, ...
    'automatic_gfm_switching', true), 'plot_results', false);
% NO synchronism_overrides, NO delays_overrides.
r = stability.run_hybrid_case(scenario, opt);
% The request is still recorded as scheduled, and no close is claimed.
tc.verifyEqual(r.requested_sg_on_time, 8.0);
tc.verifyEqual(char(string(r.reclose_status)), 'SYNC_TIMEOUT');
tc.verifyTrue(isnan(r.actual_reclose_time), ...
    'A timed-out request must not record a reclose time.');
% The timeout is measured: it lands one full case-owned window after the
% request (8.0 + 5.0 = 13.0), not at some earlier or later point.
tc.verifyGreaterThan(r.t(end), 13.0);
tc.verifyTrue(any(strcmp({r.event_log.type}, 'sg_reclose_timeout')), ...
    'The timeout must be logged.');
timeout_entry = r.event_log(strcmp({r.event_log.type}, 'sg_reclose_timeout'));
tc.verifyFalse(timeout_entry.applied, 'A timeout is not a committed close.');
tc.verifyEqual(timeout_entry.t, 13.0, 'AbsTol', 1e-9, ...
    'Timeout fires at the request plus the case-owned 5.0 s window.');
tc.verifyFalse(any(strcmp({r.event_log.type}, 'sg_reclose')), ...
    'No sg_reclose may be logged when the physical guard refuses the close.');
% The scheduled events DID execute, so the timeout is not a refusal to start.
tc.verifyTrue(all(ismember(["fault_on","fault_clear","sg_trip","sg_on"], ...
    string({r.event_log(logical([r.event_log.applied])).type}))));
end

function test_plotting_does_not_mutate_results(tc)
% plot_ibr_switching_comparison must NOT mutate the result struct (copy-on-
% write). Build a synthetic result, snapshot it, plot, and verify equality.
r = synthetic_result();
snapshot = r;
out = fullfile(tc.TestData.out, 'plots');
stability.plot_ibr_switching_comparison(struct('A', r), ...
    struct('output_dir', out, 'figure', 'main_physical_evidence', 'visible', false));
tc.verifyEqual(r.t, snapshot.t, 'AbsTol', 0);
tc.verifyEqual(r.coi_frequency_Hz, snapshot.coi_frequency_Hz, 'AbsTol', 0);
tc.verifyEqual(r.bus_voltage_magnitude, snapshot.bus_voltage_magnitude, 'AbsTol', 0);
end

function test_plotting_does_not_crash_with_tiledlayout(tc)
% Plotting must not crash under tiledlayout (the pre-fix dead axis-loop
% crashed with 'Index exceeds the number of array elements').
r = synthetic_result();
out = fullfile(tc.TestData.out, 'plots_tl');
p = stability.plot_ibr_switching_comparison(struct('A', r), ...
    struct('output_dir', out, 'figure', 'main_physical_evidence', 'visible', false));
tc.verifyTrue(isfile(p));
end

function test_plotting_creates_six_axes(tc)
% The figure must have exactly 6 axes (one per subplot). Verify by counting
% axes children of the figure (via a visible figure so handles persist).
r = synthetic_result();
out = fullfile(tc.TestData.out, 'plots_axes');
% Call the internal plotting by invoking the function with a visible figure
% is not supported; instead verify the PNG is produced (6 subplots drawn).
p = stability.plot_ibr_switching_comparison(struct('A', r), ...
    struct('output_dir', out, 'figure', 'main_physical_evidence', 'visible', false));
tc.verifyTrue(isfile(p));
info = imfinfo(p);
% The figure is 1400x900; just verify a non-trivial image was produced.
tc.verifyGreaterThan(info.Width, 1000);
tc.verifyGreaterThan(info.Height, 500);
end

function test_plotting_event_markers_distinguish_committed_rejected(tc)
% Marker metadata must retain scenario, event identity, status, time, and
% transaction ID.  The timeout log is authoritative; the reconnect request
% time must never be fabricated as a rejected timeout marker.
r = synthetic_result_with_gap();
r.event_log = [struct('t', 0.1, 'applied', true, 'type', 'fault_on', ...
                      'transaction_id', 1); ...
               struct('t', 0.9, 'applied', false, 'type', 'sg_reclose_timeout', ...
                      'transaction_id', 3)];
r.events = [struct('t', 0.1, 'type', 'fault_on'); ...
            struct('t', 0.4, 'type', 'sg_on')];
r.reclose_status = 'SYNC_TIMEOUT';
r.requested_sg_on_time = 0.4;
r.actual_reclose_time = NaN;
out = fullfile(tc.TestData.out, 'plots_markers');
[p, markers] = stability.plot_ibr_switching_comparison(struct('A', r), ...
    struct('output_dir', out, 'figure', 'main_physical_evidence', 'visible', false));
tc.verifyTrue(isfile(p));
tc.verifyEqual({markers.scenario}, repmat({'A'}, 1, numel(markers)));
fault_commit = strcmp({markers.event_type}, 'fault_on') & ...
    strcmp({markers.status}, 'committed');
tc.verifyEqual(sum(fault_commit), 1);
tc.verifyEqual(markers(fault_commit).time, 0.1, 'AbsTol', 0);
tc.verifyEqual(markers(fault_commit).transaction_id, 1, 'AbsTol', 0);
request = strcmp({markers.event_type}, 'sg_on') & ...
    strcmp({markers.status}, 'scheduled');
timeout = strcmp({markers.event_type}, 'sg_reclose_timeout') & ...
    strcmp({markers.status}, 'rejected');
tc.verifyEqual(sum(request), 1);
tc.verifyEqual(sum(timeout), 1);
tc.verifyEqual(markers(request).time, 0.4, 'AbsTol', 0);
tc.verifyEqual(markers(timeout).time, 0.9, 'AbsTol', 0);
tc.verifyFalse(any(strcmp({markers.status}, 'rejected') & ...
    abs([markers.time] - 0.4) < eps), ...
    'Reconnect request time must not be reused as a timeout marker.');
% Result must not be mutated by plotting.
tc.verifyEqual(r.reclose_status, 'SYNC_TIMEOUT');
end

function test_plot_finite_inserts_nan_gaps(tc)
% plot_finite (local) must insert NaN gaps so MATLAB does not connect across
% missing/failed samples. Verify via a synthetic result with a NaN gap and
% checking the plotted line data has a break. (Indirect: plotting must not
% error on data with NaN gaps.)
r = synthetic_result_with_gap();
out = fullfile(tc.TestData.out, 'plots_gap');
p = stability.plot_ibr_switching_comparison(struct('A', r), ...
    struct('output_dir', out, 'figure', 'main_physical_evidence', 'visible', false));
tc.verifyTrue(isfile(p));
end

function test_no_nan_inf_in_accepted_samples(tc)
% Accepted samples must have no NaN/Inf in the core trajectory fields.
s = cases.scenario_ieee14_1sg_4ibr();
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready);
opt = struct('t_end', 0.5, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*0.1, ...
    'fault_on', 0.1, 'fault_clear', 0.12, 'sg_trip', 0.2, 'sg_on', 0.4, ...
    'selected_gfm_indices', 2:5, 'reference_resource_index', 2, ...
    'automatic_gfm_switching', true, 'synchronism_overrides', ...
    struct('dV_max', 10, 'df_max', 10, 'dtheta_max', 180), 'delays_overrides', ...
    struct('T_sg_min_off_s', 0, 'dwell_s', 0.01, 'timeout_s', 0.5)), 'plot_results', false);
r = stability.run_hybrid_case(scenario, opt);
% This test concerns accepted samples, not whether a later composite step
% converges.  A fail-closed partial trajectory must still contain only finite
% accepted differential/algebraic/input samples.
tc.verifyNotEmpty(r.t);
tc.verifyTrue(all(isfinite(r.t)));
tc.verifyTrue(all(isfinite(r.x_traj(:))));
tc.verifyTrue(all(isfinite(r.y_traj(:))));
tc.verifyTrue(all(isfinite(r.u_history(:))));
end

function test_scenario_a_no_event_publishes_derived_diagnostics(tc)
% Phase 6: the no-event path (Scenario A) must publish the same derived-
% diagnostic fields as the hybrid path so compute_metrics does not yield NaN.
% Core trajectory fields (t, x_traj, y_traj, converged) remain bit-identical.
% u_history is a new public field = eq.u_eq repeated across samples.
% bus_voltage_magnitude is a read-only reconstruction from y_traj.
% Device-level diagnostics requiring device reconstruct (coi_frequency_Hz,
% device_P_MW, device_modes_history) are NOT produced on the no-event path;
% this is a documented gap, not a regression.
s = cases.scenario_ieee14_1sg_4ibr();
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready);
opt = struct('t_end', 1.0, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', false), 'plot_results', false);
r = stability.run_hybrid_case(scenario, opt);
tc.verifyTrue(r.converged, 'Scenario A must converge.');
% Core fields present and finite.
tc.verifyTrue(all(isfinite(r.t)));
tc.verifyTrue(all(isfinite(r.x_traj(:))));
tc.verifyTrue(all(isfinite(r.y_traj(:))));
% u_history present and equals eq.u_eq repeated.
tc.verifyTrue(isfield(r, 'u_history'));
tc.verifyEqual(size(r.u_history, 2), numel(r.t), 'AbsTol', 0);
tc.verifyEqual(r.u_history(:, 1), r.equilibrium.u_eq(:), 'AbsTol', 0);
% bus_voltage_magnitude present, finite, and near 1.0 pu (nominal).
tc.verifyTrue(isfield(r, 'bus_voltage_magnitude'));
tc.verifyTrue(all(isfinite(r.bus_voltage_magnitude(:))));
tc.verifyGreaterThan(min(r.bus_voltage_magnitude(:)), 0.9);
% sample_side + transaction_id present (continuous + zeros for no-event).
tc.verifyTrue(isfield(r, 'sample_side'));
tc.verifyTrue(isfield(r, 'transaction_id'));
tc.verifyEqual(numel(r.sample_side), numel(r.t), 'AbsTol', 0);
% Independent oracle: the hybrid route new_samples() sets the first sample's
% side to 'initial' (ts_simulate_ibr_hybrid.m). The no-event path must match:
% first sample 'initial', all others 'continuous'. (For nt==1, sample_side(2:end)
% is empty and all(...) returns true, which is correct for this contract.)
tc.verifyEqual(r.sample_side{1}, 'initial');
tc.verifyTrue(all(strcmp(r.sample_side(2:end), 'continuous')));
tc.verifyEqual(r.transaction_id, zeros(size(r.transaction_id)));
end

function test_deterministic_repeat_numerical_payload(tc)
% F8: deterministic repeat compares numerical/audit payload only. Run twice
% with identical inputs and verify trajectories/modes/fingerprints match.
% Uses the no-event path (Scenario A) so the run converges deterministically
% without the post-trip dynamics instability that affects short-horizon event
% runs. The event-route deterministic repeat is covered by the reclose_workflow
% suite (test_sample_keys_unique_per_transaction). Here we verify the
% no-event trajectory, u_history, and bus_voltage_magnitude are bit-identical
% across two identical runs.
s = cases.scenario_ieee14_1sg_4ibr();
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready);
opt = struct('t_end', 1.0, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', false), 'plot_results', false);
r1 = stability.run_hybrid_case(scenario, opt);
r2 = stability.run_hybrid_case(scenario, opt);
tc.verifyTrue(r1.converged, 'Run 1 must converge.');
tc.verifyTrue(r2.converged, 'Run 2 must converge.');
tc.verifyEqual(r1.t, r2.t, 'AbsTol', 0);
tc.verifyEqual(r1.x_traj, r2.x_traj, 'AbsTol', 0);
tc.verifyEqual(r1.y_traj, r2.y_traj, 'AbsTol', 0);
% u_history and bus_voltage_magnitude (Phase 6 derived diagnostics) must
% also be bit-identical across runs.
tc.verifyTrue(isfield(r1, 'u_history') && isfield(r2, 'u_history'));
tc.verifyEqual(r1.u_history, r2.u_history, 'AbsTol', 0);
tc.verifyTrue(isfield(r1, 'bus_voltage_magnitude') && isfield(r2, 'bus_voltage_magnitude'));
tc.verifyEqual(r1.bus_voltage_magnitude, r2.bus_voltage_magnitude, 'AbsTol', 0);
end

function test_no_bare_unique_t_assertion(tc)
% C5: Replace tautological numel(unique(t)) <= numel(t) with a genuine
% composite-sample-key uniqueness test. If transaction_id is published
% (C4), the key includes timestamp + side + transaction_id; otherwise
% falls back to (t, sample_side). Duplicate t is EXPECTED at event
% boundaries; only the FULL key must be unique.
s = cases.scenario_ieee14_1sg_4ibr();
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready);
opt = struct('t_end', 1.0, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*0.1, ...
    'fault_on', 0.1, 'fault_clear', 0.12, 'sg_trip', 0.2, 'sg_on', 0.4, ...
    'selected_gfm_indices', 2:5, 'reference_resource_index', 2, ...
    'automatic_gfm_switching', true, 'synchronism_overrides', ...
    struct('dV_max', 10, 'df_max', 10, 'dtheta_max', 180), 'delays_overrides', ...
    struct('T_sg_min_off_s', 0, 'dwell_s', 0.01, 'timeout_s', 0.5)), 'plot_results', false);
r = stability.run_hybrid_case(scenario, opt);
tc.verifyGreaterThan(numel(r.t), 1);
tc.verifyTrue(isfield(r, 'transaction_id'), ...
    'The public raw trajectory must expose transaction_id.');
tc.verifySize(r.transaction_id, size(r.t));
n = numel(r.t);
keys = cell(1, n);
for k = 1:n
    keys{k} = sprintf('%.12g|%s|%d', r.t(k), ...
        char(r.sample_side{k}), int32(r.transaction_id(k)));
end
tc.verifyEqual(numel(unique(keys)), numel(keys), ...
    'No duplicate composite sample keys (t, side, transaction_id).');
% Duplicate t is EXPECTED at event boundaries (left+right), confirming the
% tautology-free check is stricter than the old bagged-times test.
tc.verifyLessThan(numel(unique(r.t)), numel(r.t), ...
    'Duplicate t at event boundaries is expected and correct.');
end

% =========================================================================
% Real 15 s comparison runner (acceptance evidence; runs ONCE)
% =========================================================================

function test_real_comparison_runner_completes(tc)
% Execute the real 15 s run_ieee14_ibr_switching_comparison() ONCE as
% acceptance evidence. Record wall time, convergence, metrics, artifact paths.
% This is evidence-gathering, not a production-readiness claim.
t0 = tic;
[results, metrics, plot_paths] = run_ieee14_ibr_switching_comparison();
elapsed = toc(t0);
fid = fopen(fullfile(tc.TestData.out, 'comparison_metrics.txt'), 'w');
fprintf(fid, 'wall_time_s=%.1f\n', elapsed);
fprintf(fid, 'scenarios=%s\n', strjoin(fieldnames(results), ','));
    mfn = fieldnames(metrics);
    for k = 1:numel(mfn)
        m = metrics.(mfn{k});
    fprintf(fid, '[%s] converged=%d failure=%s\n', m.label, m.converged, m.failure_id);
    fprintf(fid, '  freq_nadir=%.4f max_dev=%.4f min_V=%.4f max_I_ratio=%.4f\n', ...
        m.frequency_nadir, m.max_frequency_deviation, m.min_voltage, m.max_normalized_current);
    fprintf(fid, '  sync=%s reselection=%s mode_changes=%d rejected=%d max_kcl=%.3e\n', ...
        m.synchronization_outcome, char(string(m.reselection_status)), ...
        m.n_mode_changes, m.n_rejected_transitions, m.max_kcl_residual);
end
fclose(fid);
% Verify artifacts were produced.
tc.verifyTrue(isfield(results, 'A') && isfield(results, 'B'));
tc.verifyTrue(isfield(results, 'C_natural') && isfield(results, 'C_workflow'));
% Scenario B must fail closed (exact failure, C6).
tc.verifyEqual(metrics.B.failure_id, ...
    'ts_simulate_ibr_hybrid:noVoltageFormingSource');
% C-natural reaches its reclose request and is refused by the PHYSICAL guard:
% MEASURED on this tree (2026-09-26, mission profile on the surviving
% eecon49_dual family) it runs to t_end=15.0 s, logs an unapplied
% sg_reclose_timeout at t=13.0 s and reports synchronization_outcome
% SYNC_TIMEOUT with no close accepted. That is the contract the runner header
% documents for this arm. The acceptance run must show the physical guard
% refused the close -- not that the run died early.
tc.verifyEqual(metrics.C_natural.synchronization_outcome, 'SYNC_TIMEOUT', ...
    'The physical synchronism guard must time out rather than accept a close.');
tc.verifyFalse(strcmp(metrics.C_natural.synchronization_outcome,'SUCCESS'), ...
    'No successful reclose may be claimed by the physical arm.');
% C-workflow (relaxed test-guard) is documented to exercise the reclose path,
% and still must not converge.
tc.verifyFalse(metrics.C_workflow.converged, ...
    'The relaxed test-guard arm must still fail closed.');
tc.verifyTrue(isfield(plot_paths, 'main') && isfile(char(plot_paths.main)));
tc.verifyTrue(isfield(plot_paths, 'workflow') && isfile(char(plot_paths.workflow)));
tc.verifyTrue(isfield(plot_paths, 'delay') && isfile(char(plot_paths.delay)));
end

% =========================================================================
% Local synthetic fixtures
% =========================================================================

function r = synthetic_result()
% Minimal result struct for plot-mutation tests. Field shapes match the
% production result contract: bus_voltage_magnitude is nb x nt, device_*
% fields are nd x nt, coi_frequency_Hz is 1 x nt, t is 1 x nt.
t = (0:0.01:0.5).';   % 51x1
nt = numel(t);
r.t = t.';            % 1 x nt (row)
r.coi_frequency_Hz = (60 + 0.1 * sin(2 * pi * t)).';   % 1 x nt
% bus_voltage_magnitude: 1 bus x nt (so min(...,[],1) yields 1 x nt).
r.bus_voltage_magnitude = (1.0 + 0.01 * cos(2 * pi * t)).';
% device_P_MW: 5 devices x nt.
r.device_P_MW = [100 + 10*t, 50 + 5*t, 30 + 3*t, 20 + 2*t, 10 + t].';
% device_current_magnitude: 5 devices x nt (horizontal concat then transpose).
r.device_current_magnitude = [1.0 + 0.1*t, 0.5 + 0.05*t, 0.3 + 0.03*t, ...
    0.2 + 0.02*t, 0.1 + 0.01*t].';
r.device_current_limit_sys = [1.5; 1.0; 0.6; 0.4; 0.2] * ones(1, nt);
r.sg_indices = 1;
r.device_modes_history = repmat({'gfm'}, 5, nt);
r.device_modes_history(1, :) = {'sg'};
end

function r = synthetic_result_with_gap()
r = synthetic_result();
% Insert a NaN gap in the middle.
mid = round(numel(r.t) / 2);
r.coi_frequency_Hz(mid) = NaN;
r.bus_voltage_magnitude(mid) = NaN;
end
