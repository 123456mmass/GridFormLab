function tests=test_ieee14_ibr_ts_event_runner()
%TEST_IEEE14_IBR_TS_EVENT_RUNNER Falsification gates for mixed SG+IBR events.
% The previous draft only checked timestamps/file existence and accepted
% failed synchronism paths. These tests use independent canonical-TS, KCL,
% device-mode, state-partition, and phasor synchronism oracles.
tests=functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath')))); pf_init_paths();
s=cases.scenario_ieee14_1sg_4ibr();
[devices,~]=stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
eq=stability.mixed_equilibrium_solve(s.case_data,struct('devices',devices),struct('verbose',false));
tc.assertTrue(eq.converged,eq.failure_reason);
dae=stability.composite_dae(s.case_data,eq.devices,struct('load_model','cz_p_cz_q'));
tc.TestData.scenario=s; tc.TestData.eq=eq; tc.TestData.dae=dae;
% Two pinned authenticated tables (manual_override) built ONCE for reuse.
% table_4gfm: SG_OFF n_gfm_required=4, ref=2 (candidate [2 3 4 5]).
% table_1gfm: SG_OFF n_gfm_required=1, ref=2 (single-GFM right-limit oracle).
% SG_ON remains unpinned (all 16 rows) because C1 handback authenticates the
% exact current set and staged release authenticates each one-device target.
tc.TestData.table_4gfm=build_pinned_table(s,4,2);
tc.TestData.table_1gfm=build_pinned_table(s,1,2);
end

function table = build_pinned_table(s, n_gfm, ref)
% Build a pinned authenticated selector_table mirroring run_hybrid_case's
% mode-dependent pinning: SG_OFF pinned to the manual tuple, SG_ON n=0.
table_opt=struct();
table_opt.sg_off=struct('n_gfm_required',n_gfm,'reference_resource_index',ref);
table=stability.ibr_selector_table(s.case_data,s.resources,s,table_opt);
end

function test_event_disabled_is_canonical_bit_identical(tc)
[a,b]=no_event_pair(tc.TestData,0.02,0.01);
tc.verifyEqual(b.t,a.t,'AbsTol',0);
tc.verifyEqual(b.x_traj,a.x_traj,'AbsTol',0);
tc.verifyEqual(b.y_traj,a.y_traj,'AbsTol',0);
end

function test_prefix_before_fault_is_canonical_bit_identical(tc)
r=event_run_with_table(tc.TestData,2:5,2,struct(),tc.TestData.table_4gfm);
tc.assertTrue(r.converged,r.failure_reason);
o=base_opt(tc.TestData.eq,0.02,0.01);
[base,~]=stability.ts_simulate_composite(tc.TestData.scenario.case_data, ...
    tc.TestData.eq.devices,tc.TestData.eq.x0,tc.TestData.eq.y0,o);
left=find(abs(r.t-0.02)<1e-12 & strcmp(r.sample_side,'left'),1);
tc.assertNotEmpty(left);
tc.verifyEqual(r.x_traj(:,1:left),base.x_traj,'AbsTol',0);
tc.verifyEqual(r.y_traj(:,1:left),base.y_traj,'AbsTol',0);
end

function test_events_have_exact_left_right_and_finite_kcl(tc)
r=event_run_with_table(tc.TestData,2:5,2,struct(),tc.TestData.table_4gfm);
tc.assertTrue(r.converged,r.failure_reason);
tc.verifyNumElements(r.accepted_residual_per_step,numel(r.residual_per_step));
tc.verifyTrue(all(isfinite(r.accepted_residual_per_step)));
tc.verifyLessThanOrEqual(r.accepted_residual_per_step, ...
    r.residual_per_step+10*eps(max(1,r.residual_per_step)), ...
    'An accepted-leaf residual cannot exceed the attempt-inclusive residual.');
for te=[0.02 0.03 0.04 0.06]
    tc.verifyEqual(sum(abs(r.t-te)<1e-12),2, ...
        sprintf('Event %.3f must publish one left and one right sample.',te));
end
tc.verifyTrue(all([r.event_log.applied]));
tc.verifyTrue(all(isfinite([r.event_log.right_kcl_norm])));
tc.verifyLessThan(max([r.event_log.right_kcl_norm]),1e-6);
right_fault=find(abs(r.t-0.02)<1e-12 & strcmp(r.sample_side,'right'),1);
right_clear=find(abs(r.t-0.03)<1e-12 & strcmp(r.sample_side,'right'),1);
tc.verifyEqual(r.topology_history{right_fault},'fault');
tc.verifyEqual(r.topology_history{right_clear},'post');
end

function test_trip_commits_modes_partition_and_zero_sg_current(tc)
r=event_run_with_table(tc.TestData,2:5,2,struct(),tc.TestData.table_4gfm);
tc.assertTrue(r.converged,r.failure_reason);
j=find(abs(r.t-0.04)<1e-12 & strcmp(r.sample_side,'right'),1);
tc.assertNotEmpty(j);
tc.verifyEqual(r.device_modes_history(:,j),{'sg';'GFM';'GFM';'GFM';'GFM'});
tc.verifyFalse(r.device_online_history(1,j));
tc.verifyEqual(r.device_current_magnitude(1,j),0,'AbsTol',0);
tc.verifyTrue(isnan(r.device_frequency_Hz(1,j)), ...
    'An offline SG rotor speed is not reported as connected-grid frequency.');
post=tc.TestData.scenario.case_data.dispatch_contract.post_trip.post_trip_Pg_MW;
for d=2:5
    slot=find(strcmpi(string(tc.TestData.dae.devices(d).input_names),'P_ref'));
    ug=tc.TestData.dae.u_offsets(d)+slot;
    tc.verifyEqual(r.u_history(ug,j),post.(tc.TestData.dae.devices(d).device_id)/ ...
        tc.TestData.scenario.case_data.mpc.baseMVA, ...
        'AbsTol',0,'The trip must atomically commit the CASE_DEFINED MW dispatch.');
end
expected=stability.ts_dynamic_state_indices(tc.TestData.dae,r.event_context_history{j});
tc.verifyEqual(r.active_state_history{j},expected,'AbsTol',0);
for d=2:5
    off=tc.TestData.dae.device_offsets(d);
    inactive=off+(14:20);
    tc.verifyEqual(r.x_traj(inactive,j:end),repmat(r.x_traj(inactive,j),1,size(r.x_traj,2)-j+1),'AbsTol',0);
end
end

function test_one_gfm_configuration_fails_closed_and_rolls_back(tc)
% IEEE14 single-GFM (n=1) is PHYSICALLY INFEASIBLE under the frozen
% SCR/equilibrium/SSSA gates: the real selector marks it NO_FEASIBLE_CANDIDATE,
% so the authenticated candidate is not ready_to_commit. The transaction must
% therefore fail closed with the validator's candidateNotReady failure ID,
% commit NO candidate, publish NO right-limit sample at sg_trip, and mutate NO
% hybrid-state metadata (atomic rollback). The core property is identical to a
% right-limit failure: the rejected transaction is not partially published.
r=event_run_with_table(tc.TestData,2,2,struct(),tc.TestData.table_1gfm);
tc.verifyFalse(r.converged);
tc.verifyEqual(r.failure_id,'stability:gfm_selection:candidateNotReady', ...
    'An infeasible single-GFM candidate must be rejected by the validator before the right-limit solve.');
trip=find(strcmp({r.event_log.type},'sg_trip'),1);
tc.assertNotEmpty(trip); tc.verifyFalse(r.event_log(trip).applied);
tc.verifyEqual(r.event_log(trip).right_kcl_norm,inf);
tc.verifyFalse(any(abs(r.t-0.04)<1e-12 & strcmp(r.sample_side,'right')));
tc.verifyEqual(r.device_modes_history(:,end),{'sg';'gfl';'gfl';'gfl';'gfl'}, ...
    'A rejected transaction must not mutate IBR modes.');
tc.verifySize(r.bus_voltage_magnitude,[14 numel(r.t)], ...
    'A failed transition must retain diagnostic voltage for accepted samples.');
tc.verifySize(r.device_P_MW,[5 numel(r.t)], ...
    'A failed transition must retain diagnostic device power for plotting.');
end

function test_missing_post_trip_dispatch_rolls_back_atomically(tc)
c=tc.TestData.scenario.case_data;
c.dispatch_contract.post_trip.post_trip_Pg_MW=rmfield( ...
    c.dispatch_contract.post_trip.post_trip_Pg_MW,'IBR8');
ev=event_spec(2:5,2);
sched=stability.ibr_event_schedule(c,tc.TestData.eq.devices,ev,0.10,0.01);
o=base_opt(tc.TestData.eq,0.10,0.01); o.ibr_event_schedule=sched;
o.selector_table=tc.TestData.table_4gfm;
[r,~]=stability.ts_simulate_ibr_hybrid(c,tc.TestData.eq.devices, ...
    tc.TestData.eq.x0,tc.TestData.eq.y0,o);
tc.verifyFalse(r.converged);
tc.verifyEqual(r.failure_id,'ts_simulate_ibr_hybrid:dispatch');
trip=find(strcmp({r.event_log.type},'sg_trip'),1);
tc.assertNotEmpty(trip); tc.verifyFalse(r.event_log(trip).applied);
tc.verifyFalse(any(abs(r.t-0.04)<1e-12 & strcmp(r.sample_side,'right')));
tc.verifyEqual(r.u_history(:,end),tc.TestData.eq.u_eq,'AbsTol',0, ...
    'A rejected dispatch transaction must not publish its candidate input.');
end

function test_reclose_guard_uses_phasor_angle_and_pu_slip(tc)
g=stability.synchronism_guard(exp(1i*0.05),exp(1i*0.04),99,5e-4,0, ...
    struct('dV_max',0.05,'df_max',0.001,'dtheta_max',10));
tc.verifyTrue(g.passes);
tc.verifyEqual(g.df,5e-4,'AbsTol',0);
tc.verifyEqual(g.dtheta,rad2deg(0.01),'AbsTol',1e-12);
bad=stability.synchronism_guard(1,exp(-1i*0.3),0,0,0, ...
    struct('dV_max',1,'df_max',1,'dtheta_max',10));
tc.verifyFalse(bad.passes);
end

function test_reclose_requires_dwell_and_preserves_sg_state(tc)
% This oracle ends at the first permitted close.  It falsifies the atomic
% right-limit/state-continuity contract; post-close trajectory stability is a
% separate physical gate and is never repaired here with looser numerics.
over=struct('synchronism_overrides',struct('dV_max',10,'df_max',10,'dtheta_max',180), ...
    'delays_overrides',struct('T_sg_min_off_s',0,'dwell_s',0,'timeout_s',0.04), ...
    'event_overrides',struct('sg_on',0.05),'t_end',0.05);
r=event_run_with_table(tc.TestData,2:5,2,over,tc.TestData.table_4gfm);
tc.assertTrue(r.converged,r.failure_reason);
tc.verifyEqual(r.reclose_status,'SUCCESS');
tc.verifyEqual(r.actual_reclose_time,0.05,'AbsTol',1e-12);
left=find(abs(r.t-0.05)<1e-12 & ~strcmp(r.sample_side,'right'),1,'last');
right=find(abs(r.t-0.05)<1e-12 & strcmp(r.sample_side,'right'),1,'last');
tc.assertNotEmpty(left); tc.assertNotEmpty(right);
tc.verifyEqual(r.x_traj(1:6,right),r.x_traj(1:6,left),'AbsTol',0, ...
    'Reclose changes the breaker context and algebraic right limit, not SG state.');
tc.verifyTrue(r.device_online_history(1,right));
tc.verifyEqual(r.device_modes_history(:,right),{'sg';'GFM';'GFM';'GFM';'GFM'});
tc.verifyEqual(r.u_history(:,right),r.u_history(:,left),'AbsTol',0, ...
    'Reclose must not step SG or IBR controller commands.');
expected=stability.ts_dynamic_state_indices(tc.TestData.dae,r.event_context_history{right});
tc.verifyEqual(r.active_state_history{right},expected,'AbsTol',0);
st=find(strcmp({r.status_log.stage},'sg_reclose'),1);
tc.assertNotEmpty(st);
tc.verifyEqual(r.status_log(st).n_sg_online,1);
tc.verifyEqual(r.status_log(st).gfm_indices,2:5);
% Phase-1 reference handback (F1/C1): reference_owner_indices points to the
% reclosed SG (index 1), gfm_reference_resource_indices is empty for that
% island, while selected_gfm_indices (the physical GFM set) is unchanged.
if isfield(r,'reference_owner_indices') && ~isempty(r.reference_owner_indices)
    tc.verifyEqual(r.reference_owner_indices,1,'AbsTol',0, ...
        'Phase 1 must return reference ownership to the reclosed SG.');
end
if isfield(r,'gfm_reference_resource_indices') && ~isempty(r.gfm_reference_resource_indices)
    % SG owns the island -> GFM reference entry is empty (NaN placeholder).
    tc.verifyTrue(isnan(r.gfm_reference_resource_indices(1)), ...
        'gfm_reference_resource_indices must be empty while SG owns reference.');
end
% Phase 2 remains pending at the exact close because the C1 participation
% handback has only just started. No immediate mode release is permitted.
if isfield(r,'reselection_status')
    tc.verifyEqual(r.reselection_status,'NO_FEASIBLE_SG_ON', ...
        'The same-timestamp legacy fixture must not release a GFM.');
end
if isfield(r,'actual_mode_reselection_time')
    tc.verifyTrue(isnan(r.actual_mode_reselection_time), ...
        'actual_mode_reselection_time must be NaN when no Phase-2 reselection occurs.');
end
end

function test_reclose_timeout_stays_offline(tc)
over=struct('synchronism_overrides',struct('dV_max',1e-12,'df_max',1e-12,'dtheta_max',1e-9), ...
    'delays_overrides',struct('T_sg_min_off_s',0,'dwell_s',0.01,'timeout_s',0.02));
r=event_run_with_table(tc.TestData,2:5,2,over,tc.TestData.table_4gfm);
tc.assertTrue(r.converged,r.failure_reason);
tc.verifyEqual(r.reclose_status,'SYNC_TIMEOUT');
tc.verifyTrue(isnan(r.actual_reclose_time));
tc.verifyFalse(r.device_online_history(1,end));
end

function test_schedule_validation_is_fail_closed(tc)
ev=event_spec(2:5,2); ev.fault_clear=ev.fault_on;
tc.verifyError(@() stability.ibr_event_schedule(tc.TestData.scenario.case_data, ...
    tc.TestData.eq.devices,ev,0.10,0.01),'stability:ibr_event_schedule:badOrdering');
end

function test_plots_preserve_legacy_and_add_resource_group_png(tc)
% The former test required exactly two plots. That contract became stale when
% the approved UI added SG- and IBR-separated angle/frequency/P/V figures.
% The independent oracle is the audited result mapping: one SG row and four
% IBR rows, each mapped by device_bus_ids to terminal-voltage rows.
r=event_run_with_table(tc.TestData,2:5,2,struct(),tc.TestData.table_4gfm); tc.assertTrue(r.converged,r.failure_reason);
out=fullfile(tempdir,'ibr_ts_plot_gate'); if ~isfolder(out),mkdir(out);end
p=stability.plot_ibr_ts_results(r,struct('output_dir',out,'prefix','gate','visible',false));
tc.verifyTrue(isfile(p.freq_plot)); tc.verifyTrue(isfile(p.power_plot));
group_files=[struct2cell(p.group_plots.sg);struct2cell(p.group_plots.ibr)];
tc.verifyEqual(numel(group_files),8);
available=group_files(~cellfun(@isempty,group_files));
tc.verifyTrue(all(cellfun(@isfile,available)));
if ~isfield(r,'device_angle_deg')
    tc.verifyEmpty(p.group_plots.sg.angle);
    tc.verifyEmpty(p.group_plots.ibr.angle);
end
tc.verifyGreaterThan(dir(p.freq_plot).bytes,1000); tc.verifyGreaterThan(dir(p.power_plot).bytes,1000);
tc.verifyTrue(any(isfinite(r.device_frequency_Hz(2,:))));
tc.verifyTrue(any(isfinite(r.device_current_limit_sys(2,:))));
src=fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))),'+stability','plot_ibr_ts_results.m'));
tc.verifyFalse(contains(src,'yline(1.5'));
tc.verifyFalse(contains(src,'row = tb'));
end

function test_fault_only_schedule_contains_no_sg_transaction(tc)
ev=event_spec(2:5,2); ev.event_profile='fault_only';
s=stability.ibr_event_schedule(tc.TestData.scenario.case_data, ...
    tc.TestData.eq.devices,ev,0.10,0.01);
tc.verifyEqual({s.events.type},{'fault_on','fault_clear'});
tc.verifyTrue(s.has_fault); tc.verifyFalse(s.has_sg_cycle);
tc.verifyTrue(isnan(s.sg_trip)); tc.verifyTrue(isnan(s.sg_on));
end

function test_sg_cycle_schedule_contains_no_fault_transaction(tc)
ev=event_spec(2:5,2); ev.event_profile='sg_cycle';
s=stability.ibr_event_schedule(tc.TestData.scenario.case_data, ...
    tc.TestData.eq.devices,ev,0.10,0.01);
tc.verifyEqual({s.events.type},{'sg_trip','sg_on'});
tc.verifyFalse(s.has_fault); tc.verifyTrue(s.has_sg_cycle);
tc.verifyTrue(isnan(s.fault_bus)); tc.verifyTrue(isnan(s.Zf));
end

function test_sg_cycle_without_manual_tuple_requests_automatic_switching(tc)
ev=event_spec(2:5,2);
ev.event_profile='sg_cycle';
ev.automatic_gfm_switching=true;
ev=rmfield(ev,{'selected_gfm_indices','reference_resource_index'});
s=stability.ibr_event_schedule(tc.TestData.scenario.case_data, ...
    tc.TestData.eq.devices,ev,0.10,0.01);
tc.verifyEqual(s.selection_request.mode,'automatic');
tc.verifyTrue(s.automatic_gfm_switching);
tc.verifyEmpty(s.audit.legacy_selected_gfm_indices);
tc.verifyEmpty(s.audit.legacy_reference_resource_index);
end

function test_fault_only_runtime_applies_only_fault_transactions(tc)
ev=event_spec(2:5,2); ev.event_profile='fault_only';
s=stability.ibr_event_schedule(tc.TestData.scenario.case_data, ...
    tc.TestData.eq.devices,ev,0.05,0.01);
o=base_opt(tc.TestData.eq,0.05,0.01); o.ibr_event_schedule=s;
[r,~]=stability.ts_simulate_ibr_hybrid(tc.TestData.scenario.case_data, ...
    tc.TestData.eq.devices,tc.TestData.eq.x0,tc.TestData.eq.y0,o);
tc.verifyTrue(r.converged,r.failure_reason);
tc.verifyEqual({r.event_log.type},{'fault_on','fault_clear'});
tc.verifyTrue(all([r.event_log.applied]));
tc.verifyFalse(any(strcmp({r.event_log.type},'sg_trip')));
end

function test_sg_cycle_runtime_applies_no_fault_transaction(tc)
ev=event_spec(2:5,2); ev.event_profile='sg_cycle';
s=stability.ibr_event_schedule(tc.TestData.scenario.case_data, ...
    tc.TestData.eq.devices,ev,0.10,0.01);
o=base_opt(tc.TestData.eq,0.10,0.01); o.ibr_event_schedule=s;
o.selector_table=tc.TestData.table_4gfm;
[r,~]=stability.ts_simulate_ibr_hybrid(tc.TestData.scenario.case_data, ...
    tc.TestData.eq.devices,tc.TestData.eq.x0,tc.TestData.eq.y0,o);
tc.verifyTrue(r.converged,r.failure_reason);
tc.verifyFalse(any(ismember({r.event_log.type},{'fault_on','fault_clear'})));
tc.verifyTrue(any(strcmp({r.event_log.type},'sg_trip')));
end

function test_missing_selector_table_fails_closed_with_canonical_id(tc)
% No table injected (event_run does NOT inject one): the automatic path must
% fail closed with the shared canonical failure ID
% stability:gfm_selection:missingTable, commit NO candidate, publish NO right
% sample at sg_trip, and mutate NO hybrid-state metadata.
r=event_run(tc.TestData,2:5,2,struct());
tc.verifyFalse(r.converged);
tc.verifyEqual(r.failure_id,'stability:gfm_selection:missingTable');
trip=find(strcmp({r.event_log.type},'sg_trip'),1);
tc.assertNotEmpty(trip); tc.verifyFalse(r.event_log(trip).applied);
tc.verifyEqual(r.event_log(trip).right_kcl_norm,inf);
tc.verifyFalse(any(abs(r.t-0.04)<1e-12 & strcmp(r.sample_side,'right')));
tc.verifyEqual(r.device_modes_history(:,end),{'sg';'gfl';'gfl';'gfl';'gfl'}, ...
    'A missing-table failure must not mutate IBR modes.');
end

function test_missing_selector_table_leaves_selector_fingerprint_empty(tc)
% On a missing-table failure, no candidate commit occurs and the result must
% not carry a selector_table_fingerprint (no table was authenticated).
r=event_run(tc.TestData,2:5,2,struct());
tc.verifyFalse(r.converged);
if isfield(r,'selector_table_fingerprint')
    tc.verifyEmpty(r.selector_table_fingerprint, ...
        'Missing-table failure must not publish a selector_table_fingerprint.');
end
end

function test_hybrid_runner_contains_no_duplicate_integrator(tc)
root=fileparts(fileparts(mfilename('fullpath')));
src=fileread(fullfile(root,'+stability','ts_simulate_ibr_hybrid.m'));
tc.verifyFalse(contains(src,'trapezoid_res'));
tc.verifyFalse(contains(src,'composite_newton'));
tc.verifyFalse(contains(src,'forward_fd'));
tc.verifyTrue(contains(src,'stability.ts_step_composite'));
for token={'fsolve','fmincon','lsqnonlin','pinv('}
    tc.verifyFalse(contains(lower(src),token{1}));
end
end

function [a,b]=no_event_pair(data,tend,dt)
o=base_opt(data.eq,tend,dt);
[a,~]=stability.ts_simulate_composite(data.scenario.case_data,data.eq.devices, ...
    data.eq.x0,data.eq.y0,o);
o.ibr_event_schedule=struct('enabled',false,'t_end',tend,'dt',dt,'events',[]);
[b,~]=stability.ts_simulate_ibr_hybrid(data.scenario.case_data,data.eq.devices, ...
    data.eq.x0,data.eq.y0,o);
end

function r=event_run(data,selected,ref,extra)
ev=event_spec(selected,ref);
if isfield(extra,'event_overrides')
    event_names=fieldnames(extra.event_overrides);
    for k=1:numel(event_names),ev.(event_names{k})=extra.event_overrides.(event_names{k});end
    extra=rmfield(extra,'event_overrides');
end
tend=0.10; if isfield(extra,'t_end'),tend=extra.t_end;end
sched=stability.ibr_event_schedule(data.scenario.case_data,data.eq.devices,ev,tend,0.01);
o=base_opt(data.eq,tend,0.01); o.ibr_event_schedule=sched;
names=fieldnames(extra); for k=1:numel(names),o.(names{k})=extra.(names{k});end
[r,~]=stability.ts_simulate_ibr_hybrid(data.scenario.case_data,data.eq.devices, ...
    data.eq.x0,data.eq.y0,o);
end

function r=event_run_with_table(data,selected,ref,extra,table)
% Authenticated-trip variant: injects the pinned authenticated selector_table
% so the manual_override tuple has an exact authenticated candidate to match.
% TABLE must be the pinned table matching (selected,ref) — see setupOnce.
ev=event_spec(selected,ref);
if isfield(extra,'event_overrides')
    event_names=fieldnames(extra.event_overrides);
    for k=1:numel(event_names),ev.(event_names{k})=extra.event_overrides.(event_names{k});end
    extra=rmfield(extra,'event_overrides');
end
tend=0.10; if isfield(extra,'t_end'),tend=extra.t_end;end
sched=stability.ibr_event_schedule(data.scenario.case_data,data.eq.devices,ev,tend,0.01);
o=base_opt(data.eq,tend,0.01); o.ibr_event_schedule=sched; o.selector_table=table;
names=fieldnames(extra); for k=1:numel(names),o.(names{k})=extra.(names{k});end
[r,~]=stability.ts_simulate_ibr_hybrid(data.scenario.case_data,data.eq.devices, ...
    data.eq.x0,data.eq.y0,o);
end

function ev=event_spec(selected,ref)
ev=struct('enabled',true,'fault_bus',4,'Zf',1i*0.1, ...
    'fault_on',0.02,'fault_clear',0.03,'sg_trip',0.04,'sg_on',0.06, ...
    'selected_gfm_indices',selected,'reference_resource_index',ref);
end

function o=base_opt(eq,tend,dt)
o=struct('t_end',tend,'dt',dt,'verbose',false,'load_model','cz_p_cz_q', ...
    'u_eq',eq.u_eq,'event_context',eq.equilibrium_context, ...
    'dynamic_state_indices',eq.dynamic_state_indices,'full_kcl',true);
end
