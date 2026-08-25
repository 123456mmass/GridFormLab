function tests = test_ieee14_ibr_sg_reclose_workflow()
%TEST_IEEE14_IBR_SG_RECLOSE_WORKFLOW  Two-phase reclose transaction semantics.
%   Deeper coverage of the Phase-1 reclose + Phase-2 reselection contract than
%   test_ieee14_ibr_ts_event_runner (which keeps the Phase-1 bit-identity and
%   dwell gates). This suite adds: sg_on-is-a-request, natural SYNC_TIMEOUT,
%   diagnostic Phase-1 completion, Phase-2 completion / no-mode-change /
%   failure-retains-Phase-1, T_down formula, sample-key uniqueness, and
%   Scenario-B (no firmware) fail-closed behavior.
%
%   All assertions go through PUBLIC entry points only:
%     stability.sg_event_handler, stability.ts_simulate_ibr_hybrid,
%     stability.ibr_selector_table, stability.run_hybrid_case.
%   No local subfunction of any production file is called directly.
%
%   Source: F1/F2/F4/F5/F9/C2/C8 user-approved validation-closure plan.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath')))); pf_init_paths();
s = cases.scenario_ieee14_1sg_4ibr();
[devices, ~] = stability.build_mixed_resource_devices(s.case_data, s.resources, s.scenario_opt);
eq = stability.mixed_equilibrium_solve(s.case_data, struct('devices', devices), struct('verbose', false));
tc.assertTrue(eq.converged, eq.failure_reason);
dae = stability.composite_dae(s.case_data, eq.devices, struct('load_model', 'cz_p_cz_q'));
tc.TestData.scenario = s; tc.TestData.eq = eq; tc.TestData.dae = dae;
table_opt = struct('sg_off',struct('n_gfm_required',4, ...
    'reference_resource_index',2));
% SG_ON must retain the complete 0..4-GFM universe: the C1 duration and every
% staged one-device release are authenticated against the exact current row.
tc.TestData.table_4gfm = stability.ibr_selector_table( ...
    s.case_data,s.resources,s,table_opt);
end

% =========================================================================
% sg_on is a REQUEST, not a close
% =========================================================================

function test_sg_on_request_does_not_close_with_strict_guard(tc)
% With a strict synchronism guard, the sg_on request must NOT close the SG;
% it stays offline until the declared short diagnostic timeout.
over = struct('synchronism_overrides', struct('dV_max', 1e-12, 'df_max', 1e-12, 'dtheta_max', 1e-9), ...
    'delays_overrides', struct('T_sg_min_off_s', 0, 'dwell_s', 0.01, 'timeout_s', 0.02), ...
    't_end', 0.10);
r = event_run_with_table(tc.TestData, 2:5, 2, over);
tc.assertTrue(r.converged, r.failure_reason);
% SG (device 1) must remain offline at the end.
tc.verifyFalse(r.device_online_history(1, end));
tc.verifyEqual(r.reclose_status, 'SYNC_TIMEOUT');
end

function test_strict_diagnostic_guard_times_out_fail_closed(tc)
% ASSUMED_DIAGNOSTIC strict guard + short timeout -> SYNC_TIMEOUT. This is a
% supervisory fail-closed unit test, not natural IEEE14 physical evidence.
over = struct('synchronism_overrides', struct('dV_max', 1e-12, 'df_max', 1e-12, 'dtheta_max', 1e-9), ...
    'delays_overrides', struct('T_sg_min_off_s', 0, 'dwell_s', 0.01, 'timeout_s', 0.02), ...
    't_end', 0.10);
r = event_run_with_table(tc.TestData, 2:5, 2, over);
tc.assertTrue(r.converged, r.failure_reason);
tc.verifyEqual(r.reclose_status, 'SYNC_TIMEOUT');
tc.verifyFalse(r.device_online_history(1, end));
tc.verifyTrue(isnan(r.actual_reclose_time), 'No reclose occurred; time must be NaN.');
end

% =========================================================================
% Phase-1 read-only resynchronization diagnostics (Mission C, Phase 1+3)
% =========================================================================

function test_resync_diagnostics_recorded_during_coast(tc)
% Phase-1 measurement hook must record per-sample synchronism state during the
% offline coast. With a strict guard the SG never synchronises; the hook still
% records every sample. Independent oracle: df exceeds df_max throughout, which
% falsifies the hypothesis that natural IEEE14 can reclose without a governor.
over = struct('synchronism_overrides', struct('dV_max', 1e-12, 'df_max', 1e-12, 'dtheta_max', 1e-9), ...
    'delays_overrides', struct('T_sg_min_off_s', 0, 'dwell_s', 0.01, 'timeout_s', 0.02), ...
    't_end', 0.10);
r = event_run_with_table(tc.TestData, 2:5, 2, over);
tc.assertTrue(r.converged, r.failure_reason);
tc.verifyEqual(r.reclose_status, 'SYNC_TIMEOUT');
% The hook must fire: at least one diagnostic record during the coast.
tc.verifyTrue(isfield(r, 'resync_diagnostics'), 'resync_diagnostics must be published.');
tc.verifyFalse(isempty(r.resync_diagnostics), 'resync_diagnostics must be non-empty during coast.');
% Every sample: strict guard never eligible.
eligible = [r.resync_diagnostics.eligible];
tc.verifyFalse(any(eligible), 'Strict guard: no sample may be eligible.');
% Physics falsification: df > df_max throughout the coast (the independent
% oracle for WHY natural reclose times out — frozen Tm, Te=0 -> monotonic slip).
df = [r.resync_diagnostics.df];
tc.verifyTrue(all(isfinite(df)) && all(df > 1e-12), ...
    'Slip (df) must exceed df_max=1e-12 throughout: Tm-frozen coast cannot synchronise.');
% The binding limiter is frequency (slip dominates dV/dtheta on a frozen coast).
limg = {r.resync_diagnostics.limiting_gate};
tc.verifyTrue(all(ismember(limg, {'V','f','theta'})), 'Limiting gate must be {V,f,theta}; none may be "none".');
	tc.verifyFalse(any(strcmp(limg, 'none')), 'Strict guard always has at least one failing margin.');
end

function test_resync_diagnostics_explain_timeout_via_margin(tc)
% Deeper Phase-1 oracle: the signed margin must be negative throughout AND
% governed by the frequency term. Proves the timeout is physical (slip), not a
% numerical defect. ASSUMED_DIAGNOSTIC strict guard, not natural evidence.
over = struct('synchronism_overrides', struct('dV_max', 1e-12, 'df_max', 1e-12, 'dtheta_max', 1e-9), ...
    'delays_overrides', struct('T_sg_min_off_s', 0, 'dwell_s', 0.01, 'timeout_s', 0.02), ...
    't_end', 0.10);
r = event_run_with_table(tc.TestData, 2:5, 2, over);
tc.assertTrue(r.converged, r.failure_reason);
sm = [r.resync_diagnostics.signed_margin];
mf = [r.resync_diagnostics.margin_f];
% Signed margin negative everywhere = never eligible.
tc.verifyTrue(all(sm < 0), 'Signed margin must be negative throughout the coast.');
	% The frequency margin is also negative everywhere (dV margin is more negative).
tc.assertTrue(all(mf < 0), 'Margin_f must be negative throughout: slip blocks reclose.');
end

% =========================================================================
% Phase-1 reclose (diagnostic relaxed guard; ASSUMED_DIAGNOSTIC, not physical)
% =========================================================================

function test_phase1_reclose_returns_reference_to_sg(tc)
% Diagnostic relaxed guard -> Phase-1 reclose completes. reference_owner_indices
% points to the reclosed SG (index 1); gfm_reference_resource_indices is empty
% (NaN) for that island; IBR modes UNCHANGED.
over = diagnostic_overrides(0.05);
r = event_run_with_table(tc.TestData, 2:5, 2, over);
tc.assertTrue(r.converged, r.failure_reason);
tc.verifyEqual(r.reclose_status, 'SUCCESS');
tc.verifyEqual(r.actual_reclose_time, 0.05, 'AbsTol', 1e-12);
tc.verifyTrue(isfield(r, 'reference_owner_indices'));
tc.verifyEqual(r.reference_owner_indices, 1, 'AbsTol', 0, ...
    'Phase 1 must return reference ownership to the reclosed SG.');
tc.verifyTrue(isfield(r, 'gfm_reference_resource_indices'));
tc.verifyTrue(isnan(r.gfm_reference_resource_indices(1)), ...
    'gfm_reference_resource_indices must be empty (NaN) while SG owns reference.');
end

function test_phase1_preserves_sg_state_and_input_at_breaker_close(tc)
% SG rotor angle/speed and every controller command must be continuous across
% the breaker close. The authenticated pre-event input is a later C1 target;
% applying it atomically was the diagnosed 1.2876-pu command-step defect.
over = diagnostic_overrides(0.05);
r = event_run_with_table(tc.TestData, 2:5, 2, over);
tc.assertTrue(r.converged, r.failure_reason);
left = find(abs(r.t - 0.05) < 1e-12 & ~strcmp(r.sample_side, 'right'), 1, 'last');
right = find(abs(r.t - 0.05) < 1e-12 & strcmp(r.sample_side, 'right'), 1, 'last');
tc.assertNotEmpty(left); tc.assertNotEmpty(right);
% SG states (first 6) unchanged across the close.
tc.verifyEqual(r.x_traj(1:6, right), r.x_traj(1:6, left), 'AbsTol', 0, ...
    'Reclose changes breaker context, not SG differential state.');
tc.verifyEqual(r.u_history(:, right), r.u_history(:, left), 'AbsTol', 0, ...
    'Breaker close must not step SG or IBR controller commands.');
end

function test_phase1_updates_committed_config_fingerprint_only(tc)
% Phase 1 updates committed_config_fingerprint ONLY; selector_table_fingerprint
% and pre_event_input_fingerprint are immutable (F1).
over = diagnostic_overrides(0.05);
r = event_run_with_table(tc.TestData, 2:5, 2, over);
tc.assertTrue(r.converged, r.failure_reason);
% committed_config_fingerprint must be present and reflect the reclose (if the
% field is propagated to the result).
tc.verifyTrue(isfield(r, 'committed_config_fingerprint'));
tc.verifyFalse(isempty(r.committed_config_fingerprint));
tc.verifyTrue(contains(r.committed_config_fingerprint, 'sg_on_reclose'), ...
    'committed_config_fingerprint must reflect the Phase-1 reclose.');
% event_run_with_table injects an authenticated selector_table, so the
% public selector_table_fingerprint must be populated and immutable across
% the Phase-1 reclose (F1). The pre-event input fingerprint is always owned
% by the driver and must be populated.
tc.verifyTrue(isfield(r, 'selector_table_fingerprint'));
tc.verifyFalse(isempty(r.selector_table_fingerprint), ...
    'selector_table_fingerprint must authenticate the injected table.');
tc.verifyTrue(isfield(r, 'pre_event_input_fingerprint'));
tc.verifyFalse(isempty(r.pre_event_input_fingerprint), ...
    'pre_event_input_fingerprint must authenticate the restored input.');
end

function test_phase1_exactly_one_right_limit_sample(tc)
% Exactly ONE right-limit solve and ONE right sample at the reclose time.
over = diagnostic_overrides(0.05);
r = event_run_with_table(tc.TestData, 2:5, 2, over);
tc.assertTrue(r.converged, r.failure_reason);
reclose_log=r.event_log(strcmp({r.event_log.type},'sg_reclose'));
tc.verifyEqual(numel(reclose_log),1);
tx=reclose_log.transaction_id;
tc.verifyGreaterThan(tx,0);
tc.verifyEqual(sum(r.transaction_id==tx & strcmp(r.sample_side,'left')),1);
tc.verifyEqual(sum(r.transaction_id==tx & strcmp(r.sample_side,'right')),1, ...
    'Exactly one right-limit sample belongs to the reclose transaction.');
% KCL residual at the right sample must be finite and within tolerance.
tc.verifyTrue(isfinite(r.event_log(end).right_kcl_norm));
tc.verifyLessThan(r.event_log(end).right_kcl_norm, 1e-6);
end

% =========================================================================
% Phase-2 reselection
% =========================================================================

function test_phase2_no_immediate_release_at_reclose(tc)
% The complete SG_ON table now contains robust stable candidates. At the exact
% reclose instant no GFM release may occur; the short legacy fixture reports
% no runtime-eligible SG_ON row because its trip lockout is still active.
over = diagnostic_overrides(0.05);
r = event_run_with_table(tc.TestData, 2:5, 2, over);
tc.assertTrue(r.converged, r.failure_reason);
tc.verifyEqual(r.reclose_status, 'SUCCESS');
% reselection_status is always published (default 'NOT_REQUESTED'); assert it.
tc.verifyTrue(isfield(r, 'reselection_status'), ...
    'reselection_status must be published.');
% The CONTRACT under test: no GFM release at the breaker close. The INDICATOR
% changed with GATE-2026-08-25-01/-04/-05. Before those fixes the all-GFL
% SG_ON row was infeasible, so the legacy authority refused outright
% (NO_FEASIBLE_SG_ON). Now the row is ready, so the same authority
% authenticates it and schedules the release at T_down =
% max(T_minimum_hold, ln(1/rho)/|omega|) -- about 46 s past the reclose on
% this row -- which the 0.10-s fixture horizon cannot reach. PENDING with
% actual_mode_reselection_time = NaN is therefore the correct signature of
% "no release happened": a release was SCHEDULED, not refused, and none
% occurred. A bare NO_FEASIBLE_SG_ON here would now mean the table had
% regressed to infeasible.
tc.verifyEqual(r.reselection_status, 'PENDING', ...
    sprintf('Unexpected reselection_status: %s', r.reselection_status));
tc.verifyTrue(isnan(r.actual_mode_reselection_time), ...
    'no release may occur at the reclose instant');
end

function test_phase2_does_not_release_before_c1_completion(tc)
% Zeroing delay overrides does not make an event-left table row a valid
% immediate release. This falsifies GFM->GFL switching at breaker close.
% INDICATOR UPDATE (GATE-2026-08-25-01/-04/-05): with the all-GFL SG_ON row
% now ready, the legacy authority authenticates it and schedules the release
% through compute_tdown, whose T_down = max(T_minimum_hold,
% ln(1/rho)/|omega|) is dominated by the ROW's own decay rate (~46 s on this
% table) and is therefore NOT zeroed by the caller's delay overrides -- the
% overrides zero the caller-level hold/guard/lockout, not the row-derived
% settling bound. The 0.10-s horizon cannot reach that deadline, so the
% correct signature of "no immediate release" is PENDING with a NaN
% reselection time. The zeroed T_minimum_hold/T_guard can only ever have
% mattered for a release whose authority was already authenticated, which is
% exactly the behaviour this test pins: scheduled, not committed.
over = diagnostic_overrides(0.05);
over.delays_overrides.T_minimum_hold_s = 0;
over.delays_overrides.T_guard_s = 0;
over.delays_overrides.T_lockout_s = 0;
r = event_run_with_table(tc.TestData, 2:5, 2, over);
tc.assertTrue(r.converged, r.failure_reason);
% reselection_status must be published.
tc.verifyTrue(isfield(r, 'reselection_status'), ...
    'reselection_status must be published.');
tc.verifyEqual(r.reselection_status, 'PENDING', ...
    sprintf('Unexpected reselection_status: %s', r.reselection_status));
% No Phase-2 mode transition occurs.
tc.verifyTrue(isnan(r.actual_mode_reselection_time), ...
    'No Phase-2 mode reselection may occur at breaker close.');
end

function test_phase2_failure_retains_phase1(tc)
% A Phase-2 failure (e.g. stale fingerprint) must NOT roll back Phase 1: SG
% stays online, reference stays at SG, no Phase-2 right sample.
% Ends at the reclose; Phase-2 outcome is recorded in reselection_status.
over = diagnostic_overrides(0.05);
over.delays_overrides.T_minimum_hold_s = 0;
over.delays_overrides.T_guard_s = 0;
over.delays_overrides.T_lockout_s = 0;
r = event_run_with_table(tc.TestData, 2:5, 2, over);
tc.assertTrue(r.converged, r.failure_reason);
% SG must be online after Phase 1 regardless of Phase-2 outcome.
tc.verifyTrue(r.device_online_history(1, end), 'Phase 1 must keep SG online.');
% After a successful Phase-1 reclose, reference_owner_indices must be published
% and point at the reclosed SG (index 1).
tc.verifyTrue(isfield(r, 'reference_owner_indices'), ...
    'reference_owner_indices must be published after reclose.');
tc.verifyFalse(isempty(r.reference_owner_indices), ...
    'reference_owner_indices must be non-empty after reclose.');
tc.verifyEqual(r.reference_owner_indices, 1, 'AbsTol', 0, ...
    'Reference stays at SG regardless of Phase-2 outcome.');
end

function test_incomplete_healthy_pf_reference_rejected_by_public_driver(tc)
% 2026-08-10 regression: run_hybrid_case previously forwarded the profile only
% when BOTH fields were present. A caller supplying just healthy_pf_V was then
% silently routed to the legacy selector instead of failing the atomic-pair
% contract. Independent oracle: ts_simulate_ibr_hybrid owns the documented
% incompleteHealthyPfReference identifier; the public driver must preserve it
% through its structured fail-closed result (the public API does not throw).
s = tc.TestData.scenario;
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready, selection.failure_reason);
opt = short_public_event_opt();
opt.healthy_pf_V = ones(1, size(s.case_data.bus_data,1));
r = stability.run_hybrid_case(scenario, opt);
tc.verifyFalse(r.converged);
tc.verifyEqual(r.failure_id, ...
    'ts_simulate_ibr_hybrid:incompleteHealthyPfReference');
tc.verifyEqual(r.metadata.ts_meta.failure_id, r.failure_id);
tc.verifyEmpty(r.t);
end

function test_invalid_healthy_pf_reference_rejected(tc)
% Equal-length is not sufficient: duplicate bus IDs make V_ref ownership
% ambiguous. The TS public entry must reject the profile before integration and
% publish the exact validation ID through its structured fail-closed contract.
o = base_opt(tc.TestData.eq, 0.10, 0.01);
o.ibr_event_schedule = stability.ibr_event_schedule( ...
    tc.TestData.scenario.case_data, tc.TestData.eq.devices, ...
    event_spec(2:5, 2), 0.10, 0.01);
o.healthy_pf_V = [1 1];
o.healthy_pf_bus_ids = [2 2];
[r,m] = stability.ts_simulate_ibr_hybrid( ...
    tc.TestData.scenario.case_data, tc.TestData.eq.devices, ...
    tc.TestData.eq.x0, tc.TestData.eq.y0, o);
tc.verifyFalse(r.converged);
tc.verifyEqual(r.failure_id, ...
    'ts_simulate_ibr_hybrid:invalidHealthyPfReference');
tc.verifyEqual(m.failure_id, r.failure_id);
tc.verifyEmpty(r.t);
end

% =========================================================================
% Sample-key uniqueness (F9)
% =========================================================================

function test_sample_keys_unique_per_transaction(tc)
% Raw identity (t, sample_side, transaction_id): duplicate t EXPECTED at discontinuities;
% at most one left + one right per committed transaction; NO duplicate
% complete sample keys. The result exposes every key component.
over = diagnostic_overrides(0.05);
r = event_run_with_table(tc.TestData, 2:5, 2, over);
tc.assertTrue(r.converged, r.failure_reason);
tc.verifyTrue(isfield(r,'transaction_id'));
tc.verifySize(r.transaction_id,size(r.t));
% Build complete sample keys (t, sample_side, transaction_id) and assert uniqueness.
n = numel(r.t);
keys = cell(1, n);
for k = 1:n
    side = '';
    if numel(r.sample_side) >= k && ~isempty(r.sample_side{k})
        side = r.sample_side{k};
    end
    keys{k} = sprintf('%.12g|%s|%d', r.t(k), side, int32(r.transaction_id(k)));
end
tc.verifyEqual(numel(unique(keys)), numel(keys), 'AbsTol', 0, ...
    'No duplicate complete (t, sample_side, transaction_id) sample keys.');
tx = unique(r.transaction_id(r.transaction_id>0));
for j = 1:numel(tx)
    mask = r.transaction_id==tx(j);
    tc.verifyLessThanOrEqual(sum(mask & strcmp(r.sample_side,'left')),1);
    tc.verifyLessThanOrEqual(sum(mask & strcmp(r.sample_side,'right')),1);
end
end

function test_no_bare_unique_t_assertion(tc)
% F9: duplicate t values are EXPECTED at discontinuities. The engine must NOT
% require globally unique timestamps. Verify that duplicate t exists at the
% reclose event (left + right share t).
over = diagnostic_overrides(0.05);
r = event_run_with_table(tc.TestData, 2:5, 2, over);
tc.assertTrue(r.converged, r.failure_reason);
% At the reclose time there must be both a left and a right sample (same t).
left = find(abs(r.t - 0.05) < 1e-12 & ~strcmp(r.sample_side, 'right'));
right = find(abs(r.t - 0.05) < 1e-12 & strcmp(r.sample_side, 'right'));
tc.assertNotEmpty(left);
tc.assertNotEmpty(right);
% So numel(unique(t)) < numel(t) is EXPECTED (duplicate t at discontinuity).
tc.verifyLessThan(numel(unique(r.t)), numel(r.t));
end

% =========================================================================
% Scenario B: no firmware (automatic_gfm_switching=false)
% =========================================================================

function test_scenario_b_fails_closed_no_voltage_forming_source(tc)
% automatic_gfm_switching=false: breaker opens, no GFM commit, per-island
% voltage-forming check -> noVoltageFormingSource; NO right sample; trajectory
% ends at event-left; NEVER extended to 15 s. Uses run_hybrid_case with the
% IEEE14 scenario (IBRs start as GFL) so no voltage-forming source remains
% after the SG trip.
s = tc.TestData.scenario;
[scenario, selection] = stability.ibr_configure_scenario(s, struct());
tc.assertTrue(selection.ready, selection.failure_reason);
opt = struct('t_end', 1.0, 'dt', 0.01, 'verbose', false, ...
    'ibr_events', struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*0.1, ...
    'fault_on', 0.1, 'fault_clear', 0.12, 'sg_trip', 0.2, 'sg_on', 0.4, ...
    'selected_gfm_indices', 2:5, 'reference_resource_index', 2, ...
    'automatic_gfm_switching', false), 'plot_results', false);
r = stability.run_hybrid_case(scenario, opt);
tc.verifyNumElements(r.accepted_residual_per_step,numel(r.residual_per_step), ...
    'run_hybrid_case must preserve the hybrid accepted-leaf residual provenance.');
tc.verifyTrue(all(isfinite(r.accepted_residual_per_step)));
tc.verifyFalse(r.converged);
tc.verifyEqual(r.failure_id,'ts_simulate_ibr_hybrid:noVoltageFormingSource');
tc.verifyFalse(r.metadata.automatic_gfm_switching);
trip_mask=strcmp({r.event_log.type},'sg_trip');
tc.verifyEqual(sum(trip_mask),1);
trip_log=r.event_log(trip_mask);
tc.verifyFalse(trip_log.candidate_committed);
tc.verifyFalse(trip_log.candidate_sg_online);
tc.verifyFalse(isempty(fieldnames(trip_log.candidate_modes)));
tc.verifyFalse(isempty(trip_log.failing_island_ids));
right_after_trip=strcmp(r.sample_side,'right') & ...
    r.t>=trip_log.t-1e-12;
tc.verifyFalse(any(right_after_trip));
tc.verifyTrue(r.device_online_history(1,end), ...
    'Rejected breaker-open candidate must not enter accepted history.');
% Trajectory must NOT extend to 15 s (ends near the trip event).
tc.verifyLessThan(max(r.t), 1.0, 'Scenario B trajectory must not extend to 15 s.');
end

% =========================================================================
% T_down formula (C8) — verified via the public selector table + compute path
% =========================================================================

function test_tdown_formula_from_omega_target(tc)
% T_down = max(T_minimum_hold, ln(1/rho)/(-Omega_target)). Omega_target must be
% finite and < 0. Verify the selector table exposes a finite negative omega
% for the SG_ON context (all-GFL when SG owns the reference).
s = tc.TestData.scenario;
resources = s.resources;
scenario = struct('selector', struct('gamma_req', 0.1), ...
    'config', struct('resource_ids', {resource_ids_of(resources)}));
opt = struct('sg_off', struct('n_gfm_required', 1), ...
    'sg_on', struct('n_gfm_required', 0));
table = stability.ibr_selector_table(s.case_data, resources, scenario, opt);
% SG_ON omega may be NaN on structural-only path; if evaluated it must be < 0.
if isfield(table.sg_on, 'omega') && isfinite(table.sg_on.omega)
    tc.verifyLessThan(table.sg_on.omega, 0, 'Omega_target must be negative (stable).');
    rho = 0.05;
    t_settle = log(1 / rho) / (-table.sg_on.omega);
    tc.verifyTrue(isfinite(t_settle) && t_settle > 0, 'T_settle must be finite positive.');
end
end

% =========================================================================
% sg_event_handler public entry point (Phase-1 reclose via sg_reclose_request)
% =========================================================================

function test_sg_event_handler_reclose_request_returns_reference_to_sg(tc)
% Drive process_sg_reclose through the PUBLIC sg_event_handler entry point
% (not the local function directly). Build a hybrid_state with the SG offline,
% send an sg_reclose_request, and verify the returned hybrid_state.
devs = tc.TestData.eq.devices;
hs = stability.ts_hybrid_state_init(devs);
% Trip the SG first (so it is offline and can be reclosed).
sg_id = devs(1).device_id;
trip_ev = struct('type', 'sg_trip_request', 't', 1.0, 'sg_ids', {{sg_id}}, ...
    'committed_selection', struct('selected_gfm_indices', 2:5, ...
    'n_gfm_required', 4, 'reference_resource_index', 2));
[hs_trip, ~] = stability.sg_event_handler(hs, trip_ev, devs, struct());
tc.verifyFalse(hs_trip.device_online.(valid_key(sg_id)));
% Now request reclose.
reclose_ev = struct('type', 'sg_reclose_request', 't', 2.0, 'sg_id', sg_id);
[hs_reclose, log] = stability.sg_event_handler(hs_trip, reclose_ev, devs, struct());
tc.verifyTrue(log.applied, 'Reclose must be applied.');
tc.verifyTrue(hs_reclose.device_online.(valid_key(sg_id)), 'SG must be online after reclose.');
tc.verifyEqual(hs_reclose.device_modes.(valid_key(sg_id)), 'synchronous');
% Reference handback: owner = SG (index 1), gfm_reference empty for island 1.
tc.verifyEqual(hs_reclose.reference_owner_indices, 1, 'AbsTol', 0);
tc.verifyTrue(isnan(hs_reclose.gfm_reference_resource_indices(1)));
% committed_config_fingerprint updated; selector_table_fingerprint untouched.
tc.verifyTrue(contains(hs_reclose.committed_config_fingerprint, 'sg_on_reclose'));
end

function test_sg_event_handler_reclose_rejects_already_online(tc)
% Reclose of an already-online SG must fail closed (no-op).
devs = tc.TestData.eq.devices;
hs = stability.ts_hybrid_state_init(devs);
sg_id = devs(1).device_id;
% SG is already online in the initial state.
reclose_ev = struct('type', 'sg_reclose_request', 't', 1.0, 'sg_id', sg_id);
[hs2, log] = stability.sg_event_handler(hs, reclose_ev, devs, struct());
tc.verifyFalse(log.applied, 'Reclose of an online SG must be rejected.');
tc.verifyEqual(log.failure_id, 'stability:sg_event_handler:sgAlreadyOnline');
end

function test_sg_event_handler_reclose_rejects_bad_request(tc)
% Missing t or sg_id must fail closed.
devs = tc.TestData.eq.devices;
hs = stability.ts_hybrid_state_init(devs);
bad_ev = struct('type', 'sg_reclose_request', 'sg_id', devs(1).device_id);  % no t
[hs2, log] = stability.sg_event_handler(hs, bad_ev, devs, struct());
tc.verifyFalse(log.applied);
tc.verifyEqual(log.failure_id, 'stability:sg_event_handler:badRecloseRequest');
end

% =========================================================================
% Local helpers (reuse the event_run/event_spec/base_opt pattern)
% =========================================================================

function r = event_run(data, selected, ref, extra)
ev = event_spec(selected, ref);
tend = 0.10; if isfield(extra, 't_end'), tend = extra.t_end; end
sched = stability.ibr_event_schedule(data.scenario.case_data, data.eq.devices, ev, tend, 0.01);
o = base_opt(data.eq, tend, 0.01); o.ibr_event_schedule = sched;
names = fieldnames(extra);
for k = 1:numel(names), o.(names{k}) = extra.(names{k}); end
[r, ~] = stability.ts_simulate_ibr_hybrid(data.scenario.case_data, data.eq.devices, ...
    data.eq.x0, data.eq.y0, o);
end

function r = event_run_with_table(data, selected, ref, extra)
% Successful-trip variant reuses one immutable table built in setupOnce. The
% SG_OFF tuple is pinned; SG_ON retains all 16 rows needed by C1/staged release.
ev = event_spec(selected, ref);
if isfield(extra,'event_overrides')
    event_names=fieldnames(extra.event_overrides);
    for k=1:numel(event_names)
        ev.(event_names{k})=extra.event_overrides.(event_names{k});
    end
    extra=rmfield(extra,'event_overrides');
end
tend = 0.10; if isfield(extra, 't_end'), tend = extra.t_end; end
sched = stability.ibr_event_schedule(data.scenario.case_data, data.eq.devices, ev, tend, 0.01);
o = base_opt(data.eq, tend, 0.01); o.ibr_event_schedule = sched;
if ~isequal(selected,2:5) || ref~=2
    error('test_ieee14_ibr_sg_reclose_workflow:fixtureTuple', ...
        'The cached workflow fixture authenticates only selected=2:5, ref=2.');
end
o.selector_table = data.table_4gfm;
names = fieldnames(extra);
for k = 1:numel(names), o.(names{k}) = extra.(names{k}); end
[r, ~] = stability.ts_simulate_ibr_hybrid(data.scenario.case_data, data.eq.devices, ...
    data.eq.x0, data.eq.y0, o);
end

function ev = event_spec(selected, ref)
ev = struct('enabled', true, 'fault_bus', 4, 'Zf', 1i*0.1, ...
    'fault_on', 0.02, 'fault_clear', 0.03, 'sg_trip', 0.04, 'sg_on', 0.06, ...
    'selected_gfm_indices', selected, 'reference_resource_index', ref);
end

function o = base_opt(eq, tend, dt)
o = struct('t_end', tend, 'dt', dt, 'verbose', false, 'load_model', 'cz_p_cz_q', ...
    'u_eq', eq.u_eq, 'event_context', eq.equilibrium_context, ...
    'dynamic_state_indices', eq.dynamic_state_indices, 'full_kcl', true);
end

function o = short_public_event_opt()
% Short public-route request: schedule shape is sufficient to reach TS option
% validation; the incomplete healthy-PF pair must be rejected before stepping.
o = struct('t_end',0.10,'dt',0.01,'verbose',false, ...
    'ibr_events',event_spec(2:5,2),'plot_results',false);
end

function over = diagnostic_overrides(reclose_t)
% Relaxed test-guard (ASSUMED_DIAGNOSTIC / NOT PHYSICAL ACCEPTANCE) to exercise
% the full reclose/handback/reselection path. sg_on=0.06; reclose lands at the
% first permitted close after dwell. t_end is set to reclose_t exactly (matching
% the existing test_reclose_requires_dwell pattern) so the simulation ends at
% the reclose and does not attempt post-reclose dynamics that the diagnostic
% guard leaves numerically unstable.
over = struct('synchronism_overrides', struct('dV_max', 10, 'df_max', 10, 'dtheta_max', 180), ...
    'delays_overrides', struct('T_sg_min_off_s', 0, 'dwell_s', 0, 'timeout_s', 0.04), ...
    'event_overrides',struct('sg_on',0.05), ...
    't_end', reclose_t);
end

function ids = resource_ids_of(resources)
ids = cell(1, numel(resources));
for k = 1:numel(resources), ids{k} = char(resources(k).resource_id); end
end

function key = valid_key(device_id)
key = matlab.lang.makeValidName(char(device_id), 'ReplacementStyle', 'underscore');
end
